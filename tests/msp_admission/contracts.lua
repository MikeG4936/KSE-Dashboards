-- Actual pinned queue/API modules; common packet transport and radio are mocks.
local env
getTime=function() return env.now end
LCD_W=800; LCD_H=480
lcd={RGB=function(r,g,b) return r*65536+g*256+b end}
model={getInfo=function() return {name=env.model,filename=env.filename} end,
       getTimer=function() return {start=0,value=0} end}
getFieldInfo=function(name)
  env.fieldReads[name]=(env.fieldReads[name] or 0)+1
  local id=env.ids[name]
  return id and {id=id,name=name} or nil
end
getSourceValue=function(id)
  env.sourceReads[id]=(env.sourceReads[id] or 0)+1
  local item=env.samples[id]
  if item and item.throw then error("source failure") end
  if item then return item.value,item.current,item.fresh end
  return nil,false,false
end
getValue=function(id)
  local item=env.samples[env.ids[id] or id]
  return item and item.value or 0
end
getRSSI=function() return env.rssi end
io={open=function() return nil end,close=function() end}
bit32={bor=function(a,b)return a|b end,band=function(a,b)return a&b end,
       lshift=function(a,b)return a<<b end,rshift=function(a,b)return a>>b end}

local function eq(label,actual,expected)
  assert(actual==expected,label..": expected "..tostring(expected)..", got "..tostring(actual))
  print("PASS|"..label)
end
local function setup(mode,counter)
  env={now=1000,model="Admission fixture",filename="fixture.yml",rssi=100,
       ids={ARM=77,Gov=78,Hspd=79},samples={
         [77]={value=0,current=true,fresh=true},
         [78]={value=0,current=true,fresh=true},
         [79]={value=0,current=true,fresh=true}},sent={},replies={},
       hostCalls=0,txCalls=0,clearCalls=0,fieldReads={},sourceReads={}}
  rf2={apiVersion=12.09,rfToolApiVersion=1.0,clock=function() return env.now/100 end,
       units={seconds=1,meters=2},
       registerWidget=function() end,call=function(fn,...) return fn(...) end,
       widget={state="disarmed",background=function() env.hostCalls=env.hostCalls+1 end}}
  rf2.executeScript=function(name)
    assert(name=="MSP/common")
    return function(cmd,payload)
      env.sent[#env.sent+1]={command=cmd,payload=payload,time=env.now,
                             armed=env.samples[env.ids.ARM].value}
    end,
    function() env.txCalls=env.txCalls+1 end,
    function()
      local reply=table.remove(env.replies,1)
      if reply then return reply.command,reply.payload,reply.error end
    end,
    function() env.clearCalls=env.clearCalls+1 end
  end
  rf2.mspQueue=dofile(upstreamPath.."/mspQueue.lua")
  rf2.mspHelper=dofile(upstreamPath.."/mspHelper.lua")
  local status=dofile(upstreamPath.."/mspStatus.lua")
  local stats=dofile(upstreamPath.."/mspFlightStats.lua")
  rf2.useApi=function(name)
    if name=="mspStatus" then return status end
    if name=="mspFlightStats" then return stats end
  end
  local api=dofile(dashboardPath).audit
  assert(api.profiles.admission and api.profiles.admission.disarmed,"MspAdmission.disarmed missing")
  api.OPT.heliType=mode or 1; api.OPT.flightCounter=counter or 1
  local w={profileRfState="disarmed",profileRfProviderRef=rf2,
    profileRfToolRegistered=true,profileWasConnected=true,
    profileInitialReadRequested=true,profileCapacityReadRequested=true,
    profileInitialReadFinished=true,profileCapacityReadFinished=true,
    profileInitialReadValid=true,profileActive=1,profileAutoShown=true,
    profileConnectReadyAt=0,armingStatusNextAt=1000000}
  api.profiles.flightSourceChanged(w)
  return api,w,rf2.mspQueue
end
local function disarmed(api,w)
  return api.profiles.admission.disarmed(w)
