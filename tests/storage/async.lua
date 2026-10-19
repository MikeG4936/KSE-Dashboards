local function eq(name, actual, expected)
  assert(actual == expected, name .. ": expected " .. tostring(expected)
         .. ", got " .. tostring(actual))
  print("PASS|" .. name)
end
local path = "/flights-count.csv"
local header = "model_name,flight_count\n# api_ver=1\n"
local function history(first, second)
  local rows = {header}
  for i = 1, 178 do rows[#rows+1] = string.format("Extra%03d,1\n", i) end
  rows[#rows+1] = "Fixture," .. first .. "\nOther," .. second .. "\n"
  return table.concat(rows)
end
local original = history(7, 20)
fs.files = {[path]=original}
__mock.now = 1000
__mock.modelFile = "model-a.yml"
model.getInfo = function()
  return {name=__mock.modelName, filename=__mock.modelFile}
end
lvgl = {clear=function() end, label=function() end}

local first = dofile(dashboardDir .. "/" .. ownerVariant .. ".lua")
local second = (scenario == "handoff" or scenario == "save_handoff")
               and dofile(dashboardDir .. "/" .. contenderVariant .. ".lua") or first
local function options(counter)
  return {Theme=1, TxBatt=1, HeliType=1, BattRsv=20, CountSrc=counter or 1,
          MinFlight=30, RxPackMin="6.60", RxPackMax="8.40", MotorSw=99}
end
local function writes()
  local total = 0
  for _, call in ipairs(fs.calls) do
    if string.find(call, "^openw:") or string.find(call, "^rename:")
       or string.find(call, "^del:") then total = total + 1 end
  end
  return total
end
local function callback(api, widget, now, seconds, foreground)
  __mock.now = now
  __mock.timer = {start=0, value=seconds}
  if foreground then api.refresh(widget, nil, nil) else api.background(widget) end
end
-- This loop is in the fixture driver, never inside a production callback.
local function drain(api, widget, seconds)
  local state, steps = api.audit.state(), 0
  local job = state.loading
  while state.loading do
    assert(state.loading == job, "load job restarted between callbacks")
    assert(state.cache == nil, "partial cache escaped before EOF")
    steps = steps + 1
    assert(steps < 40, "history load did not finish")
    callback(api, widget, __mock.now + 10, seconds)
  end
  eq("load advanced through separate callbacks", steps > 1, true)
end
local function persisted(api, widget, expected, seconds)
  local state = api.audit.state()
  eq("completion makes qualified event dirty", state.dirty, true)
  eq("completion defers persistence", fs.files[path], original)
  local saveSteps=0
  while state.dirty do
    saveSteps=saveSteps+1;assert(saveSteps<100,"save phases did not finish")
    callback(api, widget, __mock.now + 1, seconds)
  end
  eq("later callbacks persist exact complete history", fs.files[path], expected)
  eq("successful save clears dirty state", state.dirty, false)
  eq("successful save retains original backup", fs.files[path .. ".bak"], original)
  callback(api, widget, __mock.now + 10, seconds)
  eq("unchanged expired timer does not recount", fs.files[path], expected)
end

if scenario == "expired" then __mock.timer = {start=0, value=90} end
local owner = first.create({x=0, y=0, w=800, h=480}, options())
local state = first.audit.state()
local job = state.loading
eq("creation starts deferred load", type(job), "table")
eq("creation does not publish zero count", first.audit.count(), nil)
eq("creation performs no filesystem work", #fs.calls, 0)

if scenario == "expired" then
  callback(first, owner, 1000, 90)
  eq("first expired sample leaves count unavailable while loading", first.audit.count(), nil)
  eq("first expired sample creates no pending event", state.pending, nil)
  drain(first, owner, 90)
  eq("expired timer loads saved count unchanged", first.audit.count(), 7)
  eq("expired timer never creates pending event", state.pending, nil)
  eq("expired timer leaves clean history", state.dirty, false)
  eq("expired timer does not write", writes(), 0)
  eq("expired timer preserves file", fs.files[path], original)
elseif scenario == "simulation" then
  callback(first, owner, 1000, 0)
  callback(first, owner, 1010, 30)
  eq("crossing while loading records one pending event", state.pending.Fixture, 1)
  eq("crossing does not publish a partial count", first.audit.count(), nil)
  local pending, entries, calls = state.pending, job.entries, #fs.calls
  local services = first.audit.metrics.rf
  first.audit.OPT.simTelemetry = true
  callback(first, owner, 1020, 0)
  callback(first, owner, 1030, 30, true)
  callback(first, owner, 1040, 0)
  eq("simulation preserves load identity", state.loading == job, true)
  eq("simulation does not advance parsing", job.entries, entries)
  eq("simulation performs no filesystem work", #fs.calls, calls)
  eq("simulation preserves pending event map", state.pending == pending, true)
  eq("simulated resets cannot add real events", pending.Fixture, 1)
  eq("simulation consumes no save attempts", state.attempts, 0)
  eq("storage pause does not suppress RF service callbacks", first.audit.metrics.rf - services, 3)
  first.audit.OPT.simTelemetry = false
  drain(first, owner, 30)
  eq("resume applies real event once", first.audit.count(), 8)
  eq("resume consumes pending event", state.pending, nil)
  persisted(first, owner, history(8, 20), 30)
elseif scenario == "counter_change" then
  callback(first, owner, 1000, 0)
  callback(first, owner, 1010, 30)
  eq("local event qualifies before counter switch", state.pending.Fixture, 1)
  local pending, entries, calls = state.pending, job.entries, #fs.calls
  first.update(owner, options(2))
  eq("counter switch retains active load job", state.loading == job, true)
  eq("counter switch does not advance parsing", job.entries, entries)
  eq("counter switch performs no filesystem work", #fs.calls, calls)
  eq("counter switch retains qualified event map", state.pending == pending, true)
  drain(first, owner, 90)
  eq("FC callbacks complete earlier local count", state.cache.Fixture, 8)
  eq("FC callbacks do not count their expired timer", state.pending, nil)
  persisted(first, owner, history(8, 20), 90)
  first.update(owner, options(1))
  drain(first, owner, 90)
  eq("return to local retains saved count", first.audit.count(), 8)
  eq("return to local cannot backfill expired timer", state.pending, nil)
  eq("return to local leaves clean history", state.dirty, false)
elseif scenario == "handoff" then
  callback(first, owner, 1000, 0)
  callback(first, owner, 1010, 30)
  eq("first aircraft qualifies during load", state.pending.Fixture, 1)
  local pending, entries, calls = state.pending, job.entries, #fs.calls
  __mock.modelName, __mock.modelFile = "Other", "model-b.yml"
  callback(first, owner, 1020, 0)
  eq("old filename callback cannot advance parsing", job.entries, entries)
  eq("old filename callback performs no filesystem work", #fs.calls, calls)
  local contender = second.create({x=0, y=0, w=800, h=480}, options())
  eq("new filename waits for foreground ownership", contender.kseInitialized, nil)
  eq("contender create performs no filesystem work", #fs.calls, calls)
  callback(second, contender, 1020, 0, true)
  eq("new filename takes foreground ownership immediately", _G.__KSE_WIDGET_OWNER_V1.widget == contender, true)
  eq("cross-variant owner receives same storage object", second.audit.state() == state, true)
  eq("cross-variant owner continues same load job", state.loading == job, true)
  eq("cross-variant owner retains pending event map", state.pending == pending, true)
  eq("new owner still cannot expose partial history", second.audit.count(), nil)
  callback(second, contender, 1030, 30)
  eq("second aircraft qualifies independently while loading", pending.Other, 1)
  eq("second aircraft preserves first aircraft event", pending.Fixture, 1)
  entries, calls = job.entries, #fs.calls
  local services = first.audit.metrics.rf + second.audit.metrics.rf
  first.update(owner, options(2))
  callback(first, owner, 1040, 0)
  callback(first, owner, 1040, 0, true)
  eq("stale update and callbacks cannot advance parsing", job.entries, entries)
  eq("stale update and callbacks perform no filesystem work", #fs.calls, calls)
  eq("stale callbacks perform no RF service work", first.audit.metrics.rf + second.audit.metrics.rf, services)
  eq("stale callbacks cannot reclaim owner", _G.__KSE_WIDGET_OWNER_V1.widget == contender, true)
  -- Reusing filename A creates a new model generation. Its original widget
  -- must stay stale even though the filename once again matches.
  __mock.modelName, __mock.modelFile = "Fixture", "model-a.yml"
  local replacement = first.create({x=0, y=0, w=800, h=480}, options())
  callback(first, replacement, 1050, 30, true)
  eq("filename reuse creates a later model generation", replacement.kseModelEpoch > owner.kseModelEpoch, true)
  eq("returning filename continues same storage object", first.audit.state() == state, true)
  eq("returning filename continues same load job", state.loading == job, true)
  eq("returning filename retains both pending events", state.pending == pending, true)
  eq("returning expired timer cannot add another event", pending.Fixture, 1)
  entries, calls = job.entries, #fs.calls
  first.update(owner, options(2))
  callback(first, owner, 1060, 0)
  callback(first, owner, 1060, 0, true)
  callback(second, contender, 1060, 0)
  callback(second, contender, 1060, 0, true)
  eq("earlier model generations cannot advance parsing", job.entries, entries)
  eq("earlier model generations perform no filesystem work", #fs.calls, calls)
  eq("filename reuse does not revive original widget", _G.__KSE_WIDGET_OWNER_V1.widget == replacement, true)
  drain(first, replacement, 30)
  eq("completed load applies first aircraft event once", state.cache.Fixture, 8)
  eq("completed load applies second aircraft event once", state.cache.Other, 21)
  eq("completed load displays current aircraft count", first.audit.count(), 8)
  eq("completed load consumes both pending events", state.pending, nil)
  persisted(first, replacement, history(8, 21), 30)
elseif scenario == "save_simulation" or scenario == "save_counter_change"
    or scenario == "save_handoff" then
  callback(first,owner,1000,0)
  drain(first,owner,0)
  callback(first,owner,__mock.now+10,30)
  eq("flight before save pause qualifies once",state.cache.Fixture,8)
  local wanted=scenario=="save_simulation" and "write" or "serialize"
  for _=1,100 do
    job=state.saving
    if job and job.phase==wanted and (wanted~="serialize" or (job.index and job.index>1)) then break end
    callback(first,owner,__mock.now+10,30)
  end
  job=assert(state.saving,"save job not started")
  eq("save boundary reached before mutation",job.phase,wanted)
  local phase,index,text,attempts,calls=job.phase,job.index,job.text,state.attempts,#fs.calls
  if scenario=="save_simulation" then
    local services=first.audit.metrics.rf
    first.audit.OPT.simTelemetry=true
    callback(first,owner,__mock.now+10,0)
    callback(first,owner,__mock.now+10,30,true)
    callback(first,owner,__mock.now+10,90)
    eq("simulation retains save job",state.saving==job,true)
    eq("simulation retains save phase",job.phase,phase)
    eq("simulation retains immutable snapshot",job.text,text)
    eq("simulation consumes no extra attempt",state.attempts,attempts)
    eq("simulation performs no save IO",#fs.calls,calls)
    eq("simulation pause still services RF",first.audit.metrics.rf-services,3)
    eq("simulated timer reset cannot count another flight",state.cache.Fixture,8)
    first.audit.OPT.simTelemetry=false
    persisted(first,owner,history(8,20),30)
  elseif scenario=="save_counter_change" then
    first.update(owner,options(2))
    eq("counter change retains save job",state.saving==job,true)
    eq("counter change retains save progress",job.index,index)
    eq("counter change does not reset save attempt",state.attempts,attempts)
    eq("counter change performs no save IO",#fs.calls,calls)
    persisted(first,owner,history(8,20),90)
    eq("FC callbacks retain local flight count",state.cache.Fixture,8)
  else
    __mock.modelName,__mock.modelFile="Other","model-b.yml"
    local contender=second.create({x=0,y=0,w=800,h=480},options())
    callback(second,contender,__mock.now+10,0,true)
    eq("save handoff retains shared state",second.audit.state()==state,true)
    eq("save handoff retains active job",state.saving==job,true)
    eq("save handoff keeps one active attempt",state.attempts,attempts)
    eq("save handoff advances existing phase",job.index>index,true)
    local progress=job.index
    calls=#fs.calls
    callback(first,owner,__mock.now+10,0)
    callback(first,owner,__mock.now+10,0,true)
    eq("old owner cannot advance save phase",job.index,progress)
    eq("old owner cannot perform save IO",#fs.calls,calls)
    callback(second,contender,__mock.now+10,30)
    eq("new owner qualifies its own flight",state.cache.Other,21)
    eq("new owner preserves first aircraft count",state.cache.Fixture,8)
    persisted(second,contender,history(8,21),30)
  end
else
  error("Unknown scenario " .. tostring(scenario))
end
print("PASS|complete")
