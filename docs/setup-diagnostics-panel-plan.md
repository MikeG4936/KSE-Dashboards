# On-radio setup and diagnostics panel

Status: proposed implementation plan; no dashboard behavior changed. Prepared 2026-09-23 against KSE revision `31cf32a`. Firmware findings and commit-pinned citations are in [the EdgeTX research](setup-diagnostics-edgetx-research.md). The current stable check is 2.12.4; 2.11.5 and 2.12.1 are pinned compatibility baselines. The newer 2.11.7 maintenance release was not audited; inspect it before claiming support across current 2.11 releases.

## Recommendation

Add an on-demand, read-only **Setup & diagnostics** panel to both dashboards. Its job is to answer three questions: what KSE can currently use, what is preventing a particular feature from working, and what the pilot should check next.

The entry sequence is **long-press KSE → Full screen → INFO**. Put the native **INFO** button inside the model-picture area, separate from the flight-count footer, when explicit fullscreen is active. In ordinary widget view, show a noninteractive `INFO: full screen` hint, wrapping it on compact layouts if needed. The fullscreen INFO button opens a panel titled **KSE Setup & diagnostics**. Keep the same meaning and relative placement in KSE4 and KSE5, while using their existing geometry adapters. Reserve space for the button so it does not cover the helicopter image. Keep it available when the image is missing.

The battery bar/ring already opens battery profiles. The compact header already contains model name, timer, profile/rate, signal and transmitter battery. The picture area is the least disruptive place to add a discoverable control. Do not use a hidden long-press gesture: EdgeTX already assigns widget long press to its own menu.

This extra fullscreen step is a firmware constraint: `lvgl.button`, `lvgl.dialog` and `lvgl.page` are fullscreen-only in all three inspected versions, and raw refresh events are supplied only in explicit fullscreen. Configuring KSE to occupy a whole telemetry page is not the same state. EdgeTX provides no supported Lua callback for adding a Diagnostics entry to its native widget menu.

For hardware controls, use EdgeTX’s native widget-selection route: long ENTER, select KSE with the wheel if necessary, ENTER, choose **Full screen**, then wheel-focus **INFO** and press ENTER. Native LVGL focus handles the controls; do not invent raw rotary events for an LVGL widget. Verify the exact physical route on each supported transmitter. Target INFO as the initial focus when entering the fullscreen dashboard, and restore focus to it after Back; the access spike must verify what the native focus API permits. Avoid opening a second profile selector over the diagnostics view.

