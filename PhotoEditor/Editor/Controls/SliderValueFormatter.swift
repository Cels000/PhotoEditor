import Foundation

/// Display formatter for adjustment slider values.
enum SliderValueFormatter {
    /// e.g. "+25%" or "-50%" — for -1...+1 ranges.
    case signedPercent
    /// e.g. "+15°" or "-30°" — for hue / rotation.
    case degrees
    /// e.g. "0.42" — raw 2-decimal.
    case decimal2
    /// e.g. "75%" — for 0...1 ranges.
    case percent

    func format(_ value: Double) -> String {
        switch self {
        case .signedPercent:
            let pct = Int((value * 100).rounded())
            return pct >= 0 ? "+\(pct)%" : "\(pct)%"
        case .degrees:
            let deg = Int(value.rounded())
            return deg >= 0 ? "+\(deg)°" : "\(deg)°"
        case .decimal2:
            return value.formatted(.number.precision(.fractionLength(2)))
        case .percent:
            return "\(Int((value * 100).rounded()))%"
        }
    }
}
