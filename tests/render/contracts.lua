-- Retained object API only is mocked. Engine, layout and render functions run.
local objects={}
local function object(first, second)
  local properties=second or first or {}
  local item={properties=properties}
  function item:set(values) for key,value in pairs(values) do self.properties[key]=value end end
  function item:show() self.hidden=false end
  function item:hide() self.hidden=true end
  objects[#objects+1]=item
  return item
end
lvgl={clear=function() objects={} end,label=object,rectangle=object,
      image=object,hline=object,vline=object,arc=object}
local api=dofile(dashboardPath)
assert(#api.options==0,"native descriptor must be empty")
local opts={Theme=1,HeliType=1,CountSrc=1,BattRsv=20,MotorSw=99,RxPackMin="6.60",RxPackMax="8.40"}
for name,value in pairs({Hspd=2200,Tspd=9000,Gov=4,Vbat=45.6,Vcel=3.8,["Cel#"]=12,
  Curr=30,Capa=1200,["Bat%"]=65,Tesc=75,Vbec=7.4,RQly=100,["PID#"]=1,["RTE#"]=2,
  RPM=3100,RxBt=11.4,Temp=65,["tx-voltage"]=7.8}) do
  __mock.values[name]={value=value}
end
local widget=api.fixture.create({x=0,y=0,w=LCD_W,h=LCD_H},opts)
local maxRefresh=0
local function checkObjects()
  assert(#objects>20,"renderer did not build")
  for _,item in ipairs(objects) do
    for key,value in pairs(item.properties) do
      -- LVGL evaluates dynamic properties after callbacks return.
      if type(value)=="function" then value=value() end
      if key=="w" or key=="h" then assert(type(value)=="number" and value>=0,"invalid dimension") end
      if key=="text" and type(value)=="string" then
        assert(not string.find(value,"ADD M1",1,true),"retired manual OMP name prompt rendered")
      end
    end
  end
end
for _,mode in ipairs({1,2,5}) do
  opts.HeliType=mode;__mock.modelName="Fixture"
  if mode==5 then
    __setOmpSources(3,3.8)
    __mock.rssi=100
    api.fixture.apply(widget,opts)
    __mock.now=__mock.now+20
    api.refresh(widget,nil,nil)
    __mock.now=__mock.now+10
    api.refresh(widget,nil,nil)
    assert(not __ompTest(),"unresolved OMP render must precede voltage confirmation")
    checkObjects()
    for _=1,4 do
      __mock.now=__mock.now+20
      api.background(widget)
    end
    local ready,name,cells=__ompTest()
    assert(ready and name=="OMP M2" and cells==3,"OMP render fixture must confirm real source identity")
    __mock.values.RPM.value=3100
  end
  for theme=1,22 do
    opts.Theme=theme
    api.fixture.apply(widget,opts)
    __mock.now=__mock.now+10
    api.refresh(widget,nil,nil)
    checkObjects()
    __mock.now=__mock.now+10
    local cost=measure(api.refresh,widget,nil,nil)
    maxRefresh=math.max(maxRefresh,cost)
    api.background(widget)
  end

end
-- Inspect the real retained transmitter icon via test-only source exports.
-- Native color must be independent of KSE's theme, and zero must hide both.
for _,theme in ipairs({1,2}) do
  opts.Theme=theme;api.fixture.apply(widget,opts)
  -- Layout allocation and instrument population occupy successive callbacks.
  api.refresh(widget,nil,nil)
  for _,case in ipairs({{6.2,0,nil},{6.6,LCD_W==800 and 5/28 or 4/20,0xF44336},
                        {7.4,LCD_W==800 and 15/28 or 11/20,0xFFC107},
                        {7.5,LCD_W==800 and 17/28 or 12/20,0x4CAF50},
                        {8.4,1,0x4CAF50},{0,0,nil}}) do
    __mock.values["tx-voltage"]={value=case[1]}
    __mock.now=__mock.now+100
    api.refresh(widget,nil,nil)
    local ui=__txTestUi(widget)
    if case[2]<=0 then
      assert(ui.txFill.hidden==true,"empty/unavailable transmitter fill remains visible")
    else
      local inset=ui.txInsetY or ui.txInset
      local expected=math.max(1,math.floor((ui.txBodyH-2*inset)*case[2]+0.5))
      assert(not ui.txFill.hidden,"live transmitter fill hidden")
      assert(ui.txFill.properties.h==expected,"transmitter depletion differs from native fraction")
      assert(ui.txFill.properties.color==case[3],"transmitter color differs from native default")
      assert(ui.txFill.properties.y+expected==ui.txBodyY+ui.txBodyH-inset,
             "transmitter fill must stay anchored to bottom")
    end
  end
  local savedGeneral=getGeneralSettings
  getGeneralSettings=function() return {battMin=8.4,battMax=6.2} end
  __mock.values["tx-voltage"]={value=7.4}
  __mock.now=__mock.now+100
  api.refresh(widget,nil,nil)
  assert(__txTestUi(widget).txFill.hidden==true,"invalid native radio range must hide fill")
  getGeneralSettings=nil
  __mock.now=__mock.now+100
  api.refresh(widget,nil,nil)
  assert(__txTestUi(widget).txFill.hidden==true,"missing native battery API must hide fill")
  getGeneralSettings=savedGeneral
  __mock.now=__mock.now+100
  api.refresh(widget,nil,nil)
  -- Native signal bars use monochrome foreground/inactive theme colors.
  -- RQly stays 100 above: only the firmware's radio RSSI determines the icon.
  __mock.values["tx-voltage"]={value=7.4}
  for _,case in ipairs({{0,0},{29,0},{30,1},{40,2},{50,3},{60,4},{80,5},{99,5}}) do
    __mock.rssi=case[1]
    __mock.now=__mock.now+10
    api.refresh(widget,nil,nil)
    local ui,g,active,inactive,bg=__txTestUi(widget)
    assert(#ui.signal==5,"native signal icon requires five bars")
    local first=ui.signal[1].properties
    local bottom=first.y+first.h
    local height=ui.signal[5].properties.h
    for i,ratio in ipairs({5,10,15,21,31}) do
      local bar=ui.signal[i].properties
      assert(bar.color==(i<=case[2] and active or inactive),"wrong native signal color/state")
      assert(bar.y+bar.h==bottom,"signal bars must share a baseline")
      assert(bar.h==math.max(1,math.floor(height*ratio/31+0.5)),"wrong native signal height ratio")
      assert(bar.w>=3 and bar.y>=g.originY,"signal bars too small or clipped")
      if i>1 then
        local previous=ui.signal[i-1].properties
        assert(bar.x>=previous.x+previous.w+2,"signal bars collide")
      end
    end
    local last=ui.signal[5].properties
    local batteryX=ui.txBodyX or ui.txBody.fill.properties.x
    assert(last.x+last.w<batteryX,
           "signal icon overlaps battery")
    local label=ui.profileStatus.properties
    assert(label.x+label.w<first.x,"profile label overlaps signal")
    if case[1]==50 or case[1]==80 then
      -- Rectangle snapshots produce reproducible host-side geometry previews.
      -- Native font/antialiasing and physical-radio readability remain untested.
      for _,item in ipairs(objects) do
        local p=item.properties
        if p.filled~=nil and not item.hidden and p.x>=first.x
           and p.y>=g.originY and p.y+p.h<=ui.txBodyY+ui.txBodyH+1 then
          print(string.format("ICON|%d|%d|%d|%g|%g|%g|%g|%d|%d|%g",
            theme,case[1],bg,p.x,p.y,p.w,p.h,p.color,
            (p.filled==true or p.filled==1) and 1 or 0,p.rounded or 0))
        end
      end
    end
  end
end
-- ARM/profile packet transport is tested separately; this fixture never creates RF Tool.
print("66 mode/theme renders; warm refresh="..maxRefresh.." instructions (LVGL mocked)")
assert(maxRefresh<15000,"warm refresh exceeds project instruction margin")
