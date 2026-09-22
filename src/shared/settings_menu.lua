-- Fullscreen, local-only editor. Native callbacks edit a draft or queue an
-- intent; lifecycle callbacks own all page transitions and filesystem work.
local Menu = {}
local parents={model="home",power="home",nitro="power",count="home",
  appearance="home",transfer="home",leave="home"}
local titles={home="Settings",model="Model setup",power="Power & alerts",
  nitro="Nitro setup",count="Flight counting",appearance="Appearance",
  transfer="Backup & transfer",leave="Unsaved changes"}
local function copy(source)
  local result={}
  for key,value in pairs(source or {}) do result[key]=value end
  return result
end
function Menu.capable()
  if not SettingsStore.supported() or not lvgl then return false end
  for _,name in ipairs({"isFullScreen","clear","build","page","button","label",
                         "rectangle","choice","numberEdit","toggle","source","file","dialog"}) do
    if type(lvgl[name])~="function" then return false end
  end
  return type(lvgl.PAGE_BODY_HEIGHT)=="number" and type(lvgl.UI_ELEMENT_HEIGHT)=="number"
         and type(lvgl.SRC_SWITCH)=="number" and type(lvgl.SCROLL_VER)=="number"
end
function Menu.attach(widget)
  widget.kseSettingsCapable=Menu.capable()
  if widget.kseSettingsCapable then widget.kseConfig=SettingsStore.open(widget.kseModelFile) end
  return SettingsStore.effective(widget.kseConfig and widget.kseConfig.record,G.name)
end
function Menu.requirement(widget)
  if widget.kseSettingsCapable then return false end
  if not widget.kseRequirementDrawn and lvgl and type(lvgl.clear)=="function"
     and type(lvgl.label)=="function" then
    lvgl.clear()
    lvgl.label({x=12,y=12,w=math.max(1,(widget.zone.w or LCD_W)-24),font=SMLSIZE,
      text="KSE Settings require EdgeTX 2.12.4\nwith native LVGL controls."})
    widget.kseRequirementDrawn=true
  end
  return true
end
function Menu.retire(widget)
  -- May run from a retained native getter during model revocation. Never clear
  -- LVGL, touch retired handles, or write files from this invalidation hook.
  if widget.kseSettings then widget.layoutSignature=nil end
  widget.kseSettings=nil
  widget.kseSettingsGesture=nil
end
local function current(s)
  return s.widget.kseSettings==s and s.epoch==s.widget.kseOwnerEpoch
     and WidgetOwner.current(s.widget)
end
local function usable(s,revision)
  return current(s) and s.revision==revision and not s.job
end
local function queue(s,action,value,revision)
  if usable(s,revision) then s.intent={action,value} end
  return 0
end
local function dirty(s)
  return s.imported or not SettingsStore.equal(s.draft,s.original)
end
local function setDraft(s,key,value,revision)
  if not usable(s,revision) then return end
  if key=="BattVoice" then value=(value==true or value==1) and 1 or 0 end
  s.draft[key]=value
  s.message=nil
end
local function validate(s)
  local low,high=parseVolt(s.draft.RxPackMin,nil),parseVolt(s.draft.RxPackMax,nil)
  if not validRxRange(low,high) then
    return "Nitro: use 4.00-9.00 V; maximum must exceed minimum by 0.10 V."
  end
  -- SOURCE picker also exposes function switches. Only physical switches have
  -- the three-position semantics expected by the existing alert gate.
  if not isPhysicalMotorSource(s.draft.MotorSw) then
    return "Model setup: select a physical motor switch (SA, SB, ...)."
  end
