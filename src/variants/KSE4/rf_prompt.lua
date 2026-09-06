local function profileBuildEntryPrompt()
  local promptW = math.min(G.w - math.max(12, G.x(24)), G.compact and 300 or 360)
  local promptH = G.compact and 56 or 64
  local x = G.originX + math.floor((G.w - promptW) / 2)
  local y = G.originY + math.floor((G.h - promptH) / 2)
  local titleY = y + (G.compact and 5 or 7)
  local detailY = y + (G.compact and 34 or 39)
  local prompt = {
    fill=newRect(x, y, promptW, promptH, C_TILE, true,
                 math.max(2, G.min(6)), 1),
    border=newRect(x, y, promptW, promptH, C_LINE, false,
                   math.max(2, G.min(6)), 2),
    accent=newRect(x + 2, y + 2, math.max(3, G.x(5)), promptH - 4,
                   C_GREEN, true, math.max(1, G.min(2)), 1),
    title=newLabel(x + 10, titleY, promptW - 20, "",
                   G.fontSmall, C_TEXT, CENTERED),
    detail=newLabel(x + 10, detailY, promptW - 20, "",
                    G.fontSmall, C_DIM, CENTERED),
  }
  prompt.objects = {
    prompt.fill, prompt.border, prompt.accent, prompt.title, prompt.detail,
  }
  V.profilePrompt = prompt
  for _, object in ipairs(prompt.objects) do setVisible(object, false) end
end

local function profileBuildArmingBanner()
  if OPT.heliType == HELI_OMPHOBBY then return end
  local inset = math.max(5, G.x(10))
  local y = G.originY + math.max(40, G.y(48))
  local h = math.max(20, G.y(24))
  local banner = {
    fill=newRect(G.originX + inset, y, G.w - inset * 2, h,
                 C_RED, true, math.max(2, G.min(3)), 1),
    border=newRect(G.originX + inset, y, G.w - inset * 2, h,
                   C_YELLOW, false, math.max(2, G.min(3)), 1),
    label=newLabel(G.originX + inset * 2, y + math.max(2, G.y(4)),
                   G.w - inset * 4, "", G.fontSmall, C_TEXT, CENTERED),
  }
  banner.objects = { banner.fill, banner.border, banner.label }
  V.armingBanner = banner
  for _, object in ipairs(banner.objects) do setVisible(object, false) end
end

local function profileSetEntryPrompt(wgt, visible, title, detail, color, compact)
  local prompt = V.profilePrompt
  if not prompt then return end
  if visible then
    setObject(prompt.accent, { color=color or C_GREEN })
    setLabel(prompt.title, title or "BATTERY PROFILE READY", C_TEXT)
    setLabel(prompt.detail, detail or "SELECT A BATTERY PROFILE", C_DIM)
  end
  for _, object in ipairs(prompt.objects) do setVisible(object, visible) end
  if visible and compact then setVisible(prompt.accent, false) end
end
