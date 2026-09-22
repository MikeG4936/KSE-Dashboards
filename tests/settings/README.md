# Settings regressions

Run the authored settings store with the [pinned EdgeTX fixture host](../../tools/edgetx/README.md):

```sh
python3 tests/settings/run.py --runner ../kse-edgetx-build/edgetx-run
python3 tests/settings/menu_run.py --runner ../kse-edgetx-build/edgetx-run
python3 tests/settings/integration.py --runner ../kse-edgetx-build/edgetx-run
```

The storage runner embeds [`src/shared/settings_store.lua`](../../src/shared/settings_store.lua) directly. The menu runner extracts each authored variant's theme labels; settings defaults and helicopter choices come from the store itself. Neither runner maintains a second settings implementation. `--implementation path/to/module.lua` can select an equivalent module returning the `Store` table.

The filesystem mock is entirely in memory. It reproduces EdgeTX's standalone `io` calls, numeric FatFS mutation results, root `fstat` failure, directory availability, silent close errors and short writes. It never reads or changes the user's SD-card settings. Its API reference is EdgeTX 2.12.4 commit [`def35ad324896b45d6607d4778536b1bc5360d20`](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/lua/api_filesystem.cpp); the compiler/VM host retains the repository's separate EdgeTX 2.12.1 pin.

The contracts cover:

- Ten canonical settings, fresh internal default copies and removal of the TX battery fallback field.
- Schema 2 files in a separate `v2-model-`/`v2-hex-` namespace, leaving initial prototype files untouched. Version 1 companions and retired legacy numeric/text representations are rejected.
- Four helicopter menu entries mapped to stable saved IDs; both earlier version-2 OMP choices now select automatic identification, with no write merely on load.
- Shared functional values, separate dashboard themes, default theme index 1 for an unsaved variant, immutable save snapshots and preservation of the inactive variant's theme.
- Canonical serialization, completion/checksum rejection, duplicate/unknown/missing fields, schema changes, malformed hex, numeric fractions/overflow, source/theme bounds and safe model filenames.
- No writes or folder creation on first open; explicit adoption only after successful save; no direct overwrite of the main file; retained complete backup and reboot reload.
- Corrupt, oversized, foreign-model and temporary-only records; backup-only recovery without automatic mutation.
- Read/write/readback/close errors, directory failure, strict numeric FatFS status handling, external content changes before and during a staged save, and failure to confirm promoted content.
- Interruption after every pending save stage, conservative reconstruction from complete disk records, and explicit retry without partial settings adoption.
- Saved-snapshot export, non-executable import, destination-model rebinding, preserved source settings, and explicit destination save.

Voltage strings use canonical volts with two decimal places. Minimum flight time, counter source, fuel choice and theme indices use their current positive ranges; missing required fields and removed `TxBatt` fields cannot be imported. Old native Widget Settings are not a configuration source or import route.

Instruction profiles cover serialization, parsing, opening, starting a save, and the largest individual save stage for ordinary and largest valid schema records. They include Lua mock overhead and enforce the existing 15,000-instruction isolated-path margin. A limit-sized malformed parse is reported separately. These measurements exclude native filesystem latency, rendering, RF work and the rest of the widget callback. They establish neither physical SD crash durability nor transmitter memory/timing headroom; real-media interruptions and radio UI acceptance remain necessary.

## Isolated menu contracts

`menu_run.py` embeds the same store, the exact authored menu and the real voltage/source interpretation helpers. The retained-control mock validates property names and types against the subset of EdgeTX 2.12.4's native [`lua_lvgl_widget.cpp`](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/lua/lua_lvgl_widget.cpp) API used by the settings pages. It collects control specifications without pretending to render them or simulate native wheel focus, popups, keyboards or field-edit event consumption.

Tests cover firmware/control/fullscreen gating and unsupported-firmware messaging; hardware long-event entry without waiting for a suppressed release; touch holds, short taps and movement cancellation; delayed page construction; deferred button actions and file I/O; all editor mappings; ignored old native payloads; reset-to-default drafts; companion imports; saved-only export; validation errors; successful, unchanged and failed saves; Back/EXIT deduplication; discard; fullscreen escape; and stale callbacks after rebuild, owner/model changes or retirement. They check horizontal control bounds and touch heights at all three supported geometries. Reopening tests cover a shared configuration changed by the other dashboard and temporary storage failure without live-option reversion.

The menu profiles include this strict mock's schema-validation overhead. Whole-dashboard servicing, RF parity, selective alert resets and saved-option application belong to the separate integration fixtures and radio checks.

## Whole-dashboard integration

`integration.py` loads both generated dashboards with their actual lifecycle, telemetry, settings and render functions at all three geometries. Retained object mocks reject updates to cleared handles. The scenarios cover the empty native descriptor and ignored native create/update payloads; clean defaults and untouched prototype files; TX gauge unavailability without a valid native range; timer counting and RF-controller servicing while editing; layout invalidation; first adoption and failed/no-op/theme-only saves; the exact 8.30–8.40 V boundary; separate themes across owner handoff; gesture entry; full-screen cancellation before promotion; backup recovery; lost storage and A→B→A stale callbacks. The test records and gates the complete invoked Lua callbacks below 15,000 instructions, including its mocks.

RF Tool is absent in this integration fixture; the existing RF controller still executes but its full embedded host and transport do not. Run the separate [MSP admission suite](../msp_admission/README.md) for pinned upstream queue/continuation behavior. Native retained-property traversal and C API latency are also outside these callback figures. Real-radio focus, gesture routing, memory and complete timing with RF Tool remain outstanding in the [transmitter matrix](../../docs/transmitter-validation.md).
