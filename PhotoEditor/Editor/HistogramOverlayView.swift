import SwiftUI

/// VSCO-flavored chrome around a custom-drawn RGB histogram. Pass-through hit
/// testing so the canvas tap-to-hide-chrome gesture still works underneath.
/// Sized as a fraction of the screen width (capped) so it's actually
/// readable on a modern phone.
///
/// We draw the three channels ourselves with SwiftUI `Canvas` and additive
/// (`.plusLighter`) blending: pure red/green/blue traces over a dark panel,
/// overlapping regions naturally turn yellow / cyan / magenta / white. This
/// reads far better than `CIHistogramDisplayFilter`, which paints a grey
/// luma block with faint colored overlays.
struct HistogramOverlayView: View {
    let data: HistogramData?

    var body: some View {
        let screenW = UIScreen.main.bounds.width
        let width: CGFloat = min(260, max(160, screenW * 0.32))
        let height: CGFloat = width * 0.62

        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radii.small)
                .fill(Color.black.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radii.small)
                        .strokeBorder(Theme.Colors.separator.opacity(0.6), lineWidth: 0.5)
                )

            if let data {
                Canvas { ctx, size in
                    let inset: CGFloat = 6
                    let plotRect = CGRect(
                        x: inset,
                        y: inset,
                        width: size.width - inset * 2,
                        height: size.height - inset * 2
                    )

                    // Faint mid-tone gridlines (quartiles) for orientation.
                    var grid = Path()
                    for i in 1..<4 {
                        let x = plotRect.minX + plotRect.width * CGFloat(i) / 4
                        grid.move(to: CGPoint(x: x, y: plotRect.minY))
                        grid.addLine(to: CGPoint(x: x, y: plotRect.maxY))
                    }
                    ctx.stroke(grid, with: .color(.white.opacity(0.08)), lineWidth: 0.5)

                    let channels: [(values: [CGFloat], color: Color)] = [
                        (smooth(data.r), Color(red: 1.0, green: 0.22, blue: 0.22)),
                        (smooth(data.g), Color(red: 0.30, green: 1.0, blue: 0.40)),
                        (smooth(data.b), Color(red: 0.40, green: 0.60, blue: 1.0))
                    ]

                    // Pass 1: fills with additive blending. Low opacity so
                    // overlaps darken to colored midtones (yellow/cyan/magenta)
                    // instead of saturating to white the moment all three meet.
                    for channel in channels {
                        var layer = ctx
                        layer.blendMode = .plusLighter
                        layer.fill(
                            filledPath(values: channel.values, in: plotRect),
                            with: .color(channel.color.opacity(0.30))
                        )
                    }

                    // Pass 2: strokes on top, normal blend, full opacity. This
                    // is what makes individual channels readable even when their
                    // shapes are nearly identical — the outline of each channel
                    // is always visible, drawn in pure R/G/B.
                    for channel in channels {
                        ctx.stroke(
                            strokePath(values: channel.values, in: plotRect),
                            with: .color(channel.color.opacity(0.95)),
                            lineWidth: 1.25
                        )
                    }
                }
                .padding(0)
            }
        }
        .frame(width: width, height: height)
        .accessibilityLabel("RGB histogram")
        .allowsHitTesting(false)
    }

    private func filledPath(values: [CGFloat], in rect: CGRect) -> Path {
        var path = Path()
        guard !values.isEmpty else { return path }
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for (i, v) in values.enumerated() {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(values.count - 1)
            let y = rect.maxY - rect.height * min(max(v, 0), 1)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }

    /// 5-tap binomial smoothing (1-4-6-4-1) — Lightroom-style noise tame so a
    /// single hot pixel column doesn't produce a needle that obscures the
    /// shape of the curve. Cheap (256 mults), runs once per render commit.
    private func smooth(_ v: [CGFloat]) -> [CGFloat] {
        guard v.count >= 5 else { return v }
        var out = v
        for i in 2..<(v.count - 2) {
            out[i] = (v[i - 2] + 4 * v[i - 1] + 6 * v[i] + 4 * v[i + 1] + v[i + 2]) / 16
        }
        return out
    }

    private func strokePath(values: [CGFloat], in rect: CGRect) -> Path {
        var path = Path()
        guard !values.isEmpty else { return path }
        for (i, v) in values.enumerated() {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(values.count - 1)
            let y = rect.maxY - rect.height * min(max(v, 0), 1)
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}
