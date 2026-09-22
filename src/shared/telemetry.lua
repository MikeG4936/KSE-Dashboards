local flightStore = Storage.new(FLIGHTS_PATH)
local function trim(s) return string.match(s or "", "^%s*(.-)%s*$") end
local function sanitizeFsName(name)
  if not name then return nil end
  local s = (string.gsub(name, "[\\/:*?\"<>|]", "_"))
  return trim(s)
end
local function get(name)
  local source, sourceKnown = name, false
  if type(name) == "string" and getFieldInfoFn then
    local key, now = "$" .. name, frameNow()
    local cached = RESOLVED[key]
    -- Motor-stop evidence cannot use an id cached before sensor discovery.
    local immediate = name == "ARM" or name == "Gov" or name == "Hspd" or name == "RPM"
                      or (OPT.ompAuto and name == "RxBt")
    if immediate or not cached or now < cached.tick or now - cached.tick >= 100 then
      local ok, info = pcall(getFieldInfoFn, name)
      cached = cached or {}
      cached.tick, cached.id = now, ok and type(info) == "table" and info.id or false
      RESOLVED[key] = cached
    end
    if not cached.id then return nil, false, false, false end
    source, sourceKnown = cached.id, true
  end
  local sourceValueFn = rawget(_G, "getSourceValue") or _G.getSourceValue
  if type(sourceValueFn) == "function" then
    local ok, value, current, fresh = pcall(sourceValueFn, source)
    if not ok or value == nil or current ~= true then
      return nil, false, fresh == true, sourceKnown
    end
    if type(value) == "table" then value = value.value end
    return value, value ~= nil, fresh == true, sourceKnown
  end
  -- Legacy values can support display; they cannot prove fresh motor-stop evidence.
  local ok, value = pcall(getValue, source)
  if not ok then return nil, false, false, sourceKnown end
  if type(value) == "table" then value = value.value end
  return value, value ~= nil, false, sourceKnown
end

local function getModelInfo()
  local v = F.modelInfo
  if v ~= nil then return v ~= false and v or nil end
  local ok, info = pcall(model.getInfo)
  v = ok and type(info) == "table" and info or false
  F.modelInfo = v
  return v ~= false and v or nil
end
local function getModelName()
  local v = F.modelName
  if v ~= nil then return v end
  local info = getModelInfo()
  local n = OPT.ompAuto and (OMP_AUTO.name or "OMPHOBBY")
            or (OPT.autoHeliType and AUTO_HELI.name or (info and info.name or nil))
  if not n or n == "" then n = "MODEL" end
  v = (string.gsub(n, ",", " "))
  F.modelName = v
  return v
end

-- Telemetry names are case-sensitive. Resolve each discovered source to its
-- numeric id, prefer getSourceValue() current-state reporting, and retain the
-- legacy getValue() path only as a compatibility fallback. Electric/Nitro use
-- the Rotorflight contract; OMPHOBBY uses the receiver's smaller contract.
-- Sensor helpers share one local binding to retain EdgeTX compiler headroom.
local sensors = {}
local ROTORFLIGHT_SENSOR = {
  headspeed        = "Hspd",
  tailHeadspeed    = "Tspd",
  becVoltage       = "Vbec",
  cellVoltage      = "Vcel",
  cellCount        = "Cel#",
  -- The AMPS tile (and its session maximum) always reads Rotorflight's
  -- dedicated current sensor rather than the ESC telemetry source.
  current          = "Curr",
  capacity         = "Capa",
  -- Rotorflight publishes getBatteryChargeLevel() here. With Smart Fuel
  -- enabled, this is the FC's sag-compensated/rate-limited estimate.
  batteryPercent   = "Bat%",
  escTemperature   = "Tesc",
  governorMode     = "Gov",
  batteryProfile   = "BAT#",
  pidProfile       = "PID#",
  rateProfile      = "RTE#",
  -- Pack voltage remains a separate input used to validate electric packs.
  packVoltage      = "Vbat",
}
local OMPHOBBY_SENSOR = {
  headspeed        = "RPM",
  packVoltage      = "RxBt",
  current          = "Curr",
  capacity         = "Capa",
  batteryPercent   = "Bat%",
  escTemperature   = "Temp",
}
function sensors.activeSensorName(key)
  local sensors = OPT.heliType == HELI_OMPHOBBY
                  and OMPHOBBY_SENSOR or ROTORFLIGHT_SENSOR
  return sensors[key]
end
function sensors.getSensorNumber(key)
  local name = sensors.activeSensorName(key)
  if not name then return nil end
  local v, current, fresh, exists = get(name)
  return tonumber(v), current, fresh, exists
