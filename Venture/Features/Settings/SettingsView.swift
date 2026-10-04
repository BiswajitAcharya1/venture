import FamilyControls
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: VentureStore
    let onSignOut: () -> Void

    @State private var signOutPending = false
    @State private var appeared = false
    @State private var signingOut = false
    private let authService = AccountAuthService()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    accountHero
                    learnedSection
                    controlSection

                    Button(role: .destructive) {
                        Haptics.strong()
                        signOutPending = true
                    } label: {
                        Label("sign out", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay { Capsule().stroke(VentureTheme.line, lineWidth: 0.8) }
                    }
                    .buttonStyle(HapticPlainButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 34)
            }
            .background(VentureAtmosphereView().ignoresSafeArea())
            .navigationTitle("settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AnimatedCloseButton { dismiss() }
                }
            }
            .confirmationDialog("sign out of venture?", isPresented: $signOutPending, titleVisibility: .visible) {
                Button("sign out", role: .destructive) {
                    guard !signingOut else { return }
                    signingOut = true
                    Haptics.strong()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(120))
                        await authService.clearSession()
                        onSignOut()
                    }
                }
                Button("cancel", role: .cancel) { Haptics.soft() }
            } message: {
                Text("your encrypted measurements remain on this device.")
            }
            .onAppear {
                withAnimation(.spring(response: 0.72, dampingFraction: 0.86)) { appeared = true }
            }
            .scaleEffect(signingOut ? 0.96 : 1)
            .blur(radius: signingOut ? 5 : 0)
            .opacity(signingOut ? 0.3 : 1)
            .animation(.easeInOut(duration: 0.24), value: signingOut)
        }
    }

    private var accountHero: some View {
        VStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(VentureTheme.sage.opacity(0.12))
                    .frame(width: 132, height: 132)
                    .blur(radius: 18)
                LivingPortalView(size: 112, intensity: 0.78, interactive: false)
            }
            Text("your profile")
                .font(.system(.title2, design: .serif, weight: .semibold))
            Text("\(store.snapshots.count) measured days · Apple Health \(store.healthService.state.rawValue.lowercased())")
                .font(.caption)
                .foregroundStyle(VentureTheme.secondary)
        }
        .frame(maxWidth: .infinity)
        .scaleEffect(appeared ? 1 : 0.94)
        .opacity(appeared ? 1 : 0)
    }

    private var learnedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("what venture can see")
            ForEach(Array(store.metricGroups.enumerated()), id: \.element.id) { index, group in
                HStack(spacing: 12) {
                    Image(systemName: group.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.title.lowercased()).font(.subheadline.weight(.medium))
                        Text("\(group.metrics.count) signals · \(group.summary.lowercased())")
                            .font(.caption2)
                            .foregroundStyle(VentureTheme.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 12)
                if index < store.metricGroups.count - 1 { Divider().opacity(0.45) }
            }
            if store.metricGroups.isEmpty {
                Text("complete a scan or connect Apple Health to begin.")
                    .font(.subheadline)
                    .foregroundStyle(VentureTheme.secondary)
                    .padding(.vertical, 16)
            }
        }
    }

    private var controlSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("controls")
            destination(SecuritySettingsView(), symbol: "lock.shield", title: "security center", detail: "device protections and access")
            destination(
                PrivacyVaultView(store: store, onAccountWiped: onSignOut),
                symbol: "externaldrive.badge.checkmark",
                title: "privacy vault",
                detail: "stored metrics and deletion"
            )
            destination(AISettingsView(), symbol: "text.bubble", title: "assistant & language", detail: "Gemma 4 and response language")
            destination(ScanSettingsView(), symbol: "viewfinder", title: "scan behavior", detail: "camera, voice, and task controls")
            destination(HealthSettingsView(store: store), symbol: "heart.text.square", title: "health integrations", detail: "Apple Health · \(store.healthService.state.rawValue.lowercased())")
            destination(
                FocusProtectionSettingsView(service: store.supportService, sleepHours: store.healthService.latest.sleepHours),
                symbol: "hourglass",
                title: "focus protection",
                detail: "Screen Time controls when supported"
            )
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(.title3, design: .serif, weight: .semibold))
            .padding(.bottom, 8)
    }

    private func destination<Destination: View>(_ destination: Destination, symbol: String, title: String, detail: String) -> some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.medium))
                    Text(detail).font(.caption2).foregroundStyle(VentureTheme.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VentureTheme.secondary)
            }
        }
        .buttonStyle(HapticPlainButtonStyle())
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.62), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.035), radius: 12, y: 6)
    }
}

