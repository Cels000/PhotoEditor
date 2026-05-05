import Foundation
import UniformTypeIdentifiers

// MARK: - ExportFormat

/// The file format for exported images.
public enum ExportFormat: String, Codable, Hashable, CaseIterable {
    case jpeg
    case heic
    case png

    /// The system UTType identifier for this format. Canonical strings owned by the OS.
    public var uti: String {
        switch self {
        case .jpeg: return UTType.jpeg.identifier
        case .heic: return UTType.heic.identifier
        case .png:  return UTType.png.identifier
        }
    }

    /// File extension for this format.
    public var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .png:  return "png"
        }
    }

    /// Whether this format supports a lossy quality setting.
    /// PNG is always lossless — upstream UI uses this to hide the quality slider (EXPORT-05).
    public var supportsQuality: Bool {
        switch self {
        case .jpeg, .heic: return true
        case .png:         return false
        }
    }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .jpeg: return "JPEG"
        case .heic: return "HEIC"
        case .png:  return "PNG"
        }
    }
}

// MARK: - ExportSize

/// The output resolution preset for exported images.
public enum ExportSize: Codable, Hashable {
    /// Full resolution — no resize, long edge equals source long edge.
    case full
    /// Web preset — long edge capped at 2048 px.
    case web
    /// Story / social preset — long edge capped at 1080 px.
    case story
    /// Custom long edge. Clamped to 256...8192 at resolve time.
    case custom(longEdge: Int)

    /// Resolve the output long edge in pixels for a given source long edge.
    /// This is the single clamp site for the 256...8192 rule.
    /// Downstream plans MUST call this rather than re-clamping independently.
    public func resolve(sourceLongEdge: Int) -> Int {
        switch self {
        case .full:              return sourceLongEdge
        case .web:               return 2048
        case .story:             return 1080
        case .custom(let edge):  return max(256, min(8192, edge))
        }
    }

    /// Human-readable display name.
    public var displayName: String {
        switch self {
        case .full:   return "Full"
        case .web:    return "Web (2048)"
        case .story:  return "Story (1080)"
        case .custom: return "Custom"
        }
    }
}

// MARK: - ExportOptions

/// The canonical export configuration model consumed by every Phase 5 plan.
///
/// Defaults satisfy requirements:
/// - EXPORT-03: HEIC format default (best size/quality tradeoff).
/// - EXPORT-04: Full resolution default (no unintentional downscaling).
/// - EXPORT-05: Quality 0.85 default; slider hidden for PNG via `format.supportsQuality`.
public struct ExportOptions: Codable, Equatable {
    public var format: ExportFormat
    public var size: ExportSize
    /// Compression quality in 0.0...1.0. Only meaningful when `format.supportsQuality` is true.
    public var quality: Double
    /// HDR HEIC export. When true and `format == .heic`, the export pipeline:
    ///   1. Renders into an extended-linear Display P3 working buffer (no
    ///      highlight clamp), so EDR data from ProRAW survives end-to-end.
    ///   2. Encodes 10-bit HEIC tagged with `displayP3_HLG`, which iOS
    ///      Photos and other HDR-aware viewers light up on the EDR display.
    /// Falls back to standard SDR encode if format != heic. Honored only by
    /// the editor export path; camera capture stays SDR for now.
    public var hdr: Bool

    public init(
        format: ExportFormat = .heic,
        size: ExportSize = .full,
        quality: Double = 0.85,
        hdr: Bool = false
    ) {
        self.format = format
        self.size = size
        self.quality = quality
        self.hdr = hdr
    }

    /// Default export options: HEIC, full resolution, quality 0.85.
    /// Referenced by EXPORT-03, EXPORT-04, EXPORT-05.
    public static let `default` = ExportOptions()
}
