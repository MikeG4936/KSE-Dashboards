# KSE dashboard agent instructions

## Model and collaboration

Use **GPT-6 Astra with High reasoning** for the primary agent and every subagent. When a tool exposes these settings, select `model="gpt-6-astra"` and reasoning effort `high` explicitly. Apply the same configuration to resumed agents. If the environment cannot select or verify that configuration, disclose the limitation rather than claiming compliance or silently choosing another model.

One primary agent owns edits to both dashboard engines and integrates changes. Use subagents for bounded upstream research, independent EdgeTX compatibility review, and RF safety/parity review when those can run alongside useful primary work. Give each reviewer the relevant files, pinned sources, slice scope and acceptance criteria. Parallel implementation is appropriate only for explicitly disjoint files; keep concurrent writers out of `KSE4/main.lua` and `KSE5/main.lua`. Integrate findings before dependent slices proceed.

## Required context

- **Implement the optimization work:** read [the implementation plan](docs/implementation-plan.md) before editing. It defines the six slices, dependencies and completion gates. Continue through authorized slices without routine approval pauses.
- **Change dashboard behavior, RF integration, rendering, storage or resource usage:** read the applicable findings, preservation rules and validation cases in [the compatibility review](docs/KSE4-KSE5-optimization-review.md) first. Its measurements and source lines are dated evidence; recheck the current functions and supported upstream versions before applying a finding.
- **Change installation, options or user-visible behavior:** reconcile the affected [README](README.md) instructions with the resulting code. Preserve existing saved settings and data unless an explicit migration is part of the task.
- **Edit shared sections:** change the authored module under `src/shared`, run `python3 tools/assemble.py`, and require `python3 tools/assemble.py --check` to pass. The marked blocks in each dashboard are generated; surrounding render code remains authored in place. Run the affected [storage](tests/storage/README.md) or [MSP admission](tests/msp_admission/README.md) contracts.

## Project invariants

- Keep KSE4 and KSE5 functionally aligned. Share the functional implementation as the planned extraction proceeds; preserve their intentional layouts, palettes and theme-index mappings.
- Use the shared **800×480 reference geometry**, retaining operation at 480×320 and 480×272. Preserve the ten persisted option slots and standalone dashboard-folder installation contract.
- Preserve normal telemetry, Smart Fuel semantics, flight instruments, counters and alerts. The selected policy stops **all new KSE-owned MSP admission unless disarm is confirmed** while retaining pre-arm diagnostics, ground configuration and post-flight updates. Keep RF Tool unmodified and preserve its initialization/recovery and foreign queue ownership. Already-active requests may continue upstream fragments/retries indefinitely; this is an accepted limitation, not a zero-traffic or measured-latency guarantee. See the review's feature-preservation contract for the exact boundaries.
- Require valid, current and fresh ARM bit 0 disarmed, a live link and ready provider, with no armed host contradiction, before every KSE MSP admission and profile-operation stage. Governor/headspeed do not restrict MSP admission; rotation does not block requests when disarm is confirmed. Add no extra disarm-settle gate; preserve existing FC-count and connection/rate intervals. Invalidate stale callbacks and remove safely identifiable pending owned work across arming, link loss, model/provider change and reset. Preserve active upstream transactions and foreign work; do not claim per-send cancellation through the unmodified RF Tool API.
- Treat EdgeTX's Lua implementation and official Rotorflight source as compatibility authorities. Verify APIs, MSP layouts and telemetry semantics against identified versions; carry relevant commit-pinned citations into the change explanation.

## Completion and resource discipline

Create compiler headroom before expanding helper-heavy code. Apply the review's resource gates to every compiled function in both outputs; distinguish project margins from upstream hard limits. Keep the checker and regression fixtures reproducible from a fresh checkout rather than depending on temporary audit files.

Complete each slice with its relevant behavior/parity tests, EdgeTX compiler checks, resource comparison and independent review where specified by the plan. Report passed checks, unresolved findings and missing radio validation separately. Real-radio memory, timing and RF results require real-radio evidence; desktop compilation or mocks establish only their tested scope.

Keep durable policy here, execution order in the implementation plan, and source evidence in the compatibility review. Update those authorities together when an accepted decision changes; keep task progress and completion logs out of this file.
