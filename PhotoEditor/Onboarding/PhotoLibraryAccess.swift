import Photos
import UIKit

enum PhotoLibraryAccess {
    /// Read-write status. The picker import path doesn't strictly need readWrite,
    /// but checking .limited is what UX-08 requires.
    static var currentStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    static var isLimited: Bool { currentStatus == .limited }

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
