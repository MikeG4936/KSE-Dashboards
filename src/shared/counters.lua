local function statRpmMax()  return S.rpmMax or 0 end
local function statCurrMax() return S.currMax or 0 end
local function statTempMax() return S.tempMax or 0 end
local function statBecMin()  return S.becMin end
local function statCellMin() return S.cellMin end
-- model.getTimer(0) shared per frame: the flight counter and top-bar clock both
-- need it, so read it once. Returns the timer table, or false on failure.
local function getTimer0()
  local t = F.timer0
  if t ~= nil then return t end
  local ok, tt = pcall(model.getTimer, 0)
  t = (ok and tt) or false
  F.timer0 = t
  return t
end
local function getTimer1Secs()
  local v = F.timerSecs
  if v ~= nil then return v end
  local t = getTimer0()
  v = (t and t.value) or 0
  F.timerSecs = v
  return v
end
local function getFlightCount()
  if OPT.flightCounter == FC.ROTORFLIGHT then return FC.count end
  return flightStore.cache and modelFlights or nil
end
local function getFlightCache()
  flightCache = flightStore.cache
  if OPT.flightCounter ~= FC.RADIO then return {} end
  if not flightCache then
    flightCache = Storage.load(flightStore) or {}
    A.flightSaveError = flightStore.error ~= nil
  end
  return flightCache
end
local function saveFlightCache()
  if OPT.flightCounter ~= FC.RADIO then return false end
  local ok = Storage.markDirty(flightStore, frameNow())
  A.flightSaveError = flightStore.error ~= nil
  return ok
end
local function modelKey(name)
  if type(name) ~= "string" or name == "" then return "__default__" end
  local s = trim(name)
  if s == "" then return "__default__" end
  return (string.gsub(s, ",", " "))
end
local function resetSessionStats()
  S.rpmMax  = 0
  S.currMax = 0
  S.tempMax = 0
  S.becMin  = nil
  S.cellMin = nil
end
local function resetSessionEvidence()
  for key in pairs(RESOLVED) do RESOLVED[key] = nil end
  A.linkAvailable = false
  A.linkSourceKnown = false
  A.linkSourceSeen = false
  A.battLinkWasAvailable = false
  A.battConnectionZeroPending = false
  A.battConnectionZeroSince = nil
  D.packVoltageValid = false
  D.cellCountValid = false
  D.cellVoltageValid = false
  D.batteryPercentValid = false
  D.capacityValid = false
  D.currentValid = false
  D.tempValid = false
  D.becValid = false
  D.rpmValid = false
  D.rpmFresh = false
  D.tailRpmValid = false
  D.govValid = false
    D.govFresh = false
  D.govCurrentInvalid = false
  D.hasBattData = false
  D.adjustedPercent = 0
  D.capacity = 0
  D.voltage = 0
  D.cellsResolved = 0
  D.isLiHV = false
  A.liHvHighSamples = 0
  A.displayPercent = 0
  A.displayPercentInit = false
  A.motorSwitchLastPosition = nil
  A.motorPausedPosition = nil
  A.motorGateCandidateFrom = nil
  A.motorGateCandidateTo = nil
  A.motorGateCandidateTick = nil
  A.govGateLastState = nil
  A.govGateRunningPosition = nil
  A.govGateStopTick = nil
  A.govGateStopSince = nil
  A.electricRpmGateRunningPosition = nil
  A.electricRpmGateZeroSince = nil
  A.ompGateRunningPosition = nil
  A.ompGateZeroSince = nil
  A.flightBatteryAlertsPaused = false
  A.batteryAlertPauseTick = nil
  A.motorPauseProof = nil
  D.minCellVoltage = nil
  D.minRxVoltage = nil
  resetBatteryAlertState()
