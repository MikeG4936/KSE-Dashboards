# OMP Auto contracts

Build the pinned EdgeTX fixture host using [the compiler tooling](../../tools/edgetx/README.md), then run from the repository root:

```sh
python3 tests/omp_auto/run.py --runner ../kse-edgetx-build/edgetx-run
```

The runner instruments temporary copies of both complete dashboards with a test-only `audit` descriptor. Real lifecycle functions and retained render callbacks run at 800×480, 480×320, and 480×272. No production test exports or desktop Lua libraries are required.

The fixture extends the shared behavior/storage mocks with native telemetry slot metadata: `telem1` source IDs advance by three per slot, valid empty slots return tables, raw and calculated sensors remain distinct, and source values report current/fresh flags. Contracts cover:

- Appended option order, preserved original ten slots and additional fuel setting, local counter override without rewriting its saved preference, and manual OMP fallback.
- Exact 49/50-tick confirmation, full LiHV packs with CRSF rounding, partly charged 3S packs, ratio tolerance, invalid ratios and values, stale or noncurrent samples, stopped RPM, candidate interruption, and backwards time.
- Raw CRSF voltage and RPM metadata validation, calculated-name collisions, ambiguous raw sources, valid empty slots, source removal, and rediscovery. Missing or unqualified RPM cannot authorize an aircraft change after flight starts.
- Retained identity during flight or temporary telemetry/link loss; ground class changes, warning/extrema/chemistry resets, timer qualification, theme edits, saved model changes, and explicit mode changes.
- Separate `OMP M1`/`OMP M2` count and image keys, unresolved counter suppression, persistence, and unchanged radio model metadata. Editing only the saved radio display name preserves identity and alerts. Same-class reconfirmation preserves earlier counts and latches, cannot backfill a timer threshold crossed while unresolved, and permits counting again after a timer reset.
- Duplicate ownership, cross-variant takeover, deferred background layout changes, and no RF Tool load, host/queue service, or MSP admission.
- Reproducible Lua instruction observations for the identity helper during acquisition, steady flight, and callbacks inside its 10-tick sampling interval. These include the Lua API mocks and exclude native API time; they measure the helper rather than the complete callback.

These tests establish the exercised Lua behavior with mocked firmware boundaries. They do not establish physical display appearance, native CRSF decoding, RF delivery, real-radio timing, or memory margins.
