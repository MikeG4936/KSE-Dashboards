-- @module widget_owner WidgetOwner
local G = {
  referenceW=800, referenceH=480,
  screenW=tonumber(LCD_W) or 800, screenH=tonumber(LCD_H) or 480,
  originX=0, originY=0, scaleX=1, scaleY=1, scaleMin=1,
  compact=false, compactJumboHero=false, largeScreen=false,
  screen480x320=false, screen480x272=false, screen800x480=false,
}
G.name = "KSE4"
G.assetRoot = "/WIDGETS/KSE4"
local SMLSIZE      = rawget(_G, "SMLSIZE")      or SMLSIZE      or 0
local MIDSIZE      = rawget(_G, "MIDSIZE")      or MIDSIZE      or 0
local DBLSIZE      = rawget(_G, "DBLSIZE")      or DBLSIZE      or 0
local XXLSIZE      = rawget(_G, "XXLSIZE")      or XXLSIZE      or DBLSIZE
G.fontSmall, G.fontValue, G.fontHero, G.fontTimer = SMLSIZE, MIDSIZE,
                                                     DBLSIZE, MIDSIZE
G.fontTop, G.fontGovernor, G.fontBattery = MIDSIZE, DBLSIZE, MIDSIZE
G.fontSecondaryLabel, G.fontSecondaryValue = SMLSIZE, SMLSIZE
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
G.min = function(v)
  return G.rounded(v * G.scaleMin)
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
  G.originX, G.originY = x, y
  G.w, G.h = w, h
  G.scaleX = G.w / G.referenceW
  G.scaleY = G.h / G.referenceH
  G.scaleMin = math.min(G.scaleX, G.scaleY)
  -- TX15-class screens are 480x320, while TX16S MKII is 480x272. Both need a
  -- compact typography/layout pass because EdgeTX bitmap fonts do not scale
  -- continuously with the panel geometry. TX16S MK3 remains on the 800x480
  -- reference presentation.
  G.compact = G.w <= 520
  G.compactJumboHero = G.compact and G.w >= 460 and G.h >= 260
  G.largeScreen = G.w >= 700 and G.h >= 420
  G.screen480x320 = G.screenW == 480 and G.screenH == 320
                      and G.w == 480 and G.h == 320
  G.screen480x272 = G.screenW == 480 and G.screenH == 272
                      and G.w == 480 and G.h == 272
  G.screen800x480 = G.screenW == 800 and G.screenH == 480
                      and G.w == 800 and G.h == 480

  -- Font constants select discrete EdgeTX fonts; they are not additive style
  -- flags. In particular, combining BOLD with SMLSIZE/MIDSIZE can select an
  -- unintended oversized font and make retained LVGL labels wrap.
  G.fontSmall = SMLSIZE
  G.fontValue = G.screen800x480 and DBLSIZE
                or (G.scaleMin < 0.50 and SMLSIZE or MIDSIZE)
  G.fontHero = (G.largeScreen or G.compactJumboHero) and XXLSIZE
               or (G.scaleMin < 0.50 and SMLSIZE
               or ((not G.compact or (G.w >= 460 and G.h >= 260))
                   and DBLSIZE or MIDSIZE))
  G.fontTimer = G.scaleMin < 0.50 and SMLSIZE or MIDSIZE
  G.fontTop = G.scaleMin < 0.50 and SMLSIZE or MIDSIZE
  G.fontGovernor = G.scaleMin < 0.50 and SMLSIZE
                     or (G.compact and MIDSIZE or DBLSIZE)
  G.fontBattery = G.scaleMin < 0.50 and SMLSIZE or MIDSIZE
  G.fontSecondaryLabel = G.fontSmall
  G.fontSecondaryValue = G.largeScreen and MIDSIZE or G.fontSmall

  G.layout = {
    top  = { x=x + G.x(10), y=y + G.y(8), h=math.max(1, G.y(36)) },
    pic  = { x=x + G.x(10),  y=y + G.y(56),
             w=math.max(1, G.x(280)), h=math.max(1, G.y(180)),
             r=math.max(0, G.min(7)) },
    gov  = { x=x + G.x(10),  y=y + G.y(246),
             w=math.max(1, G.x(280)), h=math.max(1, G.y(108)),
             r=math.max(0, G.min(7)) },
    hero = { x=x + G.x(300), y=y + G.y(56),
             w=math.max(1, G.x(490)), h=math.max(1, G.y(140)),
             r=math.max(0, G.min(7)) },
    tiles= { x=x + G.x(300), y=y + G.y(206),
             w=math.max(1, G.x(490)), h=math.max(1, G.y(148)),
             r=math.max(0, G.min(7)), gap=math.max(1, G.x(8)) },
    bot  = { x=x + G.x(10), w=math.max(1, G.x(780)),
             h=math.max(1, G.y(100)), padBot=math.max(0, G.y(14)),
             r=math.max(0, G.min(7)) },
  }
  G.layout.bot.y = y + G.h - G.layout.bot.padBot - G.layout.bot.h