end
local function loadModelFlights()
  if OPT.flightCounter == FC.ROTORFLIGHT then return end
  if flightStore.dirty then
    Storage.retry(flightStore, frameNow())
  else
    flightCache = Storage.load(flightStore) or {}
  end
  A.flightSaveError = flightStore.error ~= nil
  local key = modelKey(getModelName())
  flightModel = key
  modelFlights = getFlightCache()[key] or 0
  timerThresholdArmed = nil
  resetSessionStats()
  resetSessionEvidence()
end


local function timerElapsedSeconds(timer)
  if type(timer) ~= "table" then return nil end
  local value = tonumber(timer.value)
  if not value then return nil end
  local start = tonumber(timer.start) or 0
  local elapsed = start > 0 and (start - value) or value
  if elapsed < 0 then elapsed = 0 end
  return elapsed
end
local function shiftFlightBatteryAlertTimers(delta)
  if not delta or delta <= 0 then return end
  if (A.battAlertNextTick or 0) > 0 then
    A.battAlertNextTick = A.battAlertNextTick + delta
  end
  if (A.deadVoiceNextTick or 0) > 0 then
    A.deadVoiceNextTick = A.deadVoiceNextTick + delta
  end
  if (A.battHapticNextTick or 0) > 0 then
    A.battHapticNextTick = A.battHapticNextTick + delta
  end
  if (A.battHapticEndTick or 0) > 0 then
    A.battHapticEndTick = A.battHapticEndTick + delta
  end
  if A.battConnectionZeroSince ~= nil then
    A.battConnectionZeroSince = A.battConnectionZeroSince + delta
  end
  if A.battReplacementSince ~= nil then
    A.battReplacementSince = A.battReplacementSince + delta
  end
end
local function setFlightBatteryAlertsPaused(paused, now)
  paused = paused == true
  if paused == A.flightBatteryAlertsPaused then return end
  now = tonumber(now) or frameNow()
  if paused then
    A.flightBatteryAlertsPaused = true
    A.batteryAlertPauseTick = now
  else
    local started = tonumber(A.batteryAlertPauseTick)
    A.flightBatteryAlertsPaused = false
    A.batteryAlertPauseTick = nil
    if started and now > started then
      shiftFlightBatteryAlertTimers(now - started)
    end
  end
end
local function clearMotorGateCandidate()
  A.motorGateCandidateFrom = nil
  A.motorGateCandidateTo = nil
  A.motorGateCandidateTick = nil
  A.electricRpmGateZeroSince = nil
  A.ompGateZeroSince = nil
end
local function clearMotorGateEvidence()
  clearMotorGateCandidate()
  A.govGateLastState = nil
  A.govGateRunningPosition = nil
  A.govGateStopTick = nil
  A.govGateStopSince = nil
  A.electricRpmGateRunningPosition = nil
  A.ompGateRunningPosition = nil
end
local function releaseMotorAlertPause(now)
  setFlightBatteryAlertsPaused(false, now)
  A.motorPausedPosition = nil
  A.motorPauseProof = nil
  clearMotorGateEvidence()
end
local function resetMotorAlertGate(now)
  -- Losing or changing any gate input must fail loud: immediately restore
  -- flight-pack alerts and discard all prior movement/state correlation.
  releaseMotorAlertPause(now)
  A.motorSwitchLastPosition = nil
end
local function gateTickIsRecent(tick, now, limit)
  return tick ~= nil and now >= tick and (now - tick) <= limit
end
local function captureMotorSwitchCandidate(fromPosition, toPosition, now)
  A.motorGateCandidateFrom = fromPosition
  A.motorGateCandidateTo = toPosition
  A.motorGateCandidateTick = now
  A.electricRpmGateZeroSince = nil
  A.ompGateZeroSince = nil
end
local function pauseFlightBatteryAlerts(position, now, proof)
  clearMotorGateEvidence()
  A.motorPausedPosition = position
  A.motorPauseProof = proof
  setFlightBatteryAlertsPaused(true, now)
