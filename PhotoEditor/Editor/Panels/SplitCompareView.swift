import SwiftUI

/// Side-by-side compare with a draggable vertical divider. Both images are
/// laid out at the same `scaledToFit` frame inside a GeometryReader; the
/// edited version is masked to the right of the divider so the original
/// shows through on the left. The divider's handle accepts a horizontal drag
/// that updates `splitPosition` (0...1 of the canvas width, clamped to a
/// small inset so the handle never goes fully off-screen).
///
/// Why not just `mask(HStack { Color.clear; Color.black })` on one image?
/// That's the implementation here — it's the cheapest way to get pixel-
/// perfect alignment. Both images are sized identically by SwiftUI's layout
/// pass, so the mask cleanly bisects them.
struct SplitCompareView: View {
    let original: UIImage
    let edited: UIImage
    @Binding var splitPosition: CGFloat

    /// Minimum inset (in points) on either side so the user can always grab
    /// the handle even when they've dragged it all the way over. Without
    /// this, splitPosition=1.0 would put the handle exactly on the right
    /// edge where it's hard to hit.
    private let edgeInset: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let dividerX = max(edgeInset, min(w - edgeInset, w * splitPosition))

            ZStack(alignment: .topLeading) {
                Image(uiImage: original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: w, height: geo.size.height)

                Image(uiImage: edited)
                    .resizable()
                    .scaledToFit()
                    .frame(width: w, height: geo.size.height)
                    .mask(alignment: .leading) {
                        // Black on the right of the divider = edited shows
                        // through; clear on the left = original shows through.
                        HStack(spacing: 0) {
                            Color.clear.frame(width: dividerX)
                            Color.black
                        }
                    }

                // Divider line
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: geo.size.height)
                    .offset(x: dividerX - 1)
                    .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 0)

                // Drag handle — circular pill centered on the divider.
                handle
                    .position(x: dividerX, y: geo.size.height / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let raw = value.location.x / max(1, w)
                                splitPosition = max(0, min(1, raw))
                            }
                    )

                // BEFORE / AFTER labels at the top of each side
                Text("BEFORE")
                    .font(Theme.Typography.label)
                    .tracking(1.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(.black.opacity(0.45), in: Capsule())
                    .position(x: max(36, dividerX - 44),
                              y: 28)
                    .opacity(dividerX > edgeInset + 12 ? 1 : 0)

                Text("AFTER")
                    .font(Theme.Typography.label)
                    .tracking(1.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(.black.opacity(0.45), in: Capsule())
                    .position(x: min(w - 36, dividerX + 44),
                              y: 28)
                    .opacity(dividerX < w - edgeInset - 12 ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Side-by-side compare")
        .accessibilityHint("Drag the divider left or right to compare original and edited sides.")
    }

    private var handle: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 44, height: 44)
                .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 1)
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Image(systemName: "chevron.right")
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.black)
        }
    }
}
