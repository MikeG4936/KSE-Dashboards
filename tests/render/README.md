# Render-function smoke contracts

Configuration in these domain fixtures enters through the explicit test-only [saved-settings helper](../behavior/settings_fixture.lua). It seeds an in-memory per-model record using the production schema/defaults and calls the real `create(zone)` callback; transitions use the owner-guarded `G.updateSettings` engine boundary. The helper replaces only settings attachment and the native-editor API requirement so these radio/RF/renderer mocks need no fake editor support. It never repurposes native `create`/`update` option payloads. The [settings suite](../settings/README.md) covers the actual editor and persistence path.

Run from the repository root with the EdgeTX Lua runner described in [compiler tooling](../../tools/edgetx/README.md):

```sh
python3 tests/render/run.py --runner /path/to/edgetx-run
```

Both deployed dashboard files execute their real create/update/refresh/background functions. The test covers 22 themes × three resolved helicopter modes (Electric, Nitro, OMPHOBBY) × three resolutions (800×480, 480×320, 480×272), or 396 combinations across both dashboards. It verifies the empty native descriptor, retained object construction, nonnegative dimensions, and evaluation of dynamic LVGL property callbacks. OMP rendering starts only after real lifecycle confirmation of public RxBt/Volt CRSF metadata using the [shared source fixture](../behavior/omp_sources.lua); the radio model name does not select its aircraft. Warm refresh work must stay below the project's 15,000-instruction margin.

The LVGL object API, telemetry, files and radio are mocks. RF Tool is not loaded. This catches missing renderer references and invalid callback/property operations after assembly; it does not establish visual fidelity, native LVGL allocation/cost, actual RF latency or transmitter memory. Use the separate picker contracts for dialog/native-menu geometry and the README's radio checks for physical validation.

An additional OMP render runs before voltage confirmation. Both unresolved and confirmed retained text must omit the retired instruction to add M1/M2 to the radio model name.

Temporary test exports also expose the retained transmitter-battery objects. Both variants must use native default colors under dark/light themes, map the expected native fill fraction to their vertical height, remain bottom-anchored, and hide the fill at empty or unavailable voltage. The production dashboards contain no test exports.

The five retained signal bars are checked under dark/light themes for native threshold decisions, foreground/inactive colors, height proportions, common baseline, readable widths/gaps, and separation from the battery and profile label. Named `RQly` stays at 100 while the native radio RSSI is varied, catching accidental reuse of the wrong source.

Pass `--preview-dir /path/to/previews` to save SVG crops built from actual retained rectangle properties at three and five bars for each resolution/theme/variant. These previews are reproducible geometry evidence, not native LVGL rasterization or physical-radio readability validation. Font metrics and antialiasing are outside their scope.
