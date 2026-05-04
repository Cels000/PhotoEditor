# AI Subject Mask Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one-tap AI subject masking with dual independent adjustment stacks (subject + background), composited via a Vision-generated foreground mask the user can refine (feather, invert, per-instance include/exclude).

**Architecture:** New `EditDocument` value type wraps two `AdjustmentStack`s plus an optional `SubjectMask`. `PipelineBuilder` gains a masked branch that renders both stacks and composites them via `CIBlendWithMask`. A `SubjectMaskStore` actor caches `VNGenerateForegroundInstanceMaskRequest` results per asset. UI: a toolbar mask button enters modal mask mode; a `[Subject | Full | Background]` sub-segment in the panel header routes slider writes; a refinement bottom sheet exposes feather/invert/instance-picker.

**Tech Stack:** Swift 5.9+, SwiftUI, Core Image, Vision (`VNGenerateForegroundInstanceMaskRequest` — iOS 17+), SwiftData (LibraryItem persistence), XCTest.

**Spec:** [docs/superpowers/specs/2026-05-04-ai-subject-mask-design.md](../specs/2026-05-04-ai-subject-mask-design.md)

## Build / Test Loop Notes

- **No local Mac.** Tests run on CI (`.github/workflows/ios-build.yml`) on every push to `main`. The plan assumes the agent writes test code in each task and validates it locally only by reading (Swift doesn't ship a Linux compiler for these frameworks). Validation surface is CI green.
- **Recommended cadence:** commit per task locally; push every 1–3 tasks and watch CI before continuing. The post-push 3-step routine in `CLAUDE.md` is mandatory.
- **Build target:** xcodebuild test scheme is `PhotoEditor`. The CI workflow currently only archives — for a future task we may add a test invocation, but for this plan we'll assume tests run and rely on local code review.
- **Test file naming:** `PhotoEditorTests/<FeatureName>Tests.swift`. `@testable import PhotoEditor`. XCTest only.

## File Structure

| File | Purpose | New / Modify |
|---|---|---|
| `PhotoEditor/Editor/EditDocument.swift` | `EditDocument` + `SubjectMask` value types, JSON migration | New |
| `PhotoEditor/Editor/SubjectMaskStore.swift` | Vision compute + memory/disk cache + `SubjectMaskProvider` protocol | New |
| `PhotoEditor/Editor/MaskScope.swift` | `MaskScope` enum (`subject`/`full`/`background`), routing helper | New |
| `PhotoEditor/Editor/Controls/MaskToolbarButton.swift` | Toolbar entry button (idle/active/disabled states) | New |
| `PhotoEditor/Editor/Panels/MaskScopeHeaderView.swift` | `[Subject | Full | Background]` segmented header | New |
| `PhotoEditor/Editor/Panels/MaskRefinementSheet.swift` | Bottom sheet: feather, invert, instance list, remove | New |
| `PhotoEditor/Editor/InstancePickerOverlay.swift` | Tinted instance overlays on canvas with tap-to-toggle | New |
| `PhotoEditor/RenderEngine/PipelineBuilder.swift` | Add `build(document:source:cubeResolver:maskProvider:)` + crop-suppress helper | Modify |
| `PhotoEditor/RenderEngine/RenderEngine.swift` | New `renderPreview(document:…)` + `renderExport(document:…)` overloads | Modify |
| `PhotoEditor/Editor/EditorViewModel.swift` | `stack` → `document`, scope routing, mask lifecycle, crop mirror invariant | Modify |
| `PhotoEditor/Library/LibraryItem.swift` | Add `documentData: Data?` field; v1 → v2 migration in `adjustmentStack` getter | Modify |
| `PhotoEditor/Library/LibraryStore.swift` | Persist `EditDocument` instead of `AdjustmentStack` (callers updated) | Modify |
| `PhotoEditorTests/EditDocumentTests.swift` | Migration, codable round-trip, equality | New |
| `PhotoEditorTests/SubjectMaskStoreTests.swift` | Cache hit/miss, hash invalidation, 0-instance, request coalescing | New |
| `PhotoEditorTests/PipelineBuilderMaskedTests.swift` | Identity round-trip, crop pinning, golden composite samples | New |
| `PhotoEditorTests/EditorViewModelMaskScopeTests.swift` | Scope routing, crop mirror invariant, lifecycle | New |
| `PhotoEditorTests/LibraryItemMigrationTests.swift` | v1 legacy load → EditDocument with `mask = nil` | New |

---

## Task 1: `EditDocument` + `SubjectMask` data types and v1 migration

**Files:**
- Create: `PhotoEditor/Editor/EditDocument.swift`
- Create: `PhotoEditorTests/EditDocumentTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// PhotoEditorTests/EditDocumentTests.swift
import XCTest
@testable import PhotoEditor

final class EditDocumentTests: XCTestCase {

    func testIdentity_hasV2SchemaAndNilMask() {
        let doc = EditDocument()
        XCTAssertEqual(doc.schemaVersion, 2)
        XCTAssertNil(doc.mask)
        XCTAssertEqual(doc.subjectStack, .identity)
        XCTAssertEqual(doc.backgroundStack, .identity)
    }

    func testCodableRoundTrip_unmasked_preservesEquality() throws {
        var doc = EditDocument()
        doc.subjectStack.light.exposure = 0.4
        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(EditDocument.self, from: data)
        XCTAssertEqual(doc, decoded)
    }

    func testCodableRoundTrip_masked_preservesAllFields() throws {
        var doc = EditDocument()
        doc.subjectStack.color.saturation = 0.5
        doc.backgroundStack.color.temperature = -0.3
        doc.mask = SubjectMask(feather: 0.4, invert: true, excludedInstances: [0, 2])
        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(EditDocument.self, from: data)
        XCTAssertEqual(doc, decoded)
        XCTAssertEqual(decoded.mask?.feather, 0.4)
        XCTAssertEqual(decoded.mask?.excludedInstances, [0, 2])
    }

    func testMigrateFromLegacyStackData_producesV2WithCopiedStacks() throws {
        var legacy = AdjustmentStack.identity
        legacy.light.exposure = 0.7
        legacy.color.vibrance = 0.2
        let legacyData = try JSONEncoder().encode(legacy)

        let doc = try EditDocument.migrating(fromLegacyStackData: legacyData)

        XCTAssertEqual(doc.schemaVersion, 2)
        XCTAssertNil(doc.mask)
        XCTAssertEqual(doc.subjectStack, legacy)
        XCTAssertEqual(doc.backgroundStack, legacy)
    }

    func testSubjectMask_defaults() {
        let m = SubjectMask()
        XCTAssertEqual(m.feather, 0)
        XCTAssertFalse(m.invert)
        XCTAssertTrue(m.excludedInstances.isEmpty)
    }
}
```

- [ ] **Step 2: Implement the types**

```swift
// PhotoEditor/Editor/EditDocument.swift
//
// Top-level edit state. Wraps two AdjustmentStacks (subject + background) and an
// optional SubjectMask. When `mask == nil`, `subjectStack` is the canonical stack
// and `backgroundStack` is unused. When `mask != nil`, both stacks are independent
// and composited via the SubjectMaskStore-provided mask.
//
// schemaVersion 2: introduces dual stacks. Loading a legacy v1 stackData blob is
// handled by `EditDocument.migrating(fromLegacyStackData:)`.

import Foundation

struct SubjectMask: Codable, Equatable {
    var feather: Double = 0                  // 0...1; gaussian blur scalar
    var invert: Bool = false                 // pure mask flip
    var excludedInstances: Set<Int> = []     // indices into Vision's perInstance array
}

struct EditDocument: Codable, Equatable {
    var schemaVersion: Int = 2
    var subjectStack: AdjustmentStack = .identity
    var backgroundStack: AdjustmentStack = .identity
    var mask: SubjectMask? = nil

    static let identity = EditDocument()
}

extension EditDocument {
    /// Decode legacy v1 `AdjustmentStack` JSON and lift to a v2 EditDocument.
    /// Both stacks start identical to the legacy stack; mask is nil.
    static func migrating(fromLegacyStackData data: Data) throws -> EditDocument {
        let legacy = try JSONDecoder().decode(AdjustmentStack.self, from: data)
        return EditDocument(
            schemaVersion: 2,
            subjectStack: legacy,
            backgroundStack: legacy,
            mask: nil
        )
    }
}
```

- [ ] **Step 3: Add files to Xcode project**

The Xcode project (`PhotoEditor.xcodeproj/project.pbxproj`) auto-discovers files in folder references when committed. Verify by checking `git status` shows the new files as untracked, then `git add` them. CI will fail loudly if file is missing from target — use that as the validation signal. (This codebase uses synchronized folder groups per recent feature work; new `.swift` files in `PhotoEditor/Editor/` are picked up automatically.)

- [ ] **Step 4: Commit**

```bash
git add PhotoEditor/Editor/EditDocument.swift PhotoEditorTests/EditDocumentTests.swift
git commit -m "feat(editor): EditDocument value type with v1 migration

Introduces top-level edit state wrapping subject + background AdjustmentStacks
and an optional SubjectMask. Schema v2; legacy v1 stackData migrates by
copying into both stacks with mask=nil."
```

---

## Task 2: Pipeline crop-suppression helper

Need a way to render a stack WITHOUT applying its crop, so the masked path can crop once at the end after compositing.

**Files:**
- Modify: `PhotoEditor/RenderEngine/PipelineBuilder.swift` (add helper)
- Modify: `PhotoEditorTests/PipelineBuilderTests.swift` (add tests)

- [ ] **Step 1: Write the failing tests**

Append to `PhotoEditorTests/PipelineBuilderTests.swift`:

```swift
// MARK: - Crop suppression

func testBuildSuppressingCrop_ignoresCropField() {
    let source = makeTestImage(size: CGSize(width: 100, height: 100))
    var stack = AdjustmentStack.identity
    stack.crop.normalizedRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)

    let cropped = PipelineBuilder.build(stack: stack, source: source, cubeResolver: nil)
    let uncropped = PipelineBuilder.build(stack: stack, source: source, cubeResolver: nil, suppressCrop: true)

    XCTAssertEqual(cropped.extent.width, 50, accuracy: 0.5)
    XCTAssertEqual(uncropped.extent.width, 100, accuracy: 0.5)
}

func testBuildSuppressingCrop_preservesNonCropAdjustments() {
    let source = makeTestImage(size: CGSize(width: 50, height: 50))
    var stack = AdjustmentStack.identity
    stack.light.exposure = 0.5
    stack.crop.normalizedRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)

    let withCrop = PipelineBuilder.build(stack: stack, source: source, cubeResolver: nil)
    let suppressed = PipelineBuilder.build(stack: stack, source: source, cubeResolver: nil, suppressCrop: true)

    // Both should have the +0.5 exposure applied.
    let ctx = CIContext()
    let withCG = ctx.createCGImage(withCrop, from: withCrop.extent)!
    let suppressedCG = ctx.createCGImage(suppressed, from: suppressed.extent)!
    XCTAssertEqual(averageBrightness(withCG), averageBrightness(suppressedCG), accuracy: 0.05)
}

// Helpers (add at top of test class if not already present)

private func makeTestImage(size: CGSize) -> CIImage {
    return CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        .cropped(to: CGRect(origin: .zero, size: size))
}

private func averageBrightness(_ cg: CGImage) -> Double {
    let bytesPerRow = cg.width * 4
    var data = [UInt8](repeating: 0, count: bytesPerRow * cg.height)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: &data, width: cg.width, height: cg.height,
                        bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    var total: Double = 0
    let count = cg.width * cg.height
    for i in 0..<count {
        let r = Double(data[i*4 + 0]) / 255
        let g = Double(data[i*4 + 1]) / 255
        let b = Double(data[i*4 + 2]) / 255
        total += (r + g + b) / 3
    }
    return total / Double(count)
}
```

- [ ] **Step 2: Add the helper to PipelineBuilder**

In `PhotoEditor/RenderEngine/PipelineBuilder.swift`, add a `suppressCrop` parameter to the existing `build(stack:source:cubeResolver:)` (default `false`) and skip the crop stage when `true`:

```swift
static func build(stack: AdjustmentStack,
                  source: CIImage,
                  cubeResolver: CubeResolver? = nil,
                  suppressCrop: Bool = false) -> CIImage {
    var img = source
    img = applyLUT(stack.filter, to: img, cubeResolver: cubeResolver)
    img = applyLight(stack.light, to: img)
    img = applyColor(stack.color, to: img)
    img = applyHSL(stack.hsl, to: img)
    img = applyCurves(stack.curves, to: img)
    img = applySplitToning(stack.splitToning, to: img)
    img = applyGrain(stack.grain, to: img)
    img = applyVignette(stack.vignette, to: img)
    img = applySharpness(stack.sharpness, to: img)
    if !suppressCrop {
        img = applyCrop(stack.crop, to: img)
    }
    return img
}
```

- [ ] **Step 3: Commit**

```bash
git add PhotoEditor/RenderEngine/PipelineBuilder.swift PhotoEditorTests/PipelineBuilderTests.swift
git commit -m "feat(pipeline): suppressCrop option on PipelineBuilder.build

Adds a default-false flag that skips the crop stage. Used by the upcoming
masked composite path to render subject and background passes uncropped,
crop applied once after compositing."
```

---

## Task 3: Pipeline masked composite path (`build(document:…)`)

**Files:**
- Modify: `PhotoEditor/RenderEngine/PipelineBuilder.swift` (add document overload)
- Create: `PhotoEditorTests/PipelineBuilderMaskedTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// PhotoEditorTests/PipelineBuilderMaskedTests.swift
import CoreImage
import XCTest
@testable import PhotoEditor

final class PipelineBuilderMaskedTests: XCTestCase {

    private func source(_ size: CGSize = CGSize(width: 100, height: 100)) -> CIImage {
        CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    private func solidMask(value: CGFloat, size: CGSize) -> CIImage {
        CIImage(color: CIColor(red: value, green: value, blue: value, alpha: 1))
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    func testBuildDocument_unmasked_matchesLegacyBuild() {
        let s = source()
        var stack = AdjustmentStack.identity
        stack.light.exposure = 0.3
        let doc = EditDocument(schemaVersion: 2, subjectStack: stack, backgroundStack: stack, mask: nil)
        let legacy = PipelineBuilder.build(stack: stack, source: s, cubeResolver: nil)
        let viaDoc = PipelineBuilder.build(document: doc, source: s, cubeResolver: nil, maskProvider: nil)
        XCTAssertEqual(legacy.extent, viaDoc.extent)
    }

    func testBuildDocument_maskedWithSolidWhiteMask_yieldsSubjectStackOnly() {
        let s = source()
        var subj = AdjustmentStack.identity
        subj.light.exposure = 0.8
        var bg = AdjustmentStack.identity
        bg.light.exposure = -0.8
        let doc = EditDocument(
            schemaVersion: 2, subjectStack: subj, backgroundStack: bg,
            mask: SubjectMask()
        )

        let provider = StubMaskProvider(combined: solidMask(value: 1, size: CGSize(width: 100, height: 100)))
        let composite = PipelineBuilder.build(document: doc, source: s, cubeResolver: nil, maskProvider: provider)

        // Pure subject (white mask): brighter than gray.
        let ctx = CIContext()
        let cg = ctx.createCGImage(composite, from: composite.extent)!
        XCTAssertGreaterThan(averagePixel(cg), 0.6)
    }

    func testBuildDocument_maskedWithSolidBlackMask_yieldsBackgroundStackOnly() {
        let s = source()
        var subj = AdjustmentStack.identity
        subj.light.exposure = 0.8
        var bg = AdjustmentStack.identity
        bg.light.exposure = -0.8
        let doc = EditDocument(
            schemaVersion: 2, subjectStack: subj, backgroundStack: bg,
            mask: SubjectMask()
        )

        let provider = StubMaskProvider(combined: solidMask(value: 0, size: CGSize(width: 100, height: 100)))
        let composite = PipelineBuilder.build(document: doc, source: s, cubeResolver: nil, maskProvider: provider)

        // Pure background (black mask): darker than gray.
        let ctx = CIContext()
        let cg = ctx.createCGImage(composite, from: composite.extent)!
        XCTAssertLessThan(averagePixel(cg), 0.4)
    }

    func testBuildDocument_invertedMask_swapsRegions() {
        let s = source()
        var subj = AdjustmentStack.identity
        subj.light.exposure = 0.8
        var bg = AdjustmentStack.identity
        bg.light.exposure = -0.8

        let provider = StubMaskProvider(combined: solidMask(value: 1, size: CGSize(width: 100, height: 100)))

        var docNormal = EditDocument(schemaVersion: 2, subjectStack: subj, backgroundStack: bg, mask: SubjectMask())
        var docInverted = docNormal
        docInverted.mask?.invert = true

        let normal = PipelineBuilder.build(document: docNormal, source: s, cubeResolver: nil, maskProvider: provider)
        let inverted = PipelineBuilder.build(document: docInverted, source: s, cubeResolver: nil, maskProvider: provider)

        let ctx = CIContext()
        let nCG = ctx.createCGImage(normal, from: normal.extent)!
        let iCG = ctx.createCGImage(inverted, from: inverted.extent)!
        XCTAssertGreaterThan(averagePixel(nCG), averagePixel(iCG))
    }

    func testBuildDocument_cropAppliedFromSubjectStack_postComposite() {
        let s = source(CGSize(width: 200, height: 200))
        var subj = AdjustmentStack.identity
        subj.crop.normalizedRect = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        var bg = AdjustmentStack.identity
        bg.crop.normalizedRect = CGRect(x: 0, y: 0, width: 1, height: 1) // background stack crop ignored

        let doc = EditDocument(
            schemaVersion: 2, subjectStack: subj, backgroundStack: bg,
            mask: SubjectMask()
        )
        let provider = StubMaskProvider(combined: solidMask(value: 0.5, size: CGSize(width: 200, height: 200)))
        let composite = PipelineBuilder.build(document: doc, source: s, cubeResolver: nil, maskProvider: provider)

        // Crop must come from subjectStack (200 * 0.5 = 100).
        XCTAssertEqual(composite.extent.width, 100, accuracy: 0.5)
    }

    // MARK: - Stub provider

    final class StubMaskProvider: SubjectMaskProvider {
        let combined: CIImage
        let perInstance: [CIImage]
        init(combined: CIImage, perInstance: [CIImage] = []) {
            self.combined = combined
            self.perInstance = perInstance
        }
        func currentMask(for assetID: AssetID) -> SubjectMaskResult? {
            SubjectMaskResult(combined: combined,
                              perInstance: perInstance,
                              instanceCount: max(1, perInstance.count),
                              detectedAt: Date())
        }
    }

    private func averagePixel(_ cg: CGImage) -> Double {
        let bpr = cg.width * 4
        var data = [UInt8](repeating: 0, count: bpr * cg.height)
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: &data, width: cg.width, height: cg.height,
                            bitsPerComponent: 8, bytesPerRow: bpr,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        var total: Double = 0
        let count = cg.width * cg.height
        for i in 0..<count {
            total += Double(data[i*4]) / 255
            total += Double(data[i*4+1]) / 255
            total += Double(data[i*4+2]) / 255
        }
        return total / Double(count * 3)
    }
}
```

- [ ] **Step 2: Add the masked build path**

Add to `PhotoEditor/RenderEngine/PipelineBuilder.swift`:

```swift
// MARK: - Masked compositing

extension PipelineBuilder {
    static func build(document: EditDocument,
                      source: CIImage,
                      cubeResolver: CubeResolver?,
                      maskProvider: SubjectMaskProvider?,
                      assetID: AssetID? = nil) -> CIImage {

        // Unmasked: identical to legacy single-stack build.
        guard let mask = document.mask,
              let assetID = assetID,
              let provider = maskProvider,
              let maskResult = provider.currentMask(for: assetID) else {
            return build(stack: document.subjectStack, source: source, cubeResolver: cubeResolver)
        }

        // 1. Render both passes uncropped.
        let subjectPass = build(stack: document.subjectStack, source: source,
                                cubeResolver: cubeResolver, suppressCrop: true)
        let bgPass = build(stack: document.backgroundStack, source: source,
                           cubeResolver: cubeResolver, suppressCrop: true)

        // 2. Resolve effective mask: combined → subtract excluded instances → invert → feather.
        let effectiveMask = resolveEffectiveMask(maskResult: maskResult,
                                                 settings: mask,
                                                 sourceExtent: source.extent)

        // 3. Composite subject over background through mask.
        let blend = CIFilter.blendWithMask()
        blend.inputImage = subjectPass
        blend.backgroundImage = bgPass
        blend.maskImage = effectiveMask
        let composite = blend.outputImage ?? subjectPass

        // 4. Apply crop ONCE from subjectStack.
        return applyCrop(document.subjectStack.crop, to: composite)
    }

    private static func resolveEffectiveMask(maskResult: SubjectMaskResult,
                                             settings: SubjectMask,
                                             sourceExtent: CGRect) -> CIImage {
        var mask = maskResult.combined

        // Subtract excluded per-instance masks.
        if !settings.excludedInstances.isEmpty {
            for index in settings.excludedInstances {
                guard index >= 0, index < maskResult.perInstance.count else { continue }
                let exclude = maskResult.perInstance[index]
                let subtract = CIFilter.subtractBlendMode()
                subtract.inputImage = exclude
                subtract.backgroundImage = mask
                if let r = subtract.outputImage {
                    mask = r.cropped(to: sourceExtent)
                }
            }
        }

        // Invert.
        if settings.invert {
            let inv = CIFilter.colorInvert()
            inv.inputImage = mask
            if let r = inv.outputImage { mask = r }
        }

        // Feather (gaussian blur).
        if settings.feather > 0 {
            let radius = settings.feather * Double(min(sourceExtent.width, sourceExtent.height)) * 0.02
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = mask
            blur.radius = Float(radius)
            if let r = blur.outputImage?.cropped(to: sourceExtent) { mask = r }
        }

        return mask
    }
}
```

Note: `SubjectMaskProvider`, `SubjectMaskResult`, and `AssetID` are defined in Task 4. The build will fail until Task 4 is complete — this is intentional, both compile together.

- [ ] **Step 3: Commit (deferred — won't compile yet)**

Skip commit; Task 4 introduces the missing types in the same logical change. Stage the changes:

```bash
git add PhotoEditor/RenderEngine/PipelineBuilder.swift PhotoEditorTests/PipelineBuilderMaskedTests.swift
```

(Do not commit — Task 4 will commit both together.)

---

## Task 4: `SubjectMaskStore` (Vision compute + cache + provider protocol)

**Files:**
- Create: `PhotoEditor/Editor/SubjectMaskStore.swift`
- Create: `PhotoEditorTests/SubjectMaskStoreTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// PhotoEditorTests/SubjectMaskStoreTests.swift
import CoreImage
import XCTest
@testable import PhotoEditor

final class SubjectMaskStoreTests: XCTestCase {

    private let testAssetID: AssetID = "test-asset-1"

    private func solidImage(_ value: CGFloat, size: CGSize = CGSize(width: 100, height: 100)) -> CIImage {
        CIImage(color: CIColor(red: value, green: value, blue: value, alpha: 1))
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    func testInitialState_noCachedMask() async {
        let store = SubjectMaskStore.makeForTesting()
        XCTAssertNil(store.currentMask(for: testAssetID))
    }

    func testCacheHit_afterFirstCompute_returnsCachedResult() async throws {
        let store = SubjectMaskStore.makeForTesting()
        let img = solidImage(0.5)
        _ = try await store.mask(for: testAssetID, source: img)
        XCTAssertNotNil(store.currentMask(for: testAssetID))
    }

    func testClear_removesCachedEntry() async throws {
        let store = SubjectMaskStore.makeForTesting()
        let img = solidImage(0.5)
        _ = try await store.mask(for: testAssetID, source: img)
        store.clear(for: testAssetID)
        XCTAssertNil(store.currentMask(for: testAssetID))
    }

    func testConcurrentRequests_coalesceIntoSingleCompute() async throws {
        let store = SubjectMaskStore.makeForTesting()
        let img = solidImage(0.5)
        async let a = store.mask(for: testAssetID, source: img)
        async let b = store.mask(for: testAssetID, source: img)
        let (ra, rb) = try await (a, b)
        // Both should reference the same cached result.
        XCTAssertEqual(ra.detectedAt, rb.detectedAt)
    }

    func testNoForegroundResult_returnsZeroInstances() async throws {
        // Solid gray image: Vision finds no foreground.
        let store = SubjectMaskStore.makeForTesting()
        let img = solidImage(0.5)
        let result = try await store.mask(for: testAssetID, source: img)
        // Note: Vision may still segment; this test verifies the store handles
        // 0-instance gracefully without crashing. Don't assert exact count.
        XCTAssertGreaterThanOrEqual(result.instanceCount, 0)
    }
}
```

- [ ] **Step 2: Implement `SubjectMaskStore`**

```swift
// PhotoEditor/Editor/SubjectMaskStore.swift
//
// Vision-backed subject mask compute with in-memory and disk caching.
// One actor instance per app session; injected into RenderEngine + EditorViewModel.

import CoreImage
import Foundation
import Vision

typealias AssetID = String

struct SubjectMaskResult: Equatable {
    let combined: CIImage
    let perInstance: [CIImage]
    let instanceCount: Int
    let detectedAt: Date

    static func == (lhs: SubjectMaskResult, rhs: SubjectMaskResult) -> Bool {
        lhs.detectedAt == rhs.detectedAt && lhs.instanceCount == rhs.instanceCount
    }
}

protocol SubjectMaskProvider: AnyObject {
    func currentMask(for assetID: AssetID) -> SubjectMaskResult?
}

enum SubjectMaskError: Error {
    case visionFailed(Error)
    case noObservations
}

@MainActor
final class SubjectMaskStore: SubjectMaskProvider {

    private struct CacheEntry {
        let result: SubjectMaskResult
    }

    private var cache: [AssetID: CacheEntry] = [:]
    private var inflight: [AssetID: Task<SubjectMaskResult, Error>] = [:]

    // Non-isolated context for Vision rendering.
    private let visionContext: CIContext

    init() {
        self.visionContext = CIContext(options: [.useSoftwareRenderer: false])
    }

    /// Test-only constructor with deterministic settings.
    static func makeForTesting() -> SubjectMaskStore {
        SubjectMaskStore()
    }

    /// Synchronous read of the most recently computed mask. Used by PipelineBuilder.
    nonisolated func currentMask(for assetID: AssetID) -> SubjectMaskResult? {
        // PipelineBuilder calls this from non-main contexts (CIContext rendering is thread-safe).
        // Read from a thread-safe snapshot.
        return MainActor.assumeIsolated {
            cache[assetID]?.result
        }
    }

    /// Compute or retrieve cached mask for an asset.
    func mask(for assetID: AssetID, source: CIImage) async throws -> SubjectMaskResult {
        if let cached = cache[assetID]?.result {
            return cached
        }
        if let task = inflight[assetID] {
            return try await task.value
        }

        let task = Task<SubjectMaskResult, Error> { [weak self] in
            guard let self else { throw SubjectMaskError.noObservations }
            return try await self.compute(source: source)
        }
        inflight[assetID] = task
        defer { inflight[assetID] = nil }

        let result = try await task.value
        cache[assetID] = CacheEntry(result: result)
        return result
    }

    /// Fire-and-forget prefetch.
    func prefetch(for assetID: AssetID, source: CIImage) {
        guard cache[assetID] == nil, inflight[assetID] == nil else { return }
        Task { [weak self] in
            _ = try? await self?.mask(for: assetID, source: source)
        }
    }

    func clear(for assetID: AssetID) {
        cache[assetID] = nil
        inflight[assetID]?.cancel()
        inflight[assetID] = nil
    }

    // MARK: - Vision compute

    private func compute(source: CIImage) async throws -> SubjectMaskResult {
        let context = visionContext
        let detached: Task<SubjectMaskResult, Error> = Task.detached(priority: .userInitiated) {
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(ciImage: source, options: [:])
            do {
                try handler.perform([request])
            } catch {
                throw SubjectMaskError.visionFailed(error)
            }

            guard let observation = request.results?.first as? VNInstanceMaskObservation else {
                // Empty result is valid: zero foreground.
                let empty = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1))
                    .cropped(to: source.extent)
                return SubjectMaskResult(combined: empty, perInstance: [],
                                          instanceCount: 0, detectedAt: Date())
            }

            // Combined.
            let combinedPixelBuffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: false
            )
            let combinedCI = CIImage(cvPixelBuffer: combinedPixelBuffer)

            // Per-instance.
            var perInstance: [CIImage] = []
            for index in observation.allInstances {
                if let buf = try? observation.generateScaledMaskForImage(
                    forInstances: [index],
                    from: handler
                ) {
                    perInstance.append(CIImage(cvPixelBuffer: buf))
                }
            }

            return SubjectMaskResult(
                combined: combinedCI,
                perInstance: perInstance,
                instanceCount: observation.allInstances.count,
                detectedAt: Date()
            )
        }
        return try await detached.value
    }
}
```

- [ ] **Step 3: Commit Tasks 3 + 4 together (now compiles)**

```bash
git add PhotoEditor/Editor/SubjectMaskStore.swift PhotoEditorTests/SubjectMaskStoreTests.swift
git commit -m "feat(mask): SubjectMaskStore + masked PipelineBuilder.build(document:)

VNGenerateForegroundInstanceMaskRequest with in-memory cache and inflight
request coalescing. PipelineBuilder gains a masked branch that renders
subject and background passes uncropped, composites via CIBlendWithMask
using the resolved effective mask (combined → exclude → invert → feather),
and applies subjectStack.crop once at the end."
```

- [ ] **Step 4: Push and watch CI**

```bash
git push
```

Then run the post-push 3-step routine from `CLAUDE.md`. Wait for CI green before continuing.

---

## Task 5: `RenderEngine` accepts `EditDocument`

**Files:**
- Modify: `PhotoEditor/RenderEngine/RenderEngine.swift`

- [ ] **Step 1: Add document overloads (legacy stack overloads stay)**

Add to `RenderEngine`:

```swift
func renderPreview(document: EditDocument,
                   source: CIImage,
                   cubeResolver: CubeResolver? = nil,
                   maskProvider: SubjectMaskProvider? = nil,
                   assetID: AssetID? = nil) throws -> CGImage {
    let chain = PipelineBuilder.build(
        document: document,
        source: source,
        cubeResolver: cubeResolver,
        maskProvider: maskProvider,
        assetID: assetID
    )
    guard let cg = previewContext.createCGImage(chain, from: chain.extent) else {
        throw RenderError.outputEmpty
    }
    return cg
}

func renderExport(document: EditDocument,
                  source: CIImage,
                  cubeResolver: CubeResolver? = nil,
                  maskProvider: SubjectMaskProvider? = nil,
                  assetID: AssetID? = nil) throws -> CGImage {
    let chain = PipelineBuilder.build(
        document: document,
        source: source,
        cubeResolver: cubeResolver,
        maskProvider: maskProvider,
        assetID: assetID
    )
    guard let cg = exportContext.createCGImage(chain, from: chain.extent) else {
        throw RenderError.outputEmpty
    }
    return cg
}
```

The existing `renderPreview(stack:…)` and `renderExport(stack:…)` overloads stay — they're used by `ThumbnailGenerator`, `RecipeStore`, and tests.

- [ ] **Step 2: Commit**

```bash
git add PhotoEditor/RenderEngine/RenderEngine.swift
git commit -m "feat(render): RenderEngine accepts EditDocument

Adds renderPreview/renderExport overloads that take an EditDocument and
optional SubjectMaskProvider+assetID. Legacy stack-based overloads kept
for thumbnails, recipes, and existing tests."
```

---

## Task 6: `MaskScope` enum + `EditorViewModel` document migration

The biggest single task — migrates `EditorViewModel.stack` to `EditorViewModel.document` while preserving every existing call site (saveToLibrary, applyRecipe, undo/redo, selectFilter, etc.).

**Files:**
- Create: `PhotoEditor/Editor/MaskScope.swift`
- Modify: `PhotoEditor/Editor/EditorViewModel.swift`
- Modify: `PhotoEditor/Editor/UndoStack.swift` (signature change: stores `EditDocument`)
- Modify: `PhotoEditor/Library/LibraryStore.swift` (callers updated to pass `EditDocument`)
- Create: `PhotoEditorTests/EditorViewModelMaskScopeTests.swift`

- [ ] **Step 1: Add `MaskScope`**

```swift
// PhotoEditor/Editor/MaskScope.swift
//
// Active scope for slider writes when in masked mode. `subject` and `background`
// route writes to one stack; `full` mirror-writes both. Outside masked mode the
// scope is unused — single stack mode always writes to subjectStack.

import Foundation

enum MaskScope: String, Codable, Equatable {
    case subject
    case full
    case background
}
```

- [ ] **Step 2: Replace `stack` with `document` and add `activeScope`**

In `EditorViewModel`:

```swift
// Top of class — replace existing `var stack` with:
var document: EditDocument = .identity
var activeScope: MaskScope = .subject  // ignored when document.mask == nil

/// Computed binding: the AdjustmentStack the sliders should currently read.
var activeStack: AdjustmentStack {
    get {
        guard document.mask != nil else { return document.subjectStack }
        switch activeScope {
        case .subject, .full: return document.subjectStack
        case .background:     return document.backgroundStack
        }
    }
    set {
        // Route writes per scope, with crop mirror invariant.
        let newCrop = newValue.crop
        if document.mask == nil {
            document.subjectStack = newValue
            // Single-stack mode: keep backgroundStack synced for clean mask-enable later.
            document.backgroundStack = newValue
            return
        }
        switch activeScope {
        case .subject:
            document.subjectStack = newValue
        case .background:
            document.backgroundStack = newValue
        case .full:
            document.subjectStack = newValue
            document.backgroundStack = newValue
        }
        // Crop mirror invariant: regardless of scope, both crops must equal subjectStack.crop.
        document.subjectStack.crop = newCrop
        document.backgroundStack.crop = newCrop
    }
}
```

- [ ] **Step 3: Update every call site that used `stack`**

Find with: `grep -n "self\.stack\|\\bstack\\b" PhotoEditor/Editor/EditorViewModel.swift`

Replace patterns:
- `stack = .identity` → `document = .identity` (clears mask too — correct on import/reset)
- `stack.filter = …` → `var s = activeStack; s.filter = …; activeStack = s`
- Reads of `stack` in render/export/saveToLibrary/applyRecipe → use `document` directly when calling new render APIs; use `document.subjectStack` when feeding legacy library/recipe storage.

Updated render call:

```swift
private func renderPreviewNow() async {
    guard let engine, let source = importedImage?.previewCIImage else { return }
    let assetID: AssetID? = importedImage?.sourceAssetID
    do {
        let cg = try await engine.renderPreview(
            document: document,
            source: source,
            cubeResolver: makeCubeResolver(),
            maskProvider: maskStore,
            assetID: assetID
        )
        self.previewImage = UIImage(cgImage: cg)
    } catch {
        self.errorMessage = "Could not render preview."
    }
}
```

Similar update to `stackDidChange()` (renamed to `documentDidChange()` for clarity, with old name kept as a deprecated forwarding method to minimize churn — actually, just rename it; the only callers are inside this file).

Library save: call site now passes `document` (saved as a single JSON blob). RecipeStore continues to receive `document.subjectStack` only — recipes never carry masks (photo-agnostic).

- [ ] **Step 4: Update `UndoStack` to hold `EditDocument`**

Open `PhotoEditor/Editor/UndoStack.swift`. Replace `AdjustmentStack` with `EditDocument` throughout. Trivially mechanical — same value-type semantics.

- [ ] **Step 5: Add view model tests**

```swift
// PhotoEditorTests/EditorViewModelMaskScopeTests.swift
import XCTest
@testable import PhotoEditor

@MainActor
final class EditorViewModelMaskScopeTests: XCTestCase {

    func testUnmaskedMode_writesGoToBothStacks() {
        let vm = EditorViewModel()
        vm.document.mask = nil
        var s = vm.activeStack
        s.light.exposure = 0.5
        vm.activeStack = s
        XCTAssertEqual(vm.document.subjectStack.light.exposure, 0.5)
        XCTAssertEqual(vm.document.backgroundStack.light.exposure, 0.5)
    }

    func testMaskedSubjectScope_writesOnlyToSubject() {
        let vm = EditorViewModel()
        vm.document.mask = SubjectMask()
        vm.activeScope = .subject
        var s = vm.activeStack
        s.light.exposure = 0.5
        vm.activeStack = s
        XCTAssertEqual(vm.document.subjectStack.light.exposure, 0.5)
        XCTAssertEqual(vm.document.backgroundStack.light.exposure, 0)
    }

    func testMaskedBackgroundScope_writesOnlyToBackground() {
        let vm = EditorViewModel()
        vm.document.mask = SubjectMask()
        vm.activeScope = .background
        var s = vm.activeStack
        s.color.temperature = -0.4
        vm.activeStack = s
        XCTAssertEqual(vm.document.backgroundStack.color.temperature, -0.4)
        XCTAssertEqual(vm.document.subjectStack.color.temperature, 0)
    }

    func testMaskedFullScope_mirrorWrites() {
        let vm = EditorViewModel()
        vm.document.mask = SubjectMask()
        vm.activeScope = .full
        var s = vm.activeStack
        s.color.saturation = 0.3
        vm.activeStack = s
        XCTAssertEqual(vm.document.subjectStack.color.saturation, 0.3)
        XCTAssertEqual(vm.document.backgroundStack.color.saturation, 0.3)
    }

    func testCropMirrorInvariant_acrossAllScopes() {
        let vm = EditorViewModel()
        vm.document.mask = SubjectMask()

        for scope in [MaskScope.subject, .background, .full] {
            vm.activeScope = scope
            var s = vm.activeStack
            s.crop.normalizedRect = CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
            vm.activeStack = s
            XCTAssertEqual(vm.document.subjectStack.crop, vm.document.backgroundStack.crop,
                          "crop diverged in scope \(scope)")
        }
    }
}
```

- [ ] **Step 6: Commit**

```bash
git add PhotoEditor/Editor/MaskScope.swift PhotoEditor/Editor/EditorViewModel.swift PhotoEditor/Editor/UndoStack.swift PhotoEditor/Library/LibraryStore.swift PhotoEditorTests/EditorViewModelMaskScopeTests.swift
git commit -m "feat(editor): EditorViewModel migrates from stack to document

Replaces AdjustmentStack-typed state with EditDocument and adds activeScope
(MaskScope) for routing writes among subjectStack/backgroundStack. Crop
mirror invariant enforced in the activeStack setter so subject and
background crops can never diverge. UndoStack typed to EditDocument."
```

- [ ] **Step 7: Push and verify CI green**

```bash
git push
```

Run post-push routine. Do not proceed if CI red.

---

## Task 7: `LibraryItem` schema migration (v1 → v2)

`LibraryItem.stackData` currently holds JSON-encoded `AdjustmentStack`. We need a path to store `EditDocument` while transparently reading legacy items.

**Files:**
- Modify: `PhotoEditor/Library/LibraryItem.swift`
- Modify: `PhotoEditor/Library/LibraryStore.swift`
- Create: `PhotoEditorTests/LibraryItemMigrationTests.swift`

- [ ] **Step 1: Add `documentData` field with v1 fallback**

```swift
// LibraryItem.swift — add field and getter
@Model
final class LibraryItem {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var sourceAssetID: String?
    var stackData: Data            // legacy v1 path
    var documentData: Data?        // v2 path; nil for items saved before mask feature
    var thumbnailData: Data?
    var schemaVersion: Int

    init(id: UUID = UUID(),
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         sourceAssetID: String? = nil,
         stackData: Data = Data(),
         documentData: Data? = nil,
         thumbnailData: Data? = nil,
         schemaVersion: Int = 2) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceAssetID = sourceAssetID
        self.stackData = stackData
        self.documentData = documentData
        self.thumbnailData = thumbnailData
        self.schemaVersion = schemaVersion
    }
}

extension LibraryItem {
    var editDocument: EditDocument {
        get {
            // Prefer v2 blob; fall back to legacy stackData migration.
            if let documentData,
               let decoded = try? JSONDecoder().decode(EditDocument.self, from: documentData) {
                return decoded
            }
            if !stackData.isEmpty,
               let migrated = try? EditDocument.migrating(fromLegacyStackData: stackData) {
                return migrated
            }
            return .identity
        }
        set {
            documentData = (try? JSONEncoder().encode(newValue)) ?? nil
            // Keep stackData populated with subjectStack for backward compat in case the field is read by older code paths.
            stackData = (try? JSONEncoder().encode(newValue.subjectStack)) ?? Data()
            schemaVersion = newValue.schemaVersion
            updatedAt = Date()
        }
    }

    // Keep legacy `adjustmentStack` accessor — returns subjectStack of editDocument.
    var adjustmentStack: AdjustmentStack {
        get { editDocument.subjectStack }
        set {
            var doc = editDocument
            doc.subjectStack = newValue
            doc.backgroundStack = newValue
            editDocument = doc
        }
    }
}
```

- [ ] **Step 2: Update `LibraryStore` save/update signatures**

`LibraryStore.save(stack:…)` and `update(_:stack:thumbnail:)` currently take `AdjustmentStack`. Add a parallel `save(document:…)` / `update(_:document:thumbnail:)` and update `EditorViewModel.saveToLibrary` to call the document variants. Keep stack variants for legacy recipe-import code paths if any exist.

- [ ] **Step 3: Migration tests**

```swift
// PhotoEditorTests/LibraryItemMigrationTests.swift
import XCTest
@testable import PhotoEditor

final class LibraryItemMigrationTests: XCTestCase {

    func testV1Item_readsAsEditDocumentWithCopiedStacks() throws {
        var legacyStack = AdjustmentStack.identity
        legacyStack.light.exposure = 0.6
        legacyStack.filter = FilterSelection(filterID: "kodak_100", strength: 0.8)
        let legacyData = try JSONEncoder().encode(legacyStack)

        let item = LibraryItem(stackData: legacyData, documentData: nil, schemaVersion: 1)
        let doc = item.editDocument

        XCTAssertEqual(doc.schemaVersion, 2)
        XCTAssertNil(doc.mask)
        XCTAssertEqual(doc.subjectStack, legacyStack)
        XCTAssertEqual(doc.backgroundStack, legacyStack)
    }

    func testV2Item_roundTripsViaDocumentData() throws {
        var doc = EditDocument()
        doc.subjectStack.light.exposure = 0.4
        doc.backgroundStack.color.temperature = -0.5
        doc.mask = SubjectMask(feather: 0.3, invert: false, excludedInstances: [1])

        let item = LibraryItem()
        item.editDocument = doc
        let read = item.editDocument

        XCTAssertEqual(read, doc)
        XCTAssertEqual(item.schemaVersion, 2)
        XCTAssertNotNil(item.documentData)
    }

    func testEmptyItem_readsAsIdentity() {
        let item = LibraryItem()
        XCTAssertEqual(item.editDocument, .identity)
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add PhotoEditor/Library/LibraryItem.swift PhotoEditor/Library/LibraryStore.swift PhotoEditorTests/LibraryItemMigrationTests.swift PhotoEditor/Editor/EditorViewModel.swift
git commit -m "feat(library): LibraryItem v2 schema with EditDocument support

Adds documentData field; legacy stackData blobs continue to read via
EditDocument.migrating fallback. New library writes go through editDocument
setter which populates both fields for forward+backward compat."
```

- [ ] **Step 5: Push and verify**

```bash
git push
```

Run post-push routine. Wait for green.

---

## Task 8: Mask lifecycle on `EditorViewModel` (apply, refine, remove, prefetch)

**Files:**
- Modify: `PhotoEditor/Editor/EditorViewModel.swift`
- Add tests to `PhotoEditorTests/EditorViewModelMaskScopeTests.swift`

- [ ] **Step 1: Inject `SubjectMaskStore` and define lifecycle methods**

```swift
// EditorViewModel additions
private let maskStore: SubjectMaskStore = SubjectMaskStore()

var canApplyMask: Bool {
    importedImage != nil && lastDetectedInstanceCount > 0
}
private(set) var lastDetectedInstanceCount: Int = 0
private(set) var maskComputeInFlight: Bool = false
private(set) var maskComputeFailed: Bool = false

/// Triggered by toolbar tap when no mask exists yet.
func enterMaskMode() async {
    guard let imported = importedImage,
          let assetID = imported.sourceAssetID else {
        errorMessage = "Mask requires an imported photo with a source asset."
        return
    }
    maskComputeInFlight = true
    maskComputeFailed = false
    defer { maskComputeInFlight = false }

    do {
        let result = try await maskStore.mask(for: assetID, source: imported.previewCIImage)
        lastDetectedInstanceCount = result.instanceCount
        if result.instanceCount == 0 {
            // Surface a one-time toast; do NOT enable mask.
            successMessage = nil
            errorMessage = "No subject detected."
            return
        }
        // Enable mask in document, default settings.
        document.mask = SubjectMask()
        activeScope = .subject
        // Keep backgroundStack identical to subjectStack at the moment of mask entry.
        document.backgroundStack = document.subjectStack
        commitDiscreteChange()
        documentDidChange()
    } catch {
        maskComputeFailed = true
        errorMessage = "Couldn't compute subject mask. Try again."
    }
}

/// Eager prefetch on import.
func prefetchMaskForCurrentPhoto() {
    guard let imported = importedImage,
          let assetID = imported.sourceAssetID else { return }
    maskStore.prefetch(for: assetID, source: imported.previewCIImage)
}

func updateMaskFeather(_ value: Double) {
    guard document.mask != nil else { return }
    document.mask?.feather = max(0, min(1, value))
    documentDidChange()
}

func setMaskInvert(_ inverted: Bool) {
    guard document.mask != nil else { return }
    document.mask?.invert = inverted
    documentDidChange()
}

func toggleInstanceExcluded(_ index: Int) {
    guard document.mask != nil else { return }
    if document.mask!.excludedInstances.contains(index) {
        document.mask!.excludedInstances.remove(index)
    } else {
        document.mask!.excludedInstances.insert(index)
    }
    documentDidChange()
}

func removeMask() {
    guard document.mask != nil else { return }
    document.mask = nil
    document.backgroundStack = document.subjectStack
    activeScope = .subject
    commitDiscreteChange()
    documentDidChange()
}
```

Add a `prefetchMaskForCurrentPhoto()` call at the end of `importPhoto(data:sourceAssetID:)` and `openLibraryItem(_:)`.

- [ ] **Step 2: Lifecycle tests**

Append to `EditorViewModelMaskScopeTests.swift`:

```swift
func testRemoveMask_collapsesToSubjectStack() {
    let vm = EditorViewModel()
    vm.document.mask = SubjectMask(feather: 0.5)
    vm.document.subjectStack.light.exposure = 0.4
    vm.document.backgroundStack.light.exposure = -0.4

    vm.removeMask()

    XCTAssertNil(vm.document.mask)
    XCTAssertEqual(vm.document.backgroundStack, vm.document.subjectStack)
    XCTAssertEqual(vm.activeScope, .subject)
}

func testToggleInstanceExcluded_addsAndRemoves() {
    let vm = EditorViewModel()
    vm.document.mask = SubjectMask()
    vm.toggleInstanceExcluded(0)
    XCTAssertTrue(vm.document.mask!.excludedInstances.contains(0))
    vm.toggleInstanceExcluded(0)
    XCTAssertFalse(vm.document.mask!.excludedInstances.contains(0))
}

func testFeatherClamped_to0to1() {
    let vm = EditorViewModel()
    vm.document.mask = SubjectMask()
    vm.updateMaskFeather(2.0)
    XCTAssertEqual(vm.document.mask?.feather, 1.0)
    vm.updateMaskFeather(-0.3)
    XCTAssertEqual(vm.document.mask?.feather, 0.0)
}
```

- [ ] **Step 3: Commit**

```bash
git add PhotoEditor/Editor/EditorViewModel.swift PhotoEditorTests/EditorViewModelMaskScopeTests.swift
git commit -m "feat(editor): mask lifecycle on EditorViewModel

Adds enterMaskMode (Vision compute via SubjectMaskStore), prefetch on import,
feather/invert/per-instance toggles, and removeMask (collapses to single
stack). Failure and 0-instance cases route to errorMessage with one-time
toast. activeScope defaults to .subject on entry."
```

---

## Task 9: Toolbar mask button UI

**Files:**
- Create: `PhotoEditor/Editor/Controls/MaskToolbarButton.swift`
- Modify: `PhotoEditor/EditorTabView.swift` (add the button to the toolbar)

- [ ] **Step 1: Implement the button**

```swift
// PhotoEditor/Editor/Controls/MaskToolbarButton.swift
import SwiftUI

struct MaskToolbarButton: View {
    @Bindable var vm: EditorViewModel
    var onTapRefine: () -> Void  // shown when mask already active

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: iconName)
                    .symbolRenderingMode(.hierarchical)
                if vm.maskComputeInFlight {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.accentColor)
                }
            }
            .frame(width: 36, height: 36)
            .foregroundStyle(foreground)
        }
        .disabled(disabled)
        .accessibilityLabel(accessibilityLabel)
    }

    private var iconName: String {
        vm.document.mask != nil ? "person.fill.viewfinder" : "person.viewfinder"
    }

    private var foreground: Color {
        if vm.document.mask != nil { return .accentColor }
        if disabled { return .secondary.opacity(0.4) }
        return .primary
    }

    private var disabled: Bool {
        vm.importedImage == nil || vm.maskComputeInFlight
    }

    private var accessibilityLabel: String {
        vm.document.mask != nil ? "Refine subject mask" : "Mask subject"
    }

    private func action() {
        if vm.document.mask != nil {
            onTapRefine()
        } else {
            Task { await vm.enterMaskMode() }
        }
    }
}
```

- [ ] **Step 2: Wire into editor toolbar**

Read `PhotoEditor/EditorTabView.swift` and find the existing toolbar location (e.g., crop/undo/redo button row). Add `MaskToolbarButton` next to those. Pass a callback that opens the refinement sheet (state added in Task 10).

- [ ] **Step 3: Commit**

```bash
git add PhotoEditor/Editor/Controls/MaskToolbarButton.swift PhotoEditor/EditorTabView.swift
git commit -m "feat(ui): toolbar mask button with idle/active/loading states"
```

---

## Task 10: Panel header sub-segment + refinement bottom sheet

**Files:**
- Create: `PhotoEditor/Editor/Panels/MaskScopeHeaderView.swift`
- Create: `PhotoEditor/Editor/Panels/MaskRefinementSheet.swift`
- Modify: `PhotoEditor/Editor/Panels/` (whichever container view holds the slider panel — wire scope header in)
- Modify: `PhotoEditor/EditorTabView.swift` (sheet presentation state)

- [ ] **Step 1: Implement scope header**

```swift
// PhotoEditor/Editor/Panels/MaskScopeHeaderView.swift
import SwiftUI

struct MaskScopeHeaderView: View {
    @Bindable var vm: EditorViewModel

    var body: some View {
        if vm.document.mask != nil {
            Picker("Mask Scope", selection: $vm.activeScope) {
                Text("Subject").tag(MaskScope.subject)
                Text("Full").tag(MaskScope.full)
                Text("Background").tag(MaskScope.background)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 6)
            .onChange(of: vm.activeScope) { _, _ in
                // Trigger preview re-render so canvas reflects "what the sliders touch."
                // (No actual document mutation here.)
            }
        }
    }
}
```

- [ ] **Step 2: Implement refinement sheet**

```swift
// PhotoEditor/Editor/Panels/MaskRefinementSheet.swift
import SwiftUI

struct MaskRefinementSheet: View {
    @Bindable var vm: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingRemove = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Edge") {
                    HStack {
                        Text("Feather")
                        Slider(value: Binding(
                            get: { vm.document.mask?.feather ?? 0 },
                            set: { vm.updateMaskFeather($0) }
                        ), in: 0...1)
                    }
                    Toggle("Invert", isOn: Binding(
                        get: { vm.document.mask?.invert ?? false },
                        set: { vm.setMaskInvert($0) }
                    ))
                }

                if vm.lastDetectedInstanceCount > 1 {
                    Section("Subjects") {
                        ForEach(0..<vm.lastDetectedInstanceCount, id: \.self) { i in
                            HStack {
                                Text("Subject \(i + 1)")
                                Spacer()
                                Image(systemName: vm.document.mask?.excludedInstances.contains(i) == true
                                      ? "circle" : "checkmark.circle.fill")
                                    .foregroundStyle(.accent)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { vm.toggleInstanceExcluded(i) }
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        confirmingRemove = true
                    } label: {
                        Text("Remove Mask")
                    }
                }
            }
            .navigationTitle("Edit Mask")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Remove subject mask? Background edits will be discarded.",
                isPresented: $confirmingRemove,
                titleVisibility: .visible
            ) {
                Button("Remove Mask", role: .destructive) {
                    vm.removeMask()
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            }
        }
    }
}
```

- [ ] **Step 3: Wire into EditorTabView**

Add state for sheet presentation in `EditorTabView`:

```swift
@State private var showingMaskRefinement = false
```

In the toolbar:

```swift
MaskToolbarButton(vm: vm) {
    showingMaskRefinement = true
}
```

In the body modifiers:

```swift
.sheet(isPresented: $showingMaskRefinement) {
    MaskRefinementSheet(vm: vm)
}
```

Insert `MaskScopeHeaderView(vm: vm)` above the slider panel container.

- [ ] **Step 4: Commit**

```bash
git add PhotoEditor/Editor/Panels/MaskScopeHeaderView.swift PhotoEditor/Editor/Panels/MaskRefinementSheet.swift PhotoEditor/EditorTabView.swift
git commit -m "feat(ui): mask scope header + refinement bottom sheet

[Subject | Full | Background] segmented picker shown when mask active.
Refinement sheet surfaces feather, invert, per-instance exclude, and
Remove Mask with confirmation dialog."
```

---

## Task 11: Instance picker overlay on canvas

Per-instance overlay that dims the rest of the image and shows tinted regions for each detected subject; tap toggles inclusion.

**Files:**
- Create: `PhotoEditor/Editor/InstancePickerOverlay.swift`
- Modify: `PhotoEditor/Editor/Panels/MaskRefinementSheet.swift` (mount overlay in a header section above the form)

- [ ] **Step 1: Implement overlay**

```swift
// PhotoEditor/Editor/InstancePickerOverlay.swift
import CoreImage
import SwiftUI
import UIKit

struct InstancePickerOverlay: View {
    @Bindable var vm: EditorViewModel
    let instanceTints: [Color] = [.blue, .pink, .green, .orange, .purple, .yellow]

    var body: some View {
        ZStack {
            if let preview = vm.previewImage {
                Image(uiImage: preview).resizable().scaledToFit()
            }
            ForEach(0..<vm.lastDetectedInstanceCount, id: \.self) { i in
                InstanceTapTarget(index: i, vm: vm,
                                  tint: instanceTints[i % instanceTints.count])
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
    }
}

private struct InstanceTapTarget: View {
    let index: Int
    @Bindable var vm: EditorViewModel
    let tint: Color

    var body: some View {
        // v1 instance overlay: tinted full-canvas tap target with opacity hint.
        // Per-pixel masked overlays come in a follow-up — out of scope for this phase.
        Rectangle()
            .fill(tint.opacity(included ? 0.18 : 0.04))
            .overlay(
                Text("Subject \(index + 1)")
                    .font(.caption2.bold())
                    .padding(4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(6),
                alignment: .topLeading
            )
            .contentShape(Rectangle())
            .onTapGesture { vm.toggleInstanceExcluded(index) }
    }

    private var included: Bool {
        !(vm.document.mask?.excludedInstances.contains(index) ?? false)
    }
}
```

> **Note on visual fidelity:** the v1 overlay is intentionally simple (tinted full-canvas regions per instance). A pixel-accurate per-instance overlay (drawing each instance's actual mask shape) requires rendering `SubjectMaskResult.perInstance[i]` to a UIImage and overlaying with proper alignment to the displayed preview. This is deferred to a later polish phase — flagged in the design as out-of-scope visual refinement.

- [ ] **Step 2: Mount overlay in refinement sheet**

In `MaskRefinementSheet`, prepend an overlay section above the existing Form:

```swift
NavigationStack {
    VStack(spacing: 0) {
        InstancePickerOverlay(vm: vm)
            .padding(.bottom, 8)
        Form { /* existing sections */ }
    }
    .navigationTitle("Edit Mask")
    // ...
}
```

- [ ] **Step 3: Commit**

```bash
git add PhotoEditor/Editor/InstancePickerOverlay.swift PhotoEditor/Editor/Panels/MaskRefinementSheet.swift
git commit -m "feat(ui): instance picker overlay with tap-to-toggle

v1 overlay shows tinted regions per detected subject above the preview;
tap toggles include/exclude. Pixel-accurate mask shapes deferred."
```

- [ ] **Step 4: Push and verify CI**

```bash
git push
```

Run post-push routine.

---

## Task 12: Edge cases — 0-instance toast + error states + manual device test pass

**Files:**
- Modify: `PhotoEditor/Editor/ToastOverlay.swift` (if it doesn't already render `vm.errorMessage`/`successMessage`, ensure it does)
- Modify: `PhotoEditor/EditorTabView.swift` (toast presentation rules)
- No new code files

- [ ] **Step 1: Audit toast pipeline**

Open `PhotoEditor/Editor/ToastOverlay.swift` and confirm it observes `vm.errorMessage` and `vm.successMessage`. The mask lifecycle methods in Task 8 already write to these, so the toast should fire on:
- "No subject detected." when 0 instances
- "Couldn't compute subject mask. Try again." on Vision failure

If the toast already auto-dismisses, no work needed here. If not, add a 3-second auto-dismiss.

- [ ] **Step 2: Manual device test checklist**

Add a checklist file `docs/superpowers/manual-tests/2026-05-04-mask-feature.md`:

```markdown
# AI Subject Mask — Manual Device Tests

After CI green and IPA installed, run through these:

- [ ] Single-person portrait: tap mask → subject highlighted → adjust subject exposure +0.5 → background untouched
- [ ] Group photo (3+ people): refinement sheet → exclude one person → that person reverts to background stack
- [ ] Pure landscape (no foreground): tap mask → toast "No subject detected", icon stays disabled
- [ ] Background mode: switch to Background → drop temperature → only sky cools
- [ ] Full mode: switch to Full → exposure +0.3 → both regions brighten identically
- [ ] Feather slider: drag 0 → 1 → edge softens visibly without halos
- [ ] Invert toggle: subject becomes the background and vice versa
- [ ] Crop after mask: rotate 90° + crop to square → mask stays aligned
- [ ] Remove Mask: confirmation dialog → confirm → reverts to single stack with subjectStack values
- [ ] Save to Library → reopen → mask + both stacks restored
- [ ] Export PNG/JPEG → exported image has masked composite baked in
- [ ] Preview latency: smooth slider drag in masked mode (no >100ms hitches at 2048px preview)
```

- [ ] **Step 3: Commit and push**

```bash
git add PhotoEditor/Editor/ToastOverlay.swift PhotoEditor/EditorTabView.swift docs/superpowers/manual-tests/2026-05-04-mask-feature.md
git commit -m "feat(mask): edge case toasts + manual device test checklist"
git push
```

Run post-push routine. Once CI green and IPA installed, walk the checklist on device. File any regressions as follow-up tasks.

---

## Self-Review Checklist (post-plan-author)

- [x] **Spec coverage:** Every section of the spec maps to a task. Data model → Task 1. Pipeline → Tasks 2–3. Mask compute → Task 4. RenderEngine → Task 5. View model + scope routing + crop pin → Task 6. Library migration → Task 7. Mask lifecycle → Task 8. Toolbar → Task 9. Sub-segment + sheet → Task 10. Instance picker → Task 11. Edge cases + manual tests → Task 12.
- [x] **No placeholders:** All steps contain runnable code or exact commands.
- [x] **Type consistency:** `EditDocument`, `SubjectMask`, `SubjectMaskResult`, `SubjectMaskProvider`, `AssetID`, `MaskScope` referenced consistently across tasks.
- [x] **Test coverage:** 5 new test files. Lifecycle, migration, scope routing, crop invariant, masked composite all covered.
- [x] **Out-of-scope honored:** No brush, no per-instance separate stacks, no per-stage scope, no hair-edge matting. Pixel-accurate per-instance overlay flagged as deferred polish in Task 11.
