# RF adapter feasibility and design review

Design review dated 2026-09-05 for slices 2/3 of the [implementation plan](implementation-plan.md). This records an integration constraint discovered while verifying the original audit, not an implemented scheduling guarantee. RF Lua baseline: `aaacfe68407c09d49a26c5aa326c00119b378bb0`; EdgeTX baseline: `1511b3f29152f18c704f1f89b3608e0f71317de9`. Dashboard line references are pre-primary-refactor KSE4/main.lua.

## Accepted decision: unmodified RF Tool, admission-only control

The user selected **stopping new KSE-owned MSP admission outside safe ground while leaving RF Tool unmodified**. This applies to embedded and already-loaded external hosts. Ground evidence is checked before each new request or profile-operation stage; losing that evidence invalidates continuation callbacks and permits removal of safely identifiable pending owned entries. Foreign requests and active upstream transport state remain intact.

An already-active request may continue sending fragments and retrying indefinitely under the pinned upstream queue policy. This includes a request admitted before arming, link loss, model/provider change or reset. Callback invalidation prevents new KSE stages and stale UI updates; it cannot retract an active request or guarantee that it will not mutate the FC later. The user accepts this boundary. It is neither a per-send safety guarantee nor a guarantee of zero in-flight MSP traffic, and no latency improvement has been measured.

Normal telemetry, Smart Fuel, instruments, alerts, counters and telemetry-driven profile indicators continue. Clear the pre-arm blocker banner whenever safe-ground evidence is unavailable; fresh diagnostics, ground configuration and post-flight FC count reads resume after safe-ground recovery. Preserve official RF Tool initialization, recovery, page activity and queue ownership.

No integration patch or further approval is required for the selected scope. The alternatives below document what stronger per-send cancellation and mixed-frame demultiplexing would require; they are historical design evidence, not prerequisites for the admission-only implementation.

## Historical feasibility finding for stronger transport guarantees

A complete adapter cannot safely retrofit an **already loaded, unmodified external RF Tool** using the public API in this pinned release. The required per-send/per-fragment/per-retry ownership check and mixed receive demultiplexing hooks are absent. Admission checks and operation callback generations are insufficient for that stronger guarantee.

A scoped, versioned adapter is implementable when installed **before** the provider loads its queue and telemetry decoder. It requires a narrow interception of the provider's module loader or explicit upstream dependency-injection hooks; it need not replace global `crossfireTelemetryPush`, global `crossfireTelemetryPop`, or queue methods. Cold-start-only compatibility is materially narrower than the external-host contract. This approach was not selected.

## Primary source references

- [Rotorflight queue](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/MSP/mspQueue.lua), [private MSP transport state](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/MSP/common.lua).
- [RF Tool callbacks](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/WIDGETS/RfTool/app.lua), [CRSF MSP reader](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/MSP/crsf.lua), [custom telemetry reader](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/rf2tlm.lua).
- [EdgeTX manager FIFO and loader implementation](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/lua/api_general.cpp), [standard loadfile environment handling](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/thirdparty/Lua/src/lbaselib.c).

## Why

- `src/SCRIPTS/RF2/MSP/mspQueue.lua:5` privately captures the four functions returned by `MSP/common`.
- `mspQueue.lua:45–83` selects a message, sends/retries, advances private pending TX, and polls. There is no admission/cancellation callback. `:118` applies queue-wide `maxRetries` only after processing; changing it does not suppress a first send or a pending fragment.
- `src/SCRIPTS/RF2/MSP/common.lua:3–17` owns private RX/TX state and transport closures. `:19–52` advances fragments; `:55–76` can immediately send the first fragment. `:157–160` clears TX and drains the transport reader.
- `src/SCRIPTS/RF2/MSP/crsf.lua:16–36` discards every raw frame other than the addressed 0x7B MSP response. `src/SCRIPTS/RF2/rf2tlm.lua:19–55` drains every raw frame while decoding only 0x88. Reordering consumers cannot preserve mixed traffic.
- `src/WIDGETS/RfTool/app.lua:281–323,335–351` has official background/refresh callbacks that may process the shared queue independently of KSE. KSE cannot interpose a pre-callback check on those callbacks merely by ordering its own service.
- EdgeTX `radio/src/lua/api_general.cpp:895–912` selects FIFO by current script manager, and `:1153–1179` destructively pops it. Calling another widget's Lua method does not select that widget's manager. Two widget managers are not interchangeable receive contexts.
- KSE4 `profileServiceEmbeddedRfTool:3563–3614` presently skips telemetry background while pending. `profileCancelOperationQueue:3722–3735` refuses cancellation with any foreign queue message. `profileBeginOperation:4427–4510` prequeues set, verify, save. These are separate faults; none repairs the missing send/receive hooks.

