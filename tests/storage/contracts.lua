-- Unit semantics drain bounded phases explicitly; cpu_budget measures each
-- real lifecycle callback separately and prevents an unbounded caller loop.
local function load(state)
  Storage.beginLoad(state)
  local steps=0
  while state.loading do
    steps=steps+1;assert(steps<2000,"history load did not finish")
    Storage.stepLoad(state,0)
  end
  return state.cache
end
local function eq(name,actual,expected)
  assert(actual==expected,name..": expected "..tostring(expected)..", got "..tostring(actual))
  print("PASS|"..name)
end
local path="/flights-count.csv"
local header="model_name,flight_count\n# api_ver=1\n"
local old=header.."Model A,7\nModel B,20\n"
local updated=header.."Model A,8\nModel B,20\n"
local function setup(files)
  fs.files=files or {}; fs.directories={["/"]=true}; fs.faults={}; fs.calls={}; fs.online=true
  local s=Storage.new(path); load(s); return s
end
local function dirty(s)
  s.cache["Model A"]=8; Storage.markDirty(s,0)
end
local function writesMain()
  for _,call in ipairs(fs.calls) do if call=="openw:"..path then return true end end
  return false
end
local s=setup({[path]=old})
eq("load all models",s.cache["Model B"],20)
dirty(s); eq("normal save",Storage.service(s,0),true)
eq("normal main contents",fs.files[path],updated)
eq("retain backup",fs.files[path..".bak"],old)
eq("never direct overwrite",writesMain(),false)
eq("save clears dirty",s.dirty,false)

s=setup(); eq("native root stat unavailable",fstat("/"),nil)
eq("new readable filesystem",s.writable,true)
eq("new filesystem has no error",s.error,nil)
local directoryOpens=0
for _,call in ipairs(fs.calls) do
  if call=="dir:/" then directoryOpens=directoryOpens+1 end
  eq("first initialization does not enumerate "..call,string.find(call,"^iterate:")==nil,true)
  eq("first initialization does not create probe file "..call,string.find(call,"^openw:")==nil,true)
end
eq("new filesystem checks root once",directoryOpens,1)
s.cache["Model A"]=1; Storage.markDirty(s,0)
eq("new history save",Storage.service(s,0),true)
eq("new history serialized",fs.files[path],header.."Model A,1\n")
fs.online=false; s=Storage.new(path); load(s)
eq("missing SD read only",s.writable,false)
eq("missing SD visible",s.error,"STORAGE UNAVAILABLE")

for _,fault in ipairs({"nil","throw",true,7,{}}) do
  setup(); fs.faults["dir:/"]=fault
  s=Storage.new(path); load(s)
  eq("unavailable directory read only "..tostring(fault),s.writable,false)
  eq("unavailable directory visible "..tostring(fault),s.error,"STORAGE UNAVAILABLE")
  eq("unavailable directory no cache "..tostring(fault),s.cache,nil)
end
setup(); fs.directories={}
s=Storage.new(path); load(s)
eq("missing parent read only",s.writable,false)
eq("missing parent visible",s.error,"STORAGE UNAVAILABLE")
local dirApi=dir
dir=false -- An unavailable/non-callable API must fail closed.
s=setup(); eq("missing directory API read only",s.writable,false)
eq("missing directory API visible",s.error,"STORAGE UNAVAILABLE")
dir=dirApi

for _,suffix in ipairs({"",".bak",".tmp"}) do
  setup({[path..suffix]=old}); fs.calls={}; fs.faults["dir:/"]="throw"
  s=Storage.new(path); load(s)
  eq("existing history independent of root open "..suffix,s.cache["Model A"],7)
  for _,call in ipairs(fs.calls) do
    eq("existing history avoids directory open "..suffix..call,string.find(call,"^dir:")==nil,true)
  end
end

