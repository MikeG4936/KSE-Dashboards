G.applyOptionTheme = function(rawTheme)
  OPT.bgTransparent   = (rawTheme == 3 or rawTheme == 19)
  applyTheme(THEME_NAMES[rawTheme] or "dark")
  C_ACCENT = themeAccent or DEFAULT_ACCENT
end

-- Transparent dashboard themes use their corresponding opaque settings palette.
G.settingsPalette = function(rawTheme)
  local name=THEME_NAMES[rawTheme] or "dark"
  local p=COLOR_THEMES[name]
  if p then
    return {bg=lcd.RGB(p.bg[1],p.bg[2],p.bg[3]),
      panel=lcd.RGB(p.tile[1],p.tile[2],p.tile[3]),
      dim=lcd.RGB(p.dim[1],p.dim[2],p.dim[3]),
      accent=lcd.RGB(p.accent[1],p.accent[2],p.accent[3]), text=lcd.RGB(255,255,255)}
  end
  local light=name=="light"
  return {bg=light and lcd.RGB(255,255,255) or lcd.RGB(0,0,0),
    panel=light and lcd.RGB(242,242,242) or lcd.RGB(13,14,17),
    dim=light and lcd.RGB(110,110,110) or lcd.RGB(124,134,148),
    text=light and lcd.RGB(0,0,0) or lcd.RGB(255,255,255),
    accent=lcd.RGB(95,211,188)}
end
