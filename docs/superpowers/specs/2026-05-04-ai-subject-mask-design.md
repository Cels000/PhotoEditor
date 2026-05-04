# AI Subject Mask — Design Spec

**Date:** 2026-05-04
**Size:** M
**Status:** Approved (brainstorming)

## Goal

One tap → perfect cutout of the subject, then independently edit subject and background within a single photo. Both regions are full first-class adjustment stacks (LUT + light + color + HSL + curves + …), composited via a Vision-generated foreground mask that the user can refine.

## User Story

> *I open a photo of my kid at sunset. I want them warm and bright, but the sky cooler and more contrasty. I tap the mask icon, the system finds the subject in under a second, and now my slider panel header shows `[Subject | Full | Background]`. I dial subject warmth +20, switch to Background, drop temperature −15, push contrast +10. Export. Done.*

## Decisions Locked

1. **Dual stacks** (not single-scope or per-stage scope). Subject and background each carry a full `AdjustmentStack`.
2. **Mask button → modal scope** (not a permanent segmented control). Toolbar button toggles into masked mode.
3. **Sub-segment inside the panel header** when masked: `[Subject | Full | Background]`. `Full` writes both stacks in lockstep.
4. **Refinement controls (v1):** feather + invert + per-instance include/exclude. No manual brush.

## Architecture

### Data model

`AdjustmentStack` (current top-level edit state) is wrapped by a new top-level document type:

```swift
struct EditDocument: Codable, Equatable {
    var schemaVersion: Int = 2
    var subjectStack = AdjustmentStack()  // canonical when mask == nil
    var backgroundStack = AdjustmentStack()
    var mask: SubjectMask? = nil
}

struct SubjectMask: Codable, Equatable {
    var feather: Double = 0          // 0...1 → gaussian blur radius scalar
    var invert: Bool = false
    var excludedInstances: Set<Int> = []
}
```

`AdjustmentStack` itself is unchanged — this is an additive wrapper.

### Mode rules

- `document.mask == nil` — single-stack mode. Sliders read/write `subjectStack`. `backgroundStack` is unused.
- `document.mask != nil` — masked mode. Panel header shows `[Subject | Full | Background]`.
  - **Subject** writes only `subjectStack`.
  - **Background** writes only `backgroundStack`.
  - **Full** mirror-writes both stacks. Used for symmetric global tweaks after the mask is applied.

### Crop pinning

`subjectStack.crop` is the canonical crop for the document. View model mirrors crop writes from Background and Full sub-segments into `subjectStack.crop` so the two stacks' crops can never diverge. Pipeline reads only `subjectStack.crop` and applies it once after compositing.

**Why:** mask is in source-pixel space. If subject and background cropped independently, the mask would no longer align with either rendered branch.

### Migration

Saved edits today are `AdjustmentStack` v1. Read path for v2:

1. If JSON root has `schemaVersion: 2`, decode `EditDocument` directly.
2. Otherwise, decode legacy `AdjustmentStack`, then construct `EditDocument(subjectStack: legacy, backgroundStack: legacy, mask: nil)`.

Pure superset migration; no field is removed or repurposed.

## Render Pipeline

### New entry point

```swift
extension PipelineBuilder {
    static func build(document: EditDocument,
                      source: CIImage,
                      cubeResolver: CubeResolver?,
                      maskProvider: SubjectMaskProvider?) -> CIImage
}
```

Existing `build(stack:source:cubeResolver:)` stays unchanged for callers that still pass a single stack (preset thumbnail rendering, filter previews).

### Branches

**Unmasked path** (`document.mask == nil`):

```
PipelineBuilder.build(stack: document.subjectStack, source: source, cubeResolver: cubeResolver)
```

Identical to today's behavior.

**Masked path** (`document.mask != nil`):

1. Render `subjectPass = build(stack: subjectStack, source: source, cubeResolver:)` with crop suppressed.
2. Render `bgPass = build(stack: backgroundStack, source: source, cubeResolver:)` with crop suppressed.
3. Resolve `effectiveMask` from `maskProvider`:
   - Start with `maskResult.combined`.
   - For each `i` in `mask.excludedInstances`: subtract `maskResult.perInstance[i]` (CISubtractBlendMode equivalent).
   - If `mask.invert`: apply `CIColorInvert`.
   - If `mask.feather > 0`: apply `CIGaussianBlur` with radius = `feather * min(W, H) * 0.02`.