EdgeTX documentation also calls this interactive fullscreen state **App mode**. Entering it does not change the saved **App mode layout** setting. Long EXIT returns to the ordinary widget view. See the [terminology clarification in the research](setup-diagnostics-edgetx-research.md#entrypoint-fullscreen-first).

## User experience

The panel opens only by request. It works disconnected, with missing ARM, and in OMP modes; those are situations it needs to explain. Opening it does not require confirmed disarm, because it does not request or change controller configuration. It never claims the aircraft is safe to fly. Use feature-specific wording such as **Battery profiles waiting** or **Flight history needs attention**, rather than an overall green readiness certificate.

Use a diagnostics view **inside the existing fullscreen widget**, with three short pages, explicit navigation controls, and a persistent **Back** button. Do not make a native modal dialog the baseline: the inspected 2.11.5 modal path can prevent the underlying widget from being serviced, while 2.12 moved servicing outside that path. Native Exit/Return behavior must be verified alongside touch and wheel focus; Back explicitly returns to the dashboard without leaving fullscreen. Leaving fullscreen also closes diagnostics. Prefer a small fixed number of rows per page and drill-in explanation over a large scrolling form. Keep text and symbols alongside colors.

| Page | Contents | Examples |
| --- | --- | --- |
| Overview | Aircraft/type, connection and ARM evidence, battery/profile state, selected counter and history state. Prioritize actionable items. | `ARM: not discovered` → `Open Model > Telemetry and discover sensors.` / `Battery profiles: waiting for ARM updates` / `History: unsaved changes`. |
| Sensors | Sources relevant to the selected mode and feature; discovered/current/invalid/unknown distinctions; a selected row explains what uses it. | `Tesc: current, Celsius` / `Hspd: missing — headspeed unavailable` / `Bat%: unavailable — voltage estimate in use`. |
| Details | Radio/EdgeTX information available through supported APIs, dashboard identity, selected options, image lookup/fallback, and bounded storage/provider details. | Expected image filename; local versus FC count; observed RF Tool host failure; unresolved Auto identity. |

Suggested overview layout (content is illustrative, not a literal rendering specification):

```text
KSE Setup & diagnostics                   [Back]
Overview                                  1 / 3

Aircraft       RAW 700 · Electric (Auto)
Connection     Connected · ARM not discovered
Profiles       Waiting for ARM telemetry
Flight history KSE counter · no pending save

Next step: Open Model > Telemetry and
discover ARM while the helicopter is connected.

[Previous]                              [Next]
```

At 480×272, target four concise rows plus one short explanation, with paging for additional findings. At 480×320 and 800×480, preserve the same order and navigation rather than adding a different information hierarchy. Continue to use 800×480 reference geometry with physical font/button minima. Reserve explicit space for the diagnostics header and navigation controls rather than scaling body text into a fixed outer rectangle. If a later 2.12-only variant uses native dialogs, existing picker tests identify a separate 32-pixel header on 480-wide targets and 44 pixels at 800-wide targets; that modal variant is outside the first version.

## What the first version diagnoses

| Area | Authoritative inputs | Wording and limits |
| --- | --- | --- |
| Aircraft identity | `OPT`, `AUTO_HELI.ready/name/status`, `OMP_AUTO.ready/name/status` | Distinguish chosen mode, pending detection, and confirmed identity. Do not treat a retained name after disconnect as a new confirmation. OMP M1/M2 identity is a cell class, not a unique airframe. |
| RF connection | Normal service's provider/host state and existing host errors | Explain missing RF Tool, disabled/unsupported host path, or connection wait. In OMP mode mark RF Tool **not used**. A usable API does not prove every installed file belongs to one exact package version. |
| ARM and profile availability | Published results from the existing admission/connection service; `profileStatusForDisplay` | Distinguish missing source, waiting for usable evidence, confirmed armed, and host contradiction where evidence supports it. Missing/stale ARM is not the same as disarmed. The panel must not run admission checks itself. |
| Battery | Existing validity flags and the result of `selectFlightBatteryPercent`; profile snapshot validity, capacities and operation status | Explain FC/telemetry percentage versus voltage estimate and reserve adjustment. Publish the selected percentage source during normal computation, because it is currently only a local result. Receiving `Bat%` alone does not prove Smart Fuel is enabled or correctly calibrated. Zero remains a valid measurement where the existing engine accepts it. |
| Counter/timer | Effective counter selection, `FC.status/count/stale`, `A.motorConfigError/motorSourcePhysical/motorSourceReadable`, normal Timer 1 observation and configured minimum/fuel duration | Describe FC statistics disabled, settling/waiting, local count requirements, invalid/unreadable Motor Switch selection, and current timer values. A timer being stopped on the bench is not a configuration failure. No automatic timer reset, switch test, or assertion that its wiring is correct. |
| History | `flightStore.source/error/dirty/writable` and normal save outcomes | Report existing error/recovery reason and pending changes. `writable` is KSE's permission-to-attempt-save state, not proof the SD card is currently writable. `dirty == false` alone does not establish a successful save. Distinguish unused, new history, recovered history and actual saved data. |
| Image | Existing cached `modelImageName/modelImagePath`; bounded reason codes captured during ordinary image checks | Show expected custom filename and selected fallback. The current boolean validator cannot explain a precise rejection: capture reasons at the original check if detailed messages are included. Header acceptance does not establish native decode success. Opening the panel must not reload images or enumerate the SD card. Preserve the existing image object in the hidden dashboard root. |
| Version/setup information | Verified `getVersion`, `model.getInfo`, widget options and available sensor metadata | Show only what can be established. Do not invent FC, ELRS or RF Tool semantic versions from an API version number. Defer a KSE build/version field until a reproducible build-label convention is selected. |

Sensor requirements must follow the current mode and affected feature. Missing optional instruments should explain an unavailable value without marking unrelated functionality broken. Nitro does not require electric pack telemetry; OMP does not require RF Tool or ARM; voltage fallback is an intentional behavior. While Auto identity is unresolved, show that first and avoid diagnosing against its provisional Electric/Nitro type.

## EdgeTX boundaries

The implementation must use the verified capability/version matrix in [the research](setup-diagnostics-edgetx-research.md), rather than assume all EdgeTX builds expose the same APIs.

- **Native widget menu:** no supported custom Diagnostics item. Use a control inside KSE and the existing native fullscreen route where necessary.
- **Telemetry:** source lookup, metadata and current/fresh flags can support useful diagnostics. A fresh flag is a brief pulse, not a continuous health signal or exact packet-age measurement. Preserve KSE's existing four-second observed ARM window. `getValue` alone cannot prove a zero reading is current.
- **Configuration:** first version gives directions to EdgeTX/Rotorflight settings. It does not promise a supported Lua deep link to a specific settings screen or automatically repair telemetry discovery, mixers, timers, profile capacities or files.
- **Execution:** continue the existing foreground/background service while the diagnostics view is open. Avoid a separate native modal layer on the common 2.11/2.12 path. Standalone Lua tools can suspend widget execution, so a separate Tools script is a poor primary entrypoint for this feature.
- **Resources:** the diagnostics view adds native UI allocations as well as Lua state. There is no universal safe file-size or per-widget RAM allowance. Build one bounded diagnostics tree on demand, hide it on Back, and release its callbacks/object references on owner/layout/theme replacement. Measure both retained roots together rather than assuming a hidden view is free. Do not load a second KSE engine or RF stack.
- **API fallback:** capability-check the required controls in explicit fullscreen. Keep a noninteractive explanation if that build lacks them; preserve the working dashboard. Do not silently fall back to a native menu/dialog on older firmware where it may suspend service. Never replace the whole renderer with an unverified LCD fallback.

## Shared-engine design and invariants

Implement one small diagnostics module in `src/shared/`, assembled into each standalone folder. It owns reason codes, feature applicability, snapshots and panel lifecycle. Track dashboard-versus-diagnostics view and explicit fullscreen mode independently of pixel dimensions: both current `ensureLayout` functions cache only geometry, so a full-page widget can enter fullscreen without a size change. The control set must still rebuild/change at that transition. Variant adapters supply only entry/button bounds and presentation style. Keep all existing option keys, positions and types unchanged; this feature needs no new saved option or history-file format.

### Render within the widget; avoid a new modal layer

Preferred structure: two retained `lvgl.box` roots, one for the existing dashboard and one for diagnostics. Keep the dashboard root and its image allocated; create one bounded diagnostics tree lazily after entering explicit fullscreen. Switch roots with supported hide/show operations. Hidden descendants are skipped by the firmware’s retained-property callback traversal; normal KSE engine service still runs. Reuse a fixed row pool for the three pages instead of retaining a separate tree for every page. This recommendation is supported by the source, with native focus and memory behavior still subject to the access spike.

Wrap the existing renderer without changing its physical coordinates, font choices or touch bounds. Parent-relative coordinates need explicit render regression coverage. Do not switch views by calling `updateOwned()` or `G.prepareWidget()`: those have option/lifecycle effects and assume normal-widget geometry. Route presentation callbacks to a pending intent and apply it in the current owner's next foreground refresh. Route updates to the visible view; force a normal dashboard presentation update on return so cached labels are current.

When replacing roots for layout/theme/owner changes, invalidate both view generations and all KSE4 `V/OBJECT_STATE` or KSE5 `ui/objectState/uiBuilt` references, including RF prompt/banner references. Preserve service order. Never set properties on deleted objects or destroy a control while its press callback is executing. If source/version or physical tests invalidate the retained-box approach, a root renderer swap is a bounded alternative, but must measure dashboard-image rebuild cost and meet the same operational parity requirements before adoption.

### Publish observations; keep rendering passive

Existing helpers have side effects. `MspAdmission.disarmed()` updates ARM observation and context/epoch state; `valid()` and `profileSwitchUnsafe()` invoke it. `profileDisplayStatus()` samples ARM. OMP sensor-resolution helpers also maintain acquisition evidence. Calling these from a label callback would make displayed information affect operational state.

Publish a compact diagnostics result from the existing normal service at the points where these observations already occur. Include context identity/generation, availability/reason codes and observation time. Keep the extra publication work bounded. Existing `D.*Valid` flags alone do not distinguish a missing source, noncurrent data and a rejected value; publish that distinction from the normal read path without changing its operational return values. Do not add an eligibility call or reorder operational checks. Rendering reads those fields; diagnostic sensor inspection uses separate data and cannot refresh ARM admission evidence or OMP identity evidence.

Clear or mark unavailable any context-dependent result when its source/model/provider/aircraft context changes. Check the original context before presenting a cached observation. A stale diagnostic snapshot never authorizes an action. Derive the message for each affected feature from its actual state, rather than applying a profile-specific reason to all features.

### Preserve the service loop and RF behavior

Opening/closing/paging the panel must introduce **zero additional KSE MSP requests**. No refresh/retry/reconnect button in version one. Existing background work, including the current single-configured-profile behavior and active upstream retries, continues with its existing admission rules; the panel is not a transport pause or zero-radio-traffic feature.

Do not call `resetSessionStats`, `loadModelFlights`, `Storage.load/save/retry`, RF preparation, or sensor-identity reset helpers from panel callbacks. Do not inspect/copy/clear queue internals for a diagnostics display. Preserve timers, alerts, flight attribution, unsaved counts and pending upstream work.

### One interactive view at a time

Coordinate diagnostics with battery-profile dialogs and the native-menu fallback. Do not simply pass `allowUi=false` to the entire RF service or stop servicing it. The manual battery-tap handler is outside that flag’s guard, and connection UI cleanup currently depends on it; use an explicit shared view/input guard for automatic and manual opening while preserving cleanup. While diagnostics owns the interactive view, defer only profile UI opening; keep connection cleanup, existing operations and published status active.

Keep a deferred profile popup eligible: do not mark `profileAutoShown=true` unless it was actually displayed/handled under the existing rules. After diagnostics closes, reevaluate whether the original prompt is still relevant. Never replay a stale prompt after a mode or context change. Route each input once so closing one overlay cannot select a control underneath it. Model the native picker explicitly too: it is not currently represented by `profileDialog`.

Guard callbacks with the existing owner epoch/model context plus a diagnostics-view generation. Owner checks may themselves retire obsolete model state, so use them as lifecycle guards, not as repeatedly evaluated diagnostic facts. Close/release the old panel when its owner or model changes, explicit fullscreen ends, or its UI is rebuilt; do not let stale close callbacks clear a replacement panel. On disconnect, keep diagnostics available but invalidate live evidence. On a normal page hide, return its view state to the dashboard and defer necessary UI changes until foreground. Do not touch global UI from an obsolete/background owner. Presentation callbacks only record intent; apply view changes during the owned foreground path. A root rebuild must replace all retained renderer references before their update functions run. Back hides diagnostics and restores the already-retained dashboard; no diagnostic code should reread images or rescan the SD card. Long EXIT belongs to the native fullscreen-exit path; the next normal refresh must restore dashboard view and remove/hide fullscreen-only controls. Do not promise short EXIT as an in-panel Back shortcut before verifying event propagation.

### Bound additional work

When closed, do no diagnostic sensor scans or file I/O. During normal service publish only the small operational facts needed later. When open, update displayed rows at a bounded rate (initial target at most 2 Hz), outside the RF/alert logic; measure the full callback before fixing the final rate.

If duplicate-name and unit checks require enumerating sensors, build a bounded inventory incrementally in foreground callbacks, stopping at the firmware's out-of-range result with a defensive cap. Keep only relevant names/metadata, label an incomplete scan **Checking**, and detect/restart on inconsistent lookup or model change. Re-read selected source identity before presenting its value. Start with small batches and tune to measured instruction/time headroom. Do not reuse `OMP_AUTO.uniqueSources()` as a generic diagnostics scan or scan all sensors per frame. Metadata availability does not prove sensor scaling/calibration correctness.

## Implementation slices

1. **Prove access and uninterrupted service.** Use a minimal disposable test widget plus the real KSE layout to verify the normal-view hint, explicit-fullscreen INFO button, native hardware focus/activation, Back/Exit, profile-UI coexistence and usable body geometry at all three resolutions. Verify the preferred two-box hide/show structure keeps service running on 2.11.5, preserves native focus, retains the image without reload, and has bounded allocation behavior. Verify same-geometry fullscreen entry/exit rebuilds the control set. Use a root renderer swap only if the preferred structure fails the measured gate; native dialogs are outside the common baseline. Confirm APIs against 2.11.5, 2.12.1 and 2.12.4. Record the exact supported gestures. Capture current compiler/resource baselines. This is a go/no-go for the proposed entrypoint, not a reason to promise unsupported key shortcuts.
2. **Add passive diagnostic state.** Define feature/reason codes and context invalidation, publish results at existing service observation points, and implement pure message selection. Cover offline, missing/stale/invalid ARM, Auto/OMP acquisition, intentional battery fallback, counter waits and history errors. Run parity and RF trace comparisons before UI work depends on these changes.
3. **Ship the entry and Overview panel.** Implement one interactive-view coordinator, owner/generation guards, fullscreen-aware rebuilding, bounded page objects and reliable Back/Exit. Start with the most useful existing state: identity, connection/ARM, profiles and counting/storage. Test that service and RF behavior remain unchanged while it is open. This is the smallest useful first release.
4. **Add Sensors and Details.** Add mode-specific source metadata, bounded incremental duplicate checks where supported, timer/settings facts, cached image selection and precise existing storage reasons. Add image rejection reasons only at the normal validation path. Keep any information not proven by available APIs explicitly unknown or omit it.
5. **Validate and document the supported result.** Regenerate both dashboards, run affected tests and resource checks, complete physical-radio access/readability/lifecycle checks, and add concise README instructions and troubleshooting examples. Keep unresolved hardware results explicit. Publish source-pinned API evidence with the eventual change; do not treat this plan as compatibility certification.

These can be separate reviewable commits, each explained by its user-visible effect. Do not add future history export, automated fixes, a standalone diagnostics application, active RF probes, or a settings migration to this scope.

## Acceptance criteria

- Identical diagnostic meaning in KSE4 and KSE5; existing layouts, themes, settings, counters and standalone installation remain intact.
- Entry and Back are usable at 480×272, 480×320 and 800×480, including missing-image fallback, long names and each theme. Native focus, labels and touch targets are checked on actual radios; mock geometry alone is insufficient.
- Offline and missing-ARM cases remain accessible. Unknown, invalid, absent, observed-current and not-applicable states cannot collapse into a misleading green success.
- The same timestamped inputs/replies with the panel closed versus open produce identical KSE MSP admissions and operational outcomes. Compare normalized traces, ARM/context epochs, Auto/OMP evidence, alert events, timer/reminder state, flight counts and storage effects. Direct UI callbacks enqueue only presentation intents.
- Profile autopup/manual picker/native fallback, disconnect/reconnect, model A→B→A, stale callbacks, duplicate owners, mode/theme changes, widget recreation and hidden-screen transitions behave correctly. Exercise arm/link loss between every profile-operation stage while diagnostics is open.
- Sensor inventory is bounded, tolerates absent APIs and slot deletion/reuse, preserves valid zero readings and cannot mutate admission or OMP acquisition evidence. Optional sources do not block unrelated features.
- Every compiled prototype remains within the existing 180-local/230-register project gates. Record baseline/delta bytecode and complete callback work; retain the roughly 15,000-instruction project target, including called RF service. No new per-frame closures or unbounded retained objects. Hidden roots still consume memory, so measure the whole retained pair rather than only the currently visible page.
- On the smallest-memory supported transmitter, repeated opening, paging, closing and screen/model changes show bounded retained Lua/native memory. Measure native allocation peaks and timing in normal non-DEBUG firmware; `getUsage()` and Lua heap alone are not whole-radio measurements.
- Affected suites include assembly, behavior, rendering, picker, ownership, Auto, OMP, MSP admission and storage, plus focused diagnostics contracts. Run the pinned EdgeTX compiler; source comparisons and fixtures do not replace hardware validation.

## Relevant KSE code

- [Foreground/background and owner lifecycle](../src/shared/lifecycle.lua)
- [ARM admission observation and context mutation](../src/shared/msp_admission.lua)
- [Provider state, profile UI, admission service and staged operations](../src/shared/rf.lua)
- [Telemetry names, validity helpers and battery percentage selection](../src/shared/telemetry.lua)
- [Normal battery sampling and selected percentage source](../src/shared/alerts.lua)
- [OMP acquisition evidence](../src/shared/omp_auto.lua)
- [History state and recovery semantics](../src/shared/count_storage.lua)
- [Cached image lookup and boolean header validation](../src/shared/images.lua)
- [KSE4 layout](../src/variants/KSE4/main.lua) and [KSE5 layout](../src/variants/KSE5/main.lua)
- [Resource limits](runtime-resources.md), [picker geometry/fallback tests](../tests/picker/README.md), and [hardware acceptance](transmitter-validation.md)
