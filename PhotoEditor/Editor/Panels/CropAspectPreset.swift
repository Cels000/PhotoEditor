import Foundation
import CoreGraphics

enum CropAspectPreset: String, CaseIterable, Identifiable {
    case free, original, square, fourFive, threeFour, nineSixteen, sixteenNine, threeTwo, twoThree
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .free:        return "Free"
        case .original:    return "Original"
        case .square:      return "1:1"
        case .fourFive:    return "4:5"
        case .threeFour:   return "3:4"
        case .nineSixteen: return "9:16"
        case .sixteenNine: return "16:9"
        case .threeTwo:    return "3:2"
        case .twoThree:    return "2:3"
        }
    }
    /// Returns target width/height ratio. nil means "free" or "original" (use source).
    var ratio: CGFloat? {
        switch self {
        case .free, .original: return nil
        case .square:      return 1.0
        case .fourFive:    return 4.0/5.0
        case .threeFour:   return 3.0/4.0
        case .nineSixteen: return 9.0/16.0
        case .sixteenNine: return 16.0/9.0
        case .threeTwo:    return 3.0/2.0
        case .twoThree:    return 2.0/3.0
        }
    }
}
