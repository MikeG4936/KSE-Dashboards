-- Real generated engine/render/lifecycle callbacks, with retained native object
-- lifetime and public radio/filesystem APIs mocked. No RF Tool or RF packets.
local assertions=0
local function check(ok,message)
  assert(ok,message); assertions=assertions+1
end
__mock.modelFile="model1.yml"
model.getInfo=function() return {name=__mock.modelName,filename=__mock.modelFile} end
EVT_TOUCH_FIRST=100;EVT_TOUCH_BREAK=101;EVT_TOUCH_SLIDE=102;EVT_TOUCH_TAP=103
EVT_VIRTUAL_ENTER_LONG=104;EVT_VIRTUAL_ENTER=105
EVT_VIRTUAL_EXIT=106;EVT_EXIT_BREAK=106
SMLSIZE=0;MIDSIZE=1;DBLSIZE=2;XXLSIZE=3;CENTERED=1
local full=true
local objects,roots={},{}
local generation,clears=0,0
local function object(first,second)
  local spec=second or first or {}
  local item={spec=spec,alive=true,gen=generation}
  function item:set(props)
    assert(self.alive,"engine updated a retired LVGL handle")
    for k,v in pairs(props) do self.spec[k]=v end
  end
  function item:show() assert(self.alive,"show retired handle"); self.hidden=false end
  function item:hide() assert(self.alive,"hide retired handle"); self.hidden=true end
  function item:build(children) self.children=children end
  function item:close() self.alive=false; if self.spec.close then self.spec.close() end end
  objects[#objects+1]=item
  return item
end
lvgl={isFullScreen=function() return full end,
  PAGE_BODY_HEIGHT=LCD_H-(LCD_W==800 and 62 or 45),UI_ELEMENT_HEIGHT=LCD_W==800 and 44 or 32,
  SRC_SWITCH=1,SCROLL_VER=1,SCROLL_OFF=0,
  clear=function()
    for _,o in ipairs(objects) do o.alive=false end
    objects={};roots={};generation=generation+1;clears=clears+1
  end}
for _,kind in ipairs({"label","rectangle","image","hline","vline","arc",
  "page","button","choice","numberEdit","toggle","source","file","dialog"}) do lvgl[kind]=object end
lvgl.build=function(specs)
  roots=specs
  local function add(children)
    for _,spec in ipairs(children) do
      object(spec)
      if spec.children then add(spec.children) end
    end
  end
  add(specs)
  return {}
end
local function find(kind,text)
  for _,item in ipairs(objects) do
    local s=item.spec
    if s.type==kind and (text==nil or s.text==text or s.title==text) then return s end
  end
  error("Missing native control: "..kind.." "..tostring(text))
end
local function press(text) local s=find("button",text); check(not s.active or s.active(),"disabled "..text); s.press() end
local api=dofile(dashboardPath)
local audit=api.audit
-- Retired native options must have no influence, even with different values.
local native={Theme=22,HeliType=2,CountSrc=1,MinFlight=2,MotorSw=100,BattRsv=43,BattVoice=1,
 RxPackMin="66",RxPackMax="84",TxBatt=2,FuelCheck=0}
local oldPath="/KSE/Settings/model-model1.yml.kse"
local oldArtifact="KSE_SETTINGS=1\nmodel=6D6F64656C312E796D6C\nTxBatt=2\n"
fs.files[oldPath]=oldArtifact
for name,value in pairs({Hspd=2200,Tspd=9000,Gov=4,Vbat=45.6,Vcel=3.8,["Cel#"]=12,
 Curr=30,Capa=1200,["Bat%"]=65,Tesc=75,Vbec=7.4,RQly=100,RSSI=100,["PID#"]=1,
 ["RTE#"]=2,RPM=3100,RxBt=7.4,Temp=65,["tx-voltage"]=7.8,ARM=1}) do
 __mock.values[name]={value=value}
end
local costs={}
local function measured(label,fn,...)
  local count,result=measure(fn,...)
  costs[label]=math.max(costs[label] or 0,count)
  check(count<15000,label.." exceeded project instruction margin: "..count)
  return result
end
local w=measured("create",api.create,{x=0,y=0,w=LCD_W,h=LCD_H},native)
check(#api.options==0,"retired native descriptor still exposed")
check(w.options.Theme==1 and w.options.HeliType==1 and w.options.BattRsv==20,
      "old native appearance/functional options affected clean defaults")
check(w.options.CountSrc==2 and w.options.MinFlight==20 and w.options.MotorSw==99,
      "old native counter/source options affected clean defaults")
check(w.options.FuelCheck==25 and w.options.RxPackMin=="6.60" and w.options.TxBatt==nil,
      "old native timing/voltage/fallback options affected clean defaults")
check(w.kseNativeOptions==nil and w.kseConfig.record==nil,"retired settings source still retained")
check(fs.files[oldPath]==oldArtifact,"old prototype artifact changed during creation")
local function refresh(event,touch,label)
  __mock.now=__mock.now+10
  return measured(label or "refresh",api.refresh,w,event or 0,touch)
end
refresh()
check(w.kseSettingsCapable,"settings capabilities not detected")
-- TX gauge range comes only from the transmitter's own settings.
for _,badRange in ipairs({{}, {battMin=8.4,battMax=6.2}, {battMin=0,battMax=8.4},
                         {battMin=6.2,battMax=26}}) do
  __mock.generalSettings=badRange; audit.sensors.txRangeAt=nil
  check(audit.sensors.txBatteryState()==nil,"invalid native TX range used a retired fallback")
end
local generalApi=getGeneralSettings
getGeneralSettings=nil; audit.sensors.txRangeAt=nil
check(audit.sensors.txBatteryState()==nil,"missing native TX range used a retired fallback")
getGeneralSettings=generalApi; __mock.generalSettings={battMin=6.2,battMax=8.4}
audit.sensors.txRangeAt=nil
check(type(audit.sensors.txBatteryState())=="number","valid native TX range no longer fills gauge")
local rfCalls=0
local realService=audit.profiles.service
audit.profiles.service=function(widget,allow,event,touch)
  rfCalls=rfCalls+1
  if widget.kseSettings then check(not allow and event==nil and touch==nil,"settings leaked RF UI input") end
  return realService(widget,allow,event,touch)
end
local function enter()
  refresh(EVT_VIRTUAL_ENTER_LONG,nil,"entry")
  check(w.kseSettings~=nil,"hardware entry failed without BREAK")
  refresh(0,nil,"build")
  check(find("page")~=nil,"settings page missing")
end
local function save()
  press("Save & close")
  refresh(0,nil,"save-start")
  for _=1,8 do
    if not w.kseSettings or not w.kseSettings.job then break end
    refresh(0,nil,"save-step")
  end
end
-- A retained profile modal blocks settings entry until explicitly dismissed.
local closed=0
w.profileDialog=object({close=function() closed=closed+1 end})
refresh(EVT_VIRTUAL_ENTER_LONG)
check(not w.kseSettings,"profile dialog did not retain input ownership")
w.layoutSignature=nil;refresh()
check(closed==1 and not w.profileDialog,"renderer did not close owned modal before clear")
enter();refresh(EVT_VIRTUAL_EXIT)
check(not w.kseSettings,"root-focused short EXIT failed")
-- Configure the local counter through the new editor, never a native payload.
enter()
w.kseSettings.draft.CountSrc=1;w.kseSettings.draft.MinFlight=2
save()
check(not w.kseSettings and w.options.CountSrc==1,"canonical menu counter setup failed")
check(fs.files[oldPath]==oldArtifact,"new settings save touched old prototype artifact")
enter()
local scene=clears
local beforeRf=rfCalls
local beforeCount=audit.count()
__mock.timer.value=1;refresh()
__mock.timer.value=2;refresh()
check(audit.count()==beforeCount+1,"timer counting stopped in settings")
check(rfCalls==beforeRf+2,"RF background servicing stopped in settings")
check(clears==scene,"telemetry rebuilt dashboard over editor")
-- Auto/OMP and RF callbacks can invalidate geometry while the editor is open.
w.layoutSignature=nil;w.kseUiDirty=true;refresh()
check(clears==scene,"invalidated dashboard layout cleared editor")
press("Power & alerts");refresh(0,nil,"page")
local reserve=find("numberEdit")
reserve.set(30)
check(audit.OPT.reservePct==20,"draft changed live options")
press("Nitro setup  >");refresh(0,nil,"page")
local fields={}
for _,o in ipairs(objects) do if o.spec.type=="numberEdit" then fields[#fields+1]=o.spec end end
fields[1].set(830);fields[2].set(840)
save()
check(not w.kseSettings,"successful Save did not close")
check(audit.OPT.reservePct==30 and audit.OPT.rxPackValid,"saved values not applied or 0.10 V gap invalid")
check(w.kseConfig.record~=nil,"save failed to retain shared config")
local countFile=fs.files["/flights-count.csv"]
local retained=reserve.set
retained(40)
check(audit.OPT.reservePct==30,"stale setter changed live settings")
-- No-op save bypasses all selective resets, not just RF transport.
enter()
audit.A.fuelCheckArmed=true;audit.S.maxSpeed=123
local apply=audit.G.updateSettings
local applyCalls=0
audit.G.updateSettings=function(...) applyCalls=applyCalls+1; return apply(...) end
save()
check(applyCalls==0,"no-op Save reapplied options")
check(audit.A.fuelCheckArmed==true and audit.S.maxSpeed==123,"no-op Save reset session")
check(fs.files["/flights-count.csv"]==countFile,"settings save touched count history")
-- EdgeTX update payloads no longer configure KSE or retire an active draft.
enter()
local retainedPage=find("page")
local retainedDraft=w.kseSettings
native.BattRsv=44
api.update(w,native)
check(w.kseSettings==retainedDraft and audit.OPT.reservePct==30,"native update affected editor/config")
check(w.kseNativeOptions==nil,"native update retained retired settings")
retainedPage.back()
refresh()
check(not w.kseSettings,"ignored native update broke normal Back")
-- Theme selection is a draft preview; live options/session stay unchanged.
enter();press("Appearance");refresh(0,nil,"page")
find("choice").set(2);refresh(0,nil,"page")
check(w.options.Theme==1,"theme preview mutated live options")
local s=w.kseSettings
s.draft.BattVoice=1
save()
check(w.options.Theme==2 and w.options.BattVoice==1,"theme save failed")
check(audit.A.fuelCheckArmed==true and audit.S.maxSpeed==123,"theme save reset session")
-- Save failure leaves both applied settings and draft intact.
enter();w.kseSettings.draft.BattRsv=31
fs.faults["write:"..w.kseConfig.path..".tmp"]="silent-short"
save()
check(w.kseSettings and w.kseSettings.draft.BattRsv==31,"failed Save lost draft")
check(audit.OPT.reservePct==30,"failed Save applied draft")
fs.faults={}
find("page").back();refresh()
check(w.kseSettings.page=="leave","dirty Back skipped choice")
press("Discard changes");refresh()
check(not w.kseSettings,"discard failed")
-- A short tap and moving touch do not open settings; a held touch does.
refresh(EVT_TOUCH_FIRST,{x=20,y=20});refresh(EVT_TOUCH_BREAK)
check(not w.kseSettings,"short touch entered settings")
refresh(EVT_TOUCH_FIRST,{x=20,y=20});__mock.now=__mock.now+100
refresh(EVT_TOUCH_SLIDE,{x=70,y=20});refresh(EVT_TOUCH_BREAK)
check(not w.kseSettings,"sliding touch entered settings")
refresh(EVT_TOUCH_FIRST,{x=20,y=20});__mock.now=__mock.now+70;refresh(EVT_TOUCH_BREAK)
check(w.kseSettings~=nil,"long touch failed")
refresh();full=false;api.background(w)
check(not w.kseSettings,"fullscreen loss retained draft")
full=true;refresh()
-- Both variants share functional settings and default unsaved themes to index 1.
local other=dofile(otherDashboardPath)
__mock.now=__mock.now+600
local otherNative={Theme=5,MotorSw=99,BattRsv=7,HeliType=2,CountSrc=2}
local otherW=other.create({x=0,y=0,w=LCD_W,h=LCD_H},otherNative)
other.refresh(otherW,0,nil)
check(otherW.options.BattRsv==30 and otherW.options.HeliType==1,"other variant did not load shared functions")
check(otherW.options.Theme==1,"other variant adopted a retired native theme")
-- Reclaiming original loads only canonical settings and its own saved theme.
__mock.now=__mock.now+600;api.refresh(w,0,nil)
check(w.options.Theme==2 and w.kseNativeOptions==nil,"owner reclaim consulted retired native settings")
-- Cancellation after backup rename cannot persist a draft as the committed main.
enter();w.kseSettings.draft.BattRsv=33;press("Save & close");refresh()
while w.kseSettings.job.phase<5 do refresh() end
local path=w.kseConfig.path
check(fs.files[path]==nil and fs.files[path..".bak"]~=nil,"expected pre-promotion stage")
full=false;api.background(w);full=true;refresh()
enter()
check(w.options.BattRsv==30 and w.kseConfig.source=="backup","interrupted save failed recovery")
find("page").back();refresh()
-- A lost SD file while live never changes the current effective configuration.
local backup=fs.files[path..".bak"];fs.files[path..".bak"]=nil
enter()
check(w.options.BattRsv==30 and not w.kseConfig.writable,"missing saved data reverted live config")
full=false;api.background(w);full=true
fs.files[path..".bak"]=backup
refresh();enter()
local oldSet=find("button","Model setup").press
__mock.modelFile="model2.yml"
local writes=#fs.calls
oldSet()
check(w.kseSettings==nil,"model change did not retire stale session")
check(#fs.calls==writes,"stale model callback performed filesystem work")
__mock.modelFile="model1.yml"
oldSet();check(not w.kseSettings,"A-B-A revived stale session")
for label,cost in pairs(costs) do print("PROFILE|"..label.."="..cost) end
print("PROFILE|assertions="..assertions.." (includes retained-handle checks)")
print("PASS|complete")
