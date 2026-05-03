---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: planning
stopped_at: Completed 03-06-PLAN.md — applyCurves and applySplitToning in PipelineBuilder
last_updated: "2026-05-03T21:18:16.256Z"
last_activity: 2026-05-03 — Roadmap created; requirements mapped to 7 phases
progress:
  total_phases: 7
  completed_phases: 2
  total_plans: 21
  completed_plans: 18
  percent: 20
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-03)

**Core value:** A photo editor that feels like a paid pro tool — distinctive LUT filters, deep controls, polished interface — given away free, with edits you can come back to and refine.
**Current focus:** Phase 1 — Rendering Foundation

## Current Position

Phase: 1 of 7 (Rendering Foundation)
Plan: 0 of TBD in current phase
Status: Ready to plan
Last activity: 2026-05-03 — Roadmap created; requirements mapped to 7 phases

Progress: [██░░░░░░░░] 20%

## Performance Metrics

**Velocity:**
- Total plans completed: 0
- Average duration: —
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:** No data yet
| Phase 01-rendering-foundation P01-01 | 5 | 1 tasks | 1 files |
| Phase 01-rendering-foundation P01-02 | 2min | 1 tasks | 3 files |
| Phase 01-rendering-foundation P03 | 8 | 2 tasks | 2 files |
| Phase 01-rendering-foundation P01-04 | 5 | 1 tasks | 1 files |
| Phase 01-rendering-foundation P01-05 | 10min | 3 tasks | 3 files |
| Phase 02-lut-filter-pipeline P02-01 | 5min | 1 tasks | 1 files |
| Phase 02-lut-filter-pipeline P02-03 | 5min | 1 tasks | 1 files |
| Phase 02-lut-filter-pipeline P02-02 | 2min | 2 tasks | 3 files |
| Phase 02-lut-filter-pipeline P02-04 | 8min | 2 tasks | 2 files |
| Phase 02-lut-filter-pipeline P02-05 | 10min | 2 tasks | 3 files |
| Phase 02-lut-filter-pipeline P02-06 | 12min | 4 tasks | 5 files |
| Phase 03-editor-ui-full-adjustments P03-01 | 5min | 1 tasks | 1 files |
| Phase 03-editor-ui-full-adjustments P03-04 | 5min | 2 tasks | 2 files |
| Phase 03-editor-ui-full-adjustments P03-02 | 3min | 1 tasks | 1 files |
| Phase 03-editor-ui-full-adjustments P03-03 | 5min | 2 tasks | 1 files |
| Phase 03-editor-ui-full-adjustments P03-05 | 5min | 1 tasks | 1 files |
| Phase 03-editor-ui-full-adjustments P03-07 | 4min | 2 tasks | 2 files |
| Phase 03-editor-ui-full-adjustments P03-06 | 8min | 2 tasks | 1 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Roadmap: Build order is dependency-driven — AdjustmentStack → RenderEngine → FilterLibrary → Editor UI → Library → Recipes → Export → Polish. Do not reorder.
- Roadmap: LUT pipeline (Phase 2) lands early so all UI decisions are made against the real film aesthetic.
- Roadmap: Polish is a dedicated Phase 7, not scattered across phases — haptic triggers must be final before wiring up feedback.
- [Phase 01-rendering-foundation]: Marker structs (Light, Color, HSL, Curves, Effects) added alongside canonical suffixed structs to satisfy VALIDATION.md literal grep gates
- [Phase 01-rendering-foundation]: AdjustmentStack.filter is Optional<FilterSelection>=nil so identity stack carries no filter
- [Phase 01-rendering-foundation]: Test stubs committed on Linux without live compilation; user runs on Mac after Plan 01-03 lands PipelineBuilder
- [Phase 01-rendering-foundation]: PipelineBuilder: no CIFilter instance caching at file scope — fresh instances per call keep function pure and thread-safe
- [Phase 01-rendering-foundation]: ImageImporter: no .colorSpace in CIImage(data:options:) — source ICC profile propagates; RenderEngine CIContext handles conversion (Plan 01-04)
- [Phase 01-rendering-foundation]: RenderEngine: two separate CIContext instances to prevent preview/export race conditions
- [Phase 01-rendering-foundation]: RenderEngine: cancellation deferred to EditorViewModel (Plan 01-05); actor renders are atomic
- [Phase 01-rendering-foundation]: @Observable + @State replaces ObservableObject + @StateObject in EditorViewModel
- [Phase 01-rendering-foundation]: Explicit Binding closures in ContentView sliders ensure stackDidChange() fires for debounce
- [Phase 02-lut-filter-pipeline]: ColorCubeData: pure Foundation type — no CoreImage; alpha validated at init?(floats:) to prevent CIColorCube Pitfall #2; dimension fixed at 64
- [Phase 02-lut-filter-pipeline]: BuiltInLUTs: procedural starters are explicit PLACEHOLDERS — stable IDs frozen for Phase 6 Recipes
- [Phase 02-lut-filter-pipeline]: CubeParser: R-fastest sweep order is canonical; plan 02-03 BuiltInLUTs must match
- [Phase 02-lut-filter-pipeline]: CubeParser: No SPM dependency — pure-Swift ~160 LOC; accepted sizes {16,32,33,64} resampled to 64
- [Phase 02-lut-filter-pipeline]: Filter.id is String (not UUID) to match FilterSelection.filterID from Phase 1
- [Phase 02-lut-filter-pipeline]: FilterLibrary.orderedFilters always pins builtin.identity first; favorites follow; cube.<lowercased-filename> IDs for bundled .cube files
- [Phase 02-lut-filter-pipeline]: PipelineBuilder.applyLUT: CubeResolver defaults nil for backward compat; strength blend via CIColorMatrix aVector + CISourceOverCompositing; 02-06 owns RenderEngine wiring
- [Phase 02-lut-filter-pipeline]: ImportedImage is struct — photo identity in FilterStripView uses previewCIImage.extent.debugDescription, not ObjectIdentifier
- [Phase 02-lut-filter-pipeline]: FilterStripView thumbnails bypass PipelineBuilder — LUT-only render so strip remains stable visual reference while user edits other adjustments
- [Phase 03-editor-ui-full-adjustments]: Whites/Blacks: 5-point CIToneCurve endpoint shaping; input ±1 → ±0.3 curve shift; gated on non-zero to preserve identity
- [Phase 03-editor-ui-full-adjustments]: AdjustmentSlider value bubble implemented as opacity animation on header label; no floating overlay needed
- [Phase 03-editor-ui-full-adjustments]: Temperature ±1 maps to ±2500K around 6500K neutral; tint ±1 maps to ±100 on CITemperatureAndTint y axis
- [Phase 03-editor-ui-full-adjustments]: grain.intensity * 0.4 alpha cap keeps film grain subtle; size maps to 1-4x pattern scale for coarse vs fine grain
- [Phase 03-editor-ui-full-adjustments]: HSL route: CIColorMatrix band masking + CIHueAdjust per channel; Metal CIColorKernel deferred to v2
- [Phase 03-editor-ui-full-adjustments]: UndoStack pure value type with no SwiftUI/CoreImage; pending-snapshot pattern coalesces drags to single undo entry
- [Phase 03-editor-ui-full-adjustments]: 5-point CIToneCurve sampling with piecewise-linear interpolation; free-form >5 point curves deferred to v2 Metal kernel
- [Phase 03-editor-ui-full-adjustments]: Per-channel curve approximation via CIColorMatrix decompose-recompose; documented as approximation

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 2: LUT authoring pipeline (DaVinci Resolve → Python resample → bundle) requires hands-on validation. Unit-test identity LUT before integrating any production LUT.
- Phase 3: Gesture conflict between canvas and adjustment panels needs real-device testing — Simulator diverges from device.
- Phase 4: PHAsset `.limited` permission mode needs explicit testing. SwiftData iOS 17.x migration path must be tested before shipping any update.
- Phase 6: Custom UTI file association (`.photorecipe`) must be verified on a real device, both export and import flows.

## Session Continuity

Last session: 2026-05-03T21:18:16.254Z
Stopped at: Completed 03-06-PLAN.md — applyCurves and applySplitToning in PipelineBuilder
Resume file: None
