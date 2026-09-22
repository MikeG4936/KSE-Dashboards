# Dashboard source and assembly

Edit behavior in `shared/*.lua` and presentation in `variants/KSE4` or `variants/KSE5`. `KSE4/main.lua` and `KSE5/main.lua` are fully generated deployment artifacts. Run `python3 tools/assemble.py` after edits and `python3 tools/assemble.py --check` before committing. Both outputs must be committed with their inputs.

The assembler inserts shared lexical fragments and the existing scoped modules into each variant. Includes preserve declaration order and scope. Every shared source must appear exactly once in each output; duplicate/recursive includes and omitted shared modules fail assembly. The radio needs only its selected dashboard folder. There is no runtime dependency on `src`, a package loader or another KSE widget.

Keep telemetry, options, alerts, counters, RF scheduling and lifecycle decisions in the common engine. Renderer files own layout, colors, fonts, image placement and touch geometry. `option_theme.lua` preserves each dashboard's persisted theme mapping. RF prompt/banner/touch fragments execute inside the common controller's existing scope; shared code owns picker intents, validity and request admission. Geometry hooks on `G` adapt creation and rendering without adding another runtime script.

## Behavior contracts

Consult the applicable contract before changing these boundaries:

- **RF, ARM, ownership, Auto Elec/Nitro, Nitro reminder or footer status:** [compatibility contracts](../docs/compatibility.md) and [RF integration](../docs/rf-integration.md) define current behavior, staged operations and retained upstream limitations.
- **OMP Auto:** [identity contract](../docs/omp-auto-identification-feasibility.md#omp-auto-implementation-contract) covers source qualification, acquisition, flight retention and shared image/count identity. It remains separate from Rotorflight Auto and MSP admission.
- **Transmitter battery:** [battery contract](../docs/edgetx-2.12.4-battery-icon-comparison.md#implementation-contract) defines native range/color behavior and unavailable-range handling.
- **Signal or volume indication:** [status-icon contract](../docs/edgetx-2.12.4-status-icons.md) keeps native signal display independent of alert/RF link evidence and documents why volume remains deferred.
- **Image loading:** [resource limits](../docs/image-resource-limits.md) define header screening, fallback and native-memory boundaries.
- **Fullscreen settings:** [menu/storage contract](../docs/settings-menu.md) defines App Mode/activation, fresh setup, draft lifetime, shared values/separate themes, companion transfer and firmware gates.
- **Count storage:** [storage contracts](../tests/storage/README.md) define recovery, dirty-cache handoff and EdgeTX filesystem semantics.

## Validation

Run the affected behavior/parity contracts below and EdgeTX compiler checks for both generated outputs. Create compiler headroom before expanding helper-heavy code; apply the [resource gates](../tools/edgetx/README.md) to every compiled function, distinguish project margins from upstream hard limits, and compare resource usage before and after the change. Keep checkers and regression fixtures reproducible from a fresh checkout.

Recheck current functions and the cited upstream versions before extending a contract. Hardware acceptance and independent review requirements are in [transmitter validation](../docs/transmitter-validation.md).

Validation entry points:

- [Auto helicopter type](../tests/auto_type/README.md): confirmed FC identity, mode transitions, count identity and retained rendering.
- [OMP Auto](../tests/omp_auto/README.md): CRSF source qualification, voltage confirmation, connection retention, image/count identity and RF isolation.
- [Behavior](../tests/behavior/README.md): source identity/freshness, alerts, options and counter parity.
- [MSP admission](../tests/msp_admission/README.md): pinned RF queue, continuation stages and embedded/external servicing.
- [Settings](../tests/settings/README.md): schema, interrupted saves, draft/native callbacks, model/owner lifetime and full-dashboard integration.
- [Storage](../tests/storage/README.md): recovery, handoff and instruction profiles.
- [Picker](../tests/picker/README.md) and [rendering](../tests/render/README.md): capabilities, preserved style and actual render-function smoke coverage.
- [Image bounds](../tests/assets/README.md): supplied assets, PNG/BMP headers and bounded resource checks before native decoding.
- [Compiler tooling](../tools/edgetx/README.md): every-prototype EdgeTX limits and project margins.

Report passed checks, unresolved findings and outstanding radio validation separately. Real-radio memory, timing and RF claims require real-radio evidence; mocks and desktop compilation establish only their tested scope. Use the [transmitter validation matrix](../docs/transmitter-validation.md) for outstanding hardware checks.

The [maintainer documentation index](../docs/README.md) maps current contracts, source evidence, release packaging and historical material.
