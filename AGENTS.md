# KSE dashboard agent instructions

## Model and collaboration

One primary agent owns the shared engine and integrates both generated dashboards. Use subagents for bounded upstream research, independent EdgeTX compatibility review, and RF safety/parity review when those can run alongside useful primary work. Give each reviewer the relevant files, pinned sources, slice scope and acceptance criteria. Parallel implementation is appropriate only for explicitly disjoint files; keep concurrent writers out of shared engine files and generated outputs. Integrate findings before dependent slices proceed.

## Project rules

- Keep KSE4 and KSE5 functionally aligned through one authored engine, preserving their intentional layouts, palettes and theme-index mappings. For dashboard edits, follow the [source, assembly and validation rules](src/README.md).
- Use the shared **800×480 reference geometry**, retaining operation at 480×320 and 480×272 and standalone dashboard-folder installation.
- Preserve saved settings and user data unless an explicit migration is part of the task. Keep the original ten option positions, keys and types; append settings only on verified supported firmware, retaining the older descriptor and documented fallback.
- Admit **no new KSE-owned MSP request unless disarm is confirmed**, including every profile-operation stage. For RF or ARM handling, follow the [RF policy](docs/compatibility.md#rf-admission-policy) and [ARM timing contract](docs/compatibility.md#arm-update-timing-contract). Keep RF Tool unmodified and preserve active upstream transactions, foreign work, normal telemetry, Smart Fuel, instruments, counters and alerts. Active requests may retry indefinitely; admission control is not per-send cancellation or a zero-traffic guarantee.
- Treat EdgeTX's Lua implementation and official Rotorflight source as compatibility authorities. Verify APIs, MSP layouts and telemetry semantics against identified versions; include relevant commit-pinned citations in the change explanation.

Keep the [user guide](README.md) aligned with changes to installation, options and user-visible behavior. For release archives, follow the [packaging guide](docs/release-packaging.md).

## Commit messages

Start with a plain-language title and opening paragraph explaining the problem, change and practical purpose. Kyle should be able to judge whether the commit belongs upstream without reading code or knowing internal names. Lead with the effect on users; for maintenance work, explain what becomes safer or easier to maintain.

Put implementation details, citations, test results and limitations after that summary. Describe the commit as it stood at that point in history. When revising an earlier decision, identify its commit, what is being walked back and what remains; distinguish a partial walk-back from a full revert.

Keep task sequencing in implementation plans and completion reports in task/PR handoffs; keep this file focused on durable project policy.