end
local C_BG, C_TEXT, C_DIM, C_LINE, C_TILE
local C_GREEN_BG, C_GREEN_BR
local C_YELLOW_BG, C_YELLOW_BR
local C_RED_BG,    C_RED_BR
local C_BLUE_BG,   C_BLUE_BR
local C_GREEN, C_YELLOW, C_RED, C_BLUE
local DEFAULT_ACCENT, C_ACCENT
local C_BLACK
-- RotorFlight 2.3 exposes six battery-profile slots. MSP uses zero-based
-- indexes while the BAT# telemetry sensor and the user-facing UI use 1..6.
-- @include shared:enums.lua
local GOV_LABELS = { AUTOROT="AUTO" }
local GOV_COLOR = {}
local GOV_FALLBACK = {}
local themeAccent = nil
-- Single-color themes: solid bg + tiles a lighter shade of the
-- SAME hue (the original monochromatic look). Paired and specialty themes use
-- contrasting surfaces/accents. All keep text + status colors legible.
-- CHOICE values are 1-based. (bg = page background, tile = panel.)
local COLOR_THEMES = {
  orange = { bg={ 92, 42,  2}, tile={120, 60, 10}, line={160, 86, 24}, dim={230,178,120}, accent={255,155, 35} },
  red    = { bg={100, 18, 18}, tile={130, 28, 28}, line={180, 50, 50}, dim={240,165,165}, accent={255, 95, 95} },
  blue   = { bg={  4, 20, 54}, tile={ 10, 32, 74}, line={ 28, 72,124}, dim={150,180,220}, accent={ 80,165,255} },
  pink   = { bg={145,  0, 83}, tile={184,  0,105}, line={255, 20,147}, dim={255,196,225}, accent={255,222,239} },
  green  = { bg={  6, 54, 22}, tile={ 12, 74, 34}, line={ 24,120, 58}, dim={150,215,175}, accent={ 60,220,120} },
  purple = { bg={ 34, 12, 60}, tile={ 50, 22, 82}, line={ 92, 46,140}, dim={190,165,225}, accent={175,110,245} },
  reef   = { bg={  8, 22, 58}, tile={  8, 46, 50}, line={ 24, 96,104}, dim={150,190,218}, accent={ 70,200,230} },
  royal  = { bg={ 40, 16, 66}, tile={ 52, 40, 12}, line={112, 88, 28}, dim={202,172,228}, accent={180,120,248} },
  ember  = { bg={ 70, 18, 10}, tile={ 92, 52,  8}, line={150, 88, 26}, dim={235,175,150}, accent={255,150, 50} },
  graphite = { bg={ 18, 21, 25}, tile={ 34, 39, 46}, line={ 75, 85, 98}, dim={165,175,188}, accent={215,225,235} },
  glacier  = { bg={  8, 28, 42}, tile={ 18, 52, 68}, line={ 46,105,126}, dim={155,203,218}, accent={117,225,250} },
  sunset   = { bg={ 96, 12, 10}, tile={160, 48,  8}, line={230,105, 20}, dim={255,191,145}, accent={255,190, 48} },
  synthwave= { bg={ 22, 10, 55}, tile={ 59, 13, 70}, line={147, 35,126}, dim={205,154,226}, accent={ 71,229,255} },
  gulf     = { bg={ 10, 48, 65}, tile={ 16, 72, 88}, line={204,102, 36}, dim={162,205,216}, accent={255,139, 59} },
  voltage  = { bg={  9, 19, 10}, tile={ 26, 37, 17}, line={ 83,117, 31}, dim={183,204,145}, accent={185,255, 50} },
  titanium_ember = { bg={ 11, 14, 18}, tile={ 41, 49, 58}, line={100,113,125}, dim={174,184,193}, accent={255,138, 61} },
  aurora   = { bg={  6, 27, 24}, tile={ 23, 27, 59}, line={ 52, 84,122}, dim={159,185,200}, accent={116,242,206} },
  desert_night = { bg={ 26, 21, 12}, tile={ 52, 51, 27}, line={118,101, 59}, dim={201,187,139}, accent={245,196, 81} },
}
local THEME_NAMES = {
  [2] = "light",  [4] = "orange", [5] = "red",      [6] = "blue",
  [7] = "pink",   [8] = "green",  [9] = "purple",   [10] = "reef",
  [11]= "royal",  [12]= "ember",  [13]= "graphite", [14] = "glacier",
  [15]= "sunset", [16]= "synthwave", [17]= "gulf",  [18] = "voltage",
  [19]= "light",
  [20]= "titanium_ember", [21]= "aurora", [22]= "desert_night",
}
local function applyTheme(name)
  local rgb = lcd.RGB
  local ct = COLOR_THEMES[name]
  themeAccent = nil
  if not C_GREEN then
    C_GREEN        = rgb( 34, 197,  94)
    C_YELLOW       = rgb(240, 180,  41)
    C_RED          = rgb(239,  68,  68)
    C_BLUE         = rgb( 50, 130, 235)
    DEFAULT_ACCENT = rgb( 95, 211, 188)
    C_ACCENT       = DEFAULT_ACCENT
    C_BLACK        = rgb(  0,   0,   0)
  end
  if name == "light" or (ct and ct.light) then
    C_BG        = rgb(255, 255, 255)
    C_TEXT      = rgb(  0,   0,   0)
    C_DIM       = rgb(110, 110, 110)
    C_LINE      = rgb(210, 210, 210)
    C_TILE      = rgb(242, 242, 242)
    C_GREEN_BG  = rgb(220, 245, 228)
    C_GREEN_BR  = rgb(160, 210, 178)
    C_YELLOW_BG = rgb(255, 243, 205)
    C_YELLOW_BR = rgb(230, 200, 100)
    C_RED_BG    = rgb(252, 225, 225)
    C_RED_BR    = rgb(230, 170, 170)
    C_BLUE_BG   = rgb(225, 238, 255)
    C_BLUE_BR   = rgb(170, 200, 235)
  else
    C_BG        = rgb(  0,   0,   0)
    C_TEXT      = rgb(255, 255, 255)
    C_DIM       = rgb(124, 134, 148)
    C_LINE      = rgb( 42,  45,  51)
    C_TILE      = rgb( 13,  14,  17)
    C_GREEN_BG  = rgb( 12,  42,  22)
    C_GREEN_BR  = rgb( 29,  77,  42)
    C_YELLOW_BG = rgb( 42,  33,  10)
    C_YELLOW_BR = rgb( 90,  67,  19)
    C_RED_BG    = rgb( 42,  13,  13)
    C_RED_BR    = rgb( 88,  27,  27)
    C_BLUE_BG   = rgb( 13,  31,  42)
    C_BLUE_BR   = rgb( 30,  66,  88)
  end
  if ct then
    C_BG   = rgb(ct.bg[1],   ct.bg[2],   ct.bg[3])
    C_TILE = rgb(ct.tile[1], ct.tile[2], ct.tile[3])
    C_LINE = rgb(ct.line[1], ct.line[2], ct.line[3])
    C_DIM  = rgb(ct.dim[1],  ct.dim[2],  ct.dim[3])
    if ct.text then C_TEXT = rgb(ct.text[1], ct.text[2], ct.text[3]) end
    themeAccent = rgb(ct.accent[1], ct.accent[2], ct.accent[3])
  end
  GOV_COLOR.ACTIVE     = { fg=C_GREEN,  bg=C_GREEN_BG,  br=C_GREEN_BR  }
  GOV_COLOR.IDLE       = { fg=C_YELLOW, bg=C_YELLOW_BG, br=C_YELLOW_BR }
  GOV_COLOR.SPOOLUP    = { fg=C_YELLOW, bg=C_YELLOW_BG, br=C_YELLOW_BR }
  GOV_COLOR.RECOVERY   = { fg=C_YELLOW, bg=C_YELLOW_BG, br=C_YELLOW_BR }
  GOV_COLOR.OFF        = { fg=C_RED,    bg=C_RED_BG,    br=C_RED_BR    }
  GOV_COLOR["THR-OFF"] = { fg=C_RED,    bg=C_RED_BG,    br=C_RED_BR    }
  GOV_COLOR["LOST-HS"] = { fg=C_RED,    bg=C_RED_BG,    br=C_RED_BR    }
  GOV_COLOR.AUTOROT    = { fg=C_BLUE,   bg=C_BLUE_BG,   br=C_BLUE_BR   }
  GOV_COLOR.BAILOUT    = { fg=C_BLUE,   bg=C_BLUE_BG,   br=C_BLUE_BR   }
  GOV_COLOR.BYPASS     = { fg=C_BLUE,   bg=C_BLUE_BG,   br=C_BLUE_BR   }
  GOV_FALLBACK.fg = C_DIM
  GOV_FALLBACK.bg = C_TILE
  GOV_FALLBACK.br = C_LINE
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
local FMT_CACHE = {}
local function fmtNum(slot, pattern, v)
  local c = FMT_CACHE[slot]
  if c and c.v == v then return c.s end
  local s = string.format(pattern, v)
  if c then c.v = v; c.s = s else FMT_CACHE[slot] = { v = v, s = s } end
  return s
