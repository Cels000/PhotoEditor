import CoreImage
import Foundation
import ImageIO
import Metal

enum RenderError: Error {
    case noMetalDevice
    case outputEmpty
}

/// Actor owning both Metal-backed CIContexts. One actor instance per app session.
/// - `previewContext` is used for live slider previews (caller passes in a ≤1080 px source).
/// - `exportContext` is used only on the export path (full-resolution, called from save flow).
/// Both contexts use `extendedLinearSRGB` working space and Display P3 output, with
/// `.useSoftwareRenderer: false` set explicitly to satisfy RENDER-05.
actor RenderEngine {

    private let previewContext: CIContext
    private let exportContext: CIContext
    /// HDR-capable export context. Same Metal device, same working space, but
    /// outputs into `extendedLinearDisplayP3` so values >1.0 (EDR highlights
    /// from ProRAW or scenes that pushed past clip in linear working space)
    /// survive into the encoded HEIC instead of being clamped to displayP3.
    /// Only used by the HDR export branch; preview always renders SDR.
    private let hdrExportContext: CIContext

    /// Caller-side preview cap. The caller is responsible for downsampling sources
    /// to this size before invoking `renderPreview`. Documented here so the constant
    /// has a single source of truth.
    nonisolated static let previewMaxLongEdge: CGFloat = 1080

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RenderError.noMetalDevice
        }

        let workingSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        let outputSpace = CGColorSpace(name: CGColorSpace.displayP3)!

        let options: [CIContextOption: Any] = [
            .workingColorSpace: workingSpace,
            .outputColorSpace: outputSpace,
            .useSoftwareRenderer: false
        ]

        self.previewContext = CIContext(mtlDevice: device, options: options)
        self.exportContext = CIContext(mtlDevice: device, options: options)

        let hdrOutputSpace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
        let hdrOptions: [CIContextOption: Any] = [
            .workingColorSpace: workingSpace,
            .outputColorSpace: hdrOutputSpace,
            .useSoftwareRenderer: false
        ]
        self.hdrExportContext = CIContext(mtlDevice: device, options: hdrOptions)
    }

    /// Preview render. Caller MUST pass a source already downsampled to
    /// ≤`previewMaxLongEdge` px (typically the `previewCIImage` from `ImageImporter`).
    func renderPreview(stack: AdjustmentStack, source: CIImage, cubeResolver: CubeResolver? = nil) throws -> CGImage {
        let chain = PipelineBuilder.build(stack: stack, source: source, cubeResolver: cubeResolver)
        guard let cg = previewContext.createCGImage(chain, from: chain.extent) else {
            throw RenderError.outputEmpty
        }
        return cg
    }

    /// Full-resolution export render. Called only from the save flow.
    func renderExport(stack: AdjustmentStack, source: CIImage, cubeResolver: CubeResolver? = nil) throws -> CGImage {
        let chain = PipelineBuilder.build(stack: stack, source: source, cubeResolver: cubeResolver)
        guard let cg = exportContext.createCGImage(chain, from: chain.extent) else {
            throw RenderError.outputEmpty
        }
        return cg
    }

    /// Preview render for the dual-stack EditDocument with optional mask result.
    /// When `document.mask == nil` or `maskResult == nil`, this is identical to
    /// renderPreview(stack: document.subjectStack, ...). Otherwise PipelineBuilder
    /// composites subject + background passes via CIBlendWithMask.
    func renderPreview(document: EditDocument,
                       source: CIImage,
                       cubeResolver: CubeResolver? = nil,
                       maskResult: SubjectMaskResult? = nil) throws -> CGImage {
        let chain = PipelineBuilder.build(
            document: document,
            source: source,
            cubeResolver: cubeResolver,
            maskResult: maskResult
        )
        guard let cg = previewContext.createCGImage(chain, from: chain.extent) else {
            throw RenderError.outputEmpty
        }
        return cg
    }

    /// Full-resolution export render for the EditDocument.
    func renderExport(document: EditDocument,
                      source: CIImage,
                      cubeResolver: CubeResolver? = nil,
                      maskResult: SubjectMaskResult? = nil) throws -> CGImage {
        let chain = PipelineBuilder.build(
            document: document,
            source: source,
            cubeResolver: cubeResolver,
            maskResult: maskResult
        )
        guard let cg = exportContext.createCGImage(chain, from: chain.extent) else {
            throw RenderError.outputEmpty
        }
        return cg
    }

    /// Build the full pipeline CIImage and encode it as 10-bit HLG-tagged HEIC.
    /// Working space stays `extendedLinearSRGB` so EDR highlight values >1.0
    /// survive the chain; the encoder converts that linear extended-range
    /// buffer into the HLG transfer curve as it writes the HEIC bytes. The
    /// resulting file is recognized by Photos / Preview as HDR and lights up
    /// the EDR display.
    ///
    /// `targetLongEdge` lets the caller request a downscale at encode time
    /// (so HDR export still honors the size preset). Pass `nil` for full-res.
    func renderExportHDRData(document: EditDocument,
                             source: CIImage,
                             cubeResolver: CubeResolver? = nil,
                             maskResult: SubjectMaskResult? = nil,
                             targetLongEdge: Int?,
                             quality: Double) throws -> Data {
        var chain = PipelineBuilder.build(
            document: document,
            source: source,
            cubeResolver: cubeResolver,
            maskResult: maskResult
        )

        if let targetLongEdge {
            let extent = chain.extent
            let longEdge = max(extent.width, extent.height)
            let scale = Double(targetLongEdge) / Double(longEdge)
            if scale < 1.0 {
                chain = chain.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }
        }

        guard let hlgSpace = CGColorSpace(name: CGColorSpace.displayP3_HLG) else {
            throw RenderError.outputEmpty
        }
        let qualityKey = CIImageRepresentationOption(
            rawValue: kCGImageDestinationLossyCompressionQuality as String
        )
        let opts: [CIImageRepresentationOption: Any] = [
            qualityKey: max(0, min(1, quality))
        ]
        return try hdrExportContext.heif10Representation(of: chain,
                                                         colorSpace: hlgSpace,
                                                         options: opts)
    }
}
