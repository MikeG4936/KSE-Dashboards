# Dashboard ownership callback fixtures

Run from the repository root using the pinned EdgeTX Lua runner described in
[tools/edgetx](../../tools/edgetx/README.md):

```sh
python3 tests/ownership/run.py --runner /path/to/edgetx-run
```

The driver instruments temporary copies of both production dashboards. No test
exports or additional Lua files are installed on the transmitter. Each case uses
a fresh Lua process, the shared radio and failure-injectable filesystem mocks in
`tests/behavior` and `tests/storage`, and the actual production `create`, `update`,
`refresh`, and `background` callbacks. Dashboard rendering and profile-controller
service are replaced by counters; the actual picker closure and MSP admission
functions remain available to test stale ownership.

Six pairings cover two widgets using one loaded KSE4 or KSE5 module, separate loads
of the same variant, and KSE4/KSE5 in both ownership orders. Assertions cover:

- Initial ownership, ordinary local threshold counting and persistence.
- Duplicate creation and option updates preserving the active options, alerts,
  statistics, lease, count file, and controller state; inactive widgets remain
  lightweight and cannot admit MSP.
- Background activity renewing the active owner's lease. A duplicate's background
  callback never claims ownership, including after expiration.
- Foreground takeover at 500 EdgeTX ticks, with no takeover at 499 ticks or from
  duplicate creation alone. The new owner initializes its saved options.
- Handoff retiring pending owned MSP entries while preserving foreign entries,
  and late acknowledgments being unable to stage the old operation.
- Stale picker callbacks, MSP admission, option updates, foreground callbacks, and
  background callbacks remaining inactive while the replacement owner is active.
  Old picker and ACK callbacks remain invalid after ownership returns to the
  original widget and it starts a new operation.
- Active-owner model changes preserving independent counts, and transfer of an
  unsaved qualified count through the shared store without recounting it.

The fixture models deletion/suspension as absence of the old owner's callbacks;
EdgeTX has no widget deletion callback in this descriptor. It does not reproduce
radio scheduling, LVGL memory/resource lifetime, RF host discovery or transport,
or over-the-air behavior. The production profile service is mocked here; the
separate `tests/msp_admission` suite exercises the pinned upstream queue. Hardware
lifecycle and RF validation remain separate requirements.
