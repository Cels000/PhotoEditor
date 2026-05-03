---
phase: 03-editor-ui-full-adjustments
plan: "07"
subsystem: ui
tags: [swift, undo-redo, history, adjustment-stack, drag-coalescing]

requires:
  - phase: 03-editor-ui-full-adjustments
    provides: EditorViewModel with stackDidChange() and AdjustmentStack value type

provides:
  - UndoStack value type: capacity-capped linear undo/redo over AdjustmentStack snapshots
  - EditorViewModel.undo() / redo() for restoring prior/next snapshots
  - EditorViewModel.canUndo / canRedo computed properties for UI button enable-state
  - beginInteractiveEdit() / endInteractiveEdit() for drag coalescing (one push per drag)
  - commitDiscreteChange() for discrete mutations (filter select, crop apply)
  - resetAdjustments() now pushes .identity so reset is itself undoable

affects:
  - 03-08-panel-ui (wires AdjustmentSlider.onEditingChanged to beginInteractiveEdit/endInteractiveEdit)
  - Any future plan wiring undo/redo buttons to canUndo/canRedo

tech-stack:
  added: []
  patterns:
    - "Pending-snapshot drag coalescing: capture pre-drag state, push once on drag-end only if changed"
    - "Re-entrancy guard in beginInteractiveEdit: only captures if pendingDragSnapshot == nil"
    - "Reset-as-undoable: resetAdjustments() pushes .identity before clearing messages"

key-files:
  created:
    - PhotoEditor/Editor/UndoStack.swift
  modified:
    - PhotoEditor/Editor/EditorViewModel.swift

key-decisions:
  - "UndoStack is a pure value type with no SwiftUI/CoreImage imports — snapshots are AdjustmentStack values"
  - "Drag coalescing uses a pendingDragSnapshot field; endInteractiveEdit compares pre/post and pushes exactly once"
  - "resetAdjustments() guards on stack != .identity to avoid a no-op reset pushing an extra entry"
  - "commitDiscreteChange() is the explicit hook for discrete mutations; setFilterStrength relies on caller's begin/endInteractiveEdit"

patterns-established:
  - "Interactive edit pattern: beginInteractiveEdit() before drag, endInteractiveEdit() after drag-end"
  - "Discrete change pattern: mutate stack, then call commitDiscreteChange()"

requirements-completed: [HIST-01, HIST-03]

duration: 4min
completed: 2026-05-03
---

# Phase 3 Plan 07: Undo/Redo + Drag Coalescing Summary

**UndoStack value type + EditorViewModel undo/redo integration with one-push-per-drag coalescing and undoable reset**

## Performance

- **Duration:** 4 min
- **Started:** 2026-05-03T21:14:50Z
- **Completed:** 2026-05-03T21:19:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Created UndoStack: capacity-capped (100 entries) pure value type with push/seed/clear/undo/redo
- Integrated undo/redo into EditorViewModel with beginInteractiveEdit/endInteractiveEdit for drag coalescing
- resetAdjustments() now pushes identity snapshot so reset is itself undoable
- selectFilter() calls commitDiscreteChange() after mutation for proper history tracking

## Task Commits

1. **Task 1: Create UndoStack value type** - `755636a` (feat)
2. **Task 2: Integrate undo/redo + drag coalescing into EditorViewModel** - `d2b856a` (feat)

## Files Created/Modified
- `PhotoEditor/Editor/UndoStack.swift` - Generic value-type undo stack over AdjustmentStack snapshots
- `PhotoEditor/Editor/EditorViewModel.swift` - undo/redo methods, drag coalescing, commitDiscreteChange, canUndo/canRedo

## Decisions Made
- UndoStack is a pure Foundation value type — no SwiftUI/CoreImage dependency keeps it testable in isolation
- pendingDragSnapshot re-entrancy guard means nested beginInteractiveEdit calls are safe (first snapshot wins)
- resetAdjustments() short-circuits on stack == .identity to prevent a no-op from dirtying the undo stack
- setFilterStrength intentionally not auto-committing — strength slider wired via panel UI (03-08)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- HIST-01 and HIST-03 wired; UI buttons (undo/redo toolbar items) and confirmation alert for Reset All live in 03-08
- AdjustmentSlider.onEditingChanged callbacks need to forward begin/endInteractiveEdit to EditorViewModel (03-08 owns this wiring)
- canUndo / canRedo are ready to bind to SwiftUI button `.disabled` state

---
*Phase: 03-editor-ui-full-adjustments*
*Completed: 2026-05-03*
