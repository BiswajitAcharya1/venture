import AppIntents
import SwiftUI

@main
struct VentureApp: App {
    @State private var store = VentureStore()
    private let accountAuth = AccountAuthService()

    init() {
        VentureAppShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            VentureExperienceView(store: store)
                .preferredColorScheme(.light)
                .task {
                    _ = try? await accountAuth.refreshSessionIfNeeded()
                    await store.bootstrap()
                }
        }
    }
}

enum VentureSystemRoute: String, Sendable {
    case scan
    case assistant
}

enum VentureSystemRouteStore {
    private static let key = "venture.pending-system-route"

    static func request(
        _ route: VentureSystemRoute,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(route.rawValue, forKey: key)
    }

    static func consume(defaults: UserDefaults = .standard) -> VentureSystemRoute? {
        guard
            let rawValue = defaults.string(forKey: key),
            let route = VentureSystemRoute(rawValue: rawValue)
        else { return nil }
        defaults.removeObject(forKey: key)
        return route
    }
}

struct StartVentureScanIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a venture voice check"
    static let description = IntentDescription("Opens venture's voice check and practical support options.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        VentureSystemRouteStore.request(.scan)
        return .result(dialog: "Opening today's venture scan.")
    }
}

struct AskVentureIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask venture"
    static let description = IntentDescription("Opens the local assistant grounded in your measured signals.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        VentureSystemRouteStore.request(.assistant)
        return .result(dialog: "Opening the venture assistant.")
    }
}

struct VentureAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartVentureScanIntent(),
            phrases: [
                "Start a scan in \(.applicationName)",
                "Measure with \(.applicationName)"
            ],
            shortTitle: "Start scan",
            systemImageName: "waveform.path.ecg"
        )
        AppShortcut(
            intent: AskVentureIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Open my signals in \(.applicationName)"
            ],
            shortTitle: "Ask venture",
            systemImageName: "bubble.left.and.text.bubble.right"
        )
    }
}
