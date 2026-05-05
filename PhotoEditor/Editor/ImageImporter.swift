// RENDER-01 color profile: source ICC profile inherited automatically from CIImage(data:options:);
// color-space conversion is handled by the RenderEngine CIContext working/output color spaces
// (extendedLinearSRGB working, displayP3 output — wired in Plan 01-04).
// Do NOT set .colorSpace in the options dict here — the source's tagged profile must propagate.
//
// RAW/ProRAW: when the source bytes are a recognized RAW format (DNG including
// Apple ProRAW, plus all the CR2/NEF/ARW/etc. formats Core Image's RAW pipeline
// supports), we route through `CIRAWFilter` so the user gets the actual reason
// to shoot RAW — extended highlight latitude and shadow recoverability — rather
// than a default-rendered demosaic. Falls back to the standard `CIImage(data:)`
// path when the bytes aren't RAW.

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
    /// True when the import bytes were a recognized RAW format and decoded
    /// through CIRAWFilter. Export uses this to override the embedded preview's
    /// (often sRGB) ICC tag and force Display P3 output — RAW captures wide
    /// gamut data, and tagging the export with the embedded JPEG preview's
    /// narrow gamut throws away exactly the fidelity the user shot RAW for.
    let wasRawSource: Bool
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
        // EXIF orientation lives in the container metadata for both standard
        // and RAW formats. CIRAWFilter's outputImage doesn't carry .properties
        // reliably, so we read orientation up-front from the bytes and bake
        // it geometrically below regardless of decode path.
        let exifOrientation: Int32 = {
            guard let src = CGImageSourceCreateWithData(data as CFData, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                  let o = props[kCGImagePropertyOrientation] as? Int32
            else { return 1 }
            return o
        }()

        // RAW path: CIRAWFilter init returns nil when the bytes aren't a
        // recognized RAW format, so we use it as the format probe. ProRAW DNG
        // and traditional RAW both flow through here.
        //
        // boostShadowAmount (0...1, default ~0): lifts shadows during demosaic
        // so the latitude the user shot RAW to keep is actually visible in the
        // editor without them having to drag the shadow slider every time.
        // Conservative 0.5 — leaves room for further adjustment, and isn't so
        // aggressive that it crushes mid-tone contrast on flat scenes.
        //
        // extendedDynamicRangeAmount (iOS 14.1+, 0...2): unlocks the EDR
        // highlight headroom that ProRAW captures. 1.0 = full extended range
        // mapped into the working [0,1] domain. No-op on traditional RAW
        // formats that don't carry EDR data.
        let oriented: CIImage
        let wasRaw: Bool
        if let rawFilter = CIRAWFilter(imageData: data, identifierHint: nil) {
            rawFilter.boostShadowAmount = 0.5
            rawFilter.extendedDynamicRangeAmount = 1.0
            if let rawOutput = rawFilter.outputImage {
                oriented = rawOutput.oriented(forExifOrientation: exifOrientation)
                wasRaw = true
            } else {
                // CIRAWFilter created but couldn't produce output (corrupt /
                // partially-supported variant) — fall back to the standard
                // decoder, which usually has a baseline preview embedded.
                oriented = try standardDecode(data: data, exifOrientation: exifOrientation)
                wasRaw = false
            }
        } else {
            oriented = try standardDecode(data: data, exifOrientation: exifOrientation)
            wasRaw = false
        }

        // Downsample for preview (≤1080px long edge).
        let preview = downsample(oriented, maxLongEdge: previewMaxLongEdge)

        return ImportedImage(
            sourceData: data,
            previewCIImage: preview,
            exportCIImage: oriented,
            pixelSize: oriented.extent.size,
            sourceAssetID: nil,
            wasRawSource: wasRaw
        )
    }

    /// Standard (non-RAW) decode path. Kept separate so the RAW branch can
    /// fall back to it without duplicating the decode + orient logic.
    private static func standardDecode(data: Data, exifOrientation: Int32) throws -> CIImage {
        let options: [CIImageOption: Any] = [.applyOrientationProperty: true]
        guard let raw = CIImage(data: data, options: options) else {
            throw ImageImportError.invalidImageData
        }
        return raw.oriented(forExifOrientation: exifOrientation)
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
            sourceAssetID: assetID,
            wasRawSource: base.wasRawSource
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
