---
phase: 03-editor-ui-full-adjustments
verified: 2026-05-03T00:00:00Z
status: human_needed
score: 17/17 requirements verified
human_verification:
  - test: "Drag Exposure slider while viewing a photo"
    expected: "Preview visibly brightens or darkens in real time"
    why_human: "Runtime CI rendering on device/simulator required"
  - test: "Drag Highlights and Shadows sliders"
    expected: "Highlight recovery and shadow lift visible in preview"
    why_human: "Runtime rendering"
  - test: "Drag Whites and Blacks sliders"
    expected: "White/black point shift visible — no banding or clipping artifacts"
    why_human: "Runtime rendering; tone curve correctness not inspectable statically"
  - test: "Drag Saturation, Vibrance, Temperature, Tint sliders"
    expected: "Each control produces a distinct color shift on the preview"
    why_human: "Runtime rendering"
  - test: "Select each HSL channel (Red through Magenta) and drag Hue/Sat/Lum"
    expected: "Only the targeted hue range shifts; neighbouring hues unaffected"
    why_human: "Mask isolation correctness requires visual check"
  - test: "Edit RGB and per-channel curves by dragging control points"
    expected: "Tonal response follows the drawn curve with no visible banding"
    why_human: "Runtime rendering"
  - test: "Apply Split Toning highlight and shadow hues"
    expected: "Highlights and shadows take distinct tints; midtones unaffected"
    why_human: "Luminance mask quality requires visual check"
  - test: "Drag Grain size and intensity sliders"
    expected: "Film grain texture appears and scales with size control"
    why_human: "Runtime rendering"
  - test: "Drag Vignette amount and feather"
    expected: "Dark vignette appears around edges; feather smooths falloff"
    why_human: "Runtime rendering"
  - test: "Drag Sharpen slider"
    expected: "Edge sharpness increases visibly without halos"
    why_human: "Runtime rendering"
  - test: "Double-tap any adjustment slider"
    expected: "Slider snaps back to zero (default) immediately"
    why_human: "Gesture recogniser on device required"
  - test: "Select aspect ratio presets in Crop panel (1:1, 4:5, 9:16, etc.)"
    expected: "Canvas crops to the chosen ratio; crop is reflected in the preview"
    why_human: "Runtime rendering"
  - test: "Drag the rotation ruler in Crop panel"
    expected: "Image rotates continuously; no progressive pixel drift on re-edit"
    why_human: "Runtime rendering; pixel drift test requires re-entering the crop tool"
  - test: "Tap rotate-left, rotate-right, flip-H, flip-V buttons"
    expected: "Image transforms as expected; undo returns to previous state"
    why_human: "Runtime rendering"
  - test: "Make several adjustments, then tap Undo repeatedly"
    expected: "Each undo restores the previous adjustment state"
    why_human: "State machine correctness requires runtime"
  - test: "Undo to an earlier state then make a new change"
    expected: "Redo history is discarded; new change becomes the tip"
    why_human: "Runtime state machine"
  - test: "Press-and-hold the canvas for >=0.4 s"
    expected: "Preview switches to the unedited original while held; reverts on release"
    why_human: "Long-press gesture timing requires device/simulator"
  - test: "Tap Reset in UndoToolbar and confirm"
    expected: "All adjustments cleared; confirmation alert shown first"
    why_human: "Runtime UI interaction"
  - test: "Add Mantis SPM package and run on simulator"
    expected: "Interactive crop UI replaces the fallback placeholder text"
    why_human: "MantisCropBridge is compiled as a conditional #if canImport(Mantis); requires SPM linkage"
---

# Phase 03: Editor UI Full Adjustments — Verification Report

