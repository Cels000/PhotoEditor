# Phase 3: Editor UI + Full Adjustments - Context

**Gathered:** 2026-05-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Make the app fully usable as a photo editor. Wire every adjustment panel against the live render pipeline; add crop/straighten/rotate/flip; add undo/redo; add press-and-hold before/after. Replace the temporary brightness/contrast/saturation slider trio in `ContentView` (Phase 1 smoke-test bindings) with real, organized panels.

Specifically:

- **Light panel:** Exposure, Contrast, Highlights, Shadows, Whites, Blacks (6 sliders)
- **Color panel:** Saturation, Vibrance, Temperature, Tint (4 sliders)
- **HSL panel:** 8 color channels (red, orange, yellow, green, aqua, blue, purple, magenta) × Hue/Saturation/Luminance (3 sliders) = 24 sliders
- **Curves panel:** RGB + per-channel tone curves with draggable control points
- **Split toning:** Highlights hue + amount, Shadows hue + amount
- **Effects panel:** Grain (size + intensity), Vignette (amount + feather), Sharpen (amount)
- **Crop & Geometry:** Aspect-ratio presets (free/orig/1:1/4:5/3:4/9:16/16:9/3:2/2:3), free-rotate ruler, 90° rotate L/R, flip H/V — using Mantis SPM (note: requires user to add SPM dep on Mac, like XCTest)
- **History:** Undo/Redo of every adjustment within session (stack-based, capacity ~100)
- **Compare:** Press-and-hold canvas → preview unedited source
- **Reset:** Reset all edits with confirmation

This phase fills 17 of 49 requirements (the largest single phase by far).

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

- **Pipeline wiring:** All Phase 1 stub stages in `PipelineBuilder` (light, color, HSL, curves, splitToning, grain, vignette, sharpen, crop) get filled with their real CIFilter implementations. Stage order remains locked: LUT → light → color → HSL → curves → splitToning → effects → crop. Each stage is its own pure function on `PipelineBuilder`.
- **CIFilter mapping:**
  - Light: `CIExposureAdjust` (exposure) + `CIColorControls` (contrast) + `CIHighlightShadowAdjust` (highlights/shadows). Whites/Blacks are derived through `CIToneCurve` 5-point shaping or via additional `CIColorControls` brightness offset — finalize at implementation, document the choice.
  - Color: `CIColorControls.saturation` + `CIVibrance` + `CITemperatureAndTint` (separate inputs for warm/tint).
  - HSL: `CIHueSaturationValueGradient` is for displays, not edits. Use `CIColorPolynomial` per-channel or roll a custom `CIKernel` — recommendation: per-channel `CIColorMatrix` with hue rotation matrices; if too coarse, write a small Metal `CIColorKernel`. Document the chosen route.
  - Curves: `CIToneCurve` accepts 5 control points. Our UI offers more — sample the user's draggable spline at exactly 5 evenly-spaced X positions and pass those as control points (simplification; proper free-form curves would need a custom Metal kernel — defer to v2).
  - Split toning: implement as two `CIColorMatrix` operations applied to luminance-masked images, then composited. Or use `CIColorAbsoluteDifference` + `CIBlendWithMask`. Document.
  - Grain: `CIRandomGenerator` + `CIColorMatrix` to gray + `CIBlendWithAlpha` over source, scaled by intensity, sized by stretching the random pattern.
  - Vignette: `CIVignette`.
  - Sharpen: `CISharpenLuminance`.
  - Crop: applied LAST as a CIImage transform + crop, NOT folded into color filters (per ARCHITECTURE.md decision: "crop is architecturally separate").
- **History:** Linear undo/redo stack of `AdjustmentStack` snapshots in `EditorViewModel`. Snapshot recorded on slider release (not per tick — coalesce drags). `undo()` / `redo()` swap to the snapshot and trigger a render.
- **Compare gesture:** SwiftUI `.gesture(LongPressGesture(...).onChanged/onEnded)` toggles a `@State var showOriginal: Bool` in `ContentView`. When true, `editorPreview` shows source CIImage rendered through identity stack (cached) instead of `previewImage`.
- **Crop UI:** Mantis SPM (`https://github.com/guoyingtao/Mantis`). Plan must include a step that documents the user adding the SPM dep on Mac (like Phase 1 test target). Until added, crop button shows a "requires SPM dep" alert; the rest of the editor is unaffected.
- **Panel UX:** Tabs/segmented control at the bottom of the editor (Filters | Light | Color | HSL | Curves | Effects | Crop). Selected panel slides up from the bottom. The image canvas stays fixed (no layout shift — pitfall #11). Slider double-tap to reset to default. Reset All button in a top-right menu with confirmation alert.
- **Slider component:** Single reusable `AdjustmentSlider` view with: title, value, range, default, formatter, double-tap-to-reset, value bubble that fades in during drag. (Phase 7 perfects haptics — Phase 3 establishes the API only.)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets

- `AdjustmentStack.{light,color,hsl,curves,splitToning,grain,vignette,sharpen,crop}` — already defined in Phase 1
- `PipelineBuilder.apply{Light,Color,HSL,Curves,SplitToning,Grain,Vignette,Sharpen,Crop}` — all currently identity stubs
- `EditorViewModel.stackDidChange()` — debounce + render dispatch already wired
- `AdjustmentSlider` was inlined in Phase 1's ContentView for the smoke-test trio — extract & expand

### Established Patterns

- `@Observable` class for view models
- Pure pipeline stages via `PipelineBuilder`
- 40 ms debounce in `stackDidChange`
- LUT-style render budget per slider tick

### Integration Points

- `ContentView`: bottom panel area replaces today's three smoke-test sliders
- `PipelineBuilder.swift`: each stage's stub gets filled; signatures don't change
- Mantis crop: returns `CGRect` + angle → mapped into `AdjustmentStack.crop`

</code_context>

<specifics>
## Specific Ideas

- The **Curves** UI is a candidate for visible polish later — Phase 3 ships a functional 5-point editor with draggable circles on a canvas. Phase 7 may revisit.
- **Crop with Mantis** is the only SPM dependency we add in this project. If the user prefers to avoid it, the crop panel can fall back to: aspect-preset list + a manual rotation slider + 90° buttons + flip — no interactive resize handles. Document both paths in the plan; default to Mantis but ship the fallback so the build is never broken by a missing SPM.
- **Performance:** With 9 stages active, the preview render must still be smooth. The `extendedLinearSRGB` working space + Metal context handles this — but verify by limiting full filter chain to ≤8 active CIFilters in the worst case (HSL alone is up to 8 if every channel is non-default).
- **Coalescing:** Slider drags should NOT push to undo per-tick. The drag coalesces to a single undo entry from drag-begin to drag-end value.

</specifics>

<deferred>
## Deferred Ideas

- Free-form curves (>5 points) — v2 (needs Metal kernel)
- Auto-straighten with horizon detection — v2
- Crop ratio: golden, silver, custom — v2
- Selective edits (radial / linear / brush) — v2
- Healing / clone — out of scope (anti-feature)

</deferred>
