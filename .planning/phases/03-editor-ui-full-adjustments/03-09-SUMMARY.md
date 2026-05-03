---
phase: 03-editor-ui-full-adjustments
plan: 09
subsystem: ui
tags: [swiftui, coreimage, crop, mantis, ciimage, aspect-ratio]

# Dependency graph
requires:
  - phase: 03-editor-ui-full-adjustments
    provides: AdjustmentStack, PipelineBuilder pipeline stages, EditorViewModel
  - phase: 03-04
    provides: AdjustmentSlider component, beginInteractiveEdit/endInteractiveEdit, commitDiscreteChange
  - phase: 03-07
    provides: UndoStack integration pattern

provides:
  - CropSettings with flippedHorizontally/flippedVertically fields
  - PipelineBuilder.applyCrop: rotate 90° → flip → free-rotate → normalizedRect crop (no extent.integral)
  - CropAspectPreset: 9-value enum with displayName + ratio
  - MantisCropBridge: full Mantis UIViewControllerRepresentable guarded by #if canImport(Mantis)
  - mantisAvailable Bool for runtime fallback gate
  - CropPanelView: aspect presets + rotation slider + 90° buttons + flip buttons + conditional Mantis launch button

affects: [03-10, export-pipeline, crop-sheet-presentation]

# Tech tracking
tech-stack:
  added: [Mantis SPM (optional, user adds on Mac)]
  patterns:
    - "#if canImport guard for optional SPM deps — build never breaks without dep"
    - "applyCrop single-shot transform chain: 90°rot → flip → freeRot → crop (Pitfall #10)"
    - "mantisAvailable Bool as runtime gate — same source compiles both paths"

key-files:
  created:
    - PhotoEditor/Editor/Panels/CropAspectPreset.swift
    - PhotoEditor/Editor/Panels/MantisCropBridge.swift
    - PhotoEditor/Editor/Panels/CropPanelView.swift
  modified:
    - PhotoEditor/Editor/AdjustmentStack.swift
    - PhotoEditor/RenderEngine/PipelineBuilder.swift

key-decisions:
  - "applyCrop uses single-shot chained transforms (no extent.integral); origin-corrected at end via translation to (0,0)"
  - "Mantis bridge compiled only when canImport(Mantis); mantisAvailable=false in all other builds"
  - "CropPanelView ships full fallback UI (presets + slider + 90° + flip) independent of Mantis — fallback IS the shipping path until user adds SPM"
  - "flippedHorizontally/flippedVertically added as new Codable fields with defaults — forward-compatible per AdjustmentStack versioning rules"

patterns-established:
  - "Optional SPM dep: #if canImport(Dep) wraps entire implementation; companion Bool exposed for UI gating"
  - "Crop preset normalizedRect math: ratio>=1 constrains height to 1/ratio; ratio<1 constrains width to ratio"

requirements-completed: [CROP-01, CROP-02, CROP-03, CROP-04]

# Metrics
duration: 8min
completed: 2026-05-03
---

# Phase 03 Plan 09: Crop Module Summary

**Mantis-or-fallback crop pipeline with one-shot CIImage transforms, 9 aspect presets, 90° rotation, flip, and free-rotate slider**

## Performance

- **Duration:** 8 min
- **Started:** 2026-05-03T21:20:18Z
- **Completed:** 2026-05-03T21:28:00Z
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments

- Extended CropSettings with flip fields (Codable-forward-compat) and implemented full applyCrop in PipelineBuilder with no extent.integral calls
- Created MantisCropBridge with `#if canImport(Mantis)` guard — the file compiles cleanly on Linux and any Mac without the SPM dep
- CropPanelView ships a complete fallback UI (aspect presets + rotation slider + 90° buttons + flip) that works with zero SPM deps, plus a disabled Mantis launch button with explanatory caption

## Task Commits

1. **Task 1: Extend CropSettings + implement applyCrop** - `54cf055` (feat)
2. **Task 2: CropAspectPreset + MantisCropBridge** - `fa42e11` (feat)
3. **Task 3: CropPanelView** - `13e0307` (feat)

## Files Created/Modified

- `PhotoEditor/Editor/AdjustmentStack.swift` - Added flippedHorizontally/flippedVertically to CropSettings
- `PhotoEditor/RenderEngine/PipelineBuilder.swift` - Replaced stub with full applyCrop (4-stage transform chain)
- `PhotoEditor/Editor/Panels/CropAspectPreset.swift` - 9-preset enum with displayName + ratio
- `PhotoEditor/Editor/Panels/MantisCropBridge.swift` - Full Mantis UIViewControllerRepresentable behind canImport guard
- `PhotoEditor/Editor/Panels/CropPanelView.swift` - Complete fallback crop UI + conditional Mantis button

## Decisions Made

- **Single-shot transforms:** applyCrop chains 90°rot → flip → freeRot → normalizedRect crop on the accumulated `output` CIImage, then does one final origin translation. No `extent.integral` at any step (Pitfall #10).
- **Mantis bridge design:** The `#if canImport(Mantis)` block wraps the full UIViewControllerRepresentable and the `mantisAvailable = true` assignment. The `else` branch just declares `mantisAvailable = false`. CropPanelView reads only that Bool — no conditional compilation needed in the view layer.
- **Fallback as primary path:** The plan treats the fallback UI (presets + slider + buttons) as the real shipping path, not a degradation. Mantis adds interactive drag handles but the fallback covers all core crop operations.

## Deviations from Plan

None — plan executed exactly as written. Note: the plan's verification script uses `! grep -q "extent.integral"` which technically fails because the comment `/// never chain extent.integral across renders` contains the string. The actual code has zero `.integral` calls; this is a verification script false-positive, not a code issue.

## Issues Encountered

None.

## User Setup Required

To enable the interactive Mantis crop tool: add `https://github.com/guoyingtao/Mantis` as a Swift Package dependency in Xcode on Mac. No code changes required — the `#if canImport(Mantis)` guard activates automatically when the dep is linked.

## Next Phase Readiness

- All 4 crop requirements (CROP-01..04) fulfilled
- CropPanelView ready to be wired into the main panel tab bar (03-10)
- Mantis sheet presentation stub in mantisButton body is marked for wiring in 03-10
- applyCrop is live in the build pipeline; any `stack.crop` mutation immediately reflects in preview

---
*Phase: 03-editor-ui-full-adjustments*
*Completed: 2026-05-03*
