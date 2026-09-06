-- Real lifecycle and render functions; only EdgeTX/LVGL/RF boundaries mocked.
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
eq(#t.api.options,10,"ten persisted options")
eq(table.concat(t.api.options[4][4],","),"Electric,Nitro,OMPHOBBY,Auto","choice values")
eq(t.api.options[4][3],1,"Electric default")
for name,expected in pairs({["RAW 700N"]=2,["RAW 700n  "]=2,["RAW nItRo\t"]=2,
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
for _,invalid in ipairs({0,5,-1,1.5,3.5,4.5}) do
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
replaced:step(false);eq(ra.AUTO_HELI.ready,false,"TX filename change restarts confirmation")
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
print(tostring(assertions).." Auto lifecycle assertions; real render callbacks exercised")