end
local flightsCacheN, flightsCacheS = -1, ""
local function fmtFlights(count)
  if count ~= flightsCacheN then
    flightsCacheN = count
    flightsCacheS = string.format("%d %s", count, (count == 1) and "Flight" or "Flights")
  end
  return flightsCacheS
end
local function batColor(pct)
  if pct >= 50 then return C_GREEN end
  if pct >= 20 then return C_YELLOW end
  return C_RED
end
local function txBatColor(pct)
  -- Classify the estimated whole percentage so floating-point rounding at the
  -- voltage boundaries cannot turn an exact 50% green or an exact 30% yellow.
  local wholePct = math.floor((pct or 0) + 0.5)
  if wholePct >= 51 then return C_GREEN end
  if wholePct >= 31 then return C_YELLOW end
  return C_RED
end
local function cellVoltageColor(sessionMin)
  if sessionMin and sessionMin <= SAFETY.cellRedThreshold then return C_RED end
  return C_TEXT
end

-- Retained LVGL object references. Static chrome is created once in update();
-- refresh() only changes the handful of properties whose values moved.
local V = {}
local OBJECT_STATE = {}
local function rememberObject(obj, properties)
  local state = { visible=true }
  for key, value in pairs(properties) do state[key] = value end
  OBJECT_STATE[obj] = state
  return obj
end
local function setObject(obj, properties)
  if not obj then return end
  local state = OBJECT_STATE[obj]
  if not state then
    state = {}
    OBJECT_STATE[obj] = state
  end
  local changed = false
  for key, value in pairs(properties) do
    if state[key] ~= value then
      state[key] = value
      changed = true
    end
  end
  if changed then obj:set(properties) end
end
local function setVisible(obj, visible)
  if not obj then return end
  local state = OBJECT_STATE[obj]
  if not state then
    state = {}
    OBJECT_STATE[obj] = state
  end
  visible = not not visible
  if state.visible == visible then return end
  state.visible = visible
  if visible then obj:show() else obj:hide() end
end
local function setLabel(obj, text, color, x, y, w, font, align)
  if not obj then return end
  local p = { text = tostring(text or "") }
  if color ~= nil then p.color = color end
  if x ~= nil then p.x = x end
  if y ~= nil then p.y = y end
  if w ~= nil then p.w = w end
  if font ~= nil then p.font = font end
  if align ~= nil then p.align = align end
  setObject(obj, p)
end
local function newLabel(x, y, w, text, font, color, align)
  local properties = { x=x, y=y, w=w or 0, h=0, text=text or "",
                       font=font or 0, color=color or C_TEXT, align=align or 0 }
  return rememberObject(lvgl.label(properties), properties)
end
local function newRect(x, y, w, h, color, filled, rounded, thickness)
  local properties = { x=x, y=y, w=w, h=h, color=color,
                       filled=filled and 1 or 0, rounded=rounded or 0,
                       thickness=thickness or 1 }
  return rememberObject(lvgl.rectangle(properties), properties)
end
local function newPanel(x, y, w, h, bg, border, rounded)
  return {
    fill = newRect(x, y, w, h, bg, true, rounded, 1),
    border = newRect(x, y, w, h, border, false, rounded, 1),
  }
end
local function setPanel(panel, bg, border)
  setObject(panel.fill, { color=bg })
  setObject(panel.border, { color=border })
end

