---
phase: 260504-mgz-add-histogram-overlay
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - PhotoEditor/Editor/HistogramRenderer.swift
  - PhotoEditor/Editor/HistogramOverlayView.swift
  - PhotoEditor/Editor/EditorViewModel.swift
  - PhotoEditor/EditorTabView.swift
autonomous: false
requirements:
  - HIST-OVERLAY-01
  - HIST-OVERLAY-02
  - HIST-OVERLAY-03

must_haves:
  truths:
    - "User can toggle a histogram overlay on/off via a toolbar button in the editor"
    - "When visible, the overlay shows the RGB distribution of the post-pipeline preview (after LUT, HSL, halation, grain, tone curve)"
    - "Histogram updates only when a new preview frame is committed — no per-drag-tick recomputation"
    - "Toggle state and histogram bitmap survive a normal edit session without leaking memory or stalling the slider drag path"
    - "Overlay sits in bottom-leading corner of the canvas at ~120x80pt with semi-transparent background and hairline border, following Theme tokens"
  artifacts:
    - path: "PhotoEditor/Editor/HistogramRenderer.swift"
      provides: "Pure CIAreaHistogram + CIHistogramDisplayFilter pipeline; produces a CGImage from any post-pipeline CIImage"
      contains: "CIAreaHistogram, CIHistogramDisplayFilter"
    - path: "PhotoEditor/Editor/HistogramOverlayView.swift"
      provides: "SwiftUI overlay view rendering the histogram CGImage with VSCO-style chrome (semi-transparent panel, hairline border, Theme tokens)"
      contains: "struct HistogramOverlayView"
    - path: "PhotoEditor/Editor/EditorViewModel.swift"
      provides: "isHistogramVisible toggle + histogramImage state + recompute-on-commit hook in stackDidChange/renderPreviewNow"
      contains: "isHistogramVisible, histogramImage"
    - path: "PhotoEditor/EditorTabView.swift"
      provides: "Toolbar button (chart icon) to toggle overlay; overlay positioned bottom-leading on canvas when visible"
      contains: "HistogramOverlayView"
  key_links:
    - from: "EditorViewModel.stackDidChange / renderPreviewNow"
      to: "HistogramRenderer"
      via: "post-render commit hook (only after the latest-generation preview CGImage commits)"
      pattern: "HistogramRenderer\\.render|histogramImage ="
    - from: "EditorTabView toolbar button"
      to: "EditorViewModel.isHistogramVisible"
      via: "@Bindable toggle"
      pattern: "isHistogramVisible"
    - from: "EditorTabView canvas overlay"
      to: "EditorViewModel.histogramImage"
      via: "conditional .overlay(alignment: .bottomLeading)"
      pattern: "HistogramOverlayView"
---

<objective>
Add an RGB histogram overlay to the editor preview so the user can judge clipping/exposure on the *post-pipeline* image (after LUT, HSL, halation, grain, tone curve) while editing.

Purpose: Critical photographer feedback that the current "no scope" UX is missing. Must integrate cleanly into the existing debounced render pipeline — no extra hot-path passes per slider tick.

Output: A toolbar-toggleable, ~120x80pt semi-transparent histogram in the bottom-leading corner of the canvas, recomputed only when a new preview frame commits.
</objective>

<execution_context>
@/home/matt/.claude/get-shit-done/workflows/execute-plan.md
@/home/matt/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@CLAUDE.md
@PhotoEditor/Editor/EditorViewModel.swift
@PhotoEditor/RenderEngine/RenderEngine.swift
@PhotoEditor/EditorTabView.swift
@PhotoEditor/Editor/Panels/CompareGesture.swift
@PhotoEditor/Design/Theme.swift

<interfaces>
<!-- Key types/contracts the executor needs. Do not go exploring. -->

EditorViewModel (PhotoEditor/Editor/EditorViewModel.swift)
- @MainActor @Observable final class
- var previewImage: UIImage?            // committed only by latest-generation render
- var importedImage: ImportedImage?
- private var renderGeneration: UInt64  // monotonic; commit guard pattern
- func stackDidChange()                 // debounced render path (40ms, generation-coalesced)
- private func renderPreviewNow() async // first-frame / undo / redo / openLibraryItem path
- private let engine: RenderEngine?
- The render commit point is the line `self.previewImage = UIImage(cgImage: cg)` — one in stackDidChange's Task, one in renderPreviewNow. Both are guarded by `myGen == self.renderGeneration` (in the debounced path) or unconditional first-frame (in renderPreviewNow). Histogram must be (re)computed at these exact commit points, NOT inside PipelineBuilder.

