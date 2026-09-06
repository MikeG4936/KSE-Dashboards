local function profileShowArmingBanner(wgt)
  local banner = wgt and wgt.ui and wgt.ui.armingBanner or nil
  if not banner then return end
  local visible = type(wgt.armingBlockerText) == "string"
                  and wgt.armingBlockerText ~= ""
  if visible then
    setLabel(wgt, banner.label, wgt.armingBlockerText, C_TEXT, CENTERED)
  end
  for _, object in ipairs(banner.objects) do
    setVisible(wgt, object, visible)
  end
end
