---
phase: 05-export
plan: "06"
subsystem: export-ui
tags: [export, ui, swiftui, bottom-sheet, share-sheet, toolbar]
dependency_graph:
  requires: [05-01, 05-04, 05-05]
  provides: [export-ui, toolbar-export-button, share-sheet-presentation]
  affects: [ContentView, EditorViewModel]
tech_stack:
  added: []
  patterns: [SwiftUI-Form, presentationDetents, UIViewControllerRepresentable, Binding-get-set]
key_files:
  created:
    - PhotoEditor/Export/ExportSheetView.swift
  modified:
    - PhotoEditor/ContentView.swift
decisions:
  - ExportSheetView uses local SizeChoice enum mirroring ExportSize presets — avoids exposing associated-value enum to Picker directly
  - Dismiss called immediately after kicking off Task for saveExport/shareExport — export overlay belongs to ContentView alerts/ShareSheetView
  - ShareSheetView bound via inline Binding(get:set:) clearing both shareData and shareFormat on dismiss
metrics:
  duration: 1min
  completed_date: "2026-05-03"
  tasks_completed: 2
  files_changed: 2
---

# Phase 05 Plan 06: ExportSheetView UI + ContentView Toolbar Swap Summary

**One-liner:** Bottom-sheet export UI with Format/Size/Quality/Action controls wired to EditorViewModel; ContentView toolbar Save button replaced by Export button presenting the sheet.

## What Was Built

### ExportSheetView (`PhotoEditor/Export/ExportSheetView.swift`)

New `struct ExportSheetView: View` — a `NavigationStack`-wrapped `Form` presented as a bottom sheet.

Controls:
- **Format** section: segmented `Picker` over `ExportFormat.allCases` (JPEG/HEIC/PNG). PNG shows a lossless caption.
- **Size** section: `Picker` over `SizeChoice` (Full / Web (2048) / Story (1080) / Custom). Custom reveals a numeric `TextField` with `keyboardType(.numberPad)` and a "Allowed: 256 to 8192" hint.
- **Quality** section: `Slider(value:in:step:)` 0.4–1.0, step 0.05, shown **only** when `format.supportsQuality` is true (hidden for PNG).
- **Actions** section: "Save to Photos" and "Share…" buttons, both disabled while `viewModel.isExporting` or while custom size is invalid.
- **Exporting overlay**: `ZStack` with `Color.black.opacity(0.25)` + `ProgressView` + "Exporting…" label inside `.ultraThinMaterial` rounded rect.
- Cancel button in `.topBarTrailing`.

Custom size validation (`validCustomSize`): `Int(customLongEdge) != nil && 256 <= n <= 8192`. The actual clamp is owned by `ExportSize.custom(longEdge:).resolve(sourceLongEdge:)` in plan 05-01.

Button wiring:
```swift
Task { await viewModel.saveExport(options: resolvedOptions); dismiss() }
Task { await viewModel.shareExport(options: resolvedOptions); dismiss() }
```

### ContentView changes (`PhotoEditor/ContentView.swift`)

1. **New state:** `@State private var isExportSheetPresented: Bool = false`

2. **Toolbar replacement:** The legacy Save button (`viewModel.saveImage()`) was removed and replaced:
   ```swift
   ToolbarItem(placement: .topBarTrailing) {
       Button { isExportSheetPresented = true } label: {
           if viewModel.isExporting { ProgressView() }
           else { Image(systemName: "square.and.arrow.up.on.square") }
       }
       .disabled(viewModel.importedImage == nil || viewModel.isExporting)
       .accessibilityLabel("Export")
   }
   ```
   The "Save to Library" button (`saveToLibrary()`) was left unchanged.

3. **ExportSheetView sheet:**
   ```swift
   .sheet(isPresented: $isExportSheetPresented) {
       ExportSheetView(viewModel: viewModel)
           .presentationDetents([.medium, .large])
   }
   ```

4. **ShareSheetView sheet** bound to `viewModel.shareData`:
   ```swift
   .sheet(isPresented: Binding(
       get: { viewModel.shareData != nil },
       set: { if !$0 { viewModel.shareData = nil; viewModel.shareFormat = nil } }
   )) {
       if let data = viewModel.shareData, let format = viewModel.shareFormat {
           ShareSheetView(data: data, format: format) {
               viewModel.shareData = nil
               viewModel.shareFormat = nil
           }
       }
   }
   ```

## No saveImage References Remain

`grep "viewModel.saveImage" PhotoEditor/ContentView.swift` returns nothing. The legacy `saveImage()` method was removed in plan 05-05; this plan removes the only call site.

## EXPORT-XX Requirements Now User-Observable

| Requirement | Description | Satisfied by |
|-------------|-------------|--------------|
| EXPORT-01 | Export to JPEG/HEIC/PNG | ExportSheetView Format picker |
| EXPORT-02 | Save to Photos full-res | ExportSheetView Save to Photos button → saveExport |
| EXPORT-03 | HEIC default format | ExportSheetView `@State private var format: ExportFormat = .heic` |
| EXPORT-04 | Size presets + custom 256-8192 | ExportSheetView Size section |
| EXPORT-05 | Quality slider hidden for PNG | `if format.supportsQuality { Section("Quality") }` |
| (Share)    | Share via system share sheet | ExportSheetView Share button → shareExport → ShareSheetView |

## Deviations from Plan

None — plan executed exactly as written.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| Task 1 | 833dcad | feat(05-06): add ExportSheetView bottom sheet UI |
| Task 2 | d267fde | feat(05-06): wire ExportSheetView + ShareSheetView into ContentView toolbar |

## Self-Check: PASSED

- `PhotoEditor/Export/ExportSheetView.swift` — FOUND
- `PhotoEditor/ContentView.swift` modified — FOUND (ExportSheetView, ShareSheetView, isExportSheetPresented present; saveImage absent)
- Commit 833dcad — FOUND
- Commit d267fde — FOUND
