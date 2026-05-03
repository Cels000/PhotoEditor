---
phase: 06-recipes
plan: "05"
subsystem: editor
tags: [recipes, undo, filter-degradation, tests]
dependency_graph:
  requires: ["06-01", "06-02", "06-03"]
  provides: ["EditorViewModel.applyRecipe", "EditorViewModel.saveCurrentAsRecipe", "EditorViewModel.recipeStore"]
  affects: ["EditorViewModel", "RecipeStore", "RecipeItem"]
tech_stack:
  added: []
  patterns: ["missing-filter graceful degradation", "single undo entry per apply", "Task.detached thumbnail render"]
key_files:
  created:
    - PhotoEditorTests/RecipeApplyTests.swift
  modified:
    - PhotoEditor/Editor/EditorViewModel.swift
decisions:
  - "applyRecipe uses commitDiscreteChange (not beginInteractive/endInteractive) — recipe apply is discrete, one undo entry"
  - "saveCurrentAsRecipe proceeds with nil thumbnail when no photo loaded — no error surfaced, recipe saved with gradient cell per CONTEXT.md"
  - "missing filter ID cleared to nil while all other fields from recipe stack are preserved — RECIPE-05"
metrics:
  duration: "5min"
  completed_date: "2026-05-03"
  tasks: 2
  files: 2
---

# Phase 06 Plan 05: EditorViewModel Recipe Wiring Summary

EditorViewModel wired to RecipeStore with applyRecipe (RECIPE-02) + missing-filter degradation (RECIPE-05) + saveCurrentAsRecipe (RECIPE-01), all locked by four-case test suite.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add recipeStore, applyRecipe, saveCurrentAsRecipe to EditorViewModel | 139387c | PhotoEditor/Editor/EditorViewModel.swift |
| 2 | RecipeApplyTests covering missing-filter degradation | 5f46cfa | PhotoEditorTests/RecipeApplyTests.swift |

## What Was Built

**EditorViewModel extensions:**
- `var recipeStore: RecipeStore?` — optional property injected by ContentView, nil-safe for tests/previews
- `func applyRecipe(_ recipe: RecipeItem)` — swaps entire stack from recipe, resolves filter ID via FilterLibrary; clears filter slot if ID missing; calls commitDiscreteChange once then stackDidChange for debounced re-render
- `func saveCurrentAsRecipe(name: String) async` — validates trimmed name, renders 200x200 thumbnail off-main via Task.detached when photo loaded, calls recipeStore.save

**Test coverage (RecipeApplyTests.swift):**
- `testApplyWithMissingFilterClearsFilterSlot` — unknown filter ID → filter nil, all other adjustments intact
- `testApplyWithNilFilterPreservesNilFilter` — control case, nil stays nil
- `testApplyWithKnownFilterPreservesFilter` — identity LUT resolves → preserved with strength
- `testApplyCreatesSingleUndoEntry` — one apply = one undo step returns to pre-apply identity

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- PhotoEditor/Editor/EditorViewModel.swift: present with recipeStore, applyRecipe, saveCurrentAsRecipe, filterLibrary.filter(withID:) nil check, 3x commitDiscreteChange calls
- PhotoEditorTests/RecipeApplyTests.swift: present with all four test cases
- Commits 139387c and 5f46cfa verified in git log
