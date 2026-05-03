---
phase: 06-recipes
verified: 2026-05-03T00:00:00Z
status: human_needed
score: 5/5 must-haves verified
human_verification:
  - test: "Share flow — tap Share in recipe context menu, confirm system share sheet appears"
    expected: "Context menu Share -> intermediate sheet opens with a ShareLink button -> tapping it opens system share sheet with a .photorecipe file attached"
    why_human: "ShareLink is nested inside a .sheet presentation. The extra tap is an unusual UX and cannot be confirmed working without running on device."
  - test: "Import flow — AirDrop or Files app open a .photorecipe file into the app"
    expected: "File opens, recipe is imported, store refreshes, new recipe appears in the Recipes sheet"
    why_human: "UTI registration and onOpenURL dispatch require a running app and a real .photorecipe file; cannot be verified by grep."
  - test: "RECIPE-05 graceful degradation — apply a recipe whose filterID no longer exists in the FilterLibrary"
    expected: "All non-filter adjustments are applied correctly; filter slot is blank; no crash or error dialog"
    why_human: "Logic is in code but outcome (correct visual + no crash) requires device execution."
---

# Phase 6: Recipes Verification Report

**Phase Goal:** Users can capture a look as a named Recipe, reuse it across photos, and share it with others.
**Verified:** 2026-05-03
**Status:** human_needed — all automated checks pass; 3 items need device/simulator confirmation
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | User can save the current adjustment stack as a named Recipe | VERIFIED | `EditorViewModel.saveCurrentAsRecipe()` persists via `RecipeStore.save()`; wired to toolbar button in `ContentView.swift:85`; name collected via `RecipeNamePromptView` |
| 2 | User can apply any saved Recipe to a photo (replaces current stack) | VERIFIED | `EditorViewModel.applyRecipe()` replaces `stack`, calls `commitDiscreteChange()` + `stackDidChange()`; wired in `RecipesSheetView.onApply` → `ContentView:116` |
| 3 | User can rename, reorder, and delete saved Recipes | VERIFIED | `RecipeStore` has `rename()`, `reorder()`, `delete()`; wired in `RecipesSheetView` via context menu, `.onMove`, `.onDelete` |
| 4 | User can export a Recipe to a shareable file and import from a shared file | VERIFIED | `RecipeFileIO.writeTempFile()` → `ShareLink`; `onOpenURL` in `PhotoEditorApp.swift:35` calls `RecipeFileIO.read()` then `RecipeStore`; UTI `com.photoeditor.recipe` registered in `Info.plist` |
| 5 | Recipe with missing filter UUID fails gracefully (other adjustments still apply) | VERIFIED | `EditorViewModel.applyRecipe()` lines 339-340: resolves filter ID against `filterLibrary`; sets `newStack.filter = nil` when UUID absent |

**Score: 5/5 truths verified**

---

### Required Artifacts

| Artifact | Purpose | Status | Details |
|----------|---------|--------|---------|
| `PhotoEditor/Library/RecipeItem.swift` | @Model with 8 fields + adjustmentStack accessor | VERIFIED | `@Model final class RecipeItem`, all fields present, `JSONDecoder().decode(AdjustmentStack.self` in extension |
| `PhotoEditor/Library/LibrarySchema.swift` | LibrarySchemaV1 carries both models | VERIFIED | Line 28: `[LibraryItem.self, RecipeItem.self]` |
| `PhotoEditor/PhotoEditorApp.swift` | ModelContainer wired to LibrarySchemaV1; onOpenURL import handler | VERIFIED | `Schema(versionedSchema: LibrarySchemaV1.self)`; `onOpenURL` dispatches to `RecipeFileIO.read()` + `RecipeStore` |
| `PhotoEditor/Library/RecipeStore.swift` | CRUD: save, rename, reorder, delete, refresh | VERIFIED | All 5 methods present and substantive; `@Observable @MainActor` |
| `PhotoEditor/Library/RecipesSheetView.swift` | UI for apply/rename/share/delete/reorder | VERIFIED | Full implementation with context menu, `.onMove`, `.onDelete`, rename sheet, delete alert, share sheet |
| `PhotoEditor/Library/RecipeNamePromptView.swift` | Name-entry modal (save + rename) | VERIFIED | Substantive `Form` with `TextField`, submit/cancel wired |
| `PhotoEditor/Library/ExportedRecipe.swift` | On-disk document format | VERIFIED | Codable struct, `fileExtension = "photorecipe"`, `uti = "com.photoeditor.recipe"` |
| `PhotoEditor/Library/RecipeFileIO.swift` | Encode/decode/write/read .photorecipe files | VERIFIED | All 4 static methods substantive; no stubs |
| `PhotoEditor/Editor/EditorViewModel.swift` | `saveCurrentAsRecipe()` + `applyRecipe()` | VERIFIED | Both methods fully implemented including thumbnail generation and RECIPE-05 filter nil-out |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `RecipeItem` | `AdjustmentStack` | `JSONDecoder().decode(AdjustmentStack.self` | WIRED | Extension in RecipeItem.swift line 56 |
| `LibrarySchemaV1` | `RecipeItem` | `RecipeItem.self` in models array | WIRED | LibrarySchema.swift line 28 |
| `PhotoEditorApp.swift` | `LibrarySchemaV1` | `Schema(versionedSchema:)` | WIRED | PhotoEditorApp.swift line 14 area |
| `PhotoEditorApp.swift` | `RecipeStore` | `onOpenURL` → `RecipeFileIO.read()` | WIRED | PhotoEditorApp.swift line 35 |
| `ContentView` | `RecipesSheetView` | `sheet(isPresented:)` + `RecipeStore` | WIRED | ContentView.swift lines 112-117 |
| `ContentView` | `EditorViewModel.applyRecipe` | `RecipesSheetView.onApply` callback | WIRED | ContentView.swift line 116 |
| `ContentView` | `EditorViewModel.saveCurrentAsRecipe` | toolbar button + `RecipeNamePromptView.onSubmit` | WIRED | ContentView.swift lines 85, 134 |
| `RecipesSheetView` | `RecipeFileIO.writeTempFile` | `shareRecipe()` private func | WIRED | RecipesSheetView.swift, `shareRecipe(_:)` method |

