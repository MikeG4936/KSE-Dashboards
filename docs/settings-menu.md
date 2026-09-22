# Fullscreen dashboard settings

KSE uses EdgeTX’s native LVGL pages and editors for all local configuration. The implementation targets EdgeTX **2.12.4**, first on TX16S MK3/MAX (800×480), retaining 480×320 and 480×272. The version gate admits 2.12 patch releases >=4 only, plus an explicit check for every required constructor and dimension constant. Other firmware/API combinations cannot open the settings and show the firmware requirement when basic LVGL drawing is available. There is no native Widget Settings fallback. Later firmware families need a source review before widening the gate. Desktop coverage is not physical-radio certification.

See the [user guide](../README.md#fullscreen-settings-menu) for operation and [settings tests](../tests/settings/README.md) for reproducible validation.

## Interaction and native boundaries

- **App Mode** is EdgeTX’s saved single-widget layout without the top bar and trim sliders. **Active fullscreen** is the runtime state in which EdgeTX routes input to that widget. In App Mode, the first long press activates the widget and EdgeTX consumes that gesture. Once active, a subsequent hold opens KSE Settings. Ordinary layouts can reach the same state through **Full screen**. A dashboard covering the display is therefore not necessarily already accepting input.
- Once active, hold ENTER/wheel, or hold a stationary touch for 70 EdgeTX ticks (0.7 seconds) and release. Sliding cancels touch entry. Native long ENTER suppresses its following release on the reviewed color firmware; entry must not wait for BREAK. Controls are built on the next refresh. No dashboard area is reserved for a button.
- Four category buttons open Model setup, Power & alerts, Flight counting and Appearance. Nitro setup is below Power & alerts; **Backup & transfer** is directly on the home page. Native headers keep Back and a separate root-level **Save & close** button. The native body/element height constants control geometry rather than proportional scaling of fonts and fields.
- Native fields and popups consume EXIT while editing. A page Back callback handles field-focused navigation; a raw short-EXIT fallback handles the fullscreen widget root, which remains in the focus group. Long EXIT retains the firmware escape. No claim is made that it always displays the dirty-exit choice.
- Model/SYS go to the active fullscreen Lua widget instead of EdgeTX’s normal shortcut handler. Lua has `lvgl.exitFullScreen()` but no exposed native Model/System page opener or reliable event-forwarding API. The current route is long EXIT to release the widget, then the normal key action. Native popups can consume keys before the widget receives them.
- The page backdrop is opaque and floating, so scrolling does not expose the radio theme beneath a dark KSE page. KSE styles category buttons and labels. Native fields/header/focus retain their supported EdgeTX styling. Theme samples are pure palette reads, never temporary application of live options.
- An open battery-profile dialog owns input until dismissed. Verified settings-capable widgets use a tracked native dialog rather than the unobservable `lvgl.menu` fallback. Native dialogs are userdata and must be closed before clearing their Lua references. A renderer rebuild closes the owned profile dialog first. Retained callback/model revocation only invalidates state; it never clears native objects.

## Configuration authority

Users upgrading from native Widget Settings or the first menu prototype explicitly start from defaults and configure the dashboard again. The native descriptor is **`options={}`**: an empty table is required for EdgeTX registration; omitting the field is not equivalent. Native `create` and `update` payloads are ignored. There is no native snapshot, alias conversion, old slot retention or native import action. The TX battery chemistry/fallback setting is removed; the icon uses only the radio’s configured battery range.

The store defines canonical defaults independently of EdgeTX options. Until the first successful **Save & close**, these defaults supply the live configuration. Opening pages and editing a draft do not write files. Saved version-2 records are then authoritative for both variants and survive normal restarts. The first menu prototype’s version-1 files are outside the new filename namespace and remain untouched; they cannot be imported. This is the authorized clean transition, not an automatic migration.

A record contains functional `values` plus `themes.KSE4`/`themes.KSE5`. A missing variant theme uses **Dark**, index 1. Saving one variant preserves the other theme. Inactive Nitro fields and OMP’s saved FC-counter preference remain in the modern record without overriding the effective mode. Version-2 companion import loads its functional values and saved theme entries into the destination draft. **Reset draft to defaults** resets shared functions and the active theme, retaining the other variant’s saved theme; it requires explicit Save to apply.

Identity is `model.getInfo().filename`, not the display name, FC name or flight-history key. Ownership/model epochs distinguish an observed A→B→A transition. The filename is not a universal UUID: restoring a different model under an existing filename can reuse its settings. Reset and review its configuration, or explicitly import its companion. Display-name changes leave the association intact.

The Helicopter type menu shows **Electric, Nitro, Auto Elec/Nitro, OMPHOBBY**, mapped to stable saved IDs 1, 2, 4, 5. OMPHOBBY always identifies M1/M2 automatically; an existing version-2 manual OMP ID 3 is interpreted as automatic ID 5 without rewriting the file on load. The next explicit Save records ID 5. Other settings and Rotorflight Auto retain their meanings; version-1/native settings remain excluded.

Save validates the whole draft, including physical motor-source identity and the receiver voltage pair. Editor and runtime share the receiver-range validator; a one-microvolt tolerance accounts for EdgeTX’s 32-bit representation of a 0.10-V difference. Invalid values remain in the draft with a visible message. Source IDs must be reviewed after a radio-to-radio transfer; identity validation cannot know which physical switch the user intends.

## Storage protocol

`settings_store.lua` owns the bounded, nonexecutable record format and filesystem policy. Version-2 names use `/KSE/Settings/v2-model-<model filename>.kse`; other permitted filename characters use an unambiguous `v2-hex-<encoded filename>.kse`. No model-derived path separators/control characters are accepted. Records are capped at 512 bytes; the largest schema-bound record in the fixture is 316 bytes. Unknown fields, duplicate keys, unsupported versions, invalid ranges, mismatched model identity, malformed text encoding and missing completion/checksum markers are rejected. Values are never evaluated as Lua.

Receiver voltages are canonical two-decimal strings within 4.00–9.00 V. Minimum flight is 1–120 seconds, counter source is 1 or 2, and themes are 1–22. Fuel reminder uses internal indices 1–121 for Off through 30:00 in 15-second steps, with index 25 for the 06:00 default. These indices are menu storage values, not native descriptor slots. Missing required values and legacy representations are rejected.

No write occurs per field edit. Save serializes a private snapshot, then proceeds over foreground callbacks:

1. Verify destination directories and the expected original file.
2. Write `.tmp`, close and verify exact bytes.
3. Remove the previous backup only when replacing a valid current main.
4. Recheck the current main and rename it to `.bak`.
5. Promote `.tmp` to main, verify exact readback and commit the saved snapshot **within one callback**.

Numeric FatFS zero is required for mutations; truthiness is not success. Closing a file does not expose flush success, so readback is required. Main and backup are retained conservatively on failures. A successful final promotion/verification returns the record for one selective engine application. No-op saves skip reapplication. Saves allocate the returning dashboard on a following refresh, then populate instruments on the next refresh to avoid combining allocation, complete instrument updates and storage work in one budget.

Owner/model/fullscreen changes cancel earlier stages, leaving the prior main or recoverable backup authoritative. There is no callback boundary between final promotion and application. A filesystem error during that final callback can still leave an unconfirmed main; recovery must inspect files rather than infer that a reported error proves no disk change. FatFS renames/readback are not a power-loss atomicity guarantee.

Reopening refreshes the file snapshot and catches external modification. A running widget retains its known live configuration if reload fails or yields a different degraded backup; it marks the editor read-only. A fresh owner may load a valid backup according to the recovery policy. Reopening cannot silently change a running helicopter to older settings merely because the SD card becomes unavailable.

## Backup and transfer

Saved exports go to `/KSE/Settings/Exports/`. Export uses the last saved record, including both saved themes, regardless of draft edits. Export has its own verified save transaction and does not apply configuration. The native file picker returns a filename from this fixed directory; it does not browse directories. The picker is rebuilt after export to refresh its cached listing.

Companion import validates a version-2 `.kse` file and loads it into the current model’s draft. Its source identity is provenance, never a write destination. Explicit Save binds it to the current saved model filename. Whole-SD copies carry the directory automatically; individual EdgeTX model backups need the exported companion alongside them because these settings no longer live inside the EdgeTX model file. Flight-count history remains a separate root CSV and is not part of this settings transaction.

## Recovery

- A valid main wins. A missing main with a valid matching `.bak` loads the last saved backup and permits a new verified Save. A corrupt/unreadable main with a valid backup loads the backup for a fresh owner but remains read-only to preserve the damaged file.
- A temporary file by itself is not a confirmed Save and is not automatically promoted. A malformed/oversized main or identity mismatch is not overwritten. An already-running widget retains its previous live values when files disappear or degrade.
- On a computer, first copy the affected `.kse`, `.bak` and `.tmp` files somewhere safe. Restore a known-good main/backup for that exact model filename, then reopen KSE. To deliberately recover from unusable files by starting over, back up and remove only that model’s version-2 main/backup/temp set, restart its widget, configure from defaults and explicitly Save. Do not remove other model files or flight history. For a healthy record, use **Reset draft to defaults** instead.
- To transfer valid settings from another filename, use the companion import flow; do not edit encoded identities/checksums by hand. Full/failing/read-only cards need repair before Save/export can succeed.

## Telemetry and RF contract

Settings are local and remain editable while armed or offline. `refreshOwned` continues battery-profile preparation, OMP identification, telemetry/alerts/counters and RF service. The editor suppresses dashboard layout/instrument updates and competing profile UI only. The profile tap path obeys `allowUi`, and no event/touch is forwarded while settings own the display. Settings code adds no MSP request. Existing disarm admission, active upstream retries, foreign work and RF Tool ownership remain governed by [compatibility](compatibility.md) and [RF integration](rf-integration.md).

Setters validate editor generation plus widget/model ownership before mutating a draft. Navigation/import/save callbacks queue intent; foreground service performs page clears and filesystem operations. Every save step rechecks the active editor context through foreground service. Replacing a page invalidates retained callbacks from that page; model/owner changes invalidate the session without manipulating native handles from a getter.

## Version-pinned source evidence

EdgeTX authority: `def35ad324896b45d6607d4778536b1bc5360d20` (2.12.4). Rotorflight Lua reference: `aaacfe68407c09d49a26c5aa326c00119b378bb0` (2.3).

- [EdgeTX control exports, fullscreen gate and dimension constants](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/lua/api_colorlcd_lvgl.cpp).
- [App Mode layout](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/gui/colorlcd/layouts/layout1x1AppMode.cpp#L26-L55), [direct long-press activation](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/gui/colorlcd/mainview/view_main.cpp#L329-L340), [activation consumes the gesture](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/gui/colorlcd/mainview/widget.cpp#L173-L190), [input requires active fullscreen](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/lua/lua_widget.cpp#L508-L522).
- [Model/SYS delivery to active Lua widgets](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/lua/lua_widget.cpp#L557-L563), [base widget handles long EXIT](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/gui/colorlcd/mainview/widget.cpp#L194-L200), [normal 2.x shortcut mappings](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/datastructs_radio.cpp#L95-L120), [Lua fullscreen exit](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/lua/api_colorlcd_lvgl.cpp#L412-L416), [deferred exit](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/lua/lua_widget.cpp#L294-L299) and [event queue clearing](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/lua/lua_widget.cpp#L445-L452).
- [Empty option-table parsing](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/lua/lua_widget_factory.cpp#L274-L350) and [required descriptor for registration](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/lua/widgets.cpp#L146-L153).
- [Touch/ENTER event routing and native cancellation](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/lua/lua_widget.cpp), [Rotorflight’s explicit color-firmware long-ENTER workaround](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/ui_lcd.lua#L26-L27), [RF LVGL EXIT handling](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/ui_lvgl_runner.lua).
- [Native page, number, choice, source, toggle and file bindings; userdata lifetime](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/lua/lua_lvgl_widget.cpp), [file enumeration](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/gui/colorlcd/libui/filechoice.cpp), [modal parent](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/gui/colorlcd/libui/modal_window.cpp#L49-L55).
- [Filesystem results and bounded I/O](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/lua/api_filesystem.cpp), [model filename](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/lua/api_model.cpp).
- [Rotorflight page and sibling Save pattern](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/LVGL/page.lua#L154-L193).

Native focus, physical gesture release, file/source pickers, SD durability, retained native memory, instruction/elapsed-time peaks with RF Tool and smallest-radio headroom still require the [transmitter validation matrix](transmitter-validation.md). Host fixtures establish only the exercised logic, schema and mocked callback costs.

## Implementation resource comparison

Compared with pre-menu commit `31cf32a1fc4f91d5687d97d3af263d18347bada1`, using the repository-pinned EdgeTX compiler/VM (`1511b3f29152f18c704f1f89b3608e0f71317de9`):

| Dashboard | Maximum active locals, before → after | Maximum registers, before → after | Stripped bytecode, before → after |
| --- | --- | --- | --- |
| KSE4 | 174 → 172 | 199 → 196 | 132,292 → 157,715 bytes |
| KSE5 | 168 → 166 | 193 → 190 | 130,173 → 156,310 bytes |

Every prototype passes the 180-local/230-register project gates. The bytecode increase adds the shared native menu, draft lifecycle, verified settings storage and palette sampling to each standalone dashboard; removing native descriptors and migration paths reduces peak locals/registers. It is not a measurement of retained radio RAM. The whole-dashboard fixture's largest measured callback is 14,398 instructions on KSE5; RF Tool is absent and LVGL/I/O are mocked. Menu-specific actions, storage failures, owner/model lifetime, all three geometries and the existing RF admission/parity suites pass their host contracts. Complete radio timing and memory remain unmeasured.
