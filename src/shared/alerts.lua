function BATTERY_VOICE.play(path)
  if OPT.simTelemetry then return false end
  if not playFile or not path then return false end
  local available = BATTERY_VOICE.available[path]
  if available == nil then
    local f = io.open(path, "r")
    available = f ~= nil
    BATTERY_VOICE.available[path] = available
    if f then pcall(io.close, f) end
  end
  if not available then return false end
  return pcall(playFile, path)
end
local function playBatteryRemainingAlert(level)
  if OPT.simTelemetry then return false end
  local n = tonumber(level)
  if n == nil then return false end
  local customPath = BATTERY_VOICE.path .. tostring(math.floor(n)) .. "%.wav"
  if BATTERY_VOICE.play(customPath) then return true end
  if playNumber then
    return pcall(playNumber, n, SAFETY.batteryPercentUnit, 0)
  end
  return false
end
local function playBatteryHaptic()
  if OPT.simTelemetry then return end
  if not playHaptic then return end
  local modeNow = _G.PLAY_NOW or 0
  pcall(playHaptic, 15, 0, modeNow)
end
local function resetBatteryAlertState(scope)
  scope = scope or "all"
  if scope ~= "rx" then
    A.battAlertPrevPct       = nil
    A.battAlertPrevSource    = nil
    A.battVoicePlayed        = {}
    A.battZeroReached        = false
    A.deadVoiceNextTick      = 0
    A.flightDeadVoiceLatched = false
    A.flightDeadVoiceAcknowledged = false
    A.flightDeadVoiceStartPosition = nil
    A.battAlert5HapticPlayed = false
    A.battAlert0HapticPlayed = false
    A.battAlertNextTick      = 0
    A.battHapticState        = 0
    A.battHapticBurstCount   = 0
    A.battHapticNextTick     = 0
    A.battHapticEndTick      = 0
    A.battConnectionZeroPending = false
    A.battConnectionZeroSince = nil
    A.battReplacementSince  = nil
    A.liHvHighSamples        = 0
    D.isLiHV                 = false
  end
  if scope ~= "flight" then
    A.rxLowSinceTick         = nil
    A.rxLowHapticNext        = 0
    A.rxDeadVoiceLatched     = false
    A.rxDeadVoiceAcknowledged= false
    A.rxDeadVoiceStartPosition = nil
    A.rxDeadVoiceNextTick    = 0
  end
  if scope == "all" then
    A.escTempAlertPlayed = false
    A.becAlertPlayed = false
    A.escTempHighSince = nil
    A.becLowSince = nil
  end
end
function BATTERY_VOICE.prime(percent, leaveZeroPending)
  local played = A.battVoicePlayed
  for _, level in ipairs(BATTERY_VOICE.levels) do
    -- Do not announce thresholds already passed when the widget starts or is
    -- reloaded in the middle of a flight. Zero is the safety exception: a
    -- widget that starts on a confirmed empty pack must still alert.
    if percent <= level and not (leaveZeroPending and level == 0) then
      played[level] = true
    end
  end
