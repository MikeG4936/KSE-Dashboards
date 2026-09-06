-- KSE admission policy only; RF Tool retains its transport and retry policy.
local Admission = {}

function Admission.sample(name)
  -- Resolve every safety sample by name. Display caches can survive sensor-ID
  -- reuse, and getValue cannot establish currentness/freshness.
  if type(_G.getFieldInfo) ~= "function"
     or type(_G.getSourceValue) ~= "function" then return nil end
  local ok, info = pcall(_G.getFieldInfo, name)
  if not ok or type(info) ~= "table" or type(info.id) ~= "number" then return nil end
  local read, value, current, fresh = pcall(_G.getSourceValue, info.id)
  if type(value) == "table" then value = value.value end
  if not read or current ~= true or fresh ~= true
     or type(value) ~= "number" or value ~= value then return nil end
  return value
end

function Admission.disarmed(wgt)
  if not WidgetOwner.current(wgt) then return false, "ANOTHER KSE DASHBOARD IS ACTIVE" end
  local reason
  local arm = Admission.sample("ARM")
  local host = _G.rf2
  local hostState = type(host) == "table" and type(host.widget) == "table"
                    and host.widget.state or nil
  local queue = type(host) == "table" and host.mspQueue or nil
  local widget = type(host) == "table" and host.widget or nil
  local ok, info = pcall(model.getInfo)
  local name = ok and type(info) == "table" and (info.filename or info.name) or nil
  local linked, rssi = false, nil
  if type(_G.getRSSI) == "function" then linked, rssi = pcall(_G.getRSSI) end
  if OPT.simTelemetry or not linked or type(rssi) ~= "number" or not (rssi > 0)
     or type(name) ~= "string" then
    reason = "WAITING FOR LIVE TELEMETRY"
  elseif wgt.profileRfState == "armed" or hostState == "armed" then
    reason = "DISARM TO CHANGE PROFILE"
  elseif type(queue) ~= "table"
     or (wgt.profileRfState ~= "connected" and wgt.profileRfState ~= "disarmed")
     or (widget ~= nil and hostState ~= "connected" and hostState ~= "disarmed") then
    reason = "WAITING FOR RF TOOL CONNECTION"
  elseif arm == nil or arm < 0 or arm > 255 or arm > math.floor(arm) then
    reason = "WAITING FOR ARM TELEMETRY"
  elseif math.floor(arm) % 2 == 1 then
    reason = "DISARM TO CHANGE PROFILE"
  end
  if reason or wgt.mspContextProvider ~= host or wgt.mspContextModel ~= name
     or wgt.mspContextQueue ~= queue or wgt.mspContextWidget ~= widget then
    wgt.mspContextEpoch = (wgt.mspContextEpoch or 0) + 1
  end
  wgt.mspContextProvider, wgt.mspContextModel = host, name
  wgt.mspContextQueue, wgt.mspContextWidget = queue, widget
  if reason then return false, reason end
  return true
end

function Admission.capture(wgt, operation)
  operation.provider = wgt.mspContextProvider
  operation.modelName = wgt.mspContextModel
  operation.epoch = wgt.mspContextEpoch
  operation.heliType = OPT.heliType
end

function Admission.valid(wgt, operation)
  return operation ~= nil and Admission.disarmed(wgt)
     and operation.provider == wgt.mspContextProvider
     and operation.modelName == wgt.mspContextModel
     and operation.queue == wgt.mspContextQueue
     and operation.epoch == wgt.mspContextEpoch
     and operation.heliType == OPT.heliType
end

function Admission.cancelPending(operation)
  local queue = operation and operation.queue
  if not queue or type(queue.messageQueue) ~= "table" then return false end
  local pending, write = queue.messageQueue, 1
  local currentOwned = false
  local owned = {}
  for _, message in ipairs(operation.messages or {}) do owned[message] = true end
  currentOwned = owned[queue.currentMessage] == true
  for read=1,#pending do
    if not owned[pending[read]] then
      pending[write] = pending[read]
      write = write + 1
    end
  end
  for i=#pending,write,-1 do pending[i] = nil end
  -- Never clear private framing/receive buffers or modify an active request.
  return not currentOwned
end

return Admission
