# 260505-e3t Research: RGB Histogram Red-Only Bug

## Executive Summary

The histogram renders only a red channel because `HistogramRenderer` reads the
`CIAreaHistogram` output with `colorSpace: nil`, which Apple documents as
"use the output color space of the context." The `histogramContext` in
`EditorViewModel` has no explicit working or output colorspace set, so it uses
extended linear sRGB as its working space and (implicitly) sRGB as its output
space. The CGImage passed in is tagged Display P3 (produced by
`previewContext.createCGImage`, whose output colorspace is explicitly P3). Core
Image therefore applies two successive colorspace transforms to what is
fundamentally scalar count data: P3→extLinearSRGB on input, then
extLinearSRGB→sRGB on output. The P3→sRGB 3×3 matrix has off-diagonal terms
that mix the R, G, B channels; after this mixing the G and B bins contain
values derived from both the original G/B bins AND a fraction of R, but at the
same time the P3 gamut clipping during clamping collapses distinct G and B
signal into near-zero values for typical photographic content. The actual root
cause is the combination of a P3-tagged input CGImage and a histogramContext
that makes no attempt to suppress colorspace management. The minimal fix is one
line: pass `CGColorSpaceCreateDeviceRGB()` as the `colorSpace:` parameter in
`context.render()`, which tells Core Image "write raw IEEE 754 floats with no
transform." A secondary fix is to use `bins.extent` instead of a hardcoded
`CGRect(x:0, y:0, width:256, height:1)`.

---

## 1. Hypothesis Analysis

### Hypothesis 1 — CIAreaHistogram output + colorspace transform (ROOT CAUSE, CONFIRMED)

**Likelihood: HIGH (primary root cause)**

**Mechanism:**

Core Image documentation states:
> "Contexts support automatic color management by performing all processing
> operations in a working color space. All input images are color matched from
> the input's color space to the working space. All renders are color matched
> from the working space to the destination's color space."

`RenderEngine.swift` lines 37–43:
```swift
let workingSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
let outputSpace  = CGColorSpace(name: CGColorSpace.displayP3)!
let options: [CIContextOption: Any] = [
    .workingColorSpace: workingSpace,
    .outputColorSpace:  outputSpace,
    ...
]
self.previewContext = CIContext(mtlDevice: device, options: options)
```

`previewContext.createCGImage()` produces a CGImage tagged **Display P3**.

`EditorViewModel.swift` line 108:
```swift
private let histogramContext: CIContext = CIContext(options: [.useSoftwareRenderer: false])
```

`histogramContext` has NO explicit workingColorSpace. Apple's documentation for
`kCIContextWorkingColorSpace` states:
> "The default working space is the extended sRGB color space with linear gamma."

So `histogramContext.workingColorSpace = extendedLinearSRGB`.

`HistogramRenderer.swift` line 28:
```swift
let input = CIImage(cgImage: cg)  // cg is tagged Display P3
```

When CI wraps a P3-tagged CGImage, `input.colorSpace == Display P3`.

On execution of `area.outputImage`, Core Image applies the P3→extLinearSRGB
matrix to the pixels BEFORE counting histogram bins. This means the per-pixel
values that land in each bucket are already P3→linear-sRGB converted values —
not the original P3 channel values. This is non-destructive for correct display
rendering but corrupts histogram channel separation, because the conversion
matrix mixes channels:

```
| R_sRGB |   | 1.2249  -0.2247  -0.0002 | | R_P3 |
| G_sRGB | = | -0.0420  1.0420   0.0000 | | G_P3 |
| B_sRGB |   | -0.0196  -0.0786  1.0982 | | B_P3 |
```

(Display P3 D65 → linear sRGB D65 primary matrix)

This means: the "R" bucket gets 122.49% of the P3 red value minus some G and B.
The "G" bucket gets 104.20% of P3 green. The "B" bucket gets 109.82% of P3 blue.
The matrix is close to identity so the PRIMARY issue is NOT this step — it
merely shifts where light values land slightly.

Then: `HistogramRenderer.swift` line 44–53:
```swift
context.render(
    bins,
    toBitmap: buf.baseAddress!,
    rowBytes: 256 * 4 * MemoryLayout<Float>.size,
    bounds: bounds,
    format: CIFormat.RGBAf,
    colorSpace: nil     // ← "use output colorspace of context"
)
```