**Phase Goal:** The app is fully usable as a photo editor — all adjustment panels are functional against live output, crop and geometry work, undo/redo work, and the before/after compare is available.
**Verified:** 2026-05-03
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | All 6 light controls (exposure, contrast, highlights, shadows, whites, blacks) implemented in pipeline | VERIFIED | `applyLight` uses `CIExposureAdjust`, `CIColorControls`, `CIHighlightShadowAdjust`, and `CIFilter.toneCurve()` for whites/blacks — PipelineBuilder.swift lines 34–105 |
| 2 | All 4 color controls (saturation, vibrance, temperature, tint) implemented | VERIFIED | `applyColor` uses `CIColorControls`, `CIVibrance`, `CITemperatureAndTint` — PipelineBuilder.swift lines 106–202 |
| 3 | HSL panel covers 8 color channels (red/orange/yellow/green/aqua/blue/purple/magenta) × 3 controls | VERIFIED | `applyHSL` iterates all 8 channels; `HSLAdjustments` struct declares all 8 — AdjustmentStack.swift lines 47–56, PipelineBuilder.swift lines 204–322 |
| 4 | Tone curves (RGB + per-channel) implemented | VERIFIED | `applyCurves` uses `CIFilter.toneCurve()` 5-point interpolation — PipelineBuilder.swift lines 324–457 |
| 5 | Split toning (highlights + shadows hue/saturation) implemented | VERIFIED | `applySplitToning` uses luminance masks + CISourceOverCompositing — PipelineBuilder.swift lines 459–561 |
| 6 | Grain (size + intensity), Vignette (amount + feather), Sharpen implemented | VERIFIED | `applyGrain`, `applyVignette`, `applySharpness` all use live CI filters — PipelineBuilder.swift lines 563–609 |
| 7 | Every slider double-taps to reset to default value | VERIFIED | `AdjustmentSlider` has `.onTapGesture(count: 2) { value = defaultValue }` — Controls/AdjustmentSlider.swift lines 35–36 |
| 8 | Pipeline applies adjustments in deterministic order | VERIFIED | `build()` calls: LUT→light→color→HSL→curves→splitToning→grain→vignette→sharpness→crop — PipelineBuilder.swift lines 19–28; matches ADJUST-10 spec |
| 9 | Crop with aspect ratio presets works | VERIFIED | `CropAspectPreset` has 9 cases (free/original/1:1/4:5/3:4/9:16/16:9/3:2/2:3); `applyCrop` handles normalizedRect — CropAspectPreset.swift, PipelineBuilder.swift lines 611+ |
| 10 | Free rotate / straighten (angle ruler) works | VERIFIED | `CropPanelView` binds `rotationDegrees` slider to `viewModel.stack.crop.rotationDegrees`; `applyCrop` applies free-rotation transform |
| 11 | 90° rotate and flip controls work | VERIFIED | `CropPanelView` buttons mutate `clockwiseRotations`, `flippedHorizontally`, `flippedVertically` and call `commitDiscreteChange()` |
| 12 | Crop state stored separately, no pixel drift | VERIFIED | `CropSettings` is a separate struct in `AdjustmentStack`; `applyCrop` recomputes from source extent each render |
| 13 | Undo and redo work per adjustment | VERIFIED | `UndoStack` push/undo/redo with cursor; `EditorViewModel` exposes `beginInteractiveEdit`/`endInteractiveEdit`/`undo()`/`redo()` |
| 14 | Before/after compare on long-press | VERIFIED | `CompareGesture` (`LongPressGesture` 0.4s minimum) bound via `.compareOnLongPress(showOriginal:)` in ContentView; `showOriginal` switches preview to original CI image |
| 15 | Reset all edits with confirmation | VERIFIED | `UndoToolbar` shows `.alert` confirmation before calling `viewModel.resetAdjustments()`; `resetAdjustments()` calls `undoStack.push(.identity)` |
| 16 | All panels wired into EditorViewModel via @Bindable | VERIFIED | `PanelContainerView` declares `@Bindable var viewModel: EditorViewModel`; `ContentView` injects `viewModel` to both `PanelContainerView` and `UndoToolbar` |
| 17 | Panel slider drag events forwarded to beginInteractiveEdit/endInteractiveEdit | VERIFIED | Pattern found in both `PanelContainerView` context and EditorViewModel; `beginInteractiveEdit`/`endInteractiveEdit` present and called on drag events |

**Score:** 17/17 truths verified (automated grep gates)

### Required Artifacts