end
local function updateBatteryAlertState(percent, hasData, voiceEnabled, percentSource)
  if not hasData or not A.linkAvailable then
    -- A telemetry gap means a startup zero was not continuously observed.
    if A.battConnectionZeroPending then
      A.battConnectionZeroSince = nil
    end
    return
  end
  local p = tonumber(percent)
  if p == nil then return end
  if p < 0 then p = 0 end
  if p > 100 then p = 100 end
  local now = frameNow()
  local connectionZeroWaiting = false
  local connectionZeroConfirmed = false
  if A.battConnectionZeroPending then
    if p <= 0 then
      if A.battConnectionZeroSince == nil then
        A.battConnectionZeroSince = now
      end
      if now - A.battConnectionZeroSince
         >= SAFETY.batteryConnectionZeroConfirm then
        A.battConnectionZeroPending = false
        A.battConnectionZeroSince = nil
        connectionZeroConfirmed = true
      else
        connectionZeroWaiting = true
      end
    else
      -- Any positive reading proves the connection-time zero was transient.
      A.battConnectionZeroPending = false
      A.battConnectionZeroSince = nil
    end
  end
  local prev = tonumber(A.battAlertPrevPct)
  if prev == nil then
    local startsAtZero = p <= 0
    A.battAlertPrevPct = startsAtZero and 0.01 or p
    A.battAlertPrevSource = percentSource
    BATTERY_VOICE.prime(p, startsAtZero)
    return
  end
  local previousSource = A.battAlertPrevSource
  local sourceChanged = previousSource ~= nil and percentSource ~= nil
                        and previousSource ~= percentSource
  local replacementJump = false
  if not sourceChanged then
    if percentSource == "fc" and previousSource == "fc" then
      -- Rotorflight Smart Fuel is monotonic within a battery session. A
      -- sustained upward step therefore rearms alerts for the new FC session
      -- without any voltage/capacity-based pack classifier.
      replacementJump = (p - prev) >= 1
    else
      -- Voltage-derived/receiver percentages can rebound under reduced load,
      -- so retain the deliberately conservative legacy qualification.
      replacementJump = (p >= 95 and prev < 80)
                        or ((p - prev) >= 25 and p >= 60)
    end
  end
  if replacementJump then
    if A.battReplacementSince == nil then A.battReplacementSince = now end
    if (now - A.battReplacementSince) >= BATTERY_VOICE.replacementConfirm then
      resetBatteryAlertState("flight")
      A.battAlertPrevPct = p
      A.battAlertPrevSource = percentSource
      BATTERY_VOICE.prime(p)
    end
    return
  end
  A.battReplacementSince = nil
  local playedLevels = A.battVoicePlayed
  if voiceEnabled then
    if now >= (tonumber(A.battAlertNextTick) or 0) then
      local selectedLevel
      for i = #BATTERY_VOICE.levels, 1, -1 do
        local level = BATTERY_VOICE.levels[i]
        if not playedLevels[level] and p <= level then
          selectedLevel = level
          break
        end
      end
      if selectedLevel ~= nil then
        -- If telemetry skipped several thresholds, announce the current
        -- lowest one and retire the higher backlog. At 0%, this prevents old
        -- percentage clips from delaying the safety-critical dead warning.
        for _, level in ipairs(BATTERY_VOICE.levels) do
          if p <= level then playedLevels[level] = true end
        end
        playBatteryRemainingAlert(selectedLevel)
        A.battAlertNextTick = now + SAFETY.batteryAlertCooldown
        if selectedLevel == 0 then
          A.battZeroReached = true
          A.deadVoiceNextTick = now + BATTERY_VOICE.initialDelay
        end
      end
    end
  else
    -- Keep threshold state current while muted so enabling Battery Voice later
    -- does not announce a backlog of percentages already passed.
    for _, level in ipairs(BATTERY_VOICE.levels) do
      if p <= level then playedLevels[level] = true end
    end
  end
  if connectionZeroConfirmed and not A.battAlert0HapticPlayed then
    A.battHapticState      = 2
    A.battHapticNextTick   = now
    A.battHapticEndTick    = now + 500
    A.battAlert0HapticPlayed = true
  elseif not connectionZeroWaiting then
    if (not A.battAlert5HapticPlayed)
       and prev > SAFETY.batteryHapticThreshold
       and p <= SAFETY.batteryHapticThreshold then
      A.battHapticState      = 1
      A.battHapticBurstCount = 0
      A.battHapticNextTick   = now
      A.battAlert5HapticPlayed = true
    end
    if (not A.battAlert0HapticPlayed) and prev > 0 and p <= 0 then
      A.battHapticState      = 2
      A.battHapticNextTick   = now
      A.battHapticEndTick    = now + 500
      A.battAlert0HapticPlayed = true
    end
  end
  A.battAlertPrevPct = p
  A.battAlertPrevSource = percentSource
end
function BATTERY_VOICE.updateDead(voiceEnabled)
  if not voiceEnabled or not A.battZeroReached then return end
  -- Once the pilot has heard dead.wav, a later movement of the configured
  -- physical Motor Switch acknowledges only this repeating voice. Movement
  -- before the first successful playback cannot pre-acknowledge the warning;
  -- percentage/haptic pausing remains telemetry-validated separately.
  if A.flightDeadVoiceLatched then
    local startPosition = A.flightDeadVoiceStartPosition
    local currentPosition = A.motorSwitchPosition
    if startPosition == nil and currentPosition ~= nil then
      A.flightDeadVoiceStartPosition = currentPosition
      startPosition = currentPosition
    end
    if startPosition ~= nil and currentPosition ~= nil
       and currentPosition ~= startPosition then
      A.flightDeadVoiceAcknowledged = true
      A.deadVoiceNextTick = 0
    end
  end
  if A.flightDeadVoiceAcknowledged then return end
  if not A.linkAvailable then return end
  local now = frameNow()
  if now < (tonumber(A.deadVoiceNextTick) or 0) then return end
  if BATTERY_VOICE.play(BATTERY_VOICE.deadPath)
     and not A.flightDeadVoiceLatched then
    A.flightDeadVoiceLatched = true
    A.flightDeadVoiceStartPosition = A.motorSwitchPosition
  end
  A.deadVoiceNextTick = now + BATTERY_VOICE.repeatDelay
