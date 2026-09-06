G.applyOptionTheme = function(rawTheme)
  local themeNames = {
    [1]="dark", [2]="light", [3]="arctic", [4]="violet",
    [5]="orange", [6]="red", [7]="blue", [8]="pink",
    [9]="green", [10]="purple", [11]="reef", [12]="royal",
    [13]="ember", [14]="graphite", [15]="glacier", [16]="sunset",
    [17]="synthwave", [18]="gulf", [19]="voltage",
    [20]="titanium_ember", [21]="aurora", [22]="desert_night",
  }
  OPT.bgTransparent = false
  OPT.themeName = themeNames[rawTheme] or "dark"
  applyTheme(OPT.themeName)
end