local SIG_HEIGHTS = { 6, 10, 14, 18 }
local function buildTopBar()
  local y, h = G.layout.top.y, G.layout.top.h
  local centerY = y + h / 2
  local timerX = G.originX + G.w / 2 - G.x(100)
  local modelGap = math.max(3, G.x(8))
  local modelW = math.max(G.x(120), timerX - G.layout.top.x - modelGap)
  -- LVGL fonts carry more top leading than lcd.drawText(); compensate so the
  -- glyphs occupy the same top-bar baseline as the original dashboard.
  V.modelName = newLabel(G.layout.top.x, y - G.y(2), modelW, "",
                         G.fontTop, C_TEXT)
  V.timer = newLabel(timerX,
                     math.max(G.originY, y - G.y(9)),
                     G.x(200), "", G.fontTimer, C_TEXT, CENTERED)
  -- A compact vertical battery sits at the far right. Rotating the original
  -- glyph counter-clockwise puts its terminal on top and makes charge fill
  -- bottom-to-top. Signal quality occupies the space immediately to its left.
  local battW, battH = math.max(4, G.x(20)), math.max(8, G.y(28))
  local terminalW, terminalH = math.max(2, G.x(10)), math.max(1, G.y(3))
  local oneY = math.max(1, G.y(1))
  local totalBattH = battH + terminalH + oneY
  local battX = G.originX + G.w - G.x(10) - battW
  local battY = centerY - totalBattH / 2 + terminalH + oneY
  local sigX = battX - G.x(14) - G.x(36)
  local profileSignalGap = math.max(8, G.x(10))
  local profileMinW = #"Profile 6 / Rate 6" * 9
  local profileX = math.min(timerX + G.x(150),
                            sigX - profileSignalGap - profileMinW)
  local profileY = math.floor(centerY - 11)
  if G.screen480x320 then profileY = profileY + 2 end
  V.profileStatus = newLabel(
    profileX, profileY,
    math.max(1, sigX - profileSignalGap - profileX), "",
    SMLSIZE, C_TEXT, RIGHT)
  V.signal = {}
  for i, referenceH in ipairs(SIG_HEIGHTS) do
    local bh = math.max(1, G.y(referenceH))
    V.signal[i] = newRect(sigX + (i-1) * G.x(10),
                          centerY + G.y(10) - bh,
                          math.max(1, G.x(6)), bh,
                          C_LINE, true, 0, 0)
  end
  V.txBody = newPanel(battX, battY, battW, battH, C_TILE, C_DIM,
                      math.max(0, G.min(3)))
  newRect(battX + (battW - terminalW) / 2, battY - terminalH - 1,
          terminalW, terminalH, C_DIM, true, math.max(0, G.min(1)), 0)
  local insetX, insetY = math.max(1, G.x(2)), math.max(1, G.y(2))
  V.txFill = newRect(battX + insetX, battY + battH - insetY - 1,
                     math.max(1, battW - insetX * 2), 1, C_GREEN, true,
                     math.max(0, G.min(2)), 0)
  lvgl.hline({ x=G.originX, y=y + h + G.y(2), w=G.w, h=1, color=C_LINE })
  V.txBodyW, V.txBodyH, V.txBodyY = battW, battH, battY
  V.txInsetX, V.txInsetY = insetX, insetY
end

local function buildModelPanel()
  local p = G.layout.pic
  local footerH = math.max(1, G.y(28))
  local imgH = p.h - footerH
  newPanel(p.x, p.y, p.w, p.h, C_TILE, C_LINE, p.r)
  local inset = math.max(1, p.r - G.min(3))
  V.modelImage = lvgl.image({
    x=p.x + inset, y=p.y + inset, w=p.w - inset * 2,
    h=imgH - inset * 2, fill=false,
    file=function() return resolveModelImagePath() or "" end,
    visible=function() return resolveModelImagePath() ~= nil end,
  })
  V.noImage = lvgl.label({
    x=p.x, y=p.y + imgH / 2 - G.y(8), w=p.w, h=0,
    text="no model image", font=G.fontSmall, color=C_DIM, align=CENTERED,
    visible=function() return resolveModelImagePath() == nil end,
  })
  lvgl.hline({ x=p.x + G.x(8), y=p.y + imgH,
               w=p.w - G.x(16), h=1, color=C_LINE })
  V.flightCount = newLabel(p.x, p.y + p.h - footerH + G.y(5) - 2, p.w, "",
                           G.fontSmall, C_TEXT, CENTERED)
end

local function buildGovernor()
  local g = G.layout.gov
  V.govPanel = newPanel(g.x, g.y, g.w, g.h, C_TILE, C_LINE, g.r)
  newLabel(g.x, g.y + G.y(14), g.w, "GOVERNOR",
           G.fontSmall, C_ACCENT, CENTERED)
  V.govState = newLabel(g.x, g.y + G.y(50), g.w, "",
                        G.fontGovernor, C_TEXT, CENTERED)
end

local function buildHero()
  local hb = G.layout.hero
  newPanel(hb.x, hb.y, hb.w, hb.h, C_TILE, C_LINE, hb.r)
  local title = G.compact and "HEADSPEED" or "HEADSPEED RPM"
  newLabel(hb.x + G.x(14), hb.y + G.y(3), G.x(285),
           title, G.fontSmall, C_DIM)
  local rpmW = G.compact and G.x(250) or G.x(230)
  local rpmY = hb.y + G.y(42)
  -- This optical correction is for TX16S MKII's exact 480x272 layout only.
  if G.screen480x272 then rpmY = rpmY - 2 end
  V.rpm = newLabel(hb.x + G.x(14), rpmY, rpmW, "",
                   G.fontHero, C_TEXT)
  local rx = hb.x + hb.w - G.x(14)
  if G.compact then
    -- Combine each secondary label/value into one right-aligned object. This
    -- avoids the narrow "max" and "tail" labels wrapping on 480-wide radios.
    local rightW = G.x(170)
    local rightX = rx - rightW
    local ry = hb.y + G.y(25)
    V.rpmMax = newLabel(rightX, ry, rightW, "",
                        G.fontSmall, C_YELLOW, RIGHT)
    V.tailRpm = newLabel(rightX, ry + G.y(60), rightW, "",
                         G.fontSmall, C_TEXT, RIGHT)
    V.compactHero = true
  elseif G.largeScreen then
    -- Pair each caption tightly with a left-aligned value. Offset the smaller
    -- caption downward so its visual center matches the MIDSIZE number.
    local ry, step = hb.y + G.y(25), G.y(60)
    local valueW = G.x(90)
    local labelW = G.x(45)
    local gap = G.x(6)
    local rightInset = G.x(20)
    local valueX = rx - rightInset - valueW
    local labelX = valueX - gap - labelW
    local labelYAdjust = G.y(4)
    newLabel(labelX, ry + labelYAdjust, labelW, "max",
             G.fontSecondaryLabel, C_DIM, RIGHT)
    V.rpmMax = newLabel(valueX, ry, valueW, "",
                        G.fontSecondaryValue, C_YELLOW)
    newLabel(labelX, ry + step + labelYAdjust, labelW, "tail",
             G.fontSecondaryLabel, C_DIM, RIGHT)
    V.tailRpm = newLabel(valueX, ry + step, valueW, "",
                         G.fontSecondaryValue, C_TEXT)
  else
    local lx = rx - G.x(170)
    local ry, step = hb.y + G.y(25), G.y(30)
    local labelW = G.x(70)
    newLabel(lx, ry, labelW, "max", G.fontSecondaryLabel, C_DIM)
    V.rpmMax = newLabel(lx + labelW, ry, G.x(100), "",
                        G.fontSecondaryValue, C_YELLOW, RIGHT)
    newLabel(lx, ry + step * 2, labelW, "tail", G.fontSecondaryLabel, C_DIM)
    V.tailRpm = newLabel(lx + labelW, ry + step * 2, G.x(100), "",
                         G.fontSecondaryValue, C_TEXT, RIGHT)
  end
