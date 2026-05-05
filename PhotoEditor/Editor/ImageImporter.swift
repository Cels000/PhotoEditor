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
    /// True when the source carries HDR / EDR content. Drives the export
    /// sheet's default for the HDR toggle so users don't have to remember.
    /// Set by `detectHDRContent` based on the source's color space tag,
    /// gain-map presence, or RAW flag (RAW always has EDR potential).
    let hasHDRContent: Bool
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

    static func importImage(from data: Data,
                            explicitEXIFOrientation: Int32? = nil) throws -> ImportedImage {
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
        // Caller's authoritative orientation wins (e.g., PHImageManager's
        // separate orientation parameter is more reliable than EXIF on
        // Photos-edited assets). Falls back to a CGImageSource read of the
        // container's EXIF tag for picker / file-import paths.
        let exifOrientation: Int32 = explicitEXIFOrientation
            ?? readEXIFOrientation(from: data)

        let oriented: CIImage
        let wasRaw: Bool
        if let rawFilter = CIRAWFilter(imageData: data, identifierHint: nil) {
            rawFilter.boostShadowAmount = 0.5
            rawFilter.extendedDynamicRangeAmount = 1.0
            if let rawOutput = rawFilter.outputImage {
                // CIRAWFilter outputs in sensor-native orientation (its
                // `orientation` property defaults to .up). Apply EXIF on top.
                oriented = rawOutput.oriented(forExifOrientation: exifOrientation)
                wasRaw = true
            } else {
                oriented = try standardDecode(data: data, exifOrientation: exifOrientation)
                wasRaw = false
            }
        } else {
            oriented = try standardDecode(data: data, exifOrientation: exifOrientation)
            wasRaw = false
        }

        // Downsample for preview (≤1080px long edge).
        let preview = downsample(oriented, maxLongEdge: previewMaxLongEdge)

        // HDR detection: RAW always carries EDR potential (the whole point of
        // shooting RAW). Otherwise read the source's color space and HEIF
        // metadata for HDR transfer-curve tags or gain-map presence.
        let hasHDR = wasRaw || detectHDRContent(in: data)

        return ImportedImage(
            sourceData: data,
            previewCIImage: preview,
            exportCIImage: oriented,
            pixelSize: oriented.extent.size,
            sourceAssetID: nil,
            wasRawSource: wasRaw,
            hasHDRContent: hasHDR
        )
    }

    /// Inspect the source bytes for HDR content. Two signals, either of which
    /// flips the bit:
    ///
    ///  1. The image's tagged color space uses an HDR transfer curve (HLG or
    ///     PQ) — Apple's iPhone-12-Pro-and-later default capture for stills.
    ///     Detected via `CGColorSpace.name` matching one of the known HDR
    ///     name constants.
    ///  2. The HEIF container carries an ISO 21496-1 gain map — Apple's
    ///     "HDR Photo" gain-map format that pairs an SDR base image with an
    ///     auxiliary image describing the HDR boost. Detected via
    ///     `kCGImagePropertyAuxiliaryDataType` for HDR gain map.
    ///
    /// False negatives are acceptable (user can flip the toggle manually);
    /// false positives are worse — they'd default users into HDR export of
    /// SDR content. So this errs conservative.
    private static func detectHDRContent(in data: Data) -> Bool {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return false }

        // Signal 1: HDR transfer-curve color space.
        if let cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil),
           let csName = cgImage.colorSpace?.name as String? {
            // Match all the HDR name constants Apple ships across iOS
            // versions. The HLG variants are the common iPhone capture path;
            // PQ shows up on imported HDR HEIC from other sources.
            let hdrNames: Set<String> = [
                CGColorSpace.itur_2100_HLG as String,
                CGColorSpace.itur_2100_PQ as String,
                CGColorSpace.displayP3_HLG as String,
                CGColorSpace.displayP3_PQ as String,
                CGColorSpace.extendedLinearDisplayP3 as String,
                CGColorSpace.extendedLinearITUR_2020 as String
            ]
            if hdrNames.contains(csName) { return true }
        }

        // Signal 2: Apple HDR gain map auxiliary data. iOS 14.1+ exposes the
        // gain map as kCGImageAuxiliaryDataTypeHDRGainMap on iPhone HDR HEIC
        // stills. Presence (any non-nil dict) is enough — we don't read the
        // contents, just use it as the HDR yes/no signal.
        if CGImageSourceCopyAuxiliaryDataInfoAtIndex(
            src, 0, kCGImageAuxiliaryDataTypeHDRGainMap
        ) != nil {
            return true
        }

        return false
    }

    /// Standard (non-RAW) decode path. Deliberately does NOT pass
    /// `.applyOrientationProperty: true` — its effect on the post-decode
    /// `raw.properties` orientation key has been observed inconsistently
    /// across iOS versions / capture sources (sometimes it bakes the rotation
    /// AND clears the property to 1, sometimes it leaves the property at the
    /// source EXIF, sometimes it doesn't bake at all). The double-rotate
    /// vs. no-rotate ambiguity is what was leaving portrait photos sideways.
    ///
    /// Without the option, `CIImage(data:)` returns pixels in sensor-storage
    /// orientation. We then read the source EXIF directly from the container
    /// (always returns the original source value, no Core Image ambiguity)
    /// and apply via `.oriented(forExifOrientation:)`. Predictable.
    private static func standardDecode(data: Data, exifOrientation: Int32) throws -> CIImage {
        guard let raw = CIImage(data: data) else {
            throw ImageImportError.invalidImageData
        }
        return raw.oriented(forExifOrientation: exifOrientation)
    }

    /// Reads EXIF orientation from a container's metadata via CGImageSource.
    /// Used by the RAW branch where CIRAWFilter's output doesn't expose the
    /// source's properties dict. Returns 1 (Up) when missing or unreadable.
    private static func readEXIFOrientation(from data: Data) -> Int32 {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let o = props[kCGImagePropertyOrientation] as? Int32
        else { return 1 }
        return o
    }

    /// Loads an ImportedImage from a PHAsset localIdentifier. Used by the library
    /// re-edit flow (LIB-02) and gracefully throws when the source has been
    /// deleted from Photos (LIB-05).
    ///
    /// ProRAW gamut: PHImageManager's `requestImageDataAndOrientation` returns
    /// the rendered HEIC for ProRAW assets (a HEIC+DNG bundle), not the DNG —
    /// so a naive re-edit lost the wide-gamut RAW data the user shot for. We
    /// probe `PHAssetResource.assetResources(for:)` first for an
    /// `.alternatePhoto` resource with the Adobe DNG UTI; when present, fetch
    /// the DNG bytes via `PHAssetResourceManager` so the editor reopens with
    /// full RAW latitude. Falls back to the standard image-data path for HEIC,
    /// JPEG, and any RAW formats Photos doesn't expose as alternates.
    static func importImage(fromAssetID assetID: String) async throws -> ImportedImage {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = fetch.firstObject else {
            throw ImageImportError.phAssetUnavailable
        }

        let data: Data
        let exifOverride: Int32?
        if let rawData = try? await fetchRawAlternate(for: asset) {
            data = rawData
            exifOverride = nil  // DNG container carries its own EXIF
        } else {
            let (d, o) = try await fetchImageDataAndOrientation(for: asset)
            data = d
            exifOverride = Int32(o.rawValue)
        }

        // Reuse existing decode/orient/downsample path, then attach sourceAssetID.
        let base = try importImage(from: data, explicitEXIFOrientation: exifOverride)
        return ImportedImage(
            sourceData: base.sourceData,
            previewCIImage: base.previewCIImage,
            exportCIImage: base.exportCIImage,
            pixelSize: base.pixelSize,
            sourceAssetID: assetID,
            wasRawSource: base.wasRawSource,
            hasHDRContent: base.hasHDRContent
        )
    }

    /// Try to fetch a RAW DNG resource attached to the asset. Returns nil if
    /// the asset has no DNG alternate (most assets — JPEG, HEIC, traditional
    /// RAW formats Photos doesn't bundle as alternates). Throws only on a
    /// genuine resource-fetch error so the caller can fall back.
    private static func fetchRawAlternate(for asset: PHAsset) async throws -> Data? {
        let resources = PHAssetResource.assetResources(for: asset)
        // ProRAW assets carry the DNG as `.alternatePhoto` with UTI
        // `com.adobe.raw-image`. The primary `.photo` resource is the rendered
        // HEIC. We deliberately prefer the DNG even when the user has saved
        // edits in Photos — the editor wants the source of truth.
        guard let dng = resources.first(where: {
            $0.type == .alternatePhoto &&
            $0.uniformTypeIdentifier == "com.adobe.raw-image"
        }) else { return nil }

        let opts = PHAssetResourceRequestOptions()
        opts.isNetworkAccessAllowed = true
        return try await withCheckedThrowingContinuation { cont in
            var buffer = Data()
            PHAssetResourceManager.default().requestData(
                for: dng,
                options: opts,
                dataReceivedHandler: { chunk in buffer.append(chunk) },
                completionHandler: { error in
                    if let error { cont.resume(throwing: error); return }
                    cont.resume(returning: buffer)
                }
            )
        }
    }

    /// Standard PHImageManager fetch — used for HEIC, JPEG, and any asset
    /// without a DNG alternate. Returns the user's *current* version (Photos
    /// edits applied) since that matches what they see in the Photos app.
    /// Also returns the orientation parameter from the callback — Photos.app
    /// strips/overwrites EXIF on edited assets, so the callback orientation
    /// is the authoritative signal.
    private static func fetchImageDataAndOrientation(
        for asset: PHAsset
    ) async throws -> (Data, CGImagePropertyOrientation) {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.version = .current

        return try await withCheckedThrowingContinuation { cont in
            PHImageManager.default().requestImageDataAndOrientation(
                for: asset, options: options
            ) { data, _, orientation, info in
                if let data { cont.resume(returning: (data, orientation)); return }
                if (info?[PHImageErrorKey] as? Error) != nil {
                    cont.resume(throwing: ImageImportError.phAssetUnavailable); return
                }
                cont.resume(throwing: ImageImportError.phAssetUnavailable)
            }
        }
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
