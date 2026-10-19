# Combined RF Tool callback CPU regressions

This suite executes the complete KSE4/KSE5 callbacks with the actual pinned RF Tool startup, queue, CRSF transport and CUSTOM decoder. Its default measurement includes dashboard **and RF Lua instructions**, while excluding the Lua implementations of mocked native APIs. It complements the dashboard-only [CPU suite](../cpu_budget/README.md) and the detailed [MSP admission contracts](../msp_admission/README.md).

## Reproduce from a fresh checkout

Requirements are Python 3.9+, Git and the pinned EdgeTX fixture host; no Python packages or desktop Lua installation are needed. Build and self-test that host using [tools/edgetx](../../tools/edgetx/README.md). Supply a Git repository containing Rotorflight Lua commit `aaacfe68407c09d49a26c5aa326c00119b378bb0`, for example:

```sh
git clone --no-checkout https://github.com/rotorflight/rotorflight-lua-scripts.git ../kse-rf-lua
python3 tools/edgetx/check.py --edgetx ../kse-edgetx --build-dir ../kse-edgetx-build build
python3 tools/edgetx/self_test.py --edgetx ../kse-edgetx --build-dir ../kse-edgetx-build
python3 tests/rf_cpu/run.py --runner ../kse-edgetx-build/edgetx-run --rf-source ../kse-rf-lua --json output/rf-cpu.json
```

The driver extracts the exact commit with `git archive`; modified working-tree files are ignored. It executes the pinned official [`bin/minimize.lua`](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/bin/minimize.lua) unchanged using the EdgeTX host and virtual desktop file APIs. This applies the release transformations, including `rf2.call` → `pcall`, debug/simulator-code removal and indexed sensor tables. `minimize.py` adapts file access only; it does not approximate the replacements. The original manifest is processed in the same order as upstream [`bin/build.sh`](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/bin/build.sh). Subsequent manifest regeneration and first-install compilation are outside this already-installed fixture.

All generated files live in a temporary directory unless `--artifacts output/rf-cpu-fixtures` requests retained sources, fixtures and logs. JSON records source hashes, the exact minimizer hash, transformed-file hashes, every measured callback and failures. No audit output directory, personal path, RF working tree, or radio installation is required or changed.

## Gates and callback boundaries

Default execution runs eight scenarios for both dashboards at 800×480. Every production `create`, `update` and `refresh` runs separately under a **20,200 instruction hard hook**. Every save callback, including the open-picker overlap, also has a **15,000 combined-instruction target**. Loads and saves advance through further ordinary refresh callbacks; the test never drains a storage job synchronously inside a measured callback. Completion verifies the exact full CSV, one qualified increment and the original backup.

The LVGL boundary evaluates dynamic properties during construction and after update/refresh, including all six profile-button `active` checks. Visibility runs first; hidden objects skip their other display properties. Event functions such as `press` and `close` are never evaluated as display properties. The P6 press is deliberately invoked as a separate event and measured without a budget gate because the native event budget boundary has not been established. Selection, verification and save continuations run under the ordinary refresh gate.

Six-profile popup construction remains above the 15,000 project margin: the initial minimized-source burst measured 18,375 KSE4 / 18,661 KSE5. These callbacks remain subject to the 20,200 hard hook. This is an explicit remaining margin limitation, not a reason to cache current ARM values or weaken any button's admission check. Broader screen sizes and themes are covered by the dashboard-only suite; their complete RF overlap still needs separate characterization.

The open-picker save case peaks at 14,546/14,810 during the staged save, including a status-101 reply, CUSTOM decoding and retained button safety checks. Its construction callback peaks at 18,298/18,581. The save passes the 15,000 target; construction retains the documented hard-hook-only gate.

## Covered behavior

