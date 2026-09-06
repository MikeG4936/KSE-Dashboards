-- @module widget_owner WidgetOwner
--[[
  KSE5 - retained LVGL telemetry dashboard for EdgeTX color radios.

  Functional behavior is assembled from src/shared.
  The visual adapter intentionally retains KSE5's ring-card design while
  deriving its geometry from the current EdgeTX screen or widget zone.
]]

-- Shared with KSE4: scaled design measurements use an 800x480 reference.
-- Actual radio dimensions and widget zones still determine the rendered size.
local G = {
  referenceW=800, referenceH=480,
  screenW=tonumber(_G.LCD_W) or 800,
  screenH=tonumber(_G.LCD_H) or 480,
  originX=0, originY=0, w=800, h=480,
  scaleX=1, scaleY=1, scaleMin=1,
  compact=false, largeScreen=true,
}
G.name = "KSE5"
G.assetRoot = "/WIDGETS/KSE5"
local SMLSIZE      = rawget(_G, "SMLSIZE")      or SMLSIZE      or 0
local MIDSIZE      = rawget(_G, "MIDSIZE")      or MIDSIZE      or 0
local BOLD_FONT    = _G.BOLD or SMLSIZE
G.fontSmall, G.fontRingValue, G.fontTileValue = SMLSIZE, MIDSIZE, MIDSIZE
G.fontGovernorValue, G.fontTop, G.fontTimer = MIDSIZE, MIDSIZE, MIDSIZE
G.signalHeights = { 6, 10, 14, 18 }
local VALUE  = rawget(_G, "VALUE")  or 0
local BOOL   = rawget(_G, "BOOL")   or 2
local CHOICE = rawget(_G, "CHOICE") or 10
local STRING = rawget(_G, "STRING") or 3
local SOURCE = rawget(_G, "SOURCE") or _G.SOURCE or 1
-- EdgeTX exposes these flags through its read-only global lookup table. The
-- public Lua name for CENTERED is CENTER, so rawget("CENTERED") silently
-- returned nil and made every intended centered/right-aligned label align left.
local RIGHT = rawget(_G, "RIGHT") or _G.RIGHT or 0
local CENTERED = rawget(_G, "CENTER") or rawget(_G, "CENTERED")
                 or _G.CENTER or _G.CENTERED or 0
G.rounded = function(v)
  return math.floor(v + 0.5)
end
G.x = function(v)
  return G.rounded(v * G.scaleX)
end
G.y = function(v)
  return G.rounded(v * G.scaleY)
end
-- Fit a uniform detail (ring radius, inset, or border) within its reference
-- width and height. Separate extents preserve KSE5's established proportions
-- across aspect ratios after rebasing from 480x320 to 800x480. A single extent
-- retains the usual minimum-axis scaling used by KSE4.
G.min = function(w, h)
  return G.rounded(math.min(w * G.scaleX, (h or w) * G.scaleY))
end
G.positiveSize = function(v, fallback)
  v = tonumber(v)
  if not v or v < 1 then return fallback end
  return G.rounded(v)
end
G.bounds = function(zone, fullScreen)
  if fullScreen then return 0, 0, G.screenW, G.screenH end
  local w = G.positiveSize(zone and zone.w, G.screenW)
  local h = G.positiveSize(zone and zone.h, G.screenH)
  local x = G.rounded(tonumber(zone and zone.x) or 0)
  local y = G.rounded(tonumber(zone and zone.y) or 0)
  return x, y, w, h
end
G.signature = function(x, y, w, h)
  return table.concat({ x, y, w, h }, ":")
end
G.configure = function(x, y, w, h)
  G.originX, G.originY, G.w, G.h = x, y, w, h
  G.scaleX = w / G.referenceW
  G.scaleY = h / G.referenceH
  G.scaleMin = math.min(G.scaleX, G.scaleY)
  G.compact = w <= 520
  G.largeScreen = w >= 700 and h >= 420

  -- EdgeTX font constants are discrete selectors, not arithmetic style flags.
  -- Keep general values at MIDSIZE. On compact governor tiles, standalone
  -- BOLD is the useful step between SMLSIZE and MIDSIZE; it must not be added
  -- to another font selector. Fall back to SMLSIZE if firmware omits BOLD.
  G.fontSmall = SMLSIZE
  G.fontRingValue = MIDSIZE
  G.fontTileValue = MIDSIZE
  G.fontGovernorValue = G.compact and BOLD_FONT or MIDSIZE
  G.fontTop = MIDSIZE
  G.fontTimer = MIDSIZE
end
local C_BG, C_TOP, C_PANEL, C_PANEL_ALT, C_BORDER, C_TRACK
local C_TEXT, C_DIM, C_ACCENT, C_IMAGE_BG
local C_GREEN, C_YELLOW, C_RED, C_BLUE, C_CYAN, C_ORANGE

-- RotorFlight 2.3 exposes six battery-profile slots. MSP uses zero-based
-- indexes while the BAT# telemetry sensor and the user-facing UI use 1..6.
-- @include shared:enums.lua
local GOV_COLOR, GOV_FALLBACK = {}, {}

