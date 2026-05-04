import SwiftUI

enum Theme {
    // VSCO-style monochrome palette. The accent is intentionally non-chromatic
    // — selection state in VSCO is just darker text on white (or white on black),
    // never a colored highlight. The photo provides all the color in the UI.
    enum Colors {
        static let canvas: Color    = Color(light: 0xFFFFFF, dark: 0x000000)
        static let panel: Color     = Color(light: 0xFAFAFA, dark: 0x0A0A0A)
        static let accent: Color    = Color(light: 0x0A0A0A, dark: 0xFFFFFF) // emphasis tone
        static let text: Color      = Color(light: 0x0A0A0A, dark: 0xF2F2F2)
        static let secondary: Color = Color(light: 0x8E8E8E, dark: 0x6E6E6E)
        static let separator: Color = Color(light: 0xEAEAEA, dark: 0x1A1A1A)
    }

    // Typography is small, sparse, often UPPERCASE with letterspacing — VSCO's
    // signature understatement. Body text is system-default; chrome labels are
    // tiny, tracked-out captions.
    enum Typography {
        static let title: Font        = .system(.title2, design: .default).weight(.regular)
        static let subtitle: Font     = .system(.subheadline, design: .default).weight(.regular)
        static let body: Font         = .system(.body)
        static let caption: Font      = .system(.caption2).weight(.medium)
        static let valueBubble: Font  = .system(.caption, design: .monospaced).monospacedDigit()
        // Tab/section labels: ALL CAPS at ~10pt with positive tracking.
        static let label: Font        = .system(size: 10, weight: .semibold)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radii {
        // VSCO uses minimal-to-zero rounding. Squares everywhere.
        static let small: CGFloat  = 2
        static let medium: CGFloat = 4
        static let large: CGFloat  = 6
        static let xLarge: CGFloat = 8
    }

    enum Shadow {
        // VSCO uses essentially no drop shadows. Keep this for parity but
        // dial way down — most surfaces should be flat.
        static let panel: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) =
            (Color.black.opacity(0.04), 4, 0, 1)
    }
}

private extension Color {
    /// Resolves to one hex in light mode, another in dark mode, via UIColor dynamicProvider.
    init(light: UInt32, dark: UInt32) {
        self = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark)
                : UIColor(hex: light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >>  8) & 0xFF) / 255.0
        let b = CGFloat( hex        & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