## Historical alternative: explicit upstream interface

The smallest supported change is an explicit provider adapter contract, versioned beyond existing `rfToolApiVersion=1.00`:

1. Queue ownership metadata supplied with a message and retained for all its fragments/retries.
2. A message-scoped `beforeTransmit(message)`/cancellation decision checked before `mspSendRequest` and `mspProcessTxQ` on **every** queue invocation, including official UI/background callers. This must return cancellation without dereferencing a removed current message later in the same invocation.
3. `cancelOwned(owner, generation)` removes only matching pending entries; if the current message matches, cancels its private TX and RX transaction state without clearing foreign pending entries or custom telemetry. Returns a concrete cancelled/drained result.
4. One provider-owned bounded raw-frame demultiplexer that feeds both MSP and RF custom telemetry. Neither consumer drains the other consumer's frames. Official initialization/recovery/page work uses this same transport unchanged in purpose.
5. A documented owner-service entry point / manager responsibility. External RF Tool is serviced by its own EdgeTX callbacks; an embedded host is serviced only by its owning KSE widget. KSE does not directly service an external host through the KSE manager.

Upstream explicit hooks also avoid relying on private queue tables and a loader interception contract that upstream does not promise.

## Historical alternative: pre-initialization adapter with narrower boundary

After hidden `app.lua` factory initialization creates `rf2`, before `app.lua:99–107` loads the queue/background, install a provider-scoped loader interceptor for exactly `MSP/crsf` and `rf2tlm`. Load the original pinned modules in separate environments inheriting `_G`, substituting only each module's `crossfireTelemetryPop` and the MSP module's `crossfireTelemetryPush`. `rf2.loadScript` itself is the interception point; non-target names call its original function. No second MSP/common stack and no duplicate decoder copy are necessary.

**EdgeTX caveat (static finding, requires a dedicated firmware reproducer):** Do not rely on `loadScript(path, mode, env)` here. In the pinned C implementation `api_general.cpp:2167–2179`, `lua_settop(L,0)` discards the supplied environment before `lua_pushvalue(L,env)`. This needs a reproducer/upstream fix before use. Standard `loadfile(path,"bt",env)` is exported (`thirdparty/lua/src/lbaselib.c:483`) and retains the environment correctly (`:286–291`, `load_aux:267–283`). It bypasses loadScript's compilation selection/cache behavior, so startup resource checks must include it. Loading `.luac` needs explicitly compatible compiler/source provenance; do not accidentally prefer stale compiled files.

The shared demultiplexer routes addressed 0x7B (`data[1]=0xEA`, `data[2]=0xC8`) to the original MSP reader and 0x88 to the original custom decoder, preserving frame order within each stream. Use bounded FIFO buffers and raw-pop work budget; preserve other frame handling explicitly. EdgeTX's incoming FIFO is itself only 256 bytes (`telemetry/telemetry.h:237–238`), so no software design can promise losslessness under arbitrarily delayed callbacks. On capacity/work exhaustion, stop draining, count overflow/backpressure, and validate supported rates; do not silently discard the other consumer's frames. Reset/quarantine stale MSP frames on owned transaction cancellation without dropping custom frames.

The scoped push wrapper checks the current queue message's KSE owner/generation and current ground evidence before both the no-argument availability probe and actual push. Foreign messages bypass KSE policy. On invalid owned traffic, latch cancellation and deny transmission; do not remove `currentMessage` during the nested push because upstream processQueue dereferences it afterward. The next service-safe point cancels it. Always recheck generation/provider identity so an old host cannot emit an invalidated operation after replacement.

For current-owned cancellation under the pinned queue implementation, retain/filter the foreign `messageQueue` table, call original `queue:clear()` to discard private current TX state, then restore foreign pending entries. This is only safe if the **current** message is proven owned and no callback/reentrant operation runs during the clear. If the current message is foreign, remove only owned pending entries and leave all current framing untouched. Without the demux, `clear()` also drains custom telemetry and fails the preservation contract. Do not clear the queue merely because every message shares a command number; use message identity.

External providers already holding private queue/decoder closures cannot be retrofitted through these future-load environments. Replacing an idle queue alone leaves the existing decoder in `background.lua`'s private closure, which still consumes raw MSP frames. A supported clean restart/reinitialization or upstream hooks are required.

## Historical operation model if stronger hooks are introduced

