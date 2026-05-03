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
            Picker("", selection: $tab) {
                ForEach(ChannelTab.allCases) { c in Text(c.label).tag(c) }
            }
            .pickerStyle(.segmented)

            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                canvasView(size: size)
                    .frame(width: size, height: size)
            }
            .frame(height: 200)

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
                // Curve through pts (linear interp).
                var curve = Path()
                for i in 0..<pts.count {
                    let p = pts[i]
                    let cgp = CGPoint(x: CGFloat(p.x) * size, y: (1 - CGFloat(p.y)) * size)
                    if i == 0 { curve.move(to: cgp) } else { curve.addLine(to: cgp) }
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
