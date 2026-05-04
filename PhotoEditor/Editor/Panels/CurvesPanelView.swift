import SwiftUI

struct CurvesPanelView: View {
    @Bindable var viewModel: EditorViewModel

    enum ChannelTab: String, CaseIterable, Identifiable {
        case rgb, red, green, blue
        var id: String { rawValue }
        var label: String { self == .rgb ? "RGB" : rawValue.capitalized }
        var tint: Color {
            switch self {
            case .rgb:   return .primary
            case .red:   return .red
            case .green: return .green
            case .blue:  return .blue
            }
        }
    }

    @State private var tab: ChannelTab = .rgb
    @State private var draggingIndex: Int? = nil

    private var curveKP: WritableKeyPath<AdjustmentStack, CurveChannel> {
        switch tab {
        case .rgb:   return \.curves.rgb
        case .red:   return \.curves.red
        case .green: return \.curves.green
        case .blue:  return \.curves.blue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Curve channel", selection: $tab) {
                ForEach(ChannelTab.allCases) { c in
                    Text(c.label)
                        .font(Theme.Typography.caption)
                        .tag(c)
                        .accessibilityLabel("\(c.label) channel")
                        .accessibilityHint("Switches the curve to this channel")
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Curve channel selector")

            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                canvasView(size: size)
                    .frame(width: size, height: size)
            }
            .frame(height: 200)
            .accessibilityLabel("Tone curve")
            .accessibilityHint("Drag points to shape the curve. Use VoiceOver swipe up or down on each point to adjust.")

            Button("Reset Curve") {
                viewModel.beginInteractiveEdit()
                viewModel.stack[keyPath: curveKP] = CurveChannel()
                viewModel.stackDidChange()
                viewModel.endInteractiveEdit()
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func canvasView(size: CGFloat) -> some View {
        // Ensure exactly 5 points; if user has 2 (identity), expand to 5.
        let pts = ensureFivePoints(viewModel.stack[keyPath: curveKP].points)

        ZStack {
            // Grid + curve.
            Canvas { ctx, _ in
                // 4x4 grid
                let step = size / 4
                for i in 0...4 {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: CGFloat(i) * step))
                    path.addLine(to: CGPoint(x: size, y: CGFloat(i) * step))
                    path.move(to: CGPoint(x: CGFloat(i) * step, y: 0))
                    path.addLine(to: CGPoint(x: CGFloat(i) * step, y: size))
                    ctx.stroke(path, with: .color(.gray.opacity(0.2)), lineWidth: 0.5)
                }
                // Smooth curve through points using Catmull-Rom → cubic Bezier.
                // Replaces the prior piecewise-linear polyline that read as a
                // placeholder.
                let cgPoints: [CGPoint] = pts.map { p in
                    CGPoint(x: CGFloat(p.x) * size, y: (1 - CGFloat(p.y)) * size)
                }
                var curve = Path()
                if let first = cgPoints.first { curve.move(to: first) }
                let n = cgPoints.count
                for i in 0..<(n - 1) {
                    let p0 = cgPoints[max(i - 1, 0)]
                    let p1 = cgPoints[i]
                    let p2 = cgPoints[i + 1]
                    let p3 = cgPoints[min(i + 2, n - 1)]
                    // Catmull-Rom → Bezier control points (tension 0.5).
                    let c1 = CGPoint(
                        x: p1.x + (p2.x - p0.x) / 6,
                        y: p1.y + (p2.y - p0.y) / 6
                    )
                    let c2 = CGPoint(
                        x: p2.x - (p3.x - p1.x) / 6,
                        y: p2.y - (p3.y - p1.y) / 6
                    )
                    curve.addCurve(to: p2, control1: c1, control2: c2)
                }
                ctx.stroke(curve, with: .color(tab.tint), lineWidth: 2)
            }
            // Draggable points overlay.
            ForEach(0..<pts.count, id: \.self) { i in
                let p = pts[i]
                Circle()
                    .fill(tab.tint)
                    .frame(width: 14, height: 14)
                    .position(x: CGFloat(p.x) * size, y: (1 - CGFloat(p.y)) * size)
                    .gesture(
                        DragGesture()
                            .onChanged { drag in
                                if draggingIndex == nil {
                                    draggingIndex = i
                                    viewModel.beginInteractiveEdit()
                                }
                                var local = pts
                                let nx = max(0, min(1, drag.location.x / size))
                                let ny = max(0, min(1, 1 - drag.location.y / size))
                                // Lock x for endpoints.
                                let clampedX: Double
                                if i == 0 { clampedX = 0 }
                                else if i == local.count - 1 { clampedX = 1 }
                                else {
                                    let lo = local[i-1].x + 0.01
                                    let hi = local[i+1].x - 0.01
                                    clampedX = max(lo, min(hi, Double(nx)))
                                }
                                local[i] = CurvePoint(x: clampedX, y: Double(ny))
                                viewModel.stack[keyPath: curveKP].points = local
                                viewModel.stackDidChange()
                            }
                            .onEnded { _ in
                                draggingIndex = nil
                                viewModel.endInteractiveEdit()
                            }
                    )
                    .accessibilityElement()
                    .accessibilityLabel("Curve point \(i + 1) of \(pts.count)")
                    .accessibilityValue("Y value \(Int(p.y * 100)) percent")
                    .accessibilityAdjustableAction { direction in
                        let step = 0.05
                        var local = viewModel.stack[keyPath: curveKP].points
                        guard i < local.count else { return }
                        switch direction {
                        case .increment: local[i].y = min(1.0, local[i].y + step)
                        case .decrement: local[i].y = max(0.0, local[i].y - step)
                        @unknown default: break
                        }
                        viewModel.stack[keyPath: curveKP].points = local
                        viewModel.stackDidChange()
                    }
            }
        }
    }

    private func ensureFivePoints(_ pts: [CurvePoint]) -> [CurvePoint] {
        if pts.count == 5 { return pts }
        // Initialize from identity: 5 evenly-spaced points along y=x.
        return [
            CurvePoint(x: 0.0,  y: 0.0),
            CurvePoint(x: 0.25, y: 0.25),
            CurvePoint(x: 0.5,  y: 0.5),
            CurvePoint(x: 0.75, y: 0.75),
            CurvePoint(x: 1.0,  y: 1.0),
        ]
    }
}