| Artifact | Status | Notes |
|----------|--------|-------|
| `PhotoEditor/RenderEngine/PipelineBuilder.swift` | VERIFIED | All 10 pipeline functions present and substantive |
| `PhotoEditor/Editor/Controls/AdjustmentSlider.swift` | VERIFIED | Double-tap reset, formatted value display |
| `PhotoEditor/Editor/Controls/SliderValueFormatter.swift` | VERIFIED | Used in AdjustmentSlider body |
| `PhotoEditor/Editor/UndoStack.swift` | VERIFIED | Full push/undo/redo/clear implementation |
| `PhotoEditor/Editor/EditorViewModel.swift` | VERIFIED | beginInteractiveEdit, endInteractiveEdit, undo, redo, resetAdjustments |
| `PhotoEditor/Editor/Panels/PanelContainerView.swift` | VERIFIED | @Bindable injection |
| `PhotoEditor/Editor/Panels/LightPanelView.swift` | VERIFIED | Present |
| `PhotoEditor/Editor/Panels/ColorPanelView.swift` | VERIFIED | Present |
| `PhotoEditor/Editor/Panels/HSLPanelView.swift` | VERIFIED | Present |
| `PhotoEditor/Editor/Panels/CurvesPanelView.swift` | VERIFIED | Present |
| `PhotoEditor/Editor/Panels/EffectsPanelView.swift` | VERIFIED | Present |
| `PhotoEditor/Editor/Panels/CompareGesture.swift` | VERIFIED | LongPressGesture + showOriginal binding |
| `PhotoEditor/Editor/Panels/UndoToolbar.swift` | VERIFIED | Undo/redo/reset with alert confirmation |
| `PhotoEditor/Editor/Panels/CropPanelView.swift` | VERIFIED | Aspect presets, rotation, flip, commitDiscreteChange |
| `PhotoEditor/Editor/Panels/CropAspectPreset.swift` | VERIFIED | 9 presets including all required ratios |
| `PhotoEditor/Editor/Panels/MantisCropBridge.swift` | PARTIAL | `#if canImport(Mantis)` conditional — full interactive crop UI available only when Mantis SPM package is linked; fallback shows preset/rotation/flip without interactive drag-crop |
| `PhotoEditor/ContentView.swift` | VERIFIED | PanelContainerView, UndoToolbar, compareOnLongPress all wired |

### Key Link Verification

| From | To | Via | Status |
|------|----|-----|--------|
| AdjustmentStack.light | PipelineBuilder.applyLight | build() | WIRED — `applyLight(stack.light, to: img)` line 20 |
| AdjustmentStack.color | PipelineBuilder.applyColor | build() | WIRED — `applyColor(stack.color, to: img)` line 21 |
| AdjustmentStack.hsl | PipelineBuilder.applyHSL | build() | WIRED — `applyHSL(stack.hsl, to: img)` line 22 |
| AdjustmentStack.curves | PipelineBuilder.applyCurves | build() | WIRED — `applyCurves(stack.curves, to: img)` line 23 |
| AdjustmentStack.splitToning | PipelineBuilder.applySplitToning | build() | WIRED — `applySplitToning(stack.splitToning, to: img)` line 24 |
| AdjustmentStack.{grain,vignette,sharpness} | PipelineBuilder.{applyGrain,applyVignette,applySharpness} | build() | WIRED — lines 25–27 |
| AdjustmentStack.crop | PipelineBuilder.applyCrop | build() | WIRED — `applyCrop(stack.crop, to: img)` line 28 |
| AdjustmentSlider | SliderValueFormatter | format() call in body | WIRED — `format.format(value)` and `format: SliderValueFormatter` |
| AdjustmentSlider.onTapGesture(count:2) | defaultValue reset | .onTapGesture | WIRED |
| AdjustmentSlider drag events | EditorViewModel.beginInteractiveEdit/endInteractiveEdit | panel view closures | WIRED |
| PanelContainerView | EditorViewModel | @Bindable injection | WIRED |
| CompareGesture | showOriginal binding | .compareOnLongPress | WIRED — ContentView line 87 |
| UndoToolbar | EditorViewModel.undo/redo/resetAdjustments | viewModel injection | WIRED — ContentView line 17 |
| CropPanelView changes | commitDiscreteChange | binding writes + commit | WIRED — CropPanelView lines 63, 68, 79, 86, 130 |

### Requirements Coverage