end
local function updateBatteryHapticTick()
  if (A.battHapticState or 0) == 0 then return end
  if not A.linkAvailable then return end
  local now = frameNow()
  if now < (A.battHapticNextTick or 0) then return end
  if A.battHapticState == 1 then
    playBatteryHaptic()
    A.battHapticBurstCount = (A.battHapticBurstCount or 0) + 1
    if A.battHapticBurstCount >= 2 then
      A.battHapticState = 0
    else
      A.battHapticNextTick = now + 100
    end
  elseif A.battHapticState == 2 then
    if now >= (A.battHapticEndTick or 0) then
      A.battHapticState = 0
    else
      playBatteryHaptic()
      A.battHapticNextTick = now + 18
    end
  end
end
local function updateEscBecAlerts(escT, escValid, becV, becValid)
  if not A.linkAvailable then
    A.escTempHighSince = nil
    A.becLowSince = nil
    return
  end
  local now = frameNow()
  if escValid then
    if escT > SAFETY.escTempThreshold then
      if not A.escTempAlertPlayed then
        if A.escTempHighSince == nil then A.escTempHighSince = now end
        if (now - A.escTempHighSince) >= SAFETY.alertConfirmTicks then
          playBatteryHaptic()
          A.escTempAlertPlayed = true
          A.escTempHighSince = nil
        end
      end
    elseif A.escTempAlertPlayed and escT < SAFETY.escTempRearm then
      A.escTempAlertPlayed = false
      A.escTempHighSince = nil
    elseif not A.escTempAlertPlayed then
      A.escTempHighSince = nil
    end
  else
    A.escTempHighSince = nil
  end
  if becValid and becV >= SAFETY.becAlertMinVoltage then
    if becV < SAFETY.becVoltThreshold then
      if not A.becAlertPlayed then
        if A.becLowSince == nil then A.becLowSince = now end
        if (now - A.becLowSince) >= SAFETY.alertConfirmTicks then
          playBatteryHaptic()
          A.becAlertPlayed = true
          A.becLowSince = nil
        end
      end
    elseif A.becAlertPlayed and becV > SAFETY.becVoltRearm then
      A.becAlertPlayed = false
      A.becLowSince = nil
    elseif not A.becAlertPlayed then
      A.becLowSince = nil
    end
  else
    A.becLowSince = nil
  end
end
-- Nitro Rx pack low-voltage alert: if rx voltage sits at or below RxPackMin for
-- SAFETY.rxLowArmTicks (2s) continuously, buzz aggressively and latch the repeating
-- dead-battery voice warning. Caller only invokes this in Nitro mode.
function BATTERY_VOICE.updateRxDead(voiceEnabled, rx)
  if not rx or rx < SAFETY.becAlertMinVoltage then return end
  if not A.rxDeadVoiceLatched or A.rxDeadVoiceAcknowledged then return end
  if not A.linkAvailable then return end
  local startPosition = A.rxDeadVoiceStartPosition
  local currentPosition = A.motorSwitchPosition
  if startPosition == nil and currentPosition ~= nil then
    A.rxDeadVoiceStartPosition = currentPosition
    startPosition = currentPosition
  end
  if startPosition ~= nil and currentPosition ~= nil
     and currentPosition ~= startPosition then
    A.rxDeadVoiceAcknowledged = true
    A.rxDeadVoiceNextTick = 0
    return
  end
  if not voiceEnabled then return end
  local now = frameNow()
  if now < (tonumber(A.rxDeadVoiceNextTick) or 0) then return end
  BATTERY_VOICE.play(BATTERY_VOICE.deadPath)
  A.rxDeadVoiceNextTick = now + BATTERY_VOICE.repeatDelay
