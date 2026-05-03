---
phase: 01-rendering-foundation
plan: 03
subsystem: rendering
tags: [CoreImage, CIImage, CIFilter, orientation, color-profile, pipeline]

requires:
  - phase: 01-rendering-foundation
    plan: 01
    provides: AdjustmentStack with LightAdjustments, ColorAdjustments, and all sub-structs

provides:
  - PipelineBuilder: pure enum that maps AdjustmentStack → CIImage filter chain with locked 10-stage order
  - ImageImporter: pure enum that converts photo Data → orientation-correct ImportedImage (preview + export)
  - ImportedImage struct with sourceData, previewCIImage (≤1080px), exportCIImage, pixelSize
  - ImageImportError.invalidImageData for bad data

affects: [01-04-RenderEngine, 02-LUT-pipeline, 03-adjustments-ui]

tech-stack:
  added: []
  patterns:
    - "Pure enum namespace pattern for stateless helpers (PipelineBuilder, ImageImporter)"
    - "CIFilter.exposureAdjust() / colorControls() / highlightShadowAdjust() / vibrance() from CIFilterBuiltins"
    - "CIImage(data:options:[.applyOrientationProperty:true]) + .oriented(forExifOrientation:) for correct orientation"
    - "Stage-deferred identity pass-through pattern with phase comments for future implementors"

key-files:
  created:
    - PhotoEditor/RenderEngine/PipelineBuilder.swift
    - PhotoEditor/Editor/ImageImporter.swift
  modified: []

key-decisions:
  - "PipelineBuilder does NOT cache CIFilter instances at file scope — each call creates fresh instances to keep function pure and thread-safe"
  - "ImageImporter does NOT pass .colorSpace in CIImage(data:options:) dict — source ICC profile propagates automatically; RenderEngine CIContext handles conversion (Plan 01-04)"
  - "Explicit .oriented(forExifOrientation:) call required — .applyOrientationProperty alone only marks metadata without transforming pixels"
  - "Phase-deferred stages (LUT, HSL, curves, grain, vignette, sharpness, crop) are explicit identity one-liners with phase number comments to guide future implementors"

patterns-established:
  - "Pure enum namespace: no stored properties, all static funcs, no actor — enables unit testing in isolation"
  - "Stage order locked in build() comment block: LUT → light → color → HSL → curves → split toning → grain → vignette → sharpness → crop"
  - "Nil-safe filter output: if outputImage returns nil, fall through with prior image rather than crash"

requirements-completed: [RENDER-01, RENDER-02]

duration: 8min
completed: 2026-05-03
---

# Phase 1 Plan 3: PipelineBuilder + ImageImporter Summary

**Pure CIImage pipeline builder with locked 10-stage order and EXIF-orientation-correct photo importer using ICC-profile-preserving CIImage data path**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-05-03T20:30:00Z
- **Completed:** 2026-05-03T20:38:00Z
- **Tasks:** 2
- **Files modified:** 2 (both new)

## Accomplishments

- PipelineBuilder pure enum with `build(stack:source:)` applying Phase 1 light + color stages (exposure, contrast, highlights/shadows, saturation, vibrance) and identity pass-throughs for 8 deferred stages
- ImageImporter pure enum converting photo Data to ImportedImage with full-res oriented CIImage and ≤1080px preview — no UIImage detour, ICC profile preserved
- All 11 acceptance criteria grep gates passing for both files

## Task Commits

1. **Task 1: Create PipelineBuilder.swift** - `3c354bf` (feat)
2. **Task 2: Create ImageImporter.swift** - `cb2ee62` (feat)

## Files Created/Modified

- `PhotoEditor/RenderEngine/PipelineBuilder.swift` - Pure pipeline construction; locked stage order; Phase 1 light + color stages implemented
- `PhotoEditor/Editor/ImageImporter.swift` - Photo import via CIImage data path; EXIF orientation baking; preview downsample

## Decisions Made

- Did not pass `.colorSpace` in `CIImage(data:options:)` — source ICC profile propagates automatically through pipeline; color conversion is deferred to RenderEngine CIContext in Plan 01-04
- Explicit `.oriented(forExifOrientation:)` call kept even though `.applyOrientationProperty: true` is also set — the option only marks metadata, the explicit call bakes pixel geometry

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- PipelineBuilder and ImageImporter are ready to be consumed by RenderEngine (Plan 01-04)
- Stage order locked; Phase 2 (LUT) just needs to fill in `applyLUT`
- Phase 3 adjustment stages have their identity stubs in place with phase comments

---
*Phase: 01-rendering-foundation*
*Completed: 2026-05-03*