- One recorded provider, queue, owner epoch, model/type generation per operation. Capture exact message identities from API insertion before yielding.
- Ground admission and send guard use the same strict sample policy: positively current/fresh ARM-disarmed, recognized stopped governor and zero headspeed, no contradictory host state; missing/invalid/unknown evidence denies owned sends. Use normal telemetry, not a fresh MSP request, to establish permission.
- Set acknowledgement records runtime state, then queues verify only at a subsequent checked stage. Matching verify queues save only after another check. Each message's guard remains active regardless of which caller services it.
- Callback tokens stop stale UI updates; cancellation/guard stops future wire mutations. Both are required. A packet already handed to the radio cannot be retracted; the safety promise concerns evidence at the send boundary and prevents later fragments/retries.
- Deadlines are common-service work in all modes, foreground and background. Bounded owner retry policy is per-message, never a global `maxRetries` modification or one-day sentinel. Do not enqueue continuation from an invalidated callback.
- Keep host heartbeat, ARM tracking, receive-side telemetry and official initialization/recovery servicing active. In-flight suppression applies only to KSE owned messages.
- Clear stale arming-blocker banner when leaving safe ground; retain last confirmed FC count and telemetry-driven indicators; resume diagnostics and post-flight reads after stable safe-ground recovery.

## Applicable lifecycle work under the accepted boundary

- Move Nitro/Electric operation deadline checks into common service and align reset entry points.
- Record model/provider/owner generations and invalidate callback side effects on every reset/replacement.
- Filter not-yet-current owned queue entries by identity without altering a foreign current transaction.
- Leave unresolved active transactions in RF Tool's queue with their callbacks invalidated; KSE deadlines release local bookkeeping only. Preserve message identity for attribution and test the accepted continuing retry behavior. Clearing local operation state does not cancel transport work.
- Add duplicate ownership checks before `create`/`update` mutates shared module options/state. Weak references alone are insufficient if RF Tool's widget registration strongly retains callbacks. A lease/epoch design must recheck ownership at every callback and provide delayed recreation takeover without a permanent global lock. RF work already active across takeover remains subject to upstream retries; duplicate UI/state guarding does not stop that traffic.

## Acceptance probes for the selected policy

- Exercise every KSE request admission and profile continuation stage in Electric and Nitro, foreground and background. Armed/rotating, missing/stale/invalid or contradictory safety evidence must prevent new admissions; diagnostics and post-flight reads resume after safe-ground recovery.
- Invalidate operations at arming, link loss, model/provider change, reset and ownership takeover. Assert no stale callback admits a new stage or updates a new operation. Pending owned removal preserves foreign identity/order and active upstream framing.
- Reproduce an already-active request continuing fragments/retries after KSE invalidation, including dropped replies and upstream unlimited retry behavior. Attribute that residual traffic separately; do not count it as a failed admission gate or claim KSE cancelled it.
- Verify ongoing telemetry, alerts, host heartbeat/recovery and last confirmed FC count; clear the pre-arm banner outside safe ground. Cover embedded and already-loaded external hosts. Record mixed-frame consumption limitations without claiming a demultiplexing fix.
- Run compiler/resource and parity checks, then record outstanding real-radio traffic, memory and timing checks. Software probes establish only their tested scope.

## Historical acceptance probes for a stronger adapter

These probes apply only if a future task adopts the stronger transport adapter; they are not gates for the accepted admission-only scope.


1. Mixed addressed MSP, custom telemetry and unrelated frames in both orders, fragmented responses and delayed/dropped replies; assert original custom decoder updates ARM/Hspd/Bat% through waits and counters are not duplicated across manager FIFOs.
2. Own pending behind foreign current, own current with foreign pending, foreign pending on both sides; cancel before first send, between fragments, before retry, after set ACK, after verify, before save. Foreign identities/order and active framing survive.
3. Mutate ARM/Gov/Hspd currentness/freshness, host contradiction, link, provider, model and owner epoch at every boundary. Assert **actual** outgoing pushes contain no disallowed owned command, including official queue callers between KSE callbacks.
4. Electric/Nitro × foreground/background dropped command 14; timeout releases pending state and later ground diagnostics work. OMP/FC-count unsupported pairing is explicitly exercised.
5. External host already initialized, external cold-start, hidden host, external visible/on another page, decoder reinitialization and sensor deletion. Unsupported adapter installation must fail closed with truthful capability status, never silently use unsafe fallback.
6. KSE4+KSE4, KSE5+KSE5, KSE4+KSE5; update loser, delete/recreate owner, model switch, suspended callbacks, old owner resumes. Only current owner mutates functional state or transmits owned work.
7. Non-debug EdgeTX instruction/memory tests for demux backlog and initialization. Over-the-air tests compare RF Tool baseline against each dashboard; desktop mocks cannot certify radio behavior or latency.