local function applyTheme(name)
  local rgb = lcd.RGB
  C_GREEN  = rgb(28, 232, 119)
  C_YELLOW = rgb(255, 196, 48)
  C_ORANGE = rgb(255, 112, 28)
  C_RED    = rgb(255, 64, 80)
  C_BLUE   = rgb(55, 136, 255)
  C_CYAN   = rgb(30, 220, 240)
  -- KSE4-inspired opaque palettes. Each entry retains KSE4's background,
  -- tile, border, muted-text, and accent colors; KSE5 derives its additional
  -- top-bar, alternate-panel, and ring-track layers from those five anchors.
  -- Only the selected palette is allocated, which keeps radio memory bounded.
  local p
  if name == "red" then
    p = {100,18,18, 130,28,28, 180,50,50, 240,165,165, 255,95,95}
  elseif name == "blue" then
    p = {4,20,54, 10,32,74, 28,72,124, 150,180,220, 80,165,255}
  elseif name == "pink" then
    p = {145,0,83, 184,0,105, 255,20,147, 255,196,225, 255,222,239}
  elseif name == "green" then
    p = {6,54,22, 12,74,34, 24,120,58, 150,215,175, 60,220,120}
  elseif name == "purple" then
    p = {34,12,60, 50,22,82, 92,46,140, 190,165,225, 175,110,245}
  elseif name == "reef" then
    p = {8,22,58, 8,46,50, 24,96,104, 150,190,218, 70,200,230}
  elseif name == "royal" then
    p = {40,16,66, 52,40,12, 112,88,28, 202,172,228, 180,120,248}
  elseif name == "ember" then
    p = {70,18,10, 92,52,8, 150,88,26, 235,175,150, 255,150,50}
  elseif name == "graphite" then
    p = {18,21,25, 34,39,46, 75,85,98, 165,175,188, 215,225,235}
  elseif name == "glacier" then
    p = {8,28,42, 18,52,68, 46,105,126, 155,203,218, 117,225,250}
  elseif name == "sunset" then
    p = {96,12,10, 160,48,8, 230,105,20, 255,191,145, 255,190,48}
  elseif name == "synthwave" then
    p = {22,10,55, 59,13,70, 147,35,126, 205,154,226, 71,229,255}
  elseif name == "gulf" then
    p = {10,48,65, 16,72,88, 204,102,36, 162,205,216, 255,139,59}
  elseif name == "voltage" then
    p = {9,19,10, 26,37,17, 83,117,31, 183,204,145, 185,255,50}
  elseif name == "titanium_ember" then
    p = {11,14,18, 41,49,58, 100,113,125, 174,184,193, 255,138,61}
  elseif name == "aurora" then
    p = {6,27,24, 23,27,59, 52,84,122, 159,185,200, 116,242,206}
  elseif name == "desert_night" then
    p = {26,21,12, 52,51,27, 118,101,59, 201,187,139, 245,196,81}
  end
  if p then
    C_BG        = rgb(p[1], p[2], p[3])
    C_TOP       = rgb(math.floor((p[1] * 2 + p[4]) / 3 + 0.5),
                      math.floor((p[2] * 2 + p[5]) / 3 + 0.5),
                      math.floor((p[3] * 2 + p[6]) / 3 + 0.5))
    C_PANEL     = rgb(p[4], p[5], p[6])
    C_PANEL_ALT = rgb(math.floor((p[4] * 2 + p[7]) / 3 + 0.5),
                      math.floor((p[5] * 2 + p[8]) / 3 + 0.5),
                      math.floor((p[6] * 2 + p[9]) / 3 + 0.5))
    C_BORDER    = rgb(p[7], p[8], p[9])
    C_TRACK     = rgb(math.floor((p[4] + p[7]) / 2 + 0.5),
                      math.floor((p[5] + p[8]) / 2 + 0.5),
                      math.floor((p[6] + p[9]) / 2 + 0.5))
    C_TEXT      = rgb(245, 245, 245)
    C_DIM       = rgb(p[10], p[11], p[12])
    C_ACCENT    = rgb(p[13], p[14], p[15])
    C_IMAGE_BG  = C_PANEL_ALT
  elseif name == "light" then
    C_BG        = rgb(223, 236, 247)
    C_TOP       = rgb(250, 253, 255)
    C_PANEL     = rgb(244, 250, 255)
    C_PANEL_ALT = rgb(231, 242, 251)
    C_BORDER    = rgb(145, 177, 202)
    C_TRACK     = rgb(195, 217, 234)
    C_TEXT      = rgb(8, 27, 43)
    C_DIM       = rgb(61, 88, 111)
    C_ACCENT    = rgb(0, 137, 224)
    C_IMAGE_BG  = C_PANEL_ALT
    C_GREEN     = rgb(0, 143, 76)
    C_YELLOW    = rgb(176, 112, 0)
    C_ORANGE    = rgb(224, 82, 0)
    C_RED       = rgb(211, 35, 56)
    C_BLUE      = rgb(0, 98, 218)
    C_CYAN      = C_ACCENT
  elseif name == "arctic" then
    C_BG        = rgb(2, 10, 21)
    C_TOP       = rgb(4, 19, 37)
    C_PANEL     = rgb(7, 29, 53)
    C_PANEL_ALT = rgb(9, 40, 70)
    C_BORDER    = rgb(24, 85, 128)
    C_TRACK     = rgb(14, 55, 88)
    C_TEXT      = rgb(239, 249, 255)
    C_DIM       = rgb(115, 172, 208)
    C_ACCENT    = rgb(26, 211, 255)
    C_IMAGE_BG  = C_PANEL_ALT
  elseif name == "violet" then
    C_BG        = rgb(11, 8, 19)
    C_TOP       = rgb(18, 13, 29)
    C_PANEL     = rgb(25, 18, 38)
    C_PANEL_ALT = rgb(33, 24, 49)
    C_BORDER    = rgb(73, 55, 96)
    C_TRACK     = rgb(53, 39, 67)
    C_TEXT      = rgb(247, 242, 255)
    C_DIM       = rgb(167, 152, 184)
    C_ACCENT    = rgb(181, 140, 255)
    C_IMAGE_BG  = C_PANEL_ALT
  elseif name == "orange" then
    C_BG        = rgb(18, 5, 0)
    C_TOP       = rgb(44, 12, 0)
    C_PANEL     = rgb(62, 18, 0)
    C_PANEL_ALT = rgb(86, 26, 0)
    C_BORDER    = rgb(190, 68, 0)
    C_TRACK     = rgb(126, 35, 0)
    C_TEXT      = rgb(255, 250, 238)
    C_DIM       = rgb(255, 176, 92)
    C_ACCENT    = rgb(255, 132, 0)
    C_IMAGE_BG  = C_PANEL_ALT
  else
    C_BG        = rgb(2, 2, 2)
    C_TOP       = rgb(5, 5, 5)
    C_PANEL     = rgb(10, 10, 10)
    C_PANEL_ALT = rgb(15, 15, 15)
    C_BORDER    = rgb(42, 42, 42)
    C_TRACK     = rgb(26, 26, 26)
    C_TEXT      = rgb(245, 245, 245)
    C_DIM       = rgb(150, 150, 150)
    C_ACCENT    = rgb(230, 230, 230)
    C_IMAGE_BG  = C_PANEL_ALT
  end
  GOV_COLOR.ACTIVE      = C_GREEN
  GOV_COLOR.IDLE        = C_YELLOW
  GOV_COLOR.SPOOLUP     = C_YELLOW
  GOV_COLOR.RECOVERY    = C_YELLOW
  GOV_COLOR.OFF         = C_RED
  GOV_COLOR["THR-OFF"] = C_RED
  GOV_COLOR["LOST-HS"] = C_RED
  GOV_COLOR.AUTOROT     = C_BLUE
  GOV_COLOR.BAILOUT     = C_BLUE
  GOV_COLOR.BYPASS      = C_BLUE
  GOV_FALLBACK          = C_DIM
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function round(v)
  if v >= 0 then return math.floor(v + 0.5) end
  return math.ceil(v - 0.5)
