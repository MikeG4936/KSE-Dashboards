# KSE4 / KSE5 optimization and compatibility review

Date: 2026-09-05

Repository baseline: `12470a0c3f87deaa49d3036708dacc694f5fb73f`

Scope: `KSE4/main.lua`, `KSE5/main.lua`, and the installation/behavior claims in `README.md`. This is an implementation handoff. The initial review changed neither dashboard; the resolution follow-up below subsequently changed KSE5 geometry. This dated review supplies evidence for the [implementation plan](implementation-plan.md). Project instructions and the two linked implementation documents are included in the repository allowlist.

## Superseding RF policy decision

After the feasibility review, the user selected **unmodified RF Tool with ground-only admission of new KSE-owned MSP requests**. This supersedes the stronger per-send/per-fragment/per-retry requirements in the original findings and acceptance language below. Before every new request or profile continuation stage, establish current safe-ground evidence; invalidate stale callbacks and remove safely identifiable pending owned entries when that evidence is lost. Preserve active upstream transactions, foreign queue work, and official RF Tool initialization, recovery and page activity.

An already-active KSE request may continue fragments/retries indefinitely and may still affect the FC after KSE invalidates its operation. That is an accepted upstream limitation. Admission control provides no zero-wire-traffic or per-send cancellation guarantee and establishes no measured latency improvement. No RF Tool patch or additional approval is a prerequisite for the selected scope. The [RF adapter design](rf-adapter-design.md) retains the stronger integration alternatives as historical evidence; the [implementation plan](implementation-plan.md) defines the revised completion gates.

Normal telemetry, Smart Fuel, flight instruments, alerts and local counters continue. Clear the pre-arm blocker banner whenever safe-ground evidence is unavailable; resume fresh diagnostics, ground configuration and post-flight FC count reads after safe-ground recovery. The original source findings and probes remain dated evidence, not a claim that the selected policy or its tests have been implemented.

## Follow-up: shared resolution reference implemented

After this baseline review, KSE5 was rebased from 480×320 to **800×480**, matching KSE4. Scaled horizontal/vertical measurements were converted, with paired reference extents preserving the existing aspect-ratio behavior of rings, insets, and borders. Fixed pixel minima and discrete EdgeTX fonts were retained. This is a geometry refactor, not implementation of the ranked functional fixes below.

Validation used the EdgeTX v2.12.1 Lua core: both production scripts parse successfully, with local-variable counts unchanged. Mock LVGL property/layout comparisons covered 81 combinations of three screen sizes (800×480, 480×320, 480×272), three helicopter modes, three themes, and full-sized/offset/fullscreen-transition zones. Full-screen target geometry matched the previous KSE5 exactly; resized zones allowed at most one pixel of coordinate/size rounding difference from 32-bit floating-point conversion. These are geometry checks, not physical-radio rendering tests. Line references and bytecode figures elsewhere in this report refer to the original review baseline.

## Assessment

The highest-value improvements are correctness and lifecycle fixes, followed by making the functional engine identical between variants. The existing 10 Hz sampling, numeric sensor-ID cache, retained LVGL objects, and changed-property updates are sensible. A wholesale rendering rewrite or more aggressive polling is not justified.

There are confirmed issues with profile-change safety, operation deadlines, pending-request cancellation, file replacement, and a ROM-backed haptic constant. Both dashboards also add periodic MSP status requests while armed; reducing these is an ExpressLRS performance recommendation, not an EdgeTX compatibility requirement. The scripts also sit close to EdgeTX Lua's local-variable ceiling. These are more valuable to address than cosmetic simplification or speculative micro-optimizations.

**This review does not certify bug-free operation on a transmitter.** Source inspection and targeted execution establish the findings below; RF transport, display behavior, instruction budgets, and memory headroom still require the specified simulator/hardware checks. The user's installed EdgeTX/Rotorflight versions were not available, so compatibility is tied to explicit upstream baselines rather than assumed from the radio model.

## Evidence and verification baseline

Primary upstream sources:

- **EdgeTX v2.12.1**, commit [`1511b3f29152f18c704f1f89b3608e0f71317de9`](https://github.com/EdgeTX/edgetx/tree/1511b3f29152f18c704f1f89b3608e0f71317de9). Selected v2.11.0 API definitions were also checked for minimum-version behavior.
- **Rotorflight Lua release/2.3.0**, commit [`aaacfe68407c09d49a26c5aa326c00119b378bb0`](https://github.com/rotorflight/rotorflight-lua-scripts/tree/aaacfe68407c09d49a26c5aa326c00119b378bb0).
- **Rotorflight firmware release/4.6.0**, the Rotorflight 2.3 firmware release series, commit [`118e9120260bb33f46df4f92052fb0e9fd4e9ebc`](https://github.com/rotorflight/rotorflight-firmware/tree/118e9120260bb33f46df4f92052fb0e9fd4e9ebc). Do not confuse the firmware tag numbering with the Lua package version.

Both unmodified files parsed successfully using EdgeTX v2.12.1's own modified Lua 5.3.6 core, built locally with its cross-compiler file-loading path and a stub for firmware debug output. Parser inspection measured:

| Measurement | KSE4 | KSE5 |
|---|---:|---:|
| Source lines | 5,477 | 5,353 |
| Peak simultaneous locals in main chunk | **197 / 200** | **193 / 200** |
| Main chunk stack slots | 222 | 218 |
| Stripped bytecode produced by that core | 107,162 bytes | 108,377 bytes |

Bytecode size is **not** total runtime RAM: closures, tables, strings, LVGL objects, images, and RF Tool add allocations. These measurements do not establish radio memory headroom.

A minimal executable using the same Lua core and its base/math/string/table libraries ran **14 targeted reproduction probes**, seven per script, with mocked radio APIs. They reproduced: missing safety inputs accepted; haptics receiving flag 0 despite ROM-exposed `PLAY_NOW=16`; direct count-file overwrite despite global rename availability; counter increment at threshold before timer reset; Nitro timeout omitted; the KSE4/KSE5 cancellation difference; and acceptance of a current-but-not-fresh source. Assertions deliberately tested the existing defects, not successful application behavior. This harness was not the EdgeTX simulator and did not emulate RF packets, LVGL, radio scheduling, or FatFS failure timing.

## Ranked improvements

Ranking considers impact, confidence, and usefulness; estimated effort is relative. Related changes should be implemented together where indicated.

| Rank | Improvement | Applies to | Evidence | Effort |
|---:|---|---|---|---|
| 1 | Require positive safety evidence and protect every profile-write stage | Both | Confirmed code defect and upstream lack of armed guard | Medium–high |
| 2 | Repair RF Tool servicing and mixed telemetry/MSP ownership | Both | Confirmed servicing gap; integration remedy needs bench validation | High |
| 3 | Run operation deadlines in every helicopter mode | Both | Reproduced Nitro hang condition | Low–medium |
| 4 | Cancel/invalidate owned transactions consistently on reset | KSE5 divergence; hardening in both | Reproduced cancellation difference | Medium |
| 5 | Fix EdgeTX file replacement and prevent history truncation | Both, KSE Counter | Reproduced API mismatch; static data-loss paths | Medium |
| 6 | Resolve `PLAY_NOW` through EdgeTX's normal global lookup | Both | Reproduced wrong flag | Low |
| 7 | Create compiler headroom (prerequisite) and share functional source | Both | Measured limit proximity and concrete drift | Medium–high |
| 8 | Guard duplicate instances and define RF host ownership | Both | Shared state confirmed; crash cause unproven | Medium–high |
| 9 | Fix compact KSE4 picker compatibility and declare supported builds | Primarily KSE4 | Confirmed version/branch mismatch | Low–medium |
| 10 | Make sensor-cache identity and freshness policy explicit | Both | Source/API verified | Medium |
| 11 | Resolve counter/documentation and option-contract mismatches | Both | Reproduced threshold behavior | Low–medium |
| 12 | Profile allocations and callback budgets before tuning hot paths | Both | Existing avoidable work; benefit unmeasured | Medium |
| 13 | Suppress KSE-added in-flight MSP diagnostics on ExpressLRS (selected optimization) | Both | Armed polling reproduced; latency guidance verified, actual impact unmeasured | Medium |
| 14 | Remove obsolete executable paths and misleading historical comments | Both; more executable residue in KSE5 | Static call-site audit | Low–medium |
| 15 | Validate image resources before expensive loading | Both | Missing enforcement; conditional benefit | Low–medium |

### 1. Profile selection needs positive, current safety evidence

**Locations:** KSE4 `profileSwitchUnsafe` at 4574, `profileBeginOperation` at 4427, service at 5064; KSE5 equivalents at 4370, 3932, 4904. Also inspect both `profileFlightCounterArmState` functions.

`profileSwitchUnsafe` rejects an explicitly armed state, a recognized running governor, or a valid nonzero headspeed. It returns safe when those sensors are missing/invalid, including an unknown governor enum. That contradicts the README's positive promise of disarmed/stopped/zero-headspeed gating. The same permissive gate can trigger automatic selection of the sole configured profile without a user opening the picker.

This is not protected by Rotorflight firmware: `MSP_SET_BATTERY_PROFILE` validates the index and changes the profile without checking armed state. EEPROM save has a separate armed check, which does not undo the preceding runtime profile change. See the [release profile setter](https://github.com/rotorflight/rotorflight-firmware/blob/118e9120260bb33f46df4f92052fb0e9fd4e9ebc/src/main/msp/msp.c#L3909-L3918) and [profile mutation](https://github.com/rotorflight/rotorflight-firmware/blob/118e9120260bb33f46df4f92052fb0e9fd4e9ebc/src/main/sensors/battery.c#L251-L257).

There is also a time-of-check gap: set, verify, and save messages are all queued together. The next service pass processes the queue **before** reassessing safety; an already-running select operation is not canceled merely because conditions become unsafe. A stalled RF host can leave `profileRfState="disarmed"` stale; the flight-stat helper returns that state before considering a contradicting current ARM sensor.

**Implement:** use one explicit safe/unsafe/unknown policy for writes. Require fresh-enough disarmed and stopped evidence; missing/malformed/contradictory evidence must block mutation. Preserve the distinction between current and recently refreshed values; choose freshness limits that accommodate the tested telemetry rates. Check safety and operation generation before any owned write/retry can be transmitted. Queue verify only after successful set acknowledgement, and EEPROM save only after a matching verified response and another safety check. Do not rely on callback tokens alone: they prevent stale UI updates, not transmissions. Read-only diagnostics may use a separate policy: their transmission cost and the selected ground-only scheduling policy are assessed in rank 13. That policy choice does not relax the safety requirements for profile writes.

**Acceptance:** no MSP 176/250 for missing, invalid, stale or contradictory safety inputs; no deferred mutation after arming, link loss, model/type change, or reset. Exercise automatic single-profile selection as well as manual selection. Keep the truthful “active but not saved” outcome when persistence fails after a successful runtime change.

### 2. RF Tool background work cannot be suspended throughout MSP waits

**Locations:** KSE4 3515–3615; KSE5 3057–3181, especially `priorityPass` / `priorityServiced`.

While a profile operation or arming-status read is pending, both dashboards process the queue and skip `host.background(host, true)`. That upstream callback refreshes the RF Tool heartbeat, updates ARM-related state, and services RF2 background telemetry. Long unanswered requests can therefore stall the very telemetry used for safety and display. This is especially consequential when combined with rank 3.

The current comments explain a real protocol concern, but the workaround has costs. The [RF Tool callback](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/WIDGETS/RfTool/app.lua#L281-L325) and [RF2 background service](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/background.lua#L20-L98) establish what is skipped.

**Do not fix this by simply swapping two calls.** RF2's [MSP CRSF reader](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/MSP/crsf.lua) can consume non-MSP frames; the [custom telemetry reader](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/rf2tlm.lua) drains frames while handling its custom type. Additionally, EdgeTX selects the telemetry FIFO using the current Lua script manager; invoking another widget's Lua table does not switch manager/FIFO context. See [EdgeTX queue selection](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/lua/api_general.cpp#L895-L912).

**Implement:** centralize the RF integration in a narrow versioned adapter with one identified transport owner. Establish and test how mixed MSP/custom frames reach both consumers without starvation or loss. Preserve bounded telemetry service and host state updates during outstanding requests. Prefer a supported upstream integration or an explicitly tested adapter over monkey-patching queue-wide methods or introducing a second transport. Shared queue internals are implementation dependencies, not a guaranteed permanent public contract.

**Implementation feasibility follow-up:** the [RF adapter design review](rf-adapter-design.md) identifies missing send/cancel/receive hooks in this pinned RF Tool release. The user subsequently accepted admission-only control with unmodified RF Tool, including already-loaded external providers. The stronger transport guarantee and demultiplexing design remain historical alternatives; their missing hooks do not block the selected scope. See the superseding policy decision above.

**Acceptance:** with no visible RF Tool, with RF Tool on another screen, and with delayed/dropped MSP replies, monitor continuing `Hspd`, `ARM`, `Bat%`, heartbeat, warnings and reconnect behavior. Run at slow telemetry ratios. Inspect actual outgoing/reply packets; successful queue insertion is not evidence of successful transport.

### 3. Nitro flight-stat requests can wait indefinitely

**Locations:** KSE4 timeout definition 4513 and call 5127; KSE5 4296 and call 4983. Both calls are inside `profileEligible and connected`, where profile eligibility means Electric.

Nitro can start a `flightStats` operation, but never runs that operation's deadline checker. The command-14 message also sets `retryDelay=86400`; the upstream queue defaults to unlimited retries. A missing reply can leave `profileBusy`, `FC.pending`, and the priority-service path latched rather than reaching the intended two-second failure. The targeted probe showed that invoking the omitted deadline checker immediately clears the same expired operation.

The [upstream queue](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/MSP/mspQueue.lua#L7-L150) does not supply KSE's deadline automatically.

**Implement:** service operation timeout/cancellation once in the common RF-service path, independent of profile-picker eligibility and UI visibility. Use a bounded request policy rather than a one-day retry-delay sentinel wherever the integration permits. Check deadlines/safety before additional sends. Retain the bounded post-flight confirmation reads.

**Acceptance:** drop MSP 14 in Electric and Nitro, in foreground and background. Verify timeout, release of owned traffic, a truthful unavailable/stale count, and subsequent working diagnostics. Include the unsupported OMP + Rotorflight-counter setting in the mode tests rather than silently assuming it cannot be selected.

### 4. Reset behavior has diverged and can leave old writes queued

**Locations:** KSE4 `profileResetConnection` 4877; KSE5 4720; common `profileCancelOperationQueue` KSE4 3722 / KSE5 3271.

KSE4 attempts cancellation for an outstanding non-flight-stat profile operation. KSE5 only handles flight-stat operations, then discards `wgt.profileOperation`. A reset during select/snapshot/active-capacity can therefore leave the old messages in the shared queue while forgetting ownership. A mock queue reproduced cancellation in KSE4 and no cancellation in KSE5 for the same pending MSP 176.

Both scripts also have an incomplete cancellation contract: `profileCancelOperationQueue` correctly refuses to clear a queue containing foreign messages, but several callers ignore its false return and forget the operation anyway. The [RF2 queue's clear method](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/MSP/mspQueue.lua) affects shared queue/framing state, so indiscriminate clearing would introduce a different bug.

**Implement:** use identical reset/cancellation code in both variants. Invalidate callbacks with an operation/model/provider generation, preserve ownership until cancellation/drain completes, and prevent future owned writes when invalidated. Handle foreign messages without deleting them. Cancel against the operation's recorded provider/queue, including replacement of global `rf2`. Combine this with staged writes from rank 1.

**Acceptance:** reset during every transaction stage; repeat with another consumer's message ahead/behind it. No old write later executes, no stale response completes a new operation, and foreign traffic continues.

### 5. Count-file replacement currently uses the wrong EdgeTX API

**Locations:** KSE4 `readAll` 587, `writeAll` 606, cache/load/save 1687–1721; KSE5 571, 590, 1652–1686.

The code seeks `dir.rename` or `os.rename`. EdgeTX exposes `dir` as an iterator function and `rename`/`del` as globals; it does not supply the desktop `os` library here. The safe-replacement branch is bypassed and the main CSV is opened with `"w"`. The probe confirmed that global rename availability makes no difference to the current code.

Other data-loss paths: `readAll` silently returns a partial prefix beyond 32 KiB; parsing silently stops after 200 entries. A later save rewrites only the retained subset. Save failure leaves the incremented in-memory count without a dedicated dirty/retry mechanism. Even after API discovery is fixed, a restart between original→backup and temporary→original needs recovery logic.

**Implement:** resolve `_G.rename` and `_G.del`, check numeric FRESULT `0`, write and validate a temporary file, retain a recoverable backup, and recover deterministically on startup. Treat size/entry-limit breaches and read errors as explicit non-writable conditions; never overwrite the source with a partial parse. Track dirty data and bounded retries without counting the same event again. Keep writes out of the critical telemetry path when possible. Preserve the existing CSV identity/format unless an explicit migration is included.

EdgeTX's [`rename` / `del` exports](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/lua/api_filesystem.cpp#L227-L269) return filesystem status. Existing `io.write(f, text)` calling convention and its handle/nil check are correct. [`io.close`](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/thirdparty/Lua/src/liolib.c#L227-L233) discards the underlying close status: `pcall` success cannot prove that media flushed. Do not describe a multi-rename FAT transaction as power-loss-proof.

**Acceptance:** missing/full/removed SD; short/failed write; rename failure; startup with only backup, only temporary, or both; 201 entries; >32 KiB input; malformed records. Existing counts survive and failures remain visible.

### 6. Haptic priority flag is wrong on EdgeTX

**Locations:** KSE4 1133–1137; KSE5 1109–1113.

`rawget(_G, "PLAY_NOW") or 0` bypasses EdgeTX's ROM-backed global lookup. The actual flag is `0x10`; the function consequently calls `playHaptic` with ordinary queued mode. This is a definite, small fix affecting warning responsiveness.

**Implement:** use `_G.PLAY_NOW` / normal global indexing. Audit the other rawget-only probes; the `UNIT_PERCENT` fallback currently happens to be correct at 13, while many font/source probes already include a normal-lookup fallback. Preserve warning duration, cadence, independent voice/haptic behavior, and acknowledgement rules.

Sources: [ROM global lookup](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/thirdparty/Lua/src/linit.c#L44-L85), [`PLAY_NOW` definition](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/edgetx.h#L468).

**Acceptance:** ROM/metatable-style mock resolves flag 16; radio test confirms intended haptics during an existing haptic backlog. This finding concerns `playHaptic`, not a claim that all custom voice playback already requests immediate priority.

### 7. Share functional source and create compiler headroom

KSE4 has only three simultaneous-local slots below the 200 limit; KSE5 has seven. Adding a few ordinary top-level helper declarations can make a valid script fail to compile. EdgeTX uses [modified Lua with 32-bit numeric configuration](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/thirdparty/Lua/src/luaconf.h#L60-L85) and a [200-local parser limit](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/thirdparty/Lua/src/lparser.c#L34).

**Recommended structure:** one authored functional engine for telemetry normalization, battery/motor alert state, statistics, both counters, persistence, options normalization, and the RF adapter. Keep layout, palettes, assets, text placement and widget-specific LVGL objects in separate KSE4/KSE5 render adapters. Return a normalized display state so presentation does not independently reinterpret safety or data validity.

For the current “copy one folder” installation contract, a **build-time assembly step generating two self-contained `main.lua` files** is a good first choice. This avoids a new shared runtime file that users might omit and makes generated functional blocks identical. Mark generated files and verify regeneration in CI. A runtime module loaded with EdgeTX `loadScript` is also possible, but must explicitly address installation paths, per-instance factories, memory, errors and cache ownership. Do not introduce standard desktop `require`/package assumptions.

Move helpers into appropriately scoped modules/tables/factories; do not just convert locals into uncontrolled globals. Prefer gradual extraction after regression characterization over a large rewrite. Require parser checks for both outputs after every structural change. Preserve all ten saved option positions, names/keys, and the different theme-index mappings.

**Acceptance:** one functional edit generates equivalent behavior in both dashboards; parser headroom is measured and materially increased; standalone folder deployment remains documented and tested. Compare resulting telemetry/alerts/MSP/CSV traces rather than screenshots alone.

#### Resource limits and anti-growth requirements

This is a prerequisite for implementing the ranked changes, including the flight-time MSP gate; rank 7 does not mean waiting until after new helpers exhaust the compiler. The following measurements were repeated against the **current files after the resolution alignment**, using EdgeTX v2.12.1's modified Lua core and inspecting every compiled function prototype before stripping debug metadata.

| Current measurement | KSE4 | KSE5 |
|---|---:|---:|
| Source bytes, including comments | 202,685 | 199,357 |
| Stripped bytecode bytes | 107,162 | 108,644 |
| Function prototypes including the main chunk | 230 | 249 |
| Highest simultaneous active locals in any function (main chunk in both) | **197** | **193** |
| Highest register/stack-slot requirement in any function | **222** | **218** |
| Highest captured outer-variable count in any function (upvalues) | 46 | 33 |

Both current scripts compile. These are compiler measurements, not firmware heap measurements or runtime instruction counts. A prototype count describes compiled function definitions, not the number of closure objects created at runtime.

**Hard compiler limits in the pinned EdgeTX Lua implementation:**

- **200 simultaneously active local variables per function**, including the main file chunk. A `local function helper(...)` consumes a local-variable slot in its enclosing scope; function parameters and other active locals also count. This is not a dashboard-wide cap of 200 functions. Properly scoped blocks/factories can give different functions separate local budgets. [Parser declaration and enforcement](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/thirdparty/Lua/src/lparser.c#L169-L181).
- **Register demand must remain below 255**: a request for 255 or more registers is rejected, so the accepted maximum is 254. Registers include temporaries as well as locals; large expressions, constructor expressions, or call argument lists can fail even below 200 locals. [Register check](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/thirdparty/Lua/src/lcode.c#L356-L369).
- **255 upvalues per function**. Capturing many outer helpers/state variables into a new closure moves pressure to this separate limit; inspect it when extracting a shared engine. [Upvalue limit](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/thirdparty/Lua/src/lfunc.h#L25-L29), [enforcement](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/thirdparty/Lua/src/lparser.c#L228-L243).

There is no single useful “maximum functions per dashboard” or portable source-file kilobyte allowance to use as a safety budget. Functions consume compiled code, constants and runtime closure memory; locals/registers apply per function, while total memory and execution limits apply separately. Removing comments reduces source size but does not create local/register headroom or materially reduce stripped bytecode. Splitting source files or generating two outputs does not automatically reduce live runtime memory.

**Runtime work is a separate limit:** normal color-widget file execution and `create`, `update`, `refresh`, and `background` calls use a nominal **20,000 Lua VM instruction budget per invocation** in this baseline. The hook counts in batches of 200 and errors once its counter exceeds 100; do not target the boundary or interpret this as a source-code size allowance. Ordinary helper calls and directly invoked RF Tool functions share the current callback budget; moving work into a helper does not reset it. DEBUG builds bypass the normal CPU-limit error, so a DEBUG simulator pass cannot prove compliance. C-side drawing, storage and other API work also requires elapsed-time profiling because Lua VM instruction counts are not a complete time measurement. [Widget hook and DEBUG behavior](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/lua/widgets.cpp#L37-L99), [file execution](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/lua/widgets.cpp#L157-L169), [create](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/lua/lua_widget_factory.cpp#L70-L84), [refresh/background](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/lua/lua_widget.cpp#L504-L550). Do not substitute mixer/permanent-script limits for these widget checks.

**Runtime memory is shared and target-dependent:** EdgeTX's configured `LUA_MEM_MAX` guard sums the script-state Lua heap, widget-state Lua heap and tracked extra memory; it is not a per-dashboard file-size cap. Both installed dashboard definitions and RF Tool can contribute to the loaded footprint even when only one dashboard is active. Track native LVGL/image allocations and overall free memory as well as Lua heap; no single Lua-only measurement establishes whole-radio headroom. [Combined memory check and heap measurement](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/lua/interface.cpp#L1310-L1331), [widget directory loading](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/lua/widgets.cpp#L186-L210). The user's radio/build and runtime peak are not established by this audit, so there is no verified free-RAM margin yet.

For concrete examples, the pinned [Horus-family board](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/targets/horus/board.h#L59-L61) and [rm-h750 board](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/boards/rm-h750/board.h#L43-L45) configure a **6 MiB combined Lua limit**, not 6 MiB per dashboard. The memory check runs [every ten seconds](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/main.cpp#L306-L312), so passing a brief load test does not establish compliance; ordinary allocation failure can also happen independently. Their separate tracked Bitmap budget should not be applied as a universal `lvgl.image` limit: KSE's images use the [native LVGL image path](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/lua/lua_lvgl_widget.cpp#L2021-L2026).

**Measurement pitfalls the implementation must avoid:**

- The pinned core enables [`LUA_FLOORN2I`](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/thirdparty/Lua/src/luaconf.h#L160). Implementation checks reproduced `math.tointeger(1.5) == 1` and `1.5 == 1`; [mixed numeric equality](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/thirdparty/Lua/src/lvm.c#L397-L411) can conceal a fraction. Validate range and fractional parts explicitly for persisted counts and safety-sensitive profile indices. Equality with `math.floor(value)` alone is insufficient; desktop Lua tests can miss this deviation.
- [`getUsage()`](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/lua/api_general.cpp#L2195-L2215) returns the stored completed foreground instruction percentage for an LVGL widget. Reading it inside refresh generally observes the previous completed foreground pass. It does not prove create/update/background compliance; instrument those separately. Include retained property callbacks, which run after refresh in the [foreground path](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/lua/lua_widget.cpp#L294-L318).
- `collectgarbage("count")` measures the current shared Lua state's managed heap in KiB, not all native GUI allocations or an isolated dashboard quota. Use controlled before/after comparisons; do not add forced full collections to each production frame.
- `getAvailableMemory()` must be evaluated on hardware: the pinned [simulator implementation returns a constant 1000](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/edgetx.cpp#L1927-L1944), so that simulator value cannot validate memory headroom.

**Implementation gates (project policy, deliberately below the upstream hard limits):**

1. Create headroom before adding helper-heavy fixes. Target **at most 180 active locals and at most 230 registers in every function**, including each generated main chunk. Both current chunks exceed the proposed local target; that is a refactoring prerequisite, not a claim that their present code fails EdgeTX. Small fixes may land without an increase while the scoped extraction is underway; the completed implementation must meet the target.
2. Compile both outputs with the supported EdgeTX Lua core after every structural change. Add a reproducible checker to the implementation tooling that walks every prototype and reports locals, registers, upvalues, prototype count and stripped bytecode size. Desktop Lua syntax checks alone are insufficient. Inspect metadata before stripping; do not estimate locals by counting `local` text occurrences.
3. Record before/after bytecode and resource results for each implementation batch. Explain increases; reject accidental duplication of old/new engines, full copies of the RF Tool stack, unbounded histories/caches, per-frame closures or whole-table clones. Bytecode growth alone is a review signal, not proof of a RAM failure. Do not invent an arbitrary universal KB limit.
4. Put the new flight-state/MSP admission logic in the shared RF service and reuse its state/helpers. Avoid parallel implementations in every request function, extra polling to determine flight state, or a new permanent scheduler. Preserve ownership and safety semantics while reducing duplication.
5. Profile startup, normal flight, reconnect, dropped replies, profile dialogs, full CSV loads/saves, and repeated theme/screen changes with the intended RF Tool installation and assets. Record peak allocation and callback work, plus retained memory after collection. Repeated operations must not cause unbounded retained growth. Validation must include the smallest-memory supported radio and normal non-DEBUG firmware enforcement. As an initial project target, keep measured worst-case widget Lua work below 75% of its budget (about 15,000 instructions), including invoked RF service; document paths that need incremental processing. This is a proposed margin, not an upstream limit or a claim that the current scripts already meet it.

### 8. Shared module state needs enforcement or isolation

**Locations:** both module-level `OPT`, `D`, `A`, `S`, `F`, `RESOLVED`, `FC`; KSE4 `V`/`OBJECT_STATE` at 2795; KSE5 per-widget UI helpers at 2361.

Two instances of the same widget share module state; one `create`/`update` can change the other's options, reset alerts and counters, or reuse another layout/cache. KSE5 stores UI references per widget, but its telemetry and options remain shared. KSE4 also stores UI references globally. KSE4 and KSE5 are distinct chunks but still interact through global `rf2` and the same CSV.

The README already forbids simultaneous dashboards and reports Emergency Mode. This review confirms unsafe sharing but **does not prove the cause of that reported radio failure**. See [EdgeTX widget instance guidance](https://luadoc.edgetx.org/lua-api-reference/widgets).

**Implement:** initially fail gracefully on an accidental second owner *before it mutates existing state*, with a clearly defined ownership/reload lifecycle. Alternatively move all mutable state into instance factories while retaining a single explicit shared RF service. Do not assume per-widget rendering alone solves the problem. Avoid a permanent global lock that strands a valid reload after widget deletion.

**Acceptance:** two KSE4s, two KSE5s, KSE4+KSE5, deletion/recreation, model switch and visible RF Tool. Either supported isolation or a harmless explanatory duplicate state; no silent counter/state corruption. Keep the existing single-instance deployment recommendation until multi-instance behavior is actually validated.

### 9. KSE4's compact profile picker requires a newer API than its fallback suggests

**Locations:** KSE4 4626, 4717; KSE5 4422, 4532.

KSE4 forces `showNativeBatteryProfileMenu` when height <300 or width <430. EdgeTX v2.11.0 has `lvgl.dialog`, but lacks `lvgl.menu`. On a 480×272 TX16S, the native function returns false and the available dialog is never attempted. KSE5 instead scales a dialog and uses native menu as fallback. This is a functional compatibility divergence, not merely a stylistic choice. The affected case requires a picker; automatic single-profile selection can conceal it.

See [v2.11 LVGL exports](https://github.com/EdgeTX/edgetx/blob/v2.11.0/radio/src/lua/api_colorlcd_lvgl.cpp#L340-L370) and [LVGL overview](https://luadoc.edgetx.org/lua-api-reference/lvgl-for-lua/overview).

**Implement:** capability-driven selection with a compact dialog fallback, or explicitly require a tested EdgeTX release providing the needed native menu on these screens. Add an intelligible unsupported-version message for missing required LVGL APIs. Do not claim compatibility with every EdgeTX build simply because `useLvgl=true` is present.

**Acceptance:** choose among at least two configured profiles at 480×272, 480×320 and 800×480; test both actual APIs and the menu-absent branch. Preserve keyboard/touch navigation and current safety checks.

### 10. Separate cache identity, currentness and safety freshness

**Locations:** KSE4 `get` 671 / `RESOLVED` 449; KSE5 655 / 426; all safety consumers of `getSensorNumber` and `get("ARM")`.

Numeric IDs improve performance, but a still-current ID may refer to a different sensor after deletion/re-discovery. Clearing only when reads fail or become old cannot detect that reassignment. Missing sources are not negative-cached, so an absent sensor is repeatedly resolved. Stale sources can similarly cause repeated metadata probes.

The adapter correctly returns separate current/fresh flags, but most callers discard freshness. `isFresh` is a short recent-update window; `isCurrent` permits a longer sensor-loss interval. Do not treat these as equivalent, and do not indiscriminately require `isFresh` for every displayed number on a slow telemetry link. Sources: [EdgeTX source resolution and value API](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/lua/api_general.cpp#L477-L528), [freshness implementation](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/telemetry/telemetry_sensors.h#L95-L129).

**Implement:** bounded metadata revalidation or explicit discovery/reload invalidation, plus a short negative-cache expiry. Keep readable/current/fresh/known distinctions in the shared sample. Use strict age/evidence policy for mutation and motor-stop acknowledgement, while treating ordinary display validity separately. If the declared minimum provides `getSourceValue`, either require it for safety or make the less informative `getValue` fallback explicitly fail closed for writes.

**Acceptance:** delete and rediscover sensors into reused slots; missing sensors later appear; ARM/headspeed stale while LQ remains live; zero is valid while missing is not. Sampling must recover without manual radio restart and without turning a still-current wrong ID into trusted safety evidence.

### 11. Decide and document the actual counter and mode contracts

**Locations:** KSE4 2551; KSE5 2074; README “KSE Counter”.

The README says resetting Timer 1 after qualification counts the flight. Both scripts actually increment when elapsed time **crosses the threshold**, then rearm when elapsed time drops below it. A 0→20-second probe increments at 20 seconds without a reset. Countdown timers use `start - value`; changing the minimum during an existing flight can also change qualification behavior.

**Implement:** preserve threshold counting and correct the documentation unless reset-triggered counting is the desired product behavior. If behavior changes, give it an explicit regression specification and release note; do not alter it incidentally during refactoring. Review arming-helper documentation too: the RF counter currently trusts RF Tool's armed/disarmed state before consulting the supposedly required ARM sensor. Rank 1 defines the stronger evidence policy.

OMPHOBBY has no RF Tool profile/diagnostic requirement with KSE Counter, but choosing Heli Type=OMPHOBBY leaves the default Rotorflight counter selectable and eligible to start RF Tool. Make this unsupported pairing explicit or handle it deliberately; do not silently switch stored counter preferences during a theme edit.

**Acceptance:** ascending and countdown timers, attach mid-flight, reset before/after threshold, changed minimum, restart after failed save, and each helicopter/counter combination. Two dashboards must produce the same count events.

### 12. Optimize measured callback cost, especially allocation bursts

**Locations:** frame caches and service callbacks in both; KSE4 2797–2841 and 5291; KSE5 2361–2412 and 5190.

Already good: sample at 10 Hz, reuse numeric IDs, preserve extrema in background, avoid repeating unchanged LVGL setters, and cache model-image paths. Keep these.

Remaining opportunities:

- `setLabel`/`setObject` construct fresh property tables even when every displayed value is unchanged. Compare/cache common text/color values before constructing update tables; reuse bounded scratch structures only where EdgeTX does not retain the table unexpectedly.
- Profile service runs every refresh/background call and re-reads some sources outside the 10 Hz sample. Share one coherent sample and clock per service pass; keep event input and needed MSP polling responsive rather than blanket-throttling everything to 10 Hz.
- KSE5 formats many unchanged strings each sample; KSE4 already caches some formatted extrema and flight text. Reuse a small bounded formatting strategy after measurement.
- Count CSV parse/sort/write, RF Tool loading/initialization, and LVGL rebuild can cause larger spikes than steady-state telemetry. Measure those transitions separately.

EdgeTX's non-debug widget hook imposes approximately a **20,000-VM-instruction callback budget**; nested calls are not free, and `pcall` does not neutralize an exceeded budget. See [instruction hook](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/lua/widgets.cpp#L37-L74).

**Acceptance:** record callback instruction use, elapsed time, Lua memory before/after collection, and rebuild/load peaks on each supported class. Preserve alert and input latency. Do not claim a percentage speedup from code appearance alone. Avoid adding forced full GC calls to every frame or removing error handling solely for imagined speed.

### 13. Selected optimization: suppress KSE-added in-flight MSP diagnostics on ExpressLRS

**Conclusion: both dashboards initiate MSP while armed.** This is confirmed KSE behavior, not merely an inference from RF Tool being installed. The clearest path is the recurring arming-blocker/status poll (MSP 101). It runs in Electric and Nitro with either flight-counter setting, including background service. The two variants agree on this behavior; the resolution alignment did not change it.

**Guidance, not a protocol prohibition.** ExpressLRS's [official 3.5.5 release warning](https://github.com/ExpressLRS/ExpressLRS/releases/tag/3.5.5) discourages flight-time MSP requests for latency-sensitive applications because they compete with RC updates and can trigger telemetry boosting. The 3.5.5 AUX-channel fix did not remove that performance concern. Its worst-case 25% example is not a universal measurement for every later mode/version. The same bandwidth-sharing mechanism remains in [4.1.0 boost selection](https://github.com/ExpressLRS/ExpressLRS/blob/a9d4a9cb5b5687c4c9d7e9e7fbdf44ad93651da6/src/src/tx_main.cpp#L336-L368) and [channel/data scheduling](https://github.com/ExpressLRS/ExpressLRS/blob/a9d4a9cb5b5687c4c9d7e9e7fbdf44ad93651da6/src/src/tx_main.cpp#L561-L603), and in [3.6.4 with its Wide-mode exception](https://github.com/ExpressLRS/ExpressLRS/blob/b61c9e24305b2f80046a5e0b3c4edf56c4f059a3/src/src/tx_main.cpp#L274-L318); the installed module version and mode were not supplied. This audit does not establish an actual control-rate reduction on the user's radio.

**Classification:** user-selected performance improvement, ranked below confirmed correctness and lifecycle fixes. It is part of the accepted implementation scope; its classification as guidance rather than an EdgeTX prohibition does not make it skippable. The user accepts established official RF Tool behavior; preserve that baseline and do not classify MSP use alone as a defect. The recommendation here targets **additional requests initiated by KSE**. Calling an official RF Tool API for transport does not make KSE's polling schedule an official RF Tool behavior.

#### What sends requests, and when?

Locations below use the current files after KSE5's resolution conversion, unlike the original baseline references elsewhere in this report.

| Request / activity | Initiator and current behavior | Flight assessment |
|---|---|---|
| Ordinary `getValue` / `getSourceValue` reads for RPM, battery, ARM, profiles, etc. | KSE reads values already held by EdgeTX; no MSP request created by these reads | Receive-only dashboard sampling is not the concern |
| **MSP 101 — arming diagnostics** | **KSE starts** `mspStatus.getStatus`; after a successful response schedules another in 100 ticks (one second). No armed, governor, headspeed, or motor-switch guard in the poll scheduler | **Confirmed repeated requests while armed**, with Electric or Nitro and either counter |
| MSP 14 — FC flight statistics | KSE normally waits for disarmed state plus 150 ticks before starting; normal armed state returns without a new stats request | Intended ground-only. A request queued before arming can still transmit before cancellation because queue processing occurs first; stale RF state is another existing caveat |
| MSP 175 + 32 — battery snapshot | KSE starts these in Electric when `profileSwitchUnsafe` allows it | Normally blocked by known unsafe state; existing fail-open safety inputs and outstanding-queue behavior prevent a firm no-flight guarantee |
| MSP 176 → 175 → 250 — select, verify, save | KSE queues all three after the local safety check | Previously queued traffic can continue after arming. This is a transmission finding; FC rejection of an armed EEPROM save does not make that outgoing request disappear |
| MSP 130 — post-selection active capacity | KSE starts an optional read after selection, using the same safety check | Intended ground-only, with the same pending-request/evidence caveats |
| RF Tool status/configuration pages | Official Status page and profile-switch helpers can periodically request MSP 101; a previously opened page can continue its timer through the official background UI runner | Upstream context-specific polling is real. Its presence establishes supported behavior, not a guarantee of zero ExpressLRS latency cost |
| RF Tool's own initialization/reinitialization | Official background setup obtains FC metadata/configuration and sets its RTC; can rerun after reconnect/reset | Separate upstream behavior; record it and preserve it under the user's stated preference. Do not conflate it with KSE's recurring status poll |
| OMPHOBBY + KSE Counter | KSE's RF feature eligibility is off | No KSE-initiated MSP in this supported pairing; OMP + Rotorflight counter remains a separately selectable, problematic pairing |

**Direct local evidence:** KSE4 `profileBeginArmingStatus` 4046, `profileServiceArmingStatus` 4086, `profileModeAccess` 5054, final service call 5250; KSE5 equivalents 3710, 3750, 4900, 5135. The service only requires connection, an idle queue, no pending operation, and a due timestamp. `connected` explicitly includes `"armed"`. `allowUi=false` suppresses presentation, not requests. A hidden banner does not disable polling, and selecting KSE Counter does not disable diagnostics.

The actual request is built by the official [mspStatus API](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/MSP/mspStatus.lua#L1-L41), but its recurring invocation comes from KSE. RF Tool's ordinary arm-state update reads the `ARM` telemetry value through `getValue`; it does not itself require KSE's one-second MSP 101 loop. See [RF Tool arm-state handling](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/WIDGETS/RfTool/app.lua#L65-L89). The initialized RF background telemetry path is receive-side processing; initialization is a distinct path in [background.lua](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/background.lua) and [background_init.lua](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/background_init.lua).

**RF Tool does poll MSP in its own UI.** The official [Status page](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/PAGES/status.lua) queues command 101 from its timer. The [LVGL framework](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/ui_lvgl_framework.lua#L159-L185) runs loaded page timers at about half-second intervals, and the official [background callback](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/WIDGETS/RfTool/app.lua#L281-L325) can invoke the UI runner for an already opened page. Profile pages also use the [status helper](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/PAGES/helpers/profileSwitcher.lua#L1-L18). KSE calls the embedded background host with `calledFromRefresh=true`, which skips that particular UI-runner invocation; KSE supplies its own recurring status schedule. Therefore, neither “RF Tool never polls while armed” nor “KSE polling is required by ordinary RF Tool background telemetry” is accurate. The distinction is request purpose and lifetime, not whether the transport API is official.

#### Feature-preservation contract for low-latency flight

The user's preferred outcome is lower flight-time link overhead while retaining useful dashboard features. Scope the change to KSE-owned MSP scheduling, not telemetry refresh or the official RF Tool recovery lifecycle. In both scripts, `profileFinishArmingStatus` consumes only `status.armingDisableFlags` for the `ARMING BLOCKED` banner; the other fields in MSP 101 are not used by this callback to drive flight instruments.

| Feature | Behavior with ground-only admission of new KSE MSP |
|---|---|
| Live headspeed/tail RPM, governor, voltage/current, consumed capacity, battery percentage/Smart Fuel, temperatures and link displays | Continue at their existing telemetry/display cadence; none depends on the recurring MSP 101 result |
| Battery/temperature/motor alerts, voice and haptics; timers and local statistics | Continue from existing telemetry/timer inputs; do not disable their service when suppressing requests |
| Active battery, PID and rate profile indicators | Continue from `BAT#`, `PID#` and `RTE#` telemetry |
| `ARMING BLOCKED: ...` diagnostic banner | Refresh before flight; suspend its MSP refresh while armed/rotating. Clear the old banner whenever safe-ground evidence is unavailable so a pre-flight blocker is not presented as current. Resume fresh diagnostics after verified disarmed/stopped recovery. Actual FC arming checks remain unchanged |
| Battery-profile capacities, selection, verification and save | Remain available on the ground. Use already loaded capacities in flight; defer new configuration reads and profile-operation stages during flight; an already-active request can still retry upstream. Loading/reloading KSE while airborne may leave configuration details unavailable until safe ground recovery |
| Rotorflight FC flight count | Keep the last confirmed total visible during flight; refresh after disarm/stopped recovery. This does not change the FC's own counting or persistence. Initial airborne loading may show unavailable until a permitted read |
| KSE Counter | Continue its current local Timer 1/counting behavior independently of MSP; any separate counter fixes retain their own acceptance criteria |

Do not remove the diagnostic feature or label stale data as live. Retain pre-flight diagnostics and post-flight updates. With missing or contradictory safety evidence, explain deferred configuration/diagnostics rather than showing a false ready state. Gating through rotor coast-down can delay post-flight count/diagnostic refresh until the rotor stops; this is intentional. Preserve upstream initialization/reconnect service so the optimization does not prevent normal telemetry recovery. There is no claim of a specific latency improvement until transport measurements establish it.

#### Reproduction and selected implementation

An additional **14 scenario probes** ran with EdgeTX's Lua core, current KSE code, and the release-pinned RF2 `mspQueue`, `mspStatus`, `mspHelper`, and `mspFlightStats` modules. A mock replaced the packet transport, radio APIs, and host lifecycle. Both dashboards repeatedly reached the transport's send function with command 101 while host state was `armed` and ARM telemetry was current/armed, across both helicopter modes and counter choices. Controls showed no MSP for OMP + KSE Counter. Transition probes also observed queued 14 and queued 176/175/250 reaching send while armed. Synthetic replies were used to exercise all stages; they do not claim that the real FC accepts an armed save. This is executable send-path evidence, not an over-the-air capture or RC latency benchmark.

**Selected implementation:** gate each new KSE diagnostics poll, configuration request, profile continuation stage and FC-count read on current safe-ground telemetry/state evidence. This implements the user's scheduling preference; it is not an upstream compatibility mandate. Clear the old arming-blocker banner whenever safe-ground evidence is unavailable and resume fresh diagnostics after safe-ground recovery; ordinary telemetry remains live. Motor-switch position alone is inadequate: defer new admissions through autorotation/coast-down and uncertain/stale safety state. Use existing telemetry inputs to establish permission, not a fresh MSP request.

Apply the selected policy at KSE request admission and callback continuation. Invalidate stale callbacks and remove safely identifiable pending owned entries; preserve active upstream transport state and foreign work. An already-active request may continue fragments/retries indefinitely, including after arming or reset. Keep RF Tool unmodified, preserve its telemetry/recovery service and ordinary display/alarms/cached counts, and retain the existing installation contract. The stronger per-send/demultiplexing adapter is not part of this decision.

**Selected acceptance:** compare RF Tool alone against RF Tool+KSE under identical inputs and distinguish request ownership and admission from later transmission. During armed/rotating or uncertain intervals, KSE admits no new periodic 101 or other owned requests; radio-native telemetry and warnings continue. Exercise loss of safety before each admission/continuation, plus an already-active partial request or retry. Verify stale callbacks cannot admit verification/save after invalidation, while explicitly reproducing the accepted upstream retry limitation. Also cover page changes, hidden and external hosts, stale/disagreeing ARM state, link loss/recovery, rotor coast-down and counter/type changes. Resume diagnostics and post-flight count refresh after safe-ground recovery. Packet traces must attribute residual upstream activity without claiming zero in-flight traffic or an unmeasured latency gain.

**Read-only MSP still transmits a request**, but that fact alone is not a correctness defect. Keep this selected polling change distinct from the confirmed unsafe queued profile writes in rank 1. No MSP policy or RF Tool code was changed as part of this assessment.

### 14. Remove dead engine residue, while preserving intentional rendering differences

KSE4 1800–2235 contains a large commented legacy FC implementation that monkey-patched the queue. It is **not executable** and should not be cited as current queue behavior. Remove it from the working source; Git preserves history. Its removal helps review/readability, not meaningful runtime bytecode savings.

KSE5 retains extra readback/capacity callbacks (`profileReadbackReceived` 3333; `profileFinishCapacities` 3462; capacity callbacks 3513/3559) and generic `profileBeginOperation` branches. Current call sites only request `"select"` and `"activeCapacity"`; the live initial read uses the separate snapshot path. These obsolete executable branches and closures offer real simplification/headroom, subject to call-graph verification. KSE5's `profileRfStatusKey` and some unsafe/transport caches are assigned but not consumed meaningfully.

Both set `OPT.simTelemetry=false` in `applyOptions`, and neither exposes a simulation option. KSE4 has more guards/synthetic getter paths; KSE5 chiefly uses a synthetic frame cache. These differences are mostly unreachable in normal release use. Consolidate simulation as an explicit development-only adapter or remove it from generated production code. Do not casually expose an eleventh widget option.

Remove misleading references to immutable StacyDash/UltiDash source authority and unsupported claims about all other screens ceasing background service. Establish this repository's common engine and pinned upstream interfaces as the maintainable authority.

**Acceptance:** behavior traces unchanged after cleanup; both generated files compile; no removed function is called by an LVGL closure or returned interface. Comments about inactive historical code no longer obscure the actual queue controller.

### 15. Make image limits enforceable without decoding an oversized image first

**Locations:** KSE4 2736; KSE5 2262; README image requirements.

Both resolvers check existence only. The README's 100 KB / 480×272 limits are not enforced, so an oversized user image can still be passed to LVGL. This is a robustness improvement for resource-constrained radios, not proof that supplied images are currently problematic.

**Implement:** use EdgeTX `fstat` for a bounded file-size check and, if dimension enforcement is desired, read a bounded PNG/BMP header or validate assets during installation/build. Do not decode the full image merely to discover that it is too large. Fall back to the supplied image and retain path caching. The API is documented in [EdgeTX filesystem source](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/lua/api_filesystem.cpp#L95-L158).

**Acceptance:** valid PNG/BMP, missing/corrupt image, tiny compressed image with excessive dimensions, excessive file size, and normal fallback at each display resolution.

## Functional divergence map

A raw diff overstates divergence because layouts, theme tables and comments differ heavily. Function-block comparison and call-site review found the following more useful divisions. This is not a claim that a text-diff percentage proves semantic equivalence.

| Area | Current relationship | Target |
|---|---|---|
| Scalar telemetry getters and sensor names | Largely identical; KSE4 has extra simulation branches | Identical adapter, separate simulation provider |
| Battery percentage, reserve, alerts, motor gate, Nitro warnings | Core state machines already closely aligned | Keep exact shared implementation and trace tests |
| Session extrema and timer qualification | Equivalent live logic; counter constant called `RADIO` in KSE4, `STACYDASH` in parts of KSE5 | One terminology and implementation |
| In-flight MSP diagnostics | Both initiate MSP 101 while armed, independently of counter choice | Selected ground-only KSE polling, rank 13; preserve official RF Tool behavior |
| RF provider discovery/service | Nearly equivalent executable behavior; comments differ substantially | One versioned RF adapter; fix starvation and ownership once |
| Reset/cancellation | **KSE5 omits non-flight-stat cancellation** | Common lifecycle logic, rank 4 |
| Battery snapshot | Same active/profile-capacity sequence and raw-capacity interception; KSE5 has redundant wrapper bookkeeping | One snapshot implementation |
| Other profile operations | KSE5 retains unused generic capacity/readback modes | Remove unused branches and share live state machine |
| Options normalization | Theme handling intentionally differs; counter normalization placement/name aliases differ | Shared functional normalization plus variant theme map |
| UI object state | KSE4 module-wide; KSE5 widget-owned | Same lifecycle contract; variant-specific objects/layout |
| Refresh ordering | KSE4 services RF before rendering serviced telemetry; KSE5 renders first and has an extra connection-status-driven lower-panel refresh | Common service order and presentation invalidation contract |
| Initial UI lifecycle | KSE5 has explicit `uiBuilt` guard; KSE4 relies on EdgeTX invoking `update` for LVGL widgets | Harmonize defensively; **not a confirmed blank-start bug** on audited EdgeTX |
| Compact profile dialog/menu | KSE4 forces native menu on short screens; KSE5 scales dialog | Equivalent usable capability coverage, rank 9 |
| Model info/image lookup | Same image search order modulo folder; KSE5 caches whole model info; KSE4 only name | Shared metadata/image resolution with variant asset root |
| Formatting caches | KSE4 caches more number/flight strings; KSE5 directly formats more often | Share bounded formatter where measurement justifies it |
| Simulation and historical code | KSE4 commented legacy FC block and more guards; KSE5 extra executable old profile modes | One development adapter; no obsolete production branches |
| Visual design | Reference geometry, typography, ring/bar widgets, palettes, labels, intentional hidden fields and theme indexing differ | Preserve; these are not accidental engine drift |

The KSE4 startup distinction above was checked against the [EdgeTX LVGL widget constructor](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/lua/lua_widget.cpp#L230-L265), which invokes `update()` after creation for LVGL widgets.

## EdgeTX / Rotorflight rules the implementation must preserve

1. **Use supported widget callbacks and EdgeTX APIs.** Keep `useLvgl=true`, retain LVGL objects, rebuild on actual layout/theme changes, and avoid LCD drawing from background. Do not import desktop Lua file methods, `os`, package-loader assumptions, or radio-incompatible compiled bytecode. Check both parser locals and runtime callback limits.
2. **Preserve the ten option slots and persisted values.** Functional slots/defaults should agree; theme indices intentionally map to different palettes. Avoid an unannounced settings migration.
3. **Keep Rotorflight sensor semantics.** `Vcel` is a scalar average-cell voltage in the RF telemetry contract; it is not an EdgeTX `Cels` table. Do not report `.value` unwrapping as a present Vcel bug or silently replace average-cell voltage with weakest-cell voltage. Keep `Curr`, ARM bit 0, and one-based BAT#/PID#/RTE# conventions. [RF2 sensor definitions](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/rf2tlm_sensors.lua).
4. **Preserve Smart Fuel authority.** Valid Rotorflight `Bat%` is the FC charge estimate; do not replace it with voltage-only percentage or add smoothing to the FC estimate as a performance “optimization.” Keep missing/zero/USB-power distinctions and reserve behavior. [Rotorflight battery charge selector](https://github.com/rotorflight/rotorflight-firmware/blob/118e9120260bb33f46df4f92052fb0e9fd4e9ebc/src/main/sensors/battery.c#L193-L211).
5. **Keep MSP layouts versioned.** Battery profile read/write use 175/176 with zero-based wire indices; save is 250. Verify battery-config/state offsets against the supported firmware. Do not guess that a truncated modern response is a valid legacy packet solely from its length. Flight stats uses read command 14; never send setter 15 for this display. Use the upstream [flight-stat API decoder](https://github.com/rotorflight/rotorflight-lua-scripts/blob/aaacfe68407c09d49a26c5aa326c00119b378bb0/src/SCRIPTS/RF2/MSP/mspFlightStats.lua) and retain API checks and disabled-stat handling.
6. **Account for callback suspension outside normal screens.** EdgeTX ordinarily services widgets on other screens; a blanket claim that another screen gets no callbacks is incorrect. Standalone Lua tools explicitly disable widget refresh while active, so widget-only warnings are not continuously guaranteed in that state. Do not attempt to solve this by automatically adding conflicting `rf2bg` functions. See [standalone tool lifecycle](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/gui/colorlcd/standalone_lua.cpp#L136) and [main-view widget service](https://github.com/EdgeTX/edgetx/blob/1511b3f29152f18c704f1f89b3608e0f71317de9/radio/src/gui/colorlcd/view_main.cpp#L408-L421). Ordinary `lvgl.dialog` suspension was **not established** by this review; test that behavior rather than treating the existing comment as evidence.

## Implementation and validation

Execute the six slices and completion gates in [the implementation plan](implementation-plan.md). That document owns ordering and collaboration; this review owns source evidence, finding-specific acceptance criteria and the matrix below.

Minimum validation matrix:

| Dimension | Required cases |
|---|---|
| Radio/display | 480×272, 480×320, 800×480; normal widget/fullscreen transitions; actual supported transmitter builds |
| Aircraft | Electric, Nitro, OMP M1 and M2; incomplete sensors; USB-only FC; valid zero battery |
| Safety | Stale/missing/invalid ARM/Gov/Hspd; rotor coast-down; conflicting RF state; arm/link loss between each write stage |
| Telemetry/RF | Compare RF Tool alone versus RF Tool+KSE and identify request ownership; no new KSE-owned MSP admissions outside safe ground; distinguish already-active upstream retries from new requests; slow custom CRSF + MSP, dropped/truncated/delayed replies, reconnect and FC reboot; hidden host and visible RF Tool |
| Counters/storage | Both sources; timer directions/resets; multiple qualified arm cycles; stats disabled; failed/recovered file writes; oversized history |
| Lifecycle | Theme/reserve/motor-source/counter/type changes; model change; widget deletion/recreation; duplicate instances; provider replacement |
| Alerts | Every threshold, hysteresis, missing samples, pack replacement, switch acknowledgement, queued haptics, voice disabled, tool-screen interruption |
| Resources | Rank 7 per-function compiler gates; before/after bytecode; initial compile/load, RF startup, full history load/save, UI rebuild, repeated screen changes; callback instruction and combined memory peaks on normal non-DEBUG builds |
| Parity | Feed identical timestamped inputs/options/replies to both; compare normalized values, validity, alert events, count changes, and outgoing MSP |

Acceptance requires both parser checks and real runtime validation. A successful desktop load, a screenshot, or a returned `pcall` success alone is insufficient evidence for EdgeTX/Rotorflight compatibility.
