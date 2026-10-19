__runIntegration=function()
  local t,m=__integration,__mock
  local path="/flights-count.csv"
  local header="model_name,flight_count\n# api_ver=1\n"
  local old=header.."Fixture,7\nOther,20\n"
  local updated=header.."Fixture,8\nOther,20\n"
  local opts={Theme=1,TxBatt=1,HeliType=1,BattRsv=20,CountSrc=1,MinFlight=30,
              RxPackMin="6.60",RxPackMax="8.40",MotorSw=99}
  local function eq(name,actual,expected)
    assert(actual==expected,name..": expected "..tostring(expected)..", got "..tostring(actual))
    print("PASS|"..name)
  end
  local function writes()
    local count=0
    for _,call in ipairs(fs.calls) do
      if string.find(call,"^openw:") or string.find(call,"^rename:")
         or string.find(call,"^del:") then count=count+1 end
    end
    return count
  end
  local w
  local function callback(now,seconds)
    m.now=now; m.timer={start=0,value=seconds}; t.background(w)
  end
  -- Test-only driver: each phase runs in its own production callback.
  local function saveAttempt(now,seconds)
    for _=1,100 do
      callback(now,seconds)
      if not t.state.dirty or not t.state.saving or not t.state.saving.active then return end
    end
    error("save attempt did not finish")
  end
  local function saveAll(now,seconds)
    for _=1,100 do
      if not t.state.dirty then return end
      saveAttempt(now,seconds)
      if t.state.saving and not t.state.saving.active then return end
    end
    error("save generations did not finish")
  end
  local function create()
    w=t.create({x=0,y=0,w=800,h=480},opts)
    local steps=0
    while t.state.loading do
      steps=steps+1;assert(steps<40,"fixture history failed to finish")
      t.background(w)
    end
  end
  local function qualify()
    create(); callback(0,0); callback(10,30)
  end
  local function exhaust()
    qualify(); fs.faults["write:"..path..".tmp"]="nil"
    saveAttempt(20,30); saveAttempt(520,30); saveAttempt(1020,30); saveAttempt(1520,30)
    eq("exactly three attempts",t.state.attempts,3)
    eq("exhausted dirty count retained",t.count(),8)
    eq("exhausted error visible",t.A.flightSaveError,true)
    eq("exhausted original preserved",fs.files[path],old)
    fs.faults={}
  end
  fs.files={[path]=old}
  if __scenario=="first_install" then
    fs.files={}; create(); callback(0,0)
    eq("first install begins at zero",t.count(),0)
    eq("first install has no file warning",t.A.flightSaveError,false)
    eq("first install has no probe writes",writes(),0)
    callback(10,30)
    eq("first flight counted",t.count(),1)
    saveAll(11,30)
    eq("first flight creates history",fs.files[path],header.."Fixture,1\n")
    eq("first flight clears pending save",t.state.dirty,false)
    eq("first flight has no file warning",t.A.flightSaveError,false)
  elseif __scenario=="directory_unavailable" then
    fs.files={}; fs.faults["dir:/"]="nil"; create()
    eq("unavailable directory count unknown",t.count(),nil)
    eq("unavailable directory file warning",t.A.flightSaveError,true)
    callback(0,0); callback(10,30); callback(520,30)
    eq("unavailable directory never writes",writes(),0)
    eq("unavailable directory never creates history",fs.files[path],nil)
  elseif __scenario=="qualified" then
    qualify()
    eq("threshold increments count",t.count(),8)
    eq("threshold marks dirty",t.state.dirty,true)
    eq("threshold callback defers write",fs.files[path],old)
    saveAll(11,30)
    eq("later callbacks persist",fs.files[path],updated)
    eq("later callbacks clear dirty",t.state.dirty,false)
    eq("later callbacks preserve backup",fs.files[path..".bak"],old)
    eq("no second threshold increment",t.count(),8)
  elseif __scenario=="retry" then
    exhaust()
    opts.CountSrc=2; t.update(w,opts)
    local before=#fs.calls
    callback(2000,30)
    eq("FC selection preserves pending count",t.state.cache.Fixture,8)
    eq("exhausted retry budget prevents further IO in FC mode",#fs.calls,before)
    opts.CountSrc=1; t.update(w,opts)
    eq("local reload resets retry budget",t.state.attempts,0)
    saveAll(2010,30)
    eq("local reload retry persisted",fs.files[path],updated)
    eq("local reload no recount",t.count(),8)
    eq("local reload clears error",t.A.flightSaveError,false)
  elseif __scenario=="recreate" then
    exhaust(); create()
    eq("recreated duplicate waits for foreground ownership",w.kseInitialized,nil)
    eq("recreated duplicate retains exhausted retry state",t.state.attempts,3)
    eq("recreated duplicate preserves dirty cache",t.state.dirty,true)
    m.now=m.now+500
    t.refresh(w,nil,nil)
    eq("recreated foreground initializes after lease expires",w.kseInitialized,true)
    eq("recreate starts one resumed attempt",t.state.attempts,1)
    eq("recreate preserves qualified cache",t.state.cache.Fixture,8)
    saveAll(2030,30)
    eq("recreate persists",fs.files[path],updated)
    eq("recreate no recount",t.count(),8)
  elseif __scenario=="unreadable" then
    fs.faults["read:"..path]="empty"
    create()
    eq("unreadable count unavailable",t.count(),nil)
    eq("unreadable error visible",t.A.flightSaveError,true)
    callback(0,0); callback(10,30); callback(520,30)
    eq("unreadable count remains unavailable",t.count(),nil)
    eq("unreadable state not dirty",t.state.dirty,false)
    eq("unreadable history never writes",writes(),0)
    eq("unreadable source preserved",fs.files[path],old)
  elseif __scenario=="fc" then
    opts.CountSrc=2; create(); callback(0,0); callback(10,30); callback(520,30)
    eq("FC mode no count-file IO",#fs.calls,0)
    eq("FC mode cache never loaded",t.state.cache,nil)
    eq("FC mode source unchanged",fs.files[path],old)
  elseif __scenario=="fc_pending" then
    qualify(); opts.CountSrc=2; t.update(w,opts)
    eq("FC switch retains dirty real event",t.state.dirty,true)
    saveAll(20,30)
    eq("FC callbacks persist earlier local event",fs.files[path],updated)
    eq("FC callbacks clear dirty",t.state.dirty,false)
    callback(30,180)
    eq("FC callbacks do not recount local event",t.state.cache.Fixture,8)
    opts.CountSrc=1; t.update(w,opts); callback(40,180)
    eq("returning to local after save no recount",t.count(),8)
  elseif __scenario=="fc_pending_failure" then
    qualify(); opts.CountSrc=2; t.update(w,opts)
    fs.faults["write:"..path..".tmp"]="nil"; saveAttempt(20,30)
    eq("FC failed pending save retains real count",t.state.cache.Fixture,8)
    eq("FC failed pending save remains dirty",t.state.dirty,true)
    eq("FC failed pending save retains visible error state",t.A.flightSaveError,true)
    eq("FC failed pending save preserves file",fs.files[path],old)
    fs.faults={}; saveAll(520,30)
    eq("FC pending save retries successfully",fs.files[path],updated)
    eq("FC pending save success clears error",t.A.flightSaveError,false)
  elseif __scenario=="simulation" then
    qualify(); t.OPT.simTelemetry=true
    local before=#fs.calls
    callback(20,0); callback(520,30); callback(1020,90)
    eq("simulation defers all count-file IO",#fs.calls,before)
    eq("simulation retains earlier real dirty event",t.state.dirty,true)
    eq("simulation retains earlier real count",t.state.cache.Fixture,8)
    eq("simulation consumes no retry attempts",t.state.attempts,0)
    eq("simulation leaves confirmed file unchanged",fs.files[path],old)
    t.OPT.simTelemetry=false; saveAll(1030,90)
    eq("real mode resumes pending persistence",fs.files[path],updated)
    eq("real mode resumes without recount",t.count(),8)
    eq("real mode clears dirty",t.state.dirty,false)
  elseif __scenario=="model_change" then
    qualify()
    local cache=t.state.cache
    fs.faults["write:"..path..".tmp"]="nil"
    m.modelName="Other"; callback(20,0)
    eq("model change preserves cache identity",t.state.cache==cache,true)
    eq("model change retains dirty first count",t.state.cache.Fixture,8)
    eq("model change selects existing count",t.count(),20)
    callback(30,30)
    eq("new model qualifies independently",t.count(),21)
    eq("new model retains first dirty count",t.state.cache.Fixture,8)
    fs.faults={}; saveAll(520,30)
    eq("model change persists both counts",fs.files[path],header.."Fixture,8\nOther,21\n")
    eq("model change leaves no dirty data",t.state.dirty,false)
  else error("Unknown scenario "..tostring(__scenario)) end
  print("PASS|complete")
end
__runIntegration()
