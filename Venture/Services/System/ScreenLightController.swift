import Observation
import UIKit

@MainActor
@Observable
final class ScreenLightController {
    private var originalBrightness: CGFloat?

    private(set) var isActive = false

    func begin() {
        guard !isActive else { return }
        originalBrightness = UIScreen.main.brightness
        isActive = true
        UIScreen.main.brightness = 1
    }

    func restore() {
        guard isActive else { return }
        if let originalBrightness {
            UIScreen.main.brightness = originalBrightness
        }
        originalBrightness = nil
        isActive = false
    }
}
