import SwiftUI

enum Theme {
    enum Colors {
        static let canvas: Color    = Color(light: 0xF5EFE8, dark: 0x0E0D0C)
        static let panel: Color     = Color(light: 0xFFFFFF, dark: 0x1B1916)
        static let accent: Color    = Color(light: 0xB66A2A, dark: 0xE89A52)
        static let text: Color      = Color(light: 0x1A1816, dark: 0xF5EFE8)
        static let secondary: Color = Color(light: 0x6E6961, dark: 0x8A8378)
        static let separator: Color = Color(light: 0xE5DED4, dark: 0x2A2622)
    }

    enum Typography {
        // All use relativeTo: a system text style so Dynamic Type works (UX-04).
        static let title: Font        = .system(.largeTitle, design: .rounded).weight(.semibold)
        static let subtitle: Font     = .system(.headline, design: .default).weight(.medium)
        static let body: Font         = .system(.body)
        static let caption: Font      = .system(.caption)
        static let valueBubble: Font  = .system(.footnote, design: .monospaced).monospacedDigit()
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radii {
        static let small: CGFloat  = 8
        static let medium: CGFloat = 12
        static let large: CGFloat  = 20
        static let xLarge: CGFloat = 24
    }

    enum Shadow {
        static let panel: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) =
            (Color.black.opacity(0.18), 12, 0, 4)
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