end
local function service(api,w,now,ui)
  env.now=now or env.now+10
  api.profiles.service(w,ui==true,nil,nil)
end
local function arm(w)
  env.samples[env.ids.ARM].value=1
  rf2.widget.state="armed"; w.profileRfState="armed"
end
local function reply(command,payload)
  env.replies[#env.replies+1]={command=command,payload=payload or {}}
end
local function queueStep(queue,command,payload)
  if command then reply(command,payload) end
  env.now=env.now+10; queue:processQueue()
end
local function commands()
  local out={}
  for _,sent in ipairs(env.sent) do out[#out+1]=tostring(sent.command) end
  return table.concat(out,",")
end

-- All four admission paths must independently deny unsafe calls.
local gates={
  {"status",function(a,w) return a.profiles.status(w) end},
  {"stats",function(a,w) return a.profiles.stats(w) end},
  {"snapshot",function(a,w) return a.profiles.snapshot(w) end},
  {"selection",function(a,w) return a.profiles.begin(w,"select",2) end},
  {"capacity",function(a,w) return a.profiles.begin(w,"activeCapacity",2) end},
}
for _,gate in ipairs(gates) do
  local a,w,q=setup(1,2); arm(w)
  eq(gate[1].." armed denial",gate[2](a,w),false)
  eq(gate[1].." no queued request",#q.messageQueue,0)
  a,w,q=setup(1,2); assert(disarmed(a,w))
  eq(gate[1].." disarmed admission",gate[2](a,w),true)
  eq(gate[1].." disarmed queued count",#q.messageQueue,gate[1]=="snapshot" and 2 or 1)
end

local a,w,q=setup()
eq("fresh disarmed ARM admits immediately",a.profiles.admission.disarmed(w),true)
eq("admission has no artificial time advance",env.now,1000)
eq("picker uses same disarmed state",a.profiles.unsafe(w),false)

local invalids={
 {"missing ARM",function() env.ids.ARM=nil end},
 {"noncurrent ARM",function() env.samples[77].current=false end},
 {"stale ARM",function() env.samples[77].fresh=false end},
 {"unknown ARM freshness",function() env.samples[77].fresh=nil end},
 {"fractional ARM",function() env.samples[77].value=0.5 end},
 {"negative ARM",function() env.samples[77].value=-2 end},
 {"overflow ARM",function() env.samples[77].value=256 end},
 {"radio link lost",function() env.rssi=0 end},
 {"host armed contradiction",function() rf2.widget.state="armed" end},
 {"widget armed contradiction",function(_,w) w.profileRfState="armed" end},
 {"host initializing",function() rf2.widget.state="initializing" end},
 {"widget initializing",function(_,w) w.profileRfState="initializing" end},
 {"source exception",function() env.samples[77].throw=true end},
 {"reused ARM ID",function()
    env.ids.ARM=80; env.samples[80]={value=1,current=true,fresh=true}
  end},
}
for _,case in ipairs(invalids) do
  a,w,q=setup(); assert(disarmed(a,w)); case[2](a,w)
  eq(case[1].." denies",a.profiles.admission.disarmed(w),false)
  eq(case[1].." blocks selection",a.profiles.begin(w,"select",2),false)
  eq(case[1].." leaves queue empty",#q.messageQueue,0)
end
a,w,q=setup(); env.samples[77].value=254
 eq("other ARM bits do not change disarmed bit",disarmed(a,w),true)

local unrelatedSensors={
 {"missing Gov and Hspd",function() env.ids.Gov=nil; env.ids.Hspd=nil end},
 {"stale Gov and Hspd",function()
    env.samples[78].current=false; env.samples[78].fresh=false
    env.samples[79].current=false; env.samples[79].fresh=false
  end},
 {"running Gov and Hspd",function() env.samples[78].value=4; env.samples[79].value=2500 end},
 {"invalid Gov and Hspd",function() env.samples[78].value=99.5; env.samples[79].value=-1 end},
 {"throwing Gov and Hspd",function() env.samples[78].throw=true; env.samples[79].throw=true end},
}
for _,case in ipairs(unrelatedSensors) do
  for _,gate in ipairs(gates) do
    a,w,q=setup(1,2); case[2]()
    local label=case[1].." "..gate[1]
    eq(label.." disarmed admission",gate[2](a,w),true)
    eq(label.." expected queued count",#q.messageQueue,gate[1]=="snapshot" and 2 or 1)
    eq(label.." no governor lookup",env.fieldReads.Gov or 0,0)
    eq(label.." no headspeed lookup",env.fieldReads.Hspd or 0,0)
    eq(label.." no governor value read",env.sourceReads[78] or 0,0)
    eq(label.." no headspeed value read",env.sourceReads[79] or 0,0)
    a,w,q=setup(1,2); case[2](); env.samples[77].value=1
    eq(label.." armed ARM denies despite disarmed host",gate[2](a,w),false)
    eq(label.." armed ARM leaves queue empty",#q.messageQueue,0)
  end
end

for mode=1,2 do
  for counter=1,2 do
    for _,ui in ipairs({false,true}) do
      a,w,q=setup(mode,counter); arm(w); w.armingStatusNextAt=nil
      for tick=1000,4000,10 do service(a,w,tick,ui) end
      local label="armed mode"..mode.." counter"..counter.." ui"..tostring(ui)
      eq(label.." sends no new KSE request",#env.sent,0)
      eq(label.." leaves queue empty",#q.messageQueue,0)
      eq(label.." continues upstream host service",env.hostCalls>0,true)
    end
  end
end

a,w,q=setup(); arm(w); w.armingStatusNextAt=nil
service(a,w,1000,false)
env.samples[77].value=0; rf2.widget.state="disarmed"; w.profileRfState="disarmed"
for tick=1010,1200,10 do service(a,w,tick,false) end
eq("disarmed recovery resumes diagnostics",env.sent[1] and env.sent[1].command,101)

a,w,q=setup(); w.profileCapacitiesReady=true; w.profileCapacitiesComplete=true
w.profileCapacities={0,1500,0,0,0,0}; arm(w)
for tick=1000,1200,10 do service(a,w,tick,false) end
eq("single configured profile cannot auto-select armed",#env.sent,0)
eq("single configured profile no armed pending selection",w.profileSelectionRequested,nil)
env.samples[77].value=0; rf2.widget.state="disarmed"; w.profileRfState="disarmed"
for tick=1210,1300,10 do service(a,w,tick,false) end
eq("single configured profile resumes selection after disarming",commands(),"176")
eq("single configured profile selects intended slot",q.currentMessage.payload[1],1)

-- Removing a KSE pending entry must not clear RF Tool's active or foreign work.
a,w,q=setup(); assert(disarmed(a,w)); assert(a.profiles.begin(w,"select",2))
local owned=w.profileOperation.messages[1]
local foreign={command=999,payload={},processReply=function() end}
local methods={processQueue=q.processQueue,add=q.add,clear=q.clear,handleReply=q.handleReply}
local pendingTable=q.messageQueue
q:add(foreign)
local callback=owned.processReply
w.armingBlockerText="OLD BLOCKER"; w.armingDisableFlags=123; arm(w)
service(a,w,1050,false)
eq("pending owned message never sent",commands(),"999")
eq("foreign active identity preserved",q.currentMessage==foreign,true)
eq("pending queue table identity preserved",q.messageQueue==pendingTable,true)
eq("foreign retry policy untouched",q.maxRetries,-1)
eq("transport buffers never cleared",env.clearCalls,0)
for key,fn in pairs(methods) do assert(q[key]==fn,"upstream method changed: "..key) end
eq("queue methods preserved",true,true)
callback(owned,{})
eq("late invalidated callback cannot recreate operation",w.profileOperation,nil)
eq("old arming banner cleared",w.armingBlockerText,nil)

-- The accepted policy leaves already-current RF Tool retry ownership intact.
a,w,q=setup(); assert(disarmed(a,w)); assert(a.profiles.begin(w,"select",2))
owned=w.profileOperation.messages[1]; queueStep(q)
eq("disarmed first send",commands(),"176")
arm(w); service(a,w,1200,false)
eq("active owned message remains RF Tool current",q.currentMessage==owned,true)
eq("active carryover retry observed",commands(),"176,176")
eq("active carryover maxRetries unchanged",q.maxRetries,-1)
eq("active carryover operation invalidated",w.profileOperation,nil)
reply(176,{}); service(a,w,1210,false)
eq("active late ACK cannot queue verify",#q.messageQueue,0)
eq("active late ACK cannot restore operation",w.profileOperation,nil)
print("LIMIT|active RF Tool message may retry while armed; no transport interception")

-- ACK callbacks only stage successors; admission happens on a later KSE pass.
a,w,q=setup(); assert(disarmed(a,w)); assert(a.profiles.begin(w,"select",2))
eq("selection admits only set",#q.messageQueue,1)
queueStep(q,176,{})
eq("set ACK does not directly queue verify",#q.messageQueue,0)
arm(w); service(a,w,1060,false)
eq("arming after set ACK prevents verification",commands(),"176")

a,w,q=setup(); assert(disarmed(a,w)); assert(a.profiles.begin(w,"select",2))
queueStep(q,176,{}); service(a,w,1060,false)
eq("later disarmed pass admits verification",(q.currentMessage or q.messageQueue[1]).command,175)
queueStep(q,175,{1})
eq("verify ACK does not directly queue save",#q.messageQueue,0)
arm(w); service(a,w,1080,false)
eq("arming after verify prevents EEPROM save",commands(),"176,175")

a,w,q=setup(); assert(disarmed(a,w)); assert(a.profiles.begin(w,"select",2))
queueStep(q,176,{}); service(a,w,1060,false); queueStep(q,175,{1})
service(a,w,1080,false)
eq("later disarmed pass admits EEPROM save",(q.currentMessage or q.messageQueue[1]).command,250)
queueStep(q,250,{})
eq("full disarmed command sequence",commands(),"176,175,250")
eq("full disarmed selected profile",w.profileActive,2)
eq("full disarmed completes operation",w.profileOperation,nil)

local identities={
 {"same-name different model filename",function() env.filename="other-model.yml" end},
 {"same-provider replacement queue",function()
    rf2.mspQueue=dofile(upstreamPath.."/mspQueue.lua")
  end},
 {"same-provider replacement host widget",function()
    rf2.widget={state="disarmed",background=function() env.hostCalls=env.hostCalls+1 end}
  end},
 {"replacement provider",function()
    local replacement={}; for key,value in pairs(rf2) do replacement[key]=value end
    rf2=replacement
  end},
 {"helicopter type change",function(a) a.OPT.heliType=2 end},
}
for _,case in ipairs(identities) do
  a,w,q=setup(); assert(disarmed(a,w)); assert(a.profiles.begin(w,"select",2))
  queueStep(q,176,{})
  local previousSuccessor=w.profileOperation.nextMessage
  case[2](a,w); service(a,w,1060,false)
  eq(case[1].." does not admit verify",commands(),"176")
  eq(case[1].." invalidates operation",w.profileOperation,nil)
  local staleQueued=false
  for _,message in ipairs(q.messageQueue) do
    if message==previousSuccessor then staleQueued=true end
  end
  eq(case[1].." original queue has no old successor",staleQueued,false)
end

a,w,q=setup(); assert(disarmed(a,w)); assert(a.profiles.begin(w,"select",2))
owned=w.profileOperation.messages[1]
arm(w)
eq("observed unsafe state invalidates disarmed epoch",a.profiles.admission.disarmed(w),false)
env.samples[77].value=0; rf2.widget.state="disarmed"; w.profileRfState="disarmed"
eq("disarmed can recover before callback",disarmed(a,w),true)
owned.processReply(owned,{})
eq("old epoch callback cannot stage verification",w.profileOperation.nextMessage,nil)
service(a,w,1090,false)
eq("old epoch operation discarded before RF service",w.profileOperation,nil)
eq("old epoch pending set never sent",#env.sent,0)

a,w,q=setup(); assert(disarmed(a,w)); assert(a.profiles.begin(w,"select",2))
owned=w.profileOperation.messages[1]; queueStep(q)
arm(w); queueStep(q,176,{})
eq("armed ACK alone cannot stage successor",w.profileOperation.nextMessage,nil)
env.samples[77].value=0; rf2.widget.state="disarmed"; w.profileRfState="disarmed"
eq("disarmed recovers after callback-only observation",disarmed(a,w),true)
owned.processReply(owned,{})
eq("duplicate ACK after recovery cannot revive old epoch",w.profileOperation.nextMessage,nil)
service(a,w,env.now+10,false)
eq("callback-observed loss discards prior operation",w.profileOperation,nil)
eq("callback-observed loss prevents later verify send",commands(),"176")

a,w,q=setup(); assert(disarmed(a,w)); assert(a.profiles.begin(w,"select",2))
owned=w.profileOperation.messages[1]; a.profiles.reset(w)
eq("reset prunes owned pending",#q.messageQueue,0)
owned.processReply(owned,{})
eq("reset callback cannot restore operation",w.profileOperation,nil)
eq("reset retains upstream retry policy",q.maxRetries,-1)

a,w,q=setup(2,2); assert(disarmed(a,w)); assert(a.profiles.stats(w))
owned=w.profileOperation.messages[1]
eq("flight stats retains upstream default retry delay",owned.retryDelay,nil)
service(a,w,1199,false)
eq("Nitro before deadline stays busy",w.profileBusy,true)
service(a,w,1200,false)
eq("Nitro operation deadline clears busy",w.profileBusy,false)
eq("Nitro operation deadline clears pending",a.FC.pending,false)
eq("Nitro operation deadline releases operation",w.profileOperation,nil)
eq("Nitro deadline leaves active RF Tool request untouched",q.currentMessage==owned,true)
reply(14,{7,0,0,0,0,0,0,0,0,0,0,0,15}); service(a,w,1310,false)
eq("Nitro late reply clears upstream current naturally",q.currentMessage,nil)
eq("Nitro late reply cannot restore operation",w.profileOperation,nil)
a,w,q=setup(); assert(disarmed(a,w)); assert(a.profiles.status(w))
eq("status retains upstream default retry delay",w.armingStatusOperation.messages[1].retryDelay,nil)

-- Scoped instruction counts include this mock host, not an actual RF Tool/LVGL
-- callback. They guard the isolated controller against the project 15k budget.
if type(measure)=="function" then
  a,w,q=setup(); arm(w); w.armingStatusNextAt=nil
  local count=measure(a.profiles.service,w,false,nil,nil)
  eq("armed controller below 15000 mock instructions",count<15000,true)
  print("RESOURCE|armed-controller|"..count.."|RF host and LVGL mocked")
  a,w,q=setup(); assert(disarmed(a,w)); w.armingStatusNextAt=nil
  count=measure(a.profiles.service,w,false,nil,nil)
  eq("disarmed controller below 15000 mock instructions",count<15000,true)
  print("RESOURCE|disarmed-controller|"..count.."|RF host and LVGL mocked")
  a,w,q=setup(); assert(disarmed(a,w)); assert(a.profiles.begin(w,"select",2))
  queueStep(q,176,{}); env.now=1060
  count=measure(a.profiles.service,w,false,nil,nil)
  eq("select continuation below 15000 mock instructions",count<15000,true)
  print("RESOURCE|select-continuation|"..count.."|RF host and LVGL mocked")
else
  print("LIMIT|instruction measure hook unavailable; resource scenarios skipped")
end
print("PASS|complete")
