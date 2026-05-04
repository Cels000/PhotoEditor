// RENDER-01 color profile: source ICC profile inherited automatically from CIImage(data:options:);
// color-space conversion is handled by the RenderEngine CIContext working/output color spaces
// (extendedLinearSRGB working, displayP3 output — wired in Plan 01-04).
// Do NOT set .colorSpace in the options dict here — the source's tagged profile must propagate.

import CoreImage
import Foundation
import ImageIO
import Photos

/// Result of importing photo bytes — both a downsampled preview and the full-res
/// oriented source. `sourceData` is retained for re-loading on export if needed.
struct ImportedImage {
    let sourceData: Data
    let previewCIImage: CIImage
    let exportCIImage: CIImage
    let pixelSize: CGSize           // full-res oriented size
    let sourceAssetID: String?      // PHAsset localIdentifier; nil for picker-imported / no-asset paths
    /// Stable per-import identity. Used as the mask-cache key fallback when
    /// `sourceAssetID` is nil — distinct imports never collide, even within the
    /// lifetime of a single EditorViewModel.
    let sessionID: UUID = UUID()
}

enum ImageImportError: Error {
    case invalidImageData
    case phAssetUnavailable
}

/// Pure namespace that converts photo `Data` into an `ImportedImage`.
/// - Uses `CIImage(data:options:[.applyOrientationProperty: true])` (no UIImage detour).
/// - Calls `.oriented(forExifOrientation:)` explicitly to bake orientation geometrically
///   (per PITFALLS Pitfall 3 — `applyOrientationProperty` alone does not transform pixels).
/// - Downsamples preview to ≤1080px long edge per RENDER-03.
enum ImageImporter {

    static let previewMaxLongEdge: CGFloat = 1080

    static func importImage(from data: Data) throws -> ImportedImage {
        // Step 1: Decode using CIImage(data:options:). DO NOT use UIImage.
        let options: [CIImageOption: Any] = [
            .applyOrientationProperty: true
        ]
        guard let raw = CIImage(data: data, options: options) else {
            throw ImageImportError.invalidImageData
        }

        // Step 2: Read the EXIF orientation tag from the image properties.
        let exifOrientation = (raw.properties[kCGImagePropertyOrientation as String] as? Int32) ?? 1

        // Step 3: Bake orientation geometrically. After this call, the image's
        // pixel data is in the visually-correct orientation and downstream
        // code can treat orientation as 1 (default).
        let oriented = raw.oriented(forExifOrientation: exifOrientation)

        // Step 4: Downsample for preview (≤1080px long edge).
        let preview = downsample(oriented, maxLongEdge: previewMaxLongEdge)

        return ImportedImage(
            sourceData: data,
            previewCIImage: preview,
            exportCIImage: oriented,
            pixelSize: oriented.extent.size,
            sourceAssetID: nil
        )
    }

    /// Loads an ImportedImage from a PHAsset localIdentifier. Used by the library
    /// re-edit flow (LIB-02) and gracefully throws when the source has been
    /// deleted from Photos (LIB-05).
    static func importImage(fromAssetID assetID: String) async throws -> ImportedImage {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = fetch.firstObject else {
            throw ImageImportError.phAssetUnavailable
        }

        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.version = .current

        let data: Data = try await withCheckedThrowingContinuation { cont in
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset, options: options
            ) { data, _, _, info in
                if let data { cont.resume(returning: data); return }
                if (info?[PHImageErrorKey] as? Error) != nil {
                    cont.resume(throwing: ImageImportError.phAssetUnavailable); return
                }
                cont.resume(throwing: ImageImportError.phAssetUnavailable)
            }
        }

        // Reuse existing decode/orient/downsample path, then attach sourceAssetID.
        let base = try importImage(from: data)
        return ImportedImage(
            sourceData: base.sourceData,
            previewCIImage: base.previewCIImage,
            exportCIImage: base.exportCIImage,
            pixelSize: base.pixelSize,
            sourceAssetID: assetID
        )
    }

    /// Pure CIImage downsample — preserves color space, no UIKit round-trip.
    static func downsample(_ image: CIImage, maxLongEdge: CGFloat) -> CIImage {
        let extent = image.extent
        let longest = max(extent.width, extent.height)
        guard longest > maxLongEdge else { return image }
        let scale = maxLongEdge / longest
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        return image.transformed(by: transform)
    }
}
