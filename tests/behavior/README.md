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

Replace `BASELINE_COMMIT` with the revision being compared. Baselines with the previous local sensor helper names and the extracted `sensors` namespace are supported. Each variant's complete trace, including its 22 theme index/label/color/transparency observations, must match its own baseline. Baseline mode is optional: a fresh checkout can assert contracts and cross-variant parity without historical files.

The driver creates temporary instrumented copies, replacing only the final widget descriptor with test exports. It adds no exports or helper dependencies to installed dashboards. Option-update fixtures replace the renderer's `buildUi` with a no-op; real `create`, `update`, telemetry, alert and counter functions still execute. The mock supplies current/invalid sensors, time, model metadata, timer inputs, audio/haptic event recording and in-memory files using the public EdgeTX `io` call style. No fixture writes a count file on the host filesystem.

Covered contracts:

- Missing/zero/invalid/thrown sensor samples, cache reuse, next-frame refresh and noncurrent sensor-ID recovery; scalar average-cell voltage, one-based battery profiles, governor enum validity, transmitter voltage and signal normalization.
- Rotorflight Smart Fuel authority, positive percentage without voltage, USB-only zero versus a powered empty pack, voltage fallback, reserve mapping and absence of a second display filter; OMP M1/M2 cell/chemistry selection and unknown model handling.
- Battery voice thresholds, skipped-threshold behavior, cooldown, low/zero haptics, startup-zero confirmation interrupted by a telemetry gap, delayed dead warning, switch acknowledgement, pack replacement and enabling voice without backlog.
- ESC/BEC persistence, hysteresis and invalid-sample recovery; Nitro low-pack qualification, acknowledgement and rearming.
- Local counter ascending/countdown threshold crossing, one count per cycle, timer reset, attach above threshold, continued counting and malformed timer handling. Counting at the threshold is the existing behavior explicitly preserved by implementation slice 4; this fixture does not implement the older README's reset-time description.
- All ten persisted option slots, default counter selection, legacy duration/Rx voltage formats, reserve normalization, theme-only warning/stat preservation, selective reserve/Rx reset and helicopter-type evidence reset.

These are baseline contracts, not a transmitter or RF simulator. They do not validate packet ownership, MSP transactions, profile-write safety, firmware queue consumption, filesystem failure recovery, retained heap, radio scheduling, instruction budgets, layout, voice file contents or actual haptic priority. In particular, haptic event timing/count assertions deliberately omit the known ROM `PLAY_NOW` lookup defect. Safety freshness/contradiction policy and other accepted fixes need their own expected-success regressions as those slices are implemented; existing unsafe behavior is not asserted as a desired contract.