| Requirement | Plan | Description | Status |
|-------------|------|-------------|--------|
| ADJUST-01 | 03-01 | Exposure, Contrast, Highlights, Shadows, Whites, Blacks | SATISFIED |
| ADJUST-02 | 03-02 | Saturation, Vibrance, Temperature, Tint | SATISFIED |
| ADJUST-03 | 03-05 | HSL per color channel (8 channels × 3 controls) | SATISFIED |
| ADJUST-04 | 03-06 | RGB + per-channel tone curves | SATISFIED |
| ADJUST-05 | 03-06 | Split Toning (hue + amount per zone) | SATISFIED |
| ADJUST-06 | 03-03 | Grain (size + intensity) | SATISFIED |
| ADJUST-07 | 03-03 | Vignette (amount + feather) | SATISFIED |
| ADJUST-08 | 03-03 | Sharpen | SATISFIED |
| ADJUST-09 | 03-04 | Double-tap to reset sliders | SATISFIED |
| ADJUST-10 | 03-01/08 | Deterministic pipeline order | SATISFIED — LUT→light→color→HSL→curves→split→effects→crop |
| CROP-01 | 03-09 | Aspect ratio presets | SATISFIED — 9 presets |
| CROP-02 | 03-09 | Free-rotate / straighten with angle ruler | SATISFIED |
| CROP-03 | 03-09 | 90° rotate + flip H/V | SATISFIED |
| CROP-04 | 03-09 | Crop/rotate stored separately, no pixel drift | SATISFIED |
| HIST-01 | 03-07 | Undo and redo within session | SATISFIED |
| HIST-02 | 03-08 | Press-and-hold compare against original | SATISFIED |
| HIST-03 | 03-07/08 | Reset all edits with confirmation | SATISFIED |

All 17 requirements (ADJUST-01..10, CROP-01..04, HIST-01..03) are covered and have implementation evidence.

### Anti-Patterns Found

| File | Pattern | Severity | Impact |
|------|---------|----------|--------|
| MantisCropBridge.swift | `#if canImport(Mantis)` conditional compilation | Info | Interactive crop drag UI unavailable until Mantis SPM package is added. Fallback (presets + rotation ruler + flip) is functional. CROP-01/02/03 are satisfied via fallback; interactive crop is an enhancement. |

No TODO/FIXME/placeholder stubs found in the editor or render-engine source. No empty implementations (`return null`, `return []`, placeholder handlers) found outside of legitimate guard-return early exits.

### Human Verification Required

All automated grep gates pass. The following require device or simulator runtime to validate visual output quality and gesture behavior:

1. **Light panel visual response** — Drag each of the 6 light sliders and confirm visible preview changes.

2. **Whites/Blacks curve correctness** — Confirm no banding or clipping artifacts from the 5-point CIToneCurve whites/blacks mapping.

3. **Color panel response** — Confirm saturation, vibrance, temperature, and tint each produce distinct effects.

4. **HSL channel isolation** — Confirm each channel mask isolates only the target hue range.

5. **Tone curves rendering** — Drag curve control points and confirm tonal response follows the drawn curve.

6. **Split toning quality** — Confirm highlight/shadow tints are visually distinct and midtones are unaffected.

7. **Effects (grain/vignette/sharpen)** — Confirm each slider produces visible, artifact-free results.

8. **Double-tap reset gesture** — Confirm `.onTapGesture(count: 2)` fires reliably on device.

9. **Crop aspect ratios** — Confirm all 9 presets crop the canvas to the correct ratio in the preview.

10. **Crop pixel drift** — Re-enter crop after saving; confirm no progressive drift on second crop.

11. **Undo/redo session** — Make 5+ adjustments, undo all, redo all; confirm state fidelity.

12. **Compare long-press** — Hold canvas for 0.4s; confirm before/after toggle works and releases correctly.

13. **Reset confirmation alert** — Tap Reset; confirm alert appears before clearing adjustments.

14. **Mantis SPM linkage** — Add Mantis package and verify interactive crop UI replaces the fallback message.

### Summary

All 17 requirements are wired end-to-end at the code level. Every pipeline function is substantive (not a stub). The AdjustmentStack model covers all required fields. The ContentView wires PanelContainerView, UndoToolbar, and CompareGesture correctly. UndoStack and EditorViewModel implement the full undo/redo/reset contract.

The only conditional item is `MantisCropBridge`, which correctly falls back to preset+rotation UI when the Mantis SPM package is not linked — CROP-01 through CROP-04 are satisfied by the fallback path.

Status is `human_needed` because all grep gates pass but visual output quality, gesture timing, and pixel drift correctness require runtime on a device or simulator.

---

_Verified: 2026-05-03_
_Verifier: Claude (gsd-verifier)_
