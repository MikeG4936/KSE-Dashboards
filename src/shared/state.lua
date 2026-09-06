local FLIGHTS_PATH              = "/flights-count.csv"
local TOPBAR_MIN_DUR_DEFAULT    = 20
local flightCache       = nil
local modelFlights      = 0
local minFlightDur      = TOPBAR_MIN_DUR_DEFAULT
local flightModel       = "__default__"
local timerThresholdArmed = nil
local S = {
  rpmMax = 0,
  currMax = 0, tempMax = 0,
  becMin = nil, cellMin = nil,
}
local D = {
  adjustedPercent = 0,
  hasBattData     = false,
  isLiHV          = false,
  capacity        = 0,
  minCellVoltage  = nil,
  voltage         = 0,
  cellsResolved   = 0,
  rxVoltage       = nil,
  rxCellVoltage   = nil,
  rxPercent       = 0,
  minRxVoltage    = nil,
  packVoltageValid= false,
  cellCountValid  = false,
  cellVoltageValid= false,
  batteryPercentValid = false,
  capacityValid   = false,
  currentValid    = false,
  tempValid       = false,
  becValid        = false,
  rpmValid        = false,
  tailRpmValid    = false,
  govValid        = false,
  govCurrentInvalid = false,
}
-- BAT# telemetry can trail a profile command for a few frames. Keep the
-- RF Tool selection visible briefly, then return authority to live telemetry.
local PROFILE_CONFIRMED = {
  value = nil,
  tick = nil,
}
local A = {
  displayPercent     = 0,
  displayPercentInit = false,
  battAlertPrevPct       = nil,
  battAlertPrevSource    = nil,
  battVoicePlayed        = {},
  battZeroReached        = false,
  deadVoiceNextTick      = 0,
  flightDeadVoiceLatched = false,
  flightDeadVoiceAcknowledged = false,
  flightDeadVoiceStartPosition = nil,
  motorSwitchPosition    = nil,
  motorSwitchLastPosition= nil,
  motorPausedPosition    = nil,
  motorGateCandidateFrom = nil,
  motorGateCandidateTo   = nil,
  motorGateCandidateTick = nil,
  govGateLastState       = nil,
  govGateRunningPosition = nil,
  govGateStopTick        = nil,
  govGateStopSince       = nil,
  electricRpmGateRunningPosition = nil,
  electricRpmGateZeroSince       = nil,
  ompGateRunningPosition = nil,
  ompGateZeroSince       = nil,
  flightBatteryAlertsPaused = false,
  batteryAlertPauseTick  = nil,
  motorPauseProof        = nil,
  battAlert5HapticPlayed = false,
  battAlert0HapticPlayed = false,
  battAlertNextTick      = 0,
  battHapticState        = 0,
  battHapticBurstCount   = 0,
  battHapticNextTick     = 0,
  battHapticEndTick      = 0,
  battLinkWasAvailable   = false,
  battConnectionZeroPending = false,
  battConnectionZeroSince = nil,
  escTempAlertPlayed = false,
  becAlertPlayed     = false,
  liHvHighSamples       = 0,
  motorSourcePhysical   = false,
  motorSourceReadable   = false,
  motorConfigError      = "SET MOTOR SWITCH",
  flightSaveError       = false,
  linkAvailable          = false,
  linkSourceKnown        = false,
  linkSourceSeen         = false,
  battReplacementSince  = nil,
  rxLowSinceTick         = nil,
  rxLowHapticNext        = 0,
  rxDeadVoiceLatched     = false,
  rxDeadVoiceAcknowledged= false,
  rxDeadVoiceStartPosition = nil,
  rxDeadVoiceNextTick    = 0,
  escTempHighSince       = nil,
  becLowSince            = nil,
  lastDataTick = -1,
}
local HELI_ELECTRIC, HELI_NITRO, HELI_OMPHOBBY = 1, 2, 3
-- Append Auto without changing the three persisted manual CHOICE values.
-- Keep name inference separate so another naming provider can be added later.
local AUTO_HELI = {
  option=4, confirmTicks=30, ready=false, name=nil,
  status="WAITING FOR FC NAME",
}
function AUTO_HELI.infer(name)
  name = type(name) == "string" and string.upper(name):gsub("%s+$", "") or ""
  if name:sub(-1) == "N" or name:sub(-5) == "NITRO" then
    return HELI_NITRO
  end
  return HELI_ELECTRIC
end
function AUTO_HELI.providerName(provider)
  local name = type(provider) == "table" and provider.modelName or nil
  if type(name) ~= "string" then return nil end
  name = string.match(name, "^%s*(.-)%s*$")
  return name ~= "" and name or nil
