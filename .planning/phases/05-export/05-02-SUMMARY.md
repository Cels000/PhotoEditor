---
phase: 05-export
plan: "02"
subsystem: export
tags: [ImageIO, CGImageDestination, CoreImage, CIContext, Lanczos, EXIF, GPS-strip, color-profile, HEIC]

requires:
  - phase: 05-export
    provides: ExportOptions / ExportFormat / ExportSize types (05-01)

provides:
  - "ExportService.encode(cgImage:sourceProperties:colorSpace:options:) -> Data"
  - "Pure CGImageDestination encoder with EXIF preserve, GPS strip, P3 color profile, resize"
  - "HEIC fallback to JPEG when encoder absent"

affects: [05-03, 05-04, 05-05, EditorViewModel.export]

tech-stack:
  added: []
  patterns:
    - "Pure enum namespace for stateless service (no actor needed — caller dispatches off-main)"
    - "CGImageDestination encoding: CGImageDestinationCreateWithData + AddImage + Finalize"
    - "Color profile tagging: cgImage.copy(colorSpace:) before encode (not kCGImagePropertyProfileName)"
    - "Lanczos resize: CIImage.transformed + CIContext(workingColorSpace: extendedLinearSRGB)"
    - "HEIC support probe: attempt destination creation; nil = fall back to JPEG"

key-files:
  created:
    - PhotoEditor/Export/ExportService.swift
  modified: []

key-decisions:
  - "ExportService is a non-isolated enum; caller (EditorViewModel) owns Task.detached dispatch"
  - "Color space tagging via cgImage.copy(colorSpace:) — NOT kCGImagePropertyProfileName which is wrong key"
  - "kCGImagePropertyGPSDictionary never written to props dict — strip is enforced by omission"
  - "HEIC fallback probe at encode time (not at startup) — lazy, per-encode check avoids state"
  - "Resize never upscales: guard scale <= 1.0 + resolve() already clamps .full to sourceLongEdge"

requirements-completed: [EXPORT-03, EXPORT-04, EXPORT-05, EXPORT-06]

duration: 8min
completed: 2026-05-03
---

# Phase 5 Plan 02: ExportService Summary

**CGImageDestination-based pure encoder with EXIF passthrough, GPS strip, Display P3 profile, Lanczos resize, and HEIC-to-JPEG fallback**

## Performance

- **Duration:** 8 min
- **Started:** 2026-05-03T21:53:55Z
- **Completed:** 2026-05-03T22:01:55Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- `ExportService.encode(cgImage:sourceProperties:colorSpace:options:)` — single public entry point returning `Data`
- CGImageDestination path (not UIImage round-trip) preserves ICC color profile and gives full metadata control
- GPS and IPTC dictionaries stripped by omission; TIFF + Exif dictionaries carried through with orientation sanitized to 1
- Lanczos downsample via `CIImage.transformed` + `CIContext(workingColorSpace: extendedLinearSRGB, outputColorSpace: outputCS)`
- HEIC encoder probed at encode time; falls back to JPEG on older simulators where HEIC encoding is absent

## Task Commits

1. **Task 1: ExportService encoder with EXIF preservation, GPS strip, P3 profile** — `8dfbe16` (feat)

**Plan metadata:** (pending docs commit)

## Files Created/Modified

- `PhotoEditor/Export/ExportService.swift` — Pure encoder enum; private helpers for resize, UTI resolution, metadata sanitization, and CGImageDestination finalization

## Public API

```swift
public enum ExportService {
    public enum Error: Swift.Error { case encodeFailed, unsupportedFormat, resizeFailed }

    public static func encode(
        cgImage: CGImage,
        sourceProperties: [CFString: Any],
        colorSpace: CGColorSpace?,
        options: ExportOptions
    ) throws -> Data
}
```

## Key Behaviors

### Quality / Format
- **JPEG/HEIC:** `kCGImageDestinationLossyCompressionQuality = options.quality` in properties dict
- **PNG:** quality key omitted (lossless; `ExportFormat.supportsQuality` is `false`)
- **HEIC fallback:** `CGImageDestinationCreateWithData` probed at encode time; `nil` result → UTType.jpeg.identifier used instead

### Color Space
- `outputCS = colorSpace ?? displayP3 ?? sRGB` — named profiles only (PITFALL #4: never `CGColorSpaceCreateDeviceRGB`)
- Tagging: `cgImage.copy(colorSpace: outputCS)` applied before resize and encode — the destination inherits whatever profile the CGImage carries
- CIContext uses `workingColorSpace: extendedLinearSRGB` for precision, `outputColorSpace: outputCS` for final conversion

### EXIF Preservation
- `kCGImagePropertyTIFFDictionary` — carried through; `kCGImagePropertyTIFFOrientation` overwritten to 1
- `kCGImagePropertyExifDictionary` — carried through as-is
- `kCGImagePropertyOrientation = 1` set at top-level properties dict (PITFALL #3: baked rotation)

### GPS / IPTC Strip
- `kCGImagePropertyGPSDictionary` — deliberately NOT copied (referenced only in strip comments)
- `kCGImagePropertyIPTCDictionary` — deliberately NOT copied

### Resize
- Source long edge = `max(cgImage.width, cgImage.height)`
- `targetLongEdge = options.size.resolve(sourceLongEdge:)` — clamped by `ExportSize`
- Skip resize when `|target - source| < 1` (integer pixels)
- Scale `= targetLongEdge / sourceLongEdge` — never exceeds 1.0; guard enforced
- Lanczos quality comes from CIImage's default `CILanczosScaleTransform` path

## Decisions Made

- `ExportService` is a non-isolated enum rather than an actor — encoding is pure and stateless; the caller (`EditorViewModel`) owns `Task.detached` dispatch
- Color space is tagged via `cgImage.copy(colorSpace:)` rather than the properties dict — the ImageIO `kCGImagePropertyProfileName` key is not the correct mechanism for embedding an ICC profile
- GPS strip is enforced by omission from the properties dict, not by explicit deletion — simpler and equally correct
- HEIC fallback probe is per-encode (not cached at startup) — avoids state, negligible cost

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- `ExportService.encode` is ready for plan 05-03 (PHPhotoLibrary save) and 05-04 (Share sheet)
- `EditorViewModel.export(options:)` in plan 05-05 will call `ExportService.encode` then dispatch to save/share
- No blockers

---
*Phase: 05-export*
*Completed: 2026-05-03*
