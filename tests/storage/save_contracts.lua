-- Save generation/optimistic-file guards across the yielded phase boundaries.
do
  local function prepare(backupOnly)
    local values={["Model A"]=7,["Model B"]=20}
    for i=1,198 do values[string.format("Other%03d",i)]=i end
    local text=assert(Storage.serialize(values))
    local state=setup({[path..(backupOnly and ".bak" or "")]=text})
    assert(Storage.increment(state,"Model A",0))
    return state,text
  end
  local function at(state,phase)
    local job=state.saving
    if not job then return false end
    if phase=="collect" then return job.phase=="serialize" and not job.index end
    if phase=="format" then return job.phase=="serialize" and job.index and job.index>1 end
    return job.phase==phase
  end
  local function advance(state,phase)
    for _=1,100 do
      if at(state,phase) then return state.saving end
      Storage.service(state,0)
    end
    error("save phase not reached: "..phase)
  end
  local function rows(text)
    local state=Storage.new(path)
    -- Validate saved bytes through the ordinary bounded loader, not the
    -- in-memory generation that produced them.
    local saved=fs.files[path];fs.files[path]=text
    load(state);fs.files[path]=saved
    assert(state.cache,state.error)
    return state.cache
  end
  for _,phase in ipairs({"collect","format","guard","write","commit"}) do
    local state,original=prepare()
    local job=advance(state,phase)
    eq("one attempt across initial phases "..phase,state.attempts,1)
    local frozen=job.text
    assert(Storage.increment(state,"Model B",10))
    if phase=="collect" or phase=="format" then
      Storage.service(state,10)
      eq("changed unfinished generation restarts snapshot "..phase,state.saving~=job,true)
      eq("snapshot restart does not consume retry "..phase,state.attempts,1)
      eq("snapshot restart performs no writes "..phase,fs.files[path],original)
      eq("restarted snapshot commits "..phase,attempt(state,10),true)
      eq("restarted snapshot includes new count "..phase,rows(fs.files[path])["Model B"],21)
      eq("restarted snapshot leaves clean state "..phase,state.dirty,false)
    else
      eq("finished snapshot retains exact bytes "..phase,state.saving.text,frozen)
      eq("older immutable snapshot commits "..phase,attempt(state,10),true)
      eq("first commit is original snapshot "..phase,fs.files[path],frozen)
      eq("newer revision stays dirty "..phase,state.dirty,true)
      eq("first commit cannot clear newer count "..phase,state.cache["Model B"],21)
      eq("first commit confirms old base "..phase,state.baseText,frozen)
      eq("later job commits newer generation "..phase,attempt(state,10),true)
      eq("newer generation retains both flights "..phase,rows(fs.files[path])["Model A"],8)
      eq("newer generation saved second flight "..phase,rows(fs.files[path])["Model B"],21)
      eq("newer generation preserves previous snapshot "..phase,fs.files[path..".bak"],frozen)
      eq("newer generation leaves clean state "..phase,state.dirty,false)
    end
  end

  -- A count crossing is allowed between every save callback. Mutating the
  -- table's key set also must restart before next(values, oldKey) is used.
  local state,original=prepare()
  advance(state,"collect")
  state.cache["Other198"]=nil;state.cache.Replacement=99
  Storage.markDirty(state,0)
  eq("key-set mutation restarts safely",attempt(state,0),true)
  local parsed=rows(fs.files[path])
  eq("key-set snapshot contains replacement",parsed.Replacement,99)
  eq("key-set snapshot excludes removed key",parsed.Other198,nil)

  for _,phase in ipairs({"guard","write","commit"}) do
    state,original=prepare()
    advance(state,phase)
    local foreign=header.."Foreign,99\n"
    fs.files[path]=foreign
    eq("foreign main blocks yielded save "..phase,attempt(state,0),false)
    eq("foreign main remains untouched "..phase,fs.files[path],foreign)
    eq("foreign main cannot rotate backup "..phase,fs.files[path..".bak"],nil)
    eq("foreign main retains dirty cache "..phase,state.dirty,true)
    eq("foreign main reports conflict "..phase,state.error,"HISTORY CHANGED")

    state,original=prepare(true)
    advance(state,phase)
    fs.files[path..".bak"]=foreign
    eq("foreign recovery backup blocks save "..phase,attempt(state,0),false)
    eq("foreign recovery backup remains untouched "..phase,fs.files[path..".bak"],foreign)
    eq("foreign backup cannot create main "..phase,fs.files[path],nil)
    eq("foreign backup reports conflict "..phase,state.error,"BACKUP UNAVAILABLE")
  end
  for _,replacement in ipairs({"foreign temp",false}) do
    state,original=prepare();advance(state,"commit")
    fs.files[path..".tmp"]=replacement or nil
    eq("changed temp blocks promotion "..tostring(replacement),attempt(state,0),false)
    eq("changed temp retains main "..tostring(replacement),fs.files[path],original)
    eq("changed temp retains candidate evidence "..tostring(replacement),fs.files[path..".tmp"],replacement or nil)
    eq("changed temp cannot rotate backup "..tostring(replacement),fs.files[path..".bak"],nil)
    eq("changed temp reports conflict "..tostring(replacement),state.error,"TEMP CHANGED")
  end

  for _,failure in ipairs({"temporary","post-promotion"}) do
    state,original=prepare()
    local job=advance(state,"write")
    local snapshot=job.text
    if failure=="temporary" then fs.faults["write:"..path..".tmp"]="nil"
    else
      fs.faults["read:"..path]=function()
        if fs.files[path]==snapshot then return "empty" end
      end
    end
    eq("snapshot attempt fails "..failure,attempt(state,0),false)
    eq("failed attempt retains snapshot "..failure,state.saving.text,snapshot)
    eq("failed attempt becomes inactive "..failure,state.saving.active,false)
    assert(Storage.increment(state,"Model B",10))
    fs.faults={}
    local calls=#fs.calls
    eq("new flight cannot skip retry delay "..failure,attempt(state,499),false)
    eq("retry delay performs no IO "..failure,#fs.calls,calls)
    eq("retry confirms original snapshot "..failure,attempt(state,500),true)
    eq("retry does not mistake newer cache for foreign edit "..failure,fs.files[path],snapshot)
    eq("retry retains newer generation "..failure,state.dirty,true)
    eq("next job saves newer generation "..failure,attempt(state,500),true)
    parsed=rows(fs.files[path])
    eq("retry preserves first flight "..failure,parsed["Model A"],8)
    eq("retry preserves second flight "..failure,parsed["Model B"],21)
    eq("retry clears all pending generations "..failure,state.dirty,false)
    eq("retry clears save warning "..failure,state.error,nil)
  end

  state,original=prepare()
  local job=advance(state,"format")
  local index=job.index
  Storage.retry(state,0)
  eq("explicit retry retains active snapshot",state.saving==job,true)
  eq("explicit retry retains active format progress",job.index,index)
  eq("explicit retry does not reset active attempt",state.attempts,1)
  local steps=0
  while state.dirty do
    steps=steps+1;assert(steps<100,"bounded save did not finish")
    local previous=state.saving
    local count=previous and previous.keys and #previous.keys
    local before=previous and previous.index
    Storage.service(state,0)
    local after=state.saving
    if after==previous and after.phase=="serialize" then
      if count then eq("collect batch remains bounded "..steps,#after.keys-count<=12,true) end
      if before then eq("format batch remains bounded "..steps,after.index-before<=12,true) end
    end
  end
  eq("save finishes through multiple callbacks",steps>4,true)
end
print("PASS|complete")
