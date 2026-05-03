# Phase 2: LUT Filter Pipeline - Context

**Gathered:** 2026-05-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Establish the product's visual identity. Replace the empty filter strip from Phase 1 with a working LUT pipeline:

- A `.cube` file parser (in-house, no SPM dependency) producing 64-point `CIColorCubeWithColorSpace` data
- A `FilterLibrary` service that loads bundled `.cube` files at launch, exposes them via stable UUIDs, supports favorites persisted to UserDefaults
- Wire-up of the `LUT` stage in `PipelineBuilder` (currently identity pass-through) to apply the chosen filter with strength blending
- The filter strip in `ContentView` rendering thumbnails generated from the user's current photo, with selection + strength control
- Ship at least 5 starter LUTs (procedurally generated where possible — identity, warm-fade, cool-cinematic, B&W-noir, sepia-tonal) so the app looks alive on first launch. The user can drop real artist `.cube` files into `Resources/LUTs/` later; the loader will pick them up by file presence.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion (locked by research + Phase 1 architecture)

- **Cube format:** 64-point only. If a `.cube` file declares a 33-point `LUT_3D_SIZE`, the parser resamples to 64 (trilinear). Do not accept arbitrary sizes — log and skip.
- **Cube parser:** In-house Swift implementation. ~150 LOC. No SwiftCube SPM dependency (avoids adding SPM packages from Linux — user-friendly). Parser supports the standard Resolve `.cube` format: `LUT_3D_SIZE`, `DOMAIN_MIN`, `DOMAIN_MAX`, `TITLE`, comments (`#`), then `R G B` triplets.
- **Color space:** All cubes interpreted in linear sRGB (CGColorSpace `extendedLinearSRGB`) — matches the RenderEngine working space established in Phase 1.
- **Starter LUTs:** Procedurally generated via small Swift functions producing 64³ Float arrays. We do NOT ship binary `.cube` files in the repo — instead, a `BuiltInLUTs.swift` exposes typed factory functions (`identity()`, `warmFade()`, `cinematicCool()`, `noir()`, `sepia()`). Loader merges built-ins with any `.cube` files found in the bundle's `LUTs/` directory at launch.
- **Stable UUIDs:** Each filter has a hard-coded UUID string in source for built-ins. `.cube` files derive UUID from file name hash (deterministic — not random) — so renames change identity, but content edits do not. Recipes (Phase 6) reference UUID; missing UUID → graceful skip with empty LUT slot.
- **FilterLibrary:** `final class FilterLibrary` (not actor — read-mostly, in-memory snapshot). Holds `[Filter]`. `Filter` is `Identifiable`, `Equatable`, has `id: UUID`, `name: String`, `category: Category` (film/portrait/bw/cinematic), `kind: Kind` (`.builtIn(BuiltInLUT)` / `.cubeFile(URL)`), `cube: ColorCubeData` (lazy-loaded).
- **Favorites:** Set of UUIDs in UserDefaults under `filter.favorites`. `FilterLibrary.toggleFavorite(_:)` mutates; published via `@Observable` so the strip re-orders live.
- **Strength:** Already represented in `AdjustmentStack.filter.strength` (0...1). PipelineBuilder's LUT stage applies `CIColorCubeWithColorSpace` then blends with `CIBlendWithMask` against the unfiltered source by `strength`.
- **Filter strip UI:** Horizontal `ScrollView` of capsule thumbnails. Thumbnail = current preview image rendered through that filter at 200×200 px. Cached per (photo, filter) pair. Recompute when photo changes; invalidate on memory warning. Selected filter has accent ring; long-press → favorite toggle.
- **Strength slider:** Inline below the strip, only visible when a non-`.original` filter is selected. Snaps to 0/0.5/1.0 with light haptics (Phase 7 finishes haptics — Phase 2 reserves the snap points only).

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets

- `AdjustmentStack.FilterSelection { id: UUID?; strength: Double }` — already defined in Phase 1
- `PipelineBuilder.applyLUT(...)` — currently an identity pass-through stub waiting to be filled
- `RenderEngine.previewContext` — used for thumbnail rendering

### Established Patterns

- `@Observable` singleton-like service pattern (EditorViewModel)
- Pure-function pipeline stages
- Codable for persistence (FilterLibrary's UserDefaults blob)

### Integration Points

- `EditorViewModel.filterLibrary: FilterLibrary` — injected at init
- `ContentView` filterStrip: replaces the empty placeholder section
- `PipelineBuilder.applyLUT(input:filter:strength:)` — the new signature

</code_context>

<specifics>
## Specific Ideas

- Procedurally generated starter LUTs are *placeholders for visual variety* — not the final aesthetic. The "real" filter pack ships when artist `.cube` files are dropped into `Resources/LUTs/`. Keep this distinction clear in code comments and the loader log.
- The `.cube` parser is small enough to be unit-testable: test (1) 33-point upsample to 64 produces the right size array, (2) DOMAIN_MIN/MAX honored, (3) malformed input returns nil, (4) identity LUT round-trips colors unchanged.
- The thumbnail cache should be backed by `NSCache` keyed by `"\(photoIdentifier)#\(filterUUID)"` — auto-evicts on pressure.
- Filter strip thumbnails should fade in (no abrupt pop) — Phase 7 perfects motion, Phase 2 just establishes the surface.

</specifics>

<deferred>
## Deferred Ideas

- Filter packs / categories drawer with section headers — Phase 7 (or v2)
- LUT preview before applying (hover preview) — v2
- Importing user `.cube` files from Files.app — v2
- Filter names localization — v2

</deferred>
