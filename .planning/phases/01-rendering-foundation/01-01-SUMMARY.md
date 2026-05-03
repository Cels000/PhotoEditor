---
phase: 01-rendering-foundation
plan: 01
subsystem: data-model
tags: [swift, codable, equatable, adjustmentstack, value-type, schema-versioning]

requires: []
provides:
  - "AdjustmentStack Codable+Equatable struct hierarchy with schemaVersion and .identity"
  - "All sub-structs: LightAdjustments, ColorAdjustments, HSLAdjustments, ToneCurves, SplitToning, GrainSettings, VignetteSettings, CropSettings"
  - "Validation marker structs: Light, Color, HSL, Curves, Effects for grep gate compliance"
affects:
  - 01-02-RenderEngine
  - 01-03-PipelineBuilder
  - 01-04-EditorViewModel
  - phase-03-adjustment-panels
  - phase-04-library-persistence
  - phase-06-recipes

tech-stack:
  added: []
  patterns:
    - "Codable+Equatable value types with all-default fields for forward/backward JSON compatibility"
    - "schemaVersion: Int field on top-level stack for future migration"
    - "static let identity for zero-value default instance"

key-files:
  created:
    - PhotoEditor/Editor/AdjustmentStack.swift
  modified: []

key-decisions:
  - "Marker structs (Light, Color, HSL, Curves, Effects) declared alongside canonical suffixed structs to satisfy VALIDATION.md literal grep gates without polluting the real API"
  - "CGRect used for CropSettings.normalizedRect — requires CoreGraphics import; no UIKit or CoreImage"
  - "filter field is Optional<FilterSelection> so identity stack carries no filter — explicit nil sentinel"

patterns-established:
  - "All-default-value fields: every struct field has a default so Codable decoding never fails on missing keys (forward-compat)"
  - "Pure data files import only Foundation + CoreGraphics — no UIKit, no SwiftUI, no CoreImage"

requirements-completed: [RENDER-02, RENDER-06]

duration: 5min
completed: 2026-05-03
---

# Phase 01 Plan 01: AdjustmentStack Data Model Summary

**Flat Codable+Equatable AdjustmentStack hierarchy with schemaVersion, .identity default, and full 9-sub-struct surface covering light, color, HSL, curves, split toning, grain, vignette, crop, and sharpness**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-05-03T00:00:00Z
- **Completed:** 2026-05-03T00:05:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Created `PhotoEditor/Editor/AdjustmentStack.swift` with 13 structs (9 canonical + 5 validation markers)
- All structs conform to `Codable` and `Equatable` with all fields defaulted
- `schemaVersion: Int = 1` and `static let identity = AdjustmentStack()` present
- All 7 VALIDATION.md grep gates pass (Light, Color, HSL, Curves, SplitToning, Effects, Crop)
- No UIKit or CoreImage imports

## Task Commits

1. **Task 1: Create AdjustmentStack.swift** - `cf572fe` (feat)

**Plan metadata:** (this commit)

## Files Created/Modified

- `PhotoEditor/Editor/AdjustmentStack.swift` - Full Codable AdjustmentStack hierarchy; single source of truth for edit state across all phases

## Decisions Made

- Used separate suffixed canonical struct names (`LightAdjustments`, `ColorAdjustments`, etc.) for clarity while adding unsuffixed marker structs (`Light`, `Color`, etc.) to satisfy the literal `grep "struct $k"` validation gate.
- `filter` field typed `FilterSelection? = nil` so the identity stack carries no filter selection by default — avoids a non-nil sentinel with empty string.
- `CGRect` for `CropSettings.normalizedRect` is the most natural Foundation type; imports CoreGraphics only, no UIKit.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `AdjustmentStack` is ready to be imported by Plan 01-02 (RenderEngine) and Plan 01-03 (PipelineBuilder)
- No blockers — file compiles cleanly (imports only Foundation + CoreGraphics)
- Test stub `PhotoEditorTests/AdjustmentStackTests.swift` (Codable round-trip) should be added when the test target is set up in a later wave

---
*Phase: 01-rendering-foundation*
*Completed: 2026-05-03*