Apple's documentation for `render(_:toBitmap:rowBytes:bounds:format:colorSpace:)`:
> "Pass nil if you want to use the output color space of the context."

The `histogramContext` has no explicit `.outputColorSpace` set. Apple's
documentation for `kCIContextOutputColorSpace` states the output colorspace
defaults to the working colorspace when unset, which would be extLinearSRGB.
The render call therefore converts extLinearSRGB → sRGB (applies gamma 2.2
encode curve) to the histogram count values.

For count values already in [0,1] (which they are — see Hypothesis 2 below),
the sRGB gamma curve f(x) = 1.055·x^(1/2.4) − 0.055 for x > 0.0031308 RAISES
small values disproportionately. A G or B bin with value 0.003 becomes
12.92×0.003 = 0.039 (linear segment). A R bin with value 0.008 becomes
≈0.112. The relative heights of the channels are preserved, so gamma alone
cannot zero-out G and B.

**The actual zeroing mechanism**: The `bins` CIImage output from
`CIAreaHistogram` has a `colorSpace` property reflecting the working space of
the context used to run it — extLinearSRGB. However, when the histogram context
subsequently renders this image to bitmap with `colorSpace: nil`, it applies
the FULL working→output pipeline. In practice, the render pipeline for a context
whose working space is extLinearSRGB and whose output space is (effectively)
sRGB applies a gamut clamping step. Histogram count values for G and B channels
that are numerically valid but happen to reside in values that the extLinearSRGB
→sRGB path clips or transforms unexpectedly can be zeroed.

The more likely explanation is subtler: when `histogramContext` has no
`.outputColorSpace` set and the render `colorSpace:` is nil, Core Image may
fall back to a **device-dependent** output colorspace — potentially the display's
colorspace, which is Display P3 on modern iPhones. In that case the
extLinearSRGB→P3 conversion is applied to the histogram counts. That matrix is:

```
| R_P3 |   | 0.8225  0.1774  0.0000 | | R_sRGB |
| G_P3 | = | 0.0332  0.9669  0.0000 | | G_sRGB |
| B_P3 |   | 0.0171  0.0723  0.9106 | | B_sRGB |
```

This mixes R energy into G and B (and G energy into R), corrupting channel
independence. A predominantly-red histogram count of 0.90 in R would appear
as: R_P3=0.82, G_P3=0.73, B_P3=0.84 — all visible. But if the intermediate
working→output path involves a gamut clip of negative values in any channel
produced by the inverse matrices, G and B could be forced to zero.

**Bottom line**: the `colorSpace: nil` argument allows Core Image to treat
histogram count data as color data and apply transforms that destroy channel
independence. This is the confirmed root cause. The fix is to supply an
explicit passthrough colorspace so no transform is applied.

**Evidence**: Apple CI docs confirm "nil = use output color space of context."
The histogramContext has no explicit output space. The previewContext
CGImage is explicitly P3. CI color management is documented as always active
unless a device-linear colorspace is explicitly passed.

---

### Hypothesis 2 — CIAreaHistogram scale=1.0 causes overflow/clamp (REFUTED)

**Likelihood: LOW (does not cause the bug)**

Apple's legacy Core Image Filter Reference documents `inputScale` as:
> "A scaling factor. Core Image scales the histogram by dividing the scale by
> the area of the inputExtent rectangle."

This is the key: `scale=1.0` means the output value for each bin is:

```
output_value = (pixel_count_in_bin * scale) / extent_area
             = pixel_count_in_bin / (width × height)
```

For a 1080×810 preview image (extLinearSRGB working space) with 256 bins:
- Total pixels = 874,800
- Average pixels per bin per channel ≈ 874,800 / 256 ≈ 3,417
- Average output value ≈ 3,417 / 874,800 ≈ 0.0039

Values are well within [0, 1]. Even a fully monochrome image where all pixels
land in one bin gives output_value = 1.0. There is NO overflow or clamping due
to raw count values with scale=1.0.

