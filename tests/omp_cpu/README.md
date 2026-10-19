# OMP Auto callback CPU and retained UI regressions

Use the pinned EdgeTX fixture host from the [compiler tooling](../../tools/edgetx/README.md):

```sh
python3 tools/edgetx/check.py --edgetx ../kse-edgetx --build-dir ../kse-edgetx-build build
python3 tools/edgetx/self_test.py --edgetx ../kse-edgetx --build-dir ../kse-edgetx-build
python3 tests/omp_cpu/run.py --runner ../kse-edgetx-build/edgetx-run --json output/omp-cpu.json
```

The suite runs both generated dashboards at 800×480, 480×320 and 480×272, with both native telemetry-slot bounds. Pinned EdgeTX 2.12.4 exposes **75 slots for STM32H7 color boards and 60 for other color boards** ([definitions](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/dataconstants.h#L53-L56)). In-range empty slots return metadata tables; only an out-of-range sensor returns nil ([model.getSensor](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/lua/api_model.cpp#L1746-L1772)). OMP's duplicate-source check therefore scans the full native bound even with few discovered sensors.

Each complete `create`, `update`, `refresh` and `background` invocation must use at most **15,000 dashboard VM instructions**, with a separate **20,200-instruction hard gate**. The suite reuses the [complete callback fixture](../cpu_budget/README.md): dynamic object properties run at construction and once after visible update/refresh, visibility precedes other properties, and event handlers do not run during display evaluation. This follows the native [constructor/set boundary](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/lua/lua_lvgl_widget.cpp#L751-L762) and [foreground/update dispatch](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/lua/lua_widget.cpp#L294-L397). Exact-source filtering counts production dashboard functions and excludes Lua boundary mocks. No production lifecycle, renderer, storage or identity function is replaced.

Thirteen scenarios at each variant/geometry/slot combination give **156 cases**:

- Fresh M1 and M2 identification, including connection before create/update and the real default-image header and size.
- M1→M2→M1 transitions in foreground and background, under the default theme and Theme 9. All retained object references, the title/image coordinates and dimensions must stay unchanged. The visible title, distinct `/IMAGES/OMP M1.png` and `/IMAGES/OMP M2.png` paths, cell-count footer, chemistry and separate saved counts must update.
- Same-class reconnection in foreground and background. Disconnect retains the previous name/image and suspends count attribution. Same-class reconfirmation preserves warning/extrema evidence; a changed class resets it. A timer threshold crossed while unresolved cannot be credited after confirmation. Hidden confirmation must update the retained UI on a one-tick foreground return without waiting for another telemetry sample.
- A pending save of a **200-entry, exact 32,768-byte history**, qualified by an actual M1 timer crossing. A temporary-file-open failure establishes the real retry deadline. Retry is aligned with M2 acquisition or confirmation, in foreground or background. Further measured callbacks must finish persistence, preserve the original backup, retain all counts, and attribute exactly one increment to M1. Tests wait for observable completion without depending on a particular number of save phases.

Every case checks that OMP does not invoke RF host service, queue processing, RF Tool loading or MSP admission. The saved OMP Auto and counter choices remain unchanged while the effective counter is local, and the saved transmitter model identity is untouched. The separate [OMP identity suite](../omp_auto/README.md) covers source freshness, ambiguity, tolerance and connection-lock edge cases.

For before/after reproduction, `--source-dir` accepts frozen `KSE4.lua` and `KSE5.lua` files. The JSON records their source hashes and every callback measurement. `--measure-only` disables CPU gates while keeping semantic assertions; `--target 0` disables only the 15,000 margin gate. A historical implementation that rebuilt on class confirmation also fails the retained-object assertions, even when its CPU gate is disabled.

The initial saved-model preparation may still construct UI. The retained-object contract starts after that preparation and concerns M1/M2 class confirmation; it does not remove saved-model, geometry or option rebuilds.

These are source-instruction and semantic regressions. Native image decoding, I/O and rendering time, allocator behavior, whole-radio memory and actual telemetry packet timing require [transmitter validation](../../docs/transmitter-validation.md). Valid image headers and preserved byte size do not model native PNG decoding. OMP intentionally performs no RF Tool work; the source-filtered budget is not evidence about mixed Rotorflight callbacks.