for _,fault in ipairs({"nil","short","silent-short","throw"}) do
  s=setup({[path]=old}); dirty(s); fs.faults["write:"..path..".tmp"]=fault
  eq("failed write "..fault,Storage.service(s,0),false)
  eq("failed write preserves main "..fault,fs.files[path],old)
  eq("failed write stays dirty "..fault,s.dirty,true)
end
for _,fault in ipairs({"empty","short","throw"}) do
  s=setup({[path]=old}); dirty(s); fs.faults["read:"..path..".tmp"]=fault
  eq("readback failure "..fault,Storage.service(s,0),false)
  eq("readback preserves main "..fault,fs.files[path],old)
end
s=setup({[path]=old}); dirty(s); fs.faults["close:"..path..".tmp"]="lost"
eq("silent close loss detected",Storage.service(s,0),false)
eq("silent close preserves main",fs.files[path],old)

for _,result in ipairs({1,true,false}) do
  s=setup({[path]=old}); dirty(s); fs.faults["rename:"..path]=result
  eq("FRESULT strict "..tostring(result),Storage.service(s,0),false)
  eq("rename error preserves main "..tostring(result),fs.files[path],old)
end
s=setup({[path]=old,[path..".bak"]=header.."Model A,6\n"}); dirty(s)
fs.faults["del:"..path..".bak"]=1
eq("backup deletion failure",Storage.service(s,0),false)
eq("backup deletion preserves main",fs.files[path],old)
eq("backup deletion preserves backup",fs.files[path..".bak"],header.."Model A,6\n")
s=setup({[path]=old}); dirty(s); fs.faults["rename:"..path..".tmp"]=1
eq("promotion failure",Storage.service(s,0),false)
eq("promotion retains confirmed backup",fs.files[path..".bak"],old)
eq("promotion retains candidate",fs.files[path..".tmp"],updated)
fs.faults={}
eq("promotion retry delayed",Storage.service(s,499),false)
eq("promotion retry succeeds",Storage.service(s,500),true)
eq("promotion retry no double increment",fs.files[path],updated)

s=setup({[path..".bak"]=old})
eq("backup startup source",s.source,"backup")
eq("backup startup all models",s.cache["Model B"],20)
dirty(s); eq("backup recovery saves",Storage.service(s,0),true)
eq("backup recovery preserves old copy",fs.files[path..".bak"],old)
s=setup({[path..".bak"]=old,[path..".tmp"]=updated})
eq("both artifacts prefer confirmed backup",s.cache["Model A"],7)
s=setup({[path..".tmp"]=updated})
eq("temp salvage available",s.cache["Model A"],8)
eq("temp alone read only",s.writable,false)
eq("temp alone warning",s.error,"TEMP UNCONFIRMED")
eq("temp alone cannot dirty",Storage.markDirty(s,0),false)

