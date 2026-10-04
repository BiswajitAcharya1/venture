import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var store: VentureStore
    private let accountAuth = AccountAuthService()

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var presentedSheet: AppSheet?
    @State private var settingsPresented = false
    @State private var assistantPresented = false
    @State private var assistantClosing = false
    @State private var bootstrapFinished = false
    @State private var returningFromSignOut = false
    @State private var signOutTransitionPresented = false
    @State private var lastSyncedMeasurementAt: Date?
    @State private var backendSyncInFlight = false
    @State private var authenticationGateID = UUID()

    var body: some View {
        ZStack {
            if !bootstrapFinished {
                BootstrapView()
                    .transition(.opacity)
            } else if hasCompletedOnboarding {
                mainApp
            } else if returningFromSignOut {
                AuthenticationView {
                    withAnimation(.easeOut(duration: 0.4)) {
                        returningFromSignOut = false
                        hasCompletedOnboarding = true
                    }
                }
                .id(authenticationGateID)
                .transition(.scale(scale: 1.04).combined(with: .opacity))
            } else {
                OnboardingFlowView(store: store) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        hasCompletedOnboarding = true
                    }
                    Task { @MainActor in
                        await Task.yield()
                        routePendingSystemAction()
                    }
                }
                .transition(.opacity)
            }

            if signOutTransitionPresented {
                PortalHandoffView(direction: .out)
                    .transition(.opacity)
                    .zIndex(20)
            }

        }
        .tint(VentureTheme.warm)
        .buttonStyle(StrongHapticButtonStyle())
        .onAppear {
#if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-skipOnboarding") || arguments.contains("-scanPreview") || arguments.contains("-eyePreview") || arguments.contains("-voicePreview") || arguments.contains("-moodResultPreview") || arguments.contains("-assistantPreview") || arguments.contains("-bloodPressurePreview") {
                hasCompletedOnboarding = true
            } else if arguments.contains("-resetOnboarding") || arguments.contains("-authPreview") {
                hasCompletedOnboarding = false
            }
            if arguments.contains("-scanPreview") || arguments.contains("-eyePreview") || arguments.contains("-voicePreview") || arguments.contains("-moodResultPreview") {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2.5))
                    presentedSheet = .scan
                }
            }
            if arguments.contains("-assistantPreview") {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2.5))
                    withAnimation { assistantPresented = true }
                }
            }
#endif
        }
        .task {
            let startedAt = ContinuousClock.now
            while !store.isReady {
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled else { return }
            }
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-bloodPressurePreview") {
                _ = store.recordCuffBloodPressure(systolic: 148, diastolic: 94)
            }
