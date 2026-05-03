---
phase: 06-recipes
plan: 04
subsystem: infra
tags: [ios, plist, uti, file-association, photorecipe]

requires:
  - phase: 05-export
    provides: ShareSheetView and export pipeline that will share .photorecipe files

provides:
  - CFBundleDocumentTypes entry declaring this app as Owner handler for com.photoeditor.recipe
  - UTExportedTypeDeclarations entry defining com.photoeditor.recipe (extension=photorecipe, conforms to public.json + public.data)

affects: [06-recipes, plan 06-06 onOpenURL import handler]

tech-stack:
  added: []
  patterns: [iOS custom UTI export declaration pattern; LSHandlerRank=Owner for proprietary file types]

key-files:
  created: []
  modified:
    - PhotoEditor/Info.plist

key-decisions:
  - "LSHandlerRank=Owner (not Default/Alternate) — app is canonical owner of .photorecipe files; no other app should claim this extension"
  - "UTTypeConformsTo includes both public.json and public.data — enables text-editor fallback and binary-safe transfer over AirDrop"
  - "MIME type application/x-photoeditor-recipe is custom (no registered IANA type for this extension) — acceptable for app-specific format"

patterns-established:
  - "Info.plist UTI registration: CFBundleDocumentTypes references the UTI string; UTExportedTypeDeclarations defines it — both must be present for OS routing to work"

requirements-completed: [RECIPE-04]

duration: 3min
completed: 2026-05-03
---

# Phase 6 Plan 04: Info.plist UTI Registration Summary

**Registered custom UTI `com.photoeditor.recipe` in Info.plist so iOS routes `.photorecipe` files (AirDrop, Files app, share sheet) to PhotoEditor**

## Performance

- **Duration:** 3 min
- **Started:** 2026-05-03T22:10:00Z
- **Completed:** 2026-05-03T22:13:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Added `CFBundleDocumentTypes` declaring PhotoEditor as `LSHandlerRank=Owner` for `com.photoeditor.recipe` files
- Added `UTExportedTypeDeclarations` defining `com.photoeditor.recipe` — conforms to `public.json` + `public.data`, extension `photorecipe`, MIME `application/x-photoeditor-recipe`
- Verified plist parses cleanly via Python `plistlib`

## Task Commits

1. **Task 1: Add CFBundleDocumentTypes + UTExportedTypeDeclarations** - `758bac0` (feat)

**Plan metadata:** (included in task commit — single-file plan)

## Files Created/Modified
- `PhotoEditor/Info.plist` - Added two top-level keys for .photorecipe UTI registration

## Decisions Made
- `LSHandlerRank=Owner` ensures the OS presents PhotoEditor as the default (and only declared) handler for `.photorecipe`, not a fallback option
- Conformance to `public.json` and `public.data` follows Apple guidance for app-specific JSON-based formats — enables generic fallback viewers and safe binary transfer

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- UTI registration is complete; plan 06-06 can now wire `.onOpenURL` to import `.photorecipe` files
- Real-device verification required (per STATE.md blocker): UTI routing cannot be validated in Simulator — must be tested on device after full Phase 6 lands

---
*Phase: 06-recipes*
*Completed: 2026-05-03*