local invalids={
  {"empty",""}, {"bad count",header.."Model A,nope\n"},
  {"negative",header.."Model A,-1\n"}, {"fraction",header.."Model A,1.5\n"},
  {"extra column",header.."Model A,7,extra\n"},
  {"duplicate",header.."Model A,7\nModel A,8\n"},
  {"large",header..string.rep("# padding\n",4000)},
}
local exact=header.."#"..string.rep("x",Storage.maxBytes-#header-2).."\n"
s=setup({[path]=exact})
eq("exact byte limit accepted",s.writable,true)
local boundary={header}
for i=1,200 do boundary[#boundary+1]="Model "..i..",1\n" end
s=setup({[path]=table.concat(boundary)})
eq("200 models accepted",s.writable,true)
s.cache["new model"]=1; Storage.markDirty(s,0)
eq("201st model cannot rewrite history",Storage.service(s,0),false)
eq("201st model preserves source",fs.files[path],table.concat(boundary))
local many={header}
for i=1,201 do many[#many+1]="Model "..i..",1\n" end
invalids[#invalids+1]={"201 entries",table.concat(many)}
for _,case in ipairs(invalids) do
  s=setup({[path]=case[2],[path..".bak"]=old})
  eq("invalid source read only "..case[1],s.writable,false)
  eq("invalid source cannot save "..case[1],Storage.save(s),false)
  eq("invalid source preserved "..case[1],fs.files[path],case[2])
end
for _,fault in ipairs({"empty","short","throw"}) do
  fs.files={[path]=old}; fs.faults={["read:"..path]=fault}
  s=Storage.new(path); load(s)
  eq("main read failure blocks writes "..fault,s.writable,false)
  eq("main read failure no partial cache "..fault,s.cache,nil)
end
s=setup({[path]=old}); dirty(s); fs.files[path]=header.."Model A,99\n"
eq("foreign modification blocks save",Storage.service(s,0),false)
eq("foreign modification preserved",fs.files[path],header.."Model A,99\n")
for _,replacement in ipairs({"",header.."Model A,broken\n",header.."Model A,7\n"}) do
  s=setup({[path]=old}); dirty(s); fs.files[path]=replacement
  eq("changed main blocked "..#replacement,Storage.service(s,0),false)
  eq("changed main intact "..#replacement,fs.files[path],replacement)
  eq("changed main no temporary write "..#replacement,fs.files[path..".tmp"],nil)
end
for _,replacement in ipairs({header.."Model A,broken\n",header.."Model A,99\n"}) do
  s=setup({[path..".bak"]=old}); dirty(s); fs.files[path..".bak"]=replacement
  eq("changed recovery backup blocked "..#replacement,Storage.service(s,0),false)
  eq("changed recovery backup intact "..#replacement,fs.files[path..".bak"],replacement)
  eq("changed recovery backup no main write "..#replacement,fs.files[path],nil)
end

-- Lua integers and floats are both 32-bit in the pinned EdgeTX core. A float
-- equal to 2147483648 can compare equal to converted MAX_INT; %d then throws.
local maxCountText=header.."Model A,2147483647\n"
s=setup({[path]=maxCountText})
eq("MAX_INT history writable",s.writable,true)
eq("MAX_INT parsed exactly",s.cache["Model A"],2147483647)
eq("MAX_INT serialized exactly",Storage.serialize(s.cache),maxCountText)
s.cache["Model B"]=1; Storage.markDirty(s,0)
eq("MAX_INT survives unrelated save",Storage.service(s,0),true)
eq("MAX_INT saved exact decimal",fs.files[path],maxCountText.."Model B,1\n")
s=setup({[path]=header.."Model A,2147483648\n"})
eq("MAX_INT plus one is read only",s.writable,false)
eq("MAX_INT plus one no invalid cache",s.cache,nil)
local serializedOk,serialized=pcall(Storage.serialize,{["Model A"]=tonumber("2147483648")})
eq("overflow serialization does not throw",serializedOk,true)
eq("overflow serialization rejected",serialized,nil)
serializedOk,serialized=pcall(Storage.serialize,{["Model A"]=1.5})
eq("fraction serialization does not throw",serializedOk,true)
eq("fraction serialization rejected",serialized,nil)
local normalComments=header.."# ordinary history note\nFixture,7\n"
s=setup({[path]=normalComments})
eq("api version and ordinary comments remain valid",s.writable,true)
eq("comments preserve model counts",s.cache.Fixture,7)
local ambiguous=header.."#My helicopter,17\nFixture,7\n"
s=setup({[path]=ambiguous})
eq("comment-shaped model quarantined",s.writable,false)
eq("comment-shaped model error explicit",s.error,"AMBIGUOUS MODEL NAME")
eq("comment-shaped model no partial cache",s.cache,nil)
eq("comment-shaped model cannot save",Storage.save(s),false)
eq("comment-shaped model source preserved",fs.files[path],ambiguous)
serializedOk,serialized=pcall(Storage.serialize,{["#My helicopter"]=17})
eq("comment-shaped key serialize does not throw",serializedOk,true)
eq("comment-shaped key serialize rejected",serialized,nil)
s=setup({[path]=old}); s.cache["#My helicopter"]=17; Storage.markDirty(s,0)
eq("new comment-shaped key cannot rewrite history",Storage.service(s,0),false)
eq("new comment-shaped key preserves source",fs.files[path],old)
eq("new comment-shaped key remains dirty",s.dirty,true)
s=setup({[path]=old}); dirty(s); fs.online=false
for i=0,8 do Storage.service(s,i*500) end
eq("retry bound",s.attempts,3)
eq("retry exhaustion visible",s.error~=nil,true)
eq("retry exhaustion retains count",s.cache["Model A"],8)
fs.online=true
eq("retry exhaustion does not restart automatically",Storage.service(s,5000),false)
Storage.retry(s,5000)
eq("explicit retry succeeds",Storage.service(s,5000),true)
eq("explicit retry no recount",fs.files[path],updated)

-- Read confirmation can fail after the rename already installed correct bytes.
s=setup({[path]=old}); dirty(s)
fs.faults["read:"..path]=function()
  if fs.files[path]==updated then return "empty" end
end
eq("post-promotion read error",Storage.service(s,0),false)
eq("post-promotion keeps backup",fs.files[path..".bak"],old)
fs.faults={}
eq("post-promotion retry recognizes committed data",Storage.service(s,500),true)
eq("post-promotion retry no recount",fs.files[path],updated)

-- Public filesystem names can live behind EdgeTX's ROM-style __index lookup.
local originalMeta=getmetatable(_G)
local originalIndex=originalMeta.__index
local api={fstat=fstat,rename=rename,del=del,dir=dir}
rawset(_G,"fstat",nil); rawset(_G,"rename",nil); rawset(_G,"del",nil); rawset(_G,"dir",nil)
setmetatable(_G,{__index=function(_,key) return api[key] or originalIndex[key] end})
s=setup({[path]=old}); dirty(s)
eq("ROM filesystem lookup",Storage.service(s,0),true)
eq("ROM filesystem saved contents",fs.files[path],updated)
s=setup(); eq("ROM directory lookup initializes empty history",s.writable,true)
setmetatable(_G,originalMeta)
fstat=api.fstat; rename=api.rename; del=api.del; dir=api.dir
-- Incremental loading owns a private snapshot and uses one candidate/batch
-- per call. Re-selection and model handoff must not restart its progress.
do
  local rows={header}
  for i=1,200 do rows[#rows+1]="Model "..i..",1\n" end
  local text=table.concat(rows)
  setup({[path]=text});fs.calls={}
  local state=Storage.new(path)
  Storage.beginLoad(state)
  eq("begin load performs no filesystem work",#fs.calls,0)
  local job=state.loading
  Storage.stepLoad(state,0)
  eq("partial parse has no public cache",state.cache,nil)
  eq("partial parse is not writable",state.writable,false)
  eq("partial parse is not a failure",state.error,nil)
  eq("one batch bounds model rows",job.entries<=Storage.batchLines,true)
  local entries=job.entries
  Storage.beginLoad(state)
  eq("begin load reuses pending job",state.loading==job,true)
  eq("begin load retains progress",job.entries,entries)
  Storage.increment(state,"Model 1",10)
  Storage.increment(state,"Model 2",10)
  eq("pending flight remains private",state.cache,nil)
  eq("pending flight cannot save incomplete history",state.dirty,false)
  load(state)
  eq("load publishes all rows together",state.cache["Model 200"],1)
  eq("first pending model applied once",state.cache["Model 1"],2)
  eq("second pending model applied once",state.cache["Model 2"],2)
  eq("applied pending events cleared",state.pending,nil)
  eq("pending events dirty the complete cache",state.dirty,true)
  eq("load completion does not write",fs.files[path],text)
  local cache=state.cache
  Storage.beginLoad(state)
  eq("begin load cannot replace dirty cache",state.cache==cache,true)
  eq("begin load cannot restart dirty history",state.loading,nil)
  eq("later callback persists pending counts",Storage.service(state,10),true)

  local broken=text.."bad row\n"
  setup({[path]=broken,[path..".bak"]=text});fs.calls={}
  state=Storage.new(path);Storage.beginLoad(state)
  Storage.increment(state,"Model 1",0)
  while state.loading.stage==1 do Storage.stepLoad(state,0) end
  eq("late main failure yields before backup",state.loading.stage,2)
  local backupRead=false
  for _,call in ipairs(fs.calls) do
    if call=="openr:"..path..".bak" then backupRead=true end
  end
  eq("late failure does not spend another candidate budget",backupRead,false)
  eq("invalid main prefix never published",state.cache,nil)
  load(state)
  eq("backup count not modified by pending event",state.cache["Model 1"],1)
  eq("quarantined event retained for explicit recovery",state.pending["Model 1"],1)
  eq("pending event cannot authorize backup overwrite",state.writable,false)
  eq("quarantined event cannot dirty",state.dirty,false)
  eq("quarantine save rejected",Storage.service(state,0),false)
  fs.files[path]=text
  load(state)
  eq("explicit valid reload applies retained event",state.cache["Model 1"],2)
  eq("explicit recovery marks pending count dirty",state.dirty,true)
  eq("explicit recovery clears applied pending event",state.pending,nil)

  -- A foreign edit while parsing must not become the validated base text.
  setup({[path]=text});state=Storage.new(path);Storage.beginLoad(state)
  Storage.stepLoad(state,0)
  local foreign=text.."Foreign,3\n";fs.files[path]=foreign
  load(state);Storage.increment(state,"Model 1",0)
  eq("snapshot retains originally validated bytes",state.baseText,text)
  eq("foreign edit during parsing blocks save",Storage.service(state,0),false)
  eq("foreign edit remains untouched",fs.files[path],foreign)
  eq("foreign edit error retained",state.error,"HISTORY CHANGED")

  setup({[path]=header.."Model 1,2147483647\n"})
  state=Storage.new(path);Storage.beginLoad(state);Storage.increment(state,"Model 1",0)
  load(state)
  eq("pending event cannot overflow count",state.cache["Model 1"],2147483647)
  eq("overflow retains unavailable event",state.pending["Model 1"],1)
  eq("overflow warning visible",state.error,"COUNT UNAVAILABLE")
  eq("overflow does not dirty unchanged count",state.dirty,false)

  setup({[path]=header.."Model 1,2147483646\n"})
  state=Storage.new(path);Storage.beginLoad(state)
  Storage.increment(state,"Model 1",0);Storage.increment(state,"Model 1",0)
  load(state)
  eq("pending flights fill representable count",state.cache["Model 1"],2147483647)
  eq("only excess pending flight remains",state.pending["Model 1"],1)
  eq("representable pending flight is dirty",state.dirty,true)
  eq("representable count persists",Storage.service(state,0),true)
  eq("persisting maximum keeps excess warning",state.error,"COUNT UNAVAILABLE")
  eq("excess never wraps stored count",fs.files[path],header.."Model 1,2147483647\n")

  -- A row count limit alone would miss comment-heavy legal histories.
  setup({[path]=header..string.rep("#\n",16000).."Model 1,1\n"})
  state=Storage.new(path);Storage.beginLoad(state)
  local steps,peak=0,0
  while state.loading do
    local cost=measure(Storage.stepLoad,state,0)
    peak=math.max(peak,cost);steps=steps+1
    assert(steps<1000,"comment-heavy history did not finish")
  end
  eq("comments consume bounded batches",steps>600,true)
  eq("comment-heavy callback fits storage margin",peak<5000,true)
  eq("comment-heavy valid history is preserved",state.cache["Model 1"],1)
end
print("PASS|complete")