4. `composite = CIBlendWithMask(inputImage: subjectPass, backgroundImage: bgPass, maskImage: effectiveMask)`.
5. Apply `subjectStack.crop` to `composite`.

Crop suppression in steps 1–2 is implemented by passing a stripped-crop copy of the stack to the existing `build(stack:…)`. Stage order inside each pass remains LUT → light → color → HSL → curves → split → grain → vignette → sharpness → (no crop).

### Performance budget

- One unmasked render: ~7ms on A15 at 2048px (current measurement).
- Masked render: ~12ms on A15 at 2048px (Core Image fuses both branches into a single Metal command buffer; mask compositing is a single GPU pass).
- Both within the 30ms render-debounce budget — preview stays at 60 fps target.

## Mask Computation

### API

```swift
@MainActor
final class SubjectMaskStore {
    func mask(for assetID: AssetID, source: CIImage) async throws -> SubjectMaskResult
    func prefetch(for assetID: AssetID, source: CIImage)  // fire-and-forget
    func clear(for assetID: AssetID)
}

struct SubjectMaskResult {
    let combined: CIImage
    let perInstance: [CIImage]
    let instanceCount: Int
    let detectedAt: Date
}

protocol SubjectMaskProvider {
    func currentMask(for assetID: AssetID) -> SubjectMaskResult?
}
```

### Vision request

`VNGenerateForegroundInstanceMaskRequest` on a `VNImageRequestHandler`:

- Run on a background `Task` with QoS `.userInitiated` when triggered by tap; `.utility` when prefetching on import.
- Input: same downsampled CIImage used by render engine (≤2048px).
- Output: one `VNInstanceMaskObservation` containing all instances. Use `generateMaskedImage(ofInstances:from:)` for combined; iterate `allInstances` per index for per-instance.

### Caching

- **In-memory LRU**, capacity 8 entries (covers active editing session).
- **Disk cache** under `Caches/SubjectMasks/<hash>.png`, where `<hash>` is the SHA-256 of the source image's pixel data (stable across app launches; invalidated when pixels change).
- Disk cache stores **combined mask only**. Per-instance is recomputed from a fresh Vision pass when needed (rare — only on refinement-sheet open).
- Eager prefetch on import means the common case is "user taps mask, result is already in memory."

### Triggering

| When | Action |
|---|---|
| User imports a photo | `prefetch(for: assetID, source:)` after thumbnail generation |
| User taps mask button, result cached | Apply immediately |
| User taps mask button, result not yet ready | Mask icon shows shimmer; `await mask(for:)`; UI advances when result arrives |
| Vision returns 0 instances | Mask icon enters disabled state; one-time toast "No subject detected." |

## UX

### Toolbar entry

A single mask icon in the editor toolbar, alongside existing tools.

- **Idle (no mask):** standard icon. Tap → enter masked mode (Subject sub-segment selected).
- **Active (mask exists):** icon shows filled/colored. Tap → opens refinement bottom sheet.
- **Disabled:** Vision found no instances. Tap shows the one-time toast.

### Panel header sub-segment

When `document.mask != nil`, the slider panel grows a header row:

```
[ Subject | Full | Background ]
```

- Selection persists across panel switches within a session.
- A small thumbnail of the active mask sits next to the segment for context.

### Refinement bottom sheet

Opened by tapping the active mask icon. Contains:

1. **Feather** slider (0–1, default 0). Live-updates the mask preview overlay.
2. **Invert** toggle. Mask flip; does NOT swap which slider state is which.
3. **Instances** — main canvas dims and shows tinted overlays per detected instance. Tap an overlay to toggle exclude. Theme accent cycles for visual distinction. Below the canvas: a list (`Subject 1`, `Subject 2`, …) with checkboxes as accessibility fallback.
4. **Remove Mask** button at the bottom. Confirms with action sheet: "Remove subject mask? Background edits will be discarded." On confirm: `mask = nil`, `backgroundStack = subjectStack` (value-type assignment), so the document collapses cleanly back to single-stack mode. No partial states.

## Edge Cases

