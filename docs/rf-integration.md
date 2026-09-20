# RF Tool integration

KSE uses the official RF Tool without transport patches. The [admission policy and ARM timing contract](compatibility.md#rf-admission-policy) govern new work; active requests and foreign work remain upstream-owned. This document explains the integration boundary, not a per-send cancellation or mixed-frame demultiplexing guarantee.

Evidence below uses Rotorflight Lua `aaacfe68407c09d49a26c5aa326c00119b378bb0` and EdgeTX `1511b3f29152f18c704f1f89b3608e0f71317de9`. The private queue/transport closures expose no supported hook for cancelling every active fragment or retry, including those driven by external RF Tool callbacks. An active request may keep retrying indefinitely and can still mutate the FC after KSE invalidates its local operation.

## Primary source references

- [Rotorflight queue](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/MSP/mspQueue.lua), [private MSP transport state](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/MSP/common.lua).
- [RF Tool callbacks](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/WIDGETS/RfTool/app.lua), [CRSF MSP reader](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/MSP/crsf.lua), [custom telemetry reader](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/rf2tlm.lua).
- [EdgeTX manager FIFO implementation](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/lua/api_general.cpp).

## Upstream transport and receive limits

- `src/SCRIPTS/RF2/MSP/mspQueue.lua:5` privately captures the four functions returned by `MSP/common`.
- `mspQueue.lua:45–83` selects a message, sends/retries, advances private pending TX, and polls. There is no admission/cancellation callback. `:118` applies queue-wide `maxRetries` only after processing; changing it does not suppress a first send or a pending fragment.
- `src/SCRIPTS/RF2/MSP/common.lua:3–17` owns private RX/TX state and transport closures. `:19–52` advances fragments; `:55–76` can immediately send the first fragment. `:157–160` clears TX and drains the transport reader.
- `src/SCRIPTS/RF2/MSP/crsf.lua:16–36` discards every raw frame other than the addressed 0x7B MSP response. `src/SCRIPTS/RF2/rf2tlm.lua:19–55` drains every raw frame while decoding only 0x88. Reordering consumers cannot preserve mixed traffic.
- `src/WIDGETS/RfTool/app.lua:281–323,335–351` has official background/refresh callbacks that may process the shared queue independently of KSE. KSE cannot interpose a pre-callback check on those callbacks merely by ordering its own service.
- EdgeTX `radio/src/lua/api_general.cpp:895–912` selects FIFO by current script manager, and `:1153–1179` destructively pops it. Calling another widget's Lua method does not select that widget's manager. Two widget managers are not interchangeable receive contexts.

## Implemented lifecycle boundary

The shared controller in [rf.lua](../src/shared/rf.lua) services a host only when KSE explicitly recorded creating it. For an embedded host, a ready queue receives one processing call followed by `background(host, true)` even during pending requests or queue failure. External RF Tool widgets run their own queue/background callbacks. This follows the pinned [RF Tool callback order](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/WIDGETS/RfTool/app.lua#L281-L351); `true` suppresses the private RF page UI runner under KSE's UI context. It does not repair the mixed-frame decoder limitation described above.

[Widget ownership](../src/shared/widget_owner.lua) admits one KSE engine across both variants. Normal callbacks renew a 500-tick lease. Only foreground refresh can take over: immediately after an observed saved-model session change, or after lease expiry for same-model recreation and unavailable filename evidence. See the [saved-model handoff contract](compatibility.md#saved-model-ownership-handoff). One forwarding registration proxy per provider routes state to the current owner without registering every obsolete widget. Host transfer requires the recorded provider and host identity to remain current.

Takeover preserves the shared dirty count cache, retires pending owned work, and recreates instance state while retaining monotonic operation tokens. Picker callbacks additionally capture the owner epoch. Background resets defer UI cleanup until foreground service. Active upstream transactions and foreign queue entries retain their original behavior; local deadlines and stale callbacks do not cancel them.

The [ownership](../tests/ownership/README.md) and [MSP admission](../tests/msp_admission/README.md) contracts exercise these software boundaries. Real-radio FIFO continuity, memory retention and RF timing remain unverified.

## Owned work and staged operations

Remove only captured, identical pending KSE message objects. Preserve the pending table, foreign FIFO order, upstream queue methods/retry limits and active transport state. `queue.clear()` resets active transport and violates this boundary.

Selection admits set command 176 first. Its acknowledgement stages verify 175; matching verification stages save 250. Each successor waits for a subsequent KSE service with a new admission check. Arming, loss of confirmed-disarm evidence, link loss, model/provider/queue/host/Auto identity changes, reset and ownership takeover invalidate old operations. Stale or duplicate callbacks cannot revive them, even if permission recovers before callback delivery. Local deadlines release KSE tracking without cancelling the active upstream request.

After runtime selection is verified, a failed or timed-out EEPROM save must report that the profile is active but saving failed; do not imply that activation failed or persistence succeeded. Service deadlines in the common Electric/Nitro controller path in both foreground and background. Preserve bounded post-flight confirmation reads and the last confirmed FC total during flight; a timeout must not leave Nitro tracking permanently pending.

The [MSP admission suite](../tests/msp_admission/README.md) covers these boundaries with the pinned upstream queue. Run [ownership](../tests/ownership/README.md) and [Auto lifecycle](../tests/auto_type/README.md) checks for owner and aircraft identity transitions. The mocks do not run the full RF Tool widget, byte framing or actual radio transport; complete the [transmitter checks](transmitter-validation.md) before making hardware claims.
