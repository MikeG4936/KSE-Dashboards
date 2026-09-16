# Dashboard source and assembly

Edit behavior in `shared/*.lua` and presentation in `variants/KSE4` or `variants/KSE5`. `KSE4/main.lua` and `KSE5/main.lua` are fully generated deployment artifacts. Run `python3 tools/assemble.py` after edits and `python3 tools/assemble.py --check` before committing. Both outputs must be committed with their inputs.

The assembler inserts shared lexical fragments and the existing scoped modules into each variant. Includes preserve declaration order and scope. Every shared source must appear exactly once in each output; duplicate/recursive includes and omitted shared modules fail assembly. The radio needs only its selected dashboard folder. There is no runtime dependency on `src`, a package loader or another KSE widget.

Keep telemetry, options, alerts, counters, RF scheduling and lifecycle decisions in the common engine. Renderer files own layout, colors, fonts, image placement and touch geometry. `option_theme.lua` preserves each dashboard's persisted theme mapping. RF prompt/banner/touch fragments execute inside the common controller's existing scope; shared code owns picker intents, validity and request admission. Geometry hooks on `G` adapt creation and rendering without adding another runtime script.

The Nitro fuel reminder reads Timer 1 in shared telemetry service, independently of the selected counter and Battery Voice. Keep its latch separate from RF, type and battery-alert resets. Creation with an expired timer cannot replay it; an observed elapsed value below the configured threshold rearms it. Fuel Check Timer occupies slot 11 as CHOICE on EdgeTX 2.12+: index 1 is Off, indices 2–121 are 00:15–30:00 in 15-second steps, and default index 25 is 06:00. Build the labels once with the descriptor. Changing from the earlier STRING or VALUE field requires reselecting the duration; invalid indices stay Off. Preserve the original ten settings; older firmware keeps its ten-option descriptor and fixed six-minute reminder. See the [fuel reminder contract](../docs/KSE4-KSE5-optimization-review.md#nitro-fuel-reminder-contract) and [Auto lifecycle fixtures](../tests/auto_type/README.md).

ARM sampling retains only a sensor ID and the timestamp of an observed fresh update on the owning widget. Re-read the actual current ARM value each time; apply the [four-second update-evidence contract](../docs/KSE4-KSE5-optimization-review.md#arm-update-timing-contract) consistently to MSP, FC-count settling and footer status. Reset/context/identity loss expires that evidence; motor-stop and OMP freshness rules stay separate.

Auto Elec/Nitro is choice 4 in the existing Heli Type slot. Its confirmed FC name and effective mode belong to the shared engine; renderer fragments only present its status. Synchronize identity before telemetry and before/after embedded RF service. Callback admission independently checks the current published FC name and provider identity, including when an external RF host runs before KSE. Name confirmation does not relax or add a delay to the ARM admission policy.

OMP Auto is choice 5, with effective type OMPHOBBY. `shared/omp_auto.lua` confirms the CRSF pack/average-cell voltage ratio for each connection and supplies the fixed `OMP M1`/`OMP M2` display, image and local-count names. It does not rename the saved EdgeTX model or use the Rotorflight Auto provider. Synchronize before layout and counting; retain confirmed identity through flight and brief telemetry gaps. Follow the [OMP contract and source evidence](../docs/omp-auto-identification-feasibility.md).

Ownership spans both dashboard variants. Preserve monotonically increasing operation tokens when an old widget regains ownership: a captured old callback must never match a new operation. Pending dirty count data lives in the shared ownership registry; cache aliases must follow its current table. Bind each widget to its creation-time saved model filename and observed model generation. A known model change retires the previous owner's pending work; the new model's foreground refresh can take ownership immediately. Creation and background callbacks cannot replace an owner. Same-model recreation and unavailable filename evidence retain the 500-tick fallback; obsolete model callbacks cannot reclaim ownership or draw a duplicate warning. See [ownership contracts](../tests/ownership/README.md) before changing these boundaries.

Validation entry points:

- [Auto helicopter type](../tests/auto_type/README.md): confirmed FC identity, mode transitions, count identity and retained rendering.
- [OMP Auto](../tests/omp_auto/README.md): CRSF source qualification, voltage confirmation, connection retention, image/count identity and RF isolation.
- [Behavior](../tests/behavior/README.md): source identity/freshness, alerts, options and counter parity.
- [MSP admission](../tests/msp_admission/README.md): pinned RF queue, continuation stages and embedded/external servicing.
- [Storage](../tests/storage/README.md): recovery, handoff and instruction profiles.
- [Picker](../tests/picker/README.md) and [rendering](../tests/render/README.md): capabilities, preserved style and actual render-function smoke coverage.
- [Compiler tooling](../tools/edgetx/README.md): every-prototype EdgeTX limits and project margins.

Mocks and desktop compilation establish only their documented scope. Final transmitter validation remains governed by slice 6 of the [implementation plan](../docs/implementation-plan.md).