#endif
            let elapsed = startedAt.duration(to: .now)
            if elapsed < .seconds(2.1) {
                try? await Task.sleep(for: .seconds(2.1) - elapsed)
            }
            withAnimation(.easeInOut(duration: 0.55)) {
                bootstrapFinished = true
            }
            await requireAuthenticatedSessionIfNeeded()
            routePendingSystemAction()
            await syncLatestMeasurementsIfPossible(force: true)
        }
        .task(id: hasCompletedOnboarding, priority: .utility) {
#if targetEnvironment(simulator)
            return
#else
            guard hasCompletedOnboarding, BundledLlamaEngine.isBundled else { return }
#if DEBUG
            let process = ProcessInfo.processInfo
            guard process.environment["XCTestConfigurationFilePath"] == nil,
                  !process.arguments.contains("-skipModelWarmup")
            else { return }
#endif
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            _ = await BundledLlamaEngine.shared.prepare()
#endif
        }
        .onChange(of: store.healthService.latest) {
            store.ingestHealthUpdate()
            Task { await syncLatestMeasurementsIfPossible(force: true) }
        }
        .onChange(of: store.snapshots) {
            Task { await syncLatestMeasurementsIfPossible() }
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            routePendingSystemAction()
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            Task(priority: .utility) {
                await BundledLlamaEngine.shared.release()
            }
        }
    }

    private var mainApp: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $store.selectedTab) {
                tabContent(.home) {
                    HomeView(store: store, presentedSheet: $presentedSheet, onAskVenture: presentAssistant)
                }
                tabContent(.insights) {
                    InsightsView(store: store)
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .tabBar)

            if assistantPresented {
                Color.black.opacity(assistantClosing ? 0 : 0.38)
                    .ignoresSafeArea()
                    .onTapGesture(perform: dismissAssistant)

                CompanionView(store: store) {
                    dismissAssistant()
                }
                .frame(maxWidth: 410, minHeight: 520, maxHeight: 590)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(VentureTheme.line, lineWidth: 0.8) }
                .shadow(color: VentureTheme.ink.opacity(0.14), radius: 30, x: 0, y: 18)
                .padding(.horizontal, 12)
                .padding(.bottom, 126)
                .scaleEffect(assistantClosing ? 0.72 : 1, anchor: .bottomTrailing)
                .offset(x: assistantClosing ? 26 : 0, y: assistantClosing ? 92 : 0)
                .rotationEffect(.degrees(assistantClosing ? 2.5 : 0), anchor: .bottomTrailing)
                .blur(radius: assistantClosing ? 10 : 0)
                .opacity(assistantClosing ? 0 : 1)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.82, anchor: .bottomTrailing).combined(with: .move(edge: .bottom)).combined(with: .opacity),
                        removal: .scale(scale: 0.72, anchor: .bottomTrailing).combined(with: .move(edge: .bottom)).combined(with: .opacity)
                    )
                )
            }

            if store.selectedTab != .home {
                RotatingAssistantButton(isExpanded: assistantBinding)
                    .padding(.trailing, 18)
                    .padding(.bottom, 236)
            }
        }
        .animation(.spring(response: 0.48, dampingFraction: 0.84), value: assistantPresented)
        .animation(.timingCurve(0.22, 0.76, 0.24, 1, duration: 0.34), value: assistantClosing)
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .scan:
                ScanFlowView(store: store)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled()
            }
        }
        .sheet(isPresented: $settingsPresented) {
            SettingsView(store: store) {
                beginSignOut()
            }
        }
    }

    private var assistantBinding: Binding<Bool> {
        Binding(
            get: { assistantPresented },
            set: { expanded in
                if expanded {
                    assistantClosing = false
                    withAnimation(.spring(response: 0.48, dampingFraction: 0.84)) {
                        assistantPresented = true
                    }
                } else {
                    dismissAssistant()
                }
            }
        )
    }

    private func presentAssistant() {
        guard !assistantPresented else { return }
        assistantClosing = false
        withAnimation(.spring(response: 0.48, dampingFraction: 0.84)) {
            assistantPresented = true
        }
    }

    private func dismissAssistant() {
        guard assistantPresented, !assistantClosing else { return }
        Haptics.soft()
        withAnimation(.timingCurve(0.22, 0.76, 0.24, 1, duration: 0.34)) {
            assistantClosing = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(340))
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                assistantPresented = false
                assistantClosing = false
            }
        }
    }

    private func beginSignOut() {
        assistantPresented = false
        settingsPresented = false
        withAnimation(.easeIn(duration: 0.22)) { signOutTransitionPresented = true }
        Task { @MainActor in
            await accountAuth.clearSession()
            try? await Task.sleep(for: .milliseconds(360))
            returningFromSignOut = true
            hasCompletedOnboarding = false
            try? await Task.sleep(for: .milliseconds(330))
            withAnimation(.easeOut(duration: 0.34)) { signOutTransitionPresented = false }
        }
    }

    private func requireAuthenticatedSessionIfNeeded() async {
        guard AccountBackendConfiguration.fromBundle.requiresAuthenticatedSession, hasCompletedOnboarding else { return }
        do {
            guard try await accountAuth.refreshSessionIfNeeded() != nil else {
                showAuthenticationGate()
                return
            }
        } catch {
            await accountAuth.clearSession()
            showAuthenticationGate()
        }
    }

    @MainActor
    private func syncLatestMeasurementsIfPossible(force: Bool = false) async {
        guard hasCompletedOnboarding, !backendSyncInFlight else { return }
        guard let supabase = AccountBackendConfiguration.fromBundle.supabase else { return }
        guard let session = try? await accountAuth.refreshSessionIfNeeded(),
              let userID = UUID(uuidString: session.userID),
              let batch = store.makeBackendSyncBatch(
                userID: userID,
                email: session.email,
                displayName: session.displayName,
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                deviceModel: UIDevice.current.model
              )
        else { return }
        guard force || lastSyncedMeasurementAt != batch.scan.capturedAt else { return }

        backendSyncInFlight = true
        defer { backendSyncInFlight = false }

        let service = SupabaseBackendSyncService(
            projectURL: supabase.projectURL,
            anonKey: supabase.anonKey,
            accessToken: session.accessToken
        )
        do {
            try await service.sync(batch)
            lastSyncedMeasurementAt = batch.scan.capturedAt
        } catch {
            // Local scan history remains the source of truth when the network or backend is unavailable.
        }
    }

    @MainActor
    private func showAuthenticationGate(remountAuthentication: Bool = false) {
        if remountAuthentication {
            authenticationGateID = UUID()
        }
        withAnimation(.easeInOut(duration: 0.28)) {
            returningFromSignOut = true
            hasCompletedOnboarding = false
        }
    }

    private func routePendingSystemAction() {
        guard bootstrapFinished, hasCompletedOnboarding else { return }
        guard let route = VentureSystemRouteStore.consume() else { return }
        store.selectedTab = .home
        switch route {
        case .scan:
            assistantPresented = false
            presentedSheet = .scan
        case .assistant:
            presentedSheet = nil
            withAnimation(.spring(response: 0.46, dampingFraction: 0.82)) {
                assistantPresented = true
            }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        Task { @MainActor in
            do {
                guard try await accountAuth.handlePasswordRecoveryURL(url) else { return }
                AuthDeepLinkNoticeStore.save("reset link verified. choose a new password.")
                showAuthenticationGate(remountAuthentication: true)
                Haptics.success()
            } catch {
                let message = (error as? LocalizedError)?.errorDescription
                    ?? "reset link could not be verified. send a new link."
                AuthDeepLinkNoticeStore.save(message)
                showAuthenticationGate(remountAuthentication: true)
                Haptics.soft()
            }
        }
    }

    private func tabContent<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Haptics.selected()
                            settingsPresented = true
                        } label: {
                            VentureAccountMark()
                        }
                        .accessibilityLabel("Open settings")
                    }
                }
                .toolbarBackground(VentureTheme.background.opacity(0.92), for: .navigationBar)
        }
        .tabItem { Label(tab.title, systemImage: tab.symbol) }
        .tag(tab)
    }
}

private struct PortalHandoffView: View {
    enum Direction { case out }

    let direction: Direction
    @State private var expanded = false

    var body: some View {
        ZStack {
            VentureAtmosphereView().ignoresSafeArea()
            LivingPortalView(size: 210, intensity: 1.22, interactive: false)
                .scaleEffect(expanded ? 6.4 : 0.55)
                .blur(radius: expanded ? 22 : 0)
                .opacity(expanded ? 0.88 : 1)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.68)) { expanded = true }
        }
        .accessibilityHidden(true)
    }
}
