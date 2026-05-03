---
phase: 03-editor-ui-full-adjustments
plan: "08"
subsystem: editor-panels
tags: [swiftui, panels, undo, compare, hsl, curves, effects]
dependency_graph:
  requires: [03-01, 03-02, 03-03, 03-04, 03-05, 03-06, 03-07]
  provides: [panel-container, light-panel, color-panel, hsl-panel, curves-panel, effects-panel, undo-toolbar, compare-gesture]
  affects: [ContentView-wiring-03-10]
tech_stack:
  added: []
  patterns: [fixed-height-panel-container, bindable-viewmodel, interactive-edit-coalescing, canvas-drag-gesture]
key_files:
  created:
    - PhotoEditor/Editor/Panels/EditorPanelTab.swift
    - PhotoEditor/Editor/Panels/PanelContainerView.swift
    - PhotoEditor/Editor/Panels/UndoToolbar.swift
    - PhotoEditor/Editor/Panels/CompareGesture.swift
    - PhotoEditor/Editor/Panels/LightPanelView.swift
    - PhotoEditor/Editor/Panels/ColorPanelView.swift
    - PhotoEditor/Editor/Panels/EffectsPanelView.swift
    - PhotoEditor/Editor/Panels/HSLPanelView.swift
    - PhotoEditor/Editor/Panels/CurvesPanelView.swift
  modified: []
decisions:
  - "PanelContainerView uses fixed panelHeight=280 wrapped in ZStack so canvas frame never changes on tab switch (Pitfall #19)"
  - "HSLPanelView uses WritableKeyPath<AdjustmentStack, HSLChannel> computed property to avoid code duplication across 8 channels"
  - "CurvesPanelView.ensureFivePoints expands identity 2-point CurveChannel to 5 evenly-spaced points on first interaction"
  - "CompareGesture sequences LongPressGesture before DragGesture(minimumDistance:0) to avoid consuming short taps"
metrics:
  duration: "12min"
  completed_date: "2026-05-03"
  tasks_completed: 4
  files_created: 9
requirements_addressed: [ADJUST-01, ADJUST-02, ADJUST-03, ADJUST-04, ADJUST-05, ADJUST-06, ADJUST-07, ADJUST-08, ADJUST-09, ADJUST-10, HIST-01, HIST-02, HIST-03]
---

# Phase 3 Plan 8: Panel Container UI Summary

**One-liner:** Segmented tab bar + fixed-height slide-up panels for Light/Color/HSL/Curves/Effects with undo toolbar and press-and-hold compare gesture.

## What Was Built

Nine Swift files delivering the complete editor panel system:

- **EditorPanelTab**: `CaseIterable` enum mapping 7 tabs (Filters/Light/Color/HSL/Curves/Effects/Crop) to SF Symbols and display names
- **PanelContainerView**: ZStack-based container with `panelHeight: CGFloat = 280` — canvas never shifts position regardless of active tab; horizontal scrolling tab bar with spring animation
- **UndoToolbar**: Undo/Redo buttons bound to `canUndo`/`canRedo`, Reset All with `.alert` confirmation before calling `resetAdjustments()`
- **CompareGesture**: `ViewModifier` + `View` extension — `LongPressGesture(minimumDuration: 0.4)` sequenced with `DragGesture(minimumDistance: 0)` toggles `showOriginal` binding
- **LightPanelView**: 6 sliders (Exposure, Contrast, Highlights, Shadows, Whites, Blacks) all range -1...1
- **ColorPanelView**: 4 sliders (Saturation, Vibrance, Temperature, Tint) all range -1...1
- **EffectsPanelView**: Grain (size/intensity), Vignette (amount/feather), Sharpen, Split Toning (highlightHue 0-360, highlightSaturation, shadowHue 0-360, shadowSaturation, balance) with section headers
- **HSLPanelView**: Circle swatch picker for 8 channels + Hue/Saturation/Luminance sliders; uses computed `channelKP: WritableKeyPath<AdjustmentStack, HSLChannel>` to avoid 8-way switch duplication in slider body
- **CurvesPanelView**: RGB/R/G/B segmented tabs, `Canvas`-drawn 4x4 grid + piecewise-linear curve, 5 draggable `Circle` overlays with endpoint x-locking and neighbor x-clamping; `ensureFivePoints()` expands 2-point identity to 5 on first render

## Binding Pattern

All panels use identical inline Binding closures:
```swift
Binding(
    get: { viewModel.stack[keyPath: kp] },
    set: { viewModel.stack[keyPath: kp] = $0; viewModel.stackDidChange() }
)
```

`onEditingChanged` forwards to `beginInteractiveEdit()` / `endInteractiveEdit()` so every drag coalesces to a single undo entry.

## Deviations from Plan

None — plan executed exactly as written.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | 2f9f3ea | Panel skeleton: EditorPanelTab, PanelContainerView, UndoToolbar, CompareGesture |
| 2 | 6247d6f | Light, Color, Effects panels with full slider sets |
| 3 | d928df5 | HSLPanelView — channel swatch picker + 3 sliders |
| 4 | f2f46ac | CurvesPanelView — RGB/R/G/B tabs + 5 draggable control points |

## Self-Check: PASSED

All 9 created files exist on disk. All 4 commits verified in git log.