RenderEngine (PhotoEditor/RenderEngine/RenderEngine.swift)
- actor; do NOT add a histogram pass to PipelineBuilder.build — keep the pipeline pure.
- The post-pipeline CIImage is the `chain` returned by PipelineBuilder.build. We do not currently expose it; we work from the committed CGImage instead (wrap as CIImage(cgImage:) for histogram input — preserves Display P3 output color space).

Theme tokens (PhotoEditor/Design/Theme.swift)
- Theme.Colors.canvas / .panel / .text / .secondary / .separator
- Theme.Spacing.xs/.sm/.md/.lg
- Theme.Radii.small (2pt) / .medium (4pt)
- Typography: tracked-out 10pt labels in UPPERCASE per VSCO style

EditorTabView canvas (PhotoEditor/EditorTabView.swift)
- private var editorPreview: some View    // ZStack with Theme.Colors.canvas + Image
- existing pattern for overlays: `.overlay(alignment: .topLeading) { ... }` (the ORIGINAL pill at line ~211)
- Toolbar lives in `editorTopBar`. New toggle button goes between the Mask button and `Spacer()`.
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: HistogramRenderer (pure Core Image utility)</name>
  <files>PhotoEditor/Editor/HistogramRenderer.swift</files>
  <action>
Create a stateless enum `HistogramRenderer` that takes a post-pipeline CGImage and returns a small histogram CGImage.

Implementation:
  - `enum HistogramRenderer { static func render(postPipeline cg: CGImage, context: CIContext) -> CGImage? }`
  - Wrap input: `let input = CIImage(cgImage: cg)`
  - `CIAreaHistogram` with `inputExtent = input.extent`, `inputCount = 256`, `inputScale = 1.0` — produces a 256x1 histogram image.
  - Pipe into `CIHistogramDisplayFilter` with `inputHeight = 64`, `inputHighLimit = 1.0`, `inputLowLimit = 0.0` — produces a 256x64 RGBA image with R/G/B channels stacked as colored bars on a black background.
  - Render to CGImage via the passed-in CIContext (caller owns context lifecycle — DO NOT spin up a fresh CIContext here; expensive).
  - Return nil on any filter failure; never throw.

