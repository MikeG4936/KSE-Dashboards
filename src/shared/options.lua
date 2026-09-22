local function clearFrameCache()
  for k in pairs(F) do F[k] = nil end
end
-- Localize the hottest host globals so per-call lookups skip the global table.
local getValue = getValue
local getTime  = getTime
-- getTime(), cached once per frame. Alert paths ask for "now" repeatedly
-- within a single frame; this collapses those into one host call.
local function frameNow()
  local t = F.now
  if t ~= nil then return t end
  t = (getTime and getTime()) or 0
  F.now = t
  return t
end
local SRC = {}
local function getValSrc(srcId)
  if not srcId or srcId == 0 then return nil end
  local ok, v = pcall(getValue, srcId)
  if not ok or v == nil then return nil end
  if type(v) == "table" then v = v.value end
  return tonumber(v)
end
-- Settings store and numeric editor use volts with exactly two decimals.
local function parseVolt(value, default)
  if type(value)~="string" or not string.match(value,"^%d%.%d%d$") then return default end
  return tonumber(value) or default
end
local function validRxRange(low, high)
  -- EdgeTX uses 32-bit floats: 8.40 - 8.30 can be just below 0.10.
  return low ~= nil and high ~= nil and low >= 4 and high <= 9
         and high - low + 0.000001 >= 0.1
end
local getFieldInfoFn = getFieldInfo
local getSourceNameFn = getSourceName
local function isPhysicalMotorSource(src)
  local id = tonumber(src)
  if not id or id == 0 then return false end

  if getFieldInfoFn then
    local ok, info = pcall(getFieldInfoFn, id)
    if ok and type(info) == "table" then
      local name = string.upper(tostring(info.name or ""))
      local desc = string.upper(tostring(info.desc or ""))
      if string.match(name, "^S[A-Z]$") or string.match(desc, "^SWITCH%s+[A-Z]") then
        return true
      end
    end
  end
  if getSourceNameFn then
    local ok, name = pcall(getSourceNameFn, id)
    if ok and string.match(string.upper(tostring(name or "")), "^S[A-Z]$") then
      return true
    end
  end

  return false
end
-- @include variant:option_theme.lua
local function applyOptions(opts)
  opts = opts or {}
  G.applyOptionTheme(tonumber(opts.Theme) or 0)
  minFlightDur = math.max(1, math.min(120, tonumber(opts.MinFlight) or TOPBAR_MIN_DUR_DEFAULT))
  OPT.flightCounter = FC.ROTORFLIGHT
  OPT.simTelemetry = false
  local sgInfo = type(getFieldInfo) == "function" and getFieldInfo("SG") or nil
  local defaultMotorSwitch = type(sgInfo) == "table" and sgInfo.id or 0
  SRC.motorSwitch = defaultMotorSwitch
  if opts then
    -- The Motor Switch is the only mapped source. Rotorflight Gov/Hspd or OMP
    -- RPM telemetry validates what a movement means; other sensors auto-detect.
    SRC.motorSwitch = opts.MotorSw or defaultMotorSwitch
    -- OMP Auto resolves to the shared OMP telemetry implementation.
    -- OMPHOBBY shares the percentage bar but has its own telemetry contract.
    local bb = tonumber(opts.HeliType) or 1
    if not (bb >= 1 and bb <= OMP_AUTO.option) or bb > math.floor(bb) then bb = 1 end
    OPT.ompAuto = bb == OMP_AUTO.option or bb == HELI_OMPHOBBY
    if OPT.ompAuto then bb = HELI_OMPHOBBY end
    local automatic = bb == AUTO_HELI.option
    if automatic then
      bb = OPT.heliType == HELI_NITRO and HELI_NITRO or HELI_ELECTRIC
      if not OPT.autoHeliType then
        AUTO_HELI.ready, AUTO_HELI.name = false, nil
        AUTO_HELI.status = "WAITING FOR FC NAME"
      end
    end
    OPT.autoHeliType = automatic
    OPT.heliType = bb
    OPT.battBarMode = (bb == HELI_NITRO) and 1 or 0
    OPT.reservePct  = tonumber(opts.BattRsv) or 20
    if OPT.reservePct < 0 then OPT.reservePct = 0 end
    if OPT.reservePct > 50 then OPT.reservePct = 50 end
    OPT.battVoice   = (opts.BattVoice == 1 or opts.BattVoice == true)
    -- The editor uses one-based 15-second steps: 1=Off, 25=06:00.
    local choice = opts.FuelCheck
    if choice == nil then choice = 25 end
    local fuelSeconds = type(choice) == "number" and choice >= 1 and choice <= 121
                        and choice <= math.floor(choice) and (choice - 1) * 15 or 0
    if OPT.fuelCheckSeconds ~= fuelSeconds then A.fuelCheckArmed = nil end
    OPT.fuelCheckSeconds = fuelSeconds
    local countMode = tonumber(opts.CountSrc)
    if countMode ~= FC.RADIO
       and countMode ~= FC.ROTORFLIGHT then
      countMode = FC.ROTORFLIGHT
    end
    OPT.flightCounter = bb == HELI_OMPHOBBY and FC.RADIO or countMode
    local parsedMin = parseVolt(opts.RxPackMin or "6.60", nil)
    local parsedMax = parseVolt(opts.RxPackMax or "8.40", nil)
    OPT.rxPackMin = parsedMin or 6.6
    OPT.rxPackMax = parsedMax or 8.4
    OPT.rxPackValid = validRxRange(parsedMin, parsedMax)
  end
  A.motorSourcePhysical = isPhysicalMotorSource(SRC.motorSwitch)
  A.motorSourceReadable = A.motorSourcePhysical
                          and getValSrc(SRC.motorSwitch) ~= nil
  if OPT.simTelemetry then
    A.motorConfigError = nil
  elseif not A.motorSourcePhysical then
    A.motorConfigError = "SELECT A PHYSICAL MOTOR SWITCH"
  elseif not A.motorSourceReadable then
    A.motorConfigError = "MOTOR SWITCH UNAVAILABLE"
  else
    A.motorConfigError = nil
  end
end
local modelImageName = nil
local modelImagePath = nil
