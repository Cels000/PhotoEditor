import SwiftUI

/// Non-blocking success toast. Auto-dismisses after `duration` seconds.
/// Replaces blocking `.alert("Saved", ...)` flows.
struct ToastOverlay: ViewModifier {
    @Binding var message: String?
    var duration: TimeInterval = 1.8

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let m = message {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Colors.accent)
                    Text(m)
                        .font(Theme.Typography.subtitle)
                        .foregroundStyle(Theme.Colors.text)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm)
                .background(.thinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .padding(.top, Theme.Spacing.sm)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: m) {
                    try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                    withAnimation(Motion.adaptive(Motion.snappy)) { message = nil }
                }
            }
        }
        .animation(Motion.adaptive(Motion.snappy), value: message)
    }
}

extension View {
    func successToast(message: Binding<String?>) -> some View {
        modifier(ToastOverlay(message: message))
    }
}
