-- The four originally confirmed failures, through full production callbacks.
if string.find(scenario,"auto-",1,true)==1 then
  local t=fixture(4,2)
  if string.find(scenario,"theme9",1,true) then t.opts.Theme=9 end
  t:initialize()
  local builds=t.builds
  local names=string.find(scenario,"initial-electric",1,true)
    and {"RS4 Venom","Nitro N","Another Electric"}
    or {"Nitro N","RS4 Venom","Another Nitro","Another Electric"}
  for _,name in ipairs(names) do
    t:connect(name);t:settle(true)
    assert(t.audit.AUTO_HELI.ready,"Auto failed to confirm "..name)
    assert(t.audit.name()==name,"Auto identity stale")
    assert(t.audit.OPT.heliType==(string.find(name,"Nitro",1,true) and 2 or 1),"Auto type stale")
    assert(t:hasText(name),"rendered identity stale")
    assert(t.builds==builds,"Auto type confirmation rebuilt the retained screen")
    if variant=="KSE4" then
      local nitro=t.audit.OPT.heliType==2
      local caption=nitro and "BATT" or "BEC"
      if LCD_W<520 then caption=caption.." V" end
      assert(t:hasText(caption),"retained voltage caption has old type")
      assert(t:hasText("25%")==not nitro,"retained battery footer has old type")
    end
    t:disconnect();t:step(true)
  end
  -- A hidden confirmation must refresh retained objects immediately on return,
  -- including when the next telemetry sample is not yet due.
  t:connect("Hidden Nitro");t:settle(false)
  local tick=t.audit.A.lastDataTick
  t:step(true,1)
  assert(t.audit.A.lastDataTick==tick,"hidden return unexpectedly sampled telemetry")
  assert(t:hasText("Hidden Nitro") and t.widget.kseUiDirty==nil,"hidden type UI handoff failed")
  assert(t.builds==builds,"hidden type confirmation rebuilt the screen")
  assert(historyIO()==0,"fresh Rotorflight count mode touched local history")
  t:report(scenario)
elseif scenario=="model-takeover-20" or scenario=="model-takeover-200" then
  local count=scenario=="model-takeover-20" and 20 or 200
  local t=fixture(1,1);t:initialize();t:finishLoad(true)
  local values,text=seedHistory(t,count)
  __mock.modelName="New model";__mock.modelFilename="new.yml"
  t:create();t:step(true);t:finishLoad(true);t:step(true)
  assertHistory(t,values)
  assert(t.audit.count()==17,"recreated owner did not select new model count")
  assert(t.audit.store().writable and not t.audit.store().error,"valid model history not writable")
  assert(fs.files[historyPath]==text and historyWrites()==0,"model takeover changed history")
  t:report(scenario)
