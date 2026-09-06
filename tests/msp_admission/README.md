# KSE MSP admission regressions

These tests exercise the current KSE4/KSE5 admission policy using the actual unmodified Rotorflight `mspQueue`, `mspHelper`, `mspStatus` and `mspFlightStats` modules from commit `aaacfe68407c09d49a26c5aa326c00119b378bb0`. The driver reads that exact commit with `git show`; it does not use possibly modified working-tree copies or vendor upstream code.

Build the EdgeTX v2.12.1 fixture host using [tools/edgetx](../../tools/edgetx/README.md), then run from the repository root:

```sh
python3 tests/msp_admission/run.py --runner ../kse-edgetx-build/edgetx-run --rf-source ../rotorflight-lua-scripts
```

The RF checkout must contain the pinned commit. Python 3.9+, Git and the compiled EdgeTX host are required; no temporary audit directory is required. Instrumented dashboard copies and extracted upstream modules are generated in a temporary directory and removed after the run. No production files or RF Tool installation are changed.

The driver exposes the private controller entry points and admission module from both complete scripts. Foreground/background controller behavior is exercised through `allowUi=true/false`; prompt/banner rendering helpers are replaced with no-ops. The mock supplies sensor IDs and explicit value/current/fresh metadata, time, model identity, RF host state, common MSP transport and synthetic replies. The real upstream queue performs request selection, retries and callback dispatch. The full RF Tool widget/background implementation, byte framing and LVGL are not executed.

Covered contracts:

- All four admission entry points deny armed requests and admit settled ground requests, including both profile-selection and active-capacity operations.
- Ground requires 40 ticks of stable evidence: fresh/current ARM with bit zero clear, recognized governor stop state and zero headspeed, a live radio link and suitable RF host/widget state. Missing, stale, fractional, malformed and contradictory inputs deny admission; a reused sensor ID cannot retain an old safe ARM value.
- Electric/Nitro, both counters, and both foreground/background controller paths generate no new KSE requests during long armed intervals. Diagnostics and automatic selection of the single configured profile resume after stable ground; automatic selection remains blocked while armed.
- Cancellation removes only exact owned pending objects. Foreign objects, pending-table identity, upstream queue method identities, retry limits and transport buffers remain intact.
- Profile selection admits 176 first; its ACK only stages 175, and matching verification only stages 250. A later KSE pass must admit each successor. Arming between these stages prevents the successor; a complete ground sequence saves the selected profile.
- Provider, queue, host-widget, model filename and helicopter-type changes invalidate prior work. Models with identical display names but different filenames are distinguished. An observed unsafe condition changes the operation epoch even when ground returns before the next KSE service; stale/duplicate callbacks cannot revive old work. Both direct ground observations and callback-only observations are exercised.
- Reset discards owned pending work and invalidates callbacks. Nitro deadlines release KSE operation tracking while leaving an active upstream message alone; its eventual ACK drains naturally without restoring the expired operation.

The stop-state policy uses Gov 0/5/7 only in combination with fresh disarmed ARM and zero Hspd. Gov 5 or 7 alone is not proof of safe ground. The pinned Rotorflight firmware [governor implementation](https://github.com/rotorflight/rotorflight-firmware/blob/118e9120260bb33f46df4f92052fb0e9fd4e9ebc/src/main/flight/governor.c#L728-L754) forces the off state when disarmed; the [state enum](https://github.com/rotorflight/rotorflight-firmware/blob/118e9120260bb33f46df4f92052fb0e9fd4e9ebc/src/main/flight/governor.h#L27-L37) distinguishes off from idle. The fixture explicitly rejects Gov 1.

## Accepted transport boundary

**Admission control does not guarantee zero in-flight MSP.** An already-current RF Tool request retains upstream ownership, including its default unlimited retries. A fixture deliberately observes command 176 sent on the ground and retried after arming, while confirming that KSE invalidates its callback and admits no successor. The queue's [default retry limit](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/MSP/mspQueue.lua#L7-L15) and retry processing remain unchanged. New KSE work waits for the queue to become idle naturally; it does not intercept RF transport or clear framing buffers.

The suite reports this carryover as `LIMIT`, not a flight-safety success. It validates the accepted policy of leaving RF Tool untouched while restricting new KSE admission. It does not establish radio memory/timing, RC latency, over-the-air request attribution, firmware acceptance of writes, independence of other RF Tool consumers, or safety between observations. The older [RF trace characterization](../rf_trace/README.md) intentionally includes pre-fix armed admissions and is not an unchanged-trace acceptance test for this behavior change.

When the fixture host supplies `measure(fn, ...)`, three isolated controller scenarios report Lua instruction counts and assert fewer than 15,000 instructions: armed service, ground service and selection continuation. RF host/background and LVGL are mocked; these figures are not full-widget radio callback measurements. Without that hook, the suite explicitly reports that those resource scenarios were skipped.
