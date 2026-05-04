import SwiftUI
import UIKit

/// VSCO-flavored chrome around the histogram bitmap. Fixed 120x80pt; pass-through
/// hit testing so the canvas tap-to-hide-chrome gesture still works underneath.
struct HistogramOverlayView: View {
    let image: UIImage?

    var body: some View {
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
        .frame(width: 120, height: 80)
        .accessibilityLabel("RGB histogram")
        .allowsHitTesting(false)
    }
}