end
local function updateRotorflightMotorGate(now, position, switchChanged,
                                           governorMode, headRpm)
  local govUsable = D.govValid and D.govFresh and governorMode ~= nil
  local rpmUsable = D.rpmValid and D.rpmFresh and headRpm ~= nil
  if not govUsable and not rpmUsable then
    clearMotorGateEvidence()
    return
  end

  -- Gov correlation is intentionally short, but the independent Hspd proof
  -- needs enough time for an autorotation or normal rotor coast-down.
  if A.motorGateCandidateTick ~= nil
     and not gateTickIsRecent(A.motorGateCandidateTick, now,
                              SAFETY.electricMotorStopWindowTicks) then
    clearMotorGateCandidate()
  end

  if govUsable then
    local previousGov = A.govGateLastState
    if GOV_RUNNING_STATE[governorMode] then
      A.govGateStopTick = nil
      A.govGateStopSince = nil
      -- A switch move may reach Lua just before Gov leaves ACTIVE. Keep the
      -- last position proven by an unchanged running sample until correlation
      -- either succeeds or expires.
      if not switchChanged and A.motorGateCandidateTick == nil then
        A.govGateRunningPosition = position
      end
    elseif GOV_STOP_STATE[governorMode] then
      if previousGov ~= nil and GOV_RUNNING_STATE[previousGov] then
        A.govGateStopTick = now
        A.govGateStopSince = now
      end
    elseif governorMode ~= 1 or A.govGateStopTick == nil then
      -- IDLE may follow a sampled AUTOROT/THR-OFF/OFF transition before its
      -- confirmation time elapses. Retain that explicit stop evidence only;
      -- IDLE by itself still cannot initiate a pause.
      A.govGateStopTick = nil
      A.govGateStopSince = nil
    end

    local switchRecent = gateTickIsRecent(
      A.motorGateCandidateTick, now, SAFETY.govMotorCorrelationTicks)
    local govRecent = gateTickIsRecent(
      A.govGateStopTick, now, SAFETY.govMotorCorrelationTicks)
    local stopConfirmed = A.govGateStopSince ~= nil
                          and now >= A.govGateStopSince
                          and (now - A.govGateStopSince)
                              >= SAFETY.govMotorStopConfirmTicks
    if GOV_PAUSE_HOLD_STATE[governorMode] and switchRecent and govRecent
       and stopConfirmed
       and A.motorGateCandidateFrom == A.govGateRunningPosition
       and A.motorGateCandidateTo == position then
      pauseFlightBatteryAlerts(position, now, "gov")
      return
    end
    A.govGateLastState = governorMode
  else
    -- Do not let stale Gov transition state leak into the Hspd fallback.
    A.govGateLastState = nil
    A.govGateRunningPosition = nil
    A.govGateStopTick = nil
    A.govGateStopSince = nil
  end

  if not rpmUsable then
    A.electricRpmGateRunningPosition = nil
    A.electricRpmGateZeroSince = nil
    return
  end

  local rotorRunning = headRpm >= SAFETY.electricMotorRunningRpm
  if rotorRunning then
    A.electricRpmGateZeroSince = nil
    if A.motorGateCandidateTick == nil then
      A.electricRpmGateRunningPosition = position
    end
    return
  end

  -- A known running/unsafe or current-invalid Gov value overrides a zero Hspd;
  -- this prevents a lost RPM signal from being mistaken for motor-off. Missing
  -- or stale Gov is allowed because Hspd is an independent current proof.
  local govAllowsRpmStop = not D.govCurrentInvalid
                           and (not govUsable
                                or GOV_PAUSE_HOLD_STATE[governorMode])
  local candidateValid = govAllowsRpmStop
                         and gateTickIsRecent(
                           A.motorGateCandidateTick, now,
                           SAFETY.electricMotorStopWindowTicks)
                         and A.electricRpmGateRunningPosition ~= nil
                         and A.motorGateCandidateFrom
                             == A.electricRpmGateRunningPosition
                         and A.motorGateCandidateTo == position
  if not candidateValid then
    A.electricRpmGateZeroSince = nil
    return
  end
  if A.electricRpmGateZeroSince == nil then
    A.electricRpmGateZeroSince = now
  end
  if now >= A.electricRpmGateZeroSince
     and (now - A.electricRpmGateZeroSince)
         >= SAFETY.electricMotorZeroConfirmTicks then
    pauseFlightBatteryAlerts(position, now, "rpm")
  end
