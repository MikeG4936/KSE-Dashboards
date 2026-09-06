local function profileSetEntryPrompt(wgt, visible, title, detail, color, compact)
  local prompt = wgt.ui and wgt.ui.profilePrompt
  if not prompt then return end
  if visible then
    local geometry = compact and prompt.compact or prompt.full
    setObject(wgt, prompt.fill, {
      x=geometry.x, y=geometry.y, w=geometry.w, h=geometry.h,
    })
    setObject(wgt, prompt.border, {
      x=geometry.x, y=geometry.y, w=geometry.w, h=geometry.h,
    })
    setObject(wgt, prompt.accent, {
      x=geometry.x + 2, y=geometry.y + 2, h=geometry.h - 4,
      color=color or C_GREEN,
    })
    setObject(wgt, prompt.title, {
      x=geometry.titleX, y=geometry.titleY, w=geometry.titleW,
    })
    setObject(wgt, prompt.detail, {
      x=geometry.detailX, y=geometry.detailY, w=geometry.detailW,
    })
    setLabel(wgt, prompt.title, title or "BATTERY PROFILE READY", C_TEXT)
    setLabel(wgt, prompt.detail, detail or "SELECT A BATTERY PROFILE", C_DIM)
  end
  for _, object in ipairs(prompt.objects) do setVisible(wgt, object, visible) end
  if visible and compact then setVisible(wgt, prompt.accent, false) end
end