---

### Requirements Coverage

| Requirement | Description | Status | Evidence |
|-------------|-------------|--------|----------|
| RECIPE-01 | User can save current adjustment stack as a named Recipe | SATISFIED | `saveCurrentAsRecipe()` in EditorViewModel; toolbar button in ContentView |
| RECIPE-02 | User can apply any saved Recipe to any photo | SATISFIED | `applyRecipe()` replaces full stack; wired via `RecipesSheetView.onApply` |
| RECIPE-03 | User can rename, reorder, and delete saved Recipes | SATISFIED | All three ops in RecipeStore + RecipesSheetView UI |
| RECIPE-04 | Export to .photorecipe file + import round-trip | SATISFIED (human needed) | ExportedRecipe + RecipeFileIO + UTI in Info.plist + onOpenURL handler; share UX needs device confirmation |
| RECIPE-05 | Missing filter UUID fails gracefully | SATISFIED (human needed) | Code path verified; runtime behavior needs device test |

---

### Anti-Patterns Found

None. No TODO/FIXME/placeholder comments found in any recipe-related source files. No empty implementations or stub returns detected.

---

### Human Verification Required

#### 1. Share flow — extra tap required

**Test:** Open the Recipes sheet, long-press a recipe, tap "Share" in the context menu.
**Expected:** A system share sheet (UIActivityViewController / SwiftUI equivalent) appears with a `.photorecipe` file attachment, allowing AirDrop, Messages, Files, etc.
**Why human:** The current implementation opens an intermediate `.sheet` containing a `ShareLink` button. The user must tap the `ShareLink` button inside that sheet to reach the actual system share sheet. This is an extra step compared to the context menu going directly to system share. The UX works but is non-standard — a product decision, not a bug — and can only be confirmed on device.

#### 2. Import flow — .photorecipe file opens into app

**Test:** Send a `.photorecipe` file to the device via AirDrop or share from Files app, choosing this app as the target.
**Expected:** The app's `onOpenURL` fires, file is parsed by `RecipeFileIO.read()`, imported recipe appears in the Recipes sheet on next open, `recipeImported` notification refreshes the store.
**Why human:** UTI binding and `onOpenURL` dispatch require a running app instance and a real file; the logic is wired in code but system-level file association cannot be confirmed by static analysis.

#### 3. RECIPE-05 graceful degradation under missing filter

**Test:** Export a recipe that references a specific LUT filter. Remove or rename that LUT from the app bundle (or use a recipe from a different app build). Import and apply the recipe.
**Expected:** All adjustment sliders (brightness, contrast, etc.) are applied correctly. The filter slot shows blank/none. No crash, no error alert.
**Why human:** The nil-out logic is correct in code but the outcome — that the rendered preview looks right with other adjustments applied and filter blank — requires visual confirmation on device.

---

### Summary

All 5 RECIPE requirements are implemented end-to-end with real, substantive code. No stubs or placeholders were found. The persistence layer (RecipeItem, LibrarySchemaV1), service layer (RecipeStore), I/O layer (RecipeFileIO, ExportedRecipe), and UI layer (RecipesSheetView, RecipeNamePromptView) are all present and wired together through ContentView and EditorViewModel.

The three human verification items are UX confirmation and runtime behavior checks, not implementation gaps. The phase goal — "Users can capture a look as a named Recipe, reuse it across photos, and share it with others" — is fully addressed in the codebase.

---

_Verified: 2026-05-03_
_Verifier: Claude (gsd-verifier)_