end
local function field(s,ui,key,label,kind,extra)
  local revision=s.revision
  local row=ui.y
  ui.children[#ui.children+1]={type="label",x=ui.pad,y=row+5,w=ui.labelW,
    h=ui.h,font=SMLSIZE,text=label,color=ui.palette.text}
  local spec={type=kind,x=ui.pad+ui.labelW+ui.gap,y=row,
    w=ui.w-ui.labelW-ui.gap-2*ui.pad,h=ui.h,
    get=function() return s.draft[key] end,
    set=function(value) setDraft(s,key,value,revision) end,
    active=function() return usable(s,revision) end}
  for k,v in pairs(extra or {}) do spec[k]=v end
  ui.children[#ui.children+1]=spec
  ui.y=row+ui.h+ui.gap
end
local function note(ui,text,color)
  ui.children[#ui.children+1]={type="label",x=ui.pad,y=ui.y,w=ui.w-2*ui.pad,
    h=ui.h*2,font=SMLSIZE,text=text,color=color or ui.palette.dim}
  ui.y=ui.y+ui.h*2+ui.gap
end
local function button(s,ui,text,action,value)
  local revision=s.revision
  ui.children[#ui.children+1]={type="button",x=ui.pad,y=ui.y,w=ui.w-2*ui.pad,
    h=ui.h,font=SMLSIZE,text=text,color=ui.palette.panel,textColor=ui.palette.text,
    cornerRadius=6,active=function() return usable(s,revision) end,
    press=function() return queue(s,action,value,revision) end}
  ui.y=ui.y+ui.h+ui.gap
end
local function number(s,ui,key,label,lo,hi,display)
  field(s,ui,key,label,"numberEdit",{min=lo,max=hi,display=display})
end
local function buildHome(s,ui)
  local revision=s.revision
  local items={{"Model setup","model"},{"Power & alerts","power"},
    {"Flight counting","count"},{"Appearance","appearance"}}
  local width=math.floor((ui.w-2*ui.pad-ui.gap)/2)
  local height=ui.h+(ui.w==800 and 36 or 16)
  for i,item in ipairs(items) do
    ui.children[#ui.children+1]={type="button",x=ui.pad+((i-1)%2)*(width+ui.gap),
      y=ui.y+math.floor((i-1)/2)*(height+ui.gap),w=width,h=height,
      text=item[1],font=ui.w==800 and MIDSIZE or SMLSIZE,cornerRadius=8,
      color=ui.palette.panel,textColor=ui.palette.text,
      active=function() return usable(s,revision) end,
      press=function() return queue(s,"page",item[2],revision) end}
  end
  ui.y=ui.y+2*(height+ui.gap)
  button(s,ui,"Backup & transfer", "page","transfer")
  note(ui,s.widget.kseConfig.error or (s.widget.kseConfig.record
    and "Shared model settings  /  Separate dashboard themes"
    or "New setup: review all settings, then Save & close."))
end
local function buildModel(s,ui)
  local revision=s.revision
  field(s,ui,"HeliType","Helicopter type","choice",{
    values=SettingsStore.heliTypes,title="Helicopter type",
    get=function()
      for i,id in ipairs(SettingsStore.heliTypeIds) do
        if id==s.draft.HeliType then return i end
      end
      return 1
    end,
    set=function(v)
      local id=SettingsStore.heliTypeIds[v]
      if id then setDraft(s,"HeliType",id,revision) end
    end})
  field(s,ui,"MotorSw","Motor switch","source",{filter=lvgl.SRC_SWITCH})
  note(ui,"Auto Elec/Nitro uses the FC name.\nOMPHOBBY identifies M1/M2 from RxBt and Volt.")
end
local function buildPower(s,ui)
  number(s,ui,"BattRsv","Battery reserve",0,50,function(v) return tostring(v).." %" end)
  field(s,ui,"BattVoice","Battery voice","toggle",{
    get=function() return s.draft.BattVoice==1 end})
  button(s,ui,"Nitro setup  >","page","nitro")
  note(ui,"Reserve reduces the capacity available to the fuel gauge.\nVoice announces low and critical battery levels.")
end
local function buildNitro(s,ui)
  local revision=s.revision
  for _,item in ipairs({{"RxPackMin","Receiver pack min V",6.6},{"RxPackMax","Receiver pack max V",8.4}}) do
    local key=item[1]
    field(s,ui,key,item[2],"numberEdit",{min=400,max=900,
      get=function() return math.floor(parseVolt(s.draft[key],item[3])*100+0.5) end,
      set=function(v) setDraft(s,key,string.format("%.2f",v/100),revision) end,
      display=function(v) return string.format("%.2f V",v/100) end})
  end
  field(s,ui,"FuelCheck","Fuel Check Reminder","numberEdit",{min=0,max=120,
    get=function() return s.draft.FuelCheck-1 end,
    set=function(v) setDraft(s,"FuelCheck",v+1,revision) end,
    display=function(v) return v==0 and "Off" or string.format("%02d:%02d",math.floor(v/4),(v%4)*15) end})
  note(ui,"Nitro only. Receiver range: 4.00-9.00 V.\nFuel reminder follows Timer 1; each step is 15 seconds.")
end
local function buildCount(s,ui)
  local revision=s.revision
  field(s,ui,"CountSrc","Flight counter","choice",{
    values={"KSE counter","Rotorflight FC"},title="Flight counter",
    get=function() return s.draft.CountSrc==1 and 1 or 2 end})
  field(s,ui,"MinFlight","Min flight time","numberEdit",{min=1,max=120,
    get=function() return s.draft.MinFlight end,
    set=function(v) setDraft(s,"MinFlight",v,revision) end,
    display=function(v) return tostring(v).." sec" end})
  note(ui,"Minimum flight applies to the KSE counter.\nOMPHOBBY uses KSE counting; your saved choice is retained.")
end
local function buildAppearance(s,ui)
  local revision=s.revision
  field(s,ui,"Theme","Dashboard theme","choice",{title="Theme",values=G.settingsThemes,
    get=function() return s.draft.Theme end,
    set=function(v)
      setDraft(s,"Theme",v,revision)
      queue(s,"preview",nil,revision)
    end})
  local p=G.settingsPalette(s.draft.Theme)
  local height=ui.h*2
  ui.children[#ui.children+1]={type="rectangle",x=ui.pad,y=ui.y,w=ui.w-2*ui.pad,
    h=height,color=p.panel,filled=true,rounded=8}
  ui.children[#ui.children+1]={type="rectangle",x=ui.pad,y=ui.y,w=5,
    h=height,color=p.accent,filled=true}
  ui.children[#ui.children+1]={type="label",x=ui.pad+18,y=ui.y+8,w=ui.w-2*ui.pad-30,
    h=ui.h,font=MIDSIZE,text=G.name.."   06:24   78%",color=p.text}
  ui.children[#ui.children+1]={type="label",x=ui.pad+18,y=ui.y+ui.h,w=ui.w-2*ui.pad-30,
    h=ui.h,font=SMLSIZE,text="Theme preview",color=p.dim}
  ui.y=ui.y+height+ui.gap
  note(ui,"This dashboard's theme only.\nThe dashboard changes when you Save & close.")
end
local function buildTransfer(s,ui)
  local revision=s.revision
  button(s,ui,"Export saved KSE settings", "export")
  field(s,ui,"exportName","Companion file","file",{folder=SettingsStore.exports,
    extension=".kse",maxLen=150,hideExtension=false,title="KSE companion settings",
    get=function() return s.exportName or "" end,
    set=function(name) if usable(s,revision) then s.exportName=name end end})
  button(s,ui,"Import selected companion", "import")
  button(s,ui,"Reset draft to defaults", "defaults")
  note(ui,"Destination: "..tostring(s.widget.kseModelFile).."\nCopy companion files to /KSE/Settings/Exports.")
end
local builders={home=buildHome,model=buildModel,power=buildPower,nitro=buildNitro,
  count=buildCount,appearance=buildAppearance,transfer=buildTransfer}
local function build(s)
  s.revision=s.revision+1
  local revision=s.revision
  local w,h=LCD_W,LCD_H
  local ui={w=w,h=lvgl.UI_ELEMENT_HEIGHT,pad=w==800 and 18 or 10,
    gap=w==800 and 14 or 8,y=w==800 and 18 or 10,
    labelW=math.floor(w*0.44),palette=G.settingsPalette(s.original.Theme),children={}}
  -- Native pages do not paint a custom opaque body themselves on all themes.
  ui.children[1]={type="rectangle",x=0,y=0,w=w,h=lvgl.PAGE_BODY_HEIGHT,
    color=ui.palette.bg,filled=true,floating=true}
  if s.message then note(ui,s.message,ui.palette.text) end
  if s.page=="leave" then
    note(ui,"Keep your changes to this model?")
    button(s,ui,"Save & close","save")
    button(s,ui,"Discard changes","discard")
    button(s,ui,"Continue editing","page","home")
  else builders[s.page](s,ui) end
  local header=h-lvgl.PAGE_BODY_HEIGHT
  local saveW=w==800 and 178 or 124
  lvgl.clear()
  lvgl.build({{type="page",title=G.name.." Settings",subtitle=function()
      if s.job then return s.exporting and "Exporting..." or "Saving..." end
      return titles[s.page]..(dirty(s) and " *" or "")
    end,backButton=false,scrollDir=lvgl.SCROLL_VER,scrollBar=true,
    back=function() return queue(s,"back",nil,revision) end,children=ui.children},
    {type="button",x=w-saveW-ui.pad,y=math.floor((header-ui.h)/2),w=saveW,h=ui.h,
      text="Save & close",font=SMLSIZE,cornerRadius=6,
      active=function() return usable(s,revision) and s.widget.kseConfig.writable end,
      press=function() return queue(s,"save",nil,revision) end}})
  s.rebuild=false
end
local function open(widget)
  local state=SettingsStore.open(widget.kseModelFile)
  if widget.kseConfig.record and (not state.record
     or (state.source~="main" and state.baseText~=widget.kseConfig.baseText)) then
    -- A temporary card/read failure must not change a running model's setup.
    state.record=widget.kseConfig.record
    state.baseText=widget.kseConfig.baseText
    state.source="retained"
    state.writable=false
    state.error="Saved file changed or unavailable; keeping live settings"
  end
  widget.kseConfig=state
  local effective=SettingsStore.effective(state.record,G.name)
  if not SettingsStore.equal(effective,widget.options) then G.updateSettings(widget,effective) end
  local original=copy(widget.options)
  widget.kseSettings={widget=widget,epoch=widget.kseOwnerEpoch,revision=0,
    original=original,draft=copy(original),page="home",rebuild=true,
    themeBase={themes=copy(widget.kseConfig.record and widget.kseConfig.record.themes)}}
  widget.kseSettingsGesture=nil
  widget.layoutSignature=nil
end
local function close(s)
  Menu.retire(s.widget)
  s.widget.kseUiDirty=true
end
local function process(s)
  local intent=s.intent
  s.intent=nil
  if not intent then return end
  local action,value=intent[1],intent[2]
  if action=="page" then s.page=value; s.message=nil
  elseif action=="preview" then
    -- A native choice has closed before this deferred refresh rebuild.
  elseif action=="back" then
    if s.page=="home" then
      if dirty(s) then s.page="leave" else close(s); return end
    else s.page=parents[s.page] or "home" end
    s.message=nil
  elseif action=="discard" then close(s); return
  elseif action=="defaults" then
    s.draft=SettingsStore.defaults()
    s.themeBase={themes=copy(s.widget.kseConfig.record and s.widget.kseConfig.record.themes)}
    s.imported=false
    s.message="Defaults loaded into draft. Review, then Save & close."
  elseif action=="import" then
    local record,reason=SettingsStore.readExport(s.exportName)
    if record then
      s.draft=SettingsStore.effective(record,G.name)
      for key,v in pairs(record.themes) do s.themeBase.themes[key]=v end
      s.imported=true
      s.message="Companion loaded for this model. Check motor switch before saving."
    else s.message=reason end
  elseif action=="export" then
    s.job,s.message=SettingsStore.startExport(s.widget.kseConfig)
    s.exporting=s.job~=nil
  elseif action=="save" then
    s.message=validate(s)
    if not s.message then
      local record=SettingsStore.make(s.widget.kseModelFile,G.name,s.draft,s.themeBase)
      s.job,s.message=SettingsStore.startSave(s.widget.kseConfig,record)
      s.exporting=false
    end
  end
  s.rebuild=true
end
function Menu.service(widget,event,touch)
  if not widget.kseSettingsCapable then return false end
  local fullscreen=event~=nil and lvgl.isFullScreen()
  if not fullscreen then Menu.retire(widget); return false end
  local s=widget.kseSettings
  if s and not current(s) then Menu.retire(widget); return false end
  if s then
    -- The widget root stays in the native focus group. If it owns focus,
    -- short EXIT arrives here; focused editors/popups consume it themselves.
    if not s.intent and ((EVT_VIRTUAL_EXIT and event==EVT_VIRTUAL_EXIT)
       or (EVT_EXIT_BREAK and event==EVT_EXIT_BREAK)) then
      queue(s,"back",nil,s.revision)
    end
    if s.job then
      local status,reason=SettingsStore.step(s.job)
      if status=="done" then
        s.job=nil
        if s.exporting then
          s.message="Exported saved settings to /KSE/Settings/Exports."
          s.rebuild=true
        else
          local saved=SettingsStore.effective(widget.kseConfig.record,G.name)
          close(s)
          return false,saved
        end
      elseif status=="error" then s.job=nil; s.message=reason; s.rebuild=true end
    else process(s) end
    if widget.kseSettings==s and s.rebuild then build(s) end
    return widget.kseSettings~=nil
  end
  -- The profile modal owns its current gesture. The verified firmware path
  -- uses tracked dialogs, never the unobservable native menu fallback.
  if widget.profileDialog then widget.kseSettingsGesture=nil; return false end
  local now=getTime and getTime() or 0
  local gesture=widget.kseSettingsGesture
  if (EVT_VIRTUAL_ENTER_LONG and event==EVT_VIRTUAL_ENTER_LONG)
     or (EVT_ENTER_LONG and event==EVT_ENTER_LONG) then
    -- Color EdgeTX >=2.11 suppresses ENTER release after a long press (RF2
    -- ui_lcd.lua documents this too). Do not wait for a nonexistent BREAK.
    open(widget)
  elseif EVT_TOUCH_FIRST and event==EVT_TOUCH_FIRST and touch then
    widget.kseSettingsGesture={time=now}
  elseif EVT_TOUCH_SLIDE and event==EVT_TOUCH_SLIDE then
    widget.kseSettingsGesture=nil
  elseif EVT_TOUCH_BREAK and event==EVT_TOUCH_BREAK then
    widget.kseSettingsGesture=nil
    if gesture and gesture.time and now>=gesture.time and now-gesture.time>=70 then open(widget) end
  end
  -- Build controls on the next refresh. Touch has already released; hardware
  -- long-press release is suppressed by the verified native event route.
  return widget.kseSettings~=nil
end
function Menu.background(widget)
  if widget.kseSettingsCapable and not lvgl.isFullScreen() then Menu.retire(widget) end
end
return Menu
