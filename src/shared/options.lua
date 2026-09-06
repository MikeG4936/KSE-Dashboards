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
-- Parse an Rx-pack voltage typed as text ("6.60"), tolerant of whether EdgeTX
-- text entry offers a ".", and backward-compatible with the old integer scale:
--   <=15 -> volts as typed (6.6) ; 16-150 -> old tenths (66->6.6) ; >150 -> hundredths (660->6.6)
local function parseVolt(s, default)
  local str = string.match(tostring(s or ""), "^%s*(.-)%s*$")
  local validText = string.match(str, "^%d+$")
                    or string.match(str, "^%d+[.,]%d+$")
                    or string.match(str, "^[.,]%d+$")
  if not validText then return default end
  str = string.gsub(str, ",", ".")
  local v = tonumber(str)
  if not v or v <= 0 then return default end
  if v > 150 then return v / 100 end
  if v > 15  then return v / 10  end
  return v
end
local getFieldInfoFn = getFieldInfo
local getSourceNameFn = getSourceName
local function isPhysicalMotorSource(src)
  local id = tonumber(src)
  if not id or id == 0 then return false end

  local inspected = false
  if getFieldInfoFn then
    local ok, info = pcall(getFieldInfoFn, id)
    inspected = ok
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
    inspected = inspected or ok
    if ok and string.match(string.upper(tostring(name or "")), "^S[A-Z]$") then
      return true
    end
  end

  -- Older supported firmwares may not expose source inspection. A configured,
  -- readable SOURCE is still safer than silently falling back to a channel.
  return not inspected
end
-- @include variant:option_theme.lua
local function applyOptions(opts)
  opts = opts or {}
  G.applyOptionTheme(tonumber(opts.Theme) or 0)
  local rawBatt = tonumber(opts and opts.TxBatt) or 0
  txIsLiIon = (rawBatt == 2)
  local rawDur = tonumber(opts and (opts.MinFlight
                                    or opts["KSE Counter Min (sec)"]
                                    or opts["Min. Flight Time (sec)"]
                                    or opts.TopMinDur))
                 or TOPBAR_MIN_DUR_DEFAULT
  if rawDur < 0 then rawDur = math.abs(rawDur) end
  if rawDur < 1 then rawDur = 1 end
  minFlightDur = rawDur
  OPT.flightCounter = FC.ROTORFLIGHT
  OPT.simTelemetry = false
  local sgInfo = type(getFieldInfo) == "function" and getFieldInfo("SG") or nil
  local defaultMotorSwitch = type(sgInfo) == "table" and sgInfo.id or 0
  SRC.motorSwitch = defaultMotorSwitch
  if opts then
    -- The Motor Switch is the only mapped source. Rotorflight Gov/Hspd or OMP
    -- RPM telemetry validates what a movement means; other sensors auto-detect.
    SRC.motorSwitch = opts.MotorSw or opts["Motor Switch"]
                      or defaultMotorSwitch
    -- Heli Type CHOICE (1-based): Electric=1, Nitro=2, OMPHOBBY=3, Auto=4.
    -- OMPHOBBY shares the percentage bar but has its own telemetry contract.
    local bb = tonumber(opts.HeliType or opts["Heli Type"]) or 1
    if not (bb >= 1 and bb <= 4) or bb > math.floor(bb) then bb = 1 end
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
    OPT.reservePct  = tonumber(opts.BattRsv or opts["Batt Reserve %"]) or 20
    if OPT.reservePct < 0 then OPT.reservePct = 0 end
    if OPT.reservePct > 50 then OPT.reservePct = 50 end
    OPT.battVoice   = (opts.BattVoice == 1 or opts.BattVoice == true)
    -- CountSrc keeps slot 10 so the first nine persisted options remain in
    -- place and the EdgeTX ten-option ceiling is respected.
    local countMode = tonumber(opts.CountSrc or opts["Flight Counter"])
    if countMode ~= FC.RADIO
       and countMode ~= FC.ROTORFLIGHT then
      countMode = FC.ROTORFLIGHT
    end
    OPT.flightCounter = bb == HELI_OMPHOBBY and FC.RADIO or countMode
    local parsedMin = parseVolt(opts.RxPackMin or "6.60", nil)
    local parsedMax = parseVolt(opts.RxPackMax or "8.40", nil)
    OPT.rxPackMin = parsedMin or 6.6
    OPT.rxPackMax = parsedMax or 8.4
    OPT.rxPackValid = parsedMin ~= nil and parsedMax ~= nil
                       and parsedMin >= SAFETY.rxPackMinAllowed
                       and parsedMax <= SAFETY.rxPackMaxAllowed
                       and (parsedMax - parsedMin) >= 0.1
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
