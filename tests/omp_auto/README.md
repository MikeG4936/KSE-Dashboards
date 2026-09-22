# OMPHOBBY automatic identification contracts

Configuration in these domain fixtures enters through the explicit test-only [saved-settings helper](../behavior/settings_fixture.lua). It seeds an in-memory per-model record using the production schema/defaults and calls the real `create(zone)` callback; transitions use the owner-guarded `G.updateSettings` engine boundary. The helper replaces only settings attachment and the native-editor API requirement so these radio/RF/renderer mocks need no fake editor support. It never repurposes native `create`/`update` option payloads. The [settings suite](../settings/README.md) covers the actual editor and persistence path.

Build the pinned EdgeTX fixture host using [the compiler tooling](../../tools/edgetx/README.md), then run from the repository root:

```sh
python3 tests/omp_auto/run.py --runner ../kse-edgetx-build/edgetx-run
```

The runner instruments temporary copies of both complete dashboards with a test-only `audit` descriptor. Real lifecycle functions and retained render callbacks run at 800×480, 480×320, and 480×272. No production test exports or desktop Lua libraries are required.

The fixture extends the shared behavior/storage mocks with native telemetry slot metadata: `telem1` source IDs advance by three per slot, valid empty slots return tables, raw and calculated sensors remain distinct, and source values report current/fresh flags. Contracts cover:

- An empty native descriptor and four-choice helicopter-type menu order/default, local counter override without rewriting its saved preference, and normalization of existing saved OMP IDs to the single automatic OMPHOBBY mode. Radio names never substitute for missing voltage evidence; equivalent OMP settings preserve a confirmed session, while leaving and reentering OMP requires fresh confirmation.
- Exact 49/50-tick confirmation, full LiHV packs with CRSF rounding, partly charged 3S packs, ratio tolerance, invalid ratios and values, independent native freshness pulses, the 399/400/401-tick observation boundary, stale or noncurrent samples, candidate interruption, and backwards time.
- Raw CRSF voltage metadata validation, calculated-name collisions, ambiguous raw sources, valid empty slots, source removal, and rediscovery. Missing, stale, calculated, duplicate or running RPM does not gate voltage identification; no ARM sensor is required.
- Locked identity during a live connection despite voltage/RPM/source/timing changes; observed disconnect and fresh reconnect acquisition, warning/extrema/chemistry resets, timer qualification, theme edits, saved model changes, and explicit mode changes.
- Separate `OMP M1`/`OMP M2` count and image keys, unresolved counter suppression, persistence, and unchanged radio model metadata. Editing only the saved radio display name preserves identity and alerts. Same-class reconfirmation preserves earlier counts and latches, cannot backfill a timer threshold crossed while unresolved, and permits counting again after a timer reset.
- Duplicate ownership, cross-variant takeover, deferred background layout changes, and no RF Tool load, host/queue service, or MSP admission.
- Reproducible Lua instruction observations for the identity helper during acquisition, steady flight, and callbacks inside its 10-tick sampling interval. These include the Lua API mocks and exclude native API time; they measure the helper rather than the complete callback.

These tests establish the exercised Lua behavior with mocked firmware boundaries. They do not establish physical display appearance, native CRSF decoding, RF delivery, real-radio timing, or memory margins.
