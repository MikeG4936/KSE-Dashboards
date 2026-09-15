-- OFS3 CRSF: RxBt is pack voltage; Volt is RxBt/2 on M1 and RxBt/3
-- on M2 (OFS3 User Guide R6, p29). This does not identify individual aircraft.
function OMP_AUTO.reset()
  OMP_AUTO.ready, OMP_AUTO.cells, OMP_AUTO.name = false, nil, nil
  OMP_AUTO.status, OMP_AUTO.model = "CONNECT OMP", nil
  OMP_AUTO.candidate, OMP_AUTO.since, OMP_AUTO.lastTick = nil, nil, nil
  OMP_AUTO.packId, OMP_AUTO.cellId = nil, nil
  OMP_AUTO.observed = {}
end

function OMP_AUTO.display(widget, ready, status)
  if OMP_AUTO.ready ~= ready or OMP_AUTO.status ~= status then
    if OMP_AUTO.ready and not ready then timerThresholdArmed = nil end
    OMP_AUTO.ready, OMP_AUTO.status = ready, status
    A.lastDataTick, widget.kseUiDirty = -1, true
    clearFrameCache()
  end
end

-- Resolve the current slot each time. Cached display metadata must not let
-- deleted/reused sensor slots establish a new aircraft identity. "telem1"
-- supplies EdgeTX's source base without hard-coding radio-specific indexes.
function OMP_AUTO.sensor(name, base)
  local previous = OMP_AUTO.observed[name]
  OMP_AUTO.observed[name] = nil
  if not getFieldInfoFn or type(model.getSensor) ~= "function" or not base then return end
  local ok, field = pcall(getFieldInfoFn, name)
  if not ok or type(field) ~= "table" or type(field.id) ~= "number" then return end
  local index = (field.id - base) / 3
  if index < 0 or index ~= math.floor(index) then return end
  local valid, sensor = pcall(model.getSensor, index)
  if not valid or type(sensor) ~= "table" or sensor.type ~= 0
     or sensor.name ~= name
     or sensor.unit ~= _G.UNIT_VOLTS
     or sensor.instance ~= 0 or type(sensor.id) ~= "number" then return end
  -- Voltage-array telemetry uses pseudo sensor id FE, not wire frame id 0E.
  if name == "RxBt" then
    if sensor.id ~= 0x08 then return end
  elseif sensor.id < 0x80FE or sensor.id > 0xFFFE or sensor.id % 256 ~= 0xFE then
    return
  end
  if previous and (previous.id ~= field.id or previous.nativeId ~= sensor.id) then return end
  local value, current, fresh = get(field.id)
  value = tonumber(value)
  if not current or not value or value < 0 or not (value < math.huge) then return end
  -- EdgeTX's fresh flag is a short pulse; independently observe each source.
  -- Read its actual current value every time, never a stored voltage value.
  local now = frameNow()
  local tick = fresh and now or (previous and previous.tick)
  if not tick or now < tick or now - tick > OMP_AUTO.updateWindow then
    return nil, field.id, true -- Valid source, waiting for an observed update.
  end
  previous = previous or {}
  previous.id, previous.nativeId, previous.tick = field.id, sensor.id, tick
  OMP_AUTO.observed[name] = previous
  return value, field.id, true
end

-- Scan only when starting/finishing confirmation, never while identity is locked.
-- Empty slots are tables; the first out-of-range index returns nil in EdgeTX.
function OMP_AUTO.uniqueSources()
  local pack, cell = 0, 0
  for index = 0, 255 do
    local ok, sensor = pcall(model.getSensor, index)
    if not ok then return false end
    if sensor == nil then return pack == 1 and cell == 1 end
    if type(sensor) ~= "table" then return false end
    if sensor.name == "RxBt" then pack = pack + 1 end
    if sensor.name == "Volt" then cell = cell + 1 end
    if pack > 1 or cell > 1 then return false end
  end
  return false
end

