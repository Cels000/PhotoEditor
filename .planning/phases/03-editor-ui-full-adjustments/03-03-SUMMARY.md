---
phase: 03-editor-ui-full-adjustments
plan: "03"
subsystem: ui
tags: [coreimage, cifilter, grain, vignette, sharpen, pipeline]

requires:
  - phase: 01-rendering-foundation
    provides: PipelineBuilder identity stubs for grain/vignette/sharpness

provides:
  - applyGrain: CIRandomGenerator noise composited over source at configurable intensity and scale
  - applyVignette: CIVignette corner darkening/lightening with feather-controlled radius
  - applySharpness: CISharpenLuminance edge enhancement with 0-2 range mapping

affects: [03-editor-ui-full-adjustments]

tech-stack:
  added: []
  patterns:
    - "identity guard at function entry (guard value != default else return image) for all effects stages"
    - "CIFilter builder pattern with output ?? image fallback"

key-files:
  created: []
  modified:
    - PhotoEditor/RenderEngine/PipelineBuilder.swift

key-decisions:
  - "grain.intensity * 0.4 alpha cap keeps film grain subtle; size maps to 1-4x pattern scale for coarse vs fine grain"
  - "CIVignette intensity ±2 range (double our slider input) gives perceptually useful darkening/lightening"
  - "CISharpenLuminance 0-2 range avoids haloing at low slider values; sharpens only luminance channel"

patterns-established:
  - "Effects group identity guards: value == default → early return input"

requirements-completed: [ADJUST-06, ADJUST-07, ADJUST-08]

duration: 5min
completed: 2026-05-03
---

# Phase 03 Plan 03: Effects Pipeline (Grain, Vignette, Sharpen) Summary

**CIRandomGenerator grain composite, CIVignette corner control, and CISharpenLuminance wired into PipelineBuilder replacing Phase 3 identity stubs**

## Performance

- **Duration:** 5 min
- **Started:** 2026-05-03T21:15:00Z
- **Completed:** 2026-05-03T21:20:00Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- applyGrain composites gray noise over source using CIRandomGenerator + CIColorMatrix (Rec.709 weights) + CISourceOverCompositing; alpha capped at intensity*0.4; size maps to 1-4x scale for coarse vs fine grain
- applyVignette uses CIVignette with intensity doubled (±2 range) and feather mapped to radius 1.0-2.5; both darkening and lightening supported via sign
- applySharpness uses CISharpenLuminance with sharpness doubled (0-2 range) for perceptually linear response; luminance-only prevents color fringing

## Task Commits

1. **Task 1+2: applyGrain, applyVignette, applySharpness** - `d177f99` (feat)

## Files Created/Modified
- `PhotoEditor/RenderEngine/PipelineBuilder.swift` - Three effects stage stubs replaced with full CIFilter implementations

## Decisions Made
- grain.intensity * 0.4 alpha cap: film grain should be subtle; full alpha would be too heavy
- CIVignette intensity doubled: CIVignette's own scale is coarser so 2x maps our ±1 to its useful ±2 range
- CISharpenLuminance doubled: matches Lightroom-style sharpness where 0.5 slider = noticeable but not extreme

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- ADJUST-06 (grain), ADJUST-07 (vignette), ADJUST-08 (sharpen) requirements fulfilled
- Effects panel sliders in UI can now drive visible results through the pipeline
- Remaining deferred stages: applyHSL, applyCurves, applySplitToning, applyCrop still identity stubs

---
*Phase: 03-editor-ui-full-adjustments*
*Completed: 2026-05-03*
