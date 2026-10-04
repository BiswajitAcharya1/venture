import FamilyControls
import ManagedSettings
import Observation
import Security
import UserNotifications

struct FocusProtectionRecommendation: Sendable, Equatable {
    let durationMinutes: Int
    let reason: String
    let shouldStartAutomatically: Bool

    static func make(sleepHours: Double?, signalLoad: Int?) -> FocusProtectionRecommendation {
        if let sleepHours, sleepHours < 5.5 {
            return .init(
                durationMinutes: 60,
                reason: "Sleep was \(sleepHours.formatted(.number.precision(.fractionLength(1)))) hours, so the next focus block is longer and interruptions stay lower.",
                shouldStartAutomatically: true
            )
        }
        if let signalLoad, signalLoad >= 65 {
            return .init(
                durationMinutes: 60,
                reason: "Today’s measured signal load is \(signalLoad)/100, so venture recommends a longer low-interruption block.",
                shouldStartAutomatically: true
            )
        }
        if let sleepHours, sleepHours < 7 {
            return .init(
                durationMinutes: 45,
                reason: "Sleep was \(sleepHours.formatted(.number.precision(.fractionLength(1)))) hours, so venture recommends a moderate recovery block.",
                shouldStartAutomatically: true
            )
        }
        if let signalLoad, signalLoad >= 40 {
            return .init(
                durationMinutes: 45,
                reason: "Today’s measured signal load is \(signalLoad)/100, so a moderate focus block is recommended.",
                shouldStartAutomatically: false
            )
        }
        if sleepHours != nil || signalLoad != nil {
            return .init(
                durationMinutes: 25,
                reason: "Current measured signals do not call for a longer restriction window.",
                shouldStartAutomatically: false
            )
        }
        return .init(
            durationMinutes: 25,
            reason: "Complete a scan or connect Apple Health to personalize the window.",
            shouldStartAutomatically: false
        )
    }
}

@MainActor
@Observable
final class CognitiveSupportService {
    var selection = FamilyActivitySelection() {
        didSet {
            if let encoded = try? JSONEncoder().encode(selection) {
                ScreenTimeSelectionKeyStore.save(encoded, account: selectionAccount)
            }
            startAutomaticProtectionIfNeeded()
        }
    }
    private(set) var authorizationStatus = AuthorizationCenter.shared.authorizationStatus
    private(set) var protectionActive = false
    private(set) var notificationStatus = "Not configured"
    private(set) var message: String?
    var automaticLowSleepProtection: Bool {
        didSet {
            defaults.set(automaticLowSleepProtection, forKey: Self.automaticProtectionKey)
            startAutomaticProtectionIfNeeded()
        }
    }
    private(set) var recommendation = FocusProtectionRecommendation.make(sleepHours: nil, signalLoad: nil)
    private(set) var protectionEndsAt: Date?

    private let settingsStore = ManagedSettingsStore(named: .init("venture.recovery"))
    private let notifications = UNUserNotificationCenter.current()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let selectionAccount: String
    @ObservationIgnored private var protectionTask: Task<Void, Never>?
    @ObservationIgnored private var latestSleepHours: Double?
    @ObservationIgnored private var latestSignalLoad: Int?

    private static let automaticProtectionKey = "venture.focus.automatic"

