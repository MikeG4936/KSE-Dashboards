-- Real lifecycle and render functions; only EdgeTX/LVGL/RF boundaries mocked.
assert(getmetatable("")==nil,"rebuild the fixture runner: default EdgeTX has no string-method metatable")
local assertions=0
local function eq(actual,expected,message)
  assertions=assertions+1
  assert(actual==expected,message..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function fixture(selection,counter,embedded)
  _G.__KSE_WIDGET_OWNER_V1=nil
  __mock.now=1000; __mock.modelName="Shared Heli";__mock.modelFilename="shared.yml"
  model.getInfo=function() return {name=__mock.modelName,filename=__mock.modelFilename} end
  __mock.timer={start=0,value=0};__mock.values={};__mock.events={}
  fs.files={};fs.faults={};fs.online=true
  local t={rssi=0,builds=0,labels={},requests={},hostCalls=0,queueCalls=0}
  local id=100
  for name,value in pairs({Hspd=0,Tspd=0,Vbec=7.6,ARM=0,RQly=100,
      ["Cel#"]=6,Vcel=4,Vbat=24,["Bat%"]=100,Curr=0,Capa=0,Tesc=25,
      Gov=0,["BAT#"]=1,["PID#"]=1,["RTE#"]=1,["tx-voltage"]=8.1}) do
    id=id+1
    local item={id=id,value=value}
    __mock.values[name]=item;__mock.values[id]=item
  end
  getRSSI=function() return t.rssi end
  local readSource=getSourceValue
  -- The inherited readSource is restored after each fixture to avoid chains.
  if not __originalSource then __originalSource=readSource end
  getSourceValue=function(source)
    if source==__mock.values.Hspd.id and t.audit then t.sampledType=t.audit.OPT.heliType end
    return __originalSource(source)
  end
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
  t.host={state="initializing",background=function()
    t.hostCalls=t.hostCalls+1
    if t.onHost then local cb=t.onHost;t.onHost=nil;cb() end
  end}
  rf2={apiVersion=12.09,rfToolApiVersion=1,widget=t.host,registerWidget=function() end}
  t.provider=rf2
  t.queue={messageQueue={},add=function(q,message)
      t.requests[#t.requests+1]=message;q.messageQueue[#q.messageQueue+1]=message end,
    processQueue=function(q) t.queueCalls=t.queueCalls+1;if t.onQueue then t.onQueue(q) end end,
    isProcessed=function(q) return q.currentMessage==nil and #q.messageQueue==0 end,
    clear=function() error("KSE must not clear RF transport") end}
  rf2.mspQueue=t.queue
  t.api=dofile(dashboardPath);t.audit=t.api.audit
  t.opts={}
  for _,option in ipairs(t.api.options) do t.opts[option[1]]=option[3] end
  t.opts.HeliType=selection or 4;t.opts.CountSrc=counter or 1;t.opts.MotorSw=99
  t.widget=t.api.create({x=0,y=0,w=LCD_W,h=LCD_H},t.opts)
  if embedded then t.audit.owner.host(t.host,rf2) end
  t.api.update(t.widget,t.opts)
  function t:connect(name)
    self.rssi=100;self.host.state="disarmed";self.provider.modelName=name
  end
  function t:step(visible,delta)
    __mock.now=__mock.now+(delta or 20)
    if visible then self.api.refresh(self.widget,nil,nil) else self.api.background(self.widget) end
    if visible then
      for _,item in ipairs(self.labels) do
        for key,value in pairs(item.properties) do
          if type(value)=="function" then value=value() end
          if key=="w" or key=="h" then assert(type(value)=="number" and value>=0,"invalid render dimension") end
        end
      end
    end
  end
  function t:settle(visible) for _=1,4 do self:step(visible) end end
  function t:hasText(text)
    for _,item in ipairs(self.labels) do
      local value=item.properties.text
      if type(value)=="function" then value=value() end
      if not item.hidden and value==text then return true end
    end
    return false
  end
  function t:disconnect()
    self.rssi=0;self.host.state="disconnected";self.provider.modelName=nil
  end
  return t
end

local t=fixture()
local a=t.audit
local auto=a.AUTO_HELI
local opts=t.opts
eq(#t.api.options,11,"fuel setting appended after original ten")
eq(table.concat(t.api.options[4][4],","),"Electric,Nitro,OMPHOBBY,Auto Elec/Nitro,OMP Auto","choice values")
eq(t.api.options[4][3],1,"Electric default")
for name,expected in pairs({["TREX 700N"]=2,["RAW 700N"]=2,["RAW 700n  "]=2,["RAW nItRo\t"]=2,
  N=2,Nitro=2,Goblin=2,RAWN=2,RAWNitro=2,["RAW 700"]=1,["Nitro 700E"]=1,["OMP M2"]=1,[""]=1}) do
  eq(auto.infer(name),expected,"literal suffix "..name)
end
eq(auto.infer(nil),1,"missing inference")
t.rssi=100;__mock.values["Bat%"].value=10;__mock.values.Vcel.value=3.5
t:settle(true)
eq(auto.ready,false,"initializing is unresolved")
eq(a.A.battAlertPrevPct,nil,"unresolved alerts paused")
eq(t.widget.profileWasConnected,false,"unresolved profiles paused")
eq(t:hasText(variant=="KSE5" and LCD_W<600 and "WAIT FC NAME" or "WAITING FOR FC NAME"),true,"waiting render")
t:connect(" RAW 700N \t");t:step(true)
eq(auto.ready,false,"first FC sample waits")
t:step(true,29);eq(auto.ready,false,"29 ticks insufficient")
t:step(true,1);eq(auto.ready,true,"30 ticks confirms")
eq(auto.name,"RAW 700N","FC whitespace trimmed")
eq(a.OPT.heliType,2,"Nitro inference")
eq(t.sampledType,2,"mode applied before telemetry")
eq(a.name(),"RAW 700N","FC name overrides unchanged TX name")
eq(opts.HeliType,4,"saved Auto retained")
local builds=t.builds
a.A.rxDeadVoiceLatched=true;t:settle(true)
eq(t.builds,builds,"stable identity avoids rebuild")
eq(a.A.rxDeadVoiceLatched,true,"stable identity preserves latch")
t.rssi=0;t:step(true)
eq(auto.ready,false,"RSSI dropout unready")
eq(a.OPT.heliType,2,"dropout retains type")
eq(a.name(),"RAW 700N","dropout retains FC identity")
t.rssi=100;t:settle(true)
eq(a.A.rxDeadVoiceLatched,true,"brief dropout preserves latch")
eq(t.builds,builds,"brief dropout avoids rebuild")
t:disconnect();t:step(true);opts.Theme=2;t.api.update(t.widget,opts)
eq(a.OPT.heliType,2,"theme edit retains disconnected Nitro")
eq(auto.ready,false,"theme edit cannot resolve identity")
t.host.state="initializing";t.rssi=100;t.provider.modelName="Old Electric";t:settle(false)
eq(auto.ready,false,"stale initialization name ignored")
t:connect("RAW 700");builds=t.builds;t:step(false)
eq(auto.ready,false,"new identity immediately unready")
eq(t.widget.profileWasConnected,false,"confirmation blocks profiles")
t:settle(false)
eq(a.OPT.heliType,1,"background resolves Electric")
eq(a.A.rxDeadVoiceLatched,false,"new aircraft clears prior latch")
eq(a.D.rxVoltage,nil,"Electric clears receiver voltage")
eq(t.builds,builds,"background never builds UI")
eq(t.widget.layoutSignature,nil,"background invalidates layout")
eq(t.widget.profileWasConnected,true,"resolved Electric profiles enabled")
t:step(true);eq(t.builds,builds+1,"foreground builds once")
eq(t.hostCalls,0,"external host never called")
eq(t.queueCalls,0,"external queue never pumped")

-- Unstable candidates and backwards clock cannot shortcut confirmation.
t:connect("Candidate Electric");t:step(false)
t:connect("Candidate Nitro");t:step(false)
t:step(false,-100);eq(auto.ready,false,"rollback unresolved")
t:settle(false);eq(auto.name,"Candidate Nitro","stable candidate accepted")
a.A.rxDeadVoiceLatched=true;t:connect("Other Nitro");t:step(false);t:settle(false)
eq(a.A.rxDeadVoiceLatched,false,"same-type new identity resets session")
for selected=1,3 do
  opts.HeliType=selected;t.api.update(t.widget,opts)
  t:connect(selected==2 and "RAW Electric" or "RAW Nitro");t:settle(true)
  eq(a.OPT.heliType,selected,"manual mode overrides FC")
  eq(a.OPT.autoHeliType,false,"manual disables Auto")
end
opts.CountSrc=2;opts.HeliType=3;t.api.update(t.widget,opts)
eq(a.OPT.flightCounter,1,"OMP forces effective local counter")
eq(opts.CountSrc,2,"OMP preserves saved FC preference")
opts.HeliType=4;t.api.update(t.widget,opts)
eq(a.OPT.flightCounter,2,"Auto restores saved FC counter")
eq(auto.ready,false,"re-enabling Auto reconfirms")
t:settle(true);eq(a.OPT.heliType,2,"Auto after OMP")
for _,invalid in ipairs({0,6,-1,1.5,3.5,4.5,5.5}) do
  opts.HeliType=invalid;t.api.update(t.widget,opts)
  eq(a.OPT.heliType,1,"invalid choice becomes Electric "..tostring(invalid))
  eq(a.OPT.autoHeliType,false,"fraction cannot enable Auto")
end

local blank=fixture();blank:connect(" \t");blank:settle(true)
eq(blank.audit.AUTO_HELI.ready,false,"blank FC name unresolved")
eq(blank.audit.AUTO_HELI.name,nil,"TX cannot substitute FC name")
eq(blank.audit.A.battAlertPrevPct,nil,"blank identity pauses warnings")

-- Publish during embedded service, and verify invalidation before next pump.
local embedded=fixture(4,1,true)
embedded.rssi=100
embedded.onHost=function() embedded:connect("Embedded Nitro") end
embedded:step(true)
eq(embedded.audit.AUTO_HELI.ready,false,"same-callback publication starts confirmation")
embedded:settle(true)
eq(embedded.audit.OPT.heliType,2,"embedded publication resolves")
eq(embedded.hostCalls,5,"embedded background once per callback")
local owned={command=176};local foreign={command=10};local pending={command=175}
embedded.queue.currentMessage=owned;embedded.queue.messageQueue={foreign,pending}
embedded.widget.profileOperation={kind="select",queue=embedded.queue,messages={owned,pending}}
embedded:connect("New Electric")
embedded.onQueue=function(q)
  eq(q.currentMessage,owned,"active owned transaction preserved")
  eq(#q.messageQueue,1,"old pending work removed before pump")
  eq(q.messageQueue[1],foreign,"foreign pending preserved")
  eq(embedded.widget.profileOperation,nil,"old operation invalidated before pump")
end
embedded:step(false);embedded.onQueue=nil

local counts=fixture();local ca=counts.audit
counts.rssi=100;__mock.timer.value=25;counts:settle(false)
eq(ca.cache()["Shared Heli"],nil,"unresolved cannot count generic TX key")
__mock.timer.value=0;counts:connect("Aircraft A");counts:settle(false)
__mock.timer.value=25;counts:step(false)
eq(ca.cache()["Aircraft A"],1,"first FC identity counted")
counts:disconnect();counts:step(false)
__mock.timer.value=0;counts:connect("Aircraft B");counts:settle(false)
__mock.timer.value=25;counts:step(false)
eq(ca.cache()["Aircraft B"],1,"second same-type FC counted")
eq(ca.cache()["Aircraft A"],1,"first FC count retained")
eq(ca.cache()["Shared Heli"],nil,"TX key not written")
counts:settle(false)
assert(string.find(fs.files["/flights-count.csv"] or "","Aircraft A,1",1,true),"first identity persisted")
assert(string.find(fs.files["/flights-count.csv"] or "","Aircraft B,1",1,true),"second identity persisted")

-- Name-derived image lookup follows confirmed identity, including disconnect.
local picture=fixture();picture:connect("Picture Electric");picture:settle(false)
local png="\137PNG\r\n\26\n".."\0\0\0\13IHDR".."\0\0\0\100\0\0\0\100"..string.rep("\0",30)
fs.files["/IMAGES/Picture Electric.png"]=png
fs.files["/IMAGES/Second Electric.png"]=png
eq(picture.audit.image(),"/IMAGES/Picture Electric.png","image uses FC identity")
picture:disconnect();picture:step(false)
eq(picture.audit.image(),"/IMAGES/Picture Electric.png","disconnect retains identity image")
picture:connect("Second Electric");picture:settle(false)
eq(picture.audit.image(),"/IMAGES/Second Electric.png","same-type identity invalidates image cache")

-- Persist an already-counted flight despite unresolved Auto identity.
local dirty=fixture();dirty:connect("Dirty Electric");dirty:settle(false)
fs.online=false
__mock.timer.value=25;dirty:step(false)
eq(dirty.audit.cache()["Dirty Electric"],1,"count retained after storage failure")
dirty:disconnect();dirty:step(false)
eq(dirty.audit.AUTO_HELI.ready,false,"dirty save test is unresolved")
fs.online=true;dirty:step(false,501)
assert(string.find(fs.files["/flights-count.csv"] or "","Dirty Electric,1",1,true),"unresolved Auto must finish dirty save")

-- FC count admissions await identity; Nitro diagnostics still work normally.
local fc=fixture(4,2)
fc.provider.useApi=function(name)
  if name=="mspFlightStats" then return {read=function(callback,context)
    fc.queue:add({command=14,processReply=callback,context=context})
  end} end
end
fc.rssi=100;fc:settle(false)
for _,request in ipairs(fc.requests) do eq(request.command~=14,true,"unresolved blocks FC counter") end
fc:connect("Count Nitro");fc:settle(false)
fc:step(false,160)
local commands={}
for _,request in ipairs(fc.requests) do commands[request.command]=true end
eq(commands[175],nil,"Nitro does not request battery profile")
eq(commands[32],nil,"Nitro does not request capacities")
eq(commands[176],nil,"type detection never selects profile")
eq(commands[250],nil,"type detection never saves EEPROM")
-- The synthetic queue does not deliver replies; release prior diagnostics so
-- the retained 150-tick flight-stat settle can admit its independent request.
fc.queue.messageQueue={};fc.widget.armingStatusOperation=nil;fc.widget.armingStatusPending=false
fc:step(false,160)
commands={};for _,request in ipairs(fc.requests) do commands[request.command]=true end
eq(commands[14],true,"resolved Nitro permits FC count read")

-- Same FC text cannot reuse confirmation after identity/container changes.
local replaced=fixture();replaced:connect("Same Nitro");replaced:settle(false)
local ra=replaced.audit
ra.A.rxDeadVoiceLatched=true
__mock.modelFilename="other.yml"
eq(ra.AUTO_HELI.current(),false,"TX filename change invalidates callback eligibility immediately")
local oldModelWidget=replaced.widget
replaced:step(false)
eq(ra.owner.current(oldModelWidget),false,"previous model widget loses ownership")
eq(oldModelWidget.kseInitialized,false,"previous model background retires the old session")
eq(ra.A.rxDeadVoiceLatched,true,"previous model background cannot start the new session")
-- EdgeTX recreates widgets when selecting a saved model while Lua globals live on.
replaced.widget=replaced.api.create({x=0,y=0,w=LCD_W,h=LCD_H},replaced.opts)
replaced:step(true,1)
eq(ra.owner.current(replaced.widget),true,"new model foreground owns before lease expiry")
eq(ra.AUTO_HELI.ready,false,"recreated model widget restarts confirmation")
replaced:settle(false)
eq(ra.AUTO_HELI.ready,true,"new TX filename confirms")
eq(ra.A.rxDeadVoiceLatched,false,"new TX filename resets session")
ra.A.rxDeadVoiceLatched=true
local oldQueue=replaced.queue
local newQueue={messageQueue={},add=oldQueue.add,isProcessed=oldQueue.isProcessed,
  processQueue=oldQueue.processQueue,clear=oldQueue.clear}
replaced.queue=newQueue;replaced.provider.mspQueue=newQueue
eq(ra.AUTO_HELI.current(),false,"queue replacement immediately invalidates eligibility")
replaced:step(false);eq(ra.AUTO_HELI.ready,false,"same-name new queue reconfirms")
replaced:settle(false);eq(ra.A.rxDeadVoiceLatched,false,"new queue resets session")
ra.A.rxDeadVoiceLatched=true
replaced.host={state="disarmed",background=function() error("external host must not be called") end}
replaced.provider.widget=replaced.host
eq(ra.AUTO_HELI.current(),false,"host replacement immediately invalidates eligibility")
replaced:step(false);eq(ra.AUTO_HELI.ready,false,"same-name new host reconfirms")
replaced:settle(false);eq(ra.A.rxDeadVoiceLatched,false,"new host resets session")
local newProvider={apiVersion=12.09,rfToolApiVersion=1,modelName="Same Nitro",
  widget=replaced.host,mspQueue=replaced.queue,registerWidget=function() end}
rf2=newProvider;replaced.provider=newProvider
eq(ra.AUTO_HELI.current(),false,"provider replacement immediately invalidates eligibility")
replaced:step(false);eq(ra.AUTO_HELI.ready,false,"same-name new provider reconfirms")
replaced:settle(false);eq(ra.AUTO_HELI.ready,true,"new provider eventually confirms")

-- Unchanged Auto state retains the engine's 10 Hz telemetry limit.
local cadence=fixture();cadence:step(false)
local sampled=cadence.audit.A.lastDataTick
cadence:step(false,9)
eq(cadence.audit.A.lastDataTick,sampled,"unchanged unresolved name respects 10 Hz cap")
cadence:step(false,1)
eq(cadence.audit.A.lastDataTick,sampled+10,"unresolved telemetry resumes at 10 ticks")
cadence:connect("Cadence Nitro");cadence:settle(false)
local infer=cadence.audit.AUTO_HELI.infer
local inferences=0
cadence.audit.AUTO_HELI.infer=function(name) inferences=inferences+1;return infer(name) end
sampled=cadence.audit.A.lastDataTick
cadence:step(false,9)
eq(cadence.audit.A.lastDataTick,sampled,"stable confirmed name respects 10 Hz cap")
cadence:step(false,1)
eq(cadence.audit.A.lastDataTick,sampled+10,"confirmed telemetry resumes at 10 ticks")
eq(inferences,0,"stable identity avoids repeated inference")
cadence:connect("Cadence Electric");cadence:step(false,1)
eq(cadence.audit.A.lastDataTick,__mock.now,"changed candidate immediately refreshes telemetry")
eq(cadence.audit.AUTO_HELI.ready,false,"changed candidate immediately clears readiness")
cadence:step(false,30)
eq(inferences,1,"new stable identity inferred once")
cadence.audit.AUTO_HELI.infer=infer

-- Duplicate instances must not clear the active Auto session or options.
local owner=fixture();owner:connect("Owner Nitro");owner:settle(false)
owner.audit.A.rxDeadVoiceLatched=true
local duplicateOptions={HeliType=1,CountSrc=1,Theme=1}
local duplicate=owner.api.create({w=LCD_W,h=LCD_H},duplicateOptions)
owner.api.update(duplicate,duplicateOptions);owner.api.background(duplicate)
eq(owner.audit.AUTO_HELI.ready,true,"same-module duplicate preserves Auto readiness")
eq(owner.audit.AUTO_HELI.name,"Owner Nitro","duplicate preserves Auto identity")
eq(owner.audit.OPT.heliType,2,"duplicate preserves resolved type")
eq(owner.audit.A.rxDeadVoiceLatched,true,"duplicate preserves warning latch")
local other=dofile(otherDashboardPath)
local otherWidget=other.create({w=LCD_W,h=LCD_H},owner.opts)
other.update(otherWidget,owner.opts);other.background(otherWidget)
eq(owner.audit.AUTO_HELI.ready,true,"cross-variant duplicate preserves readiness")
__mock.now=__mock.now+501;other.refresh(otherWidget,nil,nil)
eq(other.audit.AUTO_HELI.ready,false,"takeover requires fresh confirmation")
__mock.now=__mock.now+30;other.background(otherWidget)
eq(other.audit.AUTO_HELI.ready,true,"new owner confirms FC identity")
eq(other.audit.AUTO_HELI.name,"Owner Nitro","new owner uses FC name")
-- Footer status must update independently of the 10 Hz telemetry cadence.
local function footer(t, expected, message)
  eq(t.widget.profileStatusForDisplay,expected,message.." shared status")
  local found
  for _,item in ipairs(t.labels) do
    local text=item.properties.text
    if type(text)=="function" then text=text() end
    if not item.hidden and type(text)=="string" then
      local suffix=string.match(text," %- (ARMED)$")
        or string.match(text," %- (DISARMED)$") or string.match(text," %- (CONNECTED)$")
      if suffix then found=suffix end
    end
  end
  eq(found,expected,message.." rendered status")
end
for _,mode in ipairs({1,2,4}) do
  for counter=1,2 do
    local f=fixture(mode,counter)
    f:connect("Footer Nitro");f:settle(true)
    footer(f,"DISARMED","confirmed disarm")
    local builds=f.builds
    local requests=#f.requests
    f.host.state="armed";__mock.values.ARM.value=1;f:step(true,1)
    footer(f,"ARMED","arm before next telemetry sample")
    eq(#f.requests,requests,"armed footer adds no request")
    eq(f.builds,builds,"arm status retains UI objects")
    -- Unchanged RF ARM updates roughly every 3 seconds. The short EdgeTX
    -- fresh pulse must not make either footer alternate with CONNECTED.
    for tick=0,600,10 do
      __mock.values.ARM.fresh=tick%300<30
      f:step(true,10)
      assert(f.widget.profileStatusForDisplay=="ARMED","armed footer flickers between ARM updates")
    end
    footer(f,"ARMED","armed between normal telemetry updates")
    eq(#f.requests,requests,"normal armed telemetry gaps admit no MSP")
    __mock.values.ARM.fresh=true
    f.host.state="disarmed";f:step(true,1)
    footer(f,"CONNECTED","contradictory host does not claim disarm")
    __mock.values.ARM.value=2;f:step(true,1)
    footer(f,"DISARMED","only ARM bit zero denotes arming")
    __mock.values.ARM.fresh=false;f:step(true,1)
    footer(f,"DISARMED","current ARM between updates")
    for tick=0,600,10 do
      __mock.values.ARM.fresh=tick%300<30
      f:step(true,10)
      assert(f.widget.profileStatusForDisplay=="DISARMED","disarmed footer flickers between ARM updates")
    end
    footer(f,"DISARMED","disarmed across normal telemetry updates")
    __mock.values.ARM.fresh=true;__mock.values.ARM.current=false;f:step(true,1)
    footer(f,"CONNECTED","noncurrent ARM")
    __mock.values.ARM.current=true
    for _,value in ipairs({-1,0.5,256,"invalid"}) do
      __mock.values.ARM.value=value;f:step(true,1)
      footer(f,"CONNECTED","invalid ARM byte "..tostring(value).." mode "..mode.." counter "..counter)
    end
    local sensor=__mock.values.ARM;__mock.values.ARM=nil;f:step(true,1)
    footer(f,"CONNECTED","missing ARM")
    __mock.values.ARM=sensor;sensor.value=0
    f.host.state="connected";f:step(true,1)
    footer(f,"CONNECTED","initial RF connection is not confirmed disarm")
    f.host.state="disarmed";f:step(true,1)
    f.rssi=0;f:step(true,1)
    footer(f,nil,"link loss clears retained host state immediately")
    f.rssi=100;f:step(true,1)
    footer(f,"DISARMED","link recovery")
    f.host.state=nil;f:step(true,1)
    footer(f,nil,"missing live host state cannot reuse cached state")
    f.host.state="initializing";f:step(true,1)
    footer(f,nil,"initializing host")
    f.host.state="disarmed";f:step(true,1)
    f.host.state="armed";sensor.value=1;f:step(false,1);f:step(true,1)
    footer(f,"ARMED","background transition renders on foreground return")
    rf2=nil;f:step(true,1)
    footer(f,nil,"removed provider")
    rf2={apiVersion=12.09,rfToolApiVersion=1,widget={state="initializing"},
      mspQueue=f.queue,registerWidget=function() end}
    f:step(true,1);footer(f,nil,"replacement provider")
  end
end
local omp=fixture(3,2);omp:connect("M2 Fixture");omp:settle(true)
footer(omp,nil,"OMP does not display RF state")
eq(#omp.requests,0,"OMP footer does not start RF work")
-- Fuel reminder uses the real Timer 1 and lifecycle in both counter modes.
local function fuelEvents(kind)
  local count=0
  for _,event in ipairs(__mock.events) do
    if event==kind then count=count+1 end
  end
  return count
end
local function fuelFixture(selection,counter,initial,missingClip)
  local f=fixture(selection,counter)
  if not missingClip then fs.files["/WIDGETS/"..variant.."/BatterySounds/fuel.wav"]="audio" end
  __mock.timer={start=0,value=initial or 0}
  f:connect(selection==1 and "RAW Electric" or "RAW Nitro");f:settle(false)
  __mock.events={}
  return f
end
local function timerStep(f,value,start,visible)
  __mock.timer={value=value,start=start or 0};f:step(visible)
end
for _,counter in ipairs({1,2}) do
  for _,selection in ipairs({2,4}) do
    local f=fuelFixture(selection,counter)
    eq(f.audit.OPT.heliType,2,"fuel test confirms Nitro")
    eq(#f.api.options,11,"fuel setting retains original ten options")
    f.host.state="armed";__mock.values.ARM.value=1;f:step(false)
    local requests=#f.requests
    timerStep(f,359);f:settle(false)
    eq(fuelEvents("file:fuel.wav"),0,"idle/paused timer cannot reach threshold")
    timerStep(f,360)
    eq(fuelEvents("file:fuel.wav"),1,"hidden Nitro alerts at six minutes")
    eq(fuelEvents("haptic:15"),1,"one queued fuel vibration")
    eq(__mock.hapticFlags,0,"fuel does not replace urgent haptics")
    eq(#f.requests,requests,"fuel threshold while armed admits no MSP")
    timerStep(f,370,nil,true)
    f.opts.Theme=2;f.api.update(f.widget,f.opts);f:step(true)
    f.opts.CountSrc=counter==1 and 2 or 1;f.api.update(f.widget,f.opts)
    f:step(false)
    f.rssi=0;f:step(false);f.rssi=100;f:settle(false)
    f:disconnect();f:step(false);f:connect("RAW Nitro");f:settle(false)
    eq(fuelEvents("file:fuel.wav"),1,"theme/counter/link/reconnect cannot repeat reminder")
    f.opts.HeliType=1;f.api.update(f.widget,f.opts);f:step(false)
    f.opts.HeliType=selection;f.api.update(f.widget,f.opts);f:settle(false)
    eq(fuelEvents("file:fuel.wav"),1,"type toggles cannot rearm reminder")
    timerStep(f,0);timerStep(f,361,nil,true)
    eq(fuelEvents("file:fuel.wav"),2,"timer reset rearms one reminder")
    timerStep(f,390)
    eq(fuelEvents("file:fuel.wav"),2,"no repeated flight reminder")
  end
end
for _,selection in ipairs({1,3,5}) do
  local f=fuelFixture(selection,2)
  timerStep(f,360);timerStep(f,400)
  eq(fuelEvents("file:fuel.wav"),0,"Electric/OMP never get fuel speech")
  eq(fuelEvents("haptic:15"),0,"Electric/OMP never get fuel vibration")
end
local f=fuelFixture(4,2)
f.rssi=0;timerStep(f,360)
eq(fuelEvents("file:fuel.wav"),0,"unidentified Auto waits")
f.rssi=100;f:settle(false)
eq(fuelEvents("file:fuel.wav"),1,"confirmed Nitro delivers pending reminder once")
f=fuelFixture(4,2)
f:connect("RAW Electric");f:settle(false);timerStep(f,360)
f:connect("RAW Nitro");f:settle(false)
eq(fuelEvents("file:fuel.wav"),0,"electric timer run does not become Nitro reminder")
f=fuelFixture(2,2,400);timerStep(f,401)
eq(fuelEvents("file:fuel.wav"),0,"late widget startup has no overdue replay")
timerStep(f,0);timerStep(f,360)
eq(fuelEvents("file:fuel.wav"),1,"late startup becomes eligible after reset")
-- A replacement widget, including the other variant, does not replay the run.
local replacement=dofile(otherDashboardPath)
local replacementOptions={}
for _,option in ipairs(replacement.options) do replacementOptions[option[1]]=option[3] end
replacementOptions.HeliType=2;replacementOptions.CountSrc=2
local other=replacement.create({x=0,y=0,w=LCD_W,h=LCD_H},replacementOptions)
__mock.now=__mock.now+501;replacement.refresh(other,nil,nil)
eq(fuelEvents("file:fuel.wav"),1,"widget takeover cannot replay expired timer")
f=fuelFixture(2,2)
timerStep(f,600,600);timerStep(f,241,600)
eq(fuelEvents("file:fuel.wav"),0,"countdown before six minutes")
timerStep(f,240,600)
eq(fuelEvents("file:fuel.wav"),1,"countdown uses elapsed flight time")
timerStep(f,600,600);timerStep(f,230,600)
eq(fuelEvents("file:fuel.wav"),2,"countdown reset rearms reminder")
f=fuelFixture(2,2)
f.audit.OPT.simTelemetry=true;timerStep(f,360)
eq(fuelEvents("file:fuel.wav"),0,"simulation is silent")
f.audit.OPT.simTelemetry=false;timerStep(f,0)
local realTimer=model.getTimer
model.getTimer=function() error("timer unavailable") end
f:step(false);eq(fuelEvents("file:fuel.wav"),0,"failed timer read is silent")
model.getTimer=realTimer;timerStep(f,360)
eq(fuelEvents("file:fuel.wav"),1,"valid timer recovers")
f=fuelFixture(2,2,0,true)
playTone=function(hz,length,pause,flags)
  __mock.events[#__mock.events+1]="tone:"..tostring(hz)
  eq(flags,0,"fallback tone is queued")
end
timerStep(f,360)
eq(fuelEvents("file:fuel.wav"),0,"missing voice clip is not requested")
eq(fuelEvents("tone:1500"),1,"first fallback tone")
eq(fuelEvents("tone:2000"),1,"second fallback tone")
eq(fuelEvents("haptic:15"),1,"missing clip retains vibration")
timerStep(f,370)
eq(fuelEvents("tone:1500"),1,"fallback cannot loop")
playTone=nil
-- Slot 11 changes deliberately from a duration string to a native choice;
-- the original ten settings stay in place. Native type migration resets it.
f=fuelFixture(2,2)
eq(f.api.options[11][1],"FuelCheck","fuel option is last")
eq(f.api.options[11][2],10,"duration uses native CHOICE option")
eq(f.api.options[11][3],25,"new widget defaults to six-minute choice")
eq(f.api.translate("FuelCheck","en"),"Fuel Check Timer","native settings label")
local durations=f.api.options[11][4]
eq(#durations,121,"Off plus 120 quarter-minute choices")
eq(durations[1],"Off","explicit Off label")
eq(durations[25],"06:00","default choice displays six minutes")
eq(durations[121],"30:00","last choice displays thirty minutes")
for i,label in ipairs(durations) do
  f.opts.FuelCheck=i;f.api.update(f.widget,f.opts)
  local seconds=(i-1)*15
  eq(f.audit.OPT.fuelCheckSeconds,seconds,"choice maps to elapsed seconds")
  if i>1 then
    eq(label,string.format("%02d:%02d",math.floor(seconds/60),seconds%60),
       "choice labels stay in quarter-minute order")
  end
end
f.opts.FuelCheck=1;f.api.update(f.widget,f.opts)
timerStep(f,359);timerStep(f,360);timerStep(f,1801)
eq(fuelEvents("file:fuel.wav"),0,"zero duration disables speech")
eq(fuelEvents("haptic:15"),0,"zero duration disables vibration")
f.opts.FuelCheck=25;f.api.update(f.widget,f.opts);f:step(false)
eq(fuelEvents("file:fuel.wav"),0,"enabling after threshold does not backfill")
timerStep(f,0);timerStep(f,360)
eq(fuelEvents("file:fuel.wav"),1,"enabled setting works after reset")
f=fuelFixture(4,1)
f.opts.FuelCheck=27;f.api.update(f.widget,f.opts)
timerStep(f,389);eq(fuelEvents("file:fuel.wav"),0,"custom duration not early")
timerStep(f,390);eq(fuelEvents("file:fuel.wav"),1,"minutes and seconds threshold")
timerStep(f,400);eq(fuelEvents("file:fuel.wav"),1,"custom duration does not repeat")
f.opts.FuelCheck=10;f.api.update(f.widget,f.opts);f:step(false)
eq(fuelEvents("file:fuel.wav"),1,"lowering past threshold does not backfill")
timerStep(f,0);timerStep(f,135)
eq(fuelEvents("file:fuel.wav"),2,"changed duration rearms after reset")
for _,duration in ipairs({{2,15},{5,60},{26,375},{120,1785},{121,1800}}) do
  f=fuelFixture(2,2);f.opts.FuelCheck=duration[1];f.api.update(f.widget,f.opts)
  eq(f.audit.OPT.fuelCheckSeconds,duration[2],"duration selected exactly")
  timerStep(f,0);timerStep(f,duration[2]-1)
  eq(fuelEvents("file:fuel.wav"),0,"duration boundary not early")
  timerStep(f,duration[2])
  eq(fuelEvents("file:fuel.wav"),1,"duration boundary works")
end
f=fuelFixture(2,2)
f.opts.FuelCheck=4;f.api.update(f.widget,f.opts)
timerStep(f,600,600);timerStep(f,556,600)
eq(fuelEvents("file:fuel.wav"),0,"seconds-only countdown not early")
timerStep(f,555,600)
eq(fuelEvents("file:fuel.wav"),1,"seconds-only countdown alert")
timerStep(f,600,600);timerStep(f,555,600)
eq(fuelEvents("file:fuel.wav"),2,"seconds-only countdown reset")
f=fuelFixture(2,2)
for _,invalid in ipairs({0,-1,1.5,25.5,122,360,math.huge,-math.huge,0/0,
                         "", " ", "25", "06:00", "06:30", true, false, {}}) do
  f.opts.FuelCheck=invalid;f.api.update(f.widget,f.opts)
  eq(f.audit.OPT.fuelCheckSeconds,0,"invalid or legacy choice disables reminder")
  timerStep(f,0);timerStep(f,390)
end
eq(fuelEvents("file:fuel.wav"),0,"invalid duration never announces")
eq(fuelEvents("haptic:15"),0,"invalid duration never vibrates")
-- A native type reset can supply zero before defaults have been parsed; after
-- defaults are parsed it can supply 25. Neither reinterprets the old text.
f.opts.FuelCheck=0;f.api.update(f.widget,f.opts)
eq(f.audit.OPT.fuelCheckSeconds,0,"migrated zero field stays safely off")
f.opts.FuelCheck=27;f.api.update(f.widget,f.opts)
timerStep(f,0);timerStep(f,390)
eq(fuelEvents("file:fuel.wav"),1,"reselected duration works after migration")
f.opts.FuelCheck=25;f.api.update(f.widget,f.opts);f:step(false)
eq(fuelEvents("file:fuel.wav"),1,"migrated default cannot backfill overdue reminder")
f.opts.FuelCheck=nil;f.api.update(f.widget,f.opts)
eq(f.audit.OPT.fuelCheckSeconds,360,"missing old-firmware setting uses six minutes")
local originalVersion=getVersion
for _,ver in ipairs({{2,11,5,10},{2,12,1,11},{2,12,4,11},{3,0,0,11}}) do
  getVersion=function() return "test", "radio", ver[1],ver[2],ver[3],"EdgeTX" end
  f=fuelFixture(2,2)
  eq(#f.api.options,ver[4],"version-compatible option count")
  eq(f.api.options[10][1],"CountSrc","original last option retains its slot")
  if ver[4]==10 then
    eq(f.opts.FuelCheck,nil,"old firmware has no unsupported option")
    timerStep(f,360)
    eq(fuelEvents("file:fuel.wav"),1,"old firmware retains fixed six-minute reminder")
  end
end
getVersion=nil;f=fixture(2,2)
eq(#f.api.options,10,"missing version API keeps conservative descriptor")
getVersion=originalVersion

-- Radio regression: switch a connected TREX 700N from Electric to Auto.
-- Default firmware has no optional string metatable (asserted above).
local switched=fixture(1,2)
switched:connect("TREX 700N");switched:settle(true)
switched.opts.HeliType=4;switched.api.update(switched.widget,switched.opts)
switched:settle(true)
eq(switched.audit.AUTO_HELI.ready,true,"Electric-to-Auto confirms TREX name")
eq(switched.audit.OPT.heliType,2,"Electric-to-Auto selects Nitro")
eq(switched.audit.name(),"TREX 700N","Electric-to-Auto displays FC name")
eq(switched.widget.profileWasConnected,false,"Nitro ends Electric profile session")
eq(switched:hasText("BATTERY PROFILE LOCKED"),false,"Nitro hides profile lock")
print(tostring(assertions).." Auto/footer/fuel lifecycle assertions; real render callbacks exercised")