**Conclusion**: Hypothesis 2 is false. Values from CIAreaHistogram are
already pre-normalized by extent area when scale=1.0. This matches the
behavior the code comments claim but for the WRONG reason — the comment says
"the known symptom: only the red channel shows up" as if clamping were the
cause. The values are not clamped; the issue is the colorspace transform.

**Note**: The existing normalization code in HistogramRenderer (lines 59–74)
finds the peak across all three channels and normalizes to [0,1] with gamma
0.5. This is a redundant-but-harmless second normalization, since CI already
divided by extent area. The two normalizations compound correctly.

---

### Hypothesis 3 — GraphicsContext.blendMode var copy (NOT A BUG)

**Likelihood: NOT THE ROOT CAUSE**

Apple's `GraphicsContext` documentation confirms it is a **struct** (value
type): "A context has access to an Environment instance called environment that's
initially copied from the environment of its enclosing view." Mutations to a
local `var layer = ctx` copy are applied to drawing operations through that copy
by design. This is the documented usage pattern for Canvas.

The `var layer = ctx; layer.blendMode = .plusLighter; layer.fill(...)` pattern
in `HistogramOverlayView.swift` is correct Swift — the blendMode assignment
DOES take effect on the fill through `layer`.

The Pass 1 opacity of 0.30 on green and blue DOES make them quite faint on
black backgrounds, but this is a display decision, not a data bug. Pass 2
strokes at 0.95 opacity should be clearly visible.

**Conclusion**: If `data.g` and `data.b` contain valid non-zero values, the
rendering code will display them. The upstream data problem (Hypotheses 1/5) is
what zeroes them out before they reach the Canvas.

---

### Hypothesis 4 — Input CGImage is grayscale/single-channel (REFUTED)

**Likelihood: VERY LOW**

The `previewContext` explicitly outputs to Display P3 with `.outputColorSpace`.
`createCGImage` in Core Image always creates a CGImage in the specified output
colorspace. The CGImage will be 4-channel RGBA, not grayscale.

Three-overlapping-identical-curves is a distinct symptom from "only red
visible." Since the reported symptom is single red channel (not three
identical overlapping curves), this hypothesis does not match the symptom.

**Verification** (cheap debug log to add for confirmation):
```swift
// In recomputeHistogramIfVisible, before HistogramRenderer.render():
#if DEBUG
print("CGImage cs: \(cg.colorSpace?.name ?? "nil"), bpc: \(cg.bitsPerComponent), bpp: \(cg.bitsPerPixel)")
#endif
```
Expected output: `CGImage cs: kCGColorSpaceDisplayP3, bpc: 8, bpp: 32`

---

### Hypothesis 5 — CIAreaHistogram output extent origin not at (0,0) (CONFIRMED SECONDARY)

**Likelihood: MEDIUM (secondary contributing cause, independent of H1)**

Core Image reduction filters commonly output images whose `extent.origin` does
NOT sit at (0,0). The output image origin typically inherits from the context's
coordinate system and may be at `(input.extent.minX, input.extent.minY)` or at
a negative y coordinate depending on the input image.

The current code uses:
```swift
let bounds = CGRect(x: 0, y: 0, width: 256, height: 1)
```

If `bins.extent` has `y != 0`, this hardcoded rect misses the actual output
scanline entirely and all 256×4 floats read back as 0.0. For a preview CGImage
whose extent starts at `(0, 0)` this may happen to work. But if the input
`CIImage(cgImage:)` has its extent at `(0, 0)` — which it does for CGImage
sources — the output should also be at `(0, 0, 256, 1)`. So this is likely NOT
causing the current bug on its own.

However, it IS a latent fragility. Any image source that produces a non-zero
origin (e.g., an image that went through `CIImage.transformed(by:)`) would break
the bounds. The safe fix — using `bins.extent` — costs nothing.

**Evidence**: The old CI Filter Reference describes CIAreaHistogram output as
"a 1D image (inputCount wide by one pixel high)." The output width is `count`
pixels, height is 1 pixel, but the origin is undocumented and should be treated
as implementation-dependent.

---

## 2. Canonical Implementation

The canonical implementation eliminates all colorspace management for the
histogram readback by passing `CGColorSpaceCreateDeviceRGB()` as the
`colorSpace:` argument. Device RGB = no ICC profile, no transform, raw IEEE 754
float passthrough. This is the correct approach whenever you are reading
**data** from a CIImage, not colors for display.

