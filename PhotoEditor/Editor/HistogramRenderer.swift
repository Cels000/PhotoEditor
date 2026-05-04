import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

/// Pure utility that produces a small RGB histogram CGImage from a post-pipeline
/// CGImage (the committed preview frame). Uses CIAreaHistogram +
/// CIHistogramDisplayFilter — Apple-blessed for exactly this use case, ~1ms on a
/// 1080px preview, no third-party deps.
///
/// Operates on the committed CGImage (Display P3) — what the user actually
/// sees — rather than the pre-CIContext linear chain, so the histogram reflects
/// monitor-relative clipping (which is what scopes are for).
///
/// Caller owns the CIContext lifecycle; we never spin up a fresh CIContext here
/// (that would be ~50ms per call — unacceptable on every render commit).
enum HistogramRenderer {
    /// Render a 256x64 RGBA histogram bitmap from the supplied post-pipeline image.
    /// Returns nil on any filter or CIContext failure; never throws.
    static func render(postPipeline cg: CGImage, context: CIContext) -> CGImage? {
        let input = CIImage(cgImage: cg)

        let area = CIFilter.areaHistogram()
        area.inputImage = input
        area.extent = input.extent
        area.count = 256
        area.scale = 1.0
        guard let histogramData = area.outputImage else { return nil }

        let display = CIFilter.histogramDisplay()
        display.inputImage = histogramData
        display.height = 64
        display.highLimit = 1.0
        display.lowLimit = 0.0
        guard let bars = display.outputImage else { return nil }

        return context.createCGImage(bars, from: bars.extent)
    }
}
