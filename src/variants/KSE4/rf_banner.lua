local function profileShowArmingBanner(wgt)
  local banner = V.armingBanner
  if not banner then return end
  local visible = type(wgt.armingBlockerText) == "string"
                  and wgt.armingBlockerText ~= ""
  if visible then
    setLabel(banner.label, wgt.armingBlockerText, C_TEXT)
  end
  for _, object in ipairs(banner.objects) do setVisible(object, visible) end
end
