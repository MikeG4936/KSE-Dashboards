-- Host-side mocks; no RF packet transport or physical LVGL rendering.
__mock={now=100,arm=0,dialogs=0,menus=0,closed=0}
LCD_W=800; LCD_H=480
SMLSIZE=1; MIDSIZE=2; DBLSIZE=3; CENTER=4
lcd={RGB=function(r,g,b) return r*65536+g*256+b end}
getTime=function() return __mock.now end
getFieldInfo=function(name) return {id=name,name=name} end
getValue=function() return 0 end
getSourceValue=function(name)
  if name=="ARM" then return __mock.arm,true,true end
  if name=="Gov" or name=="Hspd" then return 0,true,true end
  return nil,false,false
end
getRSSI=function() return 100 end
model={getInfo=function() return {name="Picker fixture"} end,
       getTimer=function() return {value=0,start=0} end}
io={open=function() return nil end, close=function() end}
rf2={apiVersion=12.09,rfToolApiVersion=1.0,registerWidget=function() end,
     widget={state="disarmed"},
     mspQueue={add=function() error("picker callback must defer RF requests") end}}