elseif scenario=="counter-switch" or scenario=="counter-switch-max-bytes"
    or scenario=="comment-heavy-max-bytes" then
  local t=fixture(1,2);t:initialize();t:connect("RS4 Venom");t:settle(true)
  assert(historyIO()==0,"fresh Rotorflight count mode touched local history")
  local values,text=seedHistory(t,200)
  if scenario=="counter-switch-max-bytes" then
    local old=values.M001
    values.M001=nil
    values["M001"..string.rep("x",32768-#text)]=old
    text=assert(t.audit.Storage.serialize(values))
    assert(#text==32768,"maximum byte fixture is not exact")
    fs.files[historyPath]=text
  elseif scenario=="comment-heavy-max-bytes" then
    values={["Shared Heli"]=7}
    local prefix="model_name,flight_count\n"..string.rep("#\n",16000)
    local row="Shared Heli,7\n"
    text=prefix.."#"..string.rep("x",32768-#prefix-#row-2).."\n"..row
    assert(#text==32768,"comment fixture is not exact")
    fs.files[historyPath]=text
  end
  t.opts.CountSrc=1;t:update();t:finishLoad(true);t:step(true)
  assertHistory(t,values)
  assert(t.audit.count()==7,"counter switch did not select saved local count")
  assert(t.audit.store().writable and not t.audit.store().error,"counter switch lost writable state")
  assert(fs.files[historyPath]==text and historyWrites()==0,"counter switch changed history")
  t:report(scenario)
elseif scenario=="backup-recovery" then
  local t=fixture(1,1)
  local values,text=seedHistory(t,200)
  local broken=text.."bad row\n"
  fs.files[historyPath]=broken;fs.files[historyPath..".bak"]=text
  t:create();t:update();t:finishLoad(true);t:step(true)
  assertHistory(t,values)
  local state=t.audit.store()
  assert(state.source=="backup" and not state.writable and state.error,"backup recovery must be read-only and show error")
  assert(t.audit.A.flightSaveError,"backup recovery warning missing")
  assert(t.audit.count()==7,"backup recovery count missing")
  __mock.timer.value=25;t:step(true)
  assertHistory(t,values)
  assert(historyWrites()==0,"backup recovery wrote to corrupt history")
  assert(fs.files[historyPath]==broken and fs.files[historyPath..".bak"]==text,"backup recovery changed evidence")
  t:report(scenario)
elseif scenario=="loading-handoff" then
  local t=fixture(1,1)
  local values,text=seedHistory(t,200)
  t:create();t:update()
  assert(t.audit.store().loading,"large history must begin asynchronously")
  local before=historyIO()
  t.audit.count();t.audit.cache();t:dispatch()
  assert(historyIO()==before,"display/getter started history IO")
  t:step(false)
  __mock.timer.value=25;t:step(false)
  assert(t.audit.store().loading,"large history completed before pending-event test")
  assert(t.audit.store().pending["Shared Heli"]==1,"loading lost a qualified flight")
  local shared=t.audit.store()
  t.opts.CountSrc=2;t:update()
  __mock.modelName="New model";__mock.modelFilename="new.yml"
  t:create();t:step(true)
  assert(t.audit.store()==shared,"owner handoff replaced the shared load job")
  t:finishLoad(false)
  values["Shared Heli"]=8
  assertHistory(t,values)
  assert(shared.dirty and not shared.pending,"load completion lost pending count or failed to mark dirty")
  assert(fs.files[historyPath]==text,"load completion saved in the same callback")
  t:step(false)
  assert(not shared.dirty and not shared.error,"following callback did not save transferred count")
  assert(fs.files[historyPath..".bak"]==text,"dirty handoff did not preserve backup")
  local committed=fs.files[historyPath]
  t:step(false);t:step(true)
  assert(fs.files[historyPath]==committed,"Rotorflight mode counted the old event twice")
  local calls=historyIO()
  t:settle(true)
  assert(historyIO()==calls,"fresh Rotorflight mode restarted local history IO")
  assertHistory(t,values)
  t:report(scenario)
elseif scenario=="partial-zone" or scenario=="partial-zone-theme9" then
  assert(variant=="KSE4" and LCD_W==800 and LCD_H==480,"partial-zone target")
  local t=fixture(4,2)
  t.zone={x=20,y=15,w=700,h=400}
  if scenario=="partial-zone-theme9" then t.opts.Theme=9 end
  t:initialize();t:connect("RS4 Venom");t:settle(true)
  local g,v=t.audit.geometry,t.audit.view()
  assert(not g.compact and not g.screen800x480,"partial zone did not use ordinary noncompact geometry")
  assert(g.w==700 and g.h==400,"partial zone fell back to full-screen dimensions")
  local builds=t.builds
  local amps,esc=v.tiles[1].value,v.tiles[4].value
  local snapshots={}
  for _,item in ipairs({amps,esc,v.bottom.ticks[1],v.bottom.ticks[2],
                        v.bottom.ticks[3],v.bottom.ticks[4],v.bottom.ticks[5]}) do
    local p=item.properties
    snapshots[#snapshots+1]={item=item,x=p.x,y=p.y,w=p.w,align=p.align}
  end
  assert(amps.properties.align==0 and esc.properties.align==0,"Electric values do not use ordinary left alignment")
  t:disconnect();t:step(true);t:connect("Nitro N");t:settle(true)
  assert(amps.properties.align~=0 and esc.properties.align~=0,"Nitro placeholders did not center")
  for _,tick in ipairs(v.bottom.ticks) do assert(tick.hidden,"Nitro retained an Electric footer tick") end
  t:disconnect();t:step(true);t:connect("RS4 Venom");t:settle(true)
  assert(t.audit.view()==v and t.builds==builds,"partial-zone transition rebuilt retained UI")
  for _,snapshot in ipairs(snapshots) do
    local p=snapshot.item.properties
    assert(p.x==snapshot.x and p.y==snapshot.y and p.w==snapshot.w,
      "retained Electric value/footer moved after type transition")
    assert(p.align==snapshot.align,"retained Electric value/footer alignment not restored")
    assert(not snapshot.item.hidden,"Electric value/footer remained hidden after Nitro")
  end
  assert(amps.properties.text=="0" and esc.properties.text=="25","Electric values did not return")
  t:report(scenario)
else error("Unknown CPU scenario "..scenario) end
