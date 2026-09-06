# KSE4 / KSE5 implementation plan

This is the execution sequence for the accepted optimization review. Use the model and collaboration policy in [AGENTS.md](../AGENTS.md). The [compatibility review](KSE4-KSE5-optimization-review.md) owns finding details, upstream evidence, resource limits and the validation matrix. Ranking expresses value; the sequence below also accounts for dependencies.

## Execution contract

Work as one coordinated task with reviewable slices. Before a slice, verify its findings against the current checkout and identify the affected behavior in both variants. Preserve unrelated work already present. Make one focused commit per completed slice, with validation results in the commit/PR handoff; split a slice further when its changes need independent review. Continue to the next authorized slice once its dependencies and executable checks pass.

Separate software completion from transmitter validation. If hardware is unavailable, complete the independent implementation and reproducible tests, record the exact outstanding radio checks, and hand off that checkpoint. A slice needing RF or hardware evidence remains pending that evidence even when its software portion is complete; do not claim final compatibility or latency results from mocks.

Use review subagents for substantive RF/safety changes and shared-engine extraction. Assign compatibility and RF safety/parity reviews distinct questions; their reports must identify actionable locations, evidence and unmet acceptance criteria. The primary agent resolves findings and reruns affected checks before dependent code proceeds. Small documentation-only or mechanical changes can be verified locally.

## Slices

### 1. Compiler headroom and baseline checks

**Scope:** the compiler-headroom portion of finding 7. Capture behavior before structural changes. Add reproducible tooling that uses the supported EdgeTX Lua core, inspects every prototype, and records locals, registers, upvalues and bytecode size. Establish focused fixtures for telemetry validity, alerts, counters and RF transaction traces. Use minimal scoped extraction to create room for subsequent fixes; retain the existing renderers.

**Done when:** both outputs compile within the review's project headroom targets; unaffected behavior traces match; tooling works from documented inputs without `/private/tmp` dependencies. Record source versions and current measurements. Keep tools/fixtures outside the transmitter deployment folders and add narrow Git allowlist entries for them when created.

### 2. RF lifecycle and ownership

**Scope:** findings 2, 3, 4 and the ownership portion of 8. Establish the shared RF adapter's ownership contract, repair background servicing and Nitro deadlines, align reset/cancellation, and guard duplicate owners. Resolve mixed MSP/custom-telemetry consumption using verified upstream behavior.

**Integration prerequisite:** read the [RF adapter feasibility review](rf-adapter-design.md). The pinned RF Tool public API lacks the transmit/cancellation/demultiplexing hooks needed for the full contract, especially for an already-loaded external host. Resolve whether the supported installation may include an RF Tool integration patch before choosing an adapter. Do not silently narrow external-host support or present admission-only checks as a per-send guarantee.

**Done when:** delayed/dropped replies, foreground/background service, reconnect, provider replacement and resets release or invalidate owned work predictably; foreign work is preserved; telemetry/state service continues. Duplicate dashboard instances cannot silently corrupt the active owner's state. The RF reviewer accepts the queue/transport design and tests. Mark any remaining over-the-air verification explicitly.

### 3. Flight safety and MSP scheduling

**Scope:** findings 1, 10 and 13, using slice 2's ownership/lifecycle contract. Establish sensor identity/freshness and contradictory-state handling; stage profile set, verify and save with safety checks before transmission/retry. Apply the selected ground-only policy to KSE-owned requests, including the diagnostic poll, queued traffic and retries.

**Done when:** no KSE-owned request is emitted by the tested send boundary while armed/rotating or while the required ground-state evidence is unavailable; invalidated operations cannot later mutate the FC. Pre-arm diagnostics work and resume after safe-ground recovery; live instruments, alerts, profile indicators and local counters preserve their existing telemetry behavior. FC count refresh occurs after flight. Preserve official RF Tool recovery/page activity as separately attributed upstream behavior. Exercise every transaction stage and automatic single-profile selection; obtain independent safety and compatibility review.

### 4. Persistence and smaller correctness fixes

**Scope:** findings 5, 6 and 11. Use EdgeTX filesystem/global-constant semantics, recover count files across failures, prevent partial-history overwrites, and reconcile counter and helicopter-mode contracts. Preserve current counting behavior when resolving documentation mismatches unless a behavior change is explicitly specified.

**Done when:** simulated write/rename/interruption failures preserve recoverable counts and visible failure state; oversized histories cannot be silently truncated; the haptic priority flag resolves correctly. Both counter choices have matching cross-variant behavior and accurate documentation, with persisted options retained. Record SD/haptic hardware checks still required.

### 5. Functional parity and compatibility

**Scope:** remaining findings 7 and 8, plus 9, 14 and 15. Finish the shared authored engine and reproducible assembly of standalone variants, align lifecycle and normalization, remove verified dead paths, fix compact picker capability handling, and validate image resources. Maintain separately authored render/style adapters.

**Done when:** one functional source generates both variants; regeneration is deterministic; identical input traces produce matching values, alerts, counts and owned MSP requests. Both outputs pass compiler/resource gates, settings remain compatible, and each dashboard installs independently. Picker/layout checks cover all three target dimensions and theme mappings. An independent reviewer verifies parity and the boundaries between shared behavior and intentional presentation differences.

### 6. Performance and transmitter validation

**Scope:** finding 12 and the remaining radio-dependent checks from earlier slices. Measure before tuning; prioritize allocation bursts, callback work and resource lifetime. Compare RF Tool alone with RF Tool plus each dashboard and attribute outbound requests by owner.

**Done when:** the review's relevant validation matrix is satisfied on the supported firmware/radio combinations, including the smallest-memory target; memory and instruction margins are recorded; repeated lifecycle operations show bounded retained memory; RF traces confirm the chosen scheduling policy. Any claimed latency gain has a measured basis. All preceding hardware checkpoints and substantive review findings are resolved, or the handoff explicitly identifies why final transmitter validation remains incomplete.

## Slice handoff

For each slice, record the concrete behavior change, affected findings, commit, reproducible checks and results, resource deltas, review findings resolved, and any outstanding hardware checks. Keep this in the task/PR handoff rather than appending a running journal to project instructions. Update the README for shipped behavior and maintain the review as dated evidence rather than presenting its original measurements as current forever.
