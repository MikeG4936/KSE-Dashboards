-- Mock native boundaries only. RF_SOURCE is actual pinned upstream Lua after
-- the official release minimizer, unless the runner explicitly selects raw.
bit32={bor=function(a,b)return a|b end,band=function(a,b)return a&b end,
  bxor=function(a,b)return a~b end,lshift=function(a,b)return a<<b end,
  rshift=function(a,b)return a>>b end,btest=function(a,b)return a&b~=0 end,
  extract=function(a,f,w)return (a>>f)&((1<<(w or 1))-1) end}
INVERS=0;BLINK=0;STDSIZE=0;SMLSIZE=1;MIDSIZE=2;DBLSIZE=3;XXLSIZE=4;TINSIZE=5
do
  local inherited=getmetatable(_G).__index
  getmetatable(_G).__index=setmetatable({CENTER=4,RIGHT=8},{__index=inherited})
end
UNIT_RAW=0;UNIT_VOLTS=1;UNIT_AMPS=2;UNIT_MAH=3;UNIT_PERCENT=4;UNIT_RPMS=5
UNIT_CELSIUS=6;UNIT_DEGREE=7;UNIT_METERS=8;UNIT_METERS_PER_SECOND=9;UNIT_G=10
serialWrite=function() end
playTone=function() end
getRtcTime=function() return 1792440000 end
sportTelemetryPush=function() return nil end
ghostTelemetryPush=function() return nil end
lcd.sizeText=function(text) return #text*8,16 end
lcd.clear=function() end
lcd.drawText=function() end
local gv={}
model.getGlobalVariable=function(a,b) return gv[a..":"..b] or 0 end
model.setGlobalVariable=function(a,b,value) gv[a..":"..b]=value end
model.getInfo=function() return {name=__mock.modelName,filename="shared.yml"} end
model.setInfo=function(info) __mock.modelName=info.name end
model.resetTimer=function() __mock.timer={start=0,value=0} end
model.setTimer=function(_,timer) __mock.timer=timer end
__mock.now=1000;__mock.modelName="Shared Heli";__mock.values={};__mock.rssi=100
fs.files={["/WIDGETS/"..variant.."/default.png"]=defaultImage}
local id=100
for name,value in pairs({Hspd=0,Tspd=0,Vbec=7.6,ARM=0,RQly=100,["Cel#"]=6,
    Vcel=4,Vbat=24,["Bat%"]=100,Curr=0,Capa=0,Tesc=25,Gov=0,
    ["BAT#"]=1,["PID#"]=1,["RTE#"]=1,["tx-voltage"]=8.1,TPWR=100}) do
  id=id+1;local item={id=id,value=value}
  __mock.values[name]=item;__mock.values[id]=item
end
local loaded={}
loadScript=function(path)
  -- A successfully compiled installation stores this generated marker as true.
  if path=="/SCRIPTS/RF2/COMPILE/scripts_compiled.lua" then return function() return true end end
  -- Exercise adjustment-teller initialization using an ordinary settings file.
  if path=="/SCRIPTS/RF2/settings.lua" then return function() return {useAdjustmentTeller=1} end end
  local text=RF_SOURCE[path]
  if not text then return nil,"script unavailable: "..path end
  loaded[path]=(loaded[path] or 0)+1
  local name=mode=="combined" and dashboardPath or rfLabel
  return assert(load(text,"@"..name))
end

local objects,dialogChildren,dialogs={},nil,0
local properties={"color","opacity","size","pos","active","endAngle",
  "startAngle","rotation","text","font","align","file"}
local function evaluate(item)
  if item.closed then return end
  local p=item.properties
  if type(p.visible)=="function" then item.hidden=not p.visible() end
  if item.hidden then return end
  for _,key in ipairs(properties) do if type(p[key])=="function" then p[key]() end end
