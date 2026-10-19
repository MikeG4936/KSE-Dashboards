-- Exercise production callbacks with the shared native-style CPU fixture.
-- Unit constants are opaque: production compares the public constants only.
UNIT_VOLTS=1;UNIT_AMPS=2;UNIT_RPMS=3;UNIT_MAH=4;UNIT_CELSIUS=5;UNIT_PERCENT=6
local fieldInfo=getFieldInfo
getFieldInfo=function(name)
  if name=="telem1" then return {id=300,name="telem1"} end
  return fieldInfo(name)
end
local t=fixture(5,2)
t.phase="startup";t.sensors={};t.hostCalls=0;t.queueCalls=0;t.loads=0
__mock.values={}
local tx={id=100,value=8.1}
__mock.values["tx-voltage"]=tx;__mock.values[100]=tx
t.host.background=function() t.hostCalls=t.hostCalls+1 end
t.queue.processQueue=function() t.queueCalls=t.queueCalls+1 end
loadScript=function() t.loads=t.loads+1;error("OMP must not load RF Tool") end
model.setInfo=function() error("OMP must not rename the saved model") end
model.getSensor=function(index)
  if index<0 or index>=sensorSlots then return nil end
  return t.sensors[index] or {type=0,name="",unit=0,id=0,instance=0}
end
function t:sensor(index,name,value,nativeId,unit)
  local id=300+3*index
  local item={id=id,value=value}
  self.sensors[index]={name=name,type=0,unit=unit or UNIT_VOLTS,id=nativeId or 0,instance=0}
  __mock.values[name]=item;__mock.values[id]=item
  return item
end
t.rx=t:sensor(1,"RxBt",7.6,0x08)
t.cell=t:sensor(7,"Volt",3.8,0x80FE)
t.rpm=t:sensor(12,"RPM",0,0x0C,UNIT_RPMS)
t:sensor(15,"Curr",0,0,UNIT_AMPS);t:sensor(20,"Capa",0,0,UNIT_MAH)
t:sensor(22,"Temp",25,0,UNIT_CELSIUS);t:sensor(26,"RQly",100,0,UNIT_PERCENT)
t:sensor(30,"Bat%",80,0,UNIT_PERCENT)
if string.find(scenario,"theme9",1,true) then t.opts.Theme=9 end

function t:callback(label,fn,display)
  local cost,result=measureSource(dashboardPath,cpuBudget,function()
    local value=fn()
    if display then self:dispatch() end
    return value
  end)
  assert(cost>0,"source filter did not observe "..label)
  print("CPU|"..self.phase.."|"..label.."|"..cost)
  if cpuTarget>0 then assert(cost<=cpuTarget,self.phase.." "..label.." exceeds dashboard margin: "..cost) end
  if self.retained then self:checkLayout() end
  return result
end
function t:at(phase,visible,delta)
  self.phase=phase
  self:step(visible,delta)