end
-- Shared, SD-card-wide flight history. Keeping one authoritative root file
-- lets other dashboards use the same per-model counters without migration or
-- competing widget-local copies.
-- @include shared:state.lua
-- @include shared:options.lua
-- @module count_storage Storage
-- @include shared:telemetry.lua
-- @include shared:alerts.lua
-- @include shared:counters.lua
-- @include shared:images.lua
local function buildLayout(zone, fullScreen)
  local x, y, w, h = G.bounds(zone, fullScreen)
  G.configure(x, y, w, h)
  local layout = {
    x=x, y=y, w=w, h=h,
    pad=math.max(3, G.min(25 / 3, 7.5)), gap=math.max(2, G.min(20 / 3, 6)),
    signature=G.signature(x, y, w, h),
  }

  layout.top = { x=x, y=y, w=w, h=math.max(28, G.y(51)) }
  layout.ringY = y + layout.top.h + layout.gap
  -- The short 480x272 target needs a fixed minimum for two discrete-font tile
  -- rows; taller screens scale the equivalent 800x480 design measurements.
  local compactBottomMin = G.compact and math.min(126, h - 118) or 0
  layout.bottomH = math.max(compactBottomMin, G.y(204),
                            math.floor(h * 0.425))
  layout.bottomY = y + h - layout.pad - layout.bottomH
  layout.ringH = math.max(88, layout.bottomY - layout.ringY - layout.gap)

  local right = x + w - layout.pad
  local contentW = w - layout.pad * 2
  local ringW = math.floor((contentW - layout.gap * 3) / 4)
  layout.rings = {}
  for i = 1, 4 do
    local cardX = x + layout.pad + (i - 1) * (ringW + layout.gap)
    layout.rings[i] = {
      x=cardX, y=layout.ringY,
      w=(i == 4) and (right - cardX) or ringW,
      h=layout.ringH,
    }
  end
  local firstRingW = layout.rings[1].w
  layout.ringRadius = math.max(math.max(24, G.min(140 / 3, 42)),
      math.min(math.max(28, G.min(220 / 3, 66)),
               math.floor(firstRingW / 2) - math.max(5, G.x(40 / 3)),
               math.floor((layout.ringH - math.max(26, G.y(45))) / 2)))
  layout.ringThickness = math.max(math.max(5, G.min(10, 9)),
                                  math.floor(layout.ringRadius * 0.20))
  -- Match StacyDashV3's vertically balanced ring placement: the gauge sits
  -- midway between its title baseline and footer instead of being top-biased.
  layout.ringCenterY = layout.ringY + math.floor((layout.ringH + 2) / 2)

  layout.modelX = x + layout.pad
  layout.modelY = layout.bottomY
  -- With Tail RPM and Pack Voltage hidden, split the lower dashboard evenly:
  -- a double-width model panel and a compact 2x2 telemetry grid.
  layout.modelW = math.floor((contentW - layout.gap) / 2)
  layout.modelH = layout.bottomH
  layout.modelFooterH = math.max(22, G.y(36))
  local imageInset = math.max(3, G.min(20 / 3, 6))
  layout.modelImageX = layout.modelX + imageInset
  layout.modelImageY = layout.modelY + imageInset
  layout.modelImageW = layout.modelW - imageInset * 2
  layout.modelImageH = layout.modelH - layout.modelFooterH - imageInset * 2

  local statsX = layout.modelX + layout.modelW + layout.gap
  local tileW = math.floor((right - statsX - layout.gap) / 2)
  local tileH = math.floor((layout.bottomH - layout.gap) / 2)
  layout.tiles = {}
  for i = 1, 4 do
    local col = (i - 1) % 2
    local row = math.floor((i - 1) / 2)
    local tileX = statsX + col * (tileW + layout.gap)
    layout.tiles[i] = {
      x=tileX,
      y=layout.bottomY + row * (tileH + layout.gap),
      w=(col == 1) and (right - tileX) or tileW,
      h=(row == 1) and (y + h - layout.pad
                         - (layout.bottomY + tileH + layout.gap)) or tileH,
    }
  end
  return layout
end

-- Retained LVGL UI -----------------------------------------------------------
local function rememberObject(wgt, object, properties)
  if not object then return nil end
  local state = { visible=true }
  for key, value in pairs(properties or {}) do state[key] = value end
  wgt.objectState[object] = state
  return object
end

local function setObject(wgt, object, properties)
  if not object then return end
  local state = wgt.objectState[object]
  if not state then
    state = { visible=true }
    wgt.objectState[object] = state
  end
  local changed = false
  for key, value in pairs(properties) do
    if state[key] ~= value then
      state[key] = value
      changed = true
    end
  end
  if changed then object:set(properties) end
end

local function setVisible(wgt, object, visible)
  if not object then return end
  local state = wgt.objectState[object]
  if not state then
    state = { visible=true }
    wgt.objectState[object] = state
  end
  visible = not not visible
  if state.visible == visible then return end
  state.visible = visible
  if visible then object:show() else object:hide() end
end

local function newLabel(wgt, x, y, w, text, font, color, align)
  local properties = {
    x=x, y=y, w=w or 0, h=0, text=text or "",
    font=font or 0, color=color or C_TEXT, align=align or 0,
  }
  return rememberObject(wgt, lvgl.label(properties), properties)
end

local function setLabel(wgt, object, text, color, align)
  local properties = { text=tostring(text or "") }
  if color ~= nil then properties.color = color end
  if align ~= nil then properties.align = align end
  setObject(wgt, object, properties)
end

