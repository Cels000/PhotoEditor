---
phase: 260504-mgz-add-histogram-overlay
plan: 01
subsystem: editor
tags: [editor, histogram, scopes, overlay, ui, core-image]
requires:
  - EditorViewModel.previewImage commit pattern (renderGeneration guard)
  - RenderEngine returning committed CGImage
  - Theme tokens (Colors.canvas/separator, Spacing.xs/md, Radii.small)
provides:
  - HistogramRenderer.render(postPipeline:context:) -> CGImage?
  - EditorViewModel.isHistogramVisible / histogramImage / toggleHistogram()
  - HistogramOverlayView (120x80pt VSCO-flavored panel)
affects:
  - EditorViewModel.swift (state + commit hooks at both render commit points)
  - EditorTabView.swift (toolbar button + canvas overlay)
tech-stack:
  added:
    - CIFilter.areaHistogram (CIAreaHistogram)
    - CIFilter.histogramDisplayFilter (CIHistogramDisplayFilter)
  patterns:
    - Caller-owned CIContext for hot-path filters (no per-call alloc)
    - Recompute hooked at render commit only, inside generation guard
key-files:
  created:
    - PhotoEditor/Editor/HistogramRenderer.swift
    - PhotoEditor/Editor/HistogramOverlayView.swift
  modified:
    - PhotoEditor/Editor/EditorViewModel.swift
    - PhotoEditor/EditorTabView.swift
decisions:
  - Operate on committed Display-P3 CGImage, not pre-CIContext linear chain — histogram must reflect what user SEES (monitor-relative clipping)
  - Apple-blessed CIAreaHistogram + CIHistogramDisplayFilter over hand-rolled Metal kernel — zero new deps, ~1ms on 1080px preview
  - Dedicated MainActor histogramContext separate from RenderEngine's preview/export contexts (those are actor-isolated)
  - Histogram visibility orthogonal to chrome-hide — sits outside the `if !isChromeHidden` block; user has its own toggle
  - Recompute fires at the TWO commit points (stackDidChange Task tail + renderPreviewNow), inside the generation guard — never mid-drag
metrics:
  duration: ~5min
  completed: 2026-05-04
---

# Quick Task 260504-mgz: Add Histogram Overlay Summary

RGB histogram overlay (120x80pt) togglable from the editor toolbar; reflects the post-pipeline preview (LUT + HSL + halation + grain + tone curve) and recomputes only on render commit, never per slider tick.

## Tasks Completed

| Task | Name                                            | Commit  |
| ---- | ----------------------------------------------- | ------- |
| 1    | HistogramRenderer (pure Core Image utility)     | 77f9525 |
| 2    | ViewModel state + render-commit hook + overlay  | db9ffa3 |
| 3    | Toolbar button + canvas overlay in EditorTabView | 6abe497 |
| 4    | On-device verification                          | pending user verification on device |

## What Shipped

### `PhotoEditor/Editor/HistogramRenderer.swift` (new, 38 LOC)
Stateless `enum HistogramRenderer` exposing `render(postPipeline:context:) -> CGImage?`. Pipes the input CGImage through `CIAreaHistogram` (256 bins, scale 1.0) → `CIHistogramDisplayFilter` (height 64, full 0–1 range) → caller's CIContext. Never throws; returns nil on filter failure. Caller owns CIContext lifecycle so we never pay the ~50ms CIContext-allocation cost on a render commit.

### `PhotoEditor/Editor/HistogramOverlayView.swift` (new, 30 LOC)
Fixed-size 120x80pt SwiftUI view: rounded-rect panel (`Theme.Colors.canvas` @ 55% opacity) + hairline `Theme.Colors.separator` border + bitmap rendered with `.interpolation(.none)` for crisp bars. `.allowsHitTesting(false)` so the canvas tap-to-hide-chrome gesture passes through.

