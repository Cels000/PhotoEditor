---
phase: 03-editor-ui-full-adjustments
plan: "06"
subsystem: ui
tags: [coreimage, cifilter, tone-curves, split-toning, pipeline]

requires:
  - phase: 03-editor-ui-full-adjustments
    provides: AdjustmentStack ToneCurves and SplitToning structs; PipelineBuilder identity stubs

provides:
  - applyCurves: composite RGB + per-channel R/G/B tone curves via CIToneCurve + CIColorMatrix decompose-recompose
  - applySplitToning: luminance-mask hue tints for highlights and shadows
  - isIdentityCurve / sampleCurve / makeCurveFilter / applyChannelCurve / applyTint helpers

affects:
  - 03-08-PLAN (Curves UI — ships 5-point draggable control points to match this implementation)
  - any plan using PipelineBuilder.build()

tech-stack:
  added: []
  patterns:
    - "5-point CIToneCurve: sample user piecewise-linear curve at evenly-spaced X=0,0.25,0.5,0.75,1.0"
    - "Per-channel curve via decompose-recompose: CIColorMatrix isolate → CIToneCurve → CIColorMatrix re-inject → CIAdditionCompositing"
    - "Split toning: CIColorMatrix luma → CIToneCurve shadow/highlight masks → constant-color tint → CIBlendWithMask → source-over"
    - "Identity short-circuit: allSatisfy { abs(x-y) < 1e-6 } before any filter instantiation"

key-files:
  created: []
  modified:
    - PhotoEditor/RenderEngine/PipelineBuilder.swift

key-decisions:
  - "5-point sampling (piecewise-linear at fixed X) chosen over spline; free-form >5 point curves deferred to v2 (Metal CIColorKernel)"
  - "Per-channel curve approximation via decompose-recompose documented honestly in code comments"
  - "Split toning balance param shifts shadow/highlight boundary: mid = 0.5 - balance*0.25"
  - "makeCurveFilter returns CIFilter? (not typed protocol) to avoid CIToneCurveProtocol casting issues on Linux"

patterns-established:
  - "Identity guard before filter construction: zero render cost at default slider positions"
  - "Private helper decomposition: one public stage func + private helpers (isIdentityCurve, sampleCurve, makeCurveFilter, applyChannelCurve, applyTint)"

requirements-completed: [ADJUST-04, ADJUST-05]

duration: 8min
completed: 2026-05-03
---

# Phase 03 Plan 06: Curves + Split Toning Summary

**CIToneCurve composite/per-channel curves and luminance-masked split toning replacing identity stubs in PipelineBuilder**

## Performance

- **Duration:** 8 min
- **Started:** 2026-05-03T21:16:17Z
- **Completed:** 2026-05-03T21:24:00Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- `applyCurves` applies the RGB composite curve and three per-channel R/G/B curves; identity curves short-circuit with zero filter cost
- `applySplitToning` produces warm-highlight / cool-shadow (or any hue pair) tinting via luminance masks derived from CIToneCurve thresholding
- 5-point sampling of user piecewise-linear curve and v2 deferral are documented in code comments

## Task Commits

1. **Task 1: applyCurves (composite + per-channel)** - `1ee2b95` (feat)
2. **Task 2: applySplitToning (luminance-mask hue tints)** - `1ee2b95` (feat — combined in single commit)

## Files Created/Modified

- `PhotoEditor/RenderEngine/PipelineBuilder.swift` - replaced two identity stubs with ~250 lines of curve + split-toning implementation plus 5 private helpers

## Decisions Made

- `makeCurveFilter` returns `CIFilter?` rather than the typed `CIToneCurveProtocol` cast to avoid compilation issues; `setValue(_:forKey:kCIInputImageKey)` used for input assignment
- Per-channel decompose-recompose: extract channel as grayscale via CIColorMatrix (all three RGB rows get the same source-channel coefficient), apply CIToneCurve, re-inject via zero-out + add approach
- Split toning `balance` shifts the luminance midpoint: `mid = 0.5 - balance * 0.25` giving a 0.25–0.75 range

## Deviations from Plan

None — plan executed exactly as written. Minor adaptation: `makeCurveFilter` return type changed from `(CIFilter & CIFilterProtocol)?` to `CIFilter?` (the plan's note anticipated this).

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `applyCurves` and `applySplitToning` are fully wired in `PipelineBuilder.build()`; 03-08 (Curves UI) can rely on the 5-point contract
- Identity short-circuits ensure no perf regression at default slider positions

---
*Phase: 03-editor-ui-full-adjustments*
*Completed: 2026-05-03*