end

local function buildTile(x, y, w, h, label, unit)
  if G.compact then
    local caption = label
    if unit == "(V)" then
      caption = label .. " V"
    elseif unit == "(°C)" then
      caption = "ESC °C"
    end
    newLabel(x + 2, y + 4, w - 4, caption,
             G.fontSmall, C_DIM, CENTERED)
    local valueY = y + math.max(20, G.y(32))
    if G.screen480x320 then
      -- MIDSIZE is 24 px tall on this target. Center the value itself in the
      -- tile while leaving the compact caption and extrema footer anchored.
      valueY = y + math.floor((h - 24) / 2)
    elseif G.screen480x272 then
      -- Lower only the four live telemetry values by four physical pixels.
      valueY = valueY + 4
    end
    return {
      value = newLabel(x + 2, valueY, w - 4, "",
                       G.fontValue, C_TEXT, CENTERED),
      footer = newLabel(x + 2, y + h - 16, w - 4, "",
                        G.fontSmall, C_DIM, CENTERED),
    }
  end
  newLabel(x + G.x(10), y + G.y(10), w - G.x(20), label,
           G.fontSmall, C_DIM)
  newLabel(x + w - G.x(45), y + G.y(10), G.x(35), unit,
           G.fontSmall, C_DIM, RIGHT)
  local valueY = y + G.y(54)
  if G.screen800x480 then
    -- Center the 32 px DBLSIZE value without moving the caption or footer.
    valueY = y + math.floor((h - 32) / 2)
  end
  return {
    value = newLabel(x + G.x(10), valueY, w - G.x(20), "",
                     G.fontValue, C_TEXT,
                     G.screen800x480 and CENTERED or 0),
    footer = newLabel(x + G.x(10), y + h - G.y(22),
                      w - G.x(20), "", G.fontSmall, C_DIM),
  }
end
local function buildTiles()
  local t = G.layout.tiles
  local n = 4
  local w = math.floor((t.w - (n-1) * t.gap) / n)
  local becLabel = OPT.heliType == HELI_NITRO and "BATT" or "BEC"
  newPanel(t.x, t.y, t.w, t.h, C_TILE, C_LINE, t.r)
  for i = 1, n - 1 do
    local dx = t.x + (w + t.gap) * i - math.floor(t.gap / 2)
    lvgl.vline({ x=dx, y=t.y + G.y(8), w=1,
                 h=t.h - G.y(16), color=C_LINE })
  end
  V.tiles = {
    buildTile(t.x,                         t.y, w, t.h, "AMPS",  "(A)"),
    buildTile(t.x + (w + t.gap),          t.y, w, t.h, "CELL",  "(V)"),
    buildTile(t.x + (w + t.gap) * 2,      t.y, w, t.h, becLabel, "(V)"),
    buildTile(t.x + (w + t.gap) * 3,      t.y, w, t.h, "ESC T", "(°C)"),
  }
end

local function buildBottom()
  local b = G.layout.bot
  local x, y, w = b.x, b.y, b.w
  local barY = y + G.y(G.compact and 30 or 26)
  -- Keep the top anchored and extend only the lower edge by five physical
  -- pixels so the increase is identical at every supported resolution.
  local barH = math.max(1, G.y(G.compact and 44 or 60) + 5)
  -- The original 44px bar centered this font at barY + 2. Move the text down
  -- by half of any added height so it remains centered as the bottom extends.
  local textY = barY + G.y(2)
                + math.floor((barH - G.y(44)) / 2)
  local insetX, insetY = math.max(1, G.x(2)), math.max(1, G.y(2))
  V.bottom = {
    x=x, y=y, w=w, barY=barY, barH=barH, textY=textY,
    insetX=insetX, insetY=insetY, minTextW=math.max(1, G.x(40)),
    header=newLabel(x, y + G.y(2), w, "", G.fontSmall, C_DIM),
    panel=newPanel(x, barY, w, barH, C_TILE, C_LINE,
                   math.max(0, G.min(5))),
    fill=newRect(x + insetX, barY + insetY, 1,
                 math.max(1, barH - insetY * 2), C_GREEN, true,
                 math.max(0, G.min(3)), 0),
    center=newLabel(x, textY, w, "", G.fontBattery, C_BLACK, CENTERED),
  }
  local B = V.bottom
  if OPT.battBarMode == 1 then
    B.mode = "nitro"
    B.minimum = newLabel(x, barY + barH + G.y(4), G.x(220), "",
                         G.fontSmall, C_DIM)
    B.range = newLabel(x + w - G.x(220), barY + barH + G.y(4),
                       G.x(220),
                       string.format("%.1fV - %.1fV", OPT.rxPackMin, OPT.rxPackMax),
                       G.fontSmall, C_DIM, RIGHT)
  else
    B.mode = "electric"
    -- The reference-size footer needs less air below the taller bar. Keep the
    -- compact-radio spacing unchanged because those layouts are independently
    -- fitted to their shorter screens.
    local footerGap = G.screen800x480 and G.y(1) or G.y(4)
    local fy = barY + barH + footerGap
    local tickW, halfTick = G.x(60), G.x(30)
    B.ticks = {
      newLabel(x,                    fy, tickW, "0%",   G.fontSmall, C_DIM),
      newLabel(x + w*.25 - halfTick, fy, tickW, "25%",  G.fontSmall, C_DIM, CENTERED),
      newLabel(x + w*.50 - halfTick, fy, tickW, "50%",  G.fontSmall, C_DIM, CENTERED),
      newLabel(x + w*.75 - halfTick, fy, tickW, "75%",  G.fontSmall, C_DIM, CENTERED),
      newLabel(x + w - tickW,        fy, tickW, "100%", G.fontSmall, C_DIM, RIGHT),
    }
  end
