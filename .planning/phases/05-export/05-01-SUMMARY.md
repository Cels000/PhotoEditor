---
phase: 05-export
plan: "01"
subsystem: export
tags: [swift, UniformTypeIdentifiers, UTType, Codable, value-types]

requires: []
provides:
  - ExportFormat enum (jpeg/heic/png) with UTType identifiers, supportsQuality, fileExtension, displayName
  - ExportSize enum (full/web/story/custom) with resolve(sourceLongEdge:) single clamp site 256...8192
  - ExportOptions struct (Codable, Equatable) with HEIC+full+0.85 defaults and static .default
affects: [05-02, 05-03, 05-04, 05-05, 05-06]

tech-stack:
  added: [UniformTypeIdentifiers]
  patterns: [pure Foundation value types with no UIKit/CoreImage; single clamp site for resize boundary]

key-files:
  created:
    - PhotoEditor/Export/ExportOptions.swift
  modified: []

key-decisions:
  - "ExportFormat.uti uses UTType.{jpeg|heic|png}.identifier — OS owns canonical strings, no hard-coding"
  - "resolve(sourceLongEdge:) is the single clamp site for 256...8192; downstream plans must not re-clamp"
  - "ExportSize.custom Codable via Swift 5.5+ synthesized enum-with-associated-value encoding"
  - "PNG supportsQuality=false is the API boundary for hiding quality slider (EXPORT-05)"

patterns-established:
  - "Single clamp site pattern: ExportSize.resolve() owns all boundary enforcement"
  - "supportsQuality flag drives UI visibility rather than conditional checks at call sites"

requirements-completed: [EXPORT-03, EXPORT-04, EXPORT-05]

duration: 5min
completed: 2026-05-03
---

# Phase 5 Plan 01: Export Value Types Summary

**Pure Foundation/UTType value types (ExportFormat, ExportSize, ExportOptions) defining the canonical export configuration contract for all Phase 5 downstream plans**

## Performance

- **Duration:** 5 min
- **Started:** 2026-05-03T00:00:00Z
- **Completed:** 2026-05-03T00:05:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Defined `ExportFormat` enum with three cases, UTType identifier mapping, supportsQuality boundary for PNG lossless path, and display metadata
- Defined `ExportSize` enum with four presets and a single `resolve(sourceLongEdge:)` clamp site enforcing the 256...8192 custom range rule
- Defined `ExportOptions` struct (Codable, Equatable) with HEIC+full+0.85 defaults and `static let default` per EXPORT-03/04/05

## Type Signatures

```swift
public enum ExportFormat: String, Codable, Hashable, CaseIterable {
    case jpeg, heic, png
    public var uti: String            // UTType.jpeg/heic/png.identifier
    public var fileExtension: String  // "jpg" / "heic" / "png"
    public var supportsQuality: Bool  // true for jpeg/heic; false for png
    public var displayName: String    // "JPEG" / "HEIC" / "PNG"
}

public enum ExportSize: Codable, Hashable {
    case full
    case web
    case story
    case custom(longEdge: Int)
    public func resolve(sourceLongEdge: Int) -> Int  // clamp site: 256...8192
    public var displayName: String
}

public struct ExportOptions: Codable, Equatable {
    public var format: ExportFormat   // default: .heic
    public var size: ExportSize       // default: .full
    public var quality: Double        // default: 0.85
    public static let `default` = ExportOptions()
}
```

## Default Values

| Field | Default | Requirement |
|-------|---------|-------------|
| format | .heic | EXPORT-03 |
| size | .full | EXPORT-04 |
| quality | 0.85 | EXPORT-05 |

## Clamp Range

`ExportSize.custom(longEdge:).resolve(sourceLongEdge:)` clamps to `max(256, min(8192, n))`. This is the single authoritative clamp site — downstream plans must not re-clamp.

Examples:
- `custom(100).resolve(sourceLongEdge: 9999)` → 256
- `custom(99999).resolve(sourceLongEdge: 100)` → 8192

## Codable Round-Trip

`ExportSize` with associated value `.custom(longEdge:)` is handled by Swift 5.5+ synthesized Codable for enums with associated values. JSON encode → decode preserves all cases including `.custom(n)`.

## Task Commits

1. **Task 1: Define ExportFormat / ExportSize / ExportOptions value types** - `3d63c86` (feat)

## Files Created/Modified

- `PhotoEditor/Export/ExportOptions.swift` — All three exported types; 112 lines; pure Foundation + UniformTypeIdentifiers

## Decisions Made

- `ExportFormat.uti` uses `UTType.jpeg.identifier` etc. rather than hard-coded strings — OS owns canonical UTI strings, avoids silent drift
- `resolve(sourceLongEdge:)` is the single clamp site; comment explicitly instructs downstream plans not to re-clamp independently
- PNG `supportsQuality = false` is the designated API boundary for EXPORT-05 (quality slider hidden for lossless format)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

All downstream Phase 5 plans (02 encoder, 03 save-to-Photos, 04 share-sheet, 05 view-model, 06 UI) can import and use `ExportFormat`, `ExportSize`, `ExportOptions` without modification. The file has no app-code dependencies — only Foundation and UniformTypeIdentifiers.

---
*Phase: 05-export*
*Completed: 2026-05-03*