end
-- Link quality is the one remaining name-variant fallback chain. Remember the
-- variant that resolves so later frames do not re-probe every candidate.
local NAMES = {
  lq = { "RQly", "RQLY", "LQ" },
}
function sensors.resolveNamed(key)
  local names = NAMES[key]
  local cached = RESOLVED[key]
  if cached then
    local raw, _, _, exists = get(cached)
    if exists then A.linkSourceKnown = true end
    local v = tonumber(raw)
    if v ~= nil then return v end
    RESOLVED[key] = nil
  end
  for i = 1, #names do
    local raw, _, _, exists = get(names[i])
    if exists then A.linkSourceKnown = true end
    local v = tonumber(raw)
    if v ~= nil then
      RESOLVED[key] = names[i]
      return v
    end
  end
  return nil
end
function sensors.getCellCount()
  local v = F.cellCount
  if v ~= nil then return v end
  if OPT.ompAuto then
    v = OMP_AUTO.ready and OMP_AUTO.cells or 0
    if v == 2 then
      D.isLiHV = true
      A.liHvHighSamples = SAFETY.liHvConfirmSamples
    end
  else
    v = sensors.getSensorNumber("cellCount") or 0
  end
  v = math.floor(v + 0.5)
  D.cellCountValid = v >= 1 and v <= SAFETY.maxCellCount
  if not D.cellCountValid then v = 0 end
  F.cellCount = v
  return v
end
function sensors.getPackVolt()
  local v = F.packVolt
  if v ~= nil then return v end
  v = sensors.getSensorNumber("packVoltage")
  D.packVoltageValid = v ~= nil and v > 0
                       and v <= SAFETY.maxCellCount * SAFETY.maxCellSanityV
  if not D.packVoltageValid then v = 0 end
  F.packVolt = v
  return v
end
function sensors.getCellVoltage()
  local v = F.cellVoltage
  if v ~= nil then return v end
  if OPT.heliType == HELI_OMPHOBBY then
    local cells = sensors.getCellCount()
    local packVoltage = sensors.getPackVolt()
    v = cells > 0 and packVoltage > 0 and packVoltage / cells or nil
  else
    v = sensors.getSensorNumber("cellVoltage")
  end
  D.cellVoltageValid = v ~= nil and v > 0
                       and v <= SAFETY.maxCellSanityV
  if not D.cellVoltageValid then v = 0 end
  F.cellVoltage = v
  return v
end
function sensors.getBatPct()
  local v = F.batPct
  if v ~= nil then return v end
  v = sensors.getSensorNumber("batteryPercent")
  D.batteryPercentValid = v ~= nil and v >= 0 and v <= 100
  if not D.batteryPercentValid then v = false end
  F.batPct = v
  return v
end
function sensors.getCapa()
  local v = F.capa
  if v ~= nil then return v end
  v = sensors.getSensorNumber("capacity")
  D.capacityValid = v ~= nil and v >= 0 and v <= 100000
  if not D.capacityValid then v = 0 end
  F.capa = v
  return v
end
function sensors.getCurr()
  local v = F.curr
  if v ~= nil then return v end
  v = sensors.getSensorNumber("current")
  local sane = v ~= nil and v >= -500 and v <= 1000
  if not sane then v = 0 end
  D.currentValid = sane
  F.curr = v
  return v
end
function sensors.getTemp()
  local v = F.temp
  if v ~= nil then return v end
  v = sensors.getSensorNumber("escTemperature")
  local sane = v ~= nil and v >= -40 and v <= 250
  if not sane then v = 0 end
  D.tempValid = sane
  F.temp = v
  return v
end
function sensors.getBec()
  local v = F.bec
  if v ~= nil then return v end
  v = sensors.getSensorNumber("becVoltage")
  local sane = v ~= nil and v > 0 and v <= 30
  D.becValid = sane
  if not D.becValid then v = 0 end
  F.bec = v
  return v
end
function sensors.getRxBatt()
  local v = F.rxBatt
  if v ~= nil then return v end
  -- Nitro Rx pack voltage uses the same Vbec resolver as the BEC tile.
  v = sensors.getBec()
  F.rxBatt = v
  return v