private struct SecuritySettingsView: View {
    @State private var authResult: String?
    private let biometrics = BiometricService()

    var body: some View {
        Form {
            Section {
                HStack(spacing: 18) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 34, weight: .light))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Device security").font(.headline)
                        Text("Measurements are encrypted with a device-only key stored in Keychain.")
                            .font(.caption)
                            .foregroundStyle(VentureTheme.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
            Section("Protection") {
                LabeledContent("Measurement encryption", value: "AES-256-GCM")
                LabeledContent("Encryption key", value: "Device-only Keychain")
                LabeledContent("Password derivation", value: "PBKDF2-SHA256")
                LabeledContent("Session lock", value: "After 15 seconds away")
                Text("Passwords are salted and processed through 310,000 PBKDF2 iterations. Existing local accounts are upgraded after a successful sign-in.")
                    .font(.caption)
                    .foregroundStyle(VentureTheme.secondary)
            }
            Section("Access check") {
                Button("Verify this device") {
                    Haptics.selected()
                    Task {
                        let success = await biometrics.authenticate(reason: "Verify access to your venture security center")
                        authResult = success ? "Device verified" : "Verification was not completed"
                    }
                }
                if let authResult { Text(authResult).font(.caption).foregroundStyle(VentureTheme.secondary) }
            }
            Section {
                Text("Cloud sessions and cross-device key rotation are not enabled in this build.")
                    .font(.caption)
                    .foregroundStyle(VentureTheme.secondary)
            }
        }
        .navigationTitle("Security center")
    }
}