local function newRect(wgt, x, y, w, h, color, filled, rounded, thickness)
  local properties = {
    x=x, y=y, w=w, h=h, color=color,
    filled=not not filled, rounded=rounded or 0, thickness=thickness or 1,
  }
  return rememberObject(wgt, lvgl.rectangle(properties), properties)
end

local function newPanel(wgt, x, y, w, h, fill, border, rounded)
  return {
    fill=newRect(wgt, x, y, w, h, fill, true, rounded or 4, 1),
    border=newRect(wgt, x, y, w, h, border, false, rounded or 4, 1),
  }
end

local function compactModelName(wgt, maxChars)
  local raw = getModelName()
  wgt.fitNames = wgt.fitNames or {}
  local cached = wgt.fitNames[maxChars]
  if cached and cached.raw == raw then return cached.text end
  local text = raw
  if #text > maxChars then text = string.sub(text, 1, maxChars - 2) .. ".." end
  wgt.fitNames[maxChars] = { raw=raw, text=text }
  return text
end

local function buildTopBar(wgt)
  local l, ui = wgt.layout, wgt.ui
  local t = l.top
  newRect(wgt, t.x, t.y, t.w, t.h, C_TOP, true, 0, 1)
  local lineInset = math.max(4, G.x(25 / 3))
  lvgl.hline({ x=t.x + lineInset, y=t.y + t.h - 1,
               w=t.w - lineInset * 2,
               h=1, color=C_BORDER })

  local txBodyW, txBodyH = math.max(11, G.x(65 / 3)), math.max(19, G.y(31.5))
  local txBodyX = t.x + t.w - l.pad - txBodyW
  local txBodyY = t.y + math.max(7, G.y(13.5))
  local centerY = G.rounded(t.y + t.h / 2)
  -- Both dashboards now express the signal geometry directly in the shared
  -- 800x480 reference, so both glyphs render at
  -- the same physical size and battery-relative position on every target.
  local sigX = txBodyX - G.x(14) - G.x(36)
  local timerW = math.max(90, G.x(500 / 3))
  local timerX = t.x + math.floor((t.w - timerW) / 2)
  local modelNameX = t.x + math.max(5, G.x(10))
  local modelNameW = math.max(90, timerX - modelNameX - math.max(5, G.x(10)))

  -- On EdgeTX color displays BOLD is a font size of its own, not a style bit.
  -- Combining it with SMLSIZE/MIDSIZE selects an unintended oversized font on
  -- the radio even when a desktop mock happens to look acceptable.
  ui.modelName = newLabel(wgt, modelNameX, t.y + math.max(1, G.y(3)),
                          modelNameW, "", G.fontTop, C_TEXT)
  ui.timer = newLabel(wgt, timerX, t.y + math.max(1, G.y(3)),
                      timerW, "", G.fontTimer, C_TEXT, CENTERED)

  local profileSignalGap = math.max(8, G.x(50 / 3))
  local profileMinW = #"Profile 6 / Rate 6" * 9
  local profileX = math.min(timerX + timerW - math.max(20, G.x(140 / 3)),
                            sigX - profileSignalGap - profileMinW)
  local profileY = math.floor(centerY - 11)
  if G.screenW == 480 and G.screenH == 320
     and G.w == 480 and G.h == 320 then profileY = profileY + 2 end
  ui.profileStatus = newLabel(
    wgt, profileX, profileY,
    math.max(1, sigX - profileSignalGap - profileX), "",
    SMLSIZE, C_TEXT, RIGHT)

  -- Match KSE4's ascending four-bar link-quality glyph immediately to the
  -- left of the vertical transmitter-battery indicator.
  ui.signal = {}
  for i, referenceH in ipairs(G.signalHeights) do
    local barH = math.max(1, G.y(referenceH))
    ui.signal[i] = newRect(wgt,
      sigX + (i - 1) * G.x(10),
      centerY + G.y(10) - barH,
      math.max(1, G.x(6)), barH, C_BORDER, true, 0, 0)
  end

  ui.txBody = newPanel(wgt, txBodyX, txBodyY, txBodyW, txBodyH,
                       C_PANEL_ALT, C_DIM, math.max(1, G.min(10 / 3, 3)))
  local terminalW = math.max(4, G.x(25 / 3))
  newRect(wgt, txBodyX + math.floor((txBodyW - terminalW) / 2),
          txBodyY - math.max(2, G.y(4.5)), terminalW,
          math.max(2, G.y(3)), C_DIM, true, 1, 1)
  local txInset = math.max(2, G.min(10 / 3, 3))
  ui.txFill = newRect(wgt, txBodyX + txInset,
                      txBodyY + txBodyH - txInset,
                      txBodyW - txInset * 2, 1, C_GREEN, true, 1, 1)
  ui.txBodyX, ui.txBodyY = txBodyX, txBodyY
  ui.txBodyW, ui.txBodyH = txBodyW, txBodyH
  ui.txInset = txInset
end

