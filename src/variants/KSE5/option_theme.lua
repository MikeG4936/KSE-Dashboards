G.themeName = function(rawTheme)
  local themeNames = {
    [1]="dark", [2]="light", [3]="arctic", [4]="violet",
    [5]="orange", [6]="red", [7]="blue", [8]="pink",
    [9]="green", [10]="purple", [11]="reef", [12]="royal",
    [13]="ember", [14]="graphite", [15]="glacier", [16]="sunset",
    [17]="synthwave", [18]="gulf", [19]="voltage",
    [20]="titanium_ember", [21]="aurora", [22]="desert_night",
  }
  return themeNames[rawTheme] or "dark"
end
G.applyOptionTheme = function(rawTheme)
  OPT.bgTransparent = false
  OPT.themeName = G.themeName(rawTheme)
  applyTheme(OPT.themeName)
end

-- Pure palette sampling keeps draft previews out of live telemetry/render state.
G.settingsPalette = function(rawTheme)
  local name = G.themeName(rawTheme)
  local p = G.themeAnchors(name)
  if not p then
    if name == "light" then p={223,236,247, 244,250,255, 0,0,0, 61,88,111, 0,137,224}
    elseif name == "arctic" then p={2,10,21, 7,29,53, 0,0,0, 115,172,208, 26,211,255}
    elseif name == "violet" then p={11,8,19, 25,18,38, 0,0,0, 167,152,184, 181,140,255}
    elseif name == "orange" then p={18,5,0, 62,18,0, 0,0,0, 255,176,92, 255,132,0}
    else p={2,2,2, 10,10,10, 0,0,0, 150,150,150, 230,230,230} end
  end
  return {bg=lcd.RGB(p[1],p[2],p[3]), panel=lcd.RGB(p[4],p[5],p[6]),
    dim=lcd.RGB(p[10],p[11],p[12]), accent=lcd.RGB(p[13],p[14],p[15]),
    text=name=="light" and lcd.RGB(8,27,43) or lcd.RGB(245,245,245)}
end
