# KSE MSP admission regressions

These tests exercise the current KSE4/KSE5 admission policy using the actual unmodified Rotorflight `mspQueue`, `mspHelper`, `mspStatus` and `mspFlightStats` modules from commit `aaacfe68407c09d49a26c5aa326c00119b378bb0`. The driver reads that exact commit with `git show`; it does not use possibly modified working-tree copies or vendor upstream code.

Build the EdgeTX v2.12.1 fixture host using [tools/edgetx](../../tools/edgetx/README.md), then run from the repository root:

```sh
python3 tests/msp_admission/run.py --runner ../kse-edgetx-build/edgetx-run --rf-source ../rotorflight-lua-scripts
```

The RF checkout must contain the pinned commit. Python 3.9+, Git and the compiled EdgeTX host are required; no temporary audit directory is required. Instrumented dashboard copies and extracted upstream modules are generated in a temporary directory and removed after the run. No production files or RF Tool installation are changed.

The driver exposes the private controller entry points, admission and widget-owner modules from both complete scripts. Each independent setup resets the global registry before loading the dashboard and claims its synthetic widget through the actual owner API. Queue-driving cases explicitly register the mock host as embedded. Foreground/background controller behavior is exercised through `allowUi=true/false`; prompt/banner rendering helpers are replaced with no-ops. The mock supplies sensor IDs and explicit value/current/fresh metadata, time, model identity, RF host state, common MSP transport and synthetic replies. The real upstream queue performs request selection, retries and callback dispatch. The full RF Tool widget/background implementation, byte framing and LVGL are not executed.

Covered contracts:

- KSE does not drive an external RF host or its queue. Its registered embedded host still receives `background(true)` while requests are pending and after queue faults; failures remain visible.
- All four admission entry points deny armed requests and admit requests immediately with valid disarmed ARM, including both profile-selection and active-capacity operations.
- Admission requires fresh/current valid ARM with bit zero clear, a live radio link and suitable RF host/widget state. It adds no settling delay. Missing, stale, fractional, malformed or contradictory ARM/connection inputs deny admission; a reused sensor ID cannot retain an old disarmed ARM value.
- Gov and Hspd are not admission inputs. Every entry path accepts disarmed ARM with missing, stale, running, invalid or throwing Gov/Hspd sources; the same cases with armed ARM are denied. Lookup/read counters assert that admission never consults Gov or Hspd.
- Electric/Nitro, both counters, and both foreground/background controller paths generate no new KSE requests during long armed intervals. Diagnostics and automatic selection of the single configured profile resume after disarming; automatic selection remains blocked while armed.
- Cancellation removes only exact owned pending objects. Foreign objects, pending-table identity, upstream queue method identities, retry limits and transport buffers remain intact.
- Profile selection admits 176 first; its ACK only stages 175, and matching verification only stages 250. A later KSE pass must admit each successor. Arming between these stages prevents the successor; a complete disarmed sequence saves the selected profile.
- Provider, queue, host-widget, model filename and helicopter-type changes invalidate prior work. Models with identical display names but different filenames are distinguished. An observed unsafe condition changes the operation epoch even when disarmed ARM returns before the next KSE service; stale/duplicate callbacks cannot revive old work. Both direct admission observations and callback-only observations are exercised.
- Reset discards owned pending work and invalidates callbacks. Nitro deadlines release KSE operation tracking while leaving an active upstream message alone; its eventual ACK drains naturally without restoring the expired operation.

## Accepted transport boundary

**Admission control does not guarantee zero in-flight MSP.** An already-current RF Tool request retains upstream ownership, including its default unlimited retries. A fixture deliberately observes command 176 sent while disarmed and retried after arming, while confirming that KSE invalidates its callback and admits no successor. The queue's [default retry limit](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/MSP/mspQueue.lua#L7-L15) and retry processing remain unchanged. New KSE work waits for the queue to become idle naturally; it does not intercept RF transport or clear framing buffers.

The suite reports this carryover as `LIMIT`, not a flight-safety success. It validates the accepted policy of leaving RF Tool untouched while restricting new KSE admission. It does not establish radio memory/timing, RC latency, over-the-air request attribution, firmware acceptance of writes, independence of other RF Tool consumers, or safety between observations. The older [RF trace characterization](../rf_trace/README.md) intentionally includes pre-fix armed admissions and is not an unchanged-trace acceptance test for this behavior change.

When the fixture host supplies `measure(fn, ...)`, three isolated controller scenarios report Lua instruction counts and assert fewer than 15,000 instructions: armed service, disarmed service and selection continuation. RF host/background and LVGL are mocked; these figures are not full-widget radio callback measurements. Without that hook, the suite explicitly reports that those resource scenarios were skipped.