end
local function updateOmpMotorGate(now, position, headRpm)
  if not D.rpmValid or not D.rpmFresh or headRpm == nil then
    clearMotorGateEvidence()
    return
  end

  if A.motorGateCandidateTick ~= nil
     and not gateTickIsRecent(A.motorGateCandidateTick, now,
                              SAFETY.ompMotorStopWindowTicks) then
    clearMotorGateCandidate()
  end

  local rotorRunning = headRpm >= SAFETY.ompMotorRunningRpm
  if rotorRunning then
    A.ompGateZeroSince = nil
    if A.motorGateCandidateTick ~= nil
       and (A.motorGateCandidateFrom ~= A.ompGateRunningPosition
            or A.motorGateCandidateTo ~= position) then
      clearMotorGateCandidate()
    end
    -- Running RPM telemetry can persist during rotor coast-down. Do not relabel the new
    -- switch position as running while a valid stop candidate is pending.
    if A.motorGateCandidateTick == nil then
      A.ompGateRunningPosition = position
    end
    return
  end

  local candidateValid = A.motorGateCandidateTick ~= nil
                         and A.ompGateRunningPosition ~= nil
                         and A.motorGateCandidateFrom
                             == A.ompGateRunningPosition
                         and A.motorGateCandidateTo == position
  if not candidateValid then
    A.ompGateZeroSince = nil
    return
  end
  if A.ompGateZeroSince == nil then A.ompGateZeroSince = now end
  if now >= A.ompGateZeroSince
     and (now - A.ompGateZeroSince) >= SAFETY.ompMotorZeroConfirmTicks then
    pauseFlightBatteryAlerts(position, now, "omp")
  end
end
updateMotorAlertGate = function(now, governorMode, headRpm)
  local position = A.motorSwitchPosition
  local switchUsable = A.motorSourcePhysical and A.motorSourceReadable
                       and position ~= nil
  if not switchUsable or not A.linkAvailable then
    resetMotorAlertGate(now)
    return
  end

  local previousPosition = A.motorSwitchLastPosition
  local switchChanged = previousPosition ~= nil
                        and previousPosition ~= position
  A.motorSwitchLastPosition = position

  -- Nitro's receiver-pack warning retains its independent post-latch switch
  -- acknowledgement. This gate only controls Electric/OMP flight-pack alerts.
  if OPT.battBarMode ~= 0 then
    releaseMotorAlertPause(now)
    return
  end

  if A.flightBatteryAlertsPaused then
    if switchChanged or position ~= A.motorPausedPosition then
      releaseMotorAlertPause(now)
      return
    end
    if OPT.heliType == HELI_ELECTRIC then
      if A.motorPauseProof == "rpm" then
        local govBlocksRpmHold = D.govCurrentInvalid
                                 or (D.govValid and D.govFresh and governorMode ~= nil
                                     and not GOV_PAUSE_HOLD_STATE[governorMode])
        if govBlocksRpmHold or not D.rpmValid or not D.rpmFresh or headRpm == nil
           or headRpm >= SAFETY.electricMotorRunningRpm then
          releaseMotorAlertPause(now)
        end
      elseif not D.govValid or not D.govFresh or governorMode == nil
             or not GOV_PAUSE_HOLD_STATE[governorMode] then
        releaseMotorAlertPause(now)
      end
    elseif not D.rpmValid or not D.rpmFresh or headRpm == nil
           or headRpm >= SAFETY.ompMotorRunningRpm then
      releaseMotorAlertPause(now)
    end
    return
  end

  if switchChanged then
    local candidateFrom = previousPosition
    if OPT.heliType == HELI_ELECTRIC then
      candidateFrom = A.govGateRunningPosition
                      or A.electricRpmGateRunningPosition
                      or candidateFrom
    elseif OPT.heliType == HELI_OMPHOBBY
           and A.ompGateRunningPosition ~= nil then
      -- A three-position switch can cross its middle detent on a separate
      -- service tick. Keep the position proven by running telemetry as the
      -- origin so intermediate detents cannot erase a valid stop event.
      candidateFrom = A.ompGateRunningPosition
    end
    if candidateFrom ~= position then
      captureMotorSwitchCandidate(candidateFrom, position, now)
    else
      clearMotorGateCandidate()
    end
  end
  if OPT.heliType == HELI_ELECTRIC then
    updateRotorflightMotorGate(now, position, switchChanged, governorMode,
                               headRpm)
  elseif OPT.heliType == HELI_OMPHOBBY then
    updateOmpMotorGate(now, position, headRpm)
  else
    clearMotorGateEvidence()
  end