local RING_LABELS = { "BATTERY", "HEAD RPM", "CURRENT", "ESC TEMP" }
local RING_UNITS = { "%", "RPM", "AMPS", "\xC2\xB0C" }
local RING_STANDARD = {
  bottom=90, span=359, -- EdgeTX: 0 is 3 o'clock; 90 is 6 o'clock.
  rpmMin=500, rpmMax=2400,
  currentMin=0, currentMax=250,
  tempMin=32, tempMax=100,
}
local function buildRingCards(wgt)
  local l, ui = wgt.layout, wgt.ui
  ui.rings = {}
  for i = 1, 4 do
    local card = l.rings[i]
    local panel = newPanel(wgt, card.x, card.y, card.w, card.h,
                           C_PANEL, C_BORDER, math.max(2, G.min(20 / 3, 6)))
    local inset = math.max(2, G.x(10 / 3))
    local accent = newRect(wgt, card.x + inset, card.y + 1,
                           card.w - inset * 2, 1, C_DIM, true, 1, 1)
    -- Arcs are children of the card fill, so EdgeTX clips overdraw at the card
    -- boundary. Keep their geometry immutable: the radio can displace an arc
    -- when object:set() changes its angles. Dynamic property functions update
    -- only the rendered sweep/color while x, y, and radius remain untouched.
    local cx = math.floor(card.w / 2)
    local cy = l.ringCenterY - card.y
    local arcState = { endAngle=RING_STANDARD.bottom, color=C_DIM, opacity=0 }
    local primaryProperties = {
      x=cx, y=cy, radius=l.ringRadius,
      thickness=l.ringThickness,
      startAngle=RING_STANDARD.bottom,
      endAngle=function() return arcState.endAngle end,
      rounded=true,
      color=function() return arcState.color end,
      opacity=function() return arcState.opacity end,
      bgColor=C_TRACK, bgOpacity=255,
      bgStartAngle=0, bgEndAngle=360,
    }
    local primary = rememberObject(wgt, lvgl.arc(panel.fill, primaryProperties),
                                   primaryProperties)
    local ringLabel = i == 1 and OPT.simTelemetry
                      and "SIM \xC2\xB7 BATTERY" or RING_LABELS[i]
    local label = newLabel(wgt, card.x + inset,
                           card.y + math.max(1, G.y(3)),
                           card.w - inset * 2, ringLabel,
                           G.fontSmall, C_DIM, CENTERED)
    local valueOffset = G.largeScreen and math.max(17, G.y(19.5)) or 13
    local unitOffset = G.largeScreen and math.max(14, G.y(15)) or 12
    -- Keep value and unit locked together; lift both another 2 px so the
    -- complete text group sits optically centered inside the ring.
    local ringTextLift = G.largeScreen and 6 or 2
    local value = newLabel(wgt, card.x + inset,
                           l.ringCenterY - valueOffset - ringTextLift,
                           card.w - inset * 2, "--", G.fontRingValue,
                           C_TEXT, CENTERED)
    local unit = newLabel(wgt, card.x + inset,
                          l.ringCenterY + unitOffset - ringTextLift,
                          card.w - inset * 2, RING_UNITS[i],
                          G.fontSmall, C_DIM, CENTERED)
    local footer = newLabel(wgt, card.x + inset,
                            card.y + card.h - math.max(16, G.y(24)),
                            card.w - inset * 2, "", G.fontSmall,
                            C_DIM, CENTERED)
    ui.rings[i] = {
      accent=accent, primary=primary, arcState=arcState,
      label=label, value=value, unit=unit, footer=footer,
    }
  end
end

local TILE_LABELS = {
  "GOV MODE", "BEC OUTPUT", "CELL VOLT", "USED CAPACITY",
}
local function buildLowerDashboard(wgt)
  local l, ui = wgt.layout, wgt.ui
  newPanel(wgt, l.modelX, l.modelY, l.modelW, l.modelH,
           C_PANEL, C_BORDER, math.max(2, G.min(20 / 3, 6)))
  newRect(wgt, l.modelImageX, l.modelImageY, l.modelImageW,
          l.modelImageH, C_IMAGE_BG, true, math.max(2, G.min(5, 4.5)), 1)
  local imageProperties = {
    x=l.modelImageX, y=l.modelImageY, w=l.modelImageW, h=l.modelImageH,
    file=function() return resolveModelImagePath() or "" end,
    visible=function() return resolveModelImagePath() ~= nil end,
    fill=false,
  }
  ui.modelImage = rememberObject(wgt, lvgl.image(imageProperties), imageProperties)
  ui.noImage = newLabel(wgt, l.modelImageX, l.modelImageY
                        + math.floor(l.modelImageH / 2) - 8,
                        l.modelImageW, "NO IMAGE", G.fontSmall,
                        C_DIM, CENTERED)
  local imagePath = resolveModelImagePath()
  setVisible(wgt, ui.modelImage, imagePath ~= nil)
  setVisible(wgt, ui.noImage, imagePath == nil)
  local footerY = l.modelY + l.modelH - l.modelFooterH
  local footerInset = math.max(4, G.x(25 / 3))
  lvgl.hline({ x=l.modelX + footerInset, y=footerY,
               w=l.modelW - footerInset * 2,
               h=1, color=C_BORDER })
  ui.flightCount = newLabel(wgt, l.modelX + math.max(3, G.x(5)),
                            footerY + math.max(2, G.y(4.5)),
                            l.modelW - math.max(6, G.x(10)), "", G.fontSmall,
                            C_TEXT, CENTERED)

  ui.tiles = {}
  for i = 1, 4 do
    local tile = l.tiles[i]
    newPanel(wgt, tile.x, tile.y, tile.w, tile.h,
             C_PANEL_ALT, C_BORDER, math.max(2, G.min(20 / 3, 6)))
    local accentW = math.max(3, G.x(5))
    local accent = newRect(wgt, tile.x + 1, tile.y + math.max(2, G.y(3)),
                           accentW, tile.h - math.max(4, G.y(6)),
                           C_DIM, true, 1, 1)
    local textX = tile.x + math.max(8, G.x(15))
    local textW = tile.w - math.max(15, G.x(80 / 3))
    local label = newLabel(wgt, textX, tile.y + math.max(2, G.y(6)),
                           textW, TILE_LABELS[i], G.fontSmall, C_DIM)
    local valueFont = i == 1 and G.fontGovernorValue or G.fontTileValue
    local valueY = tile.y + math.max(19, G.y(31.5))
    local valueX, valueW = textX, textW
    local valueAlign = RIGHT
    local persistentValueAlign
    if i == 1 and G.compact then
      -- BOLD is a 20 px line on compact EdgeTX color targets. Center the
      -- governor value horizontally, then lower it 4 px from geometric center
      -- for optical balance inside the tile.
      valueX = tile.x + 4
      valueW = tile.w - 8
      valueY = tile.y + math.floor((tile.h - 20) / 2) + 4
      valueAlign = CENTERED
      persistentValueAlign = CENTERED
    end
    local value = newLabel(wgt, valueX, valueY,
                           valueW, "--", valueFont, C_TEXT, valueAlign)
    local footer = newLabel(wgt, textX,
                            tile.y + tile.h - math.max(16, G.y(25.5)),
                            textW, "", G.fontSmall, C_DIM, RIGHT)
    ui.tiles[i] = {
      accent=accent, label=label, value=value, footer=footer,
      valueAlign=persistentValueAlign,
    }
  end
end