end
function sensors.getBattProfile()
  local v = F.battProfile
  if v ~= nil then return v end
  v = sensors.getSensorNumber("batteryProfile")
  local whole = v ~= nil and math.floor(v) or nil
  if whole == nil or v > whole
     or whole < 1 or whole > BATTERY_PROFILE_COUNT then
    v = nil
  else
    v = whole
  end

  if PROFILE_CONFIRMED.value then
    local age = frameNow() - (PROFILE_CONFIRMED.tick or 0)
    if v == PROFILE_CONFIRMED.value or age > 300 or age < 0 then
      PROFILE_CONFIRMED.value, PROFILE_CONFIRMED.tick = nil, nil
    else
      v = PROFILE_CONFIRMED.value
    end
  end
  F.battProfile = v
  return v
end
function sensors.getHeadspeed()
  local v = F.rpm
  if v ~= nil then return v end
  local current, fresh
  v, current, fresh = sensors.getSensorNumber("headspeed")
  D.rpmFresh = current == true and fresh == true
  local sane = v ~= nil and v >= 0 and v <= 100000
  if not sane then v = 0 end
  D.rpmValid = sane
  F.rpm = v
  return v
end
function sensors.getTailRpm()
  local v = F.trpm
  if v ~= nil then return v end
  v = sensors.getSensorNumber("tailHeadspeed")
  local sane = v ~= nil and v >= 0 and v <= 100000
  if not sane then v = 0 end
  D.tailRpmValid = sane
  F.trpm = v
  return v
end
function sensors.getGovernorMode()
  local cached = F.govNumber
  if cached ~= nil then return cached ~= false and cached or nil end
  if OPT.heliType == HELI_OMPHOBBY then
    D.govValid = false
    D.govFresh = false
    D.govCurrentInvalid = false
    F.govNumber = false
    return nil
  end
  local raw, current, fresh = sensors.getSensorNumber("governorMode")
  D.govFresh = current == true and fresh == true
  local whole = raw ~= nil and math.floor(raw) or nil
  local valid = whole ~= nil and not (raw > whole) and GOV_STATES[whole] ~= nil
  D.govValid = valid
  -- Missing/stale Gov may use the independent Hspd proof. A current but
  -- malformed or unknown enum is different: it must block that fallback.
  D.govCurrentInvalid = current == true and raw ~= nil and not valid
  F.govNumber = valid and whole or false
  return valid and whole or nil
end
function sensors.getGovState()
  local v = F.gov
  if v ~= nil then return v end
  if OPT.heliType == HELI_OMPHOBBY then
    v = "--"
  else
    local g = sensors.getGovernorMode()
    v = g == nil and "--" or GOV_STATES[g]
  end
  F.gov = v
  return v
end
function sensors.getTxVolt()
  local v = F.txVolt
  if v ~= nil then return v end
  -- Capture only the source value. get() also returns current/fresh/existence
  -- metadata, which must not spill into tonumber() as its optional base.
  local raw = get("tx-voltage")
  v = tonumber(raw) or 0
  if v > 100 then v = v / 1000 end
  if v < 0 or v > 20 then v = 0 end
  F.txVolt = v
  return v
end
-- EdgeTX v2.12.4 Radio Info: GET_TXBATT_BARS, then color from rounded pixels.
-- See docs/edgetx-2.12.4-battery-icon-comparison.md for commit-pinned sources.
-- Cache only the two range values for one second, not the entire API table.
function sensors.txBatteryState()
  local now = frameNow()
  if not sensors.txRangeAt or now < sensors.txRangeAt
     or now - sensors.txRangeAt >= 100 then
    sensors.txRangeAt = now
    sensors.txMin, sensors.txMax = nil, nil
    if type(getGeneralSettings) == "function" then
      local ok, settings = pcall(getGeneralSettings)
      if ok and type(settings) == "table" then
        local low, high = settings.battMin, settings.battMax
        if type(low) == "number" and type(high) == "number"
           and low > 0 and high > low and high <= 25.5 then
          low, high = math.floor(low * 10 + 0.5), math.floor(high * 10 + 0.5)
          if high > low then sensors.txMin, sensors.txMax = low, high end
        end
      end
    end
  end
  local volts = sensors.getTxVolt()
  if not (volts > 0 and volts <= 20) then return nil end
  local low, high = sensors.txMin, sensors.txMax
  if not low or not high then return nil end
  -- Use the physical display, not the widget zone, for native layout scaling.
  local width, green, amber = 20, 12, 5
  if G.screenW == 800 then width, green, amber = 28, 17, 7 end
  -- Reconstruct firmware's integer tenths to avoid Lua float boundary drift.
  local voltage = math.floor(volts * 10 + 0.5)
  local bars = math.floor((width * math.max(0, voltage - low)
                          + math.floor((high - low) / 2)) / (high - low))
  bars = math.min(width, bars)
  return bars / width, bars >= green and 3 or bars >= amber and 2 or 1
