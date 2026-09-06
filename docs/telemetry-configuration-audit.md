# Telemetry configuration audit

Audit date: 2026-09-06. Scope: the README's Rotorflight CUSTOM telemetry selection and its interaction with KSE4/KSE5 and ExpressLRS. The user reports Rotorflight 2.3 and ExpressLRS 4.1; exact patch/build, packet rate, switch mode and telemetry ratio were not supplied. ExpressLRS 4.1.0 is the primary baseline, with 3.6.4 checked for older-version differences. Source analysis establishes implementation behavior; no over-the-air control-latency or flight-controller CPU measurement was performed.

Rotorflight baselines are firmware [`release/4.6.0`, commit 118e912](https://github.com/rotorflight/rotorflight-firmware/tree/118e9120260bb33f46df4f92052fb0e9fd4e9ebc) and [RF Lua 2.3, commit aaacfe6](https://github.com/rotorflight/rotorflight-lua-scripts/tree/aaacfe68407c09d49a26c5aa326c00119b378bb0). Older telemetry mappings were spot-checked against firmware `release/4.5.1` and RF Lua 2.2.0 below. The firmware's own version numbering differs from the Rotorflight 2.x package naming.

## Sensor mapping

The audited README at commit `9cc26a9` enabled **39 nonzero Rotorflight sensor selectors**. **15 cover all telemetry consumed across KSE4/KSE5**, and **one more preserves RF Tool's Adjustment Teller**. The other **23 have no fixed dependency in these dashboards or the reviewed RF Tool/RfStats host functions**. They may still serve the user's radio alarms, logs, logical switches, RF Tool's configurable Source tile, or other widgets.

The dashboard-focused minimum is therefore **16 enabled entries**, preserving all current KSE features and RF Tool adjustment announcements. KSE5 alone does not display tail speed, so its strict dashboard requirement is one entry smaller; retain it in the common list for easy switching between dashboards. That minimum would remove 23 entries. The selected README configuration instead retains **21 entries**: the 16-entry minimum plus `Mode` (89), `MDL#` (88), `Thr` (15), `ARMD` (91) and `Resc` (92). It removes exactly the 18 requested ESC reporting entries. These selector counts are **not proportional bandwidth or RC-latency measurements**.

Dashboard evidence: [shared sensor mapping and readers](../src/shared/telemetry.lua), [alerts](../src/shared/alerts.lua), [statistics](../src/shared/counters.lua), [ARM admission](../src/shared/msp_admission.lua), [RF operations](../src/shared/rf.lua), and the [KSE4](../src/variants/KSE4/main.lua)/[KSE5](../src/variants/KSE5/main.lua) renderers, reviewed at commit `9cc26a929349f65ed7a5d064efb08b82675ed11e`. Both generated dashboards use this authored engine.

### Every entry in the audited 39-entry README

`Keep` means preserve the current feature set across both dashboards. `Optional` means unused by their fixed functions, not necessarily unused elsewhere in the radio model. The current README retains the five optional state/model/throttle entries identified above and removes the 18 optional ESC entries; this table records functional necessity across the original selection. These numbers are firmware configuration selectors, not radio source IDs or CRSF packet types. CUSTOM sends typed values inside CRSF frame `0x88`; several selected values can share a packet. The names below come from the official RF Lua decoder. [Firmware selector enum](https://github.com/rotorflight/rotorflight-firmware/blob/118e9120260bb33f46df4f92052fb0e9fd4e9ebc/src/main/telemetry/sensors.h#L35-L155), [CUSTOM encoders](https://github.com/rotorflight/rotorflight-firmware/blob/118e9120260bb33f46df4f92052fb0e9fd4e9ebc/src/main/telemetry/crsf.c#L728-L827), [RF Lua names and decoding](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/rf2tlm_sensors.lua#L132-L315).

| ID | Rotorflight value → radio name | Recommendation | Current dependency or purpose |
| --- | --- | --- | --- |
| 43 | BEC voltage → `Vbec` | Keep | BEC display/minimum; Nitro receiver-pack percentage and warnings. |
| 60 | Headspeed → `Hspd` | Keep | Main RPM, maximum RPM, motor-alert evidence. |
| 61 | Tail speed → `Tspd` | Keep for common setup | KSE4 tail-speed display; KSE5 has no tail-speed tile. |
| 89 | Flight mode → `Mode` | Optional | No KSE reader. Separate from `ARM` and `Gov`. |
| 88 | Model ID → `MDL#` | Optional | Manual KSE modes use the EdgeTX model name; Auto uses the host's FC name obtained through MSP, not `MDL#`. |
| 93 | Governor state → `Gov` | Keep | Governor display and motor-alert evidence. |
| 15 | Throttle control → `Thr` | Optional | KSE Motor Switch uses the selected radio switch, not this value. |
| 3 | Battery voltage → `Vbat` | Keep | Electric pack voltage/validity and connected-pack evidence. |
| 4 | Battery current → `Curr` | Keep | Current and maximum-current display. |
| 5 | Battery consumption → `Capa` | Keep | Used capacity. |
| 6 | Battery charge level → `Bat%` | Keep | FC battery percentage, including Smart Fuel. |
| 7 | Battery cell count → `Cel#` | Keep | Cell count and battery validation. |
| 8 | Average cell voltage → `Vcel` | Keep | Cell voltage, minimum tracking, battery/chemistry evidence. |
| 95 | PID profile → `PID#` | Keep | Top-bar active PID profile. |
| 96 | Rates profile → `RTE#` | Keep | Top-bar active rate profile. |
| 97 | Battery profile → `BAT#` | Keep | Active battery-profile indicator. |
| 90 | Arming flags → `ARM` | Keep | Fresh disarm proof for KSE MSP; RF Tool armed/disarmed events. |
| 91 | Arming-disable flags → `ARMD` | Optional | KSE's current diagnostic banner obtains these flags through MSP status. |
| 92 | Rescue state → `Resc` | Optional | No KSE reader. Removing reporting does not disable rescue. |
| 99 | Adjustment function/value → `AdjF`, `AdjV` | Keep for RF Tool | Spoken adjustment announcements; KSE itself does not read these. |
| 42 | Combined ESC voltage → `Vesc` | Optional | KSE reads `Vbat` instead. |
| 46 | Combined ESC current → `Iesc` | Optional | KSE reads `Curr` instead. |
| 50 | Combined ESC temperature → `Tesc` | Keep | Temperature display, maximum and warning. |
| 17 | ESC1 voltage → `EscV` | Optional | Detailed ESC1 telemetry. |
| 18 | ESC1 current → `EscI` | Optional | Detailed ESC1 telemetry; not `Curr`. |
| 19 | ESC1 capacity → `EscC` | Optional | Detailed ESC1 telemetry; not `Capa`. |
| 20 | ESC1 electrical RPM → `EscR` | Optional | Detailed ESC1 telemetry; not main headspeed. |
| 21 | ESC1 power → `EscP` | Optional | Detailed ESC1 telemetry. |
| 22 | ESC1 throttle → `Esc%` | Optional | Detailed ESC1 telemetry. |
| 23 | ESC1 temperature 1 → `EscT` | Optional | KSE uses the combined `Tesc` sensor. |
| 24 | ESC1 temperature 2 → `BecT` | Optional | Additional ESC/BEC temperature; no KSE reader. |
| 25 | ESC1 BEC voltage → `BecV` | Optional | KSE reads `Vbec`; these names are distinct. |
| 27 | ESC1 status → `EscF` | Optional | Detailed ESC1 status/fault reporting. |
| 28 | ESC1 model → `Esc#` | Optional | ESC identification. |
| 30 | ESC2 voltage → `Es2V` | Optional | Detailed ESC2 telemetry. |
| 31 | ESC2 current → `Es2I` | Optional | Detailed ESC2 telemetry. |
| 32 | ESC2 capacity → `Es2C` | Optional | Detailed ESC2 telemetry. |
| 33 | ESC2 electrical RPM → `Es2R` | Optional | Detailed ESC2 telemetry. |
| 41 | ESC2 model → `Es2#` | Optional | ESC identification. |

These similar-looking names are not interchangeable: `Curr` is Rotorflight's battery-current result, `Vbec` is its selected BEC meter, and `Tesc` is its combined ESC temperature. Removing transmission of `EscI`/`BecV`/`EscT` does not remove the underlying ESC input used to calculate retained values. **Keep the FC's ESC telemetry acquisition, voltage/current sources and governor settings intact.** Only change the radio telemetry selection. [Firmware value providers](https://github.com/rotorflight/rotorflight-firmware/blob/118e9120260bb33f46df4f92052fb0e9fd4e9ebc/src/main/telemetry/sensors.c#L159-L253).

ELRS link statistics (`RQly`/`LQ`, `RSSI`, `TPWR`, `RFMD`) are separate from this FC sensor list. Transmitter voltage, the selected motor switch, the manual modes' model name and Timer 1 are radio-local. Auto uses the FC name already obtained by RF Tool through MSP. None requires an extra `telemetry_sensors` selector. OMPHOBBY's receiver telemetry contract is separate; these Rotorflight CLI commands do not apply to it.

### RF Tool and feature preservation

Retain `ARM`: the KSE admission gate requires current, fresh ARM bit 0 to confirm disarm. Ordinary Lua reads consume values already held by EdgeTX; they do not request each value via MSP. `Gov` and `Hspd` remain needed for instruments/motor alerts, despite their removal from MSP admission conditions. The current arming-blocker banner uses `mspStatus`, so removing `ARMD` reporting does not remove that banner. PID/rate/battery profile telemetry is still needed during flight; the ground MSP operations are not a substitute for it.

On the personal branch, Auto helicopter type preserves the same telemetry requirements. It consumes `rf2.modelName` from the host's existing [MSP name initialization](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/background_init.lua#L130-L156); it does not depend on `MDL#`, require **Set name on TX**, or add KSE name-polling requests. The [Auto confirmation and lifecycle contract](KSE4-KSE5-optimization-review.md#auto-helicopter-type-integration-contract) still applies with the smaller sensor list.

RF Tool's Adjustment Teller consumes `AdjF`/`AdjV`. Retaining selector 99 follows the official instruction to enable Adjustment Function with custom telemetry. There is no need to modify RF Tool or use a special KSE decoder for the smaller selection. [Official RF Lua setup](https://rotorflight.org/docs/setup/radio-setup/radio-setup-edgetx/edgetx-lua-scripts).

RF Tool derives its state events from `ARM`; RfStats requests its statistics through `mspFlightStats` on connection/disarm. Host startup uses link evidence plus `TPWR` or `RFMD` discovery, then MSP API/name/pilot/telemetry configuration and RTC operations. None of these fixed prerequisites needs the optional entries above. `*Cnt` and `*Skp` are synthesized by the custom decoder, not extra FC selectors. [Host state events](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/WIDGETS/RfTool/app.lua#L58-L89), [RfStats events](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/WIDGETS/RfStats/app.lua#L59-L77), [host initialization](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/background_init.lua#L103-L165), [decoder counters](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/rf2tlm_sensors.lua#L319-L357), [Adjustment Teller readers](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/adj_teller.lua#L178-L212).

## Recommended configuration and migration

The selected active list is `43,60,61,89,88,93,15,3,4,5,6,7,8,95,96,97,90,91,92,99,50`. It is compacted into the first 21 slots, followed by 19 zero slots. **Do not paste just the active selection as a complete CLI assignment.** The firmware defines 40 slots. Its CLI array parser neither explicitly clears the remaining slots nor safely guards its comma advancement for underfilled input. The audited 39-value README command was underfilled too. This is a source-level reliability finding; no FC crash was reproduced. Both replacement arrays explicitly specify all 40 slots. [Slot definitions](https://github.com/rotorflight/rotorflight-firmware/blob/118e9120260bb33f46df4f92052fb0e9fd4e9ebc/src/main/pg/telemetry.h#L36-L55), [CLI array parsing](https://github.com/rotorflight/rotorflight-firmware/blob/118e9120260bb33f46df4f92052fb0e9fd4e9ebc/src/main/cli/cli.c#L4783-L4854).

The README uses this configuration, restoring default intervals as part of compacting the selection:

```text
feature TELEMETRY
set crsf_telemetry_mode = CUSTOM
set telemetry_sensors = 43,60,61,89,88,93,15,3,4,5,6,7,8,95,96,97,90,91,92,99,50,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
set telemetry_interval = 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
save
```

`telemetry_interval` is indexed by slot, so compacting a customized list without changing intervals can apply an old override to a different sensor. Resetting all 40 intervals to zero selects the upstream defaults and avoids that mismatch. Nonzero CUSTOM overrides affect the fast interval. Users who want to retain custom timing should remap their overrides to the compacted slots instead of using the all-zero interval line. Additional sensors used by other model functions should also be preserved explicitly. [Interval application](https://github.com/rotorflight/rotorflight-firmware/blob/118e9120260bb33f46df4f92052fb0e9fd4e9ebc/src/main/telemetry/crsf.c#L1362-L1378).

KSE resolves sensors by name, not FC list position; compaction needs no dashboard-code change. Deleting/rediscovering EdgeTX sensors does not reset FC intervals or recreate overrides that were explicitly reset. RF Tool startup reads telemetry configuration rather than restoring custom intervals. [KSE name resolution](../src/shared/telemetry.lua), [RF Tool configuration read](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/background_init.lua#L125-L155).

After saving, reconnect/restart the RF host and discover any missing sensors. Verify required values are live, including `ARM`, and check both dashboards' instruments, warnings, profile indicators, ground profile operations, diagnostic banner, chosen counter and RF adjustment announcements. In Auto, also confirm Electric/Nitro identification with transmitter naming disabled, then check name changes and reconnects before using the model. Removing an EdgeTX sensor from the radio's discovery list alone does not change the FC's configured stream. Conversely, old discovered names can remain listed after their transmission stops; confirm current values rather than relying on their names being present. Preserve radio source assignments instead of indiscriminately deleting all sensors.

The README contains the selected configuration; no FC settings have been applied by this repository change, and the dashboard/RF Tool Lua code is unchanged.

## Backward compatibility

Trimming optional selectors needs no ELRS 4.1-only feature and introduces no new Lua API dependency. The ordinary telemetry-budget conclusion also holds in the audited ELRS 3.6.4 paths; the MSP boost exception differs as documented below.

RF 2.2's firmware `release/4.5.1` (`e69823a3c185cbf1b75fd2701e938e978591a36b`) and Lua 2.2.0 (`b9c7d4f5c3942a5b8ab987054f63d6e96edff791`) have the same mappings for **15 of the 16 minimum-feature selectors** and the same 40-slot layout. The exception is `97` / `BAT#`: the older firmware reserves that enum but does not transmit it in the CUSTOM table, and the older Lua decoder lacks it. A smaller telemetry list cannot supply battery-profile functionality that the installed firmware/tool package lacks. [Older enum](https://github.com/rotorflight/rotorflight-firmware/blob/e69823a3c185cbf1b75fd2701e938e978591a36b/src/main/telemetry/sensors.h#L40-L155), [older CUSTOM table](https://github.com/rotorflight/rotorflight-firmware/blob/e69823a3c185cbf1b75fd2701e938e978591a36b/src/main/telemetry/crsf.c#L701-L795), [older profile decoder](https://github.com/rotorflight/rotorflight-lua-scripts/blob/b9c7d4f5c3942a5b8ab987054f63d6e96edff791/src/SCRIPTS/RF2/rf2tlm.lua#L294-L310), [older slot definitions](https://github.com/rotorflight/rotorflight-firmware/blob/e69823a3c185cbf1b75fd2701e938e978591a36b/src/main/pg/telemetry.h#L36-L55).

Keep the documented RF Tool 2.3 requirement for full features. Treat older firmware/package combinations as partial compatibility requiring separate verification of host APIs and unavailable-feature handling. This audit establishes the sensor mapping subset, not full KSE runtime support on RF 2.2. It also does not change the existing EdgeTX freshness requirement: [KSE admission](../src/shared/msp_admission.lua) cannot admit MSP without `getSourceValue` current/fresh evidence, even though legacy `getValue` can support ordinary displays. Do not weaken that requirement to advertise broader compatibility.

## Rotorflight scheduling and processing cost

Rotorflight samples active values, gives changed values their fast interval and unchanged values their slow interval, then visits eligible CUSTOM sensors in round-robin order. Most listed values use approximately 200 ms changed / 3 s unchanged intervals; `Tesc` uses 500 ms / 3 s. The slow interval receives a little jitter. These are scheduler inputs, not guaranteed delivery times. The order of the CLI list does not establish an ARM-first radio priority. [Scheduler](https://github.com/rotorflight/rotorflight-firmware/blob/118e9120260bb33f46df4f92052fb0e9fd4e9ebc/src/main/telemetry/telemetry.c#L241-L336), [intervals](https://github.com/rotorflight/rotorflight-firmware/blob/118e9120260bb33f46df4f92052fb0e9fd4e9ebc/src/main/telemetry/crsf.c#L728-L827), [CUSTOM initialization](https://github.com/rotorflight/rotorflight-firmware/blob/118e9120260bb33f46df4f92052fb0e9fd4e9ebc/src/main/telemetry/crsf.c#L1362-L1379).

CUSTOM packs multiple sensor entries into a frame and limits FC output with a rate bucket derived from `crsf_telemetry_link_rate` and `crsf_telemetry_link_ratio`. These FC settings are distinct from the actual ELRS RF telemetry ratio. An overloaded selection can slow the update cycle before considering the receiver's queue. Do not blindly raise the FC link rate to compensate. [Frame packing](https://github.com/rotorflight/rotorflight-firmware/blob/118e9120260bb33f46df4f92052fb0e9fd4e9ebc/src/main/telemetry/crsf.c#L1235-L1269), [rate limiting](https://github.com/rotorflight/rotorflight-firmware/blob/118e9120260bb33f46df4f92052fb0e9fd4e9ebc/src/main/telemetry/crsf.c#L119-L151), [rate configuration](https://github.com/rotorflight/rotorflight-firmware/blob/118e9120260bb33f46df4f92052fb0e9fd4e9ebc/src/main/telemetry/crsf.c#L1383-L1400).

Unused values are not necessarily free: a constant value still gets slow updates. ESC2 entries can remain eligible when ESC support is compiled in even without a useful second ESC reading. Removing them reduces active value retrieval/encoding and unnecessary downstream decoding. The scheduler still scans its fixed table, so this is not a proportional reduction in CPU cost. There is no measured evidence here that the original 39 entries overload an FC or cause control-loop misses. [Sensor eligibility](https://github.com/rotorflight/rotorflight-firmware/blob/118e9120260bb33f46df4f92052fb0e9fd4e9ebc/src/main/telemetry/sensors.c#L402-L465).

## ExpressLRS findings

### More sensors primarily compete for telemetry capacity

At an unchanged effective telemetry ratio, extra FC telemetry does not automatically reserve more over-the-air slots. The TX schedules its receive slots from the telemetry denominator; the RX only sends downlink packets at those agreed slots. Reducing sensor traffic can therefore improve freshness and reduce queuing/drops without changing the scheduled RC slot budget. This is a source-based inference, not proof that all configurations have identical end-to-end control timing. [4.1.0 TX scheduling](https://github.com/ExpressLRS/ExpressLRS/blob/a9d4a9cb5b5687c4c9d7e9e7fbdf44ad93651da6/src/src/tx_main.cpp#L846-L890), [4.1.0 RX scheduling](https://github.com/ExpressLRS/ExpressLRS/blob/a9d4a9cb5b5687c4c9d7e9e7fbdf44ad93651da6/src/src/rx_main.cpp#L452-L505).

The important distinctions are:

| Setting or mechanism | What changes | Consequence for this audit |
| --- | --- | --- |
| Explicit telemetry ratio, e.g. 1:32 | Reserves a configured fraction of RF slots for downlink | Sensor count shares that capacity; reducing sensors alone does not change the ratio. |
| `Std` | Uses the ratio assigned to the selected packet rate | It is not a queue-demand-based automatic telemetry-rate increase. |
| `Race` | Uses standard telemetry when disarmed, disables telemetry when armed | Incompatible with preserving live in-flight dashboard telemetry. |
| Dynamic transmit power | Adjusts RF output power using returned link information | This is a different setting from telemetry ratio. |

Sources: [official Lua setting definitions, pinned documentation](https://github.com/ExpressLRS/Docs/blob/043f06727b2859dd5e67b725763645df5bccddee/docs/quick-start/transmitters/lua-howto.md#L185-L186), [packet-rate defaults in 4.1.0](https://github.com/ExpressLRS/ExpressLRS/blob/a9d4a9cb5b5687c4c9d7e9e7fbdf44ad93651da6/src/src/common.cpp#L80-L91), [dynamic power definition](https://github.com/ExpressLRS/Docs/blob/043f06727b2859dd5e67b725763645df5bccddee/docs/software/dynamic-transmit-power.md).

Explicit ratios are not absolute locks against special transfer behavior: MSP/data uplink can override the effective ratio, as described below. There is no evidence in these audited paths that merely adding ordinary FC sensor telemetry triggers that override.

### Ordinary telemetry burst and MSP-triggered boost are different mechanisms

The telemetry bandwidth documentation uses **burst** for allocating already available downlink opportunities between LINK statistics and DATA from the FC. It aims to keep periodic link statistics while using the remaining opportunities for data. This does not itself increase the configured number of downlink slots. [Pinned official burst explanation](https://github.com/ExpressLRS/Docs/blob/043f06727b2859dd5e67b725763645df5bccddee/docs/info/telem-bandwidth.md#L9-L11).

In 4.1.0, an empty DATA sender causes more LINK frames; queued DATA uses the burst allowance. LINK frames can also carry data, and Full-resolution/Gemini modes change payload capacity. Thus unused sensors can increase DATA use, and saturation need not produce a one-to-one reduction in received LINK statistics. The burst limit is calculated from rate and ratio around a 512 ms link-statistics target; this is scheduling intent, not a delivery guarantee under packet loss. [RX selection and packing](https://github.com/ExpressLRS/ExpressLRS/blob/a9d4a9cb5b5687c4c9d7e9e7fbdf44ad93651da6/src/src/rx_main.cpp#L430-L519), [burst calculation](https://github.com/ExpressLRS/ExpressLRS/blob/a9d4a9cb5b5687c4c9d7e9e7fbdf44ad93651da6/src/src/common.cpp#L211-L234).

MSP requests are different: transmitting data uplink alternates with channel packets and requests increased downlink capacity for replies. In 4.1.0 the requested boost is 1:2. In 3.6.4, non-Full-resolution Wide mode has a 1:8 exception for qualifying configured ratios, preserving its switch encoding boundary. The effect depends on actual version and mode. [4.1.0 uplink selection](https://github.com/ExpressLRS/ExpressLRS/blob/a9d4a9cb5b5687c4c9d7e9e7fbdf44ad93651da6/src/src/tx_main.cpp#L561-L603), [4.1.0 boost selection](https://github.com/ExpressLRS/ExpressLRS/blob/a9d4a9cb5b5687c4c9d7e9e7fbdf44ad93651da6/src/src/tx_main.cpp#L336-L368), [3.6.4 Wide exception](https://github.com/ExpressLRS/ExpressLRS/blob/b61c9e24305b2f80046a5e0b3c4edf56c4f059a3/src/src/tx_main.cpp#L274-L318).

The official 3.5.5 warning concerns tools sending MSP/data **from the handset to the model** during flight. Its worst-case 25% control-rate example must not be attributed to an ordinary CUSTOM sensor list or treated as a measurement on later firmware. Version 3.5.5 fixed an associated Wide AUX-channel problem; the release still discourages in-flight MSP in latency-sensitive applications. [Official release warning](https://github.com/ExpressLRS/ExpressLRS/releases/tag/3.5.5).

### Congestion, queues and serial processing

ELRS 4.1.0 has a 512-byte RX telemetry FIFO. It replaces matching queued messages for selected frame types and ordinary broadcast types; other messages append. When a new message does not fit, it removes queued frames from the head until space is available. Excess input can therefore cause missed telemetry as well as delay. This is bounded buffering, not unlimited backlog. [FIFO definition](https://github.com/ExpressLRS/ExpressLRS/blob/a9d4a9cb5b5687c4c9d7e9e7fbdf44ad93651da6/src/lib/rx-crsf/RXOTAConnector.h#L10-L11), [replacement and eviction](https://github.com/ExpressLRS/ExpressLRS/blob/a9d4a9cb5b5687c4c9d7e9e7fbdf44ad93651da6/src/lib/rx-crsf/RXOTAConnector.cpp#L136-L202).

In 3.6.4, `Telemetry::AppendTelemetryPackage` implements the same bounded replacement/append/eviction pattern, also using a 512-byte FIFO. The precise replacement rules are frame-type-specific; it is not safe to assume every named sensor has a separate latest-value slot. [3.6.4 FIFO definition](https://github.com/ExpressLRS/ExpressLRS/blob/b61c9e24305b2f80046a5e0b3c4edf56c4f059a3/src/lib/Telemetry/telemetry.h#L10-L11), [3.6.4 queue logic](https://github.com/ExpressLRS/ExpressLRS/blob/b61c9e24305b2f80046a5e0b3c4edf56c4f059a3/src/lib/Telemetry/telemetry.cpp#L290-L366).

In 4.1.0, CRSF RC frames are written directly to the output port, bypassing the queued-message FIFO; the driver requests immediate RC delivery. Serial input parsing has a per-call byte cap (64 by default), while queued serial output has a separate allowance. These boundaries argue against equating an overflowing telemetry queue with queued RC channel packets. They do **not** prove that UART errors, shared CPU contention or a firmware defect can never affect control delivery. [Direct RC output](https://github.com/ExpressLRS/ExpressLRS/blob/a9d4a9cb5b5687c4c9d7e9e7fbdf44ad93651da6/src/src/rx-serial/SerialCRSF.cpp#L29-L90), [immediate CRSF delivery](https://github.com/ExpressLRS/ExpressLRS/blob/a9d4a9cb5b5687c4c9d7e9e7fbdf44ad93651da6/src/src/rx-serial/SerialCRSF.h#L19-L22), [serial processing bounds](https://github.com/ExpressLRS/ExpressLRS/blob/a9d4a9cb5b5687c4c9d7e9e7fbdf44ad93651da6/src/src/rx-serial/SerialIO.cpp#L8-L32), [default byte caps](https://github.com/ExpressLRS/ExpressLRS/blob/a9d4a9cb5b5687c4c9d7e9e7fbdf44ad93651da6/src/src/rx-serial/SerialIO.h#L105-L122).

FC CPU cost is a separate question. The ELRS source cannot establish Rotorflight scheduler execution time, UART occupancy or control-loop headroom on the user's FC. A sensor list alone cannot establish overload. Any assertion that this list worsens control response through FC load requires measurements with the actual target, firmware, loop rates and serial configuration.

## Practical interpretation and validation limits

Trim sensors because their transmitted values are unused or unnecessarily frequent, after checking dashboard, radio alerts, logging and other widget dependencies. Do not promise an RC latency improvement from the number of removed sensor IDs. Reducing a sensor list and changing the telemetry ratio are distinct changes; increasing telemetry allocation to hide an overloaded list trades away RF uplink opportunities.

Keep normal telemetry available while retaining the project's ground-only policy for new KSE-owned MSP admissions. Removing telemetry needed to confirm disarm would undermine that policy. External RF Tool pages and already-active upstream requests remain separate sources of MSP traffic.

The most useful comparison holds packet mode and telemetry ratio constant, records sensor update ages/loss and FC task statistics before/after a smaller list, and observes over-the-air/uplink traffic if a control-performance claim is intended. The installed TX/RX firmware, packet rate, switch mode, telemetry ratio, RF hardware and Rotorflight build must accompany results. Full-resolution payloads, repeated-send modes, Gemini and 3.x/4.x differences make a universal sensors-to-control-rate formula inappropriate. [Mode parameters](https://github.com/ExpressLRS/ExpressLRS/blob/a9d4a9cb5b5687c4c9d7e9e7fbdf44ad93651da6/src/src/common.cpp#L8-L91).

Sources were checked against official tag refs: [4.1.0 → a9d4a9cb5b5687c4c9d7e9e7fbdf44ad93651da6](https://api.github.com/repos/ExpressLRS/ExpressLRS/git/ref/tags/4.1.0) and [3.6.4 → b61c9e24305b2f80046a5e0b3c4edf56c4f059a3](https://api.github.com/repos/ExpressLRS/ExpressLRS/git/ref/tags/3.6.4). These are audit baselines; exact installed builds still need recording alongside measurements.
