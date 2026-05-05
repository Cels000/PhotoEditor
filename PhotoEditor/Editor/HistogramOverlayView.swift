import SwiftUI
import UIKit

/// VSCO-flavored chrome around the histogram bitmap. Pass-through hit
/// testing so the canvas tap-to-hide-chrome gesture still works underneath.
/// Sized as a fraction of the screen width (capped) so it's actually
/// readable on a modern phone — the original 120x80pt felt postage-stamp
/// on a Pro Max.
struct HistogramOverlayView: View {
    let image: UIImage?

    var body: some View {
        let screenW = UIScreen.main.bounds.width
        let width: CGFloat = min(260, max(160, screenW * 0.32))
        let height: CGFloat = width * 0.62  // ~5:3 ratio, matches Lightroom

        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radii.small)
                .fill(Theme.Colors.canvas.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radii.small)
                        .strokeBorder(Theme.Colors.separator.opacity(0.6), lineWidth: 0.5)
                )

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)   // crisp histogram bars
                    .scaledToFit()
                    .padding(Theme.Spacing.xs)
            }
        }
        .frame(width: width, height: height)
        .accessibilityLabel("RGB histogram")
        .allowsHitTesting(false)
    }
}
