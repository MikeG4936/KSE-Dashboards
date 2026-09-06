# Auto helicopter type contracts

Build the supported EdgeTX fixture runner using [the compiler tooling](../../tools/edgetx/README.md), then run from the repository root:

```sh
python3 tests/auto_type/run.py --runner ../kse-edgetx-build/edgetx-run
```

The runner creates temporary copies of both generated dashboards with a test-only `audit` field in the returned widget descriptor. It does not change production files or require `debug.getupvalue`, desktop Lua libraries, or transmitter-side test exports. Real `create`, `update`, `refresh`, `background`, layout, and retained property callbacks execute under the pinned EdgeTX Lua core. Public EdgeTX APIs, retained LVGL objects, storage, and RF host/queue boundaries are mocked.

Each dashboard runs at 800×480, 480×320, and 480×272. Contracts cover:

- Persisted choice order/default, literal name suffixes, fractional option rejection, manual overrides, and OMP's retained counter preference.
- Missing/blank/initializing FC names, exact 29/30-tick confirmation, candidate changes, clock rollback, unchanged TX names, theme edits, brief RSSI loss, and full reconnect.
- Mode selection before telemetry, paused unresolved alerts/profiles/counts, stable warning latches, same-type session resets, hidden resolution, deferred layout rebuilds, real waiting-state rendering, and the normal 10 Hz telemetry cap without repeated stable-name inference.
- Embedded publication during the callback, exactly one embedded background service per callback, untouched external hosts/queues, and pending owned request removal before pumping while preserving active requests and foreign entries.
- Separate CSV keys and image lookup for confirmed FC names, retained disconnected identity, local count persistence after identity becomes unresolved, and identified Nitro FC-count admission.
- Duplicate widgets, cross-variant foreground takeover, and fresh confirmation after TX filename, provider, queue, or host replacement. Immediate callback eligibility is checked before a subsequent KSE callback.

The suite replaces `tests/auto_heli_type.lua`, whose desktop debug introspection and active-request cancellation expectations do not apply to the supported implementation. Use the [MSP admission contracts](../msp_admission/README.md) for pinned upstream decoders, continuation stages, and stale callback delivery. Storage recovery and ownership suites cover their broader fault matrices.

These checks establish the exercised Lua behavior and callback ordering. They do not establish physical LVGL appearance, native decoder success, RF packet delivery, transmitter callback timing, or whole-radio memory margins.