end
local function updateRxPackAlert(rx)
  if not OPT.rxPackValid then
    A.rxLowSinceTick = nil
    A.rxLowHapticNext = 0
    A.rxDeadVoiceLatched = false
    A.rxDeadVoiceAcknowledged = false
    A.rxDeadVoiceStartPosition = nil
    A.rxDeadVoiceNextTick = 0
    return
  end
  if not A.linkAvailable then
    if not A.rxDeadVoiceLatched then A.rxLowSinceTick = nil end
    A.rxLowHapticNext = 0
    return
  end
  local rxMin = OPT.rxPackMin
  local low = rx and rx >= SAFETY.becAlertMinVoltage
              and rxMin and rxMin > 0 and rx <= rxMin
  if not low then
    A.rxLowSinceTick = nil
    A.rxLowHapticNext = 0
    -- Once the Motor Switch has acknowledged a latched warning, recovery above
    -- the minimum rearms it for a future sustained low-voltage event. An
    -- unacknowledged warning remains latched until the switch is moved.
    if not A.rxDeadVoiceLatched or A.rxDeadVoiceAcknowledged then
      A.rxDeadVoiceLatched = false
      A.rxDeadVoiceAcknowledged = false
      A.rxDeadVoiceStartPosition = nil
      A.rxDeadVoiceNextTick = 0
    end
    return
  end
  local now = frameNow()
  -- Only movement after the warning has actually latched can acknowledge it.
  -- Movement during the two-second qualification period is normal control
  -- activity and must not silence an alert that has not started yet.
  if A.rxDeadVoiceLatched and A.rxDeadVoiceStartPosition ~= nil
     and A.motorSwitchPosition ~= nil
     and A.motorSwitchPosition ~= A.rxDeadVoiceStartPosition then
    A.rxDeadVoiceAcknowledged = true
    A.rxDeadVoiceNextTick = 0
  end
  if A.rxLowSinceTick == nil then
    A.rxLowSinceTick  = now
    A.rxLowHapticNext = now + SAFETY.rxLowArmTicks -- first buzz only after 2s sustained
    A.rxDeadVoiceStartPosition = nil
    A.rxDeadVoiceAcknowledged = false
  else
    if (now - A.rxLowSinceTick) >= SAFETY.rxLowArmTicks
       and not A.rxDeadVoiceLatched then
      A.rxDeadVoiceLatched = true
      A.rxDeadVoiceStartPosition = A.motorSwitchPosition
      A.rxDeadVoiceAcknowledged = false
      A.rxDeadVoiceNextTick = now
    end
    if not A.rxDeadVoiceAcknowledged
       and now >= (A.rxLowHapticNext or 0) then
      playBatteryHaptic()
      A.rxLowHapticNext = now + SAFETY.rxLowHapticInterval
    end
  end