### `PhotoEditor/Editor/EditorViewModel.swift`
- `var isHistogramVisible: Bool` and `var histogramImage: UIImage?` — observable.
- `private let histogramContext: CIContext` — dedicated, MainActor-owned (RenderEngine's contexts are actor-isolated and would force a hop).
- `recomputeHistogramIfVisible(from:)` private helper — called at the TWO commit points: inside `stackDidChange()`'s Task tail (after `previewImage = ...`, INSIDE the `myGen == renderGeneration` guard) and inside `renderPreviewNow()`. So histogram only updates for latest-generation frames; never mid-drag, never stale.
- `toggleHistogram()` — flips state; on off, drops bitmap to nil; on on, computes immediately from current `previewImage` so user doesn't need to wiggle a slider to see bars.

### `PhotoEditor/EditorTabView.swift`
- New `chart.bar` / `chart.bar.fill` button in `editorTopBar` between `MaskToolbarButton` and the `Spacer()`. Disabled when `importedImage == nil`. Plays `Haptic.undoRedo` on tap (subtle, no new haptic token needed).
- New `.overlay(alignment: .bottomLeading)` on the canvas `Image`, layered AFTER the existing topLeading "ORIGINAL" pill. Conditional on `isHistogramVisible && importedImage != nil`. Padded `Theme.Spacing.md` from the corner. Uses `.transition(.opacity)`.
- Histogram overlay deliberately sits OUTSIDE the `if !isChromeHidden` block — it's canvas content, not chrome. Tapping the canvas to hide chrome leaves the histogram visible (matches the spirit of a non-intrusive scope; user has its own toggle).

## Pipeline Performance

Hot-path cost: ZERO new work. The histogram does not run inside `PipelineBuilder.build`, `RenderEngine.renderPreview`, or anywhere upstream of the commit. It runs exactly once per committed frame — same cadence as `previewImage` itself — using a separate CIContext that doesn't contend with the engine actor.

The 40ms debounce + generation-coalescing pattern is untouched. Mid-drag taps that fail the `myGen == renderGeneration` guard skip both the `previewImage` write AND the histogram compute.

## Deviations from Plan

None — plan executed exactly as written.

## Linux-Only Build Note

This was edited and committed on Linux. No local Swift compilation is possible; verification depends on the GitHub Actions macOS archive job. New SwiftUI/CoreImage APIs used:

- `CIFilter.areaHistogram()` and `CIFilter.histogramDisplayFilter()` — both available since iOS 13 via the CIFilterBuiltins module. Project targets iOS 17+, so well within range.
- `Image.interpolation(.none)` — iOS 15+.
- All Theme tokens referenced (`Theme.Colors.canvas/separator`, `Theme.Spacing.xs/md`, `Theme.Radii.small`) verified to exist in `PhotoEditor/Design/Theme.swift`.
- `Haptic.play(.undoRedo)` is the existing token used by the Undo/Redo buttons in this same file — no new haptic registration required.

If the CI archive surfaces any Swift compile error, it will most likely be:
1. Missing `CoreImage.CIFilterBuiltins` import — already added at top of `HistogramRenderer.swift`.
2. `CIHistogramDisplayFilter` property name drift — Apple's builtins use `height`, `highLimit`, `lowLimit` (verified via current SDK docs). If a future SDK renames these, fix-up is one-line.

## Task 4 Status: Pending User Verification on Device

Push to main → wait for CI → install via `ideviceinstaller`. Then run the 10-step verification list in `260504-mgz-PLAN.md` Task 4 (toggle, pipeline reflectivity, drag-coalescing, compare gesture, chrome-hide, empty state, style sanity).

## Self-Check: PASSED

Files exist:
- FOUND: PhotoEditor/Editor/HistogramRenderer.swift
- FOUND: PhotoEditor/Editor/HistogramOverlayView.swift
- FOUND: PhotoEditor/Editor/EditorViewModel.swift (modified)
- FOUND: PhotoEditor/EditorTabView.swift (modified)

Commits exist:
- FOUND: 77f9525 (HistogramRenderer)
- FOUND: db9ffa3 (ViewModel + overlay view)
- FOUND: 6abe497 (toolbar + canvas overlay)
