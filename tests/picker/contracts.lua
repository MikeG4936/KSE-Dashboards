(function()
  local api=__picker
  local function reset(width,height,dialogAvailable,menuAvailable)
    __mock.arm=0; __mock.dialogs=0; __mock.menus=0; __mock.closed=0
    __mock.dialog=nil; __mock.menu=nil; __mock.children=nil
    api.clear()
    api.G.screenW=width; api.G.screenH=height
    api.G.configure(0,0,width,height)
    api.apply({HeliType=1,Theme=0})
    lvgl={LCD_SCALE=width==800 and 1.375 or 1}
    if dialogAvailable then
      lvgl.dialog=function(spec)
        __mock.dialogs=__mock.dialogs+1
        __mock.dialog=spec
        return {build=function(self,children) __mock.children=children end,
                close=function(self) __mock.closed=__mock.closed+1; spec.close() end}
      end
    end
    if menuAvailable then
      lvgl.menu=function(spec) __mock.menus=__mock.menus+1; __mock.menu=spec end
    end
    local wgt={profileRfState="disarmed",profileActive=1,profileCapacitiesReady=true,
               profileCapacities={1000,2000,3000,4000,5000,6000}}
    if api.owner then
      __mock.now=__mock.now+500
      assert(api.owner.claim(wgt,true),"picker fixture owner claim failed")
    end
    if api.disarmed then
      assert(api.disarmed(wgt),"fresh disarmed ARM should admit immediately")
    end
    return wgt
  end
  local function case(name) print("PICKER|case|"..name) end
  local function bounds(width,height)
    local spec=__mock.dialog
    assert(spec.w<=width and spec.h<=height,"outer dialog exceeds screen")
    -- EdgeTX 1511b3f: body = h - UI_ELEMENT_HEIGHT. No flex/custom pad
    -- means Lua setFlex resets the body's padding to zero.
    local header=width==800 and 44 or 32
    for index,child in ipairs(__mock.children) do
      assert(child.x>=0 and child.y>=0 and child.w>0 and child.h>0)
      assert(child.x+child.w<=spec.w,"child exceeds body width: "..index)
      assert(child.y+child.h<=spec.h-header,
             "child exceeds body height: "..index.." bottom="..(child.y+child.h).." body="..(spec.h-header))
    end
  end
  local function resolve(value) return type(value)=="function" and value() or value end
  local function style()
    local wgt=reset(480,320,true,false)
    assert(api.show(wgt)); bounds(480,320)
    local spec=__mock.dialog
    print("STYLE|"..spec.title.."|"..spec.w.."|"..spec.h)
    for i,c in ipairs(__mock.children) do
      local parts={"STYLE",tostring(i)}
      for _,key in ipairs({"type","x","y","w","h","font","cornerRadius","color","textColor","align","text"}) do
        parts[#parts+1]=tostring(resolve(c[key])):gsub("\n","\\n")
      end
      print(table.concat(parts,"|"))
    end
  end
  if arg[1]=="style" then style(); print("PICKER|complete"); return end

  for _,size in ipairs({{480,272},{480,320},{800,480}}) do
    local width,height=size[1],size[2]
    local wgt=reset(width,height,true,false)
    assert(api.show(wgt)==true and __mock.dialogs==1 and __mock.menus==0)
    assert(#__mock.children==9,"six profiles plus status/retry/close")
    bounds(width,height)
    assert(__mock.children[1].text:find("ACTIVE") and __mock.children[2].text:find("2000 mAh"))
    assert(__mock.children[1].active()==false and __mock.children[2].active()==true)
    assert(api.show(wgt)==true and __mock.dialogs==1,"duplicate dialog")
    __mock.children[2].press()
    assert(wgt.profileSelectionRequested==2 and wgt.profileAutoShown and wgt.profileDialog==nil and __mock.closed==1)
    case("dialog-select-"..width.."x"..height)

    wgt=reset(width,height,true,false)
    wgt.profileCapacities={1000,0,3000,0,0,0}
    assert(api.show(wgt)); assert(#__mock.children==5)
    bounds(width,height)
    __mock.children[2].press()
    assert(wgt.profileSelectionRequested==3,"sparse configured profile mapped incorrectly")
    case("sparse-profiles-"..width.."x"..height)

    wgt=reset(width,height,true,false)
    assert(api.show(wgt))
    __mock.arm=1; api.clear()
    assert(__mock.children[2].active()==false)
    __mock.children[2].press()
    assert(wgt.profileSelectionRequested==nil and wgt.profileDialog~=nil)
    assert(wgt.profileNoticeTitle=="PROFILE CHANGE LOCKED")
    case("armed-after-open-"..width.."x"..height)

    wgt=reset(width,height,true,false); wgt.profileRfState="armed"
    assert(api.show(wgt)); __mock.children[2].press()
    assert(wgt.profileSelectionRequested==nil and wgt.profileNoticeTitle=="PROFILE CHANGE LOCKED")
    case("host-armed-"..width.."x"..height)

    wgt=reset(width,height,true,false); assert(api.show(wgt))
    __mock.children[9].press()
    assert(wgt.profileSelectionRequested==nil and wgt.profileAutoShown and wgt.profileDialog==nil and __mock.closed==1)
    case("close-"..width.."x"..height)

    wgt=reset(width,height,true,false); assert(api.show(wgt)); __mock.dialog.close()
    assert(wgt.profileDialog==nil and wgt.profileSelectionRequested==nil)
    case("dismiss-"..width.."x"..height)

    wgt=reset(width,height,true,false); assert(api.show(wgt)); __mock.children[8].press()
    assert(wgt.profileCapacityRefreshRequested and wgt.profileDialog==nil)
    case("refresh-"..width.."x"..height)

    wgt=reset(width,height,false,true); assert(api.show(wgt))
    assert(__mock.menus==1 and __mock.dialogs==0 and __mock.menu.get()==1)
    __mock.menu.set(2)
    assert(wgt.profileSelectionRequested==2)
    case("native-select-"..width.."x"..height)

    wgt=reset(width,height,false,true); assert(api.show(wgt)); __mock.arm=1; api.clear()
    __mock.menu.set(2)
    assert(wgt.profileSelectionRequested==nil and wgt.profileNoticeTitle=="PROFILE CHANGE LOCKED")
    case("native-arm-after-open-"..width.."x"..height)

    wgt=reset(width,height,false,true); assert(api.show(wgt)); __mock.menu.set(7)
    assert(wgt.profileSelectionRequested==nil and wgt.profileAutoShown)
    case("native-close-"..width.."x"..height)

    wgt=reset(width,height,false,false)
    assert(api.show(wgt)==false)
    assert(wgt.profileNoticeTitle=="BATTERY PROFILE ERROR" and
           wgt.profileNoticeDetail=="UPDATE EDGETX FOR PROFILE PICKER")
    case("missing-apis-"..width.."x"..height)
  end
  local wgt=reset(480,272,true,true); assert(api.show(wgt))
  if arg[2]=="KSE4" then assert(__mock.menus==1 and __mock.dialogs==0)
  else assert(__mock.dialogs==1 and __mock.menus==0) end
  case("preferred-compact-capability")
  wgt=reset(480,272,true,true)
  lvgl.menu=function() error("native menu failed") end
  assert(api.show(wgt) and __mock.dialogs==1); bounds(480,272)
  case("dialog-available-with-failing-native-api")
  wgt=reset(480,320,true,true)
  lvgl.dialog=function() error("dialog constructor failed") end
  assert(api.show(wgt) and __mock.menus==1)
  case("dialog-failure-native-fallback")
  wgt=reset(480,320,true,true)
  lvgl.dialog=function(spec)
    return {build=function() error("dialog build failed") end,
            close=function() __mock.closed=__mock.closed+1; spec.close() end}
  end
  assert(api.show(wgt) and __mock.menus==1 and __mock.closed==1 and wgt.profileDialog==nil)
  case("build-failure-closes-before-native-fallback")
  wgt=reset(480,320,false,false); lvgl=nil
  assert(api.show(wgt)==false and wgt.profileNoticeDetail=="UPDATE EDGETX FOR PROFILE PICKER")
  case("missing-lvgl")
  assert(__mock.unrelatedReads==0,"picker admission must not inspect Gov or Hspd")
  print("PICKER|complete")
end)()
