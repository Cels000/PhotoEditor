import Foundation
import Photos

/// Saves pre-encoded image `Data` to the user's Photos library.
///
/// Uses `PHAssetCreationRequest.addResource(with: .photo, data:)` — NOT
/// `PHAssetChangeRequest.creationRequestForAsset(from: UIImage)`, which
/// re-encodes via UIImage and strips our ICC profile / quality choices
/// (PITFALL #16: UIImage round-trip forces JPEG re-encode and drops P3 profile).
///
/// The caller (e.g. ExportService / EditorViewModel) owns the encoded bytes;
/// PhotoSaver only writes them verbatim to the library.
public enum PhotoSaver {

    // MARK: - Errors

    public enum Error: Swift.Error {
        /// The user denied Photos write permission.
        case permissionDenied
        /// `PHPhotoLibrary.performChanges` failed. The underlying error is from Photos.
        case saveFailed(underlying: Swift.Error?)
    }

    // MARK: - Public API

    /// Saves pre-encoded image data to the Photos library.
    ///
    /// - Parameters:
    ///   - encodedData: The raw encoded bytes produced by `ExportService.encode`.
    ///   - format: The format that was used to encode `encodedData`, used to set
    ///     `PHAssetResourceCreationOptions.uniformTypeIdentifier` so Photos stores
    ///     the resource with the correct UTI (HEIC / JPEG / PNG).
    ///
    /// - Throws: `PhotoSaver.Error.permissionDenied` if the user has not granted
    ///   add-only (or full) access. Throws `PhotoSaver.Error.saveFailed` on any
    ///   Photos write error.
    ///
    /// - Note: Accepts both `.authorized` and `.limited` status as success.
    ///   PITFALL #17: `.limited` allows asset creation — rejecting it would silently
    ///   fail for users who granted limited library access.
    public static func save(encodedData: Data, format: ExportFormat) async throws {
        // Request add-only permission (does not ask for read access).
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)

        // Accept .authorized and .limited — both allow PHAssetCreationRequest writes.
        // (PITFALL #17: rejecting .limited breaks saves for limited-access users.)
        guard status == .authorized || status == .limited else {
            throw Error.permissionDenied
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                // Set UTI so Photos records the correct format (HEIC vs JPEG vs PNG).
                options.uniformTypeIdentifier = format.uti
                request.addResource(with: .photo, data: encodedData, options: options)
            }
        } catch {
            throw Error.saveFailed(underlying: error)
        }
    }
}
