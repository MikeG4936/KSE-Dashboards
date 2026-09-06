# Dashboard behavior contracts

These fixtures execute both complete dashboard scripts using the pinned EdgeTX Lua host from [tools/edgetx](../../tools/edgetx/README.md). They require Python 3.9+ and that compiled host; they do not depend on an audit directory or installed desktop Lua.

From the repository root, build the host from the documented EdgeTX checkout, then run:

```sh
python3 tools/edgetx/check.py --edgetx ../kse-edgetx --build-dir ../kse-edgetx-build build
python3 tests/behavior/run.py --runner ../kse-edgetx-build/edgetx-run
```

`--trace-dir ../kse-behavior-traces` saves each variant's observations. Every observation has an expected value, and functional observations must match between KSE4 and KSE5. Intentional palette/theme labels are excluded from cross-variant comparison. To additionally compare before/after extraction, supply a directory with the previous `KSE4/main.lua` and `KSE5/main.lua`:

```sh
mkdir -p ../kse-baseline
git archive BASELINE_COMMIT KSE4/main.lua KSE5/main.lua | tar -x -C ../kse-baseline
python3 tests/behavior/run.py --runner ../kse-edgetx-build/edgetx-run --baseline-dir ../kse-baseline
```

Replace `BASELINE_COMMIT` with the revision being compared. Baselines with the previous local sensor helper names and the extracted `sensors` namespace are supported. Each variant's complete trace, including its 22 theme index/label/color/transparency observations, must match its own baseline. Use a baseline that already implements the current expected contracts: older revisions intentionally fail newly added metadata, freshness, OMP-counter and default-normalization assertions. Baseline mode is optional: a fresh checkout can assert contracts and cross-variant parity without historical files.

The driver creates temporary instrumented copies, replacing only the final widget descriptor with test exports. It adds no exports or helper dependencies to installed dashboards. Fixtures replace `buildUi`/`updateUiState` with minimal rendering stubs; real `create`, `update`, `refresh`, telemetry, alert and counter functions still execute. The repeated-create fixture simulates removing the prior widget by letting its 500-tick lease expire, then exercises the real foreground takeover; it does not bypass ownership checks. The mock supplies explicit current/fresh/absent/nonboolean source flags, counts metadata lookups, and provides time, model metadata, timer inputs, audio/haptic event recording and in-memory files using the public EdgeTX `io` call style. No fixture writes a count file on the host filesystem.

Covered contracts:

- Missing/zero/invalid/thrown sensor samples, cache reuse, next-frame refresh and bounded noncurrent sensor-ID recovery; scalar average-cell voltage, one-based battery profiles, governor enum validity, transmitter voltage and signal normalization.
- Positive and negative metadata-cache expiry at 100 ticks, re-resolution of ARM/Gov/Hspd/RPM on every call, positive/negative cache clearing on session/model reset, explicit boolean current/fresh handling, and legacy display values that cannot prove freshness. Source-discovery helpers wait for the documented TTL; separate boundary assertions verify that metadata remains cached until expiry.
- Fresh motor-stop evidence for Electric RPM, OMP RPM and governor acknowledgement: stale current RPM remains displayed, stale STOP evidence cannot silence alerts, fresh evidence can pause them, and stale hold evidence restores alerts. These are motor-alert tests, separate from ARM-only MSP admission.
- Rotorflight Smart Fuel authority, positive percentage without voltage, USB-only zero versus a powered empty pack, voltage fallback, reserve mapping and absence of a second display filter; OMP M1/M2 cell/chemistry selection and unknown model handling.
- Battery voice thresholds, skipped-threshold behavior, cooldown, low/zero haptics and ROM-backed immediate priority, startup-zero confirmation interrupted by a telemetry gap, delayed dead warning, switch acknowledgement, pack replacement and enabling voice without backlog.
- ESC/BEC persistence, hysteresis and invalid-sample recovery; Nitro low-pack qualification, acknowledgement and rearming.
- Local counter ascending/countdown threshold crossing, one count per cycle, timer reset, attach above threshold, continued counting and malformed timer handling. Counting at the threshold is the existing behavior explicitly preserved by implementation slice 4; this fixture does not implement the older README's reset-time description.
- All ten persisted option slots, default counter selection, legacy duration/Rx voltage formats, reserve normalization, theme-only warning/stat preservation, selective reserve/Rx reset and helicopter-type evidence reset. OMP uses the local counter while retaining the saved FC preference for restoration in Electric mode. Applying nil options restores descriptor defaults, including 20% reserve and valid 6.6/8.4 V receiver-pack limits.

These are baseline contracts, not a transmitter or RF simulator. They do not validate packet ownership, MSP transactions, profile-write safety, firmware queue consumption, filesystem failure recovery, retained heap, radio scheduling, instruction budgets, layout, voice file contents. Physical haptic timing/backlog behavior still requires a radio test. MSP admission, upstream transaction ownership, and stronger transport claims require their separate regression suites; these motor-alert freshness tests do not establish MSP behavior. Existing unsafe behavior is not asserted as a desired contract.