function OMP_AUTO.sync(widget)
  if not OPT.ompAuto then return end
  local info = getModelInfo()
  local identity = info and (info.filename or info.name)
  if identity ~= OMP_AUTO.model then
    OMP_AUTO.reset()
    OMP_AUTO.model = identity
    resetSessionStats()
    resetSessionEvidence()
    timerThresholdArmed = nil
    clearFrameCache()
    widget.layoutSignature = nil
  end
  local now = frameNow()
  local last = OMP_AUTO.lastTick
  if last and now >= last and now - last < 10
     and (not OMP_AUTO.since or now - OMP_AUTO.since < OMP_AUTO.confirmTicks) then return end
  OMP_AUTO.lastTick = now
  local ok, rssi = pcall(getRSSI)
  local live = ok and type(rssi) == "number" and rssi > 0
  if not live then
    OMP_AUTO.observed.RxBt, OMP_AUTO.observed.Volt = nil, nil
    OMP_AUTO.candidate, OMP_AUTO.since = nil, nil
    OMP_AUTO.display(widget, false, "CONNECT OMP")
    return
  end
  -- A confirmed aircraft stays selected for this connection, independent of
  -- RPM, ARM or subsequent voltage changes. Only disconnect/reset unlocks it.
  if OMP_AUTO.ready then return end
  if last and (now < last or now - last > OMP_AUTO.updateWindow) then
    OMP_AUTO.observed.RxBt, OMP_AUTO.observed.Volt = nil, nil
    OMP_AUTO.candidate, OMP_AUTO.since = nil, nil
  end
  local valid, base = pcall(getFieldInfoFn, "telem1")
  base = valid and type(base) == "table" and base.id or nil
  local pack, packId, packValid = OMP_AUTO.sensor("RxBt", base)
  local cell, cellId, cellValid = OMP_AUTO.sensor("Volt", base)
  if not packValid or not cellValid then
    OMP_AUTO.observed.RxBt, OMP_AUTO.observed.Volt = nil, nil
    OMP_AUTO.candidate, OMP_AUTO.since = nil, nil
    OMP_AUTO.display(widget, false, "CHECK RxBt/Volt")
    return
  end
  local ratio = pack and cell and cell >= 2 and cell <= SAFETY.maxCellSanityV
                and pack / cell or nil
  local cells = ratio and math.floor(ratio + 0.5) or nil
  if not cells or (cells ~= 2 and cells ~= 3) or math.abs(ratio - cells) > 0.15 then
    OMP_AUTO.candidate, OMP_AUTO.since = nil, nil
    OMP_AUTO.display(widget, false, "CHECK RxBt/Volt")
    return
  end
  local replaced = packId ~= OMP_AUTO.packId or cellId ~= OMP_AUTO.cellId
  OMP_AUTO.display(widget, false, "CONFIRMING OMP")
  if cells ~= OMP_AUTO.candidate or replaced or not OMP_AUTO.since
     or now < OMP_AUTO.since then
    OMP_AUTO.packId, OMP_AUTO.cellId = packId, cellId
    OMP_AUTO.candidate, OMP_AUTO.since = nil, nil
    if OMP_AUTO.uniqueSources() then
      OMP_AUTO.candidate, OMP_AUTO.since = cells, now
    else
      OMP_AUTO.display(widget, false, "CHECK SENSORS")
    end
    return
  end
  if now - OMP_AUTO.since < OMP_AUTO.confirmTicks then return end
  if not OMP_AUTO.uniqueSources() then
    OMP_AUTO.candidate, OMP_AUTO.since = nil, nil
    OMP_AUTO.display(widget, false, "CHECK SENSORS")
    return
  end
  local changed = cells ~= OMP_AUTO.cells
  OMP_AUTO.cells = cells
  OMP_AUTO.name = cells == 2 and "OMP M1" or "OMP M2"
  OMP_AUTO.candidate, OMP_AUTO.since = nil, nil
  if changed then
    resetSessionStats()
    resetSessionEvidence()
    timerThresholdArmed = nil
    widget.layoutSignature = nil
  end
  OMP_AUTO.display(widget, true, nil)
end
