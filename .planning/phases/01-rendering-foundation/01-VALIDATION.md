---
phase: 1
slug: rendering-foundation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-03
---

# Phase 1 — Validation Strategy

> Per-phase validation contract. Most "automated" verification on this iOS project is grep-based — Linux dev environment cannot run `xcodebuild` or simulator. On-device behavior is verified via the Manual-Only Verifications table on the user's Mac.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (target may need to be added to PhotoEditor.xcodeproj) |
| **Config file** | `PhotoEditor.xcodeproj/project.pbxproj` (test target) |
| **Quick run command** | grep-based file/symbol gates (Linux) |
| **Full suite command** | `xcodebuild test -project PhotoEditor.xcodeproj -scheme PhotoEditor -destination 'platform=iOS Simulator,name=iPhone 15'` (Mac only) |
| **Estimated runtime** | grep gates: <1 s · XCTest on Mac: ~30 s |

---

## Sampling Rate

- **After every task commit:** Run all grep-based gates that apply to that task's files
- **After every plan wave:** Re-run the full grep gate set + reread changed files
- **Before `/gsd:verify-work`:** All grep gates green; manual UAT items confirmed by user on Mac
- **Max feedback latency:** <1 s for grep gates; user-paced for Mac UAT

---

## Per-Task Verification Map

Tasks are not yet split into Plans/Waves — that is the planner's job. Below are the verification gates each Phase-1 deliverable must satisfy. The planner will map these to Task IDs.

| Deliverable | Requirement | Test Type | Automated Command (grep) | Status |
|---|---|---|---|---|
| `Editor/AdjustmentStack.swift` exists with `struct AdjustmentStack` and `var schemaVersion: Int` | RENDER-06 | grep | `grep -E "struct AdjustmentStack" PhotoEditor/Editor/AdjustmentStack.swift && grep -E "var schemaVersion: Int" PhotoEditor/Editor/AdjustmentStack.swift` | ⬜ pending |
| `AdjustmentStack` conforms to `Codable` and `Equatable` | RENDER-06 | grep | `grep -E "AdjustmentStack.*Codable" PhotoEditor/Editor/AdjustmentStack.swift` | ⬜ pending |
| `AdjustmentStack` has nested `Light`, `Color`, `HSL`, `Curves`, `SplitToning`, `Effects`, `Crop` structs (full surface, even if Phase 1 only wires light + color) | RENDER-06 | grep | `for k in Light Color HSL Curves SplitToning Effects Crop; do grep -q "struct $k" PhotoEditor/Editor/AdjustmentStack.swift || exit 1; done` | ⬜ pending |
| `RenderEngine/PipelineBuilder.swift` exports a pure free function `func buildPipeline(_ stack: AdjustmentStack, source: CIImage) -> CIImage` (or `enum PipelineBuilder` with `static func build`) | RENDER-04, ADJUST-10 | grep | `grep -E "PipelineBuilder|buildPipeline" PhotoEditor/RenderEngine/PipelineBuilder.swift` | ⬜ pending |
| `RenderEngine/RenderEngine.swift` declares `actor RenderEngine` | RENDER-03, RENDER-04 | grep | `grep -E "^actor RenderEngine" PhotoEditor/RenderEngine/RenderEngine.swift` | ⬜ pending |
| `RenderEngine` constructs Metal CIContext explicitly via `MTLCreateSystemDefaultDevice` | RENDER-05 | grep | `grep -E "MTLCreateSystemDefaultDevice|CIContext\(mtlDevice:" PhotoEditor/RenderEngine/RenderEngine.swift` | ⬜ pending |
| `RenderEngine` exposes separate `previewContext` and `exportContext` | RENDER-04, RENDER-05 | grep | `grep -E "previewContext" PhotoEditor/RenderEngine/RenderEngine.swift && grep -E "exportContext" PhotoEditor/RenderEngine/RenderEngine.swift` | ⬜ pending |
| `RenderEngine` previews at ≤1080 px long edge (constant or comment referencing 1080) | RENDER-03 | grep | `grep -E "1080" PhotoEditor/RenderEngine/RenderEngine.swift` | ⬜ pending |
| Preview render cancellation: `EditorViewModel` cancels in-flight render task on stack change (cancellation lives in the VM, not the actor) | RENDER-03 | grep | `grep -E "renderTask\?\.cancel|Task\.isCancelled" PhotoEditor/Editor/EditorViewModel.swift` | ⬜ pending |
| `Editor/ImageImporter.swift` uses `CIImage(data:options:)` not `UIImage(data:)`→`CIImage(image:)` | RENDER-01 | grep | `grep -E "CIImage\(data: .*applyOrientationProperty" PhotoEditor/Editor/ImageImporter.swift` | ⬜ pending |
| `ImageImporter` calls `.oriented(forExifOrientation:)` explicitly | RENDER-01 | grep | `grep -E "oriented\(forExifOrientation" PhotoEditor/Editor/ImageImporter.swift` | ⬜ pending |
| `ImageImporter` does NOT set `.colorSpace` in CIImage options (source ICC profile must propagate untouched); intent recorded as a `RENDER-01 color profile` comment | RENDER-01 | grep | `! grep -E "options:.*\.colorSpace" PhotoEditor/Editor/ImageImporter.swift && grep -E "RENDER-01 color profile" PhotoEditor/Editor/ImageImporter.swift` | ⬜ pending |
| `RenderEngine` declares `workingColorSpace` as `extendedLinearSRGB` so the inherited source profile converts correctly | RENDER-01 | grep | `grep -E "extendedLinearSRGB" PhotoEditor/RenderEngine/RenderEngine.swift` | ⬜ pending |
| `Editor/EditorViewModel.swift` exists and is `@Observable` | RENDER-02 | grep | `grep -E "@Observable" PhotoEditor/Editor/EditorViewModel.swift && grep -E "(class\|final class) EditorViewModel" PhotoEditor/Editor/EditorViewModel.swift` | ⬜ pending |
| `EditorViewModel` holds `var stack: AdjustmentStack` (source of truth) and `var importedImage: ImportedImage?` (source asset wrapper) | RENDER-02 | grep | `grep -E "var stack: AdjustmentStack" PhotoEditor/Editor/EditorViewModel.swift && grep -E "var importedImage: ImportedImage" PhotoEditor/Editor/EditorViewModel.swift` | ⬜ pending |
| `PhotoEditorViewModel.swift` is deleted | RENDER-05 | grep | `! test -f PhotoEditor/PhotoEditorViewModel.swift` | ⬜ pending |
| No `CIPhotoEffect*` references remain anywhere under `PhotoEditor/` | RENDER-05 | grep | `! grep -rE "CIPhotoEffect" PhotoEditor/` | ⬜ pending |
| No `CIContext\(\)` (no-arg) remains | RENDER-05 | grep | `! grep -RnE "CIContext\(\)" PhotoEditor/` | ⬜ pending |
| `ContentView.swift` slider bindings target the new stack | RENDER-02 | grep | `grep -E "stack\.light\.|stack\.color\." PhotoEditor/ContentView.swift` | ⬜ pending |
| Unit test target exists with at least: `AdjustmentStackTests` (codable round-trip) and `PipelineBuilderTests` (identity stack returns equivalent CIImage extent) | RENDER-04, RENDER-06 | grep | `grep -lE "AdjustmentStackTests" PhotoEditorTests/ && grep -lE "PipelineBuilderTests" PhotoEditorTests/` | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `PhotoEditorTests/` directory exists in the project
- [ ] `PhotoEditorTests/AdjustmentStackTests.swift` — Codable round-trip stub
- [ ] `PhotoEditorTests/PipelineBuilderTests.swift` — pipeline identity test stub
- [ ] Test target added to `PhotoEditor.xcodeproj` *(if missing — NOTE: this requires user action on Mac, since `pbxproj` editing is fragile from Linux)*

