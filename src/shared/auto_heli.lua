function AUTO_HELI.apply(widget, name)
  local heliType = AUTO_HELI.infer(name)
  local changed = name ~= AUTO_HELI.name or heliType ~= OPT.heliType
                  or widget.autoHeliNeedsReset
  AUTO_HELI.ready, AUTO_HELI.name = true, name
  AUTO_HELI.provider = _G.rf2
  AUTO_HELI.queue = AUTO_HELI.provider and AUTO_HELI.provider.mspQueue
  AUTO_HELI.host = AUTO_HELI.provider and AUTO_HELI.provider.widget
  AUTO_HELI.model = widget.autoHeliModel
  AUTO_HELI.status = nil
  widget.autoHeliNeedsReset = false
  if not changed then return end
  batteryProfiles.reset(widget)
  OPT.heliType = heliType
  OPT.battBarMode = heliType == HELI_NITRO and 1 or 0
  resetSessionStats()
  resetSessionEvidence()
  batteryProfiles.flightSourceChanged(widget)
  timerThresholdArmed = nil
  D.rxVoltage, D.rxCellVoltage, D.rxPercent = nil, nil, 0
  A.lastDataTick = -1
  clearFrameCache()
  for key in pairs(RESOLVED) do RESOLVED[key] = nil end
  -- The same-type aircraft change is a new session too. Rebuild only when
  -- visible, retaining the shared host and the saved Auto setting.
  widget.layoutSignature = nil
end

function AUTO_HELI.sync(widget, name, waitingStatus)
  local now = frameNow()
  local wasReady = AUTO_HELI.ready
  if not name or name ~= widget.autoHeliCandidate then
    local status = name and "CONFIRMING FC NAME" or waitingStatus
    if wasReady or name ~= widget.autoHeliCandidate or status ~= AUTO_HELI.status then
      A.lastDataTick = -1
    end
    AUTO_HELI.ready = false
    AUTO_HELI.status = status
    widget.autoHeliCandidate = name
    widget.autoHeliCandidateTick = name and now or nil
    -- Invalidate eligibility and old operations immediately, before the
    -- confirmation delay and before telemetry/profile processing can run.
    if wasReady then batteryProfiles.reset(widget) end
    return
  end
  -- Stable names need no repeated inference or forced telemetry sampling.
  if wasReady and not widget.autoHeliNeedsReset then return end
  local since = widget.autoHeliCandidateTick or now
  if now < since then
    widget.autoHeliCandidateTick = now
    return
  end
  if now - since < AUTO_HELI.confirmTicks then return end
  AUTO_HELI.apply(widget, name)
  if not wasReady then A.lastDataTick = -1 end
end