end
-- Display only: getRSSI() exposes the same filtered radio value used by
-- EdgeTX Radio Info. Keep getRqly() and its safety/link evidence unchanged.
function sensors.txSignalBars()
  if type(getRSSI) ~= "function" then return 0 end
  local ok, value = pcall(getRSSI)
  if not ok or type(value) ~= "number" or not (value >= 0 and value <= 100) then
    return 0
  end
  return value >= 80 and 5 or value >= 60 and 4 or value >= 50 and 3
         or value >= 40 and 2 or value >= 30 and 1 or 0
end
function sensors.signalPercent(raw)
  local v = tonumber(raw)
  if v == nil then return nil end
  local pct
  if v < 0 then
    pct = ((v + 120) / 80) * 100
  elseif v <= 100 then
    pct = v
  elseif v <= 255 then
    pct = (v / 255) * 100
  else
    pct = 100
  end
  if pct < 0 then pct = 0 end
  if pct > 100 then pct = 100 end
  return pct
end
function sensors.getRqly()
  local v = F.rqly
  if v ~= nil then return v end
  A.linkSourceKnown = false
  v = sensors.resolveNamed("lq")
  if v == nil then
    local rssi
    if getRSSI then
      local ok, r = pcall(getRSSI)
      if ok then rssi = tonumber(r) end
    end
    if rssi ~= nil and rssi ~= 0 then A.linkSourceKnown = true end
    if rssi == nil or rssi == 0 then
      local raw, _, _, exists = get("RSSI")
      if exists then A.linkSourceKnown = true end
      if raw ~= nil then rssi = tonumber(raw) end
    end
    v = sensors.signalPercent(rssi)
  end
  v = tonumber(v) or 0
  if v < 0 or v > 100 then v = sensors.signalPercent(v) or 0 end
  if v > 0 then A.linkSourceSeen = true end
  F.rqly = v
  return v
end
function sensors.percentFromCellVoltage(cellVolts, isLiHV)
  if not cellVolts or cellVolts <= 0 then return 0 end
  local minV = 3.3
  local maxV = isLiHV and 4.35 or 4.2
  local pct = (cellVolts - minV) / (maxV - minV) * 100
  if pct < 0 then pct = 0 end
  if pct > 100 then pct = 100 end
  return pct
end
-- Rotorflight publishes its FC-side charge estimate as Bat%. In Electric mode
-- that value is authoritative even when Vcel is not configured. A positive
-- Bat% is sufficient evidence by itself; a zero also needs live Vcel or Vbat
-- so an FC powered over USB without a flight pack is shown as NO DATA instead
-- of an empty battery. OMPHOBBY keeps its stricter RxBt + M1/M2 contract.
function sensors.selectFlightBatteryPercent(heliType, sensorPercent, sensorValid,
                                          voltagePercent, hasCellVoltage,
                                          hasPackVoltage)
  local raw = tonumber(sensorPercent)
  if heliType == HELI_ELECTRIC then
    local fcPercentUsable = sensorValid and raw ~= nil
                            and raw >= 0 and raw <= 100
                            and (raw > 0 or hasCellVoltage or hasPackVoltage)
    if fcPercentUsable then return raw, true, "fc" end
  elseif heliType == HELI_OMPHOBBY then
    local ompPercentUsable = hasCellVoltage and sensorValid and raw ~= nil
                             and raw >= 0 and raw <= 100
    if ompPercentUsable then return raw, true, "telemetry" end
  else
    return 0, false, nil
  end
  if voltagePercent ~= nil then return voltagePercent, true, "voltage" end
  return 0, false, nil
end
function sensors.calculateAdjustedPercent(actual, reserve)
  if not actual or actual <= 0 then return 0 end
  reserve = reserve or 0
  if reserve >= 100 then return 0 end
  local usable = 100 - reserve
  local adj = ((actual - reserve) / usable) * 100
  if adj < 0 then adj = 0 end
  if adj > 100 then adj = 100 end
  return adj
end

-- UI adapters format these values; validity and pending-state semantics are common.
function sensors.profileIndexValid(value)
  return type(value) == "number" and value >= 1 and value <= 6
         and not (value > math.floor(value))
end
function sensors.profilePair()
  local pid, rate = sensors.getSensorNumber("pidProfile"), sensors.getSensorNumber("rateProfile")
  return pid, rate, A.linkAvailable and sensors.profileIndexValid(pid)
                    and sensors.profileIndexValid(rate)
end
function sensors.flightStatusPending()
  return FC.status == "LOADING" or FC.status == "WAITING"
         or FC.status == "STARTING" or FC.status == "INITIALIZING"
end