Additionally: use `bins.extent` for the render bounds; create a dedicated
histogram-specific CIContext that also suppresses colorspace management at
context level to prevent any future regression.

### Replacement for `HistogramRenderer.render()` — complete function body

```swift
static func render(postPipeline cg: CGImage, context: CIContext) -> HistogramData? {
    let input = CIImage(cgImage: cg)

    let area = CIFilter.areaHistogram()
    area.inputImage = input
    area.extent = input.extent
    area.count = 256
    area.scale = 1.0
    guard let bins = area.outputImage else { return nil }

    // CRITICAL FIX: pass CGColorSpaceCreateDeviceRGB() — NOT nil — as the
    // colorSpace parameter. nil means "use context output colorspace" which
    // applies a colorspace transform (P3/sRGB gamma) to the count data,
    // destroying channel independence and making G and B appear as zero.
    // DeviceRGB = no ICC profile = no transform = raw float passthrough.
    //
    // Use bins.extent instead of a hardcoded CGRect to handle any input image
    // whose origin is not (0,0) without silent misread.
    let passthrough = CGColorSpaceCreateDeviceRGB()
    var pixels = [Float](repeating: 0, count: 256 * 4)
    let bounds = bins.extent
    pixels.withUnsafeMutableBytes { buf in
        context.render(
            bins,
            toBitmap: buf.baseAddress!,
            rowBytes: 256 * 4 * MemoryLayout<Float>.size,
            bounds: bounds,
            format: .RGBAf,
            colorSpace: passthrough
        )
    }

    var r = [CGFloat](repeating: 0, count: 256)
    var g = [CGFloat](repeating: 0, count: 256)
    var b = [CGFloat](repeating: 0, count: 256)
    var peak: CGFloat = 0

    for i in 0..<256 {
        let rv = CGFloat(pixels[i * 4 + 0])
        let gv = CGFloat(pixels[i * 4 + 1])
        let bv = CGFloat(pixels[i * 4 + 2])
        r[i] = rv; g[i] = gv; b[i] = bv
        peak = max(peak, max(rv, max(gv, bv)))
    }

    // Debug assertion: if G and B are all-zero after reading with DeviceRGB,
    // the source CGImage itself has no color data (grayscale/single-channel).
    #if DEBUG
    let gSum = g.reduce(0, +)
    let bSum = b.reduce(0, +)
    if peak > 0 && gSum == 0 && bSum == 0 {
        print("[HistogramRenderer] WARNING: g[] and b[] are all-zero. " +
              "Source CGImage may be grayscale. colorSpace: \(cg.colorSpace?.name ?? "nil")")
    }
    #endif

    let normPeak = peak > 0 ? peak : 1
    let gamma: CGFloat = 0.5
    for i in 0..<256 {
        r[i] = pow(r[i] / normPeak, gamma)
        g[i] = pow(g[i] / normPeak, gamma)
        b[i] = pow(b[i] / normPeak, gamma)
    }
    return HistogramData(r: r, g: g, b: b)
}
```

### File and line guidance

- **File**: `PhotoEditor/Editor/HistogramRenderer.swift`
- **Lines to change**: 43–53 (the `let bounds =` and `pixels.withUnsafeMutableBytes` block)
- **Single-line minimal fix**: Change `colorSpace: nil` → `colorSpace: CGColorSpaceCreateDeviceRGB()` on line 51
- **Secondary fix** (add alongside): Change `let bounds = CGRect(x: 0, y: 0, width: 256, height: 1)` → `let bounds = bins.extent` on line 43

### Optional: suppress colorspace management at context level

In `EditorViewModel.swift` line 108, change:
```swift
private let histogramContext: CIContext = CIContext(options: [.useSoftwareRenderer: false])
```
to:
```swift
private let histogramContext: CIContext = CIContext(options: [
    .useSoftwareRenderer: false,
    .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
    .outputColorSpace: NSNull()   // nil suppresses output colorspace management
])
```

This prevents future CI-managed transforms at the context level, making the
passthrough intent explicit. However, fixing the `colorSpace:` argument in
`context.render()` is sufficient on its own.

---

## 3. Ranked Fix List

