-- Real dashboard lifecycle/render callbacks, with public EdgeTX boundaries.
-- The minimal Lua host omits radio unit constants; distinct values suffice
-- because the dashboard compares the public constant, never its numeric ABI.
UNIT_VOLTS=1;UNIT_AMPS=2;UNIT_RPMS=3;UNIT_MAH=4;UNIT_CELSIUS=5;UNIT_PERCENT=6
local assertions=0
local function eq(actual,expected,message)
  assertions=assertions+1
  assert(actual==expected,message..": expected "..tostring(expected)..", got "..tostring(actual))
end
local fieldInfo=getFieldInfo
local function fixture(selection)
  _G.__KSE_WIDGET_OWNER_V1=nil
  __mock.now=1000;__mock.modelName="Arbitrary radio model";__mock.modelFilename="shared.yml"
  __mock.timer={start=0,value=0};__mock.values={};__mock.events={};__mock.fieldCalls={}
  fs.files={};fs.faults={};fs.online=true
  local t={rssi=100,builds=0,labels={},sensors={},base=300,hostCalls=0,queueCalls=0,loads=0,requests=0}
  model.getInfo=function() return {name=__mock.modelName,filename=__mock.modelFilename} end
  model.setInfo=function() error("OMP Auto must not rename the radio model") end
  model.getSensor=function(index)
    if index<0 or index>=64 then return nil end
    return t.sensors[index] or {type=0,name="",unit=0,id=0,instance=0}
  end
  getFieldInfo=function(name)
    if name=="telem1" then return {id=t.base,name="telem1"} end
    return fieldInfo(name)
  end
  getRSSI=function() return t.rssi end
  function t:sensor(index,name,value,sensorId,unit,sensorType,instance)
    local sourceId=self.base+3*index
    local item={id=sourceId,value=value}
    self.sensors[index]={name=name,type=sensorType or 0,unit=unit or UNIT_VOLTS,
      id=sensorId or 0,instance=instance or 0}
    __mock.values[name]=item;__mock.values[sourceId]=item
    return item
  end
  function t:remove(index)
    local metadata=self.sensors[index]
    if metadata then __mock.values[metadata.name]=nil end
    self.sensors[index]=nil;__mock.values[self.base+3*index]=nil
  end
  t.rx=t:sensor(1,"RxBt",7.6,0x08)
  t.cell=t:sensor(7,"Volt",3.8,0x80FE)
  t.rpm=t:sensor(12,"RPM",0,0x0C,UNIT_RPMS)
  t:sensor(15,"Curr",0,0,UNIT_AMPS)
  t:sensor(20,"Capa",0,0,UNIT_MAH)
  t:sensor(22,"Temp",25,0,UNIT_CELSIUS)
  t:sensor(26,"RQly",100,0,UNIT_PERCENT)
  t:sensor(30,"Bat%",80,0,UNIT_PERCENT)
  local function object(first,second)
    local item={properties=second or first or {}}
    function item:set(values) for k,v in pairs(values) do self.properties[k]=v end end
    function item:show() self.hidden=false end
    function item:hide() self.hidden=true end
    t.labels[#t.labels+1]=item
    return item
  end
  lvgl={clear=function() t.builds=t.builds+1;t.labels={} end,
    label=object,rectangle=object,image=object,hline=object,vline=object,arc=object}
  t.host={state="disarmed",background=function() t.hostCalls=t.hostCalls+1 end}
  t.queue={messageQueue={},add=function() t.requests=t.requests+1 end,
    processQueue=function() t.queueCalls=t.queueCalls+1 end,
    isProcessed=function() return true end,clear=function() error("RF clear forbidden") end}
  rf2={apiVersion=12.09,rfToolApiVersion=1,modelName="RF name must not identify OMP",
    widget=t.host,mspQueue=t.queue,registerWidget=function() end}
  loadScript=function() t.loads=t.loads+1;error("OMP Auto must not load RF Tool") end
  t.api=dofile(dashboardPath);t.audit=t.api.audit;t.opts={}
  for _,option in ipairs(t.api.options) do t.opts[option[1]]=option[3] end
  t.opts.HeliType=selection or 5;t.opts.CountSrc=2;t.opts.MotorSw=99
  t.widget=t.api.create({x=0,y=0,w=LCD_W,h=LCD_H},t.opts)
  t.api.update(t.widget,t.opts)
  function t:step(visible,delta)
    __mock.now=__mock.now+(delta or 20)
    if visible then self.api.refresh(self.widget,nil,nil) else self.api.background(self.widget) end
    if visible then
      for _,item in ipairs(self.labels) do
        for key,value in pairs(item.properties) do
          if type(value)=="function" then value=value() end
          if key=="w" or key=="h" then
            assert(type(value)=="number" and value>=0,"invalid render dimension")
          end
        end
      end
    end
  end
  function t:settle(visible) for _=1,5 do self:step(visible) end end
  function t:pack(cells,voltage)
    self.cell.value=voltage or 3.8;self.rx.value=cells*self.cell.value
  end
  function t:noRF(message)
    eq(self.hostCalls,0,message.." host service")
    eq(self.queueCalls,0,message.." queue service")
    eq(self.loads,0,message.." RF loads")
    eq(self.requests,0,message.." MSP admissions")
  end
  return t
end

local t=fixture()
local a=t.audit
eq(#t.api.options,10,"ten persisted options")
eq(table.concat(t.api.options[4][4],","),"Electric,Nitro,OMPHOBBY,Auto Elec/Nitro,OMP Auto","appended choice order")
eq(t.api.options[4][3],1,"Electric default retained")
eq(a.OPT.ompAuto,true,"OMP Auto enabled")
eq(a.OPT.autoHeliType,false,"FC name Auto independent")
eq(a.OPT.heliType,3,"OMP effective engine")
eq(a.OPT.flightCounter,1,"effective local counter")
eq(t.opts.CountSrc,2,"saved FC preference preserved")
eq(t.opts.HeliType,5,"saved OMP Auto choice preserved")
eq(a.name(),"OMP AUTO","initial unresolved display name")
eq(a.count(),nil,"unresolved counter has no guessed identity")
__mock.timer.value=25;t:step(true)
eq(a.OMP_AUTO.ready,false,"first ratio begins confirmation")
t:step(true,49);eq(a.OMP_AUTO.ready,false,"49 ticks not sufficient")
t:step(true,1);eq(a.OMP_AUTO.ready,true,"50 ticks confirms")
eq(a.name(),"OMP M1","2S selects exact M1 display name")
eq(a.D.cellsResolved,2,"M1 cells")
eq(a.D.isLiHV,true,"M1 chemistry deterministic")
eq(a.cache()["Arbitrary radio model"],nil,"generic radio key never counted")
eq(a.cache()["OMP AUTO"],nil,"unresolved key never counted")
eq(a.count(),0,"already-running timer cannot count at initial resolution")
local builds=t.builds
a.A.flightDeadVoiceLatched=true;t:settle(true)
eq(a.A.flightDeadVoiceLatched,true,"stable identity preserves latch")
eq(t.builds,builds,"stable identity avoids rebuild")
t.opts.Theme=2;t.api.update(t.widget,t.opts)
eq(a.OMP_AUTO.ready,true,"theme edit preserves ready identity")
eq(a.name(),"OMP M1","theme edit preserves name")
eq(a.A.flightDeadVoiceLatched,true,"theme edit preserves warning latch")
t:noRF("OMP Auto lifecycle")

-- Partial charge cannot turn a 3S aircraft into the 2S model.
local partial=fixture();partial:pack(3,3.4);partial:settle(true)
eq(partial.audit.name(),"OMP M2","partly charged 3S identifies by ratio")
eq(partial.audit.D.cellsResolved,3,"partly charged M2 cells")
eq(partial.audit.D.isLiHV,false,"ordinary M2 voltage does not inherit LiHV")
partial:noRF("M2 lifecycle")

-- Native pack voltage has fewer decimals than average cell voltage.
for _,cells in ipairs({2,3}) do
  local full=fixture();full:pack(cells,4.35)
  full.rx.value=math.floor(full.rx.value*10+0.5)/10
  full:settle(true)
  eq(full.audit.name(),cells==2 and "OMP M1" or "OMP M2","full LiHV pack with CRSF rounding")
  eq(full.audit.D.cellsResolved,cells,"full pack cell count")
end

-- Confirmed identity survives flight, stale voltage, and brief link loss.
local retained=fixture();retained:settle(false)
local ra=retained.audit
ra.A.flightDeadVoiceLatched=true
retained.rpm.value=2400;retained:pack(3)
retained:settle(true)
eq(ra.name(),"OMP M1","running rotor cannot switch model")
eq(ra.D.cellsResolved,2,"running rotor retains cells")
retained.rpm.value=0;retained.rpm.fresh=false;retained:settle(true)
eq(ra.name(),"OMP M1","stale RPM cannot establish ground")
eq(ra.count(),0,"stale RPM does not open unidentified count state")
retained.rpm.fresh=true;retained.cell.fresh=false;retained:settle(true)
eq(ra.name(),"OMP M1","stale voltage retains confirmed name")
retained.cell.fresh=true;retained.cell.current=false;retained:settle(false)
eq(ra.name(),"OMP M1","noncurrent voltage retains identity")
retained.cell.current=true;retained.rssi=0;retained:settle(true)
eq(ra.name(),"OMP M1","brief RSSI loss retains identity")
eq(ra.A.flightDeadVoiceLatched,true,"transient loss retains latch")
retained.rssi=100;retained:pack(2);retained:settle(true)
eq(ra.name(),"OMP M1","same-aircraft reconnect")
eq(ra.A.flightDeadVoiceLatched,true,"same-aircraft reconnect preserves latch")

-- Ground swap invalidates count eligibility before confirming a new class.
ra.S.rpmMax=9999;ra.S.currMax=99;ra.S.tempMax=99
__mock.timer.value=25;retained:pack(3)
retained:step(false,10)
eq(ra.OMP_AUTO.ready,false,"ground different ratio unresolved at next acquisition")
eq(ra.count(),nil,"ground change cannot display prior-aircraft count")
builds=retained.builds;retained:step(false,49)
eq(ra.OMP_AUTO.ready,false,"new class waits entire interval")
retained:step(false,1)
eq(ra.name(),"OMP M2","ground class swap confirms M2")
eq(ra.D.isLiHV,false,"class swap clears M1 chemistry")
eq(ra.S.rpmMax,0,"class swap resets RPM maximum")
eq(ra.S.currMax,0,"class swap resets current maximum")
eq(ra.S.tempMax,25,"new model extrema begin with its own telemetry")
eq(ra.A.flightDeadVoiceLatched,false,"class swap resets alert state")
eq(ra.count(),0,"class swap does not inherit timer qualification")
eq(retained.builds,builds,"background selection does not build UI")
retained:step(true);eq(retained.builds,builds+1,"foreground rebuilds swapped model")
retained:noRF("flight and ground swap")

-- Missing, stale, calculated, foreign, and ambiguous telemetry must not guess.
local invalidCases={
  {"missing cell",function(f) f:remove(7) end},
  {"missing pack",function(f) f:remove(1) end},
  {"missing RPM",function(f) f:remove(12) end},
  {"stale cell",function(f) f.cell.fresh=false end},
  {"noncurrent pack",function(f) f.rx.current=false end},
  {"missing source flags",function(f) f.cell.rawFlags=true end},
  {"unreadable source",function(f) f.cell.throw=true end},
  {"stale RPM",function(f) f.rpm.fresh=false end},
  {"noncurrent RPM",function(f) f.rpm.current=false end},
  {"running RPM",function(f) f.rpm.value=1 end},
  {"negative RPM",function(f) f.rpm.value=-1 end},
  {"calculated RPM",function(f) f.sensors[12].type=1 end},
  {"foreign RPM ID",function(f) f.sensors[12].id=0x0500 end},
  {"wrong RPM unit",function(f) f.sensors[12].unit=UNIT_VOLTS end},
  {"wrong RPM instance",function(f) f.sensors[12].instance=1 end},
  {"ambiguous raw RPM",function(f) f:sensor(14,"RPM",0,0x010C,UNIT_RPMS) end},
  {"ambiguous calculated RPM",function(f) f:sensor(14,"RPM",0,0x0C,UNIT_RPMS,1) end},
  {"zero cell",function(f) f.cell.value=0 end},
  {"implausible cell",function(f) f:pack(2,4.6) end},
  {"non-numeric cell",function(f) f.cell.value="unavailable" end},
  {"wrong ratio",function(f) f:pack(2.5) end},
  {"unsupported 4S",function(f) f:pack(4) end},
  {"out of tolerance",function(f) f:pack(2.16) end},
  {"calculated cell",function(f) f.sensors[7].type=1 end},
  {"calculated pack",function(f) f.sensors[1].type=1 end},
  {"wrong unit",function(f) f.sensors[7].unit=UNIT_AMPS end},
  {"foreign pack ID",function(f) f.sensors[1].id=0x0210 end},
  {"foreign cell ID",function(f) f.sensors[7].id=0xFE end},
  {"wrong cell low byte",function(f) f.sensors[7].id=0x80FD end},
  {"wrong instance",function(f) f.sensors[7].instance=1 end},
  {"ambiguous raw cell",function(f) f:sensor(9,"Volt",3.8,0x81FE) end},
}
for _,case in ipairs(invalidCases) do
  local f=fixture();case[2](f);f:settle(true)
  eq(f.audit.OMP_AUTO.ready,false,case[1].." remains unresolved")
  eq(f.audit.count(),nil,case[1].." has no counter identity")
  eq(f.audit.A.battAlertPrevPct,nil,case[1].." cannot produce pack alerts")
  f:noRF(case[1])
end
local extended=fixture();extended.sensors[7].id=0x92FE;extended:settle(false)
eq(extended.audit.name(),"OMP M1","extended CRSF high-byte family accepted")
local extendedRpm=fixture();extendedRpm.sensors[12].id=0xFF0C;extendedRpm:settle(false)
eq(extendedRpm.audit.name(),"OMP M1","CRSF RPM high-byte index accepted")
for _,ratio in ipairs({1.86,2.14,2.86,3.14}) do
  local f=fixture();f:pack(ratio);f:settle(false)
  eq(f.audit.name(),ratio<2.5 and "OMP M1" or "OMP M2","ratio tolerance "..ratio)
end

-- Any same-name duplicate is ambiguous for the name-based display pipeline.
local duplicate=fixture();duplicate:sensor(9,"Volt",9,0,UNIT_VOLTS,1)
duplicate:settle(false)
eq(duplicate.audit.OMP_AUTO.ready,false,"calculated name collision remains unresolved")
eq(duplicate.audit.count(),nil,"calculated name collision has no counter identity")
local rediscover=fixture();rediscover:remove(7);rediscover:settle(false)
rediscover.cell=rediscover:sensor(40,"Volt",3.8,0x80FE);rediscover:settle(true)
eq(rediscover.audit.name(),"OMP M1","discovers sensor after valid empty slots")
rediscover:remove(40);rediscover.rpm.value=2200;rediscover:settle(true)
eq(rediscover.audit.name(),"OMP M1","missing source after resolution retains identity")
rediscover.cell=rediscover:sensor(41,"Volt",3.8,0x80FE);rediscover:pack(3)
rediscover.rpm.value=0;rediscover:settle(true)
eq(rediscover.audit.name(),"OMP M2","rediscovered source permits new ground selection")

-- Source identity is checked before the general telemetry-name cache expires.
local moved=fixture();moved:settle(false)
moved.audit.A.flightDeadVoiceLatched=true
moved:remove(7);moved.cell=moved:sensor(41,"Volt",3.8,0x80FE)
moved:step(false,10)
eq(moved.audit.OMP_AUTO.ready,false,"source ID move requires ground reconfirmation before cache expiry")
eq(moved.audit.count(),nil,"source move suppresses old count before cache expiry")
moved:step(false,49)
eq(moved.audit.OMP_AUTO.ready,false,"source move waits full confirmation interval")
moved:step(false,1)
eq(moved.audit.name(),"OMP M1","same-class moved source reconfirms")
eq(moved.audit.A.flightDeadVoiceLatched,true,"same-class source move retains latch")

-- A zero from an unqualified RPM source cannot turn a flying M1 into an M2.
for _,case in ipairs({
  {"missing",function(f) f:remove(12) end},
  {"calculated",function(f) f.sensors[12].type=1 end},
  {"foreign",function(f) f.sensors[12].id=0x0500 end},
  {"wrong unit",function(f) f.sensors[12].unit=UNIT_VOLTS end},
}) do
  local f=fixture();f:settle(false);f.rpm.value=2400;f:step(false)
  f.audit.A.flightDeadVoiceLatched=true
  f.rpm.value=0;case[2](f);f:pack(3);f:settle(true)
  eq(f.audit.OMP_AUTO.ready,true,case[1].." RPM preserves confirmed flight")
  eq(f.audit.name(),"OMP M1",case[1].." RPM cannot select M2")
  eq(f.audit.D.cellsResolved,2,case[1].." RPM retains M1 cells")
  eq(f.audit.A.flightDeadVoiceLatched,true,case[1].." RPM preserves alert latch")
  f.rpm=f:sensor(12,"RPM",0,0x0C,UNIT_RPMS);f:settle(false)
  eq(f.audit.name(),"OMP M2","restored native RPM permits ground selection")
  f:noRF(case[1].." RPM replacement")
end

-- Reconfirmation cannot backfill a timer threshold crossed while unresolved.
local qualification=fixture();qualification:settle(false)
__mock.timer.value=25;qualification:step(false)
eq(qualification.audit.count(),1,"qualified flight counted before interruption")
__mock.timer.value=0;qualification:step(false)
qualification.audit.A.flightDeadVoiceLatched=true
qualification:remove(12)
qualification.rpm=qualification:sensor(42,"RPM",0,0x0C,UNIT_RPMS)
qualification:step(false,10)
eq(qualification.audit.OMP_AUTO.ready,false,"RPM source move requires reconfirmation")
eq(qualification.audit.count(),nil,"RPM source move suppresses displayed count")
__mock.timer.value=25;qualification:step(false,49)
eq(qualification.audit.OMP_AUTO.ready,false,"moved RPM waits full confirmation interval")
qualification:step(false,1)
eq(qualification.audit.OMP_AUTO.ready,true,"same-class RPM source reconfirms")
eq(qualification.audit.count(),1,"unresolved timer crossing does not backfill")
eq(qualification.audit.cache()["OMP M1"],1,"already-counted flight survives reconfirmation")
eq(qualification.audit.A.flightDeadVoiceLatched,true,"reconfirmation preserves alert latch")
__mock.timer.value=0;qualification:step(false)
__mock.timer.value=25;qualification:step(false)
eq(qualification.audit.count(),2,"timer reset requalifies a subsequent flight")
qualification:noRF("timer qualification")

-- Interrupted samples and backwards time cannot shorten confirmation.
local unstable=fixture();unstable:step(false)
unstable:step(false,30);unstable:pack(3);unstable:step(false,10)
unstable:step(false,49);eq(unstable.audit.OMP_AUTO.ready,false,"changed candidate restarts interval")
unstable:step(false,-100);eq(unstable.audit.OMP_AUTO.ready,false,"clock rollback cannot confirm")
unstable:settle(false);eq(unstable.audit.name(),"OMP M2","stable post-rollback ratio confirms")
local interrupted=fixture();interrupted:step(false);interrupted:step(false,30)
interrupted.cell.fresh=false;interrupted:step(false,10)
interrupted.cell.fresh=true;interrupted:step(false,10);interrupted:step(false,49)
eq(interrupted.audit.OMP_AUTO.ready,false,"stale evidence restarts interval")
interrupted:step(false,1);eq(interrupted.audit.OMP_AUTO.ready,true,"fresh interval confirms")

-- CSV and image keys follow exact virtual names; radio metadata stays untouched.
local counts=fixture();counts:settle(false)
__mock.timer.value=25;counts:step(false)
eq(counts.audit.cache()["OMP M1"],1,"M1 local counter key")
counts:pack(3);counts:settle(false)
eq(counts.audit.count(),0,"M2 starts with its own count")
__mock.timer.value=0;counts:step(false)
__mock.timer.value=25;counts:step(false)
eq(counts.audit.cache()["OMP M2"],1,"M2 local counter key")
eq(counts.audit.cache()["OMP M1"],1,"M1 count retained")
counts:settle(false)
assert(string.find(fs.files["/flights-count.csv"] or "","OMP M1,1",1,true),"M1 persists")
assert(string.find(fs.files["/flights-count.csv"] or "","OMP M2,1",1,true),"M2 persists")
local png="\137PNG\r\n\26\n".."\0\0\0\13IHDR".."\0\0\0\100\0\0\0\100"..string.rep("\0",30)
fs.files["/IMAGES/OMP M1.png"]=png;fs.files["/IMAGES/OMP M2.png"]=png
eq(counts.audit.image(),"/IMAGES/OMP M2.png","M2 exact picture key")
counts:pack(2);counts:settle(false)
eq(counts.audit.image(),"/IMAGES/OMP M1.png","M1 swap invalidates picture cache")
eq(counts.audit.count(),1,"returning M1 loads its own count")
eq(__mock.modelName,"Arbitrary radio model","radio name unchanged")
eq(__mock.modelFilename,"shared.yml","radio filename unchanged")
counts:noRF("counter and image lifecycle")

-- Saved model replacement and explicit mode changes require new selection.
local modelSwap=fixture();modelSwap:settle(true)
modelSwap.audit.A.flightDeadVoiceLatched=true
__mock.modelName="Any name works";modelSwap:step(false,10)
eq(modelSwap.audit.OMP_AUTO.ready,true,"radio display-name edit preserves identity")
eq(modelSwap.audit.name(),"OMP M1","radio display-name edit cannot select aircraft")
eq(modelSwap.audit.A.flightDeadVoiceLatched,true,"radio display-name edit preserves alerts")
__mock.modelFilename="replacement.yml";modelSwap:step(false,1)
local oldModelWidget=modelSwap.widget
eq(modelSwap.audit.owner.current(oldModelWidget),false,"previous saved model widget loses ownership")
eq(oldModelWidget.kseInitialized,false,"previous saved model background retires the old session")
eq(modelSwap.audit.A.flightDeadVoiceLatched,true,"previous saved model background cannot reset new session")
-- Saved-model selection recreates the widget; the dashboard Lua state survives.
modelSwap.widget=modelSwap.api.create({x=0,y=0,w=LCD_W,h=LCD_H},modelSwap.opts)
modelSwap:step(true,1)
eq(modelSwap.audit.owner.current(modelSwap.widget),true,"new saved model foreground owns immediately")
eq(modelSwap.audit.OMP_AUTO.ready,false,"saved model change restarts identity")
eq(modelSwap.audit.count(),nil,"saved model change suppresses counter")
modelSwap:settle(false)
eq(modelSwap.audit.name(),"OMP M1","replacement model confirms afresh")
eq(modelSwap.audit.A.flightDeadVoiceLatched,false,"saved model clears prior alert session")
modelSwap.opts.HeliType=3;__mock.modelName="Manual M2";modelSwap.api.update(modelSwap.widget,modelSwap.opts)
modelSwap:settle(true)
eq(modelSwap.audit.OPT.ompAuto,false,"manual OMP disables detection")
eq(modelSwap.audit.name(),"Manual M2","manual OMP uses radio name")
eq(modelSwap.audit.D.cellsResolved,3,"manual M2 fallback preserved")
modelSwap.opts.HeliType=5;modelSwap.api.update(modelSwap.widget,modelSwap.opts)
eq(modelSwap.audit.OMP_AUTO.ready,false,"manual to Auto requires confirmation")
eq(modelSwap.audit.count(),nil,"manual to Auto suppresses inherited counter")
modelSwap:settle(true);eq(modelSwap.audit.name(),"OMP M1","manual to Auto uses ratio")
for _,invalid in ipairs({0,6,-1,1.5,3.5,4.5,5.5}) do
  modelSwap.opts.HeliType=invalid;modelSwap.api.update(modelSwap.widget,modelSwap.opts)
  eq(modelSwap.audit.OPT.heliType,1,"invalid choice falls back to Electric")
  eq(modelSwap.audit.OPT.ompAuto,false,"invalid choice cannot enable OMP Auto")
end

-- Duplicates leave the owner's identity, mode, and alert state intact.
local owner=fixture();owner:settle(true);owner.audit.A.flightDeadVoiceLatched=true
local duplicateOptions={HeliType=1,CountSrc=1,Theme=1}
local otherWidget=owner.api.create({w=LCD_W,h=LCD_H},duplicateOptions)
owner.api.update(otherWidget,duplicateOptions);owner.api.background(otherWidget)
eq(owner.audit.OMP_AUTO.ready,true,"same-module duplicate preserves readiness")
eq(owner.audit.name(),"OMP M1","same-module duplicate preserves identity")
eq(owner.audit.OPT.ompAuto,true,"same-module duplicate preserves option")
eq(owner.audit.A.flightDeadVoiceLatched,true,"same-module duplicate preserves latch")
local other=dofile(otherDashboardPath)
otherWidget=other.create({w=LCD_W,h=LCD_H},owner.opts)
other.update(otherWidget,owner.opts);other.background(otherWidget)
eq(owner.audit.OMP_AUTO.ready,true,"cross-variant duplicate preserves readiness")
__mock.now=__mock.now+501;other.refresh(otherWidget,nil,nil)
eq(other.audit.OMP_AUTO.ready,false,"owner takeover requires confirmation")
__mock.now=__mock.now+50;other.background(otherWidget)
eq(other.audit.name(),"OMP M1","new owner confirms same ratio")
owner:noRF("duplicate ownership")

-- Reproducible helper instruction observations include these Lua API mocks.
local cost=fixture()
cost.audit.clear();__mock.now=__mock.now+20
local acquiring=measure(cost.audit.OMP_AUTO.sync,cost.widget)
cost:settle(false);cost.rpm.value=2400
cost.audit.clear();__mock.now=__mock.now+20
local voltLookups=__mock.fieldCalls.Volt or 0
local flying=measure(cost.audit.OMP_AUTO.sync,cost.widget)
eq(__mock.fieldCalls.Volt or 0,voltLookups,"steady flight skips Volt identity lookup")
eq(flying<acquiring,true,"steady flight avoids acquisition scan cost")
cost.audit.clear();__mock.now=__mock.now+1
local throttled=measure(cost.audit.OMP_AUTO.sync,cost.widget)
eq(throttled<flying,true,"sub-10-tick callback avoids repeated acquisition")
print(tostring(assertions).." OMP Auto assertions; sync VM instructions acquire="
  ..acquiring..", flight="..flying..", throttled="..throttled
  .."; real lifecycle/render callbacks exercised")