end

local function updateBottom()
  local B = V.bottom
  if not B then return end
  if OPT.autoHeliType and not AUTO_HELI.ready then
    setLabel(B.header, AUTO_HELI.status or "WAITING FOR FC NAME", C_YELLOW)
    setVisible(B.fill, false)
    setLabel(B.center, "AUTO · WAIT", C_YELLOW, B.x, B.textY, B.w,
             G.fontBattery, CENTERED)
    setVisible(B.center, true)
    return
  end
  local configWarning
  local rxSettingsInvalid = B.mode == "nitro" and not OPT.rxPackValid
  if not OPT.simTelemetry then
    if A.motorConfigError and rxSettingsInvalid then
      configWarning = A.motorConfigError .. " · CHECK RX PACK SETTINGS"
    elseif A.motorConfigError then
      configWarning = A.motorConfigError
    elseif rxSettingsInvalid then
      configWarning = "CHECK RX PACK SETTINGS"
    end
  end
  if B.mode == "nitro" then
    local hasRx = OPT.rxPackValid and D.rxVoltage ~= nil and D.rxVoltage > 0
    local rxV, rxCV, pct = D.rxVoltage or 0, D.rxCellVoltage or 0, D.rxPercent or 0
    local header
    if G.compact then
      header = hasRx and string.format("RX BATT · %.2fV · %.2fV/cell", rxV, rxCV)
                     or "RX BATT · no data"
    else
      header = hasRx
                   and string.format("Receiver Battery · %.2fV · %.2fV/cell", rxV, rxCV)
                   or "Receiver Battery · no data"
    end
    if OPT.simTelemetry then header = "SIM · " .. header end
    setLabel(B.header,
             configWarning or header,
             configWarning and C_RED or C_DIM)
    local fillW = math.floor((B.w - B.insetX * 2) * pct / 100)
    local wholePct = math.floor(pct)
    local showEmpty = hasRx and wholePct <= 0
    setPanel(B.panel, C_TILE, showEmpty and C_RED or C_LINE)
    setObject(B.fill, { w=math.max(1, fillW),
                        h=math.max(1, B.barH - B.insetY * 2),
                        color=batColor(pct) })
    setVisible(B.fill, hasRx and fillW > 0)
    if showEmpty then
      setLabel(B.center, "0%", C_RED, B.x, B.textY, B.w,
               G.fontBattery, CENTERED)
      setVisible(B.center, true)
    else
      setLabel(B.center, tostring(wholePct) .. "%", C_BLACK,
               B.x + B.insetX, B.textY, math.max(1, fillW),
               G.fontBattery, CENTERED)
      setVisible(B.center, hasRx and fillW > B.minTextW)
    end
    setLabel(B.minimum, D.minRxVoltage and string.format("min %.2fV", D.minRxVoltage)
                                          or "min --", C_DIM)
    setLabel(B.range,
             OPT.rxPackValid and string.format("%.1fV - %.1fV", OPT.rxPackMin, OPT.rxPackMax)
                             or "INVALID RANGE",
             OPT.rxPackValid and C_DIM or C_RED)
    return
  end

  local cells, volt = D.cellsResolved, D.voltage
  local capa = math.floor(D.capacity or 0)
  local usedText = D.capacityValid
                   and (G.compact and string.format(" · %dmAh", capa)
                                  or string.format(" · %d mAh used", capa))
                   or ""
  local prof = sensors.getBattProfile()
  local batteryTitle = G.compact and "BATT" or "BATTERY"
  local header
  if not D.hasBattData and OPT.heliType == HELI_OMPHOBBY
     and sensors.getCellCount() == 0 then
    header = batteryTitle .. " · ADD M1 OR M2 TO MODEL NAME"
  elseif not D.hasBattData then
    header = batteryTitle .. " · no data"
  elseif cells > 0 and volt > 0 and prof and prof > 0 then
    header = string.format("%s · P%d · %dS · %.1fV",
                           batteryTitle, math.floor(prof), cells, volt) .. usedText
  elseif cells > 0 and volt > 0 then
    header = string.format("%s · %dS · %.1fV",
                           batteryTitle, cells, volt) .. usedText
  elseif D.cellVoltageValid then
    header = string.format("%s · %.2fV/cell",
                           batteryTitle, sensors.getCellVoltage()) .. usedText
  else
    -- Smart Fuel can remain fully usable when Vcel/Vbat are not configured.
    -- Do not invent a 0.00V/cell header for a valid FC-side percentage.
    header = batteryTitle .. usedText
  end
  if OPT.simTelemetry then header = "SIM · " .. header end
  setLabel(B.header, configWarning or header, configWarning and C_RED or C_DIM)
  setPanel(B.panel, C_TILE, C_LINE)
  if not D.hasBattData then
    setVisible(B.fill, false)
    setLabel(B.center, "NO DATA", C_RED, B.x, B.textY, B.w,
             G.fontBattery, CENTERED)
    setVisible(B.center, true)
    for _, tickLabel in ipairs(B.ticks) do setVisible(tickLabel, false) end
  else
    local pct = A.displayPercentInit and A.displayPercent or D.adjustedPercent
    if pct < 0 then pct = 0 elseif pct > 100 then pct = 100 end
    local fillW = math.floor((B.w - B.insetX * 2) * pct / 100)
    local wholePct = math.floor(pct)
    local showEmpty = wholePct <= 0
    setPanel(B.panel, C_TILE, showEmpty and C_RED or C_LINE)
    setObject(B.fill, { w=math.max(1, fillW),
                        h=math.max(1, B.barH - B.insetY * 2),
                        color=batColor(pct) })
    setVisible(B.fill, fillW > 0)
    if showEmpty then
      setLabel(B.center, "0%", C_RED, B.x, B.textY, B.w,
               G.fontBattery, CENTERED)
      setVisible(B.center, true)
    else
      setLabel(B.center, tostring(wholePct) .. "%", C_BLACK,
               B.x + B.insetX, B.textY, math.max(1, fillW),
               G.fontBattery, CENTERED)
      setVisible(B.center, fillW > B.minTextW)
    end
    for _, tickLabel in ipairs(B.ticks) do setVisible(tickLabel, true) end
  end