local function buildProfileEntryPrompt(wgt)
  local l, ui = wgt.layout, wgt.ui
  local promptW = math.min(G.largeScreen and 360 or 250,
                           l.w - math.max(24, G.x(40)))
  local promptH = G.largeScreen and 64 or 56
  local titleOffset = G.largeScreen and 7 or 5
  local detailOffset = G.largeScreen and 39 or 34
  local x = l.x + math.floor((l.w - promptW) / 2)
  local y = l.y + math.floor((l.h - promptH) / 2)
  local compactW = promptW
  local compactH = promptH
  local compactX = l.x + math.floor((l.w - compactW) / 2)
  local compactY = l.y + math.floor((l.h - compactH) / 2)
  local prompt = {
    fill=newRect(wgt, x, y, promptW, promptH, C_PANEL_ALT, true,
                 math.max(3, G.min(10, 9)), 1),
    border=newRect(wgt, x, y, promptW, promptH, C_BORDER, false,
                   math.max(3, G.min(10, 9)), 2),
    accent=newRect(wgt, x + 2, y + 2, math.max(4, G.x(25 / 3)), promptH - 4,
                   C_GREEN, true, math.max(1, G.min(10 / 3, 3)), 1),
    title=newLabel(wgt, x + 10, y + titleOffset,
                   promptW - 20, "", G.fontSmall, C_TEXT, CENTERED),
    detail=newLabel(wgt, x + 10, y + detailOffset,
                    promptW - 20, "", G.fontSmall, C_DIM, CENTERED),
    full={ x=x, y=y, w=promptW, h=promptH,
           titleX=x + 10, titleY=y + titleOffset, titleW=promptW - 20,
           detailX=x + 10, detailY=y + detailOffset, detailW=promptW - 20 },
    compact={ x=compactX, y=compactY, w=compactW, h=compactH,
              titleX=compactX + 10, titleY=compactY + titleOffset,
              titleW=compactW - 20,
              detailX=compactX + 10, detailY=compactY + detailOffset,
              detailW=compactW - 20 },
  }
  prompt.objects = {
    prompt.fill, prompt.border, prompt.accent, prompt.title, prompt.detail,
  }
  ui.profilePrompt = prompt
  for _, object in ipairs(prompt.objects) do setVisible(wgt, object, false) end
end


local function batteryColor(percent)
  local p = tonumber(percent) or 0
  if p >= 50 then return C_GREEN end
  if p >= 20 then return C_YELLOW end
  return C_RED
end

local function txBatteryColor(percent)
  local p = math.floor((tonumber(percent) or 0) + 0.5)
  if p >= 51 then return C_GREEN end
  if p >= 31 then return C_YELLOW end
  return C_RED
end

local function becValueColor(volts)
  local v = tonumber(volts)
  if not v then return C_DIM end
  if v < 4.8 then return C_RED end
  if v < 5.1 then return C_YELLOW end
  return C_TEXT
end

local function formatTimer(seconds)
  local value = math.abs(tonumber(seconds) or 0)
  local minutes = math.floor(value / 60)
  local secs = math.floor(value - minutes * 60)
  return string.format("%d:%02d", minutes, secs)
end

local function updateTopBar(wgt)
  local ui = wgt.ui
  local maxModelChars = G.largeScreen and 28 or 16
  if OPT.simTelemetry then maxModelChars = G.largeScreen and 22 or 10 end
  local modelName = compactModelName(wgt, maxModelChars)
  if OPT.simTelemetry then modelName = "SIM \xC2\xB7 " .. modelName end
  setLabel(wgt, ui.modelName, modelName, C_TEXT)
  setLabel(wgt, ui.timer, formatTimer(getTimer1Secs()), C_TEXT)

  local rq = sensors.getRqly()
  local bars = rq >= 80 and 4 or rq >= 60 and 3
               or rq >= 40 and 2 or rq >= 20 and 1 or 0
  local signalColor = bars >= 3 and C_GREEN
                      or bars == 2 and C_YELLOW or C_RED
  for i, bar in ipairs(ui.signal or {}) do
    setObject(wgt, bar, { color=i <= bars and signalColor or C_BORDER })
  end

  local pidProfile, rateProfile, profilesReady = sensors.profilePair()
  setLabel(wgt, ui.profileStatus,
    profilesReady and string.format("Profile %d / Rate %d",
      pidProfile, rateProfile) or "", C_TEXT)

  local txPct = sensors.txPctFromVolts(sensors.getTxVolt(), txIsLiIon)
  if txPct then
    local innerH = ui.txBodyH - ui.txInset * 2
    local fillH = math.max(1, math.floor(innerH * clamp(txPct, 0, 100) / 100))
    setObject(wgt, ui.txFill, {
      y=ui.txBodyY + ui.txBodyH - ui.txInset - fillH,
      w=ui.txBodyW - ui.txInset * 2,
      h=fillH, color=txBatteryColor(txPct),
    })
    setVisible(wgt, ui.txFill, true)
  else
    setVisible(wgt, ui.txFill, false)
  end
end

local function updateRing(wgt, index, value, unit, footer, progress, color,
                          valid, footerColor, invalidMessage)
  local ring = wgt.ui.rings[index]
  local p = valid and clamp(tonumber(progress) or 0, 0, 1) or 0
  local activeColor = valid and (color or C_DIM) or C_DIM
  local sweep = round(p * RING_STANDARD.span)
  setObject(wgt, ring.accent, { color=activeColor })
  -- EdgeTX evaluates these functions from the retained arc without a set()
  -- call, preventing telemetry changes from disturbing the arc geometry.
  ring.arcState.endAngle = (RING_STANDARD.bottom + sweep) % 360
  ring.arcState.color = activeColor
  ring.arcState.opacity = (valid and sweep > 0) and 255 or 0
  local missingText = invalidMessage
                      or (A.linkAvailable and "NO SENSOR" or "")
  setLabel(wgt, ring.value, valid and value or "--", valid and C_TEXT or C_DIM)
  setLabel(wgt, ring.unit, unit, C_DIM)
  setLabel(wgt, ring.footer, valid and footer or missingText,
           valid and (footerColor or C_DIM) or C_DIM)
end

