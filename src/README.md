# Dashboard source and assembly

Edit behavior in `shared/*.lua` and presentation in `variants/KSE4` or `variants/KSE5`. `KSE4/main.lua` and `KSE5/main.lua` are fully generated deployment artifacts. Run `python3 tools/assemble.py` after edits and `python3 tools/assemble.py --check` before committing. Both outputs must be committed with their inputs.

The assembler inserts shared lexical fragments and the existing scoped modules into each variant. Includes preserve declaration order and scope. Every shared source must appear exactly once in each output; duplicate/recursive includes and omitted shared modules fail assembly. The radio needs only its selected dashboard folder. There is no runtime dependency on `src`, a package loader or another KSE widget.

Keep telemetry, options, alerts, counters, RF scheduling and lifecycle decisions in the common engine. Renderer files own layout, colors, fonts, image placement and touch geometry. `option_theme.lua` preserves each dashboard's persisted theme mapping. RF prompt/banner/touch fragments execute inside the common controller's existing scope; shared code owns picker intents, validity and request admission. Geometry hooks on `G` adapt creation and rendering without adding another runtime script.

Ownership spans both dashboard variants. Preserve monotonically increasing operation tokens when an old widget regains ownership: a captured old callback must never match a new operation. Pending dirty count data lives in the shared ownership registry; cache aliases must follow its current table. Only an expired foreground refresh can replace an existing owner. See [ownership contracts](../tests/ownership/README.md) before changing these boundaries.

Validation entry points:

- [Behavior](../tests/behavior/README.md): source identity/freshness, alerts, options and counter parity.
- [MSP admission](../tests/msp_admission/README.md): pinned RF queue, continuation stages and embedded/external servicing.
- [Storage](../tests/storage/README.md): recovery, handoff and instruction profiles.
- [Picker](../tests/picker/README.md) and [rendering](../tests/render/README.md): capabilities, preserved style and actual render-function smoke coverage.
- [Compiler tooling](../tools/edgetx/README.md): every-prototype EdgeTX limits and project margins.

Mocks and desktop compilation establish only their documented scope. Final transmitter validation remains governed by slice 6 of the [implementation plan](../docs/implementation-plan.md).