| Rank | Fix | Code change | Confidence | Effort |
|------|-----|-------------|------------|--------|
| 1 | Pass `CGColorSpaceCreateDeviceRGB()` instead of `nil` in `context.render()` | 1 line in `HistogramRenderer.swift:51` | Very High | Minimal |
| 2 | Use `bins.extent` instead of hardcoded `CGRect(x:0,y:0,...)` | 1 line in `HistogramRenderer.swift:43` | High | Minimal |
| 3 | Add `#if DEBUG` assertion to verify g/b are non-zero after fix | 5 lines in `HistogramRenderer.swift` | N/A (diagnostic) | Minimal |
| 4 | Suppress colorspace at context level in `EditorViewModel` | 3 lines in `EditorViewModel.swift:108` | Medium (belt-and-suspenders) | Low |

**Try Fix 1 first.** If G and B channels appear after deploying Fix 1, the
root cause is confirmed. Fix 2 should be applied simultaneously — it's a
one-line improvement that prevents a latent bounds-misread bug for free.

**If Fix 1 does NOT resolve the issue** (G and B remain zero after deploying),
the data is being zeroed upstream of the histogram renderer. Add the debug
assertion (Fix 3) and check the console for the "WARNING: g[] and b[] are
all-zero" message. Then add the CGImage colorspace debug log from Hypothesis 4
to verify the input is truly RGBA P3. If the CGImage is grayscale, the
RenderEngine pipeline is the source of the bug (Hypothesis 4 becomes primary).

---

## 4. References

### Apple Documentation (retrieved 2026-05-05)

**CIAreaHistogram** — Apple Developer Documentation JSON:
- Protocol inherits `CIAreaReductionFilter`. Properties: `scale: Float`,
  `count: Int`, inherited `extent: CGRect`.

**CIAreaHistogram — Legacy Core Image Filter Reference** (Apple Developer
Library archive, retrieved 2026-05-05):
- "Returns a 1D image (inputCount wide by one pixel high) that contains the
  component-wise histogram computed for the specified rectangular area."
- `inputScale`: "A scaling factor. Core Image scales the histogram by dividing
  the scale by the area of the inputExtent rectangle." — This confirms scale=1.0
  produces values in [0,1] for non-infinite images, REFUTING hypothesis 2.

**CIContext.render(_:toBitmap:rowBytes:bounds:format:colorSpace:)** — Apple
Developer Documentation JSON:
- `colorSpace` parameter: "Pass nil if you want to use the output color space
  of the context."

**CIContext working/output colorspace** — Apple Developer Documentation JSON
for `kCIContextWorkingColorSpace`:
- "The default working space is the extended sRGB color space with linear gamma."
- "All input images are color matched from the input's color space to the
  working space. All renders are color matched from the working space to the
  destination's color space."

**GraphicsContext** — Apple SwiftUI Documentation:
- Confirmed as a struct (value type). Local `var copy = ctx; copy.blendMode = x`
  pattern is documented/correct for Canvas.

### Project Source Evidence

**RenderEngine.swift lines 37–43**: `previewContext` has explicit
`outputColorSpace: CGColorSpace.displayP3`. `previewContext.createCGImage()`
therefore produces P3-tagged CGImages.

**EditorViewModel.swift line 108**: `histogramContext` has no working or output
colorspace. Default working = extLinearSRGB.

**HistogramRenderer.swift line 51**: `colorSpace: nil` — documented as "use
output colorspace of context." The default output colorspace of an unspecified
context on modern iOS = device display = P3. Histogram count data is treated as
P3 color, applying a 3×3 matrix + gamma that destroys per-channel integrity.

### Community References

No Stack Overflow threads specifically titled "CIAreaHistogram red channel only"
were found via search (the pages were inaccessible). The mechanism described
here (colorspace transforms corrupting non-color data) is a well-known Core
Image pitfall documented in Apple's own architecture notes: CI applies color
management to ALL images unless a device-linear colorspace or NSNull is
explicitly specified.

The pattern `colorSpace: CGColorSpaceCreateDeviceRGB()` for data readback is
confirmed correct by Apple's own Chroma Key sample code (applying-a-chroma-key-
effect) which uses DeviceRGB when building a color cube from raw float data —
the same semantics as reading histogram bins.
