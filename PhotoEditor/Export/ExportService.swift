// ExportService.swift
// Pure encoder: (CGImage, sourceMetadata, ExportOptions, sourceColorSpace) -> Data
//
// Design notes:
//   PITFALL #16: We encode via CGImageDestination, NOT UIImage.jpegData or UIImage.pngData.
//     CGImageDestination preserves the ICC color profile embedded in the CGImage and gives
//     us full control over the properties / metadata dictionary.
//   PITFALL #4: Only named CGColorSpace profiles are used (displayP3, sRGB).
//     CGColorSpaceCreateDeviceRGB is explicitly forbidden — device-RGB discards the profile.
//   PITFALL #3: Orientation is baked at import (ImageImporter). We still write
//     kCGImagePropertyOrientation = 1 so downstream tools (Photos, web viewers) don't
//     apply an additional rotation.

import Foundation
import ImageIO
import CoreGraphics
import CoreImage
import UniformTypeIdentifiers

// MARK: - ExportService

/// Namespace for the pure image-encoding pipeline.
///
/// Entry point: `ExportService.encode(cgImage:sourceProperties:colorSpace:options:)`.
///
/// This type is non-isolated. It is the caller's responsibility to dispatch off the main
/// thread (e.g. `Task.detached(priority: .userInitiated) { try await ... }`).
///
/// This encoder does NOT call PHPhotoLibrary or UIActivityViewController.
/// Saving/sharing is a separate concern handled by the caller (plan 05-03).
public enum ExportService {

    // MARK: - Error

    public enum Error: Swift.Error, LocalizedError {
        case encodeFailed
        case unsupportedFormat
        case resizeFailed

        public var errorDescription: String? {
            switch self {
            case .encodeFailed:       return "Image encoding failed. The destination could not be finalized."
            case .unsupportedFormat:  return "The requested export format is not supported on this device."
            case .resizeFailed:       return "Image resize failed during export."
            }
        }
    }

    // MARK: - Public API

    /// Encode a rendered CGImage to `Data` according to `options`.
    ///
    /// - Parameters:
    ///   - cgImage:           The fully rendered, rotation-baked bitmap to encode.
    ///   - sourceProperties:  Properties dict from `CGImageSourceCopyPropertiesAtIndex` on the
    ///                        source asset (may be empty `[:]` for programmatic images).
    ///   - colorSpace:        The source / desired output color space (e.g. Display P3).
    ///                        Honored as: P3 in → P3 out; sRGB in → sRGB out.
    ///                        Pass `nil` to fall back to Display P3 → sRGB chain.
    ///   - options:           Format, size, and quality settings.
    /// - Returns: Encoded image bytes ready to save or share.
    /// - Throws: `ExportService.Error`
    public static func encode(
        cgImage: CGImage,
        sourceProperties: [CFString: Any],
        colorSpace: CGColorSpace?,
        options: ExportOptions
    ) throws -> Data {

        // ── Step 1: Tag the CGImage with the output color space ──────────────────
        // PITFALL #4: Use named profiles. Honor source profile preference.
        // P3 in → P3 out; sRGB in → sRGB out. Never CGColorSpaceCreateDeviceRGB.
        let outputCS: CGColorSpace = colorSpace
            ?? CGColorSpace(name: CGColorSpace.displayP3)
            ?? CGColorSpace(name: CGColorSpace.sRGB)!

        guard let tagged = cgImage.copy(colorSpace: outputCS) else {
            throw Error.encodeFailed
        }

        // ── Step 2: Resize if needed ──────────────────────────────────────────────
        // Derive the source long edge from the (tagged) bitmap dimensions.
        let srcW = tagged.width
        let srcH = tagged.height
        let sourceLongEdge = max(srcW, srcH)
        let targetLongEdge = options.size.resolve(sourceLongEdge: sourceLongEdge)

        let resizedCG: CGImage
        if abs(targetLongEdge - sourceLongEdge) < 1 {
            // No resize needed (within 0.5 px tolerance — integer comparison is fine here).
            resizedCG = tagged
        } else {
            // Downsample via Lanczos (CILanczosScaleTransform baked in CIImage rendering).
            // We NEVER upscale: resolve() already clamps to sourceLongEdge for .full,
            // and the `abs(...) < 1` guard above catches the exact-match case.
            let scale = Double(targetLongEdge) / Double(sourceLongEdge)
            guard scale <= 1.0 else {
                // Safety: ExportSize.resolve should never return > sourceLongEdge, but guard anyway.
                resizedCG = tagged
                // (Not an error; just skip upscale per spec.)
                _ = scale  // silence unused-variable warning on the early-return path
                return try finalize(resizedCG: tagged, sourceProperties: sourceProperties,
                                    options: options, outputCS: outputCS)
            }

            let ci = CIImage(cgImage: tagged)
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            let scaled = ci.transformed(by: transform)

            // CIContext: workingColorSpace = extendedLinearSRGB for precision; output in outputCS.
            let ctx = CIContext(options: [
                .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
                    ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                .outputColorSpace: outputCS
            ])

            guard let rendered = ctx.createCGImage(scaled, from: scaled.extent) else {
                throw Error.resizeFailed
            }
            resizedCG = rendered
        }

        return try finalize(resizedCG: resizedCG, sourceProperties: sourceProperties,
                            options: options, outputCS: outputCS)
    }

