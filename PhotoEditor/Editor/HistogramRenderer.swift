import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import Foundation

/// 256-bin per-channel histogram counts, normalized to [0, 1] against the
/// per-frame peak across all three channels (so the tallest bar of any color
/// touches the top — matches what users expect from Lightroom/VSCO scopes).
struct HistogramData: Equatable {
    var r: [CGFloat]   // length 256
    var g: [CGFloat]
    var b: [CGFloat]
}

/// Pure utility that produces normalized RGB histogram counts from a
/// post-pipeline CGImage (the committed preview frame). Uses `CIAreaHistogram`
/// to compute the raw bins, then reads the 256x1 RGBA buffer ourselves so the
/// overlay view can draw crisp colored curves — Apple's `CIHistogramDisplayFilter`
/// produces a luma-filled grey block with faint colored traces that's hard to
/// read on-device.
///
/// Caller owns the CIContext lifecycle; we never spin up a fresh CIContext here
/// (that would be ~50ms per call — unacceptable on every render commit).
enum HistogramRenderer {
    /// Compute normalized R/G/B bin arrays from the supplied post-pipeline image.
    /// Returns nil on any filter or CIContext failure; never throws.
    static func render(postPipeline cg: CGImage, context: CIContext) -> HistogramData? {
        let input = CIImage(cgImage: cg)

        let area = CIFilter.areaHistogram()
        area.inputImage = input
        area.extent = input.extent
        area.count = 256
        area.scale = 1.0
        guard let bins = area.outputImage else { return nil }

        // Read the 256x1 area-histogram output as raw float RGBA. CRITICAL:
        // pass colorSpace=nil so CIContext does NOT apply a color transform —
        // the bytes here are *counts*, not colors, and any sRGB/P3 gamma
        // mapping silently mangles G and B (the known symptom: only the red
        // channel shows up). RGBAf preserves precision for low-count bins.
        var pixels = [Float](repeating: 0, count: 256 * 4)
        let bounds = CGRect(x: 0, y: 0, width: 256, height: 1)
        pixels.withUnsafeMutableBytes { buf in
            context.render(
                bins,
                toBitmap: buf.baseAddress!,
                rowBytes: 256 * 4 * MemoryLayout<Float>.size,
                bounds: bounds,
                format: CIFormat.RGBAf,
                colorSpace: nil
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
        // Compress the dynamic range with a gentle gamma so a single huge
        // spike (common in flat skies) doesn't squash everything else flat.
        let normPeak = peak > 0 ? peak : 1
        let gamma: CGFloat = 0.5
        for i in 0..<256 {
            r[i] = pow(r[i] / normPeak, gamma)
            g[i] = pow(g[i] / normPeak, gamma)
            b[i] = pow(b[i] / normPeak, gamma)
        }
        return HistogramData(r: r, g: g, b: b)
    }
}
