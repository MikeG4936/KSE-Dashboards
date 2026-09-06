-- One active KSE widget across both variants. Lease time uses EdgeTX 10ms ticks.
local Owner = { leaseTicks=500 }
local registry = _G.__KSE_WIDGET_OWNER_V1
if type(registry) ~= "table" then
  registry = {epoch=0, proxies=setmetatable({}, {__mode="k"})}
  _G.__KSE_WIDGET_OWNER_V1 = registry
end

function Owner.current(widget)
  return widget ~= nil and registry.widget == widget
     and widget.kseOwnerEpoch == registry.epoch
end

function Owner.claim(widget, mayTakeOver)
  local now = (getTime and getTime()) or 0
  if Owner.current(widget) then registry.seen=now; return true end
  if registry.widget and not mayTakeOver then return false end
  if registry.widget and now >= (registry.seen or now)
     and now - (registry.seen or now) < Owner.leaseTicks then return false end
  local previous = registry.widget
  if previous and type(previous.kseRevoke) == "function" then previous.kseRevoke() end
  registry.epoch = registry.epoch + 1
  registry.widget, registry.seen = widget, now
  widget.kseOwnerEpoch = registry.epoch
  return true
end

function Owner.sharedStore(fallback)
  registry.store = registry.store or fallback
  return registry.store
end

function Owner.host(host, core)
  if host then registry.host, registry.core = host, core end
  if registry.core ~= _G.rf2
     or (registry.core and registry.core.widget and registry.core.widget ~= registry.host) then
    registry.host, registry.core = nil, nil
  end
  return registry.host, registry.core
end

function Owner.register(provider)
  if registry.proxies[provider] then return true end
  local proxy = {onStateChanged=function(_, state)
    local widget = registry.widget
    if provider == _G.rf2 and Owner.current(widget) then widget.profileRfState = state end
  end}
  local ok = pcall(provider.registerWidget, proxy)
  if ok then registry.proxies[provider] = proxy end
  return ok
end

function Owner.blocked(widget)
  if widget.kseBlockedDrawn or not lvgl then return end
  lvgl.clear()
  lvgl.label({x=8,y=8,w=math.max(1,((widget.zone or {}).w or LCD_W or 480)-16),
    text="Another KSE dashboard is active.\nRemove it, then reopen this screen.",
    font=_G.SMLSIZE or 0})
  widget.kseBlockedDrawn = true
end

return Owner
