-- Native specifications are inspected as data; focus and drawing remain native
-- radio acceptance, not something this fixture pretends to render.
local m={now=0,fullscreen=true,model="menu-model.yml",owner=true,clears=0,builds=0}
local function noop() end
local common={type="string",x="number",y="number",w="number",h="number",
  font="number",color="number",floating="boolean",active="function"}
local schemas={
  label={text="text"}, rectangle={rounded="number",filled="boolean"},
  button={text="text",textColor="number",cornerRadius="number",press="function"},
  choice={title="text",values="table",get="function",set="function"},
  numberEdit={min="number",max="number",get="function",set="function",display="function"},
  source={get="function",set="function",filter="number"},
  toggle={get="function",set="function"},
  file={get="function",set="function",folder="string",extension="string",maxLen="number",
    hideExtension="boolean",title="text"},
  page={title="text",subtitle="text",backButton="boolean",scrollDir="number",
    scrollBar="boolean",back="function",children="table"},
}
local function validateSpec(spec)
  local schema=assert(schemas[spec.type],"unknown native control type")
  for key,value in pairs(spec) do
    local expected=schema[key] or common[key]
    assert(expected,"unsupported native property "..spec.type.."."..key)
    assert(type(value)==expected or (expected=="text" and (type(value)=="string" or type(value)=="function")),
           "wrong native property type "..spec.type.."."..key)
  end
  for _,child in ipairs(spec.children or {}) do validateSpec(child) end
end
lvgl={PAGE_BODY_HEIGHT=418,UI_ELEMENT_HEIGHT=44,SRC_SWITCH=1,SCROLL_VER=2,
  isFullScreen=function() return m.fullscreen end,
  clear=function() m.clears=m.clears+1; m.tree=nil end,
  build=function(tree)
    for _,spec in ipairs(tree) do validateSpec(spec) end
    m.tree=tree; m.builds=m.builds+1
  end,
  page=noop,button=noop,label=noop,rectangle=noop,choice=noop,numberEdit=noop,
  toggle=noop,source=noop,file=noop,dialog=noop}
LCD_W,LCD_H,SMLSIZE,MIDSIZE=800,480,1,2
EVT_VIRTUAL_ENTER_LONG,EVT_ENTER_LONG=11,12
EVT_VIRTUAL_ENTER,EVT_ENTER_BREAK=13,14
EVT_VIRTUAL_EXIT,EVT_EXIT_BREAK=15,16
EVT_TOUCH_FIRST,EVT_TOUCH_SLIDE,EVT_TOUCH_BREAK=21,22,23
getTime=function() return m.now end
getFieldInfo=function(source)
  if source=="SG" or source==99 then return {id=99,name="SG",desc="Switch G"} end
  if source==100 then return {id=100,name="SF",desc="Switch F"} end
  return {id=source,name="CH1",desc="Channel 1"}
end
WidgetOwner={current=function(widget)
  return m.owner and widget.kseModelFile==m.model
end}
G={name="KSE4",settingsThemes=themes4,settingsPalette=function(theme)
  return {bg=10,panel=20,text=30,dim=40,accent=theme or 1}
end,updateSettings=function(widget,values) widget.options=values; m.applied=(m.applied or 0)+1 end}

-- MODULE INSERTION POINT

local function eq(name,actual,expected)
  assert(actual==expected,name..": expected "..tostring(expected)..", got "..tostring(actual))
  print("PASS|"..name)
end
local function mutations()
  local count=0
  for _,call in ipairs(fs.calls) do
    if string.find(call,"^openw:") or string.find(call,"^mkdir:")
       or string.find(call,"^rename:") or string.find(call,"^del:") then count=count+1 end
  end
  return count
