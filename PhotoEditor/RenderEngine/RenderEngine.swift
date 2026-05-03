import CoreImage
import Foundation
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
}