Use a dedicated CIContext at the call site (not the RenderEngine's preview/export contexts — those are actor-isolated). Caller is responsible.

Why CIAreaHistogram + CIHistogramDisplayFilter (not a hand-rolled Metal kernel): zero new dependencies, GPU-accelerated, ~1ms on a 1080px preview, gives R/G/B overlaid bars in one pass. Apple-blessed for exactly this use case.

Why operate on CGImage (not the pre-CIContext CIImage chain): the `chain` output is in extendedLinearSRGB working space; sampling there gives non-monitor-relative values. The committed CGImage is in Display P3 — what the user actually SEES — which is what a clipping histogram must reflect.
  </action>
  <verify>
    <automated>MISSING — Swift unit tests not configured for this Linux→CI flow. Manual verification only: file compiles in CI archive step. Confirm via `gh run watch` that the archive step succeeds (exit 0).</automated>
  </verify>
  <done>
HistogramRenderer.swift exists, exports `HistogramRenderer.render(postPipeline:context:)`, uses CIAreaHistogram + CIHistogramDisplayFilter, no fresh CIContext per call, no throws. CI archive build passes.
  </done>
</task>

<task type="auto">
  <name>Task 2: ViewModel state + render-commit hook + SwiftUI overlay view</name>
  <files>PhotoEditor/Editor/HistogramOverlayView.swift, PhotoEditor/Editor/EditorViewModel.swift</files>
  <action>
**Part A — HistogramOverlayView.swift (new file):**

```swift
import SwiftUI
import UIKit

struct HistogramOverlayView: View {
    let image: UIImage?
    var body: some View {
        ZStack {
            // Semi-transparent VSCO-flavored chrome.
            RoundedRectangle(cornerRadius: Theme.Radii.small)
                .fill(Theme.Colors.canvas.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radii.small)
                        .strokeBorder(Theme.Colors.separator.opacity(0.6), lineWidth: 0.5)
                )
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)   // crisp histogram bars
                    .scaledToFit()
                    .padding(Theme.Spacing.xs)
            }
        }
        .frame(width: 120, height: 80)
        .accessibilityLabel("RGB histogram")
        .allowsHitTesting(false)            // pass-through; user can still tap canvas to hide chrome
    }
}
```

**Part B — EditorViewModel.swift edits:**

1. Add observable state near `previewImage`:
```swift
var isHistogramVisible: Bool = false
var histogramImage: UIImage?
```

2. Add a private CIContext for histogram rendering (cheap to keep alive, expensive to recreate):
```swift
private let histogramContext: CIContext = CIContext(options: [.useSoftwareRenderer: false])
```

3. Add a private helper:
```swift
private func recomputeHistogramIfVisible(from cg: CGImage) {
    guard isHistogramVisible else { histogramImage = nil; return }
    if let h = HistogramRenderer.render(postPipeline: cg, context: histogramContext) {
        histogramImage = UIImage(cgImage: h)
    }
}
```

4. Wire it at the TWO commit points:
   - Inside `stackDidChange()`'s Task, immediately after `self.previewImage = UIImage(cgImage: cg)`:
     ```swift
     self.recomputeHistogramIfVisible(from: cg)
     ```
     This is INSIDE the `guard myGen == self.renderGeneration else { return }` block — histogram only updates for the latest-generation frame, so it never recomputes mid-drag.
   - Inside `renderPreviewNow()`, immediately after `self.previewImage = UIImage(cgImage: cg)`:
     ```swift
     self.recomputeHistogramIfVisible(from: cg)
     ```

5. Add a toggle method:
```swift
func toggleHistogram() {
    isHistogramVisible.toggle()
    if !isHistogramVisible {
        histogramImage = nil
        return
    }
    // When turning ON, compute immediately from the current preview if available.
    if let ui = previewImage, let cg = ui.cgImage {
        recomputeHistogramIfVisible(from: cg)
    }
}
```

**Critical constraints:**
- Do NOT add histogram work inside PipelineBuilder, RenderEngine, or any per-tick path. The 40ms debounce + generation guard pattern must remain untouched.
- Do NOT recreate `histogramContext` per call — reuse the stored instance.
- Do NOT mark histogramContext `nonisolated` or move to the engine actor; it's a MainActor-private cheap CPU/GPU context used only at commit.
- When `isHistogramVisible` is false, `histogramImage` MUST be nil (so the overlay view isn't paying for stale state).
  </action>
  <verify>
    <automated>MISSING — see Task 1 verification note. Confirm via `gh run watch` that archive succeeds.</automated>
  </verify>
  <done>
HistogramOverlayView.swift renders a fixed 120x80pt panel using Theme tokens. EditorViewModel exposes `isHistogramVisible`, `histogramImage`, `toggleHistogram()`. Histogram recompute hook fires at both commit points (stackDidChange Task + renderPreviewNow), guarded by `isHistogramVisible`. CI archive build passes.
  </done>
</task>

<task type="auto">
  <name>Task 3: Wire toolbar button + canvas overlay in EditorTabView</name>
  <files>PhotoEditor/EditorTabView.swift</files>
  <action>
**Part A — Toolbar button.** In `editorTopBar`, between the `MaskToolbarButton(...)` and `Spacer()`, add:

```swift
Button {
    Haptic.play(.undoRedo)   // reuse existing subtle haptic; no new token needed
    viewModel.toggleHistogram()
} label: {
    Image(systemName: viewModel.isHistogramVisible ? "chart.bar.fill" : "chart.bar")
        .font(.system(size: 15, weight: .semibold))
}
.disabled(viewModel.importedImage == nil)
.accessibilityLabel("Histogram")
.accessibilityValue(viewModel.isHistogramVisible ? "On" : "Off")
```

(Use `chart.bar` / `chart.bar.fill` — SF Symbols, available iOS 13+. Distinct from existing toolbar icons.)

**Part B — Canvas overlay.** In `editorPreview`, on the `Image(uiImage: image)` block, ADD a second `.overlay(alignment: .bottomLeading)` modifier AFTER the existing topLeading "ORIGINAL" overlay:

```swift
.overlay(alignment: .bottomLeading) {
    if viewModel.isHistogramVisible, viewModel.importedImage != nil {
        HistogramOverlayView(image: viewModel.histogramImage)
            .padding(Theme.Spacing.md)
            .transition(.opacity)
    }
}
```

**Critical constraints:**
- Order matters: place AFTER the topLeading overlay; don't replace it.
- Do NOT put the overlay inside the `if !isChromeHidden` chrome block — the histogram is canvas content, and should stay visible when the user taps to hide chrome (matches the spirit of a non-intrusive scope). If the user explicitly wants it hidden during chrome-hide, they can toggle the button. (We follow the simpler rule: histogram visibility is its own toggle, orthogonal to chrome.)
- `.allowsHitTesting(false)` is already in HistogramOverlayView, so the existing tap-to-hide-chrome gesture on the canvas still works through the overlay.
  </action>
  <verify>
    <automated>MISSING — Linux build is impossible; verification is on-device after CI archive. Confirm via `gh run watch` that archive succeeds, then human-verify in next task.</automated>
  </verify>
  <done>
Toolbar shows a chart-bar icon between Mask and Save-options that toggles histogram visibility. Canvas shows a 120x80 semi-transparent histogram in the bottom-leading corner when toggled on. Disabled when no photo is loaded. CI archive build passes.
  </done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 4: On-device verification</name>
  <what-built>
Toolbar histogram toggle (chart-bar icon, between Mask and DONE) + 120x80 RGB histogram overlay in bottom-leading corner of the canvas. Updates only on render commit, not per drag tick. Reflects the post-pipeline image (LUT + HSL + halation + grain + tone curve all included).
  </what-built>
  <how-to-verify>
1. Push to main and wait for CI to finish (use the post-push helper from CLAUDE.md to fetch the run id and run the full watch+download+install chain).

2. Install on iPhone via `ideviceinstaller -i PhotoEditor.ipa`.

3. Open the app, pick a photo with both deep shadows and bright highlights (e.g., a backlit subject).

4. **Toggle test:** In the editor, tap the chart-bar icon in the top toolbar. Histogram appears in bottom-leading corner. Tap again — disappears. Toggle on again.

5. **Pipeline reflectivity test:** Pick a saturated film LUT (e.g., one of the Kodak/Fuji presets). The histogram bars should change. Adjust HSL saturation hard to one extreme — bars should redistribute. Crank highlights/whites to clip — you should see RGB bars piled at the right edge of the histogram.

6. **Drag-coalescing test:** Drag a slider rapidly back and forth for 3 seconds. The histogram should NOT flicker frame-by-frame; it should update only when you stop (debounce + commit). The slider drag itself must remain smooth — no stutter.

7. **Compare gesture test:** Press-and-hold the canvas to show ORIGINAL. The histogram remains showing the EDITED histogram (it's tied to previewImage commits, not displayedImage). On release, no change. Acceptable behavior — document if user wants original-histogram-on-compare in a follow-up.

8. **Chrome-hide test:** Tap the canvas to hide chrome. Histogram remains visible (intentional — it's canvas content, not chrome). Tap again to restore chrome.

9. **Empty state test:** Reset to no photo (or open app fresh). Toolbar histogram button is disabled (greyed). Tapping does nothing.

10. **Style sanity:** Histogram has hairline border, semi-transparent panel matching Theme tokens (white-on-white in light mode, black-on-black-translucent in dark mode), bars are crisp (no interpolation blur).
  </how-to-verify>
  <resume-signal>Type "approved" if all 10 checks pass, or describe specific issues (e.g., "histogram updates per drag tick" or "wrong corner" or "border too dark").</resume-signal>
</task>

</tasks>

<verification>
- CI archive succeeds (no Swift compile errors).
- All 10 manual checks in Task 4 pass.
- No regression in slider-drag smoothness (Task 4 step 6).
- No regression in render generation/coalescing logic — verified by absence of mid-drag histogram flicker.
</verification>

<success_criteria>
- Toolbar button toggles histogram on/off; state persists within session.
- Histogram reflects post-pipeline (LUT + HSL + halation + grain + tone curve) image.
- Histogram updates only on preview commit (debounced), never per slider tick.
- Overlay sits 120x80pt bottom-leading, semi-transparent, hairline border, Theme-tokens.
- Slider drag remains smooth; no new hot-path work.
- No new third-party dependencies.
</success_criteria>

<output>
After completion, create `.planning/quick/260504-mgz-add-histogram-overlay/260504-mgz-SUMMARY.md`
</output>
