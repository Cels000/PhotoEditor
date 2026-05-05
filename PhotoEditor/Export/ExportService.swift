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

        // ── Step 1: Resolve the desired output color space ───────────────────────
        // PITFALL #4: Use named profiles. Honor source profile preference.
        // P3 in → P3 out; sRGB in → sRGB out. Never CGColorSpaceCreateDeviceRGB.
        let outputCS: CGColorSpace = colorSpace
            ?? CGColorSpace(name: CGColorSpace.displayP3)
            ?? CGColorSpace(name: CGColorSpace.sRGB)!

        // Wide-gamut correctness: RenderEngine always emits Display P3. If the
        // caller asks for a different output CS (e.g. sRGB to match a non-P3
        // source), the bitmap's pixel values must be COLOR-CONVERTED, not just
        // re-tagged. `CGImage.copy(colorSpace:)` only re-tags — using it across
        // a CS change tags P3 pixel data as sRGB and the file decodes wrong
        // (Photos shows desaturated / shifted color). Convert via CIContext so
        // the conversion is gamut-mapped through extendedLinearSRGB.
        let needsColorConversion: Bool = {
            guard let inName = cgImage.colorSpace?.name else { return true }
            return inName != outputCS.name
        }()

        // ── Step 2: Resize if needed ──────────────────────────────────────────────
        let srcW = cgImage.width
        let srcH = cgImage.height
        let sourceLongEdge = max(srcW, srcH)
        let targetLongEdge = options.size.resolve(sourceLongEdge: sourceLongEdge)
        // resolve() already clamps to sourceLongEdge for .full, but guard anyway
        // so we never upscale via Lanczos.
        let scale = max(0.0, min(1.0, Double(targetLongEdge) / Double(sourceLongEdge)))
        let needsResize = abs(targetLongEdge - sourceLongEdge) >= 1 && scale < 1.0

        let resizedCG: CGImage
        if !needsResize && !needsColorConversion {
            // Fast path: bitmap already in target CS at target size.
            resizedCG = cgImage
        } else {
            // Lanczos downsample and/or color-managed conversion via CIContext.
            // workingColorSpace = extendedLinearSRGB for precision (gamut-maps
            // P3 → sRGB correctly); outputColorSpace = the requested outputCS.
            let ci = CIImage(cgImage: cgImage)
            let scaled = needsResize
                ? ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                : ci

            let ctx = CIContext(options: [
                .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
                    ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                .outputColorSpace: outputCS
            ])

            guard let rendered = ctx.createCGImage(scaled, from: scaled.extent,
                                                   format: .RGBA8,
                                                   colorSpace: outputCS) else {
                throw needsResize ? Error.resizeFailed : Error.encodeFailed
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
