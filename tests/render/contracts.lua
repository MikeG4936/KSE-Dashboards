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
assert(#api.options==11)
local opts={Theme=1,HeliType=1,CountSrc=1,BattRsv=20,MotorSw=99,RxPackMin="6.60",RxPackMax="8.40"}
for name,value in pairs({Hspd=2200,Tspd=9000,Gov=4,Vbat=45.6,Vcel=3.8,["Cel#"]=12,
  Curr=30,Capa=1200,["Bat%"]=65,Tesc=75,Vbec=7.4,RQly=100,["PID#"]=1,["RTE#"]=2,
  RPM=3100,RxBt=11.4,Temp=65,["tx-voltage"]=7.8}) do
  __mock.values[name]={value=value}
end
local widget=api.create({x=0,y=0,w=LCD_W,h=LCD_H},opts)
local maxRefresh=0
for mode=1,3 do
  opts.HeliType=mode;__mock.modelName=mode==3 and "M2 Fixture" or "Fixture"
  for theme=1,22 do
    opts.Theme=theme
    api.update(widget,opts)
    __mock.now=__mock.now+10
    api.refresh(widget,nil,nil)
    assert(#objects>20,"renderer did not build")
    for _,item in ipairs(objects) do
      for key,value in pairs(item.properties) do
        -- LVGL evaluates dynamic properties after callbacks return.
        if type(value)=="function" then value=value() end
        if key=="w" or key=="h" then assert(type(value)=="number" and value>=0,"invalid dimension") end
      end
    end
    __mock.now=__mock.now+10
    local cost=measure(api.refresh,widget,nil,nil)
    maxRefresh=math.max(maxRefresh,cost)
    api.background(widget)
  end
end
-- Inspect the real retained transmitter icon via test-only source exports.
-- Native color must be independent of KSE's theme, and zero must hide both.
for _,theme in ipairs({1,2}) do
  opts.Theme=theme;api.update(widget,opts)
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
end
-- ARM/profile packet transport is tested separately; this fixture never creates RF Tool.
print("66 mode/theme renders; warm refresh="..maxRefresh.." instructions (LVGL mocked)")
assert(maxRefresh<15000,"warm refresh exceeds project instruction margin")