end
local function object(first,second)
  local item={properties=second or first or {}}
  function item:set(values) for key,value in pairs(values) do self.properties[key]=value end end
  function item:show() self.hidden=false end
  function item:hide() self.hidden=true end
  objects[#objects+1]=item;evaluate(item);return item
end
lvgl={clear=function() objects={} end,label=object,rectangle=object,image=object,
  hline=object,vline=object,arc=object,isFullScreen=function()return false end,
  isAppMode=function()return false end}
lvgl.dialog=function(spec)
  dialogs=dialogs+1
  local owned={}
  return {build=function(_,children)
      dialogChildren=children
      for _,child in ipairs(children) do owned[#owned+1]=object(child) end
    end,
    close=function()
      for _,item in ipairs(owned) do item.closed=true end
      dialogChildren=nil;spec.close()
    end}
end
local function dispatch() for _,item in ipairs(objects) do evaluate(item) end end

local selectors={43,60,61,89,88,93,15,3,4,5,6,7,8,95,96,97,90,91,92,99,50}
local activeProfile=1
local function customFrames()
  local entries={{0x1081,2,248},{0x10c0,0,0},{0x10c1,0,0},{0x1201,0,0},
    {0x1200,0},{0x1205,0},{0x1035,0},{0x1011,9,96},{0x1012,0,0},
    {0x1013,0,0},{0x1014,100},{0x1020,6},{0x1021,200},{0x1211,1},
    {0x1212,1},{0x1214,activeProfile},{0x1202,0},{0x1203,0,0,0,0},{0x1204,0},
    {0x1220,0,0,0,0,0,0},{0x10a0,25}}
  local frames={{0,0,1}}
  for _,entry in ipairs(entries) do
    local frame=frames[#frames]
    if #frame+#entry+1>60 then frame={0,0,#frames+1};frames[#frames+1]=frame end
    frame[#frame+1]=entry[1]>>8;frame[#frame+1]=entry[1]&255
    for i=2,#entry do frame[#frame+1]=entry[i] end
  end
  assert(#frames==2 and #frames[1]==58 and #frames[2]==26,"invalid CUSTOM fixture widths")
  return frames
end
local decoded,telemetryWrites=0,0
setTelemetryValue=function(sid,_,_,value,unit,precision,name)
  telemetryWrites=telemetryWrites+1
  if name=="*Cnt" and value>0 then decoded=decoded+1 end
  if name then
    local item=__mock.values[name] or {id=sid}
    item.value=value/(10^(precision or 0));item.current=true;item.fresh=true
    __mock.values[name]=item;__mock.values[item.id]=item
  end
end
local fifo,nextReplies={},{}
local suppressCustom=false
local peakFifo,step,lastReply=0,0,"-"
local sent,txBody,txCommand={},nil,nil
local dropped=0
local function replyPayload(command,payload)
  if command==1 then return {0,12,9}
  elseif command==10 then
    local out={};for i=1,#"RS4 Venom" do out[#out+1]=string.byte("RS4 Venom",i) end;return out
  elseif command==12 then return {0,0,0,0,0,0,0,0,0,0,0,0,0,0}
  elseif command==73 then
    local out={0,1,0,0,0,0,0,1,244,1,8,0}
    for i=1,40 do out[#out+1]=selectors[i] or 0 end;return out
  elseif command==246 or command==250 then return {}
  elseif command==175 then return {activeProfile-1}
  elseif command==176 then
    activeProfile=payload[1]+1;__mock.values["BAT#"].value=activeProfile;return {}
  elseif command==32 then
    local out={};for i=1,27 do out[i]=0 end
    for i=1,6 do out[16+(i-1)*2],out[17+(i-1)*2]=152,8 end;return out
  elseif command==130 then return {152,8,6,0,0,0,0,0}
  elseif command==101 then return {240,1,124,0,35,0,0,0,0,0,0,224,1,10,1,0,26,0,0,0,0,0,2,0,6,0,6,2,4,1}
  elseif command==14 then return {123,1,0,0,100,1,2,0,0,0,0,0,15}
  else error("unhandled real RF MSP command "..command) end
end
crossfireTelemetryPush=function(command,data)
  if command==nil then return true end
  assert(command==0x7c and data[1]==0xc8 and data[2]==0xea,"unexpected CRSF TX envelope")
  if data[3]&0x10~=0 then txBody={};txCommand=nil end
  assert(txBody,"missing MSP TX start")
  for i=4,#data do txBody[#txBody+1]=data[i] end
  if #txBody>=txBody[1]+3 then
    local command=txBody[2];local payload={}
    for i=1,txBody[1] do payload[i]=txBody[i+2] end
    sent[#sent+1]={step=step,command=command,payload=payload}
    local response=replyPayload(command,payload)
    if (scenario=="drop175" and command==175) or (scenario=="drop176" and command==176) then
      dropped=dropped+1
    else
      local data={0xea,0xc8,0x30,#response,command}
      local checksum=#response~command
      for _,byte in ipairs(response) do data[#data+1]=byte;checksum=checksum~byte end
      data[#data+1]=checksum
      assert(#data<=60,"MSP reply exceeds one CRSF payload")
      nextReplies[#nextReplies+1]={0x7b,data,command}
    end
    txBody=nil
  end
  return true
end
crossfireTelemetryPop=function()
  local frame=table.remove(fifo,1)
  if frame then
    if frame[3] then lastReply=tostring(frame[3]) end
    return frame[1],frame[2]
  end
end
local function fillFifo()
  local empty=#fifo==0
  for _,frame in ipairs(nextReplies) do fifo[#fifo+1]=frame end
  nextReplies={}
  if empty and scenario~="normal" and not suppressCustom then
    local frames=customFrames()
    for i=1,4 do fifo[#fifo+1]={0x88,frames[(i-1)%2+1]} end
  end
  local bytes=0
  for _,frame in ipairs(fifo) do bytes=bytes+#frame[2]+2 end
  assert(bytes<=256,"fixture exceeds native telemetry FIFO capacity: "..bytes)
  peakFifo=math.max(peakFifo,bytes)
end

rf2=nil;_G.__KSE_WIDGET_OWNER_V1=nil
local api=dofile(dashboardPath)
local opts={}
for _,option in ipairs(api.options) do opts[option[1]]=option[3] end
opts.HeliType=4;opts.CountSrc=2;opts.MotorSw=99
local function seedHistory(maximum)
  local values={["RS4 Venom"]=7,["Other model"]=17}
  for i=1,198 do values[string.format("M%03d",i)]=i end
  local text=assert(api.audit.Storage.serialize(values))
  if maximum then
    local previous=values.M001;values.M001=nil
    values["M001"..string.rep("x",32768-#text)]=previous
    text=assert(api.audit.Storage.serialize(values));assert(#text==32768)
    fs.files["/flights-count.csv.bak"]=text
  end
  fs.files["/flights-count.csv"]=text
  return values,text
end
local openValues,openText
if scenario=="save200open" then
  opts.CountSrc=1;opts.MinFlight=20
  openValues,openText=seedHistory(true)
end
local widget
local function measured(callback,fn,display)
  lastReply="-"
  local call=function() local result=fn();if display then dispatch() end;return result end
  local cost,result
  if mode=="all" then cost,result=measure(call)
  else
    -- Native press-event budget scope is not established. Measure it separately
    -- without treating this artificial event wrapper as a hard-budget boundary.
    cost,result=measureSource(mode=="rf" and rfLabel or dashboardPath,
      callback=="press6" and 0 or productionBudget,call)
  end
  assert(not widget or not widget.profileRfToolHostError,"host: "..tostring(widget and widget.profileRfToolHostError))
  print("CPU|"..step.."|"..callback.."|"..cost.."|"..(rf2 and rf2.widget and rf2.widget.state or "none")
    .."|"..lastReply.."|"..dialogs.."|"..decoded.."|"..peakFifo)
  if mode=="combined" and callback=="save" and saveTarget>0 then
    assert(cost<=saveTarget,"save exceeds combined dashboard/RF margin: "..cost)
  end
  return result
end
widget=measured("create",function()return api.create({x=0,y=0,w=800,h=480},opts)end)
measured("update",function()api.update(widget,opts)end,true)
local selected,openAt,selectedAfter=false,nil,nil
local activeRetry,foreignMessage,timedOperation
for n=1,160 do
  step=n;__mock.now=__mock.now+20
  fillFifo()
  measured("refresh",function()api.refresh(widget,nil,nil)end,true)
  if dropped>0 and not activeRetry then
    activeRetry=assert(rf2.mspQueue.currentMessage,"dropped reply lost active request")
    timedOperation=assert(widget.profileOperation,"missing KSE operation before timeout")
    foreignMessage={command=222,payload={}}
    rf2.mspQueue:add(foreignMessage)
  end
  if dialogChildren and not openAt and scenario~="drop175" then
    assert(#dialogChildren==9,"expected six profiles plus status/retry/close")
    openAt=n
  end
  if scenario=="save200open" and openAt and n>=openAt+2 then break end
  if openAt and not selected and n>=openAt+2 then
    assert(dialogChildren and dialogChildren[6].active(),"last profile must be selectable")
    selectedAfter=#sent
    measured("press6",dialogChildren[6].press,true)
    selected=true
  end
  if scenario=="drop175" and n>=85 then break end
  -- Selection's 2,000-tick timeout is longer than snapshot's 500 ticks.
  if scenario=="drop176" and selected and n>=openAt+115 then break end
  if selected and scenario~="drop176" and n>=openAt+12
     and widget.profileActive==6 and not widget.profileBusy then break end
end
if scenario=="save200open" then
  assert(openAt and not selected and dialogChildren,"six-profile dialog did not remain open")
elseif scenario~="drop175" then assert(openAt and selected,"six-profile popup/selection never reached") end
if scenario=="drop175" or scenario=="drop176" then
  assert(dropped>=3,"retries were not exercised")
  assert(rf2.mspQueue.currentMessage==activeRetry,"active upstream retry was replaced or canceled")
  assert(rf2.mspQueue.maxRetries==-1,"upstream indefinite retry policy changed")
  local retained=false
  for _,message in ipairs(rf2.mspQueue.messageQueue) do
    if message==foreignMessage then retained=true end
  end
  assert(retained,"foreign queued work was lost during KSE timeout")
  assert(widget.profileOperation~=timedOperation,"KSE operation did not time out while upstream retry survived")
elseif scenario=="save200open" then
  assert(widget.profileActive==1 and not widget.profileBusy,"initial profile snapshot not confirmed")
else
  assert(widget.profileActive==6 and not widget.profileBusy,"final profile not confirmed")
  local stages={176,175,250,130}
  local nextStage=1
  for i=selectedAfter+1,#sent do
    local message=sent[i]
    if message.command==stages[nextStage] then
      if nextStage==1 then assert(message.payload[1]==5,"P6 must use zero-based wire index") end
      nextStage=nextStage+1
    end
  end
  assert(nextStage==#stages+1,"selection did not complete set/verify/EEPROM/capacity stages")
end
assert(rf2 and math.abs(rf2.apiVersion-12.09)<0.001,"real RF startup did not establish API")
if string.find(scenario,"save200",1,true) then
  local values,text=openValues,openText
  if scenario~="save200open" then
    values,text=seedHistory(scenario=="save200max")
    opts.CountSrc=1;opts.MinFlight=20
    measured("local-update",function()api.update(widget,opts)end,true)
  end
  local state=api.audit.store()
  local function sample(label,seconds)
    step=step+1;__mock.now=__mock.now+20;__mock.timer.value=seconds
    fillFifo();measured(label,function()api.refresh(widget,nil,nil)end,true)
  end
  for i=1,30 do
    if not state.loading then break end
    sample("load",0)
  end
  assert(not state.loading and state.cache["RS4 Venom"]==7,"full saved history did not load")
  suppressCustom=scenario=="save200quiet"
  sample("qualify",20)
  assert(state.dirty and state.cache["RS4 Venom"]==8,"actual timer crossing failed")
  local beforeDecoded=decoded
  local saveCallbacks=0
  for _=1,1000 do
    if not state.dirty then break end
    sample("save",20);saveCallbacks=saveCallbacks+1
    assert(not state.error,"save reported a storage error")
    assert(state.cache["RS4 Venom"]==8,"pending save lost or duplicated the qualified count")
    if scenario=="save200open" then
      assert(dialogChildren and widget.profileDialog,"picker closed during overlapping save")
    end
  end
  assert(not state.dirty and saveCallbacks>0,"save did not finish within ordinary callbacks")
  values["RS4 Venom"]=8
  assert(fs.files["/flights-count.csv"]==api.audit.Storage.serialize(values),"wrong saved counts")
  assert(fs.files["/flights-count.csv.bak"]==text,"backup changed")
  if scenario=="save200open" then
    assert(activeProfile==1,"open picker changed the active profile without selection")
    for _,message in ipairs(sent) do assert(message.command~=176,"open picker sent a profile write") end
  end
  assert(suppressCustom or decoded>beforeDecoded,"RF CUSTOM service stopped while saving")
  print("SAVE|"..#text.."|decoded="..(decoded-beforeDecoded).."|callbacks="..saveCallbacks)
end
for path,count in pairs(loaded) do print("LOADED|"..path.."|"..count) end
print("COMPLETE|decoded="..decoded.."|writes="..telemetryWrites.."|dropped="..dropped.."|fifo="..peakFifo)
