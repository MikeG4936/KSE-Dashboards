# RF trace characterization

This tool compares 14 transaction traces before and after structural changes. It uses the actual queue, helper and status/flight-stat APIs from Rotorflight Lua commit `aaacfe68407c09d49a26c5aa326c00119b378bb0`, loaded from a supplied Git checkout. The common transport and radio callbacks are mocked. No upstream source is vendored or loaded from an undocumented audit directory.

```sh
python3 tests/rf_trace/run.py --runner ../kse-edgetx-build/edgetx-run --rf-source ../rotorflight-lua-scripts --baseline-dir ../kse-baseline
```

Build the runner using [the compiler instructions](../../tools/edgetx/README.md). Prepare the baseline tree as described in [the behavior fixtures](../behavior/README.md). Each baseline must contain `KSE4/main.lua` and `KSE5/main.lua`.

The cases cover both variants, Electric/Nitro and both counters while armed, OMP with the local counter, selection queued before arming, and a flight-stat read queued before arming. Traces record command, mock time and host state at the mocked common transport's send entry point. Synthetic replies test queue progression, not firmware acceptance or actual air packets.

**An unchanged result is not a flight-safety pass.** The original baseline includes armed status polling and queued writes continuing after arming. This comparison is for behavior-preserving extraction only; intentional RF fixes must replace it with the corresponding expected-safe send-boundary contracts. It does not test private TX fragmentation, independent RF Tool callbacks, mixed receive frames or real-radio scheduling.
