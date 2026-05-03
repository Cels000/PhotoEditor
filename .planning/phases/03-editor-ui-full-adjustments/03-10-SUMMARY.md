---
phase: 03-editor-ui-full-adjustments
plan: 10
subsystem: editor-ui
tags: [contentview, wire-up, capstone, compare-gesture, panel-container]
dependency_graph:
  requires: [03-04, 03-07, 03-08, 03-09]
  provides: [final-editor-surface]
  affects: [ContentView]
tech_stack:
  added: []
  patterns: [NavigationStack toolbar, compareOnLongPress, task(id:) for identity-driven cache]
key_files:
  modified:
    - PhotoEditor/ContentView.swift
decisions:
  - ContentView is a pure wiring layer — no adjustment logic, no direct stack access
  - originalPreviewImage cached via CIContext in rebuildOriginalPreview(); identity keyed on previewCIImage.extent.debugDescription
  - Save and PhotosPicker moved to NavigationStack toolbar items to free vertical space
metrics:
  duration: 5min
  completed: 2026-05-03
  tasks: 1
  files_changed: 1
---

# Phase 03 Plan 10: ContentView Wire-Up Summary

**One-liner:** Final editor surface wiring — ContentView replaced with PanelContainerView + UndoToolbar + CompareGesture, removing all Phase-1 smoke-test inline sliders.

## What Was Done

Phase 3 capstone. ContentView was a Phase-1 prototype with three inline `AdjustmentSlider` instances wired directly to `viewModel.stack.light.*` and `viewModel.stack.color.*`. This plan replaced the entire body with the full panel system built across Plans 03-04 through 03-09.

**Layout after this plan:**
```
NavigationStack
  └── VStack(spacing: 0)
        ├── UndoToolbar(viewModel:)
        ├── editorPreview  ← fixed 3/4 aspect, .compareOnLongPress
        └── PanelContainerView(viewModel:, selectedTab: $selectedTab)
```

**Compare gesture:** Press-and-hold (≥0.4s) on the canvas swaps to `originalPreviewImage` and shows an "Original" pill overlay. Release restores the edited view.

**Original preview cache:** A `CIContext` renders `importedImage.previewCIImage` to a `UIImage` when the imported identity changes. This avoids re-rendering on every showOriginal toggle.

**Tab stability:** `PanelContainerView` uses `fixed panelHeight=280` (set in 03-08), so switching tabs does not shift the canvas.

## Removed

- `private struct AdjustmentSlider` (file-private duplicate — public one from 03-04 used by panels)
- `private var adjustments` (smoke-test slider trio)
- `private var actionBar` (rotate left/right stub buttons)
- `private var filterStrip` (inlined FilterStripView — now inside PanelContainerView)
- `private var saveSection` (Save button now in .toolbar)
- `private struct PrimaryButtonStyle`, `private struct SecondaryButtonStyle`

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check

- [x] `PhotoEditor/ContentView.swift` exists and contains `PanelContainerView`, `UndoToolbar`, `compareOnLongPress`, `showOriginal`, `selectedTab: EditorPanelTab`
- [x] No `private struct AdjustmentSlider` in ContentView.swift
- [x] No `viewModel.stack.light.exposure` in ContentView.swift
- [x] Commit `bc50f76` exists

## Self-Check: PASSED