- Fresh embedded RF startup discovers the protocol, loads the actual tasks, obtains API/name/telemetry configuration, initializes the real sensor decoder and enables the adjustment-announcement task. Both quiet startup and a bounded valid telemetry backlog are covered.
- Six configured profiles open the actual retained picker. P6 selection must send zero-based index 5, followed in order by 175 verification, 250 EEPROM save and 130 active capacity read. The final profile must be confirmed and no longer busy.
- Four valid CUSTOM frames run through the real decoder. Payloads are 58 and 26 bytes and include the six-byte adjustment payload. FIFO accounting includes per-frame overhead; the observed maximum is 236 bytes against the verified 256-byte capacity. A new batch is queued only after the existing FIFO drains. Synthetic MSP replies arrive on the following 200 ms callback.
- Lost command-175 and command-176 replies exercise actual upstream retries beyond KSE's snapshot/selection timeouts. The same active request must survive with the unlimited upstream retry policy, and an unrelated message queued behind it must remain intact. MSP polling consumes non-MSP frames while waiting for replies, so these scenarios do not claim simultaneous CUSTOM decoding on every retry callback.
- Local-counter saves use actual timer qualification after loading a valid 200-row history. Both a normal 1,737-byte file and an exact 32,768-byte file with an existing backup are covered. Four CUSTOM frames continue to arrive during the staged save. A matched quiet-save control suppresses that traffic only during qualification/save. All counts and the backup must survive unchanged apart from the one qualified increment.
- A further exact-limit save starts in Local mode, loads the history, then qualifies a real timer crossing while all six profile buttons remain open. The dialog must stay open throughout persistence, all counts/backup must remain correct, and no profile-176 write may occur without selection. This exercises sustained overlap with current ARM checks rather than injecting a dirty flag or pausing RF work.

Radio APIs, native filesystem/LVGL, telemetry production and receiver replies are mocks. The source execution itself includes RF `app.lua`, `rf2.lua`, initialization/background, MSP APIs, queue, fragmentation/reassembly, CRSF polling, CUSTOM decoding and adjustment-announcement servicing. The private RF UI runner loads but is correctly not serviced by KSE's `background(true)`. The generated compilation marker returns true, and a settings file enables adjustment announcements.

## Baselines and attribution

For a frozen baseline, put the uninstrumented dashboard sources in a directory as `KSE4.lua` and `KSE5.lua`, then pass `--source-dir path/to/baseline`. `--measure-only` removes instruction gates while retaining all functional assertions. `--cases` and `--variants` select bounded subsets. `--save-target 0` removes only the project save target; the 20,200 hard hook remains.

```sh
python3 tests/rf_cpu/run.py --runner ../kse-edgetx-build/edgetx-run --rf-source ../kse-rf-lua --source-dir path/to/baseline --measure-only --json output/rf-cpu-baseline.json
python3 tests/rf_cpu/run.py --runner ../kse-edgetx-build/edgetx-run --rf-source ../kse-rf-lua --modes combined dashboard rf all --json output/rf-cpu-attribution.json
```

`combined` assigns both dashboard and real RF chunks the measured source label. `dashboard` and `rf` independently attribute their components, and the driver checks that their sum exactly equals each matching combined callback. `all` also counts Lua mocks; those totals are diagnostic only and are never used as radio-failure evidence. Gated runs require `combined`. `--raw-rf` is available for an explicitly raw-source comparison; official minimized source is the acceptance default.

The frozen `569675a` baseline reproduces all four traffic-save hard failures: KSE4/KSE5 normal saves use 20,545/20,809 instructions, and exact-limit saves use 20,823/21,087. The open-picker baseline also fails the hard hook in both variants. The staged-save implementation uses batches of 12 entries while loading retains 24-line batches. It completes both sizes over 37 callbacks, with save peaks 12,119/12,383 after selection and 14,546/14,810 while the picker remains open. The final attribution run checks 1,306 complete combined callback measurements against their independent components. These figures describe the recorded fixture sequence; the executable gates, not fixed expected counts, enforce future behavior.

## Limits and source authorities

This establishes source-filtered CPU and behavior regressions in the pinned EdgeTX Lua host. It does not reproduce the native firmware scheduler, allocator, complete LVGL implementation, SD timing/durability, installed bytecode package or physical RF transport. Four queued CUSTOM frames are a legal synthetic backlog, not a measured radio capture. First-install compilation, external RF Tool widget coexistence, RF configuration pages and changing adjustment announcements remain outside this suite. Radio acceptance still needs fresh startup, all six profiles, P6 verification/save, delayed replies and local counting under actual traffic; see [transmitter validation](../../docs/transmitter-validation.md).

Relevant pinned authorities are [EdgeTX widget budget](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/lua/widgets.cpp#L37-L75), [post-refresh property dispatch](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/lua/lua_widget.cpp#L294-L318), RF [embedded background dispatch](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/WIDGETS/RfTool/app.lua#L279-L323), [decoder initialization](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/background.lua#L69-L95), [CUSTOM draining](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/rf2tlm.lua#L54-L56) and [CRSF MSP polling](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/MSP/crsf.lua#L17-L38). The [confirmed-disarm policy](../../docs/compatibility.md#rf-admission-policy) remains unchanged.
