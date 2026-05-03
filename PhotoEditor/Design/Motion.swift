import SwiftUI
import UIKit

enum Motion {
    /// Standard panel slide / sheet open. Calm, expressive.
    static let panel: Animation = .interpolatingSpring(stiffness: 240, damping: 28)

    /// Snappy tab switch / selection-ring fade. Faster, tighter.
    static let snappy: Animation = .interpolatingSpring(stiffness: 380, damping: 24)

    /// Subtle crossfade for value bubbles, opacity changes.
    static let smooth: Animation = .easeInOut(duration: 0.18)

    /// Wraps an animation so it returns nil under Reduce Motion (UX-06).
    /// Usage: `withAnimation(Motion.adaptive(.panel)) { ... }`
    /// Pass the result directly — withAnimation accepts Optional<Animation>.
    @MainActor
    static func adaptive(_ a: Animation) -> Animation? {
        UIAccessibility.isReduceMotionEnabled ? nil : a
    }
}