| Case | Behavior |
|---|---|
| Vision finds 0 instances | Mask icon disabled, toast surfaced |
| Vision finds 1 instance covering ≥95% | Allowed; refinement sheet still works; user can invert |
| User excludes every instance | `combined` becomes empty (all-black mask); composite is pure background stack; banner: "All subjects excluded — only background edits visible" |
| Crop changes during masked mode | Crop applied post-composite from `subjectStack.crop`; mask never re-derived |
| Source image replaced (re-import / new asset) | `document.mask` cleared at the document layer; new prefetch triggered |
| Undo/redo across mask add/remove | `EditDocument` is `Equatable` value-type → existing undo stack handles it for free |
| Vision request fails (rare runtime error) | Mask icon disabled; toast "Couldn't compute subject mask. Try again." Retry on next tap |
| User backgrounds app mid-compute | Task continues if possible; if cancelled by system, retried on tap |

## Components

| Component | Responsibility | Location (suggested) |
|---|---|---|
| `EditDocument` | Top-level edit state, dual stacks + optional mask | `Editor/AdjustmentStack.swift` (extend file) |
| `SubjectMask` | Refinement parameters | same file |
| `SubjectMaskStore` | Vision compute + memory/disk caching | `Editor/SubjectMaskStore.swift` (new) |
| `SubjectMaskResult` / `SubjectMaskProvider` | Mask data + read interface for pipeline | same file |
| `PipelineBuilder.build(document:…)` | Masked compositing path | `RenderEngine/PipelineBuilder.swift` (extend) |
| `EditorViewModel` | Sub-segment routing, crop mirror-writes, mask state transitions | `Editor/EditorViewModel.swift` (extend) |
| Mask toolbar button | Entry point + state visualization | `Editor/Controls/` (new file) |
| Panel header sub-segment | `[Subject | Full | Background]` selector | `Editor/Panels/` (new file) |
| Refinement bottom sheet | Feather, invert, instance picker, remove | `Editor/Panels/` (new file) |
| Instance overlay | Tinted regions on canvas during refinement | `Editor/` (new file) |

## Out of Scope (v1)

- Manual brush touch-up of the mask
- Hair-edge auto-refinement / matting
- Per-instance independent adjustment stacks (each detected person gets their own stack)
- Per-stage scope (e.g., "exposure subject-only, LUT full")
- Animated mask preview (pulsing edge)
- Mask export as alpha channel
- Sky / object-class masks (Vision has separate APIs)

None of these are foreclosed by the v1 design — `EditDocument` and the masked pipeline can be extended additively.

## Testing

### Pure pipeline tests

- Golden-image diffs of masked composite for two source images × three feather values × {no exclusion, one excluded instance}.
- Round-trip: masked render with `mask.feather = 0` and `subjectStack == backgroundStack` matches unmasked render of the same stack within ε.
- Crop pinning: render with `backgroundStack.crop` mutated diverges from `subjectStack.crop` is impossible (view-model invariant test).

### Mask store tests

- Cache hit / miss for same `assetID` and same pixels.
- Hash invalidation when source pixels change.
- 0-instance result surfaces correctly.
- Concurrent `mask(for:)` calls for the same asset coalesce into a single Vision request.

### View model tests

- Sub-segment writes:
  - Subject → only `subjectStack` mutated.
  - Background → only `backgroundStack` mutated.
  - Full → both mutated identically.
- Crop mirror invariant: any crop write through any sub-segment ends up in `subjectStack.crop`, and `backgroundStack.crop == subjectStack.crop` holds after every action.
- v1 → v2 migration on legacy persisted JSON.

### Manual / device tests

- 0-instance photo (e.g., empty landscape) — mask icon disabled, toast appears once.
- Many-instance photo (group of 6 people) — instance picker usable, exclude works.
- Large mask edit + export — verify ~12ms render budget holds on real device.
- Mask + crop + rotate combo — pixels stay aligned after cropping a rotated, masked composite.

## Open Questions

None at design time. All major forks decided during brainstorming.

## References

- `VNGenerateForegroundInstanceMaskRequest` — Apple docs (iOS 17+)
- Existing pipeline: `PipelineBuilder.swift`
- Existing data model: `AdjustmentStack.swift`
- Render scheduling: `RenderEngine.swift` (30ms debounce, `@MainActor` model)
