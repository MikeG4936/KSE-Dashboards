G.applyOptionTheme = function(rawTheme)
  OPT.bgTransparent   = (rawTheme == 3 or rawTheme == 19)
  applyTheme(THEME_NAMES[rawTheme] or "dark")
  C_ACCENT = themeAccent or DEFAULT_ACCENT
end