private struct PrivacyVaultView: View {
    @Bindable var store: VentureStore
    let onAccountWiped: () -> Void
    @State private var deletion: Deletion?
    @State private var wipeMessage: String?
    private let biometrics = BiometricService()
    private let authService = AccountAuthService()

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Raw media is never retained.").font(.headline)
                    Text("Eye video and voice audio are deleted immediately after feature extraction.")
                        .font(.caption)
                        .foregroundStyle(VentureTheme.secondary)
                }
                .padding(.vertical, 4)
            }
            Section("Stored on this device") {
                storedRow("Voice metrics", available: store.snapshots.contains { $0.speechStability != nil })
                storedRow("Eye metrics", available: store.snapshots.contains { $0.fixationStability != nil })
                storedRow("Health metrics", available: store.healthService.latest.hasData)
                storedRow("Cognitive metrics", available: store.snapshots.contains { $0.memoryScore != nil || $0.attentionScore != nil || $0.executiveFunctionScore != nil })
            }
            Section("Delete") {
                Button("Delete voice history", role: .destructive) { Haptics.selected(); deletion = .voice }
                Button("Delete eye history", role: .destructive) { Haptics.selected(); deletion = .eyes }
                Button("Delete cached health history", role: .destructive) { Haptics.selected(); deletion = .health }
                Button("Clear all scans", role: .destructive) { Haptics.selected(); deletion = .all }
                Button("Wipe local account and data", role: .destructive) { Haptics.strong(); deletion = .account }
                if let wipeMessage {
                    Text(wipeMessage).font(.caption).foregroundStyle(VentureTheme.secondary)
                }
            }
        }
        .navigationTitle("Privacy vault")
        .confirmationDialog(
            deletion?.title ?? "Delete history?",
            isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }),
            titleVisibility: .visible
        ) {
            Button(deletion?.buttonTitle ?? "Delete", role: .destructive) {
                Haptics.strong()
                guard let deletion else { return }
                if deletion == .account {
                    wipeAccount()
                } else {
                    switch deletion {
                    case .voice: store.deleteVoiceHistory()
                    case .eyes: store.deleteEyeHistory()
                    case .health: store.deleteHealthHistory()
                    case .all: store.clearAllScans()
                    case .account: break
                    }
                }
                self.deletion = nil
            }
            Button("Cancel", role: .cancel) { Haptics.soft(); deletion = nil }
        } message: {
            Text(deletion == .account
                ? "This permanently removes the local credential, encryption key, and every venture measurement on this device. Apple Health itself is not changed."
                : "This removes the selected encrypted metrics from venture. Apple Health itself is not changed.")
        }
    }

    private func storedRow(_ title: String, available: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(available ? "Stored" : "None")
                .font(.caption)
                .foregroundStyle(available ? VentureTheme.sage : VentureTheme.secondary)
        }
    }

    private func wipeAccount() {
        Task { @MainActor in
            let verified = await biometrics.authenticate(reason: "Permanently wipe your local venture account and encrypted data")
            guard verified else {
                wipeMessage = "Device authentication was not completed. Nothing was deleted."
                return
            }
            do {
                try await authService.deleteCurrentAccount()
                await store.wipeLocalData()
                onAccountWiped()
            } catch let authError as AccountAuthError
                where authError == .accountNotFound || authError == .backendNotConfigured {
                await store.wipeLocalData()
                onAccountWiped()
            } catch {
                wipeMessage = (error as? LocalizedError)?.errorDescription
                    ?? "The account could not be deleted. No local measurements were removed."
            }
        }
    }

    private enum Deletion: Equatable {
        case voice, eyes, health, all, account

        var title: String {
            switch self {
            case .account: "Wipe this device?"
            case .all: "Clear every scan?"
            default: "Delete this metric history?"
            }
        }

        var buttonTitle: String {
            switch self {
            case .account: "Authenticate and wipe"
            case .all: "Clear all scans"
            default: "Delete history"
            }
        }
    }
}

private struct AISettingsView: View {
    @StateObject private var localModelManager = LocalModelManager()
    @AppStorage("venture.companion.language") private var responseLanguage = CompanionLanguage.english.rawValue

