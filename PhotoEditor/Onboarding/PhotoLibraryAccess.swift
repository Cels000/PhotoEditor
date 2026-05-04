import Photos
import PhotosUI
import UIKit

enum PhotoLibraryAccess {
    /// Read-write status. The picker import path doesn't strictly need readWrite,
    /// but checking .limited is what UX-08 requires.
    static var currentStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    static var isLimited: Bool { currentStatus == .limited }

    /// Request the FULL read-write permission. iOS will show its system dialog
    /// with "Allow Access to All Photos / Select Photos / Don't Allow". We
    /// can't pre-select an option — Apple guarantees the user always chooses
    /// — but asking for `.readWrite` (vs just `.addOnly`) ensures the All
    /// Photos option is on screen.
    @discardableResult
    static func requestFullAccess() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    /// Presents the system "manage selected photos" picker for .limited users.
    /// Must be called from a UIViewController (use the topmost via key window).
    @MainActor
    static func presentLimitedPicker() {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return }
        // Walk to topmost presented controller
        var top: UIViewController = root
        while let presented = top.presentedViewController { top = presented }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
    }
}
