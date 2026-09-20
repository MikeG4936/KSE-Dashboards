# Transmitter validation

These hardware checks remain outstanding unless a task/PR handoff supplies results for the identified radio, firmware and dashboard revision. The implemented software contracts and desktop tests do not establish native LVGL memory, complete callback timing, SD durability, RF delivery or latency. This replaces the hardware portion of the original optimization sequence; it is not an instruction to repeat completed implementation slices.

Use the [source guide](../src/README.md) for reproducible software checks, [compatibility contracts](compatibility.md) for preserved behavior, and [resource requirements](runtime-resources.md) for measurement limits. Obtain independent EdgeTX compatibility and RF safety/parity review for substantive RF changes, and parity review for shared-engine changes. Resolve findings before dependent changes proceed.

## Completion gate

**Scope:** the remaining radio-dependent checks. Measure before tuning; prioritize allocation bursts, callback work and resource lifetime. Compare RF Tool alone with RF Tool plus each dashboard and attribute outbound requests by owner.

**Done when:** the relevant validation matrix below is satisfied on the supported firmware/radio combinations, including the smallest-memory target; memory and instruction margins are recorded; repeated lifecycle operations show bounded retained memory; RF traces confirm the chosen scheduling policy. Any claimed latency gain has a measured basis. All preceding hardware checkpoints and substantive review findings are resolved, or the handoff explicitly identifies why final transmitter validation remains incomplete.

## Validation matrix

Minimum validation matrix:

| Dimension | Required cases |
|---|---|
| Radio/display | 480×272, 480×320, 800×480; normal widget/fullscreen transitions; actual supported transmitter builds |
| Aircraft | Electric, Nitro, OMP M1 and M2; incomplete sensors; USB-only FC; valid zero battery |
| Safety | Stale/missing/invalid ARM; conflicting armed RF state; arm/link loss between each write stage; confirmed disarm with rotating or missing/stale Gov/Hspd still permits admission; no added 40-tick settle; preserve the 150-tick FC-count post-disarm wait |
| Telemetry/RF | Compare RF Tool alone versus RF Tool+KSE and identify request ownership; no new KSE-owned MSP admissions without confirmed disarm; distinguish already-active upstream retries from new requests; slow custom CRSF + MSP, dropped/truncated/delayed replies, reconnect and FC reboot; hidden host and visible RF Tool |
| Counters/storage | Both sources; timer directions/resets; multiple qualified arm cycles; stats disabled; failed/recovered file writes; oversized history |
| Lifecycle | Theme/reserve/motor-source/counter/type changes; model change; widget deletion/recreation; duplicate instances; provider replacement |
| Alerts | Every threshold, hysteresis, missing samples, pack replacement, switch acknowledgement, queued haptics, voice disabled, tool-screen interruption |
| Resources | Per-function compiler gates; before/after bytecode; initial compile/load, RF startup, full history load/save, UI rebuild, repeated screen changes; callback instruction and combined memory peaks on normal non-DEBUG builds |
| Parity | Feed identical timestamped inputs/options/replies to both; compare normalized values, validity, alert events, count changes, and outgoing MSP |

## Feature-specific checks

- **Ownership and recovery:** saved-model A→B→A, same-model recreation, duplicate widgets across variants, hidden/visible and external/embedded RF Tool, stale callbacks, provider replacement, queue faults and dropped replies. Preserve active upstream requests and foreign work while invalidating old KSE work.
- **ARM timing:** ordinary three-second updates, initial/FC post-flight reads, armed updates between fresh pulses, intentional source/link loss and callback suspension. Keep the four-second observed-update window and existing FC-count wait; never infer zero traffic from rejected admissions.
- **Auto Elec/Nitro:** FC name confirmation and changes with transmitter naming disabled; unresolved/confirmed/disconnected transitions; separate pictures/counts; provider replacement between profile stages.
- **OMP Auto:** both aircraft with full and partly used packs, actual RxBt/Volt/RPM discovery and update timing, cross-aircraft reconnects, brief in-flight dropout, separate pictures/counts and manual OMP. Check the actual shared model's channel mapping, throttle/collective, binding and Model Match on both helicopters.
- **Battery and signal icons:** compare native/KSE battery empty/full and color transitions at each physical width, then edit the radio battery range; inspect signal readability and real link-loss timing. Simulator RSSI expiry is not hardware evidence.
- **Nitro reminder:** native duration-choice popup and upgrade reselection, Timer 1 count-up/countdown and reset, late startup, hidden callbacks/tool suspension, speech/haptic queues and strength, missing-clip fallback, Battery Voice off and both counter choices.
- **Images and picker:** actual decode/fallback, repeated image/model changes, cold-load responsiveness and native memory; dialog/native-menu clipping, wheel focus, touch selection and all supported display sizes.
- **Persistence and alerts:** removed/full/failing SD, interrupted writes, backup/temporary recovery and dirty-count handoff; physical haptic backlog/priority and voice timing.

## Record results

Record the dashboard revision, radio model, EdgeTX/FC/RF Tool/ELRS versions, configuration and assets, procedure, observations, resource deltas, resolved review findings and remaining checks in the task/PR handoff. Distinguish new KSE admissions from later upstream transmissions and RF Tool's own recovery/page activity. Compare RF Tool alone with RF Tool plus each dashboard under identical inputs. A screenshot, successful desktop load or returned `pcall` alone cannot establish hardware compatibility; any claimed latency gain needs measured evidence.
