import SwiftUI

/// Bridges to Mantis SPM if present; otherwise compiles as a no-op stub
/// so the project builds without the dependency.
/// User adds Mantis via SPM on Mac per .planning STATE.md note.
#if canImport(Mantis)
import Mantis
import UIKit

struct MantisCropView: UIViewControllerRepresentable {
    let image: UIImage
    let onComplete: (CGRect, CGFloat, Bool, Bool, Int) -> Void   // (normalizedRect, rotation°, flipH, flipV, ccwSteps)
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        var config = Mantis.Config()
        config.cropViewConfig.showRotationDial = true
        let cropper = Mantis.cropViewController(image: image, config: config)
        cropper.delegate = context.coordinator
        return cropper
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, CropViewControllerDelegate {
        let parent: MantisCropView
        init(_ parent: MantisCropView) { self.parent = parent }

        func cropViewControllerDidCrop(_ cropViewController: Mantis.CropViewController,
                                       cropped: UIImage,
                                       transformation: Mantis.Transformation,
                                       cropInfo: Mantis.CropInfo) {
            let imgSize = parent.image.size
            let rect = cropInfo.cropRegion
            // cropInfo.cropRegion is in image-coords; normalize.
            let norm = CGRect(
                x: rect.minX / imgSize.width,
                y: rect.minY / imgSize.height,
                width: rect.width / imgSize.width,
                height: rect.height / imgSize.height
            )
            let rotDeg = Double(transformation.rotation) * 180 / .pi
            parent.onComplete(norm, CGFloat(rotDeg), transformation.scaleX < 0, transformation.scaleY < 0, 0)
        }
        func cropViewControllerDidCancel(_ cropViewController: Mantis.CropViewController, original: UIImage) {
            parent.onCancel()
        }
        func cropViewControllerDidFailToCrop(_ cropViewController: Mantis.CropViewController, original: UIImage) {
            parent.onCancel()
        }
        func cropViewControllerDidBeginResize(_ cropViewController: Mantis.CropViewController) {}
        func cropViewControllerDidEndResize(_ cropViewController: Mantis.CropViewController, original: UIImage, cropInfo: Mantis.CropInfo) {}
    }
}

let mantisAvailable: Bool = true
#else
/// Mantis is not linked. Fallback UI is used instead (no advanced crop UI; preset list + rotation slider).
let mantisAvailable: Bool = false
#endif