    var body: some View {
        Form {
            Section("Assistant language") {
                Picker("Reply in", selection: $responseLanguage) {
                    ForEach(CompanionLanguage.allCases) { language in
                        Text(language.displayName).tag(language.rawValue)
                    }
                }
                Text("Gemma 4 and Apple’s on-device model are asked to reply in this language. The measured-signal fallback remains in English so it never invents a translation of health data.")
                    .font(.caption)
                    .foregroundStyle(VentureTheme.secondary)
            }
            Section("Privacy") {
                LabeledContent("Inference", value: "On device")
                Text("The assistant runs locally. It uses Gemma 4 when installed, Apple’s on-device model on eligible devices, and a measured-signal fallback elsewhere.")
                    .font(.caption)
                    .foregroundStyle(VentureTheme.secondary)
            }
            Section("Gemma 4 local mode") {
                LabeledContent("Model", value: "Gemma 4 E2B Q4")
                Text("Gemma runs privately through the app’s llama.cpp runtime after its optional 2.8 GB download. It is used for conversation and explanation, never to create a disease diagnosis or probability.")
                    .font(.caption)
                    .foregroundStyle(VentureTheme.secondary)
                switch localModelManager.state {
                case .downloading:
                    HStack(spacing: 9) {
                        ProgressView()
                        Text("downloading Gemma 4…")
                            .font(.subheadline)
                    }
                case .failed(let message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(VentureTheme.warm)
                    Button("Download Gemma 4 · 2.8 GB") { localModelManager.downloadGemma4() }
                case .ready:
                    Label("Gemma 4 is ready for the next local conversation", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(VentureTheme.sage)
                case .idle:
                    Button("Download Gemma 4 · 2.8 GB") { localModelManager.downloadGemma4() }
                }
            }
            Section("Voice input") {
                LabeledContent("Voice sample", value: "Six-second sustained ahhh")
                Text("The voice task captures a sustained sound locally. It does not produce a Parkinson’s score or diagnosis.")
                    .font(.caption)
                    .foregroundStyle(VentureTheme.secondary)
            }
        }
        .navigationTitle("Assistant")
    }
}

private struct ScanSettingsView: View {
    var body: some View {
        Form {
            Section("Flow") {
                LabeledContent("Eye", value: "Pupil light response")
                LabeledContent("Voice", value: "Six-second sustained ahhh")
                LabeledContent("Cognition", value: "Memory, reaction, and mood")
            }
            Section {
                Text("Each task can be skipped. venture stores extracted metrics only; raw camera frames and microphone audio are not retained.")
                    .font(.caption)
                    .foregroundStyle(VentureTheme.secondary)
            }
        }
        .navigationTitle("Scan behavior")
    }
}

private struct FocusProtectionSettingsView: View {
    @Bindable var service: CognitiveSupportService
    let sleepHours: Double?
    @State private var pickerPresented = false

    var body: some View {
        Form {
            Section {
                Text(service.capabilityAvailable
                    ? "venture can shield only apps, categories, and websites you explicitly select. iOS does not let venture silently rewrite another app’s notification settings."
                    : "This Personal Team build cannot include Apple’s Family Controls entitlement. Sleep-aware wind-down reminders still work; app shielding requires an approved distribution profile.")
                    .font(.caption)
                    .foregroundStyle(VentureTheme.secondary)
            }
            Section("Authorization") {
                LabeledContent("Screen Time", value: authorizationLabel)
                Button("Request Screen Time access") {
                    Haptics.selected()
                    Task { await service.requestScreenTimeAuthorization() }
                }
                .disabled(!service.capabilityAvailable)
                Button("Choose distractions") { Haptics.selected(); pickerPresented = true }
                    .disabled(!service.capabilityAvailable)
                LabeledContent("Selected", value: service.selectedCount.formatted())
            }
            Section("Protection") {
                VStack(alignment: .leading, spacing: 5) {
                    LabeledContent("Recommended window", value: "\(service.recommendation.durationMinutes) min")
                    Text(service.recommendation.reason)
                        .font(.caption)
                        .foregroundStyle(VentureTheme.secondary)
                }
                Toggle("Start automatically when signals are elevated", isOn: $service.automaticLowSleepProtection)
                    .disabled(!service.capabilityAvailable)
                    .onChange(of: service.automaticLowSleepProtection) {
                        Haptics.strong()
                    }
                if service.protectionActive {
                    Button("Stop protection", role: .destructive) { Haptics.strong(); service.stopProtection() }
                } else {
                    Button("Protect selected distractions") {
                        Haptics.strong()
                        Task { await service.activateProtection(sleepHours: sleepHours) }
                    }
                    .disabled(!service.capabilityAvailable)
                }
                Button("Enable sleep-aware wind-down reminder") {
                    Haptics.selected()
                    Task { await service.scheduleWindDownReminder(sleepHours: sleepHours) }
                }
                LabeledContent("Reminder", value: service.notificationStatus)
            }
            if let message = service.message {
                Section { Text(message).font(.caption).foregroundStyle(VentureTheme.secondary) }
            }
        }
        .navigationTitle("Focus protection")
        .familyActivityPicker(
            headerText: "Select only what you want venture to shield.",
            footerText: "You can stop protection at any time.",
            isPresented: $pickerPresented,
            selection: $service.selection
        )
        .onAppear {
            service.reconcileProtectionWindow()
        }
    }

    private var authorizationLabel: String {
        if !service.capabilityAvailable { return "Requires approved profile" }
        if service.isAuthorized { return "Approved" }
        return service.authorizationStatus == .denied ? "Denied" : "Not requested"
    }
}

private struct HealthSettingsView: View {
    @Bindable var store: VentureStore

    private var service: HealthService { store.healthService }

    var body: some View {
        List {
            Section {
                HStack {
                    Label("Apple Health", systemImage: "heart.fill")
                    Spacer()
                    Text(service.state.rawValue)
                        .font(.caption)
                        .foregroundStyle(service.state == .connected ? VentureTheme.sage : VentureTheme.secondary)
                }
                Button(service.state == .connected ? "Health access granted" : "Connect Apple Health") {
                    Haptics.selected()
                    Task {
                        await service.requestAccess()
                        await store.refreshHealth()
                    }
                }
                .disabled(service.state == .connected || service.state == .unavailable)

                if service.state == .connected {
                    Button {
                        Haptics.selected()
                        Task { await store.refreshHealth() }
                    } label: {
                        HStack {
                            Text("Refresh health data")
                            Spacer()
                            if service.isRefreshing { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(service.isRefreshing)
                }
            }

            Section("Latest signals") {
                healthValue("HRV", value: service.latest.heartRateVariabilityMilliseconds, unit: "ms")
                healthValue("Resting heart rate", value: service.latest.restingHeartRateBPM, unit: "bpm")
                healthValue("Sleep", value: service.latest.sleepHours, unit: "hr", precision: 1)
                healthPercent("Sleep quality estimate", value: service.latest.sleepQuality)
                healthValue("Oxygen saturation", value: service.latest.oxygenSaturationPercent, unit: "%", precision: 1)
                healthValue("Steps today", value: service.latest.stepCount, unit: "", precision: 0)
                healthValue("Active energy", value: service.latest.activeEnergyKilocalories, unit: "kcal", precision: 0)
                if let systolic = service.latest.bloodPressureSystolicMMHg,
                   let diastolic = service.latest.bloodPressureDiastolicMMHg {
                    LabeledContent("Blood pressure", value: "\(Int(systolic.rounded()))/\(Int(diastolic.rounded())) mmHg")
                    Text(BloodPressureBand.classify(systolic: systolic, diastolic: diastolic).rawValue)
                        .font(.caption2)
                        .foregroundStyle(VentureTheme.secondary)
                } else {
                    LabeledContent("Blood pressure", value: "No cuff reading")
                }

                if let updatedAt = service.latest.updatedAt {
                    Text("Synced \(updatedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(VentureTheme.secondary)
                }
                if let errorMessage = service.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(VentureTheme.secondary)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Apple Watch ECG")
                        .font(.subheadline.weight(.medium))
                    Text("Record an ECG in Apple’s ECG app on Apple Watch. venture can import the newest HealthKit recording, but cannot start the Watch recording or diagnose the trace.")
                        .font(.caption)
                        .foregroundStyle(VentureTheme.secondary)
                    if let date = service.latest.electrocardiogramDate {
                        LabeledContent("Latest recording", value: date.formatted(.dateTime.month().day().hour().minute()))
                    }
                    Button {
                        Task { await store.importLatestECG() }
                    } label: {
                        HStack {
                            Text(service.isImportingECG ? "Checking Apple Health…" : service.state == .connected ? "Import latest Watch ECG" : "Connect Health and import ECG")
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                            Spacer()
                            if service.isImportingECG { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(service.isImportingECG)
                    if let message = service.ecgMessage {
                        Text(message).font(.caption2).foregroundStyle(VentureTheme.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Text("Apple Watch measurements appear through Apple Health. venture reads measurements only and never writes health data.")
                    .font(.caption)
                    .foregroundStyle(VentureTheme.secondary)
            }
        }
        .navigationTitle("Health integrations")
    }

    private func healthValue(
        _ title: String,
        value: Double?,
        unit: String,
        precision: Int = 0
    ) -> some View {
        LabeledContent(title) {
            if let value {
                Text("\(value.formatted(.number.precision(.fractionLength(precision)))) \(unit)")
            } else {
                Text("No sample").foregroundStyle(VentureTheme.secondary)
            }
        }
    }

    private func healthPercent(_ title: String, value: Double?) -> some View {
        LabeledContent(title) {
            if let value {
                Text(value.formatted(.percent.precision(.fractionLength(0))))
            } else {
                Text("No sample").foregroundStyle(VentureTheme.secondary)
            }
        }
    }
}
