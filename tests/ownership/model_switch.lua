-- Saved-model lifecycles recreate widgets; display-name edits do not.
local function eq(name,actual,expected)
  assert(actual==expected,name..": expected "..tostring(expected)..", got "..tostring(actual))
  print("PASS|"..name)
end
local path="/flights-count.csv"
local header="model_name,flight_count\n# api_ver=1\n"
local zone={x=0,y=0,w=800,h=480}
local function options(reserve)
  return {Theme=1,TxBatt=1,HeliType=1,BattRsv=reserve,CountSrc=1,MinFlight=30,
          RxPackMin="6.60",RxPackMax="8.40",MotorSw=99}
end
local menu,proxy,clears,labels,lastLabel
model.getInfo=function()
  if __mock.infoThrows then error("model information unavailable") end
  return {name=__mock.modelName,filename=__mock.modelFile}
end
local function setup(filename)
  _G.__KSE_WIDGET_OWNER_V1=nil
  __mock.now=1000; __mock.timer={start=0,value=0}
  __mock.modelName="Fixture"; __mock.modelFile=filename; __mock.infoThrows=false
  __mock.values.ARM={id=77,value=0}; __mock.values[77]={value=0}
  fs.files={[path]=header.."Fixture,7\nOther,20\n"}; fs.calls={}; fs.faults={}
  getRSSI=function() return 100 end
  menu=nil; proxy=nil; clears=0; labels=0; lastLabel=nil
  lvgl={menu=function(spec) menu=spec end,
        clear=function() clears=clears+1 end,
        label=function(spec) labels=labels+1; lastLabel=spec.text end}
  rf2={apiVersion=12.09,rfToolApiVersion=1.0,
       registerWidget=function(widget) proxy=widget end,
       widget={state="disarmed",background=function() end}}
  rf2.mspQueue={messageQueue={},maxRetries=-1,
    add=function(self,message) self.messageQueue[#self.messageQueue+1]=message end,
    isProcessed=function(self) return not self.currentMessage and #self.messageQueue==0 end}
  local first=dofile(dashboardDir.."/"..ownerVariant..".lua")
  local second=sameModule and first or dofile(dashboardDir.."/"..contenderVariant..".lua")
  return first,second
end
local function tick(api,widget,now,seconds,foreground)
  __mock.now=now; __mock.timer={start=0,value=seconds or 0}
  if foreground then api.refresh(widget,nil,nil) else api.background(widget) end
end
local function metrics(api)
  local m=api.audit.metrics
  return m.rf+m.build+m.draw
end

local first,second=setup("model-a.yml")
local a,b=first.audit,second.audit
local old=first.create(zone,options(20))
tick(first,old,1010,0)
tick(first,old,1020,30)
eq("A qualifies count before saved-model switch",a.count(),8)
eq("A qualified count is still dirty",fs.files[path],header.."Fixture,7\nOther,20\n")
old.profileRfState="disarmed"; old.profileActive=1
old.profileCapacitiesReady=true; old.profileCapacities={1000,2000,3000,0,0,0}
eq("A opens real native picker",a.profiles.picker(old),true)
local stalePicker=menu.set
eq("A starts real profile operation",a.profiles.begin(old,"select",2),true)
local oldOperation=old.profileOperation
local oldMessage=oldOperation.messages[1]
local staleReply,staleError=oldMessage.processReply,oldMessage.errorHandler
-- A foreign transport transaction can coexist with KSE's pending request.
local activeTransport={command=71}
rf2.mspQueue.currentMessage=activeTransport
local foreign={command=42}; rf2.mspQueue:add(foreign)
eq("A registers provider state proxy",a.owner.register(rf2),true)
local originalProxy=proxy
local lease=_G.__KSE_WIDGET_OWNER_V1
local seen=lease.seen
__mock.modelName="Other"; __mock.modelFile="model-b.yml"; __mock.now=1030
local oldRfState=old.profileRfState
originalProxy:onStateChanged("armed")
eq("provider event cannot update A before B is created",old.profileRfState,oldRfState)
staleReply()
eq("old ACK cannot continue before B is created",oldOperation.nextMessage,nil)
local fresh=second.create(zone,options(35))
local waiting=first.create(zone,options(40))
eq("B create defers ownership until foreground",lease.widget==old,true)
eq("B create stays lightweight",fresh.kseInitialized,nil)
eq("first model observation retires old operation",old.profileOperation,nil)
eq("first model observation preserves active transport",rf2.mspQueue.currentMessage==activeTransport,true)
eq("first model observation removes pending owned work",#rf2.mspQueue.messageQueue,1)
eq("first model observation preserves foreign work",rf2.mspQueue.messageQueue[1]==foreign,true)
local beforeFirst,beforeSecond=metrics(first),metrics(second)
local calls=#fs.calls
local beforeClears,beforeLabels=clears,labels
originalProxy:onStateChanged("armed")
eq("provider event cannot update A after filename changes",old.profileRfState,oldRfState)
first.update(old,options(49))
tick(first,old,1031,0)
tick(first,old,1032,0,true)
eq("old A callbacks cannot renew lease before B foreground",lease.seen,seen)
eq("old A callbacks leave active options intact",a.OPT.reservePct,20)
eq("old A callbacks cannot perform shared work",metrics(first)+metrics(second),beforeFirst+beforeSecond)
eq("old A callbacks cannot perform file IO",#fs.calls,calls)
eq("old A refresh cannot clear screen before B foreground",clears,beforeClears)
eq("old A refresh cannot draw warning before B foreground",labels,beforeLabels)
eq("old A cannot admit MSP before B foreground",a.profiles.begin(old,"select",3),false)
stalePicker(2); staleReply()
eq("old picker cannot select after filename changes",old.profileSelectionRequested,nil)
eq("old ACK cannot continue after filename changes",oldOperation.nextMessage,nil)
tick(second,fresh,1033,0,true)
eq("B first foreground takes ownership immediately",lease.widget==fresh,true)
eq("B immediate foreground initializes",fresh.kseInitialized,true)
eq("B foreground applies saved options",b.OPT.reservePct,35)
eq("B foreground reads independent saved count",b.count(),20)
eq("model switch saves dirty A history",fs.files[path],header.."Fixture,8\nOther,20\n")
eq("model switch retires old A operation",old.profileOperation,nil)
eq("model switch preserves foreign queue entry",#rf2.mspQueue.messageQueue,1)
eq("foreign queue object remains identical",rf2.mspQueue.messageQueue[1]==foreign,true)
eq("B never draws duplicate warning",fresh.kseBlockedDrawn,nil)
beforeClears,beforeLabels=clears,labels
tick(first,waiting,1034,0,true)
eq("second B contender cannot reuse model-switch shortcut",lease.widget==fresh,true)
eq("genuine B duplicate clears its screen for warning",clears,beforeClears+1)
eq("genuine B duplicate draws warning label",labels,beforeLabels+1)
eq("genuine B duplicate explains active ownership",
   string.find(lastLabel,"Another KSE dashboard is active.",1,true)~=nil,true)
originalProxy:onStateChanged("disarmed")
eq("active provider proxy reaches B",fresh.profileRfState,"disarmed")
rf2.mspQueue.messageQueue={}
rf2.mspQueue.currentMessage=nil -- The upstream transport finishes its own request.
eq("B can admit safe MSP immediately",b.profiles.begin(fresh,"select",3),true)
local newOperation=fresh.profileOperation
local selection=fresh.profileSelectionRequested
seen=lease.seen; calls=#fs.calls
beforeFirst,beforeSecond=metrics(first),metrics(second)
beforeClears,beforeLabels=clears,labels
stalePicker(2); staleReply(); staleError()
first.update(old,options(48))
tick(first,old,1040,0); tick(first,old,1041,0,true)
eq("late A callbacks preserve B lease",lease.seen,seen)
eq("late A callbacks cannot reclaim B",lease.widget==fresh,true)
eq("late A callbacks preserve B options",b.OPT.reservePct,35)
eq("late A callbacks preserve B operation",fresh.profileOperation==newOperation,true)
eq("late A picker leaves B selection unchanged",fresh.profileSelectionRequested,selection)
eq("late A callbacks do no IO",#fs.calls,calls)
eq("late A callbacks do no shared work",metrics(first)+metrics(second),beforeFirst+beforeSecond)
eq("late A refresh cannot clear B screen",clears,beforeClears)
eq("late A refresh cannot draw warning over B",labels,beforeLabels)
eq("late A MSP request remains blocked",a.profiles.begin(old,"select",2),false)

-- A second B widget still obeys the ordinary five-second foreground lease.
__mock.now=1050
local duplicate=first.create(zone,options(44))
tick(first,duplicate,1051,0,true)
eq("same-model B duplicate cannot steal immediate owner",lease.widget==fresh,true)
tick(second,fresh,1100,0)
local recreation=first.create(zone,options(45))
tick(first,recreation,1599,0,true)
eq("same-model recreation waits through tick 499",lease.widget==fresh,true)
tick(first,recreation,1600,0)
eq("same-model recreation background cannot take over at expiry",lease.widget==fresh,true)
tick(first,recreation,1600,0,true)
eq("same-model recreation foreground claims at tick 500",lease.widget==recreation,true)
tick(first,duplicate,1601,0,true)
eq("other same-model contender cannot steal winning lease",lease.widget==recreation,true)

-- On A->B->A, old A must stay obsolete even though its filename matches again.
__mock.modelName="Fixture"; __mock.modelFile="model-a.yml"; __mock.now=1610
local returned=second.create(zone,options(25))
seen=lease.seen; calls=#fs.calls
beforeClears,beforeLabels=clears,labels
tick(first,old,1611,0,true)
eq("old A session cannot claim when filename returns",lease.widget==recreation,true)
eq("old A session does not renew B lease",lease.seen,seen)
eq("old A session cannot reload dirty history",#fs.calls,calls)
eq("old A session cannot clear screen when filename returns",clears,beforeClears)
eq("old A session cannot warn when filename returns",labels,beforeLabels)
tick(second,returned,1612,0,true)
eq("new A session claims immediately",lease.widget==returned,true)
eq("new A session preserves original dirty count",b.count(),8)
eq("new A session applies its own options",b.OPT.reservePct,25)
returned.profileRfState="disarmed"
eq("new A session admits fresh operation",b.profiles.begin(returned,"select",3),true)
local returnedOperation=returned.profileOperation
stalePicker(2); staleReply(); staleError()
eq("old A ACK cannot replace returned A operation",returned.profileOperation==returnedOperation,true)
eq("old A ACK cannot stage returned A operation",returnedOperation.nextMessage,nil)
eq("old A picker remains invalid after returning",returned.profileSelectionRequested,nil)
beforeClears,beforeLabels=clears,labels
tick(first,old,2300,0,true)
eq("obsolete A session cannot claim even after lease expires",lease.widget==returned,true)
eq("obsolete A session cannot clear new A screen after expiry",clears,beforeClears)
eq("obsolete A session cannot warn over new A after expiry",labels,beforeLabels)

-- Display labels are mutable; they must not be treated as saved-model identity.
first,second=setup("same-file.yml")
old=first.create(zone,options(20)); lease=_G.__KSE_WIDGET_OWNER_V1
__mock.modelName="Renamed display label"; __mock.now=1010
fresh=second.create(zone,options(30))
tick(second,fresh,1011,0,true)
eq("display-name edit does not bypass lease",lease.widget==old,true)
tick(first,old,1020,0)
eq("display-name edit permits existing owner to renew",lease.seen,1020)
tick(second,fresh,1519,0,true)
eq("display-name edit preserves 499-tick exclusion",lease.widget==old,true)
tick(second,fresh,1520,0,true)
eq("display-name edit allows normal expired takeover",lease.widget==fresh,true)

-- Missing or invalid filename cannot establish a trustworthy model switch.
local invalid={false,"",42,{}}
for index,value in ipairs(invalid) do
  first,second=setup(value)
  old=first.create(zone,options(20)); lease=_G.__KSE_WIDGET_OWNER_V1
  __mock.modelName="Other"; __mock.modelFile=value; __mock.now=1010
  fresh=second.create(zone,options(30))
  tick(second,fresh,1011,0,true)
  eq("invalid filename "..index.." cannot fast transfer",lease.widget==old,true)
  tick(second,fresh,1499,0,true)
  eq("invalid filename "..index.." waits 499 ticks",lease.widget==old,true)
  tick(second,fresh,1500,0,true)
  eq("invalid filename "..index.." retains expired takeover",lease.widget==fresh,true)
end
first,second=setup(nil)
old=first.create(zone,options(20)); lease=_G.__KSE_WIDGET_OWNER_V1
__mock.modelName="Other"; __mock.modelFile="known-b.yml"; __mock.now=1010
fresh=second.create(zone,options(30))
tick(second,fresh,1011,0,true)
eq("missing previous filename cannot fast transfer",lease.widget==old,true)
tick(second,fresh,1500,0,true)
eq("missing previous filename retains expired takeover",lease.widget==fresh,true)

first,second=setup(nil)
old=first.create(zone,options(20)); lease=_G.__KSE_WIDGET_OWNER_V1
__mock.modelName="Other"; __mock.now=1010
fresh=second.create(zone,options(30))
tick(second,fresh,1499,0,true)
eq("missing filename throughout retains 499-tick exclusion",lease.widget==old,true)
tick(second,fresh,1500,0,true)
eq("missing filename throughout permits expired takeover",lease.widget==fresh,true)

first,second=setup("known-a.yml")
old=first.create(zone,options(20)); lease=_G.__KSE_WIDGET_OWNER_V1
__mock.modelFile=nil
tick(first,old,1010,0)
eq("transient missing filename cannot renew known owner",lease.seen,1000)
__mock.modelFile="known-b.yml"; __mock.now=1020
fresh=second.create(zone,options(30))
tick(second,fresh,1021,0,true)
eq("same display label with changed filename transfers immediately",lease.widget==fresh,true)

-- Separately exercise a real KSE request already consumed by upstream transport.
first,second=setup("active-a.yml")
old=first.create(zone,options(20)); old.profileRfState="disarmed"
eq("active transport case starts real operation",first.audit.profiles.begin(old,"select",2),true)
oldOperation=old.profileOperation
oldMessage=table.remove(rf2.mspQueue.messageQueue,1)
rf2.mspQueue.currentMessage=oldMessage
foreign={command=42}; rf2.mspQueue:add(foreign)
__mock.modelFile="active-b.yml"; __mock.modelName="Other"
oldMessage.processReply()
eq("ACK observes model switch before B exists",old.profileOperation,nil)
eq("model change preserves active owned transaction",rf2.mspQueue.currentMessage==oldMessage,true)
eq("model change preserves foreign pending transaction",rf2.mspQueue.messageQueue[1]==foreign,true)
eq("active old ACK cannot stage verification",oldOperation.nextMessage,nil)
fresh=second.create(zone,options(30))
tick(second,fresh,1010,0,true)
eq("new owner initializes while upstream old request stays active",fresh.kseInitialized,true)
eq("new owner leaves old upstream transaction intact",rf2.mspQueue.currentMessage==oldMessage,true)
print("PASS|complete")