end

local function updateUiState()
  if not V.modelName then return end
  local modelName = getModelName()
  if OPT.simTelemetry then modelName = "SIM · " .. modelName end
  local modelFont = G.fontTop
  -- 480x320 has enough vertical and horizontal room for common full model
  -- names such as "Stratos 700 #3" at MIDSIZE. Keep the earlier small-font
  -- protection on 480x272 and for genuinely longer compact-screen names.
  local compactNameLimit = G.screen480x320 and 16 or 12
  if G.compact and #modelName > compactNameLimit then
    modelFont = G.fontSmall
  end
  if G.compact and #modelName > 22 then
    modelName = string.sub(modelName, 1, 20) .. ".."
  end
  setLabel(V.modelName, modelName, C_TEXT, nil, nil, nil, modelFont)
  local secs = getTimer1Secs()
  local mm = math.floor(math.abs(secs) / 60)
  local ss = math.abs(secs) - mm * 60
  setLabel(V.timer, string.format("%d:%02d", mm, ss), C_TEXT)

  local rq = sensors.getRqly()
  local bars = rq >= 80 and 4 or rq >= 60 and 3 or rq >= 40 and 2 or rq >= 20 and 1 or 0
  local sigColor = bars >= 3 and C_GREEN or bars == 2 and C_YELLOW or C_RED
  for i, bar in ipairs(V.signal) do
    setObject(bar, { color=(i <= bars) and sigColor or C_LINE })
  end

  local pidProfile, rateProfile, profilesReady = sensors.profilePair()
  setLabel(V.profileStatus,
    profilesReady and string.format("Profile %d / Rate %d",
      pidProfile, rateProfile) or "", C_TEXT)

  local txPct = sensors.txPctFromVolts(sensors.getTxVolt(), txIsLiIon)
  if txPct then
    local fillH = math.floor((V.txBodyH - V.txInsetY * 2) * txPct / 100)
    local fillY = V.txBodyY + V.txBodyH - V.txInsetY - fillH
    setObject(V.txFill, { y=fillY,
                          w=math.max(1, V.txBodyW - V.txInsetX * 2),
                          h=math.max(1, fillH),
                          color=txBatColor(txPct) })
    setVisible(V.txFill, fillH > 0)
  else
    setVisible(V.txFill, false)
  end

  local flightText, flightColor
  if OPT.flightCounter == FC.ROTORFLIGHT then
    local count = getFlightCount()
    if count ~= nil then
      flightText = fmtFlights(count)
      flightColor = FC.stale and C_YELLOW or C_TEXT
    else
      flightText = FC.status or "WAITING"
      flightColor = sensors.flightStatusPending() and C_YELLOW or C_RED
    end
  else
    local count = getFlightCount()
    flightText = count ~= nil and fmtFlights(count) or "-- Flights"
    if A.flightSaveError then flightText = flightText .. " · FILE ERROR" end
    flightColor = A.flightSaveError and C_RED or C_TEXT
  end
  if OPT.flightCounter == FC.ROTORFLIGHT and flightStore.dirty
     and flightStore.error then
    flightText = flightText .. " - KSE FILE ERROR"
    flightColor = C_RED
  end
  if G.profileConnectedForDisplay then
    flightText = flightText .. " - Connected"
  end
  setLabel(V.flightCount, flightText, flightColor)
  local govState = sensors.getGovState()
  local govTheme = GOV_COLOR[govState] or GOV_FALLBACK
  setPanel(V.govPanel, govTheme.bg, govTheme.br)
  setLabel(V.govState, GOV_LABELS[govState] or govState, govTheme.fg)

  local rpm = sensors.getHeadspeed()
  if D.rpmValid then
    setLabel(V.rpm, tostring(math.floor(rpm)), C_TEXT)
    local maxText = fmtNum("rpmMax", "%d", math.floor(statRpmMax()))
    setLabel(V.rpmMax, V.compactHero and ("MAX " .. maxText) or maxText,
             C_YELLOW)
  else
    setLabel(V.rpm, "--", C_DIM)
    setLabel(V.rpmMax, V.compactHero and "MAX --" or "--", C_DIM)
  end
  local tailRpm = sensors.getTailRpm()
  local tailText = D.tailRpmValid and tostring(math.floor(tailRpm)) or "--"
  if V.compactHero then tailText = "TAIL " .. tailText end
  setLabel(V.tailRpm, tailText,
           D.tailRpmValid and C_TEXT or C_DIM)

  if OPT.battBarMode == 1 then
    setLabel(V.tiles[1].value, "--", C_DIM, nil, nil, nil, nil, CENTERED)
    setLabel(V.tiles[1].footer, "", C_DIM)
    local rxCell = D.rxCellVoltage
    local rxCellMin = D.minRxVoltage and (D.minRxVoltage / 2) or nil
    if rxCell and rxCell > 0 then
      setLabel(V.tiles[2].value, string.format("%.2f", rxCell), C_TEXT,
               nil, nil, nil, nil,
               (G.compact or G.screen800x480) and CENTERED or 0)
    else
      setLabel(V.tiles[2].value, "--", C_DIM,
               nil, nil, nil, nil, CENTERED)
    end
    setLabel(V.tiles[2].footer,
             rxCellMin and string.format("min %.2f", rxCellMin) or "min --", C_DIM)
  else
    local curr = sensors.getCurr()
    if D.currentValid then
      setLabel(V.tiles[1].value, tostring(math.ceil(curr)), C_TEXT)
      setLabel(V.tiles[1].footer,
               fmtNum("currMax", "max %d", math.ceil(statCurrMax())), C_YELLOW)
    else
      setLabel(V.tiles[1].value, "--", C_DIM, nil, nil, nil, nil, CENTERED)
      setLabel(V.tiles[1].footer, "", C_DIM)
    end
    local cell = sensors.getCellVoltage()
    local cellMin = statCellMin()
    if cell > 0 then
      setLabel(V.tiles[2].value, string.format("%.2f", cell),
               cellVoltageColor(cellMin), nil, nil, nil, nil,
               (G.compact or G.screen800x480) and CENTERED or 0)
    else
      setLabel(V.tiles[2].value, "--", C_DIM,
               nil, nil, nil, nil, CENTERED)
    end
    setLabel(V.tiles[2].footer,
             D.cellVoltageValid and cellMin
               and fmtNum("cellMin", "min %.2f", cellMin) or "min --", C_DIM)
  end
  local bec = sensors.getBec()
  local becColor = C_TEXT
  if bec and bec > 0 then
    if bec < 4.8 then becColor = C_RED elseif bec < 5.1 then becColor = C_YELLOW end
  end
  if D.becValid then
    setLabel(V.tiles[3].value, string.format("%.1f", bec), becColor)
    local becMin = statBecMin()
    setLabel(V.tiles[3].footer,
             becMin and fmtNum("becMin", "min %.1f", becMin) or "min --", C_DIM)
  else
    setLabel(V.tiles[3].value, "--", C_DIM, nil, nil, nil, nil, CENTERED)
    setLabel(V.tiles[3].footer, "", C_DIM)
  end
  if OPT.battBarMode == 1 then
    setLabel(V.tiles[4].value, "--", C_DIM, nil, nil, nil, nil, CENTERED)
    setLabel(V.tiles[4].footer, "", C_DIM)
  else
    local temp, tempMax = sensors.getTemp(), statTempMax()
    if D.tempValid then
      setLabel(V.tiles[4].value, tostring(math.floor(temp)), C_TEXT)
      setLabel(V.tiles[4].footer, fmtNum("tempMax", "max %d", math.floor(tempMax)),
               C_YELLOW)
    else
      setLabel(V.tiles[4].value, "--", C_DIM, nil, nil, nil, nil, CENTERED)
      setLabel(V.tiles[4].footer, "", C_DIM)
    end
  end
  updateBottom()
