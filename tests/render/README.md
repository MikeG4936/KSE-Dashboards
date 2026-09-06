# Render-function smoke contracts

Run from the repository root with the EdgeTX Lua runner described in [compiler tooling](../../tools/edgetx/README.md):

```sh
python3 tests/render/run.py --runner /path/to/edgetx-run
```

Both deployed dashboard files execute their real create/update/refresh/background functions. The test covers 22 themes × three helicopter modes × three resolutions (800×480, 480×320, 480×272), or 396 combinations across both dashboards. It verifies ten option slots, retained object construction, nonnegative dimensions, and evaluation of dynamic LVGL property callbacks. Warm refresh work must stay below the project's 15,000-instruction margin.

The LVGL object API, telemetry, files and radio are mocks. RF Tool is not loaded. This catches missing renderer references and invalid callback/property operations after assembly; it does not establish visual fidelity, native LVGL allocation/cost, actual RF latency or transmitter memory. Use the separate picker contracts for dialog/native-menu geometry and the README's radio checks for physical validation.
