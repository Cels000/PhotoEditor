---
phase: 01-rendering-foundation
plan: "04"
subsystem: rendering
tags: [metal, core-image, swift-actor, color-management, cicontext]

requires:
  - phase: 01-01
    provides: AdjustmentStack struct
  - phase: 01-03
    provides: PipelineBuilder.build pure function

provides:
  - RenderEngine Swift actor with Metal-backed preview and export CIContexts
  - renderPreview(stack:source:) returning CGImage via previewContext
  - renderExport(stack:source:) returning CGImage via exportContext
  - previewMaxLongEdge = 1080 constant as single source of truth

affects:
  - 01-05-EditorViewModel (cancellation, Task.cancel on render calls)
  - 02-lut-pipeline (uses RenderEngine export path for LUT application)
  - 03-editor-ui (calls renderPreview for live preview)

tech-stack:
  added: []
  patterns:
    - "Two-context strategy: separate CIContext for preview vs export to avoid races"
    - "Metal-backed CIContext(mtlDevice:) with explicit .useSoftwareRenderer: false"
    - "extendedLinearSRGB working space, Display P3 output for wide-gamut correctness"
    - "Actor-isolated rendering: Swift actor guarantees serial access to CIContexts"

key-files:
  created:
    - PhotoEditor/RenderEngine/RenderEngine.swift
  modified: []

key-decisions:
  - "Two separate CIContext instances (not shared) to prevent race conditions between preview and export paths"
  - "Force-unwrap CGColorSpace(name:) acceptable — extendedLinearSRGB and displayP3 are guaranteed system names on iOS 17"
  - "Cancellation deferred to EditorViewModel (Plan 01-05) — each render is atomic, actor needs no Task.checkCancellation"

patterns-established:
  - "RenderEngine: always init with throws — hard failure on no Metal device, never silent fallback to software"
  - "RenderEngine: caller responsibility to downsample source to ≤1080px before renderPreview"

requirements-completed: [RENDER-03, RENDER-04, RENDER-05]

duration: 5min
completed: 2026-05-03
---

# Phase 01 Plan 04: RenderEngine Summary

**Metal-backed Swift actor with separate preview/export CIContexts using extendedLinearSRGB working space, Display P3 output, and explicit .useSoftwareRenderer: false**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-05-03T20:25:00Z
- **Completed:** 2026-05-03T20:30:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Swift actor `RenderEngine` with two isolated Metal-backed CIContexts
- Both contexts configured with extendedLinearSRGB working space and Display P3 output
- Both render methods delegate to PipelineBuilder.build then rasterize with createCGImage
- `previewMaxLongEdge = 1080` constant establishes single source of truth for preview cap
- `init() throws RenderError.noMetalDevice` guards against nil Metal device at startup

## Task Commits

1. **Task 1: Create RenderEngine.swift actor with Metal contexts** - `99d2967` (feat)

**Plan metadata:** (docs commit to follow)

## Files Created/Modified
- `PhotoEditor/RenderEngine/RenderEngine.swift` - Metal-backed render actor with preview and export contexts

## Decisions Made
- Two separate CIContext instances rather than one shared context — prevents race conditions on preview/export paths
- Force-unwrap of CGColorSpace(name:) is intentional: extendedLinearSRGB and displayP3 are guaranteed system names on iOS 17
- No Task.checkCancellation in actor — cancellation is caller's responsibility (EditorViewModel, Plan 01-05); each render call is fast and atomic

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- RenderEngine actor is ready; EditorViewModel (Plan 01-05) can now wire up Task-based cancellation and call renderPreview/renderExport
- PipelineBuilder.build is the only dependency and was delivered in Plan 01-03

---
*Phase: 01-rendering-foundation*
*Completed: 2026-05-03*
