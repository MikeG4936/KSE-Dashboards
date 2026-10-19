-- Radio boundaries only: every production lifecycle/render callback is real.
-- Distinct opaque alignment flags through the same ROM-style lookup as EdgeTX
-- make retained alignment changes observable (all-zero fallbacks hide them).
do
  local inherited=getmetatable(_G).__index
  getmetatable(_G).__index=setmetatable({CENTER=4,RIGHT=8},{__index=inherited})
end
-- Evaluate retained properties in native order. Event handlers (press/close)
-- are not display properties and must never run during a refresh measurement.
local properties={"color","opacity","size","pos","active","endAngle",
                  "startAngle","rotation","text","font","align","file"}
local function evaluate(item)
  local p=item.properties
  if type(p.visible)=="function" then item.hidden=not p.visible() end
  if item.hidden then return end
  for _,key in ipairs(properties) do
    if type(p[key])=="function" then p[key]() end
  end
end
local function fixture(selection,counter)
  _G.__KSE_WIDGET_OWNER_V1=nil
  __mock.now=1000;__mock.modelName="Shared Heli";__mock.modelFilename="shared.yml"
  __mock.timer={start=0,value=0};__mock.values={};__mock.events={}
  model.getInfo=function() return {name=__mock.modelName,filename=__mock.modelFilename} end
  fs.files={["/WIDGETS/"..variant.."/default.png"]=defaultImage}
  fs.calls={};fs.faults={};fs.online=true
  local t={rssi=0,objects={},builds=0,requests={},peaks={},calls=0}
  local id=100
  for name,value in pairs({Hspd=0,Tspd=0,Vbec=7.6,ARM=0,RQly=100,["Cel#"]=6,
      Vcel=4,Vbat=24,["Bat%"]=100,Curr=0,Capa=0,Tesc=25,Gov=0,
      ["BAT#"]=1,["PID#"]=1,["RTE#"]=1,["tx-voltage"]=8.1}) do
    id=id+1
    local item={id=id,value=value}
    __mock.values[name]=item;__mock.values[id]=item
  end
  getRSSI=function() return t.rssi end
  local function object(first,second)
    local item={properties=second or first or {}}
    function item:set(values) for k,v in pairs(values) do self.properties[k]=v end end
    function item:show() self.hidden=false end
    function item:hide() self.hidden=true end
    t.objects[#t.objects+1]=item
    evaluate(item)
    return item
  end
  lvgl={clear=function() t.builds=t.builds+1;t.objects={} end,
    label=object,rectangle=object,image=object,hline=object,vline=object,arc=object}
  t.host={state="initializing",background=function() end}
  rf2={apiVersion=12.09,rfToolApiVersion=1,widget=t.host,registerWidget=function() end}
  t.provider=rf2
  t.queue={messageQueue={},add=function(q,message)
      t.requests[#t.requests+1]=message;q.messageQueue[#q.messageQueue+1]=message end,
    processQueue=function() end,
    isProcessed=function(q) return not q.currentMessage and #q.messageQueue==0 end,
    clear=function() error("KSE must preserve RF transport") end}
  rf2.mspQueue=t.queue
  t.api=dofile(dashboardPath);t.audit=t.api.audit
  t.opts={}
  for _,option in ipairs(t.api.options) do t.opts[option[1]]=option[3] end
  t.opts.HeliType=selection or 1;t.opts.CountSrc=counter or 2;t.opts.MotorSw=99
  function t:dispatch() for _,item in ipairs(self.objects) do evaluate(item) end end
  function t:callback(label,fn,display)
    self.calls=self.calls+1
    local cost,result=measureSource(dashboardPath,cpuBudget,function()
      local value=fn()
      if display then self:dispatch() end
      return value
    end)
    assert(cost>0,"source filter failed to observe production callback "..label)
    self.peaks[label]=math.max(self.peaks[label] or 0,cost)
    if cpuTarget>0 then assert(cost<=cpuTarget,label.." exceeds dashboard margin: "..cost) end
    return result
  end
  function t:create()
    self.widget=self:callback("create",function()
      return self.api.create(self.zone or {x=0,y=0,w=LCD_W,h=LCD_H},self.opts)
    end)
    self.audit.owner.host(self.host,self.provider)
  end
  function t:update()
    self:callback("update",function() self.api.update(self.widget,self.opts) end,true)
  end
  function t:step(visible,delta)
    __mock.now=__mock.now+(delta or 20)
    self:callback(visible and "refresh" or "background",function()
      if visible then self.api.refresh(self.widget,nil,nil)
      else self.api.background(self.widget) end
    end,visible)
  end
  function t:initialize() self:create();self:update();self:step(true) end
  function t:connect(name) self.rssi=100;self.host.state="disarmed";self.provider.modelName=name end
  function t:disconnect() self.rssi=0;self.host.state="disconnected";self.provider.modelName=nil end
  function t:settle(visible) for _=1,5 do self:step(visible) end end
  function t:finishLoad(visible)
    for _=1,1000 do
      local state=self.audit.store()
      if not state.loading then return end
      assert(state.cache==nil and not state.writable,"partial history published while loading")
      assert(not state.error,"loading alone must not show a storage failure")
      self:step(visible)
    end
    error("history loading did not finish")
  end
  function t:finishSave(visible)
    for _=1,100 do
      if not self.audit.store().dirty then return end
      self:step(visible)
    end
    error("history saving did not finish")
  end
  function t:hasText(text)
    for _,item in ipairs(self.objects) do
      local value=item.properties.text
      if type(value)=="function" then value=value() end
      if not item.hidden and value==text then return true end
    end
    return false
  end
  function t:report(name)
    for callback,cost in pairs(self.peaks) do
      print("CPU|"..name.."|"..callback.."|"..cost)
    end
  end
  return t
end
local historyPath="/flights-count.csv"
local function seedHistory(t,count)
  local values={["Shared Heli"]=7,["New model"]=17}
  for i=1,count-2 do values[string.format("M%03d",i)]=i end
  local text=assert(t.audit.Storage.serialize(values))
  fs.files[historyPath]=text
  return values,text
end
local function assertHistory(t,values)
  local state=t.audit.store()
  assert(not state.loading,"history still loading")
  assert(state.cache,"history not published")
  local expected,actual=0,0
  for name,value in pairs(values) do expected=expected+1;assert(state.cache[name]==value,"wrong history count: "..name) end
  for _ in pairs(state.cache) do actual=actual+1 end
  assert(actual==expected,"history lost or invented rows")
end
local function historyIO()
  local count=0
  for _,call in ipairs(fs.calls) do
    if string.find(call,historyPath,1,true) then count=count+1 end
  end
  return count
end
local function historyWrites()
  local count=0
  for _,call in ipairs(fs.calls) do
    if string.find(call,historyPath,1,true) and (string.find(call,"^openw:")
       or string.find(call,"^rename:") or string.find(call,"^del:")) then count=count+1 end
  end
  return count
end