local function batteryFooter()
  if not OPT.simTelemetry and A.motorConfigError then
    return G.compact and "SET MOTOR SW" or "SET MOTOR SWITCH"
  end
  if OPT.heliType == HELI_NITRO then
    if not OPT.rxPackValid then return "INVALID RX RANGE" end
    return D.rxVoltage and string.format("RX %.2fV", D.rxVoltage) or "NO TELEMETRY"
  end
  if OPT.heliType == HELI_OMPHOBBY and sensors.getCellCount() == 0 then
    return "ADD M1/M2 NAME"
  end
  local parts = {}
  local profile = sensors.getBattProfile()
  if OPT.heliType == HELI_ELECTRIC and profile and profile > 0 then
    parts[#parts+1] = "P" .. tostring(math.floor(profile))
  end
  if D.cellCountValid then parts[#parts+1] = tostring(D.cellsResolved) .. "S" end
  if D.packVoltageValid then parts[#parts+1] = string.format("%.1fV", D.voltage) end
  return #parts > 0 and table.concat(parts, " ") or "SMART FUEL"
end

local function batteryInvalidMessage()
  if OPT.autoHeliType and not AUTO_HELI.ready then
    if G.compact then
      if AUTO_HELI.status == "AUTO DISCONNECTED" then return "DISCONNECTED" end
      if AUTO_HELI.status == "CONFIRMING FC NAME" then return "CONFIRM NAME" end
      return "WAIT FC NAME"
    end
    return AUTO_HELI.status or "WAITING FOR FC NAME"
  end
  if not OPT.simTelemetry and A.motorConfigError then
    return G.compact and "SET MOTOR SW" or "SET MOTOR SWITCH"
  end
  if OPT.heliType == HELI_NITRO and not OPT.rxPackValid then
    return "CHECK RX RANGE"
  end
  if OPT.heliType == HELI_OMPHOBBY and sensors.getCellCount() == 0 then
    return "ADD M1/M2 NAME"
  end
  return A.linkAvailable and "NO BATTERY DATA" or ""
end

local function updateRings(wgt)
  local batteryValid, batteryPct
  if OPT.heliType == HELI_NITRO then
    batteryValid = OPT.rxPackValid and D.rxVoltage ~= nil and D.rxVoltage > 0
    batteryPct = D.rxPercent or 0
  else
    batteryValid = D.hasBattData
    batteryPct = A.displayPercentInit and A.displayPercent or D.adjustedPercent
  end
  if OPT.autoHeliType and not AUTO_HELI.ready then batteryValid = false end
  updateRing(wgt, 1, tostring(math.floor(batteryPct or 0)), "%",
    batteryFooter(), (batteryPct or 0) / 100,
    batteryColor(batteryPct), batteryValid, C_DIM,
    batteryInvalidMessage())

  local rpm = sensors.getHeadspeed()
  updateRing(wgt, 2, tostring(math.floor(rpm or 0)), "RPM",
    string.format("MAX %d", math.floor(statRpmMax())),
    ((rpm or 0) - RING_STANDARD.rpmMin)
      / (RING_STANDARD.rpmMax - RING_STANDARD.rpmMin),
    C_ACCENT, D.rpmValid, C_YELLOW)

  local curr = sensors.getCurr()
  local currentValid = OPT.heliType ~= HELI_NITRO and D.currentValid
  updateRing(wgt, 3, tostring(math.ceil(curr or 0)), "AMPS",
    string.format("MAX %dA", math.ceil(statCurrMax())),
    ((curr or 0) - RING_STANDARD.currentMin)
      / (RING_STANDARD.currentMax - RING_STANDARD.currentMin),
    C_BLUE, currentValid, C_YELLOW,
    OPT.heliType == HELI_NITRO and "NOT USED" or nil)

  local temp = sensors.getTemp()
  local tempValid = OPT.heliType ~= HELI_NITRO and D.tempValid
  updateRing(wgt, 4, tostring(math.floor(temp or 0)), "\xC2\xB0C",
    string.format("MAX %d\xC2\xB0C", math.floor(statTempMax())),
    ((temp or 0) - RING_STANDARD.tempMin)
      / (RING_STANDARD.tempMax - RING_STANDARD.tempMin),
    C_ORANGE, tempValid, C_YELLOW,
    OPT.heliType == HELI_NITRO and "NOT USED" or nil)
end

local function updateTile(wgt, index, value, footer, accent, valid,
                          valueColor, footerColor, align)
  local tile = wgt.ui.tiles[index]
  setObject(wgt, tile.accent, { color=valid and accent or C_DIM })
  setLabel(wgt, tile.value, valid and value or "--",
           valid and (valueColor or C_TEXT) or C_DIM,
           align or tile.valueAlign or (valid and RIGHT or CENTERED))
  setLabel(wgt, tile.footer, valid and footer or "", footerColor or C_DIM)
end

local function updateLowerDashboard(wgt)
  local ui = wgt.ui
  local imagePath = resolveModelImagePath()
  setVisible(wgt, ui.modelImage, imagePath ~= nil)
  setVisible(wgt, ui.noImage, imagePath == nil)
  local flightCount = getFlightCount()
  local flightText
  local flightColor = C_TEXT
  if OPT.flightCounter == FC.ROTORFLIGHT then
    if flightCount ~= nil then
      flightText = string.format("%d Flights", flightCount)
      if FC.stale then flightColor = C_YELLOW end
    else
      flightText = FC.status or "WAITING"
      flightColor = sensors.flightStatusPending() and C_YELLOW or C_RED
    end
  else
    flightText = flightCount ~= nil and string.format("%d Flights", flightCount)
                 or "-- Flights"
    if A.flightSaveError then flightText = flightText .. "  FILE ERROR" end
    if A.flightSaveError then flightColor = C_RED end
  end
  if OPT.flightCounter == FC.ROTORFLIGHT and flightStore.dirty
     and flightStore.error then
    flightText = flightText .. " - KSE FILE ERROR"
    flightColor = C_RED
  end
  if wgt.profileConnectedForDisplay then
    flightText = flightText .. " - Connected"
  end
  setLabel(wgt, ui.flightCount, flightText,
           flightColor)

  local govState = sensors.getGovState()
  local govValid = OPT.heliType ~= HELI_OMPHOBBY and D.govValid
  updateTile(wgt, 1, govState, "",
    GOV_COLOR[govState] or GOV_FALLBACK, govValid,
    GOV_COLOR[govState] or GOV_FALLBACK)

  local bec = sensors.getBec()
  local becValid = OPT.heliType ~= HELI_OMPHOBBY and D.becValid
  local becFooter = statBecMin() and string.format("LOW %.1fV", statBecMin()) or ""
  setLabel(wgt, ui.tiles[2].label,
           OPT.heliType == HELI_NITRO and "BATT OUTPUT" or "BEC OUTPUT", C_DIM)
  updateTile(wgt, 2, string.format("%.1fV", bec or 0), becFooter,
    becValueColor(bec), becValid, becValueColor(bec))

  local cell, cellMin, cellValid
  if OPT.heliType == HELI_NITRO then
    cell = D.rxCellVoltage
    cellMin = D.minRxVoltage and D.minRxVoltage / 2 or nil
    cellValid = cell ~= nil and cell > 0
  else
    cell = sensors.getCellVoltage()
    cellMin = statCellMin()
    cellValid = D.cellVoltageValid
  end
  local cellColor = C_TEXT
  if OPT.heliType ~= HELI_NITRO and cellMin
     and cellMin <= SAFETY.cellRedThreshold then cellColor = C_RED end
  updateTile(wgt, 3, string.format("%.2fV", cell or 0),
    cellMin and string.format("LOW %.2fV", cellMin) or "",
    cellColor, cellValid, cellColor)

  updateTile(wgt, 4, tostring(math.floor(D.capacity or 0)), "mAh",
    C_ACCENT, D.capacityValid)
end

local function updateUiState(wgt)
  if not wgt.uiBuilt then return end
  updateTopBar(wgt)
  updateRings(wgt)
  updateLowerDashboard(wgt)
end

-- RotorFlight 2.3 battery-profile picker ------------------------------------
-- RF Tool owns the telemetry transport and publishes its connection state and
-- MSP queue for other EdgeTX widgets. KSE5 deliberately uses that API as
-- its sole profile transport so it never competes for telemetry frames.
-- @include shared:rf.lua
-- @include shared:auto_heli.lua
local function buildUi(wgt)
  if not lvgl then wgt.uiBuilt = false; return end
  lvgl.clear()
  wgt.profileDialog = nil
  wgt.ui = {}
  wgt.objectState = {}
  newRect(wgt, wgt.layout.x, wgt.layout.y, wgt.layout.w,
          wgt.layout.h, C_BG, true, 0, 1)
  buildTopBar(wgt)
  buildRingCards(wgt)
  buildLowerDashboard(wgt)
  if OPT.heliType ~= HELI_OMPHOBBY then
    local bannerY = wgt.layout.top.y + wgt.layout.top.h
    local bannerH = math.max(20, G.y(33))
    local bannerInset = math.max(5, G.x(25 / 3))
    local armingBanner = {
      fill=newRect(wgt, wgt.layout.x + bannerInset, bannerY,
                   wgt.layout.w - bannerInset * 2, bannerH, C_RED, true,
                   math.max(2, G.min(5, 4.5)), 1),
      border=newRect(wgt, wgt.layout.x + bannerInset, bannerY,
                     wgt.layout.w - bannerInset * 2, bannerH,
                     C_YELLOW, false, math.max(2, G.min(5, 4.5)), 1),
      label=newLabel(wgt, wgt.layout.x + bannerInset * 2,
                     bannerY + math.max(3, G.y(6)),
                     wgt.layout.w - bannerInset * 4, "", G.fontSmall,
                     C_TEXT, CENTERED),
    }
    armingBanner.objects = {
      armingBanner.fill, armingBanner.border, armingBanner.label,
    }
    wgt.ui.armingBanner = armingBanner
    for _, object in ipairs(armingBanner.objects) do
      setVisible(wgt, object, false)
    end
  end
  buildProfileEntryPrompt(wgt)
  wgt.uiBuilt = true
  updateUiState(wgt)
end

local function ensureLayout(wgt, fullScreen)
  local x, y, w, h = G.bounds(wgt.zone, fullScreen)
  local signature = G.signature(x, y, w, h)
  if wgt.layoutSignature == signature then return false end
  wgt.layout = buildLayout(wgt.zone, fullScreen)
  wgt.layoutSignature = signature
  buildUi(wgt)
  return true
end

G.prepareWidget = function(widget)
  widget.layout = buildLayout(widget.zone, false)
  widget.layoutSignature = widget.layout.signature
  widget.uiBuilt = false
end
G.pickerStyle = function()
  return {font=G.fontSmall, radius=math.max(3, G.min(10,9)), color=C_PANEL_ALT}
end
G.preferNativePicker = false

-- @include shared:lifecycle.lua
local options = {
  { "Theme",     CHOICE, 1, {
      "Dark", "Light", "Arctic Blue", "Midnight Violet", "Orange",
      "Red", "Blue", "Pink", "Green", "Purple", "Reef", "Royal",
      "Ember", "Graphite", "Glacier", "Sunset", "Synthwave", "Gulf",
      "Voltage", "Titanium Ember", "Aurora", "Desert Night",
    } },
  { "TxBatt",    CHOICE, 1, { "LiPo", "Li-Ion" } },
  { "MinFlight", VALUE, TOPBAR_MIN_DUR_DEFAULT, -30, 120 },
  { "HeliType",  CHOICE, 1, { "Electric", "Nitro", "OMPHOBBY", "Auto" } },
  { "BattRsv",   VALUE, 20, 0, 50 },
  { "BattVoice", BOOL, 0 },
  { "RxPackMin", STRING, "6.60" },
  { "RxPackMax", STRING, "8.40" },
  { "MotorSw",   SOURCE, (function()
      local info = type(getFieldInfo) == "function" and getFieldInfo("SG") or nil
      return type(info) == "table" and info.id or 0
    end)() },
  { "CountSrc",  CHOICE, 2,
    { "KSE Counter", "RotorFlight" } },
}

local OPTION_LABELS = {
  TxBatt="TX Battery",
  MinFlight="KSE Counter Min (sec)",
  HeliType="Heli Type",
  BattRsv="Battery Reserve %",
  BattVoice="Battery Voice",
  RxPackMin="Rx Pack Minimum",
  RxPackMax="Rx Pack Maximum",
  MotorSw="Motor Switch",
  CountSrc="Flight Counter",
}

local function translate(name, language)
  return OPTION_LABELS[name] or name
end

return {
  name="KSE5",
  options=options,
  create=create,
  update=update,
  background=background,
  refresh=refresh,
  translate=translate,
  useLvgl=true,
}
