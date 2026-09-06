local function eq(name,actual,expected)
  assert(actual==expected,name..": expected "..tostring(expected)..", got "..tostring(actual))
  print("PASS|"..name)
end
local path="/flights-count.csv"
local header="model_name,flight_count\n# api_ver=1\n"
fs.files={[path]=header.."Fixture,7\nOther,20\n"}
__mock.now=1000
__mock.values.ARM={id=77,value=0}
__mock.values[77]={value=0}
getRSSI=function() return 100 end
local menu
lvgl={menu=function(spec) menu=spec end,clear=function() end,label=function() end}
rf2={apiVersion=12.09,rfToolApiVersion=1.0,registerWidget=function() end,
     widget={state="disarmed",background=function() end}}
rf2.mspQueue={messageQueue={},maxRetries=-1,
  add=function(self,message) self.messageQueue[#self.messageQueue+1]=message end,
  isProcessed=function(self) return not self.currentMessage and #self.messageQueue==0 end}

local first=dofile(dashboardDir.."/"..ownerVariant..".lua")
local second=sameModule and first or dofile(dashboardDir.."/"..contenderVariant..".lua")
local a,b=first.audit,second.audit
local function options(reserve,heli)
  return {Theme=1,TxBatt=1,HeliType=heli or 1,BattRsv=reserve,CountSrc=1,MinFlight=30,
          RxPackMin="6.60",RxPackMax="8.40",MotorSw=99}
end
local function metrics(api)
  return api.audit.metrics.rf+api.audit.metrics.build+api.audit.metrics.draw
end
local function background(api,widget,now,seconds)
  __mock.now=now; __mock.timer={start=0,value=seconds or 0}; api.background(widget)
end
local function foreground(api,widget,now,seconds)
  __mock.now=now; __mock.timer={start=0,value=seconds or 0}; api.refresh(widget,nil,nil)
end
local ownerOptions=options(20)
local owner=first.create({x=0,y=0,w=800,h=480},ownerOptions)
eq("first widget initializes options",a.OPT.reservePct,20)
eq("first widget loads saved count",a.count(),7)
assert(type(_G.__KSE_WIDGET_OWNER_V1)=="table","global lease missing")
eq("initial lease identifies first widget",_G.__KSE_WIDGET_OWNER_V1.widget==owner,true)
background(first,owner,1010,0)
background(first,owner,1020,30)
eq("owner qualifies local count",a.count(),8)
background(first,owner,1030,30)
eq("owner persists local count",fs.files[path],header.."Fixture,8\nOther,20\n")
eq("owner background performs work",a.metrics.rf>0,true)

-- Capture a real picker closure while this widget owns the lease.
owner.profileRfState="disarmed"; owner.profileActive=1
owner.profileCapacitiesReady=true; owner.profileCapacities={1000,2000,3000,0,0,0}
eq("owner can open profile picker",a.profiles.picker(owner),true)
assert(menu and type(menu.set)=="function","native picker callback missing")
local stalePicker=menu.set

local lease=_G.__KSE_WIDGET_OWNER_V1
local leaseFields={}; for key,value in pairs(lease) do leaseFields[key]=value end
local firstBefore,secondBefore=metrics(first),metrics(second)
local callsBefore=#fs.calls
a.A.battZeroReached=true; a.S.rpmMax=2300
local contenderOptions=options(45,2)
local contender=second.create({x=10,y=10,w=480,h=272},contenderOptions)
eq("duplicate create returns a widget",type(contender),"table")
eq("duplicate create preserves active options",a.OPT.reservePct,20)
eq("duplicate create preserves active heli type",a.OPT.heliType,1)
eq("duplicate create preserves active warning",a.A.battZeroReached,true)
eq("duplicate create preserves active stats",a.S.rpmMax,2300)
eq("duplicate create performs no file IO",#fs.calls,callsBefore)
eq("duplicate create performs no render or RF work",metrics(first)+metrics(second),firstBefore+secondBefore)
eq("duplicate create preserves lease object",_G.__KSE_WIDGET_OWNER_V1==lease,true)
for key,value in pairs(leaseFields) do assert(lease[key]==value,"duplicate mutated lease field "..key) end
eq("duplicate create leaves lease fields unchanged",true,true)
eq("duplicate stays uninitialized",contender.kseInitialized,nil)
local revised=options(35,2)
second.update(contender,revised)
eq("duplicate update stores own options",contender.options==revised,true)
eq("duplicate update preserves active options",a.OPT.reservePct,20)
eq("duplicate update preserves active warning",a.A.battZeroReached,true)
eq("duplicate update performs no file IO",#fs.calls,callsBefore)
background(second,contender,1100,0)
foreground(second,contender,1110,0)
eq("active lease blocks duplicate callback work",metrics(first)+metrics(second),firstBefore+secondBefore)
eq("duplicate callbacks preserve file",fs.files[path],header.."Fixture,8\nOther,20\n")
contender.profileRfState="disarmed"
eq("duplicate cannot admit MSP",b.profiles.begin(contender,"select",2),false)
eq("inactive admission does not alter context",contender.mspContextEpoch,nil)
eq("duplicate MSP attempt leaves queue empty",#rf2.mspQueue.messageQueue,0)

-- Owner activity keeps the lease live even with only background callbacks.
background(first,owner,1400,30)
local currentBefore=metrics(second)
foreground(second,contender,1800,30)
eq("owner background renews lease against foreground contender",metrics(second),currentBefore)
eq("renewed lease preserves owner options",a.OPT.reservePct,20)

-- An expired lease can only transfer through the contender's foreground path.
local afterPulse=_G.__KSE_WIDGET_OWNER_V1
callsBefore=#fs.calls; secondBefore=metrics(second)
foreground(second,contender,1899,30)
eq("lease remains exclusive before 500 ticks",_G.__KSE_WIDGET_OWNER_V1.widget==owner,true)
eq("active owner can prepare a pending request",a.profiles.begin(owner,"select",2),true)
local oldOperation=owner.profileOperation
local staleReply=rf2.mspQueue.messageQueue[1].processReply
local staleError=rf2.mspQueue.messageQueue[1].errorHandler
local foreign={command=42}
rf2.mspQueue:add(foreign)
background(second,contender,1900,30)
eq("expired contender background cannot steal",afterPulse.widget==owner,true)
eq("expired contender background performs no work",metrics(second),secondBefore)
eq("expired contender background performs no IO",#fs.calls,callsBefore)
local lateCreated=second.create({x=0,y=0,w=480,h=320},options(10))
eq("expired duplicate create cannot take over",afterPulse.widget==owner,true)
eq("expired duplicate create stays lightweight",lateCreated.kseInitialized,nil)
eq("expired duplicate create performs no IO",#fs.calls,callsBefore)
foreground(second,contender,1900,30)
eq("foreground claims at 500 ticks",afterPulse.widget==contender,true)
eq("handoff increments owner epoch",contender.kseOwnerEpoch>owner.kseOwnerEpoch,true)
eq("foreground takeover applies contender options",b.OPT.reservePct,35)
eq("foreground takeover applies contender heli type",b.OPT.heliType,2)
eq("foreground takeover loads existing persisted count",b.count(),8)
eq("foreground takeover performs owner work",metrics(second)>secondBefore,true)
eq("takeover resets prior warning evidence",b.A.battZeroReached,false)
eq("handoff retires previous operation",owner.profileOperation,nil)
eq("handoff removes owned pending request",#rf2.mspQueue.messageQueue,1)
eq("handoff preserves foreign pending request",rf2.mspQueue.messageQueue[1]==foreign,true)
staleReply()
eq("late old ACK cannot stage continuation",oldOperation.nextMessage,nil)
eq("late old ACK cannot restore operation",owner.profileOperation,nil)
-- The fake foreign consumer completes its own message.
rf2.mspQueue.messageQueue={}


-- Stale callbacks and closures cannot mutate the replacement owner's state.
local newLease=_G.__KSE_WIDGET_OWNER_V1
firstBefore,secondBefore=metrics(first),metrics(second)
callsBefore=#fs.calls
local staleSelection=owner.profileSelectionRequested
stalePicker(2)
eq("stale picker closure cannot request selection",owner.profileSelectionRequested,staleSelection)
eq("stale owner cannot admit MSP",a.profiles.begin(owner,"select",2),false)
eq("stale admission leaves shared queue untouched",#rf2.mspQueue.messageQueue,0)
first.update(owner,options(49,3))
background(first,owner,2020,0); foreground(first,owner,2030,0)
eq("old callbacks cannot steal active lease",newLease.widget==contender,true)
eq("old callbacks cannot change new options",b.OPT.reservePct,35)
eq("old callbacks perform no file IO",#fs.calls,callsBefore)
eq("old callbacks perform no work",metrics(first)+metrics(second),firstBefore+secondBefore)

-- A model change is serviced by the active owner, never by the old callback.
__mock.modelName="Other"
background(first,owner,2040,0)
eq("stale model-change callback cannot change active count",b.count(),8)
background(second,contender,2050,0)
eq("current owner recognizes model change",b.count(),20)
background(second,contender,2060,30); background(second,contender,2070,30)
eq("current model qualifies independently",b.count(),21)
eq("new owner preserves both models",fs.files[path],header.."Fixture,8\nOther,21\n")
-- Transfer a count which qualified but has not reached the next save callback.
background(second,contender,2080,0); background(second,contender,2090,30)
eq("current owner retains unsaved qualified event",b.count(),22)
eq("qualified event waits for persistence callback",fs.files[path],header.."Fixture,8\nOther,21\n")
foreground(first,owner,2590,30)
eq("returning foreground can claim expired owner",newLease.widget==owner,true)
eq("handoff preserves dirty qualified count",a.count(),22)
eq("handoff persists dirty history without recounting",fs.files[path],header.."Fixture,8\nOther,22\n")
local reclaimedSelection=owner.profileSelectionRequested
stalePicker(2)
eq("old picker stays invalid after original widget reclaims",owner.profileSelectionRequested,reclaimedSelection)
owner.profileRfState="disarmed"
eq("reclaimed owner starts a fresh operation",a.profiles.begin(owner,"select",3),true)
local replacementOperation=owner.profileOperation
staleReply()
eq("old ACK cannot stage after original widget reclaims",replacementOperation.nextMessage,nil)
eq("old ACK cannot replace fresh operation",owner.profileOperation==replacementOperation,true)
staleError()
eq("old error cannot clear fresh operation",owner.profileOperation==replacementOperation,true)
eq("old error preserves new pending request",rf2.mspQueue.messageQueue[1]==replacementOperation.messages[1],true)
print("PASS|complete")
