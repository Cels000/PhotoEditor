# Phase 1: Rendering Foundation - Context

**Gathered:** 2026-05-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Replace the existing `CIPhotoEffect*` pipeline with a correct, premium-grade rendering foundation. Deliver: Metal-backed `CIContext` (preview + export, separated), a `RenderEngine` actor managing render queueing/cancellation, a `Codable` `AdjustmentStack` model with schema versioning, a pure `PipelineBuilder` function `(AdjustmentStack, CIImage) -> CIImage`, and a correct import path that preserves EXIF orientation and color profile (`Data → CIImage(data:options:)`, no UIImage detour).

This phase ships no new user-facing features beyond what the existing app already shows — it is the architectural floor every subsequent phase builds on. The brightness/contrast/saturation sliders are temporarily wired through the new pipeline using the existing `ADJUST-01` light controls (exposure, contrast, etc.) that ship in Phase 3 may be partially wired here as a smoke test, but the full panel UX is Phase 3.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

All implementation choices defer to the architecture and stack research already produced (`.planning/research/ARCHITECTURE.md`, `.planning/research/STACK.md`, `.planning/research/PITFALLS.md`). Specifically locked:

- **CIContext:** Two contexts — `previewContext` and `exportContext`. Both Metal-backed via `MTLCreateSystemDefaultDevice()` + `CIContext(mtlDevice:)`. Created once at app launch.
- **RenderEngine:** Swift `actor` with cancellable preview tasks. Debounce: 30–40 ms.
- **Preview downsampling:** 1080px long edge (per PITFALLS guidance).
- **AdjustmentStack:** flat `Codable` struct with `schemaVersion: Int` field. Persisted to SwiftData later as JSON `Data` blob.
- **PipelineBuilder:** Pure function. No state. Deterministic ordering: LUT → light → color → HSL → curves → split toning → effects → crop. Phase 1 only needs LUT-placeholder + light scaffolding; the full filter chain fills in over later phases — but the API surface accepts the full stack today.
- **Import path:** `Data → CIImage(data:options: [.applyOrientationProperty: true])`. No UIImage intermediate. Original PHAsset reference retained for future re-load (Phase 4).
- **Color management:** Working space `extendedLinearSRGB` (CGColorSpace.extendedLinearSRGB), output color space inferred from source.
- **Existing pipeline removal:** The current `PhotoEditorViewModel`'s `CIPhotoEffect*` filter switch + scheduleRender flow is fully removed in this phase. The 10 built-in filters disappear; the filter strip will be empty until Phase 2 lands the LUT pipeline.
- **No SwiftData yet:** Persistence lives in Phase 4. AdjustmentStack is in-memory only for Phase 1.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets

- `PhotoEditor/PhotoEditorApp.swift` — entry point, untouched
- `PhotoEditor/ContentView.swift` — view structure (image preview, action bar, slider section, save button) — keep the layout shell, gut the data flow
- `PhotoEditor/PhotoEditorViewModel.swift` — `@MainActor` ObservableObject, downsample helper, save flow — keep downsample utility, replace render path entirely
- `PhotoEditor/Info.plist` — Photos permissions configured

### Established Patterns

- SwiftUI + ObservableObject MVVM
- `PhotosPicker` for image selection
- `PHPhotoLibrary.requestAuthorization(for: .addOnly) async`
- `CIContext` → `createCGImage` → `UIImage` for display
- `Task.detached` + cancellation for offloading renders

### Integration Points

- Preview surface: `editorPreview` view in `ContentView.swift` — must consume `viewModel.previewImage: UIImage?` published property
- Save flow: `saveImage()` — must call into `RenderEngine.export(stack:source:)` for full-res render, then save to Photos
- Adjustments UI: Phase 1 keeps the existing brightness/contrast/saturation sliders pointed at `AdjustmentStack.light.exposure` / `.contrast` / `.saturation` as a smoke test; Phase 3 replaces these with the full panel UX

</code_context>

<specifics>
## Specific Ideas

- The `PipelineBuilder` should be pure and testable without UI — write unit tests against it where possible (even on Linux, swift-style tests can be reasoned about; CI is on the user's Mac).
- Add an XCTest target if missing.
- Treat `EXIF orientation` as a *first-class correctness bug* — if the photo is sideways once, it's a regression. Test the import path against a known-rotated photo on Mac.

</specifics>

<deferred>
## Deferred Ideas

- LUT loader, .cube parser → Phase 2
- Full adjustment panels (HSL, curves, etc.) → Phase 3
- SwiftData library persistence → Phase 4
- CGImageDestination export with format/quality controls → Phase 5
- Recipe save/share → Phase 6
- Haptics, animations, accessibility audit → Phase 7

</deferred>
