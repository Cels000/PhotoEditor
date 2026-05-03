import UIKit

enum Haptic {
    case sliderZeroCross
    case sliderEnd
    case filterSelect
    case recipeApply
    case undoRedo
    case panelOpen
    case errorAlert

    @MainActor
    static func play(_ event: Haptic) {
        switch event {
        case .sliderZeroCross:
            Self.lightImpact.impactOccurred(intensity: 0.6)
            Self.lightImpact.prepare()
        case .sliderEnd:
            Self.rigidImpact.impactOccurred()
            Self.rigidImpact.prepare()
        case .filterSelect:
            Self.selection.selectionChanged()
            Self.selection.prepare()
        case .recipeApply:
            Self.notification.notificationOccurred(.success)
            Self.notification.prepare()
        case .undoRedo:
            Self.lightImpact.impactOccurred(intensity: 0.7)
            Self.lightImpact.prepare()
        case .panelOpen:
            Self.softImpact.impactOccurred(intensity: 0.4)
            Self.softImpact.prepare()
        case .errorAlert:
            Self.notification.notificationOccurred(.error)
            Self.notification.prepare()
        }
    }

    // Prepared generators — calling .prepare() ahead reduces first-fire latency.
    @MainActor private static let lightImpact: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .light); g.prepare(); return g
    }()
    @MainActor private static let rigidImpact: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .rigid); g.prepare(); return g
    }()
    @MainActor private static let softImpact: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .soft); g.prepare(); return g
    }()
    @MainActor private static let selection: UISelectionFeedbackGenerator = {
        let g = UISelectionFeedbackGenerator(); g.prepare(); return g
    }()
    @MainActor private static let notification: UINotificationFeedbackGenerator = {
        let g = UINotificationFeedbackGenerator(); g.prepare(); return g
    }()
}
