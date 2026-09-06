local batteryProfiles = (function()
local EVT_TOUCH_TAP = rawget(_G, "EVT_TOUCH_TAP") or _G.EVT_TOUCH_TAP
local MSP_BATTERY_CONFIG = 32
local MSP_BATTERY_STATE = 130
local MSP_BATTERY_PROFILE = 175
local MSP_SET_BATTERY_PROFILE = 176
local MSP_EEPROM_WRITE = 250
local ROTORFLIGHT_23_MSP_API = 12.09
local RF_TOOL_WIDGET_API = 1.00
local BATTERY_CAPACITY_MAX = 20000
local PROFILE_SELECTION_NOTICE = 100
local PROFILE_CONNECT_SETTLE = 40
local PROFILE_HOST_DISCOVERY = 20
local PROFILE_READ_TIMEOUT = 800
local PROFILE_SELECT_TIMEOUT = 2000
local PROFILE_ACTIVE_CAPACITY_TIMEOUT = 300
local PROFILE_SNAPSHOT_ACTIVE_TIMEOUT = 500
local PROFILE_SNAPSHOT_CAPACITY_TIMEOUT = 1200
local PROFILE_FLIGHT_STATS_TIMEOUT = 200

-- @module msp_admission MspAdmission

local function profileNow()
  return (getTime and getTime()) or 0
end

local function profileRf2()
  local value = rawget(_G, "rf2") or _G.rf2
  return type(value) == "table" and value or nil
end

local function profileRfToolInstanceLive()
  local shared = profileRf2()
  if not shared then return nil end
  local seenAt = tonumber(shared.rfToolInstanceSeenAt)
  local clock = shared.clock
  if not seenAt or type(clock) ~= "function" then return nil end
  local ok, current = pcall(clock)
  current = ok and tonumber(current) or nil
  if not current or current - seenAt > 2 then return nil end
  return shared
end

local function profileRadioLinkLive()
  local reader = rawget(_G, "getRSSI") or _G.getRSSI
  if type(reader) ~= "function" then return false end
  local ok, value = pcall(reader)
  return ok and tonumber(value) ~= nil and tonumber(value) > 0
end

local function profileStandaloneRf2bgCore(shared)
  shared = shared or profileRf2()
  if type(shared) ~= "table" then return false end
  local api = tonumber(shared.apiVersion)
  return api and api >= ROTORFLIGHT_23_MSP_API
         and type(shared.useApi) == "function"
         and type(shared.mspQueue) == "table"
         and type(shared.mspQueue.add) == "function"
         and shared.rfToolApiVersion == nil
         and shared.registerWidget == nil
         and shared.widget == nil
         and shared.rfToolInstanceSeenAt == nil
end

local function profileRfToolProvider()
  local shared = profileRf2()
  if not shared then return nil end
  local toolApi = tonumber(shared.rfToolApiVersion)
  local hasConsumerApi = toolApi and toolApi >= RF_TOOL_WIDGET_API
                         and type(shared.registerWidget) == "function"
  local mspApi = tonumber(shared.apiVersion)
  local hasQueue = type(shared.mspQueue) == "table"
                   and type(shared.mspQueue.add) == "function"
  local hasRfToolCore = hasQueue
                        and (type(shared.widget) == "table"
                             or (mspApi and mspApi >= ROTORFLIGHT_23_MSP_API
                                 and profileRfToolInstanceLive() == shared))
  if not hasConsumerApi and not hasRfToolCore then return nil end
  return shared
end

local function profileSharedQueue()
  local shared = profileRfToolProvider()
  local mspApi = shared and tonumber(shared.apiVersion) or nil
  if not shared or not mspApi or mspApi < ROTORFLIGHT_23_MSP_API
     or type(shared.mspQueue) ~= "table"
     or type(shared.mspQueue.add) ~= "function" then return nil end
  return shared.mspQueue
end

local function profileRfApi(name)
  local shared = profileRfToolProvider()
  if not shared or type(shared.useApi) ~= "function" then return nil end
  local ok, api = pcall(shared.useApi, name)
  return ok and type(api) == "table" and api or nil
end

local function profileTransport()
  return profileSharedQueue() and "shared" or nil
end

local function profileStartEmbeddedRfTool(wgt)
  -- FC count can create the hidden host before profile discovery finishes.
  -- That host is the shared runtime; retain and service it instead of loading
  -- a second instance or leaving the first one stranded in STARTING.
  if profileRfToolInstanceLive() or profileRfToolProvider()
     or wgt.profileRfToolHost then return end
  if profileStandaloneRf2bgCore() then
    wgt.profileRfToolHostError = "DISABLE rf2bg SPECIAL FUNCTION"
    return
  end
  local now = profileNow()
  if not wgt.profileRfToolDiscoveryAt then
    wgt.profileRfToolDiscoveryAt = now + PROFILE_HOST_DISCOVERY
    return
  end
  if now < wgt.profileRfToolDiscoveryAt then return end
  if wgt.profileRfToolHostNextTick
     and now < wgt.profileRfToolHostNextTick then return end

  local loader = rawget(_G, "loadScript") or _G.loadScript
  if type(loader) ~= "function" then
    wgt.profileRfToolHostError = "INSTALL RF TOOL 2.3"
    wgt.profileRfToolHostNextTick = now + 500
    return
  end
  local ok, factory = pcall(loader, "/WIDGETS/RfTool/app.lua")
  if not ok or type(factory) ~= "function" then
    wgt.profileRfToolHostError = "INSTALL RF TOOL 2.3"
    wgt.profileRfToolHostNextTick = now + 500
    return
  end
  local hostOk, host = pcall(factory, { x=0, y=0, w=1, h=1 }, {
    Source=0, Color=C_TEXT, ["Hide Model"]=1,
    ["Hide State"]=1, ["Hide Telemetry"]=1,
    sourceName="", sourceUnit="",
  })
  if not hostOk or type(host) ~= "table"
     or type(host.background) ~= "function" then
    wgt.profileRfToolHostError = "RF TOOL HOST FAILED"
    wgt.profileRfToolHostNextTick = now + 500
    return
  end
  WidgetOwner.host(host, profileRf2())
  wgt.profileRfToolHost = host
  wgt.profileRfToolHostCore = profileRf2()
  wgt.profileRfToolHostError = nil
  wgt.profileRfToolHostNextTick = nil
end

local function profileServiceEmbeddedRfTool(wgt)
  local host, core = WidgetOwner.host()
  if host then wgt.profileRfToolHost, wgt.profileRfToolHostCore = host, core end
  if wgt.profileRfToolHostCore ~= profileRf2()
     or (wgt.profileRfToolHostCore and wgt.profileRfToolHostCore.widget
         and wgt.profileRfToolHostCore.widget ~= wgt.profileRfToolHost) then
    wgt.profileRfToolHost, wgt.profileRfToolHostCore = nil, nil
  end
  profileStartEmbeddedRfTool(wgt)
  host, core = wgt.profileRfToolHost, wgt.profileRfToolHostCore
  -- External widgets run under their own EdgeTX manager, never through KSE.
  if not host or core ~= profileRf2() then return end
  local state = host.state
  local queue = core and core.mspQueue
  if (state == "connected" or state == "armed" or state == "disarmed")
     and type(queue) == "table" and type(queue.processQueue) == "function" then
    local ok = pcall(queue.processQueue, queue)
    wgt.profileQueueFault = not ok or nil
    if not ok then wgt.profileRfToolHostError = "RF TOOL QUEUE ERROR" end
  end
  -- Match official foreground ordering, including background during waits.
  -- true keeps RF Tool's private UI runner out of the KSE display.
  local ok = pcall(host.background, host, true)
  if not ok then wgt.profileRfToolHostError = "RF TOOL HOST ERROR"
  elseif not wgt.profileQueueFault then wgt.profileRfToolHostError = nil end
end

local function profileRfToolStatus(wgt)
  if wgt.profileRfToolHostError then return wgt.profileRfToolHostError end
  local shared = profileRfToolProvider()
  if not shared then return "STARTING RF TOOL 2.3" end
  local state = wgt.profileRfState
  if state == "compiling" or state == "loading"
     or state == "unknown protocol" or state == "ready"
     or state == "initializing" then
    return "RF TOOL: " .. string.upper(state)
  end
  local mspApi = tonumber(shared.apiVersion)
  if mspApi and mspApi < ROTORFLIGHT_23_MSP_API then
    return "ROTORFLIGHT 2.3 FC REQUIRED"
  end
  if not profileSharedQueue() then return "WAITING FOR RF TOOL API" end
  if state == "disconnected" then return "RF TOOL: DISCONNECTED" end
  return "WAITING FOR RF TOOL CONNECTION"
end

local function profileSetMessage(wgt, text, color)
  wgt.kseUiDirty = true
  wgt.profileMessage = text
  wgt.profileMessageColor = color or C_DIM
end

local function profileSetNotice(wgt, title, detail, color, duration, compact)
  wgt.profileNoticeTitle = title
  wgt.profileNoticeDetail = detail
  wgt.profileNoticeColor = color or C_DIM
  wgt.profileNoticeCompact = compact == true
  wgt.profileNoticeUntil = profileNow() + (duration or 300)
end

local function profileRefreshSelectionNotice(wgt, title, detail, color)
  local now = profileNow()
  if not wgt.profileNoticeCompact or not wgt.profileNoticeUntil
     or now >= wgt.profileNoticeUntil then return end
  wgt.profileNoticeTitle = title
  wgt.profileNoticeDetail = detail
  wgt.profileNoticeColor = color or C_DIM
end

-- @include variant:rf_prompt.lua
local function profileCancelOperationQueue(operation)
  return MspAdmission.cancelPending(operation)
end

local function profileOperationFailed(wgt, text, token)
  local operation = wgt.profileOperation
  if token and (not operation or operation.token ~= token) then return end
  local kind = operation and operation.kind or nil
  wgt.profileOperation = nil
  wgt.profileBusy = false
  wgt.profilePending = nil
  if kind == "snapshot" then
    wgt.profileInitialReadFinished = true
    wgt.profileCapacityReadFinished = true
    if wgt.profileInitialReadValid and wgt.profileActive then
      profileSetMessage(wgt, "MSP 32 mAh NOT RECEIVED", C_YELLOW)
    else
      profileSetMessage(wgt, text or "PROFILE DATA UNAVAILABLE", C_DIM)
    end
    return
  end
  if kind == "activeCapacity" then
    profileSetMessage(wgt,
      "PROFILE " .. tostring(operation and operation.target or "")
        .. " SELECTED", C_DIM)
    return
  end
  profileSetMessage(wgt, text or "PROFILE COMMAND FAILED", C_RED)
  profileSetNotice(wgt, "BATTERY PROFILE ERROR",
                   text or "PROFILE COMMAND FAILED", C_RED, 500)
end

local function profileSelectionVerified(wgt, zeroBased, token)
  local operation = wgt.profileOperation
  if not operation or operation.token ~= token
     or operation.kind ~= "select" then return end
  if not MspAdmission.valid(wgt, operation) then return end

  local index = tonumber(zeroBased)
  if not index or index > math.floor(index)
     or not (index >= 0 and index < BATTERY_PROFILE_COUNT) then
    profileCancelOperationQueue(operation)
    profileOperationFailed(wgt, "INVALID PROFILE REPLY", token)
    return
  end

  local displayProfile = index + 1
  wgt.profileActive = displayProfile
  F.battProfile = displayProfile
  if displayProfile ~= operation.target then
    profileCancelOperationQueue(operation)
    profileOperationFailed(wgt,
      "FC REMAINS ON PROFILE " .. tostring(displayProfile), token)
    return
  end

  operation.verified = true
  operation.stage = "save"
  operation.stageStartedAt = profileNow()
  profileSetMessage(wgt,
    "SAVING PROFILE " .. tostring(displayProfile) .. " TO FC...", C_YELLOW)
end

local function profileSelectionSaved(wgt, displayProfile, token)
  local operation = wgt.profileOperation
  if not operation or operation.token ~= token
     or operation.kind ~= "select" or not operation.verified
     or operation.target ~= displayProfile then return end
  if not MspAdmission.valid(wgt, operation) then return end
  wgt.profileOperation = nil
  wgt.profileBusy = false
  wgt.profilePending = nil
  wgt.profileActive = displayProfile
  PROFILE_CONFIRMED.value = displayProfile
  PROFILE_CONFIRMED.tick = profileNow()
  F.battProfile = displayProfile
  -- MSP 130 is a compact capacity read queued only after the verified EEPROM
  -- commit has drained from RF Tool's shared queue.
  wgt.profileActiveCapacityRequested = displayProfile
  profileSetMessage(wgt,
    "PROFILE " .. tostring(displayProfile) .. " SAVED TO FC", C_GREEN)
  local capacity = wgt.profileCapacities
                   and wgt.profileCapacities[displayProfile] or nil
  local capacityText = capacity == nil and "PERSISTS AFTER FC REBOOT"
                       or (capacity > 0 and (tostring(capacity) .. " mAh")
                           or "CAPACITY NOT SET")
  profileSetNotice(wgt,
    "PROFILE " .. tostring(displayProfile) .. " SAVED",
    capacityText, C_GREEN, PROFILE_SELECTION_NOTICE, true)
end

local function profileReadByte(buf, index)
  local value = type(buf) == "table" and tonumber(buf[index]) or nil
  if not value or not (value >= 0 and value <= 255) or value > math.floor(value) then
    return nil
  end
  return value
end

local function profileReadU16(buf, index)
  local low = profileReadByte(buf, index)
  local high = profileReadByte(buf, index + 1)
  if low == nil or high == nil then return nil end
  return low + high * 256
end

local function profileActiveCapacityReceived(wgt, buf, token)
  local operation = wgt.profileOperation
  if not operation or operation.token ~= token
     or operation.kind ~= "activeCapacity" then return end
  if not MspAdmission.valid(wgt, operation) then return end
  local capacity = profileReadU16(buf, 3)
  local replyProfile = profileReadByte(buf, 12)
  local displayProfile = replyProfile and (replyProfile + 1)
                         or tonumber(operation.target)
  if not capacity or capacity > BATTERY_CAPACITY_MAX
     or not displayProfile or displayProfile < 1
     or displayProfile > BATTERY_PROFILE_COUNT then
    profileOperationFailed(wgt, "ACTIVE CAPACITY NOT RECEIVED", token)
    return
  end
  wgt.profileOperation = nil
  wgt.profileBusy = false
  wgt.profilePending = nil
  wgt.profileActive = displayProfile
  wgt.profileCapacities = wgt.profileCapacities or {}
  wgt.profileCapacities[displayProfile] = capacity
  wgt.profileCapacitiesReady = true
  wgt.profileCapacitiesComplete = false
  local capacityText = capacity > 0 and (tostring(capacity) .. " mAh")
                       or "CAPACITY NOT SET"
  profileSetMessage(wgt,
    "PROFILE " .. tostring(displayProfile) .. ": " .. capacityText, C_GREEN)
  profileRefreshSelectionNotice(wgt,
    "PROFILE " .. tostring(displayProfile) .. " SELECTED",
    capacityText, C_GREEN)
end

local function profileDecodeCapacityConfig(wgt, config)
  local source = type(config) == "table" and config.batteryCapacity or nil
  local capacities = {}
  local allProfiles = type(source) == "table"
  for i = 1, BATTERY_PROFILE_COUNT do
    local entry = allProfiles and source[i - 1] or nil
    local capacity = type(entry) == "table" and tonumber(entry.value)
                     or tonumber(entry)
    if not capacity or capacity > math.floor(capacity)
       or capacity < 0 or capacity > BATTERY_CAPACITY_MAX then
      allProfiles = false
      break
    end
    capacities[i] = capacity
  end
  if not allProfiles then
    capacities = {}
    local activeCapacity = type(source) == "table"
                           and tonumber(source.value) or nil
    local activeProfile = tonumber(wgt.profileActive)
    if activeCapacity == nil or activeCapacity > math.floor(activeCapacity)
       or activeCapacity < 0 or activeCapacity > BATTERY_CAPACITY_MAX then
      return nil, false
    end
    if activeProfile and activeProfile >= 1
       and activeProfile <= BATTERY_PROFILE_COUNT then
      capacities[activeProfile] = activeCapacity
    end
  end
  return capacities, allProfiles
end

local function profileDecodeCapacityRaw(wgt, buf)
  local capacities = {}
  local allProfiles = true
  for i = 1, BATTERY_PROFILE_COUNT do
    local capacity = profileReadU16(buf, 16 + (i - 1) * 2)
    if capacity == nil or capacity > BATTERY_CAPACITY_MAX then
      allProfiles = false
      break
    end
    capacities[i] = capacity
  end
  if not allProfiles then
    capacities = {}
    local activeCapacity = profileReadU16(buf, 1)
    local activeProfile = tonumber(wgt.profileActive)
    if activeCapacity == nil or activeCapacity > BATTERY_CAPACITY_MAX then
      return nil, false
    end
    if activeProfile and activeProfile >= 1
       and activeProfile <= BATTERY_PROFILE_COUNT then
      capacities[activeProfile] = activeCapacity
    end
  end
  return capacities, allProfiles
end

local function profileQueueIdle(queue)
  if type(queue.isProcessed) ~= "function" then return true end
  local ok, idle = pcall(queue.isProcessed, queue)
  return ok and idle == true
end

local function profileQueueMessageSet(queue)
  local messages = {}
  if type(queue) ~= "table" then return messages end
  if queue.currentMessage then messages[queue.currentMessage] = true end
  for _, message in pairs(queue.messageQueue or {}) do
    if message then messages[message] = true end
  end
  return messages
end

local function profileCallApiAndCollect(queue, operation, callback)
  local before = profileQueueMessageSet(queue)
  local ok = pcall(callback)
  local added = 0
  local after = profileQueueMessageSet(queue)
  for message in pairs(after) do
    if not before[message] then
      operation.messages[#operation.messages + 1] = message
      added = added + 1
    end
  end
  return ok, added > 0 or type(queue.messageQueue) ~= "table"
end

local function profileInstallErrorHandler(messages, failed)
  for _, message in ipairs(messages or {}) do
    if type(message) == "table" then message.errorHandler = failed end
  end
end

-- RotorFlight arming blockers ----------------------------------------------
-- MSP 101 is read-only. ARM_SWITCH is the normal reason while the arm switch
-- is off, so the banner reports only the actionable blockers beside it.
local ARMING_DISABLE_NAMES = {
  [0]="NO GYRO", [1]="FAILSAFE", [2]="RX FAILSAFE",
  [3]="RX RECOVERY", [4]="FAILSAFE MODE", [5]="GOVERNOR",
  [6]="RPM SIGNAL", [7]="THROTTLE", [8]="ANGLE",
  [9]="BOOT GRACE", [10]="PREARM", [11]="CPU LOAD",
  [12]="CALIBRATING", [13]="CLI", [14]="CMS MENU", [15]="BST",
  [16]="MSP", [17]="PARALYZE", [18]="GPS", [19]="RESCUE",
  [20]="RPM FILTER", [21]="REBOOT REQUIRED", [22]="DSHOT",
  [23]="ACC CAL", [24]="MOTOR PROTOCOL",
}
local ARMING_STATUS_INTERVAL = 100
local ARMING_STATUS_TIMEOUT = 200
local ARMING_STATUS_STALE = 500
local ARMING_DISABLED_CALIBRATING = 4096
local ARMING_DISABLED_ARM_SWITCH = 67108864

local function armingBannerText(flags)
  local value = tonumber(flags)
  if not value then return nil end
  -- gyro_cal_on_first_arm reports CALIBRATING without ARM_SWITCH while idle.
  -- A real block during an arm attempt carries both flags.
  if bit32.band(value, ARMING_DISABLED_CALIBRATING) ~= 0
     and bit32.band(value, ARMING_DISABLED_ARM_SWITCH) == 0 then
    value = value - ARMING_DISABLED_CALIBRATING
  end
  local reasons = {}
  for index = 0, 24 do
    if bit32.band(value, bit32.lshift(1, index)) ~= 0 then
      reasons[#reasons + 1] = ARMING_DISABLE_NAMES[index]
    end
  end
  if #reasons == 0 then return nil end
  local shown = math.min(2, #reasons)
  local text = reasons[1]
  if shown == 2 then text = text .. ", " .. reasons[2] end
  if #reasons > shown then
    text = text .. " +" .. tostring(#reasons - shown)
  end
  return "ARMING BLOCKED: " .. text
end

-- @include variant:rf_banner.lua
local function profileFailArmingStatus(wgt, token)
  local operation = wgt and wgt.armingStatusOperation or nil
  if not operation or operation.token ~= token then return end
  profileCancelOperationQueue(operation)
  wgt.armingStatusOperation = nil
  wgt.armingStatusPending = false
  wgt.armingStatusNextAt = profileNow() + ARMING_STATUS_INTERVAL * 2
end

local function profileFinishArmingStatus(wgt, status, token)
  local operation = wgt and wgt.armingStatusOperation or nil
  if not operation or operation.token ~= token then return end
  if not MspAdmission.valid(wgt, operation) then return end
  wgt.armingStatusOperation = nil
  wgt.armingStatusPending = false
  if OPT.heliType == HELI_OMPHOBBY then
    wgt.armingStatusNextAt = nil
    wgt.armingDisableFlags = nil
    wgt.armingBlockerText = nil
    wgt.armingStatusUpdatedAt = nil
    return
  end
  wgt.armingStatusNextAt = profileNow() + ARMING_STATUS_INTERVAL
  wgt.armingDisableFlags = type(status) == "table"
                           and tonumber(status.armingDisableFlags) or nil
  wgt.armingBlockerText = armingBannerText(wgt.armingDisableFlags)
  wgt.armingStatusUpdatedAt = profileNow()
end

local function profileBeginArmingStatus(wgt)
  if not MspAdmission.disarmed(wgt) then return false end
  if OPT.heliType == HELI_OMPHOBBY then return false end
  if wgt.armingStatusPending or wgt.profileBusy then return false end
  local queue = profileSharedQueue()
  if not queue or not profileQueueIdle(queue) then return false end
  local api = profileRfApi("mspStatus")
  if not api or type(api.getStatus) ~= "function" then return false end

  wgt.armingStatusToken = (wgt.armingStatusToken or 0) + 1
  local token = wgt.armingStatusToken
  local operation = {
    token=token, kind="armingStatus", startedAt=profileNow(),
    queue=queue, messages={},
  }
  MspAdmission.capture(wgt, operation)
  wgt.armingStatusOperation = operation
  wgt.armingStatusPending = true
  local ok, added = profileCallApiAndCollect(queue, operation, function()
    api.getStatus(function(_, status)
      profileFinishArmingStatus(wgt, status, token)
    end, wgt)
  end)
  local decorated = false
  if ok and added then
    for _, message in ipairs(operation.messages) do
      if type(message) == "table" and message.command == 101 then
        decorated = true
        message.errorHandler = function()
          profileFailArmingStatus(wgt, token)
        end
      end
    end
  end
  if not ok or not added or not decorated then
    profileFailArmingStatus(wgt, token)
    return false
  end
  return true
end

local function profileServiceArmingStatus(wgt, connected, now, allowUi)
  if OPT.heliType == HELI_OMPHOBBY or not connected
     or not MspAdmission.disarmed(wgt) then
    if wgt.armingStatusOperation then
      profileCancelOperationQueue(wgt.armingStatusOperation)
    end
    wgt.armingStatusOperation = nil
    wgt.armingStatusPending = false
    wgt.armingStatusNextAt = nil
    wgt.armingDisableFlags = nil
    wgt.armingBlockerText = nil
    wgt.armingStatusUpdatedAt = nil
    if allowUi then profileShowArmingBanner(wgt) end
    return
  end
  local operation = wgt.armingStatusOperation
  if operation and now - operation.startedAt >= ARMING_STATUS_TIMEOUT then
    profileFailArmingStatus(wgt, operation.token)
  end
  if wgt.armingStatusUpdatedAt
     and now - wgt.armingStatusUpdatedAt >= ARMING_STATUS_STALE then
    wgt.armingStatusUpdatedAt = nil
    wgt.armingDisableFlags = nil
    wgt.armingBlockerText = nil
  end
  if allowUi then profileShowArmingBanner(wgt) end
  local flightStatsDue = OPT.flightCounter == FC.ROTORFLIGHT
                         and FC.wanted and not FC.pending
                         and FC.stableSince ~= nil
                         and now - FC.stableSince >= FC.disarmStableTicks
  if not wgt.armingStatusPending
     and now >= (wgt.armingStatusNextAt or now)
     and not wgt.profileBusy and not flightStatsDue then
    profileBeginArmingStatus(wgt)
  end
end

local function profileYieldArmingStatusToFlightStats(wgt, now)
  local operation = wgt and wgt.armingStatusOperation or nil
  if not operation then return true end
  -- Cancel only if the queue contains this widget's MSP 101 and no message
  -- owned by another RF Tool consumer.
  if not profileCancelOperationQueue(operation) then return false end
  wgt.armingStatusOperation = nil
  wgt.armingStatusPending = false
  wgt.armingStatusNextAt = now + ARMING_STATUS_INTERVAL
  return true
end

-- RotorFlight persistent flight counter ------------------------------------
-- KSE admits up to six post-flight reads to let the FC total settle.
-- RF Tool owns each admitted request's transmissions and retry lifetime.
local function profileFlightCounterSelected()
  return OPT.flightCounter == FC.ROTORFLIGHT
end

local function profileClearFlightStatsRefresh()
  FC.refreshBase = nil
  FC.refreshAttempts = 0
end

local function profileRequestFlightStatsRefresh(now, afterFlight)
  FC.wanted = true
  FC.stableSince = now
  if afterFlight and FC.count ~= nil then
    FC.refreshBase = FC.count
    FC.refreshAttempts = 0
    FC.stale = true
  end
end

local function profileFinishFlightStats(wgt, stats, token)
  local operation = wgt and wgt.profileOperation or nil
  if not operation or operation.kind ~= "flightStats"
     or operation.token ~= token then return end
  if not MspAdmission.valid(wgt, operation) then return end
  wgt.profileOperation = nil
  wgt.profileBusy = false
  wgt.profilePending = nil
  FC.pending = false
  if not profileFlightCounterSelected()
     or operation.model ~= flightModel then return end
  if type(stats) ~= "table" or type(stats.statsEnabled) ~= "table"
     or tonumber(stats.statsEnabled.value) ~= 1 then
    FC.count, FC.stale, FC.status = nil, false, "STATS OFF"
    profileClearFlightStatsRefresh()
    return
  end
  local count = type(stats.stats_total_flights) == "table"
                and tonumber(stats.stats_total_flights.value) or nil
  if not count or not (count >= 0) or count > math.floor(count) then
    FC.count, FC.stale, FC.status = nil, false, "BAD REPLY"
    profileClearFlightStatsRefresh()
    return
  end
  if operation.refreshBase ~= nil
     and count == operation.refreshBase
     and operation.refreshAttempt < FC.confirmMaxReads then
    FC.stale, FC.status = true, "CONFIRMING"
    FC.wanted = true
    FC.stableSince = profileNow()
    return
  end
  FC.count, FC.stale, FC.status = count, false, "AVAILABLE"
  profileClearFlightStatsRefresh()
end

local function profileFailFlightStats(wgt, token, status)
  local operation = wgt and wgt.profileOperation or nil
  if not operation or operation.kind ~= "flightStats"
     or (token and operation.token ~= token) then return end
  profileCancelOperationQueue(operation)
  wgt.profileOperation = nil
  wgt.profileBusy = false
  wgt.profilePending = nil
  FC.pending = false
  FC.stale = FC.count ~= nil
  FC.status = status or "NO REPLY"
  local retryable = status == "NO REPLY" or status == "QUEUE ERROR"
                    or status == "REQUEST ERROR"
  if retryable and profileFlightCounterSelected()
     and operation.model == flightModel
     and operation.refreshBase ~= nil
     and operation.refreshAttempt < FC.confirmMaxReads then
    FC.wanted = true
    FC.stableSince = profileNow()
    FC.status = "RETRYING"
  end
end

local function profileBeginFlightStats(wgt)
  if not MspAdmission.disarmed(wgt) then return false end
  if wgt.profileBusy then return false end
  local queue = profileSharedQueue()
  if not queue or not profileQueueIdle(queue) then return false end
  local api = profileRfApi("mspFlightStats")
  if not api or type(api.read) ~= "function" then
    FC.status = "NO API"
    return false
  end

  wgt.profileOperationToken = (wgt.profileOperationToken or 0) + 1
  local token = wgt.profileOperationToken
  local refreshAttempt = 0
  if FC.refreshBase ~= nil then
    FC.refreshAttempts = FC.refreshAttempts + 1
    refreshAttempt = FC.refreshAttempts
  end
  local operation = {
    token=token, kind="flightStats", startedAt=profileNow(),
    queue=queue, messages={}, model=flightModel,
    refreshBase=FC.refreshBase, refreshAttempt=refreshAttempt,
  }
  MspAdmission.capture(wgt, operation)
  wgt.profileOperation = operation
  wgt.profileBusy = true
  FC.pending, FC.wanted, FC.status = true, false, "LOADING"

  local apiOk, messageAdded = profileCallApiAndCollect(
    queue, operation,
    function()
      api.read(function(_, stats)
        profileFinishFlightStats(wgt, stats, token)
      end, wgt)
    end)
  local decorated = false
  if apiOk and messageAdded then
    for _, message in ipairs(operation.messages) do
      if type(message) == "table" and message.command == 14 then
        decorated = true
        message.errorHandler = function()
          profileFailFlightStats(wgt, token, "NO REPLY")
        end
      end
    end
  end
  if not apiOk or not messageAdded or not decorated then
    profileFailFlightStats(wgt, token, "REQUEST ERROR")
    return false
  end
  return true
end

local function profileFinishSnapshotIfReady(wgt, token)
  local operation = wgt.profileOperation
  if not operation or operation.token ~= token
     or operation.kind ~= "snapshot"
     or not operation.activeDone or not operation.capacityDone then return end
  wgt.profileOperation = nil
  wgt.profileBusy = false
  wgt.profilePending = nil
  wgt.profileInitialReadFinished = true
  wgt.profileCapacityReadFinished = true
  if wgt.profileCapacitiesReady then
    local summary = {}
    for i = 1, BATTERY_PROFILE_COUNT do
      local capacity = wgt.profileCapacities
                       and tonumber(wgt.profileCapacities[i]) or nil
      summary[i] = capacity and tostring(math.floor(capacity)) or "-"
    end
    profileSetMessage(wgt, "mAh  " .. table.concat(summary, " / "), C_DIM)
  elseif wgt.profileInitialReadValid and wgt.profileActive then
    local length = tonumber(wgt.profileCapacityReplyLength)
    profileSetMessage(wgt,
      length and ("MSP 32: " .. tostring(length) .. " BYTES, NO mAh")
        or "MSP 32 mAh NOT RECEIVED", C_YELLOW)
  else
    profileSetMessage(wgt, "PROFILE DATA UNAVAILABLE", C_DIM)
  end
end

local function profileSnapshotActiveReceived(wgt, zeroBased, token)
  local operation = wgt.profileOperation
  if not operation or operation.token ~= token
     or operation.kind ~= "snapshot" then return end
  if not MspAdmission.valid(wgt, operation) then return end
  local index = tonumber(zeroBased)
  if index and not (index > math.floor(index))
     and index >= 0 and index < BATTERY_PROFILE_COUNT then
    wgt.profileActive = index + 1
    wgt.profileInitialReadValid = true
    F.battProfile = index + 1
  else
    wgt.profileInitialReadValid = false
  end
  operation.activeDone = true
  operation.capacityStartedAt = profileNow()
  if wgt.profileInitialReadValid and wgt.profileActive then
    profileSetMessage(wgt,
      "PROFILE " .. tostring(wgt.profileActive) .. " ACTIVE - READING mAh...",
      C_YELLOW)
  end
  profileFinishSnapshotIfReady(wgt, token)
end

local function profileSnapshotCapacitiesReceived(wgt, value, token, raw)
  local operation = wgt.profileOperation
  if not operation or operation.token ~= token
     or operation.kind ~= "snapshot" then return end
  if not MspAdmission.valid(wgt, operation) then return end
  local capacities, allProfiles
  if raw then
    wgt.profileCapacityReplyLength = type(value) == "table" and #value or 0
    capacities, allProfiles = profileDecodeCapacityRaw(wgt, value)
  else
    capacities, allProfiles = profileDecodeCapacityConfig(wgt, value)
  end
  if capacities then
    wgt.profileCapacities = capacities
    wgt.profileCapacitiesReady = true
    wgt.profileCapacitiesComplete = allProfiles
  else
    wgt.profileCapacities = nil
    wgt.profileCapacitiesReady = false
    wgt.profileCapacitiesComplete = false
  end
  operation.capacityDone = true
  profileFinishSnapshotIfReady(wgt, token)
end

local function profileBeginSnapshot(wgt)
  if not MspAdmission.disarmed(wgt) then return false end
  if wgt.profileBusy then return false end
  local queue = profileSharedQueue()
  if not queue then
    profileSetMessage(wgt, "RF TOOL 2.3 REQUIRED", C_RED)
    return false
  end
  if not profileQueueIdle(queue) then
    profileSetMessage(wgt, "WAITING FOR RF TOOL QUEUE...", C_YELLOW)
    return false
  end
  wgt.profileOperationToken = (wgt.profileOperationToken or 0) + 1
  local token = wgt.profileOperationToken
  local operation = {
    token=token, kind="snapshot", startedAt=profileNow(),
    queue=queue, messages={}, activeDone=false, capacityDone=false,
  }
  MspAdmission.capture(wgt, operation)
  wgt.profileOperation = operation
  wgt.profileBusy = true
  wgt.profileInitialReadRequested = true
  wgt.profileCapacityReadRequested = true
  profileSetMessage(wgt, "READING BATTERY PROFILE DATA...", C_YELLOW)

  local function failed()
    profileCancelOperationQueue(operation)
    profileOperationFailed(wgt, "PROFILE DATA NOT RECEIVED", token)
  end
  local function activeRaw(_, buf)
    profileSnapshotActiveReceived(wgt,
      type(buf) == "table" and buf[1] or nil, token)
  end
  local function capacitiesRaw(_, buf)
    profileSnapshotCapacitiesReceived(wgt, buf, token, true)
  end
  local function activeConfig(_, config)
    local value = type(config) == "table"
                  and type(config.batteryProfile) == "table"
                  and config.batteryProfile.value or nil
    profileSnapshotActiveReceived(wgt, value, token)
  end
  local function capacitiesConfig(_, config)
    profileSnapshotCapacitiesReceived(wgt, config, token, false)
  end

  local activeApi = profileRfApi("mspBatteryProfile")
  local capacityApi = profileRfApi("mspBatteryConfig")
  if activeApi and type(activeApi.read) == "function"
     and capacityApi and type(capacityApi.read) == "function" then
    local activeOk, activeAdded = profileCallApiAndCollect(
      queue, operation, function() activeApi.read(activeConfig, wgt) end)
    local capacityOk, capacityAdded = false, false
    if activeOk and activeAdded then
      capacityOk, capacityAdded = profileCallApiAndCollect(
        queue, operation, function() capacityApi.read(capacitiesConfig, wgt) end)
    end
    if activeOk and activeAdded and capacityOk and capacityAdded then
      for _, message in ipairs(operation.messages) do
        if message.command == MSP_BATTERY_CONFIG then
          message.processReply = capacitiesRaw
          message.retryDelay = 4
        end
      end
      profileInstallErrorHandler(operation.messages, failed)
      return true
    end
    profileCancelOperationQueue(operation)
    operation.messages = {}
  end

  local activeMessage = {
    command=MSP_BATTERY_PROFILE,
    processReply=activeRaw,
  }
  local capacityMessage = {
    command=MSP_BATTERY_CONFIG,
    processReply=capacitiesRaw,
    retryDelay=4,
  }
  operation.messages[#operation.messages + 1] = activeMessage
  operation.messages[#operation.messages + 1] = capacityMessage
  queue:add(activeMessage)
  queue:add(capacityMessage)
  profileInstallErrorHandler(operation.messages, failed)
  return true
end

local function profileBeginOperation(wgt, kind, target)
  if not MspAdmission.disarmed(wgt) then return false end
  if kind ~= "select" and kind ~= "activeCapacity" then return false end
  if type(target) ~= "number" or not (target >= 1 and target <= BATTERY_PROFILE_COUNT)
     or target > math.floor(target) then return false end
  if wgt.profileBusy then return false end
  local queue = profileSharedQueue()
  if not queue then
    profileSetMessage(wgt, "RF TOOL 2.3 REQUIRED", C_RED)
    return false
  end
  if not profileQueueIdle(queue) then
    profileSetMessage(wgt, "WAITING FOR RF TOOL QUEUE...", C_YELLOW)
    return false
  end
  wgt.profileOperationToken = (wgt.profileOperationToken or 0) + 1
  local token = wgt.profileOperationToken
  local operation = {
    token=token, kind=kind, target=target, startedAt=profileNow(),
    queue=queue, messages={}, stage=kind == "select" and "set" or nil,
  }
  MspAdmission.capture(wgt, operation)
  wgt.profileOperation = operation
  wgt.profileBusy = true
  wgt.profilePending = kind == "select" and target or nil
  profileSetMessage(wgt,
    kind == "select" and ("SETTING PROFILE " .. tostring(target) .. "...")
      or ("READING PROFILE " .. tostring(target) .. " mAh..."), C_YELLOW)
  local function failed()
    profileCancelOperationQueue(operation)
    profileOperationFailed(wgt,
      kind == "select"
        and (operation.stage == "save"
             and "PROFILE ACTIVE BUT SAVE FAILED"
             or "PROFILE CHANGE NOT CONFIRMED")
       or "ACTIVE CAPACITY NOT RECEIVED", token)
  end

  if kind == "activeCapacity" then
    local message = {
      command=MSP_BATTERY_STATE,
      processReply=function(_, buf)
        profileActiveCapacityReceived(wgt, buf, token)
      end,
      errorHandler=failed,
    }
    operation.messages[#operation.messages + 1] = message
    queue:add(message)
    return true
  end

  -- A profile change is not complete until the FC acknowledges the runtime
  -- selection, MSP 175 reads the same profile back, and MSP 250 commits it to
  -- EEPROM. Admit each continuation on a later checked service pass.
  local verifyMessage, saveMessage
  local setMessage = {
    command=MSP_SET_BATTERY_PROFILE,
    payload={ target - 1 },
    processReply=function()
      local current = wgt.profileOperation
      if not current or current.token ~= token
         or not MspAdmission.valid(wgt, current) then return end
      current.nextMessage = verifyMessage
      current.stage = "verify"
      current.stageStartedAt = profileNow()
      profileSetMessage(wgt,
        "VERIFYING PROFILE " .. tostring(target) .. "...", C_YELLOW)
    end,
    errorHandler=failed,
  }
  verifyMessage = {
    command=MSP_BATTERY_PROFILE,
    processReply=function(_, buf)
      profileSelectionVerified(wgt,
        type(buf) == "table" and buf[1] or nil, token)
      if wgt.profileOperation == operation and operation.verified
         and MspAdmission.valid(wgt, operation) then
        operation.nextMessage = saveMessage
      end
    end,
    errorHandler=failed,
  }
  saveMessage = {
    command=MSP_EEPROM_WRITE,
    processReply=function()
      profileSelectionSaved(wgt, target, token)
    end,
    errorHandler=failed,
  }
  operation.messages[#operation.messages + 1] = setMessage
  operation.messages[#operation.messages + 1] = verifyMessage
  operation.messages[#operation.messages + 1] = saveMessage
  queue:add(setMessage)
  return true
end

local function profileCheckOperationTimeout(wgt, now)
  local operation = wgt.profileOperation
  if not operation then return end
  local timeout, startedAt
  startedAt = operation.startedAt
  if operation.kind == "snapshot" then
    if operation.activeDone then
      timeout = PROFILE_SNAPSHOT_CAPACITY_TIMEOUT
      startedAt = operation.capacityStartedAt or startedAt
    else
      timeout = PROFILE_SNAPSHOT_ACTIVE_TIMEOUT
    end
  elseif operation.kind == "activeCapacity" then
    timeout = PROFILE_ACTIVE_CAPACITY_TIMEOUT
  elseif operation.kind == "select" then
    timeout = PROFILE_SELECT_TIMEOUT
    startedAt = operation.stageStartedAt or startedAt
  elseif operation.kind == "flightStats" then
    timeout = PROFILE_FLIGHT_STATS_TIMEOUT
  else
    timeout = PROFILE_READ_TIMEOUT
  end
  if now - startedAt < timeout and not wgt.profileQueueFault then return end
  if operation.kind == "flightStats" then
    profileFailFlightStats(wgt, operation.token,
      wgt.profileQueueFault and "QUEUE ERROR" or "NO REPLY")
    wgt.profileQueueFault = nil
    return
  end
  profileCancelOperationQueue(operation)
  local message = wgt.profileQueueFault and "RF TOOL QUEUE ERROR"
                  or (operation.kind == "snapshot"
                      and "PROFILE DATA NOT RECEIVED"
                      or (operation.kind == "activeCapacity"
                          and "ACTIVE CAPACITY NOT RECEIVED"
                          or (operation.kind == "select"
                              and (operation.stage == "save"
                                   and "PROFILE ACTIVE BUT SAVE TIMED OUT"
                                   or "PROFILE CHANGE NOT CONFIRMED")
                              or "PROFILE REQUEST TIMED OUT")))
  wgt.profileQueueFault = nil
  profileOperationFailed(wgt, message, operation.token)
end

local function profileCapacityInProgress(wgt)
  local operation = wgt and wgt.profileOperation or nil
  return wgt and wgt.profileBusy and operation
         and operation.kind == "activeCapacity"
end

local function profileStopCapacityRead(wgt)
  if not profileCapacityInProgress(wgt) then return true end
  local operation = wgt.profileOperation
  if not profileCancelOperationQueue(operation) then return false end
  wgt.profileOperation = nil
  wgt.profileBusy = false
  wgt.profilePending = nil
  profileSetMessage(wgt, "CAPACITY READ SKIPPED", C_DIM)
  return true
end

local function profileSwitchUnsafe(wgt)
  local allowed, reason = MspAdmission.disarmed(wgt)
  return not allowed, reason
end

local closeBatteryProfileMenu
local showBatteryProfileMenu

local function profileCapacityText(wgt, profileIndex)
  if not wgt.profileCapacitiesReady then
    if wgt.profileCapacityReadRequested
       and not wgt.profileCapacityReadFinished then return "READING..." end
    return ""
  end
  local capacity = wgt.profileCapacities
                   and tonumber(wgt.profileCapacities[profileIndex]) or nil
  if capacity == nil then return "" end
  if capacity <= 0 then return "NOT SET" end
  return tostring(math.floor(capacity)) .. " mAh"
end

local function profileButtonText(wgt, profileIndex, multiline)
  local capacity = profileCapacityText(wgt, profileIndex)
  local text = "P" .. tostring(profileIndex)
  local active = wgt.profileActive == profileIndex
  if multiline and capacity ~= "" then
    if active then text = text .. "  ACTIVE" end
    text = text .. "\n" .. capacity
  else
    if capacity ~= "" then text = text .. "  " .. capacity end
    if active then text = text .. "  ACTIVE" end
  end
  return text
end

local function showNativeBatteryProfileMenu(wgt)
  local epoch = wgt.kseOwnerEpoch
  local function current() return WidgetOwner.current(wgt) and wgt.kseOwnerEpoch == epoch end
  if not lvgl or type(lvgl.menu) ~= "function" then
    profileSetNotice(wgt, "BATTERY PROFILE ERROR",
      "UPDATE EDGETX FOR PROFILE PICKER", C_RED, 500)
    return false
  end
  local title = "BATTERY PROFILES"
  if wgt.profileActive then
    title = title .. " - P" .. tostring(wgt.profileActive) .. " ACTIVE"
  end
  local unsafe, unsafeMessage = profileSwitchUnsafe(wgt)
  local profileIndexes = {}
  local values = {}
  for i = 1, BATTERY_PROFILE_COUNT do
    local capacity = wgt.profileCapacities
                     and tonumber(wgt.profileCapacities[i]) or nil
    if capacity and capacity > 0 then
      profileIndexes[#profileIndexes + 1] = i
      values[#values + 1] = profileButtonText(wgt, i, false)
    end
  end
  if #profileIndexes == 0 then
    values[#values + 1] = "NO CONFIGURED PROFILES"
  end
  local safetyIndex
  if unsafe then
    safetyIndex = #values + 1
    values[safetyIndex] = "LOCKED: " .. tostring(unsafeMessage)
  end
  values[#values + 1] = "CLOSE"
  local ok = pcall(lvgl.menu, {
    title=title,
    values=values,
    get=function()
      for valueIndex, profileIndex in ipairs(profileIndexes) do
        if wgt.profileActive == profileIndex then return valueIndex end
      end
      return 0
    end,
    set=function(selected)
      if not current() then return end
      local valueIndex = tonumber(selected)
      wgt.profileAutoShown = true
      if safetyIndex and valueIndex == safetyIndex then
        profileSetNotice(wgt, "PROFILE CHANGE LOCKED",
                         unsafeMessage, C_RED, 500)
        return
      end
      local profileIndex = valueIndex and profileIndexes[valueIndex] or nil
      if not profileIndex then return end
      local ready = profileTransport() ~= nil
                    and (wgt.profileRfState == "connected"
                         or wgt.profileRfState == "armed"
                         or wgt.profileRfState == "disarmed")
      if not ready or (wgt.profileBusy
                       and not profileCapacityInProgress(wgt)) then
        profileSetNotice(wgt, "BATTERY PROFILE ERROR",
                         profileRfToolStatus(wgt), C_RED, 500)
        return
      end
      if wgt.profileActive == profileIndex then
        profileSetNotice(wgt,
          "PROFILE " .. tostring(profileIndex) .. " IS ACTIVE",
          profileCapacityText(wgt, profileIndex) ~= ""
            and profileCapacityText(wgt, profileIndex) or "CURRENTLY ACTIVE",
          C_GREEN, PROFILE_SELECTION_NOTICE, true)
        return
      end
      local blocked, blockedMessage = profileSwitchUnsafe(wgt)
      if blocked then
        profileSetMessage(wgt, blockedMessage, C_RED)
        profileSetNotice(wgt, "PROFILE CHANGE LOCKED",
                         blockedMessage, C_RED, 500)
        return
      end
      wgt.profileSelectionRequested = profileIndex
      profileSetMessage(wgt,
        "SETTING PROFILE " .. tostring(profileIndex) .. "...", C_YELLOW)
    end,
  })
  if not ok then
    profileSetNotice(wgt, "BATTERY PROFILE ERROR",
                     "NATIVE MENU FAILED", C_RED, 500)
  end
  return ok
end

closeBatteryProfileMenu = function(wgt)
  local dialog = wgt and wgt.profileDialog or nil
  if wgt then wgt.profileDialog = nil end
  if dialog and type(dialog.close) == "function" then
    pcall(dialog.close, dialog)
  end
end

showBatteryProfileMenu = function(wgt)
  local epoch = wgt.kseOwnerEpoch
  local function current() return WidgetOwner.current(wgt) and wgt.kseOwnerEpoch == epoch end
  if wgt.profileDialog then return true end
  if G.preferNativePicker and (G.w < 430 or G.h < 300) and lvgl
     and type(lvgl.menu) == "function"
     and showNativeBatteryProfileMenu(wgt) then return true end
  if not lvgl or type(lvgl.dialog) ~= "function" then
    return showNativeBatteryProfileMenu(wgt)
  end
  local title = G.name .. " BATTERY PROFILES"
  local style = G.pickerStyle()
  if wgt.profileActive then
    title = title .. " - P" .. tostring(wgt.profileActive) .. " ACTIVE"
  end
  local dialogW = math.min(400, math.max(240, G.w - 24), G.w)
  local dialogH = math.min(285, math.max(180, G.h - 18), G.h)
  -- EdgeTX dialog height includes its fixed header (44 px on 800-wide
  -- displays, 32 px on 480-wide). Scale children within the remaining body.
  local dialogBodyH = math.max(1, dialogH - (G.screenW == 800 and 44 or 32))
  local function dx(value) return math.max(1, G.rounded(value * dialogW / 400)) end
  local function dy(value) return math.max(1, G.rounded(value * dialogBodyH / 253)) end
  local dialogOk, dialog = pcall(lvgl.dialog, {
    title=title, w=dialogW, h=dialogH,
    close=function() if current() then wgt.profileDialog = nil end end,
  })
  if not dialogOk or type(dialog) ~= "table"
     or type(dialog.build) ~= "function" then
    return showNativeBatteryProfileMenu(wgt)
  end
  wgt.profileDialog = dialog
  local profileIndexes = {}
  for i = 1, BATTERY_PROFILE_COUNT do
    local capacity = wgt.profileCapacities
                     and tonumber(wgt.profileCapacities[i]) or nil
    if capacity and capacity > 0 then
      profileIndexes[#profileIndexes + 1] = i
    end
  end
  local children = {}
  for buttonIndex, profileIndex in ipairs(profileIndexes) do
    local col = (buttonIndex - 1) % 2
    local row = math.floor((buttonIndex - 1) / 2)
    children[#children + 1] = {
      type="button", x=dx(18 + col * 190), y=dy(22 + row * 52),
      w=dx(174), h=dy(46), font=style.font, cornerRadius=style.radius,
      color=function()
        if wgt.profileActive == profileIndex then return C_GREEN end
        if wgt.profilePending == profileIndex then return C_YELLOW end
        return style.color
      end,
      textColor=C_TEXT,
      text=profileButtonText(wgt, profileIndex, true),
      active=function()
        if not current() then return false end
        local unsafe = profileSwitchUnsafe(wgt)
        return profileTransport() ~= nil and not unsafe
               and (not wgt.profileBusy or profileCapacityInProgress(wgt))
               and wgt.profileActive ~= profileIndex
      end,
      press=function()
      if not current() then return end
        if (wgt.profileBusy and not profileCapacityInProgress(wgt))
           or wgt.profileActive == profileIndex then return end
        local blocked, blockedMessage = profileSwitchUnsafe(wgt)
        if blocked then
          profileSetNotice(wgt, "PROFILE CHANGE LOCKED",
                           blockedMessage, C_RED, 500)
          return
        end
        wgt.profileSelectionRequested = profileIndex
        wgt.profileAutoShown = true
        profileSetMessage(wgt,
          "SETTING PROFILE " .. tostring(profileIndex) .. "...", C_YELLOW)
        closeBatteryProfileMenu(wgt)
      end,
    }
  end
  children[#children + 1] = {
    type="label", x=dx(18), y=dy(181), w=dx(364), h=dy(22),
    font=style.font,
    color=(function()
      local unsafe = profileSwitchUnsafe(wgt)
      return unsafe and C_RED or (wgt.profileMessageColor or C_DIM)
    end)(),
    align=CENTERED,
    text=(function()
      local unsafe, unsafeMessage = profileSwitchUnsafe(wgt)
      if unsafe then return unsafeMessage end
      if #profileIndexes == 0 then return "NO CONFIGURED PROFILES" end
      return wgt.profileMessage or "SELECT A PROFILE"
    end)(),
  }
  children[#children + 1] = {
    type="button", x=dx(18), y=dy(213), w=dx(174), h=dy(40),
    text="TRY mAh", color=style.color, textColor=C_TEXT,
    font=style.font, cornerRadius=style.radius,
    active=function() return current() and not wgt.profileBusy end,
    press=function()
      if not current() then return end
      if wgt.profileBusy then return end
      wgt.profileCapacityRefreshRequested = true
      wgt.profileAutoShown = false
      closeBatteryProfileMenu(wgt)
    end,
  }
  children[#children + 1] = {
    type="button", x=dx(208), y=dy(213), w=dx(174), h=dy(40),
    text="CLOSE", color=style.color, textColor=C_TEXT,
    font=style.font, cornerRadius=style.radius,
    press=function()
      if not current() then return end
      wgt.profileAutoShown = true
      closeBatteryProfileMenu(wgt)
    end,
  }
  local buildOk = pcall(dialog.build, dialog, children)
  if not buildOk then
    closeBatteryProfileMenu(wgt)
    return showNativeBatteryProfileMenu(wgt)
  end
  return true
end

local function profileRegisterWithRfTool(wgt)
  local shared = profileRfToolProvider()
  if wgt.profileRfProviderRef ~= shared then
    wgt.profileRfProviderRef = shared
    wgt.profileRfToolRegistered = false
    wgt.profileProviderChanged = true
  end
  if not shared then return end
  local toolApi = tonumber(shared.rfToolApiVersion)
  local canRegister = toolApi and toolApi >= RF_TOOL_WIDGET_API
                      and type(shared.registerWidget) == "function"
  if canRegister and not wgt.profileRfToolRegistered then
    wgt.profileRfToolRegistered = WidgetOwner.register(shared)
  end
  local state
  if shared.widget and shared.widget.state then
    state = shared.widget.state
  elseif not canRegister and tonumber(shared.apiVersion)
         and tonumber(shared.apiVersion) >= ROTORFLIGHT_23_MSP_API
         and (profileRfToolInstanceLive() == shared
              or profileRadioLinkLive()) then
    state = "connected"
  end
  if state and state ~= wgt.profileRfState then wgt.profileRfState = state end
end

local function profileControllerConnected(wgt)
  local state = wgt.profileRfState
  return profileSharedQueue() ~= nil
         and (state == "connected" or state == "armed" or state == "disarmed")
end

local function profileOnlyConfigured(wgt)
  if not wgt.profileCapacitiesReady
     or not wgt.profileCapacitiesComplete
     or type(wgt.profileCapacities) ~= "table" then return nil end
  local onlyProfile
  for i = 1, BATTERY_PROFILE_COUNT do
    local capacity = tonumber(wgt.profileCapacities[i])
    if not capacity or capacity > math.floor(capacity)
       or capacity < 0 or capacity > BATTERY_CAPACITY_MAX then return nil end
    if capacity > 0 then
      if onlyProfile then return nil end
      onlyProfile = i
    end
  end
  return onlyProfile
end

local function profileResetConnection(wgt)
  if not wgt then return end
  if wgt.armingStatusOperation then
    profileCancelOperationQueue(wgt.armingStatusOperation)
  end
  if wgt.profileOperation
     and wgt.profileOperation.kind == "flightStats" then
    profileFailFlightStats(wgt, wgt.profileOperation.token, "DISCONNECTED")
  elseif wgt.profileOperation then
    profileCancelOperationQueue(wgt.profileOperation)
  end
  wgt.profileUiReset = true
  wgt.profileWasConnected = false
  wgt.profileConnectedForDisplay = false
  G.profileConnectedForDisplay = false
  wgt.profileAutoShown = false
  wgt.profileSingleConfigured = nil
  wgt.profileInitialReadRequested = false
  wgt.profileInitialReadFinished = false
  wgt.profileInitialReadValid = false
  wgt.profileCapacityReadRequested = false
  wgt.profileCapacityReadFinished = false
  wgt.profileCapacitiesReady = false
  wgt.profileCapacitiesComplete = false
  wgt.profileCapacities = nil
  wgt.profileCapacityReplyLength = nil
  wgt.profileSelectionRequested = nil
  wgt.profileActiveCapacityRequested = nil
  wgt.profileCapacityRefreshRequested = nil
  wgt.profileConnectReadyAt = nil
  wgt.profileMenuRetryAt = nil
  wgt.profileDisconnectedSince = nil
  wgt.profileBusy = false
  wgt.profilePending = nil
  wgt.profileOperation = nil
  wgt.profileMessage = nil
  wgt.profileNoticeTitle = nil
  wgt.profileNoticeDetail = nil
  wgt.profileNoticeColor = nil
  wgt.profileNoticeCompact = nil
  wgt.profileNoticeUntil = nil
  wgt.profileActive = nil
  wgt.profileQueueFault = nil
  wgt.armingStatusOperation = nil
  wgt.armingStatusPending = false
  wgt.armingStatusNextAt = nil
  wgt.armingDisableFlags = nil
  wgt.armingBlockerText = nil
  wgt.armingStatusUpdatedAt = nil
  PROFILE_CONFIRMED.value, PROFILE_CONFIRMED.tick = nil, nil
end

local function profileFlightCounterArmState(wgt)
  if wgt.profileRfState == "armed" then return true end
  local value = MspAdmission.sample("ARM")
  if value == nil or value < 0 or value > 255
     or value > math.floor(value) then return nil end
  return math.floor(value) % 2 == 1
end

local function profileFlightCounterSourceChanged(wgt)
  if wgt and wgt.profileOperation
     and wgt.profileOperation.kind == "flightStats" then
    profileFailFlightStats(wgt, wgt.profileOperation.token, "SOURCE CHANGED")
  end
  FC.count, FC.stale, FC.pending = nil, false, false
  FC.stableSince, FC.state, FC.armState = nil, nil, nil
  FC.flightSeenArmed = false
  profileClearFlightStatsRefresh()
  FC.model = flightModel
  if profileFlightCounterSelected() then
    FC.status, FC.wanted = "STARTING", true
  else
    FC.status, FC.wanted = "RADIO", false
  end
end

local function profileServiceFlightCounter(wgt, connected, now)
  if not profileFlightCounterSelected() then return end
  if FC.model ~= flightModel then
    if wgt.profileOperation
       and wgt.profileOperation.kind == "flightStats" then
      profileFailFlightStats(wgt, wgt.profileOperation.token, "MODEL CHANGED")
    end
    FC.count, FC.stale, FC.pending = nil, false, false
    FC.status, FC.wanted = "WAITING", true
    FC.stableSince, FC.model = nil, flightModel
    FC.flightSeenArmed = false
    profileClearFlightStatsRefresh()
  end

  local state = wgt.profileRfState
  if not connected then
    if wgt.profileOperation
       and wgt.profileOperation.kind == "flightStats" then
      profileFailFlightStats(wgt, wgt.profileOperation.token, "DISCONNECTED")
    end
    FC.state, FC.armState, FC.stableSince = state, nil, nil
    FC.count, FC.stale, FC.pending = nil, false, false
    FC.flightSeenArmed = false
    profileClearFlightStatsRefresh()
    FC.wanted = true
    FC.status = state == "disconnected" and "DISCONNECTED" or "STARTING"
    return
  end

  if state ~= FC.state then
    local previous = FC.state
    FC.state = state
    if state == "armed" then
      FC.wanted, FC.stableSince = false, nil
      FC.flightSeenArmed = true
      profileClearFlightStatsRefresh()
    elseif state == "disarmed" or state == "connected" then
      if previous == nil or previous == "armed"
         or previous == "disconnected" then
        local afterFlight = FC.flightSeenArmed
        FC.flightSeenArmed = false
        profileRequestFlightStatsRefresh(now, afterFlight)
      end
    end
  end

  local armed = profileFlightCounterArmState(wgt)
  if armed ~= FC.armState then
    local previous = FC.armState
    FC.armState = armed
    if armed == true then
      FC.wanted, FC.stableSince = false, nil
      FC.flightSeenArmed = true
      profileClearFlightStatsRefresh()
      if wgt.profileOperation
         and wgt.profileOperation.kind == "flightStats" then
        profileFailFlightStats(wgt, wgt.profileOperation.token, "ARMED")
      end
    elseif armed == false and previous ~= false then
      local afterFlight = FC.flightSeenArmed
      FC.flightSeenArmed = false
      profileRequestFlightStatsRefresh(now, afterFlight)
    end
  end

  if armed == nil then
    FC.stableSince = nil
    if not FC.pending then FC.status = "NO ARM SENSOR" end
    return
  elseif armed then
    FC.stableSince = nil
    if FC.count == nil and not FC.pending then FC.status = "ARMED" end
    return
  end

  FC.stableSince = FC.stableSince or now
  if FC.wanted and not FC.pending then
    FC.status = "WAITING"
    if now - FC.stableSince >= FC.disarmStableTicks then
      if profileYieldArmingStatusToFlightStats(wgt, now) then
        profileBeginFlightStats(wgt)
      end
    end
  end
end

-- @include variant:rf_touch.lua
local function profileModeAccess()
  local live = not OPT.simTelemetry
  -- Nitro has no RotorFlight battery profiles. It still keeps RF Tool alive
  -- for read-only arming diagnostics and, when selected, MSP 14 flight stats.
  local profiles = live and OPT.heliType == HELI_ELECTRIC
  local arming = live and OPT.heliType ~= HELI_OMPHOBBY
  local flightStats = live and OPT.flightCounter == FC.ROTORFLIGHT
  return profiles, arming, flightStats, arming or flightStats
end

-- Admission and continuations are KSE work. An already active RF Tool
-- transaction is intentionally left alone, including its upstream retries.
local function profileServiceMspAdmission(wgt, now)
  local allowed = MspAdmission.disarmed(wgt)
  local operation = wgt.profileOperation
  if operation and (not allowed or not MspAdmission.valid(wgt, operation)) then
    local kind, target = operation.kind, operation.target
    profileCancelOperationQueue(operation)
    if kind == "flightStats" then
      profileFailFlightStats(wgt, operation.token, "WAITING FOR DISARM")
      FC.wanted = true
    else
      profileOperationFailed(wgt, "REQUEST PAUSED - CHECK PROFILE AFTER DISARM", operation.token)
      if kind == "snapshot" then
        wgt.profileInitialReadRequested = false
        wgt.profileCapacityReadRequested = false
        wgt.profileInitialReadFinished = false
        wgt.profileCapacityReadFinished = false
      elseif kind == "activeCapacity" then
        wgt.profileActiveCapacityRequested = target
      end
      wgt.profileSelectionRequested = nil
    end
  end
  local status = wgt.armingStatusOperation
  if status and (not allowed or not MspAdmission.valid(wgt, status)) then
    profileFailArmingStatus(wgt, status.token)
  end
  if not allowed then
    wgt.armingDisableFlags = nil
    wgt.armingBlockerText = nil
    wgt.armingStatusUpdatedAt = nil
  end
  profileCheckOperationTimeout(wgt, now)
  operation = wgt.profileOperation
  if operation and operation.nextMessage
     and MspAdmission.valid(wgt, operation)
     and profileQueueIdle(operation.queue) then
    local message = operation.nextMessage
    operation.nextMessage = nil
    operation.stageStartedAt = now
    operation.queue:add(message)
  end
end

local function serviceBatteryProfileFeature(wgt, allowUi, event, touchState)
  if not WidgetOwner.current(wgt) then return end
  if allowUi and wgt.profileUiReset then
    closeBatteryProfileMenu(wgt)
    profileSetEntryPrompt(wgt, false)
    wgt.profileUiReset = nil
  end
  profileServiceMspAdmission(wgt, profileNow())
  local profileEligible, armingEligible, counterEligible, rfToolNeeded =
    profileModeAccess()
  if rfToolNeeded then
    profileServiceEmbeddedRfTool(wgt)
    profileRegisterWithRfTool(wgt)
  end
  if wgt.profileProviderChanged then
    wgt.profileProviderChanged = false
    profileResetConnection(wgt)
  end
  local now = profileNow()
  local connected = rfToolNeeded and profileControllerConnected(wgt)
  local showConnected = rfToolNeeded and connected or false
  G.profileConnectedForDisplay = showConnected
  wgt.profileConnectedForDisplay = showConnected
  if profileEligible and connected then
    wgt.profileDisconnectedSince = nil
    if not wgt.profileWasConnected then
      wgt.profileWasConnected = true
      wgt.profileAutoShown = false
      wgt.profileInitialReadRequested = false
      wgt.profileInitialReadFinished = false
      wgt.profileInitialReadValid = false
      wgt.profileCapacityReadRequested = false
      wgt.profileCapacityReadFinished = false
      wgt.profileCapacitiesReady = false
      wgt.profileCapacitiesComplete = false
      wgt.profileCapacities = nil
      wgt.profileCapacityReplyLength = nil
      wgt.profileSelectionRequested = nil
      wgt.profileActiveCapacityRequested = nil
      wgt.profileCapacityRefreshRequested = nil
      wgt.profileConnectReadyAt = now + PROFILE_CONNECT_SETTLE
      wgt.profileMenuRetryAt = nil
      profileSetMessage(wgt, "SELECT A BATTERY PROFILE", C_DIM)
    end

    if wgt.profileCapacityRefreshRequested and not wgt.profileBusy then
      wgt.profileCapacityRefreshRequested = nil
      wgt.profileInitialReadRequested = false
      wgt.profileInitialReadFinished = false
      wgt.profileCapacityReadRequested = false
      wgt.profileCapacityReadFinished = false
      wgt.profileCapacitiesReady = false
      wgt.profileCapacitiesComplete = false
      wgt.profileCapacities = nil
      wgt.profileCapacityReplyLength = nil
      wgt.profileNoticeUntil = nil
      wgt.profileConnectReadyAt = now
      profileSetMessage(wgt, "READING PROFILE CAPACITIES...", C_YELLOW)
    end

    local telemetryProfile = sensors.getBattProfile()
    if telemetryProfile and telemetryProfile ~= wgt.profileActive
       and not wgt.profileBusy then
      wgt.profileActive = telemetryProfile
      wgt.profileInitialReadValid = true
      profileSetMessage(wgt,
        "CURRENT PROFILE " .. tostring(telemetryProfile), C_DIM)
    end

    local unsafe, unsafeMessage = profileSwitchUnsafe(wgt)
    local transportReady = profileTransport() ~= nil
    local connectionSettled = now >= (wgt.profileConnectReadyAt or now)
    if transportReady and connectionSettled and not unsafe
       and not wgt.profileInitialReadRequested
       and not wgt.profileCapacityReadRequested and not wgt.profileBusy then
      profileBeginSnapshot(wgt)
    end

    local snapshotReady = wgt.profileInitialReadFinished
                          and wgt.profileCapacityReadFinished
    local onlyProfile = snapshotReady and profileOnlyConfigured(wgt) or nil
    if onlyProfile then
      wgt.profileAutoShown = true
      wgt.profileSingleConfigured = onlyProfile
      if wgt.profileActive ~= onlyProfile and not unsafe
         and not wgt.profileBusy and not wgt.profileSelectionRequested then
        wgt.profileSelectionRequested = onlyProfile
        profileSetMessage(wgt,
          "USING ONLY PROFILE " .. tostring(onlyProfile) .. "...", C_YELLOW)
      elseif wgt.profileActive == onlyProfile then
        local capacity = wgt.profileCapacities[onlyProfile]
        profileSetMessage(wgt,
          "PROFILE " .. tostring(onlyProfile) .. ": "
            .. tostring(capacity) .. " mAh", C_GREEN)
      end
    else
      wgt.profileSingleConfigured = nil
    end

    local requestedProfile = wgt.profileSelectionRequested
    local selectionQueuedThisPass = false
    if requestedProfile and profileCapacityInProgress(wgt) then
      -- A user choice outranks the optional post-selection capacity read.
      -- Queue ownership checks prevent disturbing another RF Tool consumer.
      profileStopCapacityRead(wgt)
    end
    if requestedProfile and not wgt.profileBusy then
      wgt.profileSelectionRequested = nil
      local blocked, blockedMessage = profileSwitchUnsafe(wgt)
      if profileTransport() == nil then
        profileSetMessage(wgt, profileRfToolStatus(wgt), C_RED)
        profileSetNotice(wgt, "BATTERY PROFILE ERROR",
                         profileRfToolStatus(wgt), C_RED, 500)
      elseif blocked then
        profileSetMessage(wgt, blockedMessage, C_RED)
        profileSetNotice(wgt, "PROFILE CHANGE LOCKED",
                         blockedMessage, C_RED, 500)
      elseif not profileBeginOperation(wgt, "select", requestedProfile) then
        wgt.profileSelectionRequested = requestedProfile
      else
        selectionQueuedThisPass = true
      end
    end

    local activeCapacityProfile = wgt.profileActiveCapacityRequested
    if activeCapacityProfile and not selectionQueuedThisPass
       and not wgt.profileBusy and not unsafe then
      if profileBeginOperation(wgt, "activeCapacity",
                               activeCapacityProfile) then
        wgt.profileActiveCapacityRequested = nil
      end
    end

    local wasAutoShown = wgt.profileAutoShown
    if allowUi then
      local blockingRead = wgt.profileBusy
                           and not profileCapacityInProgress(wgt)
                           and not (wgt.profileOperation
                                    and wgt.profileOperation.kind
                                        == "flightStats")
      if blockingRead then
        profileSetEntryPrompt(wgt, true, "BATTERY PROFILES",
                              wgt.profileMessage or "READING CONTROLLER...",
                              C_YELLOW)
      elseif wgt.profileNoticeUntil and now < wgt.profileNoticeUntil then
        profileSetEntryPrompt(wgt, true,
                              wgt.profileNoticeTitle,
                              wgt.profileNoticeDetail,
                              wgt.profileNoticeColor,
                              wgt.profileNoticeCompact)
      elseif snapshotReady and not wgt.profileAutoShown
             and (not wgt.profileMenuRetryAt
                  or now >= wgt.profileMenuRetryAt) then
        profileSetEntryPrompt(wgt, false)
        local opened = showBatteryProfileMenu(wgt) == true
        wgt.profileAutoShown = opened
        if not opened then wgt.profileMenuRetryAt = now + 500 end
      elseif not snapshotReady and not wgt.profileAutoShown then
        profileSetEntryPrompt(wgt, true,
          unsafe and "BATTERY PROFILE LOCKED" or "READING BATTERY PROFILES",
          wgt.profileMessage or "WAITING FOR RF TOOL...",
          unsafe and C_RED or C_YELLOW)
      else
        profileSetEntryPrompt(wgt, false)
      end
    end

    if wasAutoShown and snapshotReady
       and (not wgt.profileBusy or profileCapacityInProgress(wgt))
       and EVT_TOUCH_TAP and event == EVT_TOUCH_TAP
       and profilePointInBatteryTarget(wgt, touchState) then
      wgt.profileAutoShown = true
      showBatteryProfileMenu(wgt)
    end
  else
    if wgt.profileWasConnected then
      if not wgt.profileDisconnectedSince then
        wgt.profileDisconnectedSince = now
      end
      local explicit = wgt.profileRfToolRegistered
                       and wgt.profileRfState == "disconnected"
      if explicit or now - wgt.profileDisconnectedSince >= 500 then
        profileResetConnection(wgt)
      end
    end
    if allowUi then profileSetEntryPrompt(wgt, false) end
  end
  local controllerConnected = connected == true
  profileServiceFlightCounter(wgt,
    counterEligible and controllerConnected, now)
  local armingConnected = armingEligible and controllerConnected
  profileServiceArmingStatus(wgt, armingConnected, now, allowUi)
end

local function profileRetire(wgt)
  profileCancelOperationQueue(wgt.profileOperation)
  profileCancelOperationQueue(wgt.armingStatusOperation)
  wgt.profileOperation, wgt.armingStatusOperation = nil, nil
  wgt.profileBusy, wgt.armingStatusPending = false, false
end

return {
  retire=profileRetire,
  service=serviceBatteryProfileFeature,
  reset=profileResetConnection,
-- @include variant:rf_exports.lua
  flightSourceChanged=profileFlightCounterSourceChanged,
}
end)()