end
local function controls(kind,text)
  local result={}
  local function visit(spec)
    if spec.type==kind and (not text or spec.text==text) then result[#result+1]=spec end
    for _,child in ipairs(spec.children or {}) do visit(child) end
  end
  for _,spec in ipairs(m.tree or {}) do visit(spec) end
  return result
end
local function button(text)
  local found=controls("button",text)
  assert(#found>0,"missing button: "..text)
  return found[1]
end
local function press(w,text)
  button(text).press()
  return Menu.service(w,0)
end
local function back(w)
  controls("page")[1].back()
  return Menu.service(w,0)
end
local function start(native)
  fs.reset(); m.now=0; m.model="menu-model.yml"; m.owner=true; m.fullscreen=true
  m.tree=nil; m.clears=0; m.builds=0
  m.applied=0
  local w={kseOwnerEpoch=1,kseModelFile=m.model,zone={w=LCD_W,h=LCD_H}}
  w.options=Menu.attach(w,native or {MotorSw=99})
  return w
end
local function open(w)
  Menu.service(w,EVT_VIRTUAL_ENTER_LONG)
  assert(w.kseSettings,"entry failed")
  Menu.service(w,0)
  return w.kseSettings
end
local function finish(w)
  for _=1,15 do
    local visible,saved=Menu.service(w,0)
    if saved or not visible then return visible,saved end
    if not w.kseSettings.job then return visible end
  end
  error("menu save did not terminate")
end

eq("native menu capable",Menu.capable(),true)
local functionMap={}
for _,key in ipairs({"isFullScreen","clear","build","page","button","label","rectangle",
                    "choice","numberEdit","toggle","source","file","dialog"}) do
  functionMap[key]=lvgl[key]; lvgl[key]=nil
  eq("missing native control falls back "..key,Menu.capable(),false)
  lvgl[key]=functionMap[key]
end
local version=getVersion
getVersion=function() return "2.12.3","mock",2,12,3 end
local w=start()
eq("unreviewed firmware menu disabled",w.kseSettingsCapable,false)
eq("unreviewed firmware keeps canonical defaults",w.options.MotorSw,99)
eq("unreviewed firmware no settings reads",#fs.calls,0)
eq("unreviewed firmware cannot open menu",Menu.service(w,EVT_VIRTUAL_ENTER_LONG),false)
local nativeLabel=lvgl.label
lvgl.label=function(spec) m.requirement=spec end
eq("unsupported firmware displays requirement",Menu.requirement(w),true)
eq("requirement names exact target version",string.find(m.requirement.text,"2.12.4",1,true)~=nil,true)
local requirementClears=m.clears
Menu.requirement(w)
eq("requirement page allocated once",m.clears,requirementClears)
local nativeClear=lvgl.clear
lvgl.clear=nil; w.kseRequirementDrawn=nil; m.requirement=nil
eq("missing clear safely retains requirement state",Menu.requirement(w),true)
eq("missing clear avoids partially drawing requirement",m.requirement,nil)
eq("missing clear does not mark requirement drawn",w.kseRequirementDrawn,nil)
lvgl.clear=nativeClear
Menu.requirement(w)
eq("restored clear allows requirement to draw",w.kseRequirementDrawn,true)
lvgl.label=nativeLabel
getVersion=version

w=start({MotorSw=100,Theme=21,BattRsv=49,CountSrc=1,MinFlight=-30,
  RxPackMin="660",RxPackMax="840",FuelCheck=0,TxBatt=2})
eq("old native motor option ignored",w.options.MotorSw,99)
eq("old native theme ignored",w.options.Theme,1)
eq("old native reserve ignored",w.options.BattRsv,20)
eq("old native counter ignored",w.options.CountSrc,2)
eq("old native fuel ignored",w.options.FuelCheck,25)
eq("old native voltage ignored",w.options.RxPackMin,"6.60")
eq("native options no longer retained",w.kseNativeOptions,nil)
eq("removed fallback has no runtime value",w.options.TxBatt,nil)

w=start(); m.fullscreen=false
Menu.service(w,EVT_VIRTUAL_ENTER_LONG); Menu.service(w,EVT_VIRTUAL_ENTER)
eq("normal dashboard never opens custom menu",w.kseSettings,nil)
m.fullscreen=true
Menu.service(w,EVT_VIRTUAL_ENTER)
eq("short enter alone keeps dashboard",w.kseSettings,nil)
Menu.service(w,EVT_VIRTUAL_ENTER_LONG)
eq("hold opens without suppressed native release",w.kseSettings~=nil,true)
eq("hold creates no native controls",m.builds,0)
Menu.service(w,0)
eq("next frame creates settings controls",m.builds,1)
eq("open never writes configuration",mutations(),0)
eq("home has four main categories plus transfer",#controls("button"),6)
eq("advanced legacy page removed",#controls("button","Advanced"),0)
local home=controls("page")[1]
eq("native page title",home.title,"KSE4 Settings")
eq("native page has scrolling",home.scrollDir,lvgl.SCROLL_VER)
eq("home first category",controls("button")[1].text,"Model setup")
local oldModelButton=button("Model setup")
local builds=m.builds
oldModelButton.press()
eq("native press only queues intent",w.kseSettings.page,"home")
eq("native press does not rebuild",m.builds,builds)
eq("native press does not write",mutations(),0)
Menu.service(w,0)
eq("refresh handles deferred navigation",w.kseSettings.page,"model")
local heli=controls("choice")[1]
local motor=controls("source")[1]
eq("heli choices use canonical type list",heli.values,SettingsStore.heliTypes)
eq("helicopter menu order",table.concat(heli.values,","),"Electric,Nitro,Auto Elec/Nitro,OMPHOBBY")
heli.set(3)
eq("third visible choice preserves Rotorflight Auto ID",w.kseSettings.draft.HeliType,4)
eq("Rotorflight Auto reads back as third choice",heli.get(),3)
heli.set(4)
eq("fourth visible choice uses automatic OMP ID",w.kseSettings.draft.HeliType,5)
eq("automatic OMP reads back as fourth choice",heli.get(),4)
heli.set(5)
eq("removed fifth choice cannot change draft",w.kseSettings.draft.HeliType,5)
eq("source control uses physical-switch category",motor.filter,lvgl.SRC_SWITCH)
eq("source getter returns native ID",motor.get(),99)
heli.set(2); motor.set(100)
eq("editor changes draft",w.kseSettings.draft.HeliType,2)
eq("editor does not change live settings",w.options.HeliType,1)
eq("editor does not write files",mutations(),0)
eq("old rebuilt button disabled",oldModelButton.active(),false)
oldModelButton.press()
eq("old rebuilt callback cannot queue navigation",w.kseSettings.intent,nil)
back(w); press(w,"Power & alerts")
local reserve=controls("numberEdit")[1]
eq("reserve minimum",reserve.min,0); eq("reserve maximum",reserve.max,50)
reserve.set(33)
local voice=controls("toggle")[1]
voice.set(true)
eq("native toggle maps to canonical boolean field",w.kseSettings.draft.BattVoice,1)
eq("native toggle getter is boolean",voice.get(),true)
press(w,"Nitro setup  >")
local nitro=controls("numberEdit")
eq("nitro uses three numeric editors",#nitro,3)
eq("voltage minimum hundredths",nitro[1].min,400)
eq("voltage maximum hundredths",nitro[1].max,900)
eq("voltage getter converts canonical volts",nitro[1].get(),660)
nitro[1].set(670); nitro[2].set(850); nitro[3].set(25)
eq("voltage edits keep string option type",w.kseSettings.draft.RxPackMin,"6.70")
eq("fuel edit maps quarter-minutes to choice index",w.kseSettings.draft.FuelCheck,26)
eq("fuel display off",nitro[3].display(0),"Off")
eq("fuel display minute-seconds",nitro[3].display(25),"06:15")
back(w); eq("nitro back returns one level",w.kseSettings.page,"power")
back(w); press(w,"Flight counting")
eq("counting retains source setting",controls("choice")[1].get(),2)
controls("numberEdit")[1].set(31)
back(w); press(w,"Appearance")
local theme=controls("choice")[1]
eq("theme choices use authored variant labels",theme.values,G.settingsThemes)
builds=m.builds; theme.set(9)
eq("theme preview deferred",m.builds,builds)
eq("theme preview does not change live theme",w.options.Theme,1)
Menu.service(w,0)
eq("theme preview refresh rebuilds",m.builds,builds+1)
eq("old theme setter disabled after rebuild",theme.active(),false)
theme.set(12)
eq("old theme callback cannot alter draft",w.kseSettings.draft.Theme,9)
back(w); back(w)
eq("dirty exit offers decision page",w.kseSettings.page,"leave")
eq("dirty exit offers discard",button("Discard changes")~=nil,true)
press(w,"Continue editing")
eq("continue keeps draft",w.kseSettings.draft.BattRsv,33)
local saveButton=button("Save & close")
builds=m.builds; saveButton.press()
eq("save press does not write",mutations(),0)
eq("save press does not create job yet",w.kseSettings.job,nil)
Menu.service(w,0)
eq("refresh creates save job",w.kseSettings.job~=nil,true)
eq("saving disables controls",button("Save & close").active(),false)
eq("saving keeps live options",w.options.BattRsv,20)
local visible,saved=finish(w)
eq("successful save closes menu",visible,false)
eq("successful save returns one complete option set",saved.BattRsv,33)
eq("successful save returns theme",saved.Theme,9)
eq("successful save returns source",saved.MotorSw,100)
eq("successful save defers live option application to lifecycle",w.options.BattRsv,20)
eq("successful save requests dashboard rebuild",w.kseUiDirty,true)
eq("successful save persists complete record",w.kseConfig.record.values.BattRsv,33)
w.options=saved
local state=open(w)
fs.calls={}; press(w,"Save & close"); visible,saved=finish(w)
eq("unchanged save closes normally",visible,false)
eq("unchanged save does not rewrite media",mutations(),0)
eq("unchanged save returns existing settings",saved.BattRsv,33)
w.options=saved; open(w); fs.calls={}
back(w)
eq("unchanged back closes directly",w.kseSettings,nil)
eq("unchanged back does not write",mutations(),0)
w.options=saved; state=open(w); press(w,"Power & alerts")
controls("numberEdit")[1].set(41)
back(w); press(w,"Backup & transfer")
press(w,"Export saved KSE settings"); visible,saved=finish(w)
eq("export completion retains settings page",visible,true)
eq("export returns no option update",saved,nil)
eq("export retains unsaved draft",state.draft.BattRsv,41)
eq("export contains saved values only",SettingsStore.readExport(w.kseConfig.filename).values.BattRsv,33)
eq("export does not change live options",w.options.BattRsv,33)
eq("export provides completion feedback",type(state.message),"string")
controls("file")[1].set("missing.kse")
press(w,"Import selected companion")
eq("failed import retains draft",state.draft.BattRsv,41)
eq("failed import does not change live options",w.options.BattRsv,33)

w=start(); state=open(w); press(w,"Power & alerts")
controls("numberEdit")[1].set(40)
fs.faults["write:"..w.kseConfig.path..".tmp"]="short"
press(w,"Save & close"); visible,saved=finish(w)
eq("failed save keeps menu",visible,true)
eq("failed save returns no live settings",saved,nil)
eq("failed save keeps draft edits",w.kseSettings.draft.BattRsv,40)
eq("failed save keeps previous live values",w.options.BattRsv,20)
eq("failed save shows error",type(w.kseSettings.message),"string")
eq("failed save re-enables controls",button("Save & close").active(),true)
back(w); back(w); press(w,"Discard changes")
eq("discard closes without adoption",w.kseSettings,nil)
eq("discard leaves live values",w.options.BattRsv,20)

w=start({MotorSw=99,Theme=6,BattRsv=18}); state=open(w)
press(w,"Power & alerts"); controls("numberEdit")[1].set(45)
back(w); press(w,"Backup & transfer"); fs.calls={}
eq("native import no longer available",#controls("button","Import native Widget Settings"),0)
button("Reset draft to defaults").press()
eq("restore defaults press defers draft replacement",state.draft.BattRsv,45)
Menu.service(w,0)
eq("restore loads canonical reserve",state.draft.BattRsv,20)
eq("restore loads canonical theme",state.draft.Theme,1)
eq("restore requires explicit save",w.kseConfig.record,nil)
eq("restore never writes",mutations(),0)
local file=controls("file")[1]
eq("file picker exact folder",file.folder,SettingsStore.exports)
eq("file picker exact extension",file.extension,".kse")
eq("file picker retains extension",file.hideExtension,false)
local companion=SettingsStore.make("other-model.yml","KSE5",
  {MotorSw=100,Theme=17,BattRsv=47})
companion.themes.KSE4=11
fs.files[SettingsStore.exports.."/incoming.kse"]=assert(SettingsStore.serialize(companion))
file.set("incoming.kse"); fs.calls={}
button("Import selected companion").press()
eq("companion import does not read within native callback",#fs.calls,0)
Menu.service(w,0)
eq("companion import loads shared draft values",state.draft.BattRsv,47)
eq("companion import loads current variant theme",state.draft.Theme,11)
eq("companion import retains other theme",state.themeBase.themes.KSE5,17)
eq("companion import never changes model identity",w.kseModelFile,"menu-model.yml")
eq("companion import never adopts before save",w.kseConfig.record,nil)
eq("companion import never writes",mutations(),0)
press(w,"Save & close"); visible,saved=finish(w)
eq("companion explicit save succeeds",visible,false)
eq("companion explicit save rebinds destination model",w.kseConfig.record.model,"menu-model.yml")
eq("companion explicit save keeps other theme",w.kseConfig.record.themes.KSE5,17)
eq("companion source never overwritten",fs.files[SettingsStore.root.."/v2-model-other-model.yml.kse"],nil)
w.options=saved; state=open(w); press(w,"Backup & transfer")
state.themeBase.themes.KSE5=22
press(w,"Reset draft to defaults")
eq("restore discards imported other-theme draft",state.themeBase.themes.KSE5,17)
eq("restore keeps current live settings before save",w.options.BattRsv,47)
eq("restore resets current theme draft",state.draft.Theme,1)


w=start({MotorSw=99,CountSrc=0,MinFlight=-20,RxPackMin="830",RxPackMax="8.40"})
state=open(w); press(w,"Flight counting")
eq("old zero counter excluded from draft",controls("choice")[1].get(),2)
eq("old counter replaced by internal default",state.draft.CountSrc,2)
eq("duration editor uses canonical positive seconds",controls("numberEdit")[1].get(),20)
eq("old negative duration excluded from draft",state.draft.MinFlight,20)
back(w); press(w,"Power & alerts"); press(w,"Nitro setup  >")
eq("old voltage excluded from draft",controls("numberEdit")[1].get(),660)
eq("old voltage replaced with canonical default",state.draft.RxPackMin,"6.60")
controls("numberEdit")[1].set(830)
controls("numberEdit")[2].set(840)
press(w,"Save & close"); visible,saved=finish(w)
eq("valid tenth-volt gap accepted in EdgeTX float core",visible,false)
eq("saving voltage uses canonical text",saved.RxPackMin,"8.30")

w=start(); state=open(w); press(w,"Model setup")
controls("source")[1].set(101)
press(w,"Save & close")
eq("nonphysical source blocks save job",state.job,nil)
eq("nonphysical source displays correction",type(state.message),"string")
eq("invalid source never writes",mutations(),0)
controls("source")[1].set(99); back(w); press(w,"Power & alerts"); press(w,"Nitro setup  >")
local badRange=controls("numberEdit")
badRange[1].set(850); badRange[2].set(850)
press(w,"Save & close")
eq("invalid voltage gap blocks save job",state.job,nil)
eq("invalid voltage gap keeps draft",state.draft.RxPackMin,"8.50")
eq("invalid voltage gap never writes",mutations(),0)

-- Reopening observes another dashboard's saved settings through the lifecycle
-- hook; temporary read failures keep the running setup and make the page read-only.
w=start()
local externallySaved=SettingsStore.make(m.model,"KSE5",{MotorSw=99,BattRsv=36,Theme=17})
externallySaved.themes.KSE4=7
fs.files[w.kseConfig.path]=assert(SettingsStore.serialize(externallySaved)); fs.calls={}
state=open(w)
eq("reopen reloads shared functional setting",state.draft.BattRsv,36)
eq("reopen reloads current dashboard theme",state.draft.Theme,7)
eq("reopen updates live options through hook",w.options.BattRsv,36)
eq("reopen applies changed config exactly once",m.applied,1)
eq("reopen never writes",mutations(),0)
Menu.retire(w); fs.faults["read:"..w.kseConfig.path]="empty"
state=open(w)
eq("read failure keeps previous live settings",w.options.BattRsv,36)
eq("read failure keeps previous draft source",state.draft.BattRsv,36)
eq("read failure prevents save",w.kseConfig.writable,false)
eq("read failure disables save control",button("Save & close").active(),false)
eq("read failure does not reapply defaults",m.applied,1)
Menu.retire(w); fs.faults={}
local goodMain=fs.files[w.kseConfig.path]
local oldRecord=SettingsStore.make(m.model,"KSE5",{MotorSw=99,BattRsv=9,Theme=3})
fs.files[w.kseConfig.path]="damaged"
fs.files[w.kseConfig.path..".bak"]=assert(SettingsStore.serialize(oldRecord))
state=open(w)
eq("degraded older backup does not replace running setup",w.options.BattRsv,36)
eq("degraded older backup remains read-only",w.kseConfig.writable,false)
Menu.retire(w); fs.files[w.kseConfig.path]=goodMain
state=open(w)
eq("restored main recovers editor writability",w.kseConfig.writable,true)
eq("restored main does not reapply unchanged live values",m.applied,1)


-- Retained callbacks must neither mutate a new owner/model nor initiate I/O.
for _,reason in ipairs({"epoch","owner","model","retire","fullscreen"}) do
  w=start(); state=open(w); press(w,"Power & alerts")
  local stale=controls("numberEdit")[1]
  local staleSave=button("Save & close")
  if reason=="epoch" then w.kseOwnerEpoch=2
  elseif reason=="owner" then m.owner=false
  elseif reason=="model" then m.model="changed-model.yml"
  elseif reason=="retire" then Menu.retire(w)
  elseif reason=="fullscreen" then m.fullscreen=false; Menu.background(w) end
  fs.calls={}; stale.set(49); staleSave.press()
  eq("stale setter ignored "..reason,state.draft.BattRsv,20)
  eq("stale action ignored "..reason,state.intent,nil)
  eq("stale control disabled "..reason,stale.active(),false)
  eq("stale callbacks do not write "..reason,mutations(),0)
  Menu.service(w,0)
  eq("stale session discarded "..reason,w.kseSettings,nil)
end

for _,geometry in ipairs({{800,480,418,44},{480,320,275,32},{480,272,227,32}}) do
  LCD_W,LCD_H=geometry[1],geometry[2]
  lvgl.PAGE_BODY_HEIGHT,lvgl.UI_ELEMENT_HEIGHT=geometry[3],geometry[4]
  w=start(); open(w)
  for _,text in ipairs({"Model setup","Power & alerts","Flight counting","Appearance","Backup & transfer"}) do
    press(w,text)
    for _,kind in ipairs({"button","numberEdit","choice","toggle","source"}) do
      for _,spec in ipairs(controls(kind)) do
        eq("control positive width "..LCD_W.." "..text.." "..kind,spec.w>0,true)
        eq("control within right edge "..LCD_W.." "..text.." "..kind,spec.x+spec.w<=LCD_W,true)
        eq("control touch height "..LCD_W.." "..text.." "..kind,spec.h>=lvgl.UI_ELEMENT_HEIGHT,true)
      end
    end
    back(w)
  end
  Menu.retire(w)
end
LCD_W,LCD_H=800,480; lvgl.PAGE_BODY_HEIGHT=418; lvgl.UI_ELEMENT_HEIGHT=44
w=start()
Menu.service(w,EVT_TOUCH_FIRST,{x=10,y=10}); m.now=69
Menu.service(w,EVT_TOUCH_BREAK,{x=10,y=10})
eq("short touch does not open settings",w.kseSettings,nil)
Menu.service(w,EVT_TOUCH_FIRST,{x=10,y=10}); m.now=140
Menu.service(w,EVT_TOUCH_SLIDE,{x=20,y=10}); Menu.service(w,EVT_TOUCH_BREAK,{x=20,y=10})
eq("touch movement cancels hold",w.kseSettings,nil)
Menu.service(w,EVT_TOUCH_FIRST,{x=10,y=10}); m.now=211
Menu.service(w,EVT_TOUCH_BREAK,{x=10,y=10})
eq("long touch opens settings",w.kseSettings~=nil,true)
eq("long touch release has no new controls",m.builds,0)
Menu.service(w,0); Menu.retire(w)
w.profileDialog={}
Menu.service(w,EVT_VIRTUAL_ENTER_LONG); Menu.service(w,EVT_VIRTUAL_ENTER)
eq("profile modal prevents settings entry",w.kseSettings,nil)
w.profileDialog=nil
Menu.service(w,EVT_VIRTUAL_ENTER)
eq("profile-owned key release cannot later open settings",w.kseSettings,nil)

w=start(); state=open(w); press(w,"Power & alerts"); press(w,"Nitro setup  >")
controls("page")[1].back()
Menu.service(w,EVT_VIRTUAL_EXIT)
eq("native back plus root EXIT navigates only once",state.page,"power")
controls("numberEdit")[1].set(35)
Menu.service(w,EVT_EXIT_BREAK)
eq("raw EXIT moves up one level",state.page,"home")
Menu.service(w,EVT_VIRTUAL_EXIT)
eq("raw EXIT protects unsaved draft",state.page,"leave")
press(w,"Continue editing")
m.fullscreen=false; Menu.service(w,nil)
eq("native fullscreen escape abandons draft",w.kseSettings,nil)
eq("native fullscreen escape keeps live values",w.options.BattRsv,20)
eq("native fullscreen escape never saves",mutations(),0)

w=start(); open(w)
local cost=measure(Menu.service,w,0)
button("Power & alerts").press()
local pageCost=measure(Menu.service,w,0)
controls("numberEdit")[1].set(34); button("Save & close").press()
local startCost=measure(Menu.service,w,0)
local maxStep=0
for _=1,15 do
  local stepCost,isOpen=measure(Menu.service,w,0)
  if stepCost>maxStep then maxStep=stepCost end
  if not isOpen then break end
end
print("PROFILE|menu idle="..cost.."|page="..pageCost.."|start-save="..startCost.."|max-save-frame="..maxStep)
assert(cost<15000 and pageCost<15000 and startCost<15000 and maxStep<15000,
       "isolated menu callback exceeds project instruction margin")
print("PASS|complete")