---

## Manual-Only Verifications

The user must run these on a Mac before the phase is considered verified.

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| App launches with the new pipeline; Metal CIContext is active | RENDER-05 | Runtime check — Metal device only resolves on real hardware/simulator | Build & run in iPhone 15 simulator. Set a breakpoint in `RenderEngine.init()`. Confirm `MTLCreateSystemDefaultDevice()` returns non-nil. Optionally instrument with `print(context.description)` and confirm no "software" string in description. |
| Photo imports with correct orientation across all 8 EXIF cases | RENDER-01 | Requires actual rotated photos | Pre-stage 8 test photos in Photos.app with orientations 1–8 (Apple's TestImage suite or capture rotated). Import each. Confirm preview shows upright, edges aligned. |
| Color profile preserved (Display P3 source → P3 in preview, no desaturation) | RENDER-01 | Requires P3-source photo and visual diff | Import a P3 photo (most iPhone HDR captures). Compare on-device against Photos.app preview. No visible desaturation or hue shift. |
| Slider drag stays smooth — preview never blocks | RENDER-03 | Performance is subjective; requires real device drag | Drag exposure/contrast/saturation slider rapidly. Preview must update visibly without stutter. No beachball, no frozen frames. |
| No full-resolution render fires per slider tick | RENDER-04 | Behavior visible only via Instruments / log | Add a `print` to the export-context render path. Drag a slider 50 times. Confirm zero export-context renders occur during drag. |
| Edits are non-destructive — Reset returns to exact original | RENDER-02 | Visual diff with reset | Apply heavy edit. Tap Reset. Compare to source image — must be byte-identical (same `Data` from PHAsset would round-trip). |
| Save to Photos still works (smoke test) | (continuity) | Permission + render path | Pick photo → adjust → save. Open Photos.app, confirm new asset appears with edits applied. |

---

## Validation Sign-Off

- [ ] All tasks have either an automated grep gate or a Manual-Only entry mapped to a requirement
- [ ] Sampling continuity: every task touches at least one grep gate
- [ ] Wave 0 covers test target setup and stub files
- [ ] No watch-mode flags
- [ ] Feedback latency: grep gates <1 s; manual UAT user-paced
- [ ] `nyquist_compliant: true` set in frontmatter (after planner approves)

**Approval:** pending
