import UIKit

@MainActor
enum Haptics {
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    static func prepare() {
        lightImpact.prepare()
        mediumImpact.prepare()
        heavyImpact.prepare()
        selection.prepare()
        notification.prepare()
    }

    static func selected() {
        selection.selectionChanged()
        selection.prepare()
    }

    static func soft() {
        lightImpact.impactOccurred(intensity: 0.85)
        lightImpact.prepare()
    }

    static func strong() {
        heavyImpact.impactOccurred(intensity: 1)
        heavyImpact.prepare()
    }

    static func progress() {
        mediumImpact.impactOccurred(intensity: 0.9)
        mediumImpact.prepare()
    }

    static func success() {
        notification.notificationOccurred(.success)
        notification.prepare()
    }
}