end
local OPT = {
  autoHeliType = false,
  heliType     = HELI_ELECTRIC,
  battBarMode   = 0,
  reservePct    = 0,
  battVoice     = false,
  simTelemetry  = false,
  flightCounter = 2, -- FC.ROTORFLIGHT; FC is declared immediately below.
  rxPackMin     = 6.6,
  rxPackMax     = 8.4,
  rxPackValid   = true,
  bgTransparent = false,
}
-- Callback entry points must also reject an identity published by an external
-- host since the last KSE refresh; display readiness alone can be stale.
function AUTO_HELI.current()
  if not OPT.autoHeliType then return true end
  local provider = _G.rf2
  local ok, info = pcall(model.getInfo)
  local modelIdentity = ok and type(info) == "table" and (info.filename or info.name) or nil
  return AUTO_HELI.ready and AUTO_HELI.model == modelIdentity
    and AUTO_HELI.name == AUTO_HELI.providerName(provider)
    and AUTO_HELI.provider == provider
    and AUTO_HELI.queue == provider.mspQueue
    and AUTO_HELI.host == provider.widget
end
-- Rotorflight flight-stat reads deliberately reuse RF Tool's one shared MSP
-- runtime. FC is kept in one table both to make its lifecycle explicit and to
-- stay below EdgeTX Lua's top-level local-variable limit.
local FC = {
  RADIO=1, ROTORFLIGHT=2,
  disarmStableTicks=150,
  confirmMaxReads=6,
  count=nil, status="RADIO", stale=false,
  wanted=false, pending=false, stableSince=nil,
  state=nil, armState=nil, model=nil, flightSeenArmed=false,
  refreshBase=nil, refreshAttempts=0,
}
G.profileConnectedForDisplay = false
local BATTERY_VOICE = {
  levels       = { 50, 40, 30, 20, 10, 0 },
  path         = G.assetRoot .. "/BatterySounds/",
  available    = {},
  initialDelay = 250,
  repeatDelay  = 220,
  replacementConfirm = 100, -- require a one-second rise before rearming for a new pack
}
BATTERY_VOICE.deadPath = BATTERY_VOICE.path .. "dead.wav"
-- Percentage clips are currently about 0.8-1.0s and dead.wav is ~1.18s.
-- These conservative delays keep files from continuously filling the EdgeTX
-- audio queue and leave clear silence between critical repetitions.
local SAFETY = {
  batteryAlertCooldown = 220, -- comfortably longer than the percentage clips
  batteryHapticThreshold = 10,
  batteryConnectionZeroConfirm = 300, -- 3s continuous 0% after link acquisition
  batteryPercentUnit = rawget(_G, "UNIT_PERCENT") or 13,
  rxLowArmTicks = 200,        -- low receiver pack must persist for 2.0s
  rxLowHapticInterval = 20,   -- then buzz every 0.2s while it stays low
  escTempThreshold = 110,
  escTempRearm = 100,
  becAlertMinVoltage = 4.0, -- ignore USB leakage when no receiver pack is powered
  becVoltThreshold = 4.8,
  becVoltRearm = 5.0,
  alertConfirmTicks = 50,     -- ESC/BEC conditions must persist for 0.5s
  displayPercentAlpha = 0.15,
  rxPackMinAllowed = 4.0,
  rxPackMaxAllowed = 9.0,
  maxCellCount = 16,
  maxCellSanityV = 4.5,
  cellRedThreshold = 3.50,
  liHvDetectCellV = 4.22,
  liHvConfirmSamples = 10, -- one continuous second at the 10 Hz service rate
  govMotorCorrelationTicks = 150, -- switch/Gov events may arrive 1.5s apart
  govMotorStopConfirmTicks = 20,  -- require 0.2s of recognized stopped state
  electricMotorStopWindowTicks = 3000, -- allow a 30s Hspd coast-down
  electricMotorZeroConfirmTicks = 30, -- require 0.3s of displayed-zero Hspd
  electricMotorRunningRpm = 1, -- raw Hspd below 1 RPM matches displayed zero
  ompMotorStopWindowTicks = 3000, -- allow a 30s autorotation/spindown
  ompMotorZeroConfirmTicks = 30,   -- require 0.3s of displayed-zero RPM telemetry
  ompMotorRunningRpm = 1, -- raw RPM below 1 matches the displayed zero state
}
-- Source metadata distinguishes a missing zero from a live value. This matters
-- most for Smart Fuel: Bat%=0 is meaningful only when a flight pack is actually
-- present, while positive current values can stand on their own.
local txIsLiIon = false
local F = {}
local RESOLVED = {}