end

-- RotorFlight 2.3 battery-profile picker ------------------------------------
-- This is the GX15 Dash RF Tool integration adapted to KSE4's responsive
-- retained UI. RF Tool remains the sole transport and queue owner.
-- @include shared:rf.lua
-- @include shared:auto_heli.lua
local function buildUi()
  if not lvgl then return end
  lvgl.clear()
  V = {}
  OBJECT_STATE = {}
  if not OPT.bgTransparent then
    newRect(G.originX, G.originY, G.w, G.h, C_BG, true, 0, 0)
  end
  buildTopBar()
  buildModelPanel()
  buildGovernor()
  buildHero()
  buildTiles()
  buildBottom()
  batteryProfiles.buildArmingBanner()
  batteryProfiles.buildPrompt()
  updateUiState()
end

local function ensureLayout(widget, fullScreen)
  local x, y, w, h = G.bounds(widget.zone, fullScreen)
  local signature = G.signature(x, y, w, h)
  if widget.layoutSignature == signature then return false end
  G.configure(x, y, w, h)
  widget.layoutSignature = signature
  buildUi()
  return true
end

G.prepareWidget = function(widget)
  local x,y,w,h = G.bounds(widget.zone, false)
  G.configure(x,y,w,h)
  widget.layoutSignature = G.signature(x,y,w,h)
end
G.pickerStyle = function() return {font=SMLSIZE, radius=6, color=C_TILE} end
G.preferNativePicker = true

-- @include shared:lifecycle.lua
local options = {
  { "Theme",    CHOICE, 1, { "Dark", "Light", "Transparent",
                             "Orange", "Red", "Blue", "Pink", "Green",
                             "Purple", "Reef", "Royal", "Ember",
                             "Graphite", "Glacier", "Sunset", "Synthwave",
                             "Gulf", "Voltage", "Transparent Light",
                             "Titanium Ember", "Aurora", "Desert Night" } },
  { "TxBatt",   CHOICE, 1, { "LiPo", "Li-Ion" } },
  { "MinFlight", VALUE, TOPBAR_MIN_DUR_DEFAULT, -30, 120 },
  { "HeliType", CHOICE, 1, { "Electric", "Nitro", "OMPHOBBY", "Auto" } },
  { "BattRsv", VALUE, 20, 0, 50 },
  { "BattVoice", BOOL, 0 },
  { "RxPackMin", STRING, "6.60" },
  { "RxPackMax", STRING, "8.40" },
  { "MotorSw", SOURCE, (function()
      local info = type(getFieldInfo) == "function" and getFieldInfo("SG") or nil
      return type(info) == "table" and info.id or 0
    end)() },
  { "CountSrc", CHOICE, 2, { "KSE Counter", "Rotorflight FC" } },
}
local OPTION_LABELS = {
  TxBatt   = "TX Battery",
  MinFlight= "KSE Counter Min (sec)",
  HeliType = "Heli Type",
  BattRsv  = "Batt Reserve %",
  BattVoice= "Battery Voice",
  RxPackMin= "Rx Pack Minimum",
  RxPackMax= "Rx Pack Maximum",
  MotorSw  = "Motor Switch",
  CountSrc = "Flight Counter",
}
local function translate(name, language)
  return OPTION_LABELS[name] or name
end
return {
  name       = "KSE4",
  options    = options,
  create     = create,
  update     = update,
  refresh    = refresh,
  background = background,
  translate  = translate,
  useLvgl    = true,
}
