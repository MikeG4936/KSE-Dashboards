# Complete callback CPU regressions

Build the pinned EdgeTX fixture host through the shared compiler tooling, then run:

```sh
python3 tools/edgetx/check.py --edgetx ../kse-edgetx --build-dir ../kse-edgetx-build build
python3 tools/edgetx/self_test.py --edgetx ../kse-edgetx --build-dir ../kse-edgetx-build
python3 tests/cpu_budget/run.py --runner ../kse-edgetx-build/edgetx-run --json output/cpu-budget.json
```

Both generated dashboards run at 800×480, 480×320 and 480×272. A further KSE4 case uses a real 700×400 zone on the 800×480 display. The fixture exposes selected state for assertions but replaces no production lifecycle, telemetry, storage, ownership or rendering functions. Only radio APIs, storage, LVGL objects and RF transport boundaries are mocked. The tests load the actual default-image header and retain its real size. Distinct opaque alignment flags use EdgeTX's ROM-style lookup so zero fallbacks cannot hide alignment regressions.

Each `create`, `update`, `refresh` and `background` invocation is measured separately. Creation evaluates dynamic object properties; update and refresh also dispatch the retained display properties after the callback, matching the relevant native callback boundary. Visibility is evaluated first, hidden objects skip other display properties, and event handlers such as `press` and `close` are never invoked as display properties. There is no synchronous test-only draining of history work inside a measured callback: subsequent work must run through further ordinary background/refresh calls.

The gate is at most **15,000 dashboard instructions per callback**, with a separate hard **20,200-instruction** failure. `measureSource` counts instructions from the exact instrumented dashboard filename, excluding Lua mocks. Its host self-test verifies exact matching, mock exclusion, nested measurement rejection, restoration after errors, and rejection of budget errors caught by an inner `pcall`. `--measure-only` is available for recording an ungated baseline; `--source-dir` accepts frozen `KSE4.lua` and `KSE5.lua` files for before/after reproduction.

The four regression families are:

- Fresh Auto Electric and Nitro confirmation followed by Electric↔Nitro transitions, including the retained KSE4 caption/footer and hidden-to-visible handoff before the next telemetry sample. These run under the default theme and Theme 9; the existing rendering suite covers all 22 palettes.
- Recreated saved-model ownership with 20 and 200 history entries. Complete history and the selected model's count must eventually appear without rewriting the file.
- Rotorflight→Local counting with 200 entries, including an exact 32,768-byte file and a separate exact 32,768-byte file containing 16,000 comment lines. Every loading callback includes the ordinary foreground/render work. Fresh Rotorflight mode must perform no history I/O; switching must load the complete history without modifying it.
- Late corruption after 200 valid main-file entries followed by a valid 200-entry backup. Recovery must retain all counts, show the warning, remain read-only, and preserve both original files.

An additional loading/handoff scenario qualifies a real timer crossing while a 200-entry history is loading, changes to Rotorflight counting, then transfers ownership to a new saved model. The pending count must survive, apply once after validation, and persist in a later background callback while preserving the backup. Getters/display-property dispatch cannot start history I/O. Partial parsed history cannot become visible or writable; loading alone must not produce a storage-error warning.

The partial-zone case checks actual retained KSE4 objects through Electric→Nitro→Electric. AMPS and ESC values must return from centered Nitro placeholders to ordinary noncompact left alignment; all five Electric footer labels must regain visibility with unchanged coordinates and alignment. It runs under the default theme and Theme 9. The complete suite contains 68 scenarios across the display/theme combinations.

These counts establish a dashboard-code margin for the exercised callback sequences. RF Tool Lua instructions, native API time, allocator behavior and complete firmware rendering are outside the source-filtered measurement. Radio validation remains required; see the [EdgeTX host limitations](../../tools/edgetx/README.md) and [transmitter validation](../../docs/transmitter-validation.md). EdgeTX v2.12.4's nominal widget budget and post-refresh property dispatch are defined in [widgets.cpp](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/lua/widgets.cpp#L37-L75) and [lua_widget.cpp](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/lua/lua_widget.cpp#L294-L318).
