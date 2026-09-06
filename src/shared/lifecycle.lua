local function refreshOwned(widget, event, touchState)
  clearFrameCache()
  batteryProfiles.prepare(widget)
  ensureLayout(widget, event ~= nil)
  local count, status, connected = FC.count, FC.status, widget.profileConnectedForDisplay
  local serviced = serviceTelemetry(true)
  batteryProfiles.service(widget, true, event, touchState)
  if serviced or widget.kseUiDirty or count ~= FC.count or status ~= FC.status
     or connected ~= widget.profileConnectedForDisplay then updateUiState(widget) end
  widget.kseUiDirty = nil
end
local function backgroundOwned(widget)
  clearFrameCache()
  batteryProfiles.prepare(widget)
  serviceTelemetry(true)
  batteryProfiles.service(widget, false, nil, nil)
end
local function createOwned(zone, options)
  OPT.autoHeliType = false
  AUTO_HELI.ready, AUTO_HELI.name = false, nil
  -- Drop any stale frame cache (e.g. cached model name) before loading flights.
  clearFrameCache()
  applyOptions(options)
  if OPT.flightCounter ~= FC.ROTORFLIGHT then
    loadModelFlights()
  else
    flightModel = modelKey(getModelName())
    modelFlights = 0
    timerThresholdArmed = nil
    resetSessionStats()
    resetSessionEvidence()
  end
  local widget = {
    zone=zone, options=options or {},
    profileWasConnected=false, profileConnectedForDisplay=false,
    profileAutoShown=false, profileBusy=false,
  }
  G.prepareWidget(widget)
  batteryProfiles.flightSourceChanged(widget)
  return widget
end
local function updateOwned(widget, options)
  widget.options = options
  local previousHeliType = OPT.heliType
  local previousAutoHeliType = OPT.autoHeliType
  local previousSimulation = OPT.simTelemetry
  local previousFlightCounter = OPT.flightCounter
  local previousReserve = OPT.reservePct
  local previousRxMin = OPT.rxPackMin
  local previousRxMax = OPT.rxPackMax
  local previousRxValid = OPT.rxPackValid
  local previousMotorSource = SRC.motorSwitch
  applyOptions(options)
  if previousAutoHeliType ~= OPT.autoHeliType then
    widget.autoHeliCandidate, widget.autoHeliCandidateTick = nil, nil
    widget.autoHeliNeedsReset = true
    batteryProfiles.reset(widget)
    clearFrameCache()
  end
  local heliChanged = previousHeliType ~= OPT.heliType
  local simulationChanged = previousSimulation ~= OPT.simTelemetry
  local flightCounterChanged = previousFlightCounter ~= OPT.flightCounter
  local reserveChanged = previousReserve ~= OPT.reservePct
  local rxSettingsChanged = previousRxMin ~= OPT.rxPackMin
                            or previousRxMax ~= OPT.rxPackMax
                            or previousRxValid ~= OPT.rxPackValid
  local motorChanged = previousMotorSource ~= SRC.motorSwitch

  if heliChanged or simulationChanged then
    resetSessionStats()
    resetSessionEvidence()
  else
    if reserveChanged then
      -- Changing usable reserve changes percentage meaning, but a visual/theme
      -- edit must never erase live low-battery or Nitro warning state.
      if not OPT.simTelemetry then resetBatteryAlertState("flight") end
      A.displayPercent = 0
      A.displayPercentInit = false
    end
    if rxSettingsChanged and not OPT.simTelemetry then
      resetBatteryAlertState("rx")
    end
  end

  if motorChanged and not OPT.simTelemetry then
    resetMotorAlertGate(frameNow())
    if A.flightDeadVoiceLatched and not A.flightDeadVoiceAcknowledged then
      A.flightDeadVoiceStartPosition = nil
    end
    if A.rxDeadVoiceLatched and not A.rxDeadVoiceAcknowledged then
      A.rxDeadVoiceStartPosition = nil
    end
  end
  if simulationChanged then
    widget.lastSimTick = -1
    timerThresholdArmed = nil
  end
  if flightCounterChanged then
    if OPT.flightCounter ~= FC.ROTORFLIGHT then
      loadModelFlights()
    else
      flightModel = modelKey(getModelName())
      timerThresholdArmed = nil
    end
    batteryProfiles.flightSourceChanged(widget)
  end
  if heliChanged or simulationChanged then batteryProfiles.reset(widget) end
  if heliChanged or reserveChanged or simulationChanged then
    D.hasBattData = false
  end
  if heliChanged or rxSettingsChanged or simulationChanged then
    D.rxVoltage = nil
    D.rxCellVoltage = nil
    D.rxPercent = 0
  end
  A.lastDataTick = -1
  clearFrameCache()
  G.prepareWidget(widget)
  buildUi(widget)
end
function G.initializeOwner(widget)
  flightStore = WidgetOwner.sharedStore(flightStore)
  flightCache = flightStore.cache
  for key in pairs(widget) do
    if key ~= "zone" and key ~= "options" and key ~= "kseOwnerEpoch"
       and key ~= "profileOperationToken" and key ~= "armingStatusToken" then widget[key] = nil end
  end
  local created = createOwned(widget.zone, widget.options)
  for key, value in pairs(created) do widget[key] = value end
  widget.kseInitialized, widget.kseBlockedDrawn = true, nil
  widget.layoutSignature = nil
  widget.kseRevoke = function()
    batteryProfiles.retire(widget)
    widget.kseInitialized = false
  end
end
local function create(zone, options)
  local widget = {zone=zone, options=options or {}}
  if WidgetOwner.claim(widget, false) then G.initializeOwner(widget) end
  return widget
end
local function update(widget, options)
  if not widget then return end
  widget.options = options or {}
  if not WidgetOwner.claim(widget, false) then return end
  updateOwned(widget, options)
end
local function refresh(widget, event, touchState)
  if not widget then return end
  if not WidgetOwner.claim(widget, true) then WidgetOwner.blocked(widget); return end
  if not widget.kseInitialized then G.initializeOwner(widget) end
  refreshOwned(widget, event, touchState)
end
local function background(widget)
  if not widget or not WidgetOwner.claim(widget, false) then return end
  if widget.kseInitialized then backgroundOwned(widget) end
end