end
local function tickFlightCount()
  if OPT.simTelemetry or (OPT.autoHeliType and not AUTO_HELI.ready) then return end
  local thisModel = modelKey(getModelName())
  if flightModel ~= thisModel then
    flightModel = thisModel
    if OPT.flightCounter == FC.RADIO then
      modelFlights = getFlightCache()[thisModel] or 0
    else
      FC.count, FC.stale = nil, false
      FC.status, FC.wanted = "WAITING", true
      FC.stableSince, FC.model = nil, thisModel
    end
    timerThresholdArmed = nil
    resetSessionStats()
    resetSessionEvidence()
  end
  if OPT.flightCounter ~= FC.RADIO then return end
  local t = getTimer0()
  if not t then return end
  local secs = timerElapsedSeconds(t)
  if secs == nil then return end
  if timerThresholdArmed == nil then
    timerThresholdArmed = (secs < minFlightDur)
  end
  if secs < minFlightDur then
    timerThresholdArmed = true
  elseif timerThresholdArmed then
    timerThresholdArmed = false
    local cache = getFlightCache()
    local previous = cache[thisModel] or modelFlights or 0
    if flightStore.writable and previous < 2147483647 then
      cache[thisModel] = previous + 1
      modelFlights = cache[thisModel]
      saveFlightCache()
    else
      flightStore.error = flightStore.error or "COUNT UNAVAILABLE"
      A.flightSaveError = true
    end
  end
end
local function updateStats()
  if not A.linkAvailable then return end
  local r = sensors.getHeadspeed()
  if D.rpmValid and r > 0 then
    if r > S.rpmMax then S.rpmMax = r end
  end
  local c = sensors.getCurr()
  if D.currentValid and c > S.currMax then S.currMax = c end
  local t = sensors.getTemp()
  if D.tempValid and t > S.tempMax then S.tempMax = t end
  local b = sensors.getBec()
  if D.becValid and (S.becMin == nil or b < S.becMin) then S.becMin = b end
  local mc = sensors.getCellVoltage()
  if mc and mc > 0 and (S.cellMin == nil or mc < S.cellMin) then S.cellMin = mc end
end

local DATA_INTERVAL_TICKS = 10 -- 10 Hz; telemetry and UI do not need frame-rate polling
local function serviceTelemetry(trackStats)
  local now = frameNow()
  -- Finish an already-counted local event even after selecting the FC counter.
  if not OPT.simTelemetry and flightStore.dirty then
    Storage.service(flightStore, now)
    A.flightSaveError = flightStore.error ~= nil
  end
  local last = A.lastDataTick
  if last and last >= 0 and now >= last and (now - last) < DATA_INTERVAL_TICKS then
    return false
  end
  if not OPT.simTelemetry then tickFlightCount() end
  tick(now)
  if trackStats then updateStats() end
  return true
end
