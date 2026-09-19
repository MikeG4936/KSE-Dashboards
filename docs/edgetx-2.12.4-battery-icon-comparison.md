# Transmitter battery icon: KSE versus EdgeTX 2.12.4

Research date: 2026-09-19. Scope: the native color-screen **Radio Info** widget used in the EdgeTX top bar, compared with the transmitter battery icon in KSE4/KSE5. Aircraft pack telemetry and Smart Fuel are separate features.

The official `v2.12.4` annotated tag resolves to commit `def35ad324896b45d6607d4778536b1bc5360d20`. All source links below are pinned to that commit. [Official tag object](https://api.github.com/repos/EdgeTX/edgetx/git/tags/f28bf9d5f02ccd34bd5c05713286165e881d624b).

## EdgeTX behavior

### Input and normalization

- Native battery rendering reads `g_vbat100mV`. `getValue("tx-voltage")` and `getSourceValue("tx-voltage")` expose that same transmitter source in volts, so a Lua dashboard need not estimate a different raw voltage. [Mixer source](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/mixer.cpp#L507-L508), [legacy Lua conversion](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/lua/api_general.cpp#L347-L349), [current Lua conversion](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/lua/api_general.cpp#L845-L849).
- Firmware initializes that value from its battery voltage reading, then averages eight samples and rounds to 0.1 V. The periodic sampling call runs once per second. This filtering is already shared by the native icon and Lua transmitter-voltage source. [Filtering](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/main.cpp#L328-L360).
- The native gauge uses the configured radio **Battery range**, with linear interpolation from minimum to maximum. It does not select a chemistry curve. The endpoints are available in volts as `getGeneralSettings().battMin` and `.battMax`; the same API exposes `.battWarn`. [Gauge formula](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/edgetx.h#L789-L799), [settings API](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/lua/api_general.cpp#L1739-L1763), [hardware settings UI](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/gui/colorlcd/radio/radio_hardware.cpp#L94-L119).

### Fill and color boundaries

Let `p = (V - battMin) / (battMax - battMin)`. EdgeTX calculates a **horizontal pixel width** `bars = clamp(roundNearest(W * p), 0, W)`, where ties round upward for the nonnegative in-range case. Color is determined from this already-rounded width, not a separately rounded percentage: high when `bars >= G`, middle when `bars >= O`, otherwise low. [Rounded division](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/edgetx_helpers.h#L52-L58), [width and state selection](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/gui/colorlcd/widgets/radio_info.cpp#L163-L177).

The constants `W`, `G`, and `O` are independently scaled from 20, 12, and 5. This makes the exact normalized boundaries depend on display resolution. [Constants](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/gui/colorlcd/widgets/radio_info.cpp#L195-L210), [layout scaling](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/gui/colorlcd/libui/etx_lv_theme.h#L58-L70).

| Landscape display | Fill width W | High threshold G | Middle threshold O | Green starts at normalized level | Amber starts at normalized level |
|---|---:|---:|---:|---:|---:|
| 480×272 or 480×320 | 20 px | 12 px | 5 px | 57.5% | 22.5% |
| 800×480 | 28 px | 17 px | 7 px | 58.928571…% | 23.214286…% |

These percentages are derived algebraically as `(threshold - 0.5) / W`, before considering the real 0.1 V input grid. The displayed transition voltage is therefore the first available tenth-volt step at or above the corresponding boundary. At zero computed bars the update requests zero fill width. At full computed bars it requests the whole width; there are no discrete charge-image assets for these levels. [Fill geometry](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/gui/colorlcd/widgets/radio_info.cpp#L87-L91), [fill update](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/gui/colorlcd/widgets/radio_info.cpp#L163-L177).

Default fill colors are low **#F44336**, middle **#FFC107**, and high **#4CAF50**. These are configurable **Radio Info widget options**, not universal theme green/yellow/red constants. The outline uses the theme's primary-2 color. Thus matching defaults does not guarantee matching a user's customized Radio Info palette. [Default options](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/gui/colorlcd/widgets/radio_info.cpp#L233-L240), [option application](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/gui/colorlcd/widgets/radio_info.cpp#L114-L122), [outline](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/gui/colorlcd/widgets/radio_info.cpp#L70-L77).

The battery-warning voltage does **not** select these color states; it separately triggers the transmitter low-battery audio warning at `V <= battWarn`. No battery blink is applied in the Radio Info battery state update. On builds with `USB_CHARGER`, a separate charging symbol follows `usbChargerLed()`. [Warning predicate](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/edgetx.h#L796-L799), [alarm](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/main.cpp#L330-L337), [charging and battery update](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/gui/colorlcd/widgets/radio_info.cpp#L155-L177).

## Alignment implications

To reproduce native level semantics in Lua, reuse `tx-voltage`, read the radio's battery range, and apply the native width rounding and color comparisons for the actual display. Rescale the resulting `bars / W` to the dashboard's intentional vertical geometry if preserving that design. Merely setting thresholds to 60%/25% is close but does not reproduce the pixel-rounded boundaries.

Radio range and warning values have a confirmed public Lua API. This source review did not identify a public Lua API that directly reads another widget's saved Radio Info color options; exact customization mirroring should therefore remain an explicit limitation until an access route is verified. Native USB charging-symbol access was not investigated as part of the requested charge-level/color alignment.

This is a source comparison, not a measured radio rendering or battery-capacity validation. Voltage-derived percentage is a configured gauge position, not a coulomb-counted state-of-charge measurement.

## KSE comparison

The following table describes the pre-alignment code at KSE commit `ae828aab4b1a77e4596c97dc4717529aca589264`. Current behavior is defined by the implementation contract below.

| Behavior | KSE4 and KSE5 | EdgeTX 2.12.4 Radio Info |
|---|---|---|
| Voltage source | `tx-voltage`; no additional battery smoothing | Same firmware-filtered voltage |
| Empty/full range | Fixed 7.0–8.4 V for LiPo, 6.2–8.4 V for Li-Ion | User-configured radio battery range |
| Percentage estimate | Linear, clamped 0–100 | Linear, clamped to fill width |
| Green | Rounded percentage >=51; mathematical boundary 50.5% | Rounded fill >=12/20 or >=17/28; approximately 57.5% or 58.93% |
| Yellow/amber | Rounded percentage 31–50; starts at 30.5% | Rounded fill >=5/20 or >=7/28; starts at approximately 22.5% or 23.21% |
| Red | Rounded percentage <=30 | Below amber fill threshold |
| Depletion | Vertical fill, floor of inner height × percentage | Horizontal fill, nearest-integer native width |
| Empty | KSE4 hides zero-height fill; KSE5 retains one pixel for valid zero percentage | Requests zero fill width |
| Palette | Dashboard colors; KSE5 also varies with theme | Radio Info's configurable three-color palette |

Baseline evidence is reproducible with `git show ae828aab4b1a77e4596c97dc4717529aca589264:src/shared/telemetry.lua` and the same revision's `src/shared/options.lua`, `src/variants/KSE4/main.lua`, and `src/variants/KSE5/main.lua`. The original KSE4 transmitter palette used RGB (34,197,94)/(240,180,41)/(239,68,68); KSE5's base palette used (28,232,119)/(255,196,48)/(255,64,80), with light-theme overrides.

### Concrete differences with matching endpoints

These examples assume EdgeTX's battery range is deliberately configured to the same endpoints as the selected KSE chemistry. They are calculations from the source formulas, not readings from the user's radio.

| Range and reading | KSE estimate/color | Native 480-wide fill/color | Native 800-wide fill/color |
|---|---|---|---|
| Li-Ion 6.2–8.4 V, reading 7.4 V | 54.55%, green | 11/20 (55%), amber | 15/28 (53.57%), amber |
| Li-Ion 6.2–8.4 V, reading 6.8 V | 27.27%, red | 5/20 (25%), amber | 8/28 (28.57%), amber |
| LiPo 7.0–8.4 V, reading 7.8 V | 57.14%, green | 11/20 (55%), amber | 16/28 (57.14%), amber |

Different configured endpoints can produce a much larger depletion mismatch. For example, with EdgeTX configured to 6.2–8.4 V while KSE selects LiPo, a 7.4 V reading maps to 54.55% before native rounding versus KSE's 28.57%.

### Implementation contract

Use the radio's `battMin` and `battMax` as the primary range, preserving the existing chemistry setting and fixed ranges as a fallback when the API/range is unavailable or invalid. The shared `sensors.txBatteryState` caches only the range values for 100 ticks (one second), refreshes on clock rollback, reconstructs integer tenths of a volt, and calculates the native rounded fill count for the physical display resolution. Both renderer adapters use that count's color band and map its fraction onto their vertical icon with nearest-pixel rounding; a positive native fill retains at least one vertical pixel, while zero or unavailable voltage hides the fill. Exact pixel geometry still differs because the icons have different dimensions.

Both transmitter icons use the Radio Info default RGB values in all KSE themes. Automatically mirroring user-customized Radio Info colors has not been established. The low-battery warning setting remains separate from the fill-color calculation, as it is upstream. Aircraft battery, Smart Fuel, and RF behavior are outside this change's scope.

### Saved option and future replacement candidate

Retain `TxBatt` as CHOICE in slot 2 with original values 1/2, labeled **TX Batt Fallback**. EdgeTX persists options by numeric position and type, then assigns Lua names; removing this middle slot would reset or reinterpret later values. Every named descriptor creates a visible settings row; there is no supported hidden option type. Evidence: [ordinal-to-name mapping](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/lua/lua_widget_factory.cpp#L91-L105), [per-slot storage/reset](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/gui/colorlcd/mainview/widget.cpp#L35-L84), [visible row creation](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/gui/colorlcd/mainview/widget_settings.cpp#L58-L64), [option types](https://github.com/EdgeTX/edgetx/blob/def35ad324896b45d6607d4778536b1bc5360d20/radio/src/gui/colorlcd/mainview/widget.h#L39-L58).

This retained slot is explicitly a **candidate for replacement by a future feature**. Reuse requires a defined migration, retirement of chemistry fallback, and assurance that saved LiPo/Li-Ion values cannot accidentally enable or configure the new feature. Until then preserve its key, position, type, and choice indices.

### Validation scope

The [behavior contracts](../tests/behavior/README.md) check native fill/color boundaries, integer ties, range precedence and refresh, fallback errors, and invalid voltage in both generated outputs. The [render contracts](../tests/render/README.md) inspect actual retained fill objects at all three target dimensions, verify default colors independently of theme, and verify zero fill disappears in both variants. Auto and OMP lifecycle fixtures retain their original option-position assertions.

Both outputs must pass deterministic assembly and every-prototype compiler/resource gates. Actual radio settings were not available for this comparison; physical-radio rendering, memory, and timing still need transmitter validation. In particular compare native and KSE icons at both color transitions, empty/full, and after a radio battery-range edit.