end
local updateMotorAlertGate
local function tick(nowT)
  nowT = nowT or frameNow()
  A.lastDataTick = nowT
  local rq = sensors.getRqly()
  local linkReported = rq and rq > 0 or false
  A.linkAvailable = false
  -- Read the whole physical Motor Switch as a raw source (-1024/0/+1024 for a
  -- three-position switch). There is deliberately no channel fallback: an
  -- invalid mapping must remain visible and can never suppress/acknowledge an
  -- alert.
  local rawMotorPosition
  if OPT.simTelemetry then
    A.motorSourceReadable = false
    A.motorConfigError = nil
    A.motorSwitchPosition = nil
  else
    if A.motorSourcePhysical then
      rawMotorPosition = getValSrc(SRC.motorSwitch)
    end
    rawMotorPosition = tonumber(rawMotorPosition)
    A.motorSourceReadable = A.motorSourcePhysical and rawMotorPosition ~= nil
    if not A.motorSourcePhysical then
      A.motorConfigError = "SELECT A PHYSICAL MOTOR SWITCH"
    elseif not A.motorSourceReadable then
      A.motorConfigError = "MOTOR SWITCH UNAVAILABLE"
    else
      A.motorConfigError = nil
    end
    if rawMotorPosition == nil then
      A.motorSwitchPosition = nil
    elseif rawMotorPosition > 0 then
      A.motorSwitchPosition = 1
    elseif rawMotorPosition < 0 then
      A.motorSwitchPosition = -1
    else
      A.motorSwitchPosition = 0
    end
  end
  local volt  = sensors.getPackVolt()
  local cells = sensors.getCellCount()
  local pctSensor = sensors.getBatPct()
  local capa  = sensors.getCapa()
  sensors.getCurr()
  local escT  = sensors.getTemp()
  local becV  = sensors.getBec()
  local cellVoltage = sensors.getCellVoltage()
  local headRpm = sensors.getHeadspeed()
  local governorMode = sensors.getGovernorMode()
  local hasCellVoltage = D.cellVoltageValid and cellVoltage > 0
  local telemetryEvidence = hasCellVoltage or D.batteryPercentValid
                            or D.capacityValid or D.currentValid
                            or D.tempValid or D.becValid or D.rpmValid
                            or D.govValid
  -- A link source becomes authoritative after it has produced a live positive
  -- sample. Until then, current telemetry itself keeps safety alerts operating;
  -- this covers discovered-but-unpopulated link sensors without masking a real
  -- zero after the link source has proved itself.
  A.linkAvailable = linkReported
                    or (not A.linkSourceSeen and telemetryEvidence)
  if A.linkAvailable then
    if not A.battLinkWasAvailable then
      A.battConnectionZeroPending = true
      A.battConnectionZeroSince = nil
    end
    A.battLinkWasAvailable = true
  else
    A.battLinkWasAvailable = false
    A.battConnectionZeroPending = false
    A.battConnectionZeroSince = nil
  end
  D.voltage       = D.packVoltageValid and volt or 0
  D.cellsResolved = D.cellCountValid and cells or 0
  D.capacity      = capa or 0
  if hasCellVoltage and cellVoltage > SAFETY.liHvDetectCellV then
    A.liHvHighSamples = math.min(SAFETY.liHvConfirmSamples, A.liHvHighSamples + 1)
    if A.liHvHighSamples >= SAFETY.liHvConfirmSamples then D.isLiHV = true end
  elseif not D.isLiHV then
    A.liHvHighSamples = 0
  end
  if hasCellVoltage then
    if D.minCellVoltage == nil or cellVoltage < D.minCellVoltage then
      D.minCellVoltage = cellVoltage
    end
  end
  local voltagePct = hasCellVoltage
                     and sensors.percentFromCellVoltage(cellVoltage, D.isLiHV) or nil
  local hasPackVoltage = D.packVoltageValid and volt > 0
  local pct, hasPct, pctSource = sensors.selectFlightBatteryPercent(
    OPT.heliType, pctSensor, D.batteryPercentValid, voltagePct,
    hasCellVoltage, hasPackVoltage)
  local hadPct = D.hasBattData
  D.hasBattData = hasPct
  D.adjustedPercent = sensors.calculateAdjustedPercent(pct, OPT.reservePct)
  if not hasPct then
    A.displayPercent = 0
    A.displayPercentInit = false
  elseif pctSource == "fc" then
    -- Smart Fuel already performs its own sag compensation and rate limiting.
    -- Preserve the FC estimate exactly instead of applying a second filter.
    A.displayPercent = D.adjustedPercent
    A.displayPercentInit = true
  elseif not hadPct or not A.displayPercentInit then
    A.displayPercent     = D.adjustedPercent
    A.displayPercentInit = true
  else
    A.displayPercent = A.displayPercent
                       + (D.adjustedPercent - A.displayPercent)
                         * SAFETY.displayPercentAlpha
  end
  local modeReady = not OPT.autoHeliType or AUTO_HELI.ready
  if not OPT.simTelemetry and modeReady then
    -- A raw switch move is never enough to silence a warning. Rotorflight must
    -- corroborate it with Gov or Hspd; OMPHOBBY uses stopped RPM telemetry.
    updateMotorAlertGate(nowT, governorMode, headRpm)
    -- Percentage voice/haptic alerts belong to the main flight pack shown by
    -- Electric and OMPHOBBY modes. Nitro displays an Rx-pack voltage bar, so it
    -- must never run or retain this electric flight-pack alert state machine.
    local voiceEnabled = OPT.battVoice
    if OPT.battBarMode == 0 then
      if not A.flightBatteryAlertsPaused then
        updateBatteryAlertState(D.adjustedPercent, hasPct, voiceEnabled, pctSource)
        BATTERY_VOICE.updateDead(voiceEnabled)
        updateBatteryHapticTick()
      end
    elseif A.battAlertPrevPct ~= nil or A.battZeroReached
           or (A.battHapticState or 0) ~= 0 then
      resetBatteryAlertState("flight")
    end
    updateEscBecAlerts(escT, D.tempValid, becV, D.becValid)
  end
  if OPT.battBarMode == 1 then
    local rx = sensors.getRxBatt()
    if not OPT.simTelemetry and modeReady then
      updateRxPackAlert(rx)
      BATTERY_VOICE.updateRxDead(OPT.battVoice, rx)
    end
    if D.becValid and rx and rx > 0 then
      D.rxVoltage     = rx
      D.rxCellVoltage = rx / 2
      if rx > 0 then
        if D.minRxVoltage == nil or rx < D.minRxVoltage then
          D.minRxVoltage = rx
        end
      end
      local rxMin = OPT.rxPackMin
      local rxMax = OPT.rxPackMax
      if OPT.rxPackValid and rxMax > rxMin then
        local p = (rx - rxMin) / (rxMax - rxMin) * 100
        if p < 0 then p = 0 end
        if p > 100 then p = 100 end
        D.rxPercent = p
      else
        D.rxPercent = 0
      end
    else
      D.rxVoltage = nil; D.rxCellVoltage = nil; D.rxPercent = 0
    end
  end
end
