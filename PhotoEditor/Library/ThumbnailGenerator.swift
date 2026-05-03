import CoreImage
import Foundation
import UIKit

enum ThumbnailGeneratorError: Error {
    case renderFailed
    case encodeFailed
}

/// Pure namespace producing 400x400 JPEG thumbnails of an edited image.
/// Runs on the caller's task; the caller (EditorViewModel) wraps this in a
/// detached background Task so the main actor never blocks on render.
enum ThumbnailGenerator {

    static let thumbnailEdge: CGFloat = 400
    static let jpegQuality: CGFloat = 0.6     // ~30 KB target for a 400px square

    /// Renders `stack` against `source`, center-crops to square, scales to 400px,
    /// and returns JPEG Data. The render uses `engine.renderPreview` which
    /// already applies the configured working/output color spaces.
    static func makeThumbnail(stack: AdjustmentStack,
                              source: CIImage,
                              engine: RenderEngine,
                              cubeResolver: CubeResolver?) async throws -> Data {
        // 1. Render the edited image (preview path is fine — caller passes preview-sized source).
        let cg: CGImage
        do {
            cg = try await engine.renderPreview(stack: stack, source: source, cubeResolver: cubeResolver)
        } catch {
            throw ThumbnailGeneratorError.renderFailed
        }

        // 2. Convert to UIImage so we can use UIGraphicsImageRenderer for square crop+scale.
        let rendered = UIImage(cgImage: cg)
        let size = CGSize(width: rendered.size.width, height: rendered.size.height)
        let edge = min(size.width, size.height)
        let originX = (size.width - edge) / 2
        let originY = (size.height - edge) / 2
        let cropRect = CGRect(x: originX, y: originY, width: edge, height: edge)

        // 3. Crop centered square then scale to 400x400.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let target = CGSize(width: thumbnailEdge, height: thumbnailEdge)
        let thumb = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            // Draw the cropped square scaled to fill 400x400.
            let drawRect = CGRect(origin: .zero, size: target)
            let scaleX = target.width / cropRect.width
            let scaleY = target.height / cropRect.height
            let translatedRect = CGRect(
                x: -cropRect.origin.x * scaleX,
                y: -cropRect.origin.y * scaleY,
                width: size.width * scaleX,
                height: size.height * scaleY
            )
            rendered.draw(in: translatedRect)
            _ = drawRect   // silence unused warning if compiler complains
        }

        // 4. JPEG encode.
        guard let data = thumb.jpegData(compressionQuality: jpegQuality) else {
            throw ThumbnailGeneratorError.encodeFailed
        }
        return data
    }
}
