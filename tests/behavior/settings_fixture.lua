-- TEST ONLY: inject saved-menu configuration at the storage/attachment boundary.
-- The domain suites do not emulate the native editor or write configuration files.
-- Real create/update callbacks keep their production signatures: no option payload
-- is translated into settings. tests/settings exercises the actual persistence UI.
local FixtureSettings = {}
_G.__KSE_FIXTURE_SAVED = _G.__KSE_FIXTURE_SAVED or {}
local function fixtureModel()
  local ok, info = pcall(model.getInfo)
  local filename = ok and type(info)=="table" and info.filename or nil
  return type(filename)=="string" and filename~="" and filename
         or "missing-fixture-filename.yml"
end
function FixtureSettings.defaults()
  return SettingsStore.defaults()
end
function FixtureSettings.seed(values)
  local key = fixtureModel()
  local record = SettingsStore.make(key, G.name, values, _G.__KSE_FIXTURE_SAVED[key])
  _G.__KSE_FIXTURE_SAVED[key] = record
  return record
end
-- These suites isolate domain behavior from the separate native-API gate.
SettingsMenu.requirement = function() return false end
SettingsMenu.attach = function(widget)
  local record = _G.__KSE_FIXTURE_SAVED[fixtureModel()]
  widget.kseSettingsCapable = false
  widget.kseConfig = {record=record, writable=false}
  return SettingsStore.effective(record, G.name)
end
function FixtureSettings.create(zone, values)
  FixtureSettings.seed(values or FixtureSettings.defaults())
  return create(zone)
end
function FixtureSettings.apply(widget, values)
  if not WidgetOwner.current(widget) then return false end
  FixtureSettings.seed(values)
  G.updateSettings(widget, SettingsStore.capture(values))
  return true
end
FixtureSettings.themes = G.settingsThemes
FixtureSettings.heliTypes = SettingsStore.heliTypes
