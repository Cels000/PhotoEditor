import SwiftUI

/// View modifier that toggles `showOriginal` while the user presses-and-holds
/// on the canvas. Implements HIST-02 (before/after compare).
/// Uses LongPressGesture (>=0.4s) to avoid eating short taps (Pitfall #9).
struct CompareGesture: ViewModifier {
    @Binding var showOriginal: Bool
    var minDuration: Double = 0.4

    func body(content: Content) -> some View {
        content.gesture(
            LongPressGesture(minimumDuration: minDuration)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onChanged { value in
                    switch value {
                    case .second(true, _): showOriginal = true
                    default: break
                    }
                }
                .onEnded { _ in
                    showOriginal = false
                }
        )
    }
}

extension View {
    func compareOnLongPress(showOriginal: Binding<Bool>) -> some View {
        modifier(CompareGesture(showOriginal: showOriginal))
    }
}