    // MARK: - Private Helpers

    /// Resolve the UTI string to use for encoding. Falls back HEIC → JPEG on older simulators.
    private static func resolveUTI(for format: ExportFormat) -> String {
        guard format == .heic else {
            return format.uti
        }
        // Probe HEIC support by attempting to create a destination to /dev/null.
        // If the encoder isn't present (old simulator) the call returns nil → fall back to JPEG.
        // Per CONTEXT decisions: "fallback to JPEG if device doesn't support HEIC".
        let probe = CGImageDestinationCreateWithData(
            NSMutableData() as CFMutableData,
            UTType.heic.identifier as CFString,
            1,
            nil
        )
        return probe != nil ? UTType.heic.identifier : UTType.jpeg.identifier
    }

    /// Build the per-image properties dictionary.
    ///
    /// Rules:
    ///  - kCGImagePropertyOrientation = 1 always (PITFALL #3: baked orientation).
    ///  - kCGImageDestinationLossyCompressionQuality set only for lossy formats.
    ///  - kCGImagePropertyTIFFDictionary carried through; its orientation key overwritten to 1.
    ///  - kCGImagePropertyExifDictionary carried through as-is.
    ///  - kCGImagePropertyGPSDictionary  → NOT copied (GPS strip, by design).
    ///  - kCGImagePropertyIPTCDictionary → NOT copied (IPTC author/contact strip, by design).
    private static func buildProperties(
        sourceProperties: [CFString: Any],
        format: ExportFormat,
        quality: Double
    ) -> [CFString: Any] {
        var props: [CFString: Any] = [
            // PITFALL #3: orientation baked at import; downstream tools must see Up = 1.
            kCGImagePropertyOrientation: 1
        ]

        // Quality — only for lossy formats. PNG branch deliberately omits this key.
        if format.supportsQuality {
            props[kCGImageDestinationLossyCompressionQuality] = quality
        }

        // EXIF passthrough: TIFF dictionary (orientation, creation date, camera model).
        if let tiff = sourceProperties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            var sanitizedTiff = tiff
            // Overwrite the TIFF orientation key to 1 (Up) — bitmap is already rotated.
            sanitizedTiff[kCGImagePropertyTIFFOrientation] = 1
            props[kCGImagePropertyTIFFDictionary] = sanitizedTiff
        }

        // EXIF passthrough: Exif dictionary (capture metadata — shutter, ISO, focal length).
        if let exif = sourceProperties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            props[kCGImagePropertyExifDictionary] = exif
        }

        // NOTE: kCGImagePropertyGPSDictionary is deliberately NOT copied.
        //   GPS strip: location data is identifying metadata and must not be exported by default.
        //   If the user explicitly requests GPS export in a future version, add opt-in here.

        // NOTE: kCGImagePropertyIPTCDictionary is deliberately NOT copied.
        //   IPTC author/contact strip: same privacy rationale as GPS.

        return props
    }

    /// Core CGImageDestination encode + finalize call.
    private static func finalize(
        resizedCG: CGImage,
        sourceProperties: [CFString: Any],
        options: ExportOptions,
        outputCS: CGColorSpace
    ) throws -> Data {
        // ── Step 3: Resolve UTI ───────────────────────────────────────────────────
        let uti = resolveUTI(for: options.format)

        // ── Step 4: Build properties ──────────────────────────────────────────────
        let props = buildProperties(
            sourceProperties: sourceProperties,
            format: options.format,
            quality: options.quality
        )

        // ── Step 5: Create destination, add image, finalize ───────────────────────
        // PITFALL #16: CGImageDestination (not UIImage) preserves color profile and
        // lets us precisely control the metadata dictionary.
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData,
            uti as CFString,
            1,
            nil
        ) else {
            throw Error.encodeFailed
        }

        CGImageDestinationAddImage(dest, resizedCG, props as CFDictionary)

        guard CGImageDestinationFinalize(dest) else {
            throw Error.encodeFailed
        }

        return data as Data
    }
}