    init(defaults: UserDefaults = .standard, selectionAccount: String = "primary") {
        self.defaults = defaults
        self.selectionAccount = selectionAccount
        automaticLowSleepProtection = defaults.bool(forKey: Self.automaticProtectionKey)
        if let data = ScreenTimeSelectionKeyStore.read(account: selectionAccount),
           let restored = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            selection = restored
        }
    }

    var hasPersistedSelection: Bool {
        ScreenTimeSelectionKeyStore.read(account: selectionAccount) != nil
    }

    func clearPersistedSelection() {
        selection = FamilyActivitySelection()
        ScreenTimeSelectionKeyStore.delete(account: selectionAccount)
    }

    var capabilityAvailable: Bool {
        Bundle.main.object(forInfoDictionaryKey: "VentureFamilyControlsEnabled") as? Bool ?? false
    }

    var selectedCount: Int {
        selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }

    var isAuthorized: Bool {
        if authorizationStatus == .approved { return true }
        if #available(iOS 26.4, *), authorizationStatus == .approvedWithDataAccess { return true }
        return false
    }

    func requestScreenTimeAuthorization() async {
        guard capabilityAvailable else {
            message = "Screen Time protection is unavailable in Personal Team builds. Apple must approve the Family Controls entitlement for a distribution profile."
            return
        }
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            authorizationStatus = AuthorizationCenter.shared.authorizationStatus
            message = isAuthorized
                ? "Screen Time access approved. Choose the apps you want venture to protect."
                : "Screen Time access was not approved."
        } catch {
            authorizationStatus = AuthorizationCenter.shared.authorizationStatus
            message = "Screen Time access requires Apple's Family Controls entitlement and device approval."
        }
    }

    func activateProtection(sleepHours: Double?) async {
        latestSleepHours = sleepHours ?? latestSleepHours
        recommendation = .make(sleepHours: latestSleepHours, signalLoad: latestSignalLoad)
        guard capabilityAvailable else {
            message = "Screen Time protection requires an Apple-approved Family Controls entitlement. Sleep-aware wind-down reminders remain available."
            return
        }
        if !isAuthorized {
            await requestScreenTimeAuthorization()
        }
        guard isAuthorized else { return }
        guard selectedCount > 0 else {
            message = "Choose at least one distracting app, category, or website first."
            return
        }

        settingsStore.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        settingsStore.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        settingsStore.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        protectionActive = true
        protectionEndsAt = Date.now.addingTimeInterval(Double(recommendation.durationMinutes * 60))
        message = "Protection is active for \(recommendation.durationMinutes) minutes. \(recommendation.reason)"
        await scheduleProtectionEndReminder()
        startExpiryTask()
    }

    func stopProtection() {
        protectionTask?.cancel()
        protectionTask = nil
        settingsStore.clearAllSettings()
        protectionActive = false
        protectionEndsAt = nil
        notifications.removePendingNotificationRequests(withIdentifiers: ["venture.focus-ended"])
        message = "Screen Time protection stopped."
    }

    func updateContext(sleepHours: Double?, signalLoad: Int?) {
        latestSleepHours = sleepHours
        latestSignalLoad = signalLoad
        recommendation = .make(sleepHours: sleepHours, signalLoad: signalLoad)
        startAutomaticProtectionIfNeeded()
    }

    private func startAutomaticProtectionIfNeeded() {
        guard
            capabilityAvailable,
            automaticLowSleepProtection,
            recommendation.shouldStartAutomatically,
            selectedCount > 0,
            !protectionActive
        else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await activateProtection(sleepHours: latestSleepHours)
        }
    }

    func reconcileProtectionWindow() {
        guard protectionActive, let protectionEndsAt, protectionEndsAt <= .now else { return }
        stopProtection()
    }

    func scheduleWindDownReminder(sleepHours: Double?) async {
        do {
            let granted = try await notifications.requestAuthorization(options: [.alert, .sound])
            guard granted else {
                notificationStatus = "Permission denied"
                return
            }
            notifications.removePendingNotificationRequests(withIdentifiers: ["venture.wind-down"])
            let content = UNMutableNotificationContent()
            content.title = "Protect tonight's recovery"
            content.body = sleepHours.map { $0 < 7
                ? "Your latest sleep was \($0.formatted(.number.precision(.fractionLength(1)))) hours. Start winding down earlier tonight."
                : "A quieter evening can protect tomorrow's baseline."
            } ?? "A quieter evening can protect tomorrow's baseline."
            content.sound = .default
            var components = DateComponents()
            components.hour = sleepHours.map { $0 < 7 ? 21 : 22 } ?? 22
            components.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            try await notifications.add(UNNotificationRequest(identifier: "venture.wind-down", content: content, trigger: trigger))
            notificationStatus = "Wind-down reminder enabled"
        } catch {
            notificationStatus = "Could not schedule reminder"
        }
    }

    private func scheduleProtectionEndReminder() async {
        guard let protectionEndsAt else { return }
        do {
            let granted = try await notifications.requestAuthorization(options: [.alert, .sound])
            guard granted else { return }
            notifications.removePendingNotificationRequests(withIdentifiers: ["venture.focus-ended"])
            let content = UNMutableNotificationContent()
            content.title = "Focus window complete"
            content.body = "Your \(recommendation.durationMinutes)-minute adaptive protection window is complete."
            content.sound = .default
            let interval = max(60, protectionEndsAt.timeIntervalSinceNow)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            try await notifications.add(UNNotificationRequest(identifier: "venture.focus-ended", content: content, trigger: trigger))
        } catch {
            message = "Protection is active, but the end reminder could not be scheduled."
        }
    }

    private func startExpiryTask() {
        protectionTask?.cancel()
        guard let protectionEndsAt else { return }
        let interval = max(0, protectionEndsAt.timeIntervalSinceNow)
        protectionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled, let self else { return }
            self.settingsStore.clearAllSettings()
            self.protectionActive = false
            self.protectionEndsAt = nil
            self.protectionTask = nil
            self.message = "The adaptive focus window ended."
        }
    }
}

@MainActor
private enum ScreenTimeSelectionKeyStore {
    private static let service = "com.venture.screen-time.selection"
#if targetEnvironment(simulator)
    // Unsigned simulator test hosts can reject the data-protection Keychain.
    // Keep that development fallback process-only so selection tokens never reach disk.
    private static var simulatorFallback: [String: Data] = [:]
#endif

    static func read(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess {
            return result as? Data
        }
#if targetEnvironment(simulator)
        return simulatorFallback[account]
#else
        return nil
#endif
    }

    static func save(_ data: Data, account: String) {
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        var status = updateStatus
        if updateStatus == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            status = SecItemAdd(item as CFDictionary, nil)
        }
#if targetEnvironment(simulator)
        if status == errSecSuccess {
            simulatorFallback.removeValue(forKey: account)
        } else {
            simulatorFallback[account] = data
        }
#endif
    }

    static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
#if targetEnvironment(simulator)
        simulatorFallback.removeValue(forKey: account)
#endif
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
    }
}
