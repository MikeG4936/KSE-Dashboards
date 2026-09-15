-- OFS3 CRSF: RxBt is pack voltage; Volt is RxBt/2 on M1 and RxBt/3
-- on M2 (OFS3 User Guide R6, p29). This does not identify individual aircraft.
function OMP_AUTO.reset()
  OMP_AUTO.ready, OMP_AUTO.cells, OMP_AUTO.name = false, nil, nil
  OMP_AUTO.status, OMP_AUTO.model = "CONNECT OMP", nil
  OMP_AUTO.candidate, OMP_AUTO.since, OMP_AUTO.lastTick = nil, nil, nil
  OMP_AUTO.packId, OMP_AUTO.cellId, OMP_AUTO.rpmId = nil, nil, nil
  OMP_AUTO.recheck = true
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
  if not getFieldInfoFn or type(model.getSensor) ~= "function" or not base then return end
  local ok, field = pcall(getFieldInfoFn, name)
  if not ok or type(field) ~= "table" or type(field.id) ~= "number" then return end
  local index = (field.id - base) / 3
  if index < 0 or index ~= math.floor(index) then return end
  local valid, sensor = pcall(model.getSensor, index)
  if not valid or type(sensor) ~= "table" or sensor.type ~= 0
     or sensor.name ~= name
     or sensor.unit ~= (name == "RPM" and _G.UNIT_RPMS or _G.UNIT_VOLTS)
     or sensor.instance ~= 0 or type(sensor.id) ~= "number" then return end
  -- Voltage-array telemetry uses pseudo sensor id FE, not wire frame id 0E.
  if name == "RxBt" then
    if sensor.id ~= 0x08 then return end
  elseif name == "RPM" then
    if sensor.id < 0x0C or sensor.id > 0xFF0C or sensor.id % 256 ~= 0x0C then return end
  elseif sensor.id < 0x80FE or sensor.id > 0xFFFE or sensor.id % 256 ~= 0xFE then
    return
  end
  local value, current, fresh = get(field.id)
  value = tonumber(value)
  if current and fresh and value and value >= 0 then return value, field.id end
end

-- Scan only when starting/finishing confirmation, never in steady flight.
-- Empty slots are tables; the first out-of-range index returns nil in EdgeTX.
function OMP_AUTO.uniqueSources()
  local pack, cell, rpm = 0, 0, 0
  for index = 0, 255 do
    local ok, sensor = pcall(model.getSensor, index)
    if not ok then return false end
    if sensor == nil then return pack == 1 and cell == 1 and rpm == 1 end
    if type(sensor) ~= "table" then return false end
    if sensor.name == "RxBt" then pack = pack + 1 end
    if sensor.name == "Volt" then cell = cell + 1 end
    if sensor.name == "RPM" then rpm = rpm + 1 end
    if pack > 1 or cell > 1 or rpm > 1 then return false end
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
  local valid, base = pcall(getFieldInfoFn, "telem1")
  base = valid and type(base) == "table" and base.id or nil
  local rpm, rpmId
  if live then rpm, rpmId = OMP_AUTO.sensor("RPM", base) end
  local stopped = rpm == 0
  if not live or not stopped then
    OMP_AUTO.candidate, OMP_AUTO.since = nil, nil
    if not live then OMP_AUTO.recheck = true end
    if not OMP_AUTO.ready then
      OMP_AUTO.display(widget, false, not live and "CONNECT OMP"
        or (rpm and "STOP MOTOR" or "CHECK RPM"))
    end
    return
  end
  local pack, packId = OMP_AUTO.sensor("RxBt", base)
  local cell, cellId = OMP_AUTO.sensor("Volt", base)
  local ratio = pack and cell and cell >= 2 and cell <= SAFETY.maxCellSanityV
                and pack / cell or nil
  local cells = ratio and math.floor(ratio + 0.5) or nil
  if not cells or (cells ~= 2 and cells ~= 3) or math.abs(ratio - cells) > 0.15 then
    OMP_AUTO.candidate, OMP_AUTO.since = nil, nil
    -- A gap alone cannot erase a confirmed flight. After a reconnect, however,
    -- require new ground evidence before attributing flights to that name.
    if not OMP_AUTO.ready or OMP_AUTO.recheck or (pack and cell) then
      OMP_AUTO.display(widget, false, "CHECK RxBt/Volt")
    end
    return
  end
  local replaced = packId ~= OMP_AUTO.packId or cellId ~= OMP_AUTO.cellId
                   or rpmId ~= OMP_AUTO.rpmId
  if OMP_AUTO.ready and not OMP_AUTO.recheck and not replaced
     and cells == OMP_AUTO.cells then return end
  OMP_AUTO.display(widget, false, "CONFIRMING OMP")
  if cells ~= OMP_AUTO.candidate or replaced or not OMP_AUTO.since
     or now < OMP_AUTO.since then
    OMP_AUTO.packId, OMP_AUTO.cellId = packId, cellId
    OMP_AUTO.rpmId = rpmId
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
  OMP_AUTO.recheck, OMP_AUTO.candidate, OMP_AUTO.since = false, nil, nil
  if changed then
    resetSessionStats()
    resetSessionEvidence()
    timerThresholdArmed = nil
    widget.layoutSignature = nil
  end
  OMP_AUTO.display(widget, true, nil)
end
