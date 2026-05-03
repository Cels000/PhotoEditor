# Phase 5: Export - Context

**Gathered:** 2026-05-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Get edited photos out of the app. Replace the existing simple "Save to Photos" with a real export pipeline:

- Format choice (JPEG / HEIC / PNG)
- Size choice (full / web / story presets + custom long-edge)
- Quality slider for lossy formats
- Color profile preserved (Display P3 where supported)
- EXIF preserved (date, orientation), GPS/identifying metadata stripped by default
- Save to Photos full-res
- Share-sheet to any iOS destination
- Progress indicator during export, success/failure confirmation

Export uses `RenderEngine.exportContext` (Phase 1) + `PipelineBuilder.build` (Phase 1+3) + `CGImageDestination` (this phase).

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

- **Export pipeline:** `ExportService` actor or namespace. Input: `(stack: AdjustmentStack, source: ImportedImage, options: ExportOptions)`. Output: `Data` (encoded image bytes). Saving to Photos / Share is orchestrated by the caller.
- **CGImageDestination usage:** Encoding via `CGImageDestinationCreateWithData` (in-memory, no temp file unless user-explicit Share). Set `kCGImageDestinationLossyCompressionQuality` for JPEG/HEIC.
- **Color profile:** When source CIImage has Display P3 profile, output writes Display P3 ICC profile in metadata. Working space remains `extendedLinearSRGB` through the pipeline; final color space conversion happens in `createCGImage` via `RenderEngine.exportContext.outputColorSpace`. Honor source's profile preference: P3 in → P3 out; sRGB in → sRGB out (default).
- **EXIF preservation:** Read source EXIF via `CGImageSourceCopyPropertiesAtIndex`. Carry through: `TIFFDictionary` (orientation, creation date), `ExifDictionary` (capture metadata). STRIP: `GPSDictionary`, `IPTC` author/contact fields.
- **Format → UTI map:**
  - JPEG: `UTType.jpeg.identifier`
  - HEIC: `UTType.heic.identifier` (fallback to JPEG if device doesn't support — older simulators)
  - PNG: `UTType.png.identifier` (no quality — always lossless)
- **Size presets (long-edge):**
  - Full: source long-edge (no resize)
  - Web: 2048
  - Story: 1080
  - Custom: user-entered value, clamped 256...8192
- **Quality slider:** 0.4...1.0, default 0.85, only visible for JPEG/HEIC. Step 0.05.
- **ExportOptions struct:** `Codable`, has `format: ExportFormat`, `size: ExportSize`, `quality: Double`. Default values reasonable.
- **Save to Photos:** existing `PHAssetChangeRequest.creationRequestForAsset(from: UIImage)` path replaced by `PHAssetCreationRequest.addResource(with: .photo, data: encodedData, options: nil)` so we control the encoded bytes (preserves our format/quality choices, otherwise UIImage round-trip re-encodes as JPEG).
- **Share sheet:** `UIActivityViewController` wrapped via `UIViewControllerRepresentable`. Activity items: `[Data]` → write to temp file with correct extension first, share that URL. Cleanup on dismissal.
- **Export sheet UI:** Bottom sheet "Export" with sections (Format / Size / Quality / Action). "Save to Photos" + "Share" buttons. Progress overlay during render.
- **Progress:** "Exporting..." with indeterminate spinner. Render is fast (full-res, single-pass) — typically <2s for 12MP. Don't bother with a percentage.
- **Error surfacing:** "Export failed: <reason>" alert. Specific cases: PHPhotoLibrary auth denied, encode failure, file write failure.
- **Replaces existing save:** The current `EditorViewModel.saveImage()` (rendering + creationRequestForAsset) is removed. New entry: `EditorViewModel.export(options:)` returns `Data` for the caller to dispatch (Save / Share / Both).

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets

- `RenderEngine.exportContext` — Metal CIContext with Display P3 output (Phase 1)
- `RenderEngine.renderExport(stack:source:cubeResolver:)` — full-res CIImage render (Phase 1, expanded Phase 3)
- `EditorViewModel.saveImage()` — current legacy implementation, to be replaced
- `ImportedImage.previewCIImage` and `.exportCIImage` — Phase 1
- ExifSDK / CGImageSource: built into iOS

### Patterns

- `@Observable` services
- Async/await + `Task.detached(priority: .userInitiated)` for off-main render
- Progress via `@State var isExporting: Bool` + overlay

### Integration Points

- `ContentView` — Export button (replaces current Save button) → presents sheet
- `EditorViewModel.export(options:) async throws -> Data`
- `PHPhotoLibrary` permission already requested (Phase 1 Info.plist)

</code_context>

<specifics>
## Specific Ideas

- Don't expose PNG quality — explain in the Format picker that PNG is lossless.
- Custom size: simple TextField with numeric validation, range 256–8192.
- Format default: HEIC (best size/quality tradeoff). If user previously picked another, persist to UserDefaults.
- Share extension target on iOS exposes "Save Image" itself via UIActivityViewController.
- Don't strip orientation EXIF — even though the bitmap is already pre-rotated, downstream tools may still inspect it; setting orientation = 1 (Up) explicitly is safest after we bake the rotation.

</specifics>

<deferred>
## Deferred Ideas

- Watermark on export (out of scope for v1, no monetization)
- Batch export from library — v2
- AVIF format — v2 (HEIC is fine for v1)
- Export presets ("Instagram", "Print 8x10") — v2
- Direct social share targets (Twitter X, IG) — v2 (system share covers this)

</deferred>