end
function t:pinLayout()
  local ui=variant=="KSE4" and self.audit.view() or self.widget.ui
  self.retained={builds=self.builds,ui=ui,objects={},geometry={}}
  for i,object in ipairs(self.objects) do self.retained.objects[i]=object end
  -- Dynamic fills change size legitimately. Pin the stable title/image frames.
  for _,object in ipairs({ui.modelName,ui.modelImage}) do
    local p=object.properties
    self.retained.geometry[#self.retained.geometry+1]={object=object,x=p.x,y=p.y,w=p.w,h=p.h}
  end
end
function t:checkLayout()
  local held=self.retained
  assert(self.builds==held.builds,"OMP class confirmation rebuilt the retained screen")
  local ui=variant=="KSE4" and self.audit.view() or self.widget.ui
  assert(ui==held.ui and #self.objects==#held.objects,"OMP replaced retained UI")
  for i,object in ipairs(held.objects) do assert(self.objects[i]==object,"OMP replaced an object") end
  for _,frame in ipairs(held.geometry) do
    local p=frame.object.properties
    assert(p.x==frame.x and p.y==frame.y and p.w==frame.w and p.h==frame.h,"OMP title/image geometry moved")
  end
end
function t:checkUi(cells,count)
  local name=cells==2 and "OMP M1" or "OMP M2"
  assert(self:hasText(name),"rendered OMP identity stale")
  local ui=self.retained.ui
  assert(not ui.modelImage.hidden,"OMP image hidden")
  local file=ui.modelImage.properties.file
  if type(file)=="function" then file=file() end
  local expected=self.namedImages and ("/IMAGES/"..name..".png") or ("/WIDGETS/"..variant.."/default.png")
  assert(file==expected,"retained image did not follow OMP identity")
  assert(self.audit.D.cellsResolved==cells,"retained cell count stale")
  assert(self.audit.D.isLiHV==(cells==2),"M1/M2 chemistry leaked across identity")
  assert(self.audit.count()==count,"OMP selected the wrong flight history")
  local found=false
  for _,item in ipairs(self.objects) do
    local text=item.properties.text
    if not item.hidden and type(text)=="string" and string.find(text,cells.."S",1,true) then found=true end
  end
  assert(found,"rendered battery footer has stale cell count")
end
function t:confirm(cells,visible,prefix)
  self.rx.value=cells*self.cell.value;self.rssi=100
  self:at(prefix.."-candidate",visible,10)
  assert(self.audit.OMP_AUTO.candidate==cells and not self.audit.OMP_AUTO.ready,"candidate missing")
  self:at(prefix.."-confirm",visible,50)
  assert(self.audit.OMP_AUTO.ready and self.audit.name()==(cells==2 and "OMP M1" or "OMP M2"),"OMP confirmation failed")
end
function t:disconnected(visible)
  local oldName=self.audit.name()
  self.rssi=0;self:at("disconnect",visible,10)
  assert(not self.audit.OMP_AUTO.ready and self.audit.count()==nil,"disconnect did not suspend count attribution")
  assert(self.audit.name()==oldName,"disconnect discarded the last confirmed name")
  if visible then
    assert(self:hasText(oldName),"disconnect discarded the displayed name")
    assert(self:hasText("CONNECT OMP"),"disconnect did not render unresolved status")
    local file=self.retained.ui.modelImage.properties.file
    if type(file)=="function" then file=file() end
    assert(file=="/IMAGES/"..oldName..".png","disconnect discarded the last confirmed image")
  end
end
local saving=string.find(scenario,"save-",1,true)==1
local initial=string.find(scenario,"m2",1,true) and 3 or 2
local connected=string.find(scenario,"connected-create",1,true)~=nil
local fresh=string.find(scenario,"fresh",1,true)~=nil or connected
local values={["OMP M1"]=7,["OMP M2"]=17}
if saving then
  for i=1,198 do values[string.format("M%03d",i)]=i end
  local text=assert(t.audit.Storage.serialize(values))
  local old=values.M001;values.M001=nil
  values["M001"..string.rep("x",32768-#text)]=old
end
local original=assert(t.audit.Storage.serialize(values))
if saving then assert(#original==32768,"maximum-byte history must be exact") end
fs.files[historyPath]=original
-- The default asset path is exercised on fresh starts. Identity transitions
-- use distinct filenames with valid real PNG headers, proving retained lookup.
if not fresh then
  t.namedImages=true
  fs.files["/IMAGES/OMP M1.png"]=defaultImage
  fs.files["/IMAGES/OMP M2.png"]=defaultImage
end
if connected then t.rssi=100;t.rx.value=initial*t.cell.value end
t:create();t:update();t:at("initial-refresh",true,10)
-- Initial saved-model preparation may build. Cell-class confirmations may not.
t:pinLayout();t.phase="history-load";t:finishLoad(true)
if not t.audit.OMP_AUTO.ready then
  if t.audit.OMP_AUTO.candidate then t:at("initial-confirm",true,50)
  else t:confirm(initial,true,"initial") end
end
assert(t.audit.OMP_AUTO.ready,"initial confirmation missing")
t:checkUi(initial,initial==2 and 7 or 17)

if fresh then
  t:at("settled",true,10);t:at("settled-hidden",false,10)
elseif saving then
  t:at("qualified-below",true,10)
  __mock.timer.value=25;t:at("qualified-crossing",true,10)
  local state=t.audit.store()
  assert(state.dirty and state.cache["OMP M1"]==8,"real timer did not qualify exactly one M1 flight")
  fs.faults["openw:"..historyPath..".tmp"]=true
  for _=1,200 do
    t:at("failed-save",true,10)
    if state.error and state.nextAttempt>__mock.now then break end
  end
  assert(state.dirty and state.error and state.attempts==1,"expected one failed save attempt")
  fs.faults={}
  local retry=state.nextAttempt
  t:disconnected(true)
  local visible=scenario~="save-retry-confirm-hidden"
  local candidateAtRetry=scenario=="save-retry-candidate-visible"
  t:at("retry-wait",false,retry-__mock.now-(candidateAtRetry and 10 or 60))
  t:confirm(3,visible,"retry")
  -- A successful retry may still be staged. Observe its completion through
  -- callbacks, without assuming a fixed implementation phase count.
  for _=1,200 do
    if not state.dirty then break end
    t:at("retry-progress",visible,10)
  end
  assert(not state.dirty and not state.error,"retry did not persist the pending flight")
  t:at("return-foreground",true,1)
  t:checkUi(3,17)
  values["OMP M1"]=8;assertHistory(t,values)
  assert(fs.files[historyPath]==t.audit.Storage.serialize(values),"save wrote wrong OMP histories")
  assert(fs.files[historyPath..".bak"]==original,"save did not preserve the original backup")
else
  local same=string.find(scenario,"reconnect",1,true)~=nil
  local hidden=string.find(scenario,"hidden",1,true)~=nil
  for _,cells in ipairs(same and {2} or {3,2}) do
    local a=t.audit
    a.S.rpmMax=9999;a.S.currMax=99;a.S.tempMax=99;a.A.flightDeadVoiceLatched=true
    __mock.timer.value=0;t:at("before-disconnect",true,10)
    t:disconnected(true)
    -- A threshold crossed while unresolved must not be credited after confirm.
    __mock.timer.value=25
    t:confirm(cells,not hidden,"reconnect")
    assert(a.A.flightDeadVoiceLatched==same,"same/new class warning reset contract")
    assert(a.S.rpmMax==(same and 9999 or 0),"same/new class extrema contract")
    assert(a.cache()["OMP M1"]==7 and a.cache()["OMP M2"]==17,"unresolved timer crossing was backfilled")
    if hidden then
      assert(t.widget.kseUiDirty,"hidden confirmation lost UI invalidation")
      local tick=a.A.lastDataTick
      t:at("return-foreground",true,1)
      assert(a.A.lastDataTick==tick,"foreground handoff unexpectedly resampled telemetry")
      assert(t.widget.kseUiDirty==nil,"foreground handoff did not consume invalidation")
    end
    t:checkUi(cells,cells==2 and 7 or 17)
    t:at("settled",true,10)
  end
end
assert(t.hostCalls==0 and t.queueCalls==0 and t.loads==0 and #t.requests==0,"OMP touched RF")
assert(t.opts.HeliType==5 and t.opts.CountSrc==2 and t.audit.OPT.heliType==3
       and t.audit.OPT.flightCounter==1,"OMP changed saved options or effective mode")
assert(__mock.modelName=="Shared Heli" and __mock.modelFilename=="shared.yml","OMP changed saved model identity")
