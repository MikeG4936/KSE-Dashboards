# Maintainer documentation

Use the [user guide](../README.md) for installation and operation, [project rules](../AGENTS.md) for agent work, and the [source guide](../src/README.md) for assembly and executable validation.

## Current contracts and evidence

| Document | Consult for |
| --- | --- |
| [Compatibility](compatibility.md) | RF admission, ARM timing, ownership, Auto type, Nitro reminder, footer status and preserved telemetry semantics. |
| [RF integration](rf-integration.md) | Embedded/external RF Tool servicing, pending versus active work, staged profile operations and pinned transport limitations. |
| [Runtime resources](runtime-resources.md) | Compiler margins, callback budgets, shared/native memory accounting and measurement pitfalls. |
| [Transmitter validation](transmitter-validation.md) | Outstanding hardware acceptance, independent review and result reporting. Desktop tests do not close these checks. |
| [OMP Auto](omp-auto-identification-feasibility.md) | Cell-class identification, source qualification, lifecycle and official OMP/CRSF evidence. |
| [Model-image limits](image-resource-limits.md) | Current file/dimension bounds and native decoding/cache costs. |
| [Transmitter battery](edgetx-2.12.4-battery-icon-comparison.md) | Native range, rounding/color parity and saved-option compatibility. |
| [Status icons](edgetx-2.12.4-status-icons.md) | Native signal bars and the firmware API limitation that keeps volume indication deferred. |
| [Telemetry configuration](telemetry-configuration-audit.md) | Rationale and pinned evidence for the user guide's sensor selection, including older-version limitations. |
| [Release packaging](release-packaging.md) | End-user archive contents, exclusions and packaging checks. |

Source-based research is versioned evidence. Recheck affected code and upstream versions before treating it as support for a new release. Keep copyable installation commands in the user guide and test commands beside their suites.

## Proposed work

The [setup and diagnostics panel plan](setup-diagnostics-panel-plan.md) describes proposed behavior, implementation slices and validation gates. Its [EdgeTX feasibility research](setup-diagnostics-edgetx-research.md) records version-pinned API evidence. These documents are planning material, not implemented dashboard features or completed transmitter validation.

## Repository layout

| Path | Purpose |
| --- | --- |
| `KSE4/`, `KSE5/` | Complete installable dashboards. Duplicate generated engine code and bundled sounds are intentional: each folder installs independently. |
| `src/shared/`, `src/variants/` | Authored engine and distinct renderers; generated outputs are checked in alongside them. |
| `tools/assemble.py`, `tools/edgetx/` | Assembly and reproducible EdgeTX compiler/fixture tooling. |
| `tests/` | Current behavior, RF admission, ownership, storage, picker, rendering, Auto, OMP and image-bound regressions. Their README files define each suite's scope. |
| `theme-gallery/` | Offline user previews and their generator/validator. Committed previews let users browse without building them. |
| `tools/images/` | Browser resizer plus an optional Python batch/command-line alternative and its launchers. |
| `flights-count.csv` | Optional starter/example history. Never copy it over a user's existing radio history. |
| `docs/` | Current maintainer contracts and supporting evidence listed above. |

The Git allowlist deliberately excludes local proposals, personal notes and `output/` exports/backups. They are not release inputs. Keep them private unless publication is explicitly requested; do not mistake an old exported archive for the current source or delete a backup merely because it is ignored.

## Historical material

The original optimization audit, six-slice execution plan, stronger RF adapter proposals, pre-alignment battery comparisons and unsafe pre-admission RF trace fixture are retained in Git history rather than active guidance. Their pre-cleanup versions are available at revision `f7126be`:

```sh
git show f7126be:docs/KSE4-KSE5-optimization-review.md
git show f7126be:docs/implementation-plan.md
git show f7126be:docs/rf-adapter-design.md
git show f7126be:docs/edgetx-2.12.4-battery-icon-comparison.md
git show f7126be:tests/rf_trace/README.md
```

Those files describe historical behavior and superseded alternatives. Use the current contracts and validation documents above when changing or releasing the dashboards.
