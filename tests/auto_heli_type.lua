-- Run from the repository root: lua tests/auto_heli_type.lua
-- Executes both real widgets with mocked EdgeTX/RF Tool/LVGL boundaries.
local assertions = 0
local function eq(actual, expected, message)
  assertions = assertions + 1
  assert(actual == expected, message .. ": expected " .. tostring(expected)
         .. ", got " .. tostring(actual))
end

local function upvalue(fn, wanted)
  for i = 1, 100 do
    local name, value = debug.getupvalue(fn, i)
    if not name then break end
    if name == wanted then return value end
  end
  error("Missing upvalue " .. wanted)
end

local function fixture(variant, name, selection, counter, width, height)
  local t = { name=name, now=1000, rssi=0, builds=0, requests={} }
  local env = setmetatable({}, { __index=_G })
  env._G = env
  env.LCD_W, env.LCD_H = width or 800, height or 480
  env.lcd = { RGB=function(r, g, b) return r * 65536 + g * 256 + b end }
  env.io = { open=function() return nil end }
  env.model = {
    getInfo=function() return { name=t.name } end,
    getTimer=function() return { value=t.timerValue or 0, start=0, mode=0 } end,
  }
  env.getTime = function() return t.now end
  env.getRSSI = function() return t.rssi end
  local sensors = {
    SG=-1024, Hspd=0, Tspd=0, Vbec=7.6, ARM=0, RQly=100,
    ["Cel#"]=6, Vcel=4, Vbat=24, ["Bat%"]=100,
    Curr=0, Capa=0, Tesc=25, Gov=0, ["BAT#"]=1, ["tx-voltage"]=8.1,
  }
  env.getFieldInfo = function(source)
    if sensors[source] ~= nil then return { id=source, name=source } end
  end
  env.getValue = function(source) return sensors[source] end
  env.getSourceValue = function(source)
    if source == "Hspd" and t.opt then t.sampledType = t.opt.heliType end
    return sensors[source], t.rssi > 0, t.rssi > 0
  end
  t.sensors = sensors
  t.labels = {}
  local function object(first, second)
    local o = { properties=second or first }
    t.labels[#t.labels + 1] = o.properties
    function o:set(properties)
      for k, v in pairs(properties) do self.properties[k] = v end
    end
    function o:show() self.visible = true end
    function o:hide() self.visible = false end
    return o
  end
  env.lvgl = {
    clear=function() t.builds = t.builds + 1; t.labels = {} end,
    label=object, rectangle=object, image=object, arc=object,
    hline=object, vline=object,
  }
  t.api = assert(loadfile(variant .. "/main.lua", "t", env))()
  t.opts = {}
  for _, option in ipairs(t.api.options) do t.opts[option[1]] = option[3] end
  t.opts.HeliType = selection or 4
  t.opts.CountSrc = counter or t.opts.CountSrc
  t.widget = t.api.create({ x=0, y=0, w=env.LCD_W, h=env.LCD_H }, t.opts)
  t.opt = upvalue(t.api.update, "OPT")
  t.alerts = upvalue(t.api.update, "A")
  t.data = upvalue(t.api.update, "D")
  t.auto = upvalue(upvalue(t.api.update, "applyOptions"), "AUTO_HELI")
  t.api.update(t.widget, t.opts) -- EdgeTX initializes the retained UI via update().
  t.host = { state="initializing", background=function()
    if t.onHost then t.onHost(); t.onHost = nil end
  end }
  env.rf2 = {
    widget=t.host, apiVersion=12.09, rfToolApiVersion=1,
    registerWidget=function() end,
    mspQueue={
      messageQueue={},
      clear=function(q)
        q.currentMessage, q.lastTimeCommandSent = nil, nil
        q.messageQueue = {}
        t.queueClears = (t.queueClears or 0) + 1
      end,
      add=function(q, message)
        t.requests[#t.requests + 1] = message
        q.messageQueue[#q.messageQueue + 1] = message
      end,
      processQueue=function(q) if t.onQueue then t.onQueue(q) end end,
      isProcessed=function(q) return q.currentMessage == nil and #q.messageQueue == 0 end,
    },
  }
  function t:connect(aircraftName)
    self.rssi, self.name = 100, aircraftName
    self.host.state = "connected"
    env.rf2.modelName = aircraftName
  end
  function t:disconnect()
    self.rssi, self.name = 0, "Shared Heli"
    self.host.state, env.rf2.modelName = "disconnected", nil
  end
  function t:settle(visible)
    for _ = 1, 4 do self:step(visible) end
  end
  function t:hasText(text)
    for _, properties in ipairs(self.labels) do
      if properties.text == text then return true end
    end
    return false
  end
  function t:step(visible)
    self.now = self.now + 20
    if visible then self.api.refresh(self.widget, 0)
    else self.api.background(self.widget) end
  end
  t.env = env
  return t
end

for _, variant in ipairs({ "KSE4", "KSE5" }) do
  local t = fixture(variant, "Shared Heli")
  eq(#t.api.options, 10, variant .. " option count")
  eq(table.concat(t.api.options[4][4], ","), "Electric,Nitro,OMPHOBBY,Auto",
     "saved choice values stay compatible")
  eq(t.api.options[4][3], 1, "Electric remains default")
  for name, expected in pairs({
    ["RAW 700N"]=2, ["RAW 700n  "]=2, ["RAW nItRo\t"]=2,
    ["N"]=2, ["Nitro"]=2, ["Goblin"]=2, ["RAWN"]=2, ["RAWNitro"]=2,
    ["RAW 700"]=1, ["Nitro 700E"]=1, ["OMP M2"]=1, [""]=1,
  }) do eq(t.auto.infer(name), expected, "literal suffix: " .. name) end
  eq(t.auto.infer(nil), 1, "missing name")

  t.rssi = 100
  t.sensors["Bat%"], t.sensors.Vcel = 10, 3.5
  t:settle(true)
  eq(t.auto.ready, false, "startup waits for connected FC")
  eq(t.alerts.battAlertPrevPct, nil, "unresolved startup skips battery alerts")
  eq(t.widget.profileWasConnected, false, "startup skips battery profiles")
  eq(t:hasText("WAITING FOR FC NAME"), true, "visible waiting indication")

  -- RF Tool can publish during this very callback. TX naming stays disabled.
  t.onHost = function() t:connect("RAW 700N"); t.name = "Shared Heli" end
  t:step(true)
  eq(t.auto.ready, false, "first name sample begins confirmation")
  eq(t:hasText("CONFIRMING FC NAME"), true, "visible confirmation indication")
  t:step(true)
  eq(t.auto.ready, false, "20 ticks is below 30-tick confirmation")
  t:step(true)
  eq(t.auto.ready, true, "stable name confirms")
  eq(t.opt.heliType, 2, "FC name selects Nitro with TX naming disabled")
  eq(t.sampledType, 2, "confirmed mode is applied before telemetry")
  eq(t.opt.battBarMode, 1, "Nitro layout selected")
  eq(t.widget.profileWasConnected, false, "Nitro has no battery profiles")
  eq(t.opts.HeliType, 4, "saved option stays Auto")
  eq(upvalue(t.api.create, "getModelName")(), "RAW 700N", "display/count identity uses FC name")

  local builds = t.builds
  t.alerts.rxDeadVoiceLatched = true
  t:settle(true)
  eq(t.builds, builds, "stable identity does not rebuild")
  eq(t.alerts.rxDeadVoiceLatched, true, "stable identity preserves warning latch")

  -- Brief radio dropout: do not accept a name, clear warning latches, or count
  -- the restored/generic transmitter name as a different helicopter.
  t.rssi = 0
  t:step(true)
  eq(t.auto.ready, false, "RSSI zero prevents readiness despite connected RF state")
  eq(t:hasText("AUTO DISCONNECTED"), true, "visible disconnect indication")
  eq(t.opt.heliType, 2, "dropout holds previous mode")
  t.rssi = 100
  t:settle(true)
  eq(t.alerts.rxDeadVoiceLatched, true, "brief dropout preserves warning latch")
  eq(t.builds, builds, "brief dropout does not rebuild")

  t:disconnect(); t:step(true)
  eq(t.opt.heliType, 2, "full disconnect retains Nitro")
  eq(upvalue(t.api.create, "getModelName")(), "RAW 700N", "disconnect retains confirmed identity")
  t.opts.Theme = 2
  t.api.update(t.widget, t.opts)
  eq(t.opt.heliType, 2, "theme edit preserves Nitro while disconnected")
  eq(t.auto.ready, false, "theme edit cannot enable unresolved alerts")
  t.host.state, t.rssi, t.env.rf2.modelName = "initializing", 100, "Old Electric"
  t:settle(false)
  eq(t.auto.ready, false, "stale name during initialization is ignored")

  t:connect("RAW 700")
  builds = t.builds
  t:step(false)
  eq(t.auto.ready, false, "new aircraft starts unresolved")
  eq(t.widget.profileWasConnected, false, "no profiles during confirmation")
  t:settle(false)
  eq(t.opt.heliType, 1, "hidden widget resolves Electric")
  eq(t.opt.battBarMode, 0, "Electric layout selected")
  eq(t.alerts.rxDeadVoiceLatched, false, "new identity resets prior warning")
  eq(t.data.rxVoltage, nil, "Electric clears receiver voltage")
  eq(t.builds, builds, "background never rebuilds UI")
  eq(t.widget.layoutSignature, nil, "layout invalidated for visible refresh")
  eq(t.widget.profileWasConnected, true, "confirmed Electric enables profiles")
  t:step(true)
  eq(t.builds, builds + 1, "visible refresh rebuilds once")

  -- A name change with no intervening disconnected callback must invalidate
  -- readiness and old operations immediately, before pumping the shared queue.
  local q = t.env.rf2.mspQueue
  q.messageQueue, q.currentMessage = {}, nil
  local stale = { command=176 }
  local unrelated1, unrelated2 = { command=10 }, { command=11 }
  q.currentMessage, q.messageQueue = stale, { unrelated1, { command=175 }, unrelated2 }
  t.widget.profileOperation = { kind="select", queue=q, messages={stale, q.messageQueue[2]} }
  t.widget.profileBusy = true
  local priorAlertPercent = t.alerts.battAlertPrevPct
  t:connect("Other Nitro")
  local checkedQueue = false
  t.onQueue = function(queue)
    checkedQueue = true
    eq(queue.currentMessage, nil, "old current operation cancelled before pump")
    eq(#queue.messageQueue, 2, "only unrelated queued requests retained")
    eq(queue.messageQueue[1], unrelated1, "first unrelated request retained")
    eq(queue.messageQueue[2], unrelated2, "FIFO order retained")
  end
  t:step(false)
  t.onQueue = nil
  eq(checkedQueue, true, "queue pump actually exercised")
  eq(t.auto.ready, false, "changed name invalidates old readiness immediately")
  eq(t.alerts.battAlertPrevPct, priorAlertPercent, "new identity does not advance old Electric alerts")
  eq(t.widget.profileOperation, nil, "old operation reference cleared")
  t:settle(false)
  eq(t.opt.heliType, 2, "new Nitro eventually confirms")

  -- Pending owned requests can be removed without cancelling another
  -- consumer's in-flight request or changing its retry state.
  q.currentMessage, q.lastTimeCommandSent = unrelated1, 123
  local pending = { command=175 }
  q.messageQueue = { unrelated2, pending }
  t.widget.profileOperation = { kind="snapshot", queue=q, messages={pending} }
  t:connect("Another Nitro")
  t:step(false)
  eq(q.currentMessage, unrelated1, "unrelated in-flight request preserved")
  eq(q.lastTimeCommandSent, 123, "unrelated retry timing preserved")
  eq(#q.messageQueue, 1, "owned pending request removed")
  eq(q.messageQueue[1], unrelated2, "unrelated pending request preserved")
  t.alerts.rxDeadVoiceLatched = true
  builds = t.builds
  t:settle(false)
  eq(t.opt.heliType, 2, "same-type aircraft stays Nitro")
  eq(t.alerts.rxDeadVoiceLatched, false, "same-type identity change resets session")
  eq(t.builds, builds, "same-type identity change also defers UI")

  -- Brief candidate changes restart confirmation; a clock rollback cannot
  -- accidentally satisfy the confirmation interval.
  t:connect("Candidate Electric"); t:step(false)
  t:connect("Candidate Nitro"); t:step(false)
  eq(t.auto.ready, false, "changed candidate restarts confirmation")
  t.now = t.now - 100
  t:step(false)
  eq(t.auto.ready, false, "clock rollback stays unresolved")
  t:settle(false)
  eq(t.auto.name, "Candidate Nitro", "only the stable candidate is accepted")

  for selected = 1, 3 do
    t.opts.HeliType = selected
    t.api.update(t.widget, t.opts)
    t:connect(selected == 2 and "RAW Electric" or "RAW Nitro")
    t:settle(true)
    eq(t.opt.heliType, selected, "manual choice overrides FC name")
    eq(t.opt.autoHeliType, false, "manual choice disables Auto")
  end
  t.opts.HeliType = 4
  t.api.update(t.widget, t.opts)
  eq(t.auto.ready, false, "re-enabling Auto requires fresh confirmation")
  t:settle(true)
  eq(t.opt.heliType, 2, "Auto works after manual OMP")
  eq(t.opts.HeliType, 4, "Auto remains persisted")

  local profiles = fixture(variant, "Shared Heli")
  profiles:connect("RAW Nitro"); profiles:settle(false)
  eq(#profiles.requests, 0, "Nitro queues no battery profile requests")
  profiles:connect("RAW 700")
  for _ = 1, 8 do profiles:step(false) end
  local commands = {}
  for _, message in ipairs(profiles.requests) do commands[message.command] = true end
  eq(commands[175], true, "Electric reads active battery profile")
  eq(commands[32], true, "Electric reads configured capacities")
  eq(commands[176], nil, "detection does not write profile")
  eq(commands[250], nil, "detection does not write EEPROM")
  profiles:connect("RAW Nitro"); profiles:step(false)
  eq(#profiles.env.rf2.mspQueue.messageQueue, 0, "old Electric requests actually removed")

  local noName = fixture(variant, "Misleading Nitro")
  noName:connect(" "); noName:settle(true)
  eq(noName.auto.ready, false, "blank FC name never enables mode-dependent actions")
  eq(noName.auto.name, nil, "transmitter name cannot substitute for missing FC identity")
  eq(noName.alerts.battAlertPrevPct, nil, "missing FC name leaves alerts paused")
  local counter = fixture(variant, "Shared Heli", 4, 1)
  counter.timerValue = 25
  counter.rssi = 100
  counter:settle(false)
  local tickCounter = upvalue(upvalue(counter.api.background, "serviceTelemetry"), "tickFlightCount")
  local cache = upvalue(tickCounter, "getFlightCache")()
  eq(cache["Shared Heli"], nil, "unidentified aircraft cannot increment generic CSV key")
  counter.timerValue = 0
  counter:connect("Aircraft A"); counter.name = "Shared Heli"
  counter:settle(false)
  counter.timerValue = 25; counter:step(false)
  eq(cache["Aircraft A"], 1, "KSE counter records first FC identity")
  counter:disconnect(); counter:step(false)
  counter.timerValue = 0
  counter:connect("Aircraft B"); counter.name = "Shared Heli"
  counter:settle(false)
  counter.timerValue = 25; counter:step(false)
  eq(cache["Aircraft B"], 1, "KSE counter records second same-type FC identity")
  eq(cache["Aircraft A"], 1, "first FC count remains independent")
  eq(cache["Shared Heli"], nil, "no count attributed to unchanged TX name")

  for _, size in ipairs({ {480,272}, {480,320} }) do
    local small = fixture(variant, "Shared Heli", 4, nil, size[1], size[2])
    small.rssi = 100; small:step(true)
    eq(small:hasText(variant == "KSE5" and "WAIT FC NAME" or "WAITING FOR FC NAME"),
       true, "compact waiting message")
    small:connect("Small Nitro"); small:settle(true)
    eq(small.opt.heliType, 2, "compact Nitro render")
    small:connect("Small Electric"); small:settle(true)
    eq(small.opt.heliType, 1, "compact Electric render")
  end
  print(variant .. ": combined Auto lifecycle passed")
end
print(assertions .. " assertions passed")
