---
phase: 01-rendering-foundation
plan: 05
subsystem: Editor Session ViewModel
tags: [viewmodel, observable, swiftui, render-pipeline, debounce]
dependency_graph:
  requires: [01-01-AdjustmentStack, 01-03-ImageImporter, 01-04-RenderEngine]
  provides: [EditorViewModel, ContentView-rewired]
  affects: [ContentView, PhotoEditorApp]
tech_stack:
  added: ["@Observable (Swift 5.9 Observation framework)", "Task debounce pattern"]
  patterns: ["@MainActor @Observable final class", "40ms debounce via Task.sleep + renderTask?.cancel()", "Explicit Binding closures for stackDidChange triggering"]
key_files:
  created: ["PhotoEditor/Editor/EditorViewModel.swift"]
  modified: ["PhotoEditor/ContentView.swift"]
  deleted: ["PhotoEditor/PhotoEditorViewModel.swift"]
decisions:
  - "@Observable + @State (not ObservableObject + @StateObject) — required for iOS 17 Observation framework; prevents double-update cycles"
  - "Explicit Binding closures in ContentView sliders (not $viewModel.stack.light.exposure) — ensures stackDidChange() fires on every drag event for debounce to work"
  - "Rotate buttons kept but disabled(true) — Phase 3 hook point; not wired to any VM method"
  - "Filter strip replaced with placeholder text — Phase 2 (LUT pipeline) will fill it"
  - "RenderEngine stored as Optional<RenderEngine> — gracefully handles Metal-unavailable devices at init"
metrics:
  duration: "~10 min"
  completed: "2026-05-03"
  tasks_completed: 3
  files_created: 1
  files_modified: 1
  files_deleted: 1
requirements: [RENDER-01, RENDER-02, RENDER-03, RENDER-04, RENDER-05, RENDER-06]
---

# Phase 1 Plan 5: EditorViewModel + ContentView Rewire Summary

**One-liner:** `@Observable EditorViewModel` ties `AdjustmentStack` to `RenderEngine` via 40ms debounced preview and full-res save, replacing the legacy `ObservableObject` photo VM.

## What Was Built

### Task 1 — EditorViewModel.swift (created)

`@MainActor @Observable final class EditorViewModel` at `PhotoEditor/Editor/EditorViewModel.swift`.

Key behaviors:
- `init()` constructs `RenderEngine` (Metal-backed); if Metal is unavailable stores `nil` and sets an error message — no crash.
- `importPhoto(data: Data) async` calls `ImageImporter.importImage`, resets stack to `.identity`, renders first preview immediately (no debounce on first frame).
- `stackDidChange()` cancels any in-flight `renderTask`, snapshots the current stack value, sleeps 40ms, then renders preview via `RenderEngine.renderPreview`. Uses `[weak self]` and `Task.isCancelled` guard.
- `saveImage() async` requests `.addOnly` Photos authorization, calls `RenderEngine.renderExport` (full-resolution export CIImage, never the preview), writes via `PHPhotoLibrary.performChanges`.
- `resetAdjustments()` resets `stack = .identity` then calls `stackDidChange()`.

### Task 2 — ContentView.swift (rewired)

Visual layout preserved exactly. Binding and ViewModel changes:
- `@StateObject` → `@State` (correct for `@Observable`)
- `editorPreview` shows `viewModel.previewImage` directly (no `editedImage ?? sourceImage` fallback)
- Three sliders wired via explicit `Binding` closures to `stack.light.exposure`, `stack.light.contrast`, `stack.color.saturation` — each `set` calls `viewModel.stackDidChange()`
- Filter strip replaced with placeholder `"Coming in Phase 2"` text
- Rotate buttons retained with `.disabled(true)` — Phase 3 hook
- `loadSelectedPhoto()` calls `await viewModel.importPhoto(data:)` — no `UIImage(data:)` step
- All `sourceImage == nil` guards replaced with `importedImage == nil`

### Task 3 — PhotoEditorViewModel.swift (deleted)

Deleted after T1 and T2 guard checks passed. All removal gates confirmed clean.

## Removal Gate Results

| Gate | Result |
|------|--------|
| `! test -f PhotoEditor/PhotoEditorViewModel.swift` | PASS |
| `! grep -rE "CIPhotoEffect" PhotoEditor/` | PASS |
| `! grep -rE "CISepiaTone" PhotoEditor/` | PASS |
| `! grep -rE "enum FilterPreset" PhotoEditor/` | PASS |
| `! grep -RnE "CIContext\(\)" PhotoEditor/` | PASS |
| `! grep -rE "ObservableObject" PhotoEditor/` | PASS |
| `! grep -rE "@Published" PhotoEditor/` | PASS |

## Manual Xcode Steps Required

**The user MUST perform these steps on Mac before the project will build:**

1. **Remove dangling file reference:** Open `PhotoEditor.xcodeproj` in Xcode. In the Project Navigator, find `PhotoEditorViewModel.swift` (it will show in red as missing). Right-click → "Delete" → "Remove Reference". Do NOT move to Trash (the file is already gone from disk).

2. **Add new files to the PhotoEditor target:** The following files were created on Linux and are NOT yet in `project.pbxproj`. Select each file in the Project Navigator and ensure it is checked in the target membership panel (or use File → "Add Files to PhotoEditor…"):
   - `PhotoEditor/Editor/AdjustmentStack.swift` (Plan 01-01)
   - `PhotoEditor/Editor/EditorViewModel.swift` (this plan)
   - `PhotoEditor/Editor/ImageImporter.swift` (Plan 01-03)
   - `PhotoEditor/RenderEngine/RenderEngine.swift` (Plan 01-04)
   - `PhotoEditor/RenderEngine/PipelineBuilder.swift` (Plan 01-03)

3. **Build and run** on a device or simulator with Metal support (Simulator on Apple Silicon works; iOS Simulator on Intel may lack Metal — use a real device if needed).

## Manual UAT Items (from 01-VALIDATION.md)

These require running the app on Mac/device — cannot be verified on Linux:

1. **RENDER-01 (Import path):** Tap "Choose Photo", select a JPEG from the library. Verify the preview renders in the editor canvas within ~1 second.
2. **RENDER-02 (Non-destructive stack):** Drag the Exposure slider left and right. Verify the preview updates and the original photo is unmodified.
3. **RENDER-03 (Debounced preview):** Drag a slider rapidly. Verify no excessive CPU/GPU spike — renders should be throttled, not one per drag point.
4. **RENDER-04 (Full-res export):** Tap "Save to Photos". Verify the saved photo in the Photos app is full resolution (not the downsampled preview).
5. **RENDER-05 (Metal context):** Confirm app runs without "software renderer" warnings in the Xcode console. `CIContext()` no-arg form is gone from the codebase.
6. **RENDER-06 (Stack drives UI):** Tap "Reset Edits". Verify all sliders return to 0.0 and the preview reverts to the unedited photo.

## Deviations from Plan

None — plan executed exactly as written.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| T1 | 3a0eb1c | feat(01-05): add EditorViewModel |
| T2 | 37bbe0c | feat(01-05): rewire ContentView bindings |
| T3 | d8fa1d2 | feat(01-05): delete PhotoEditorViewModel.swift |
