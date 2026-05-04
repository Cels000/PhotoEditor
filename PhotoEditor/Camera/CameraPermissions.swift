import AVFoundation
import UIKit

/// Thin wrapper around AVCaptureDevice authorization. Lives in Camera/ so the
/// rest of the app doesn't need to import AVFoundation just to gate a button.
enum CameraPermissions {

    static var status: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// Requests access if not yet determined; otherwise returns the current
    /// status synchronously. Safe to call from @MainActor — the AVF call is
    /// thread-safe and the completion fires on a background queue.
    @MainActor
    static func request() async -> AVAuthorizationStatus {
        switch status {
        case .notDetermined:
            _ = await AVCaptureDevice.requestAccess(for: .video)
            return status
        default:
            return status
        }
    }

    /// Open iOS Settings → app page so a denied user can grant access.
    @MainActor
    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
