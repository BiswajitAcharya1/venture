import AVFoundation
import SwiftUI

// The redesigned flow deliberately has no disease-score dashboard.
struct VentureExperienceView: View {
    @Bindable var store: VentureStore
    @State private var locale = VentureLocale()
    @State private var step = -1
    @State private var tab = 0
    @State private var settings = false
    @State private var choosingLanguage = false
    @State private var scan = false
    @State private var help = false
    @State private var session: AuthSession?
    @State private var restored = false
    @StateObject private var callingService = VentureCallingService()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let auth = AccountAuthService()

    var body: some View {
        ZStack {
            VentureCanvas.background.ignoresSafeArea()
            LinearGradient(
                colors: [VentureCanvas.accent.opacity(0.045), .clear, VentureTheme.warm.opacity(0.035)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ).ignoresSafeArea().allowsHitTesting(false)
            if !restored { ProgressView().tint(VentureCanvas.accent) }
            else if step == -1 {
                LaunchView {
                    withAnimation(.easeOut(duration: reduceMotion ? 0.18 : 0.42)) {
                        step = 1
                    }
                }
                .transition(.opacity)
            }
            else if step == 1 {
                VentureAccountView(locale: locale, onChooseLanguage: { choosingLanguage = true }) { account in
                    Task {
                        session = account
                        await store.beginSession(userID: account?.userID)
                        step = 2
                    }
                }
                .transition(.opacity)
            } else if step == 2 {
                VenturePermissionsView(locale: locale) { step = 3 }
            } else if step == 3 {
                VentureSimpleScanView(store: store, locale: locale) { tab = 1; step = 4 }
            } else { main }
        }
        .foregroundStyle(VentureCanvas.ink)
        .tint(VentureCanvas.accent)
        .environment(\.locale, Locale(identifier: locale.language.id))
        .environment(\.layoutDirection, locale.language.isRTL ? .rightToLeft : .leftToRight)
        .buttonStyle(VentureQuietButtonStyle())
        .sheet(isPresented: $settings) { settingsView }
        .sheet(isPresented: $help) {
            NavigationStack {
                VentureCarePage(store: store, locale: locale, calling: callingService)
                    .background(VentureCanvas.background)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(locale.t(.done)) { help = false } } }
            }.tint(VentureCanvas.accent).foregroundStyle(VentureCanvas.ink)
                .environment(\.locale, Locale(identifier: locale.language.id))
                .environment(\.layoutDirection, locale.language.isRTL ? .rightToLeft : .leftToRight)
                .buttonStyle(VentureQuietButtonStyle())
        }
        .sheet(isPresented: $choosingLanguage) {
            languagePicker
                .background(VentureCanvas.background)
                .foregroundStyle(VentureCanvas.ink)
                .tint(VentureCanvas.accent)
                .buttonStyle(VentureQuietButtonStyle())
                .environment(\.locale, Locale(identifier: locale.language.id))
                .environment(\.layoutDirection, locale.language.isRTL ? .rightToLeft : .leftToRight)
        }
        .fullScreenCover(isPresented: $scan) {
            VentureSimpleScanView(store: store, locale: locale) { tab = 1; scan = false }
                .environment(\.locale, Locale(identifier: locale.language.id))
                .environment(\.layoutDirection, locale.language.isRTL ? .rightToLeft : .leftToRight)
                .buttonStyle(VentureQuietButtonStyle())
        }
        .task {
            while !store.isReady {
                try? await Task.sleep(for: .milliseconds(40))
                guard !Task.isCancelled else { return }
            }
            session = try? await auth.refreshSessionIfNeeded()
            await store.beginSession(userID: session?.userID)
            if session != nil, UserDefaults.standard.bool(forKey: "venture.experience.completed") { step = 4 }
            if ProcessInfo.processInfo.arguments.contains("-resetExperience") || ProcessInfo.processInfo.arguments.contains("-resetOnboarding") { step = -1 }
            if ProcessInfo.processInfo.arguments.contains("-authPreview") { step = 1 }
            if ProcessInfo.processInfo.arguments.contains("-skipOnboarding") { step = 4 }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-voiceResultsFixture") {
                let poorQuality = ProcessInfo.processInfo.arguments.contains("-poorVoiceQuality")
                store.snapshots = [CognitiveSnapshot(
                    capturedAt: .now, voiceActivityRatio: poorQuality ? 0.1 : 0.83, noiseLevel: poorQuality ? 0.7 : 0.06,
                    spontaneousWordCount: poorQuality ? nil : 42,
                    voiceAcousticSummary: VoiceAcousticSummary(pitchHz: 188, pitchVariation: 0.08, amplitudeVariation: 0.13,
                        voicedSeconds: poorQuality ? 0.5 : 13.9, recordingQuality: poorQuality ? 0.2 : 0.84, clippingRatio: 0.001)
                )]
                tab = 1; step = 4
            }
            #endif
            restored = true
            route()
        }
        .onChange(of: step) { _, value in
            if value == 4 { UserDefaults.standard.set(true, forKey: "venture.experience.completed") }
        }
        .onOpenURL { url in
            Task { _ = try? await auth.handlePasswordRecoveryURL(url) }
        }
    }

    private var languagePicker: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("venture").font(.system(size: 32, weight: .medium, design: .rounded)).tracking(-1)
                Spacer()
                Image(systemName: "globe").font(.system(size: 20, weight: .light))
                    .foregroundStyle(VentureCanvas.accent).frame(width: 48, height: 48)
                    .background(VentureCanvas.surface, in: Circle())
            }
            Text(locale.t(.language)).font(.system(size: 28, weight: .regular, design: .rounded))
            languageList
            VentureAction(title: locale.t(.next), symbol: "arrow.right") { choosingLanguage = false }
        }.padding(28)
    }

    private var languageList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(VentureLanguage.all) { language in
                    Button {
                        Haptics.selected()
                        locale.language = language
                    } label: {
                        HStack {
                            Text(language.name).font(.system(size: 18, weight: language == locale.language ? .medium : .regular))
                            Spacer()
                            if language == locale.language { Image(systemName: "checkmark.circle.fill").foregroundStyle(VentureCanvas.accent) }
                        }.padding(.vertical, 13).padding(.horizontal, 14)
                            .background(language == locale.language ? VentureCanvas.surface : .clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(language == locale.language ? VentureCanvas.accent.opacity(0.22) : .clear, lineWidth: 1)
                            }
                    }.accessibilityIdentifier("language-\(language.id)")
                }
            }
        }.scrollIndicators(.hidden)
    }

    private var main: some View {
        VStack(spacing: 0) {
            HStack {
                Text("venture").font(.system(size: 25, weight: .medium, design: .rounded)).tracking(-0.7)
                Spacer()
                Button { settings = true } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 17, weight: .regular))
                        .frame(width: 44, height: 44).background(VentureCanvas.surface, in: Circle())
                        .overlay { Circle().stroke(VentureCanvas.line, lineWidth: 0.8) }
                }
                    .accessibilityLabel(locale.t(.settings)).accessibilityIdentifier("settings")
            }.padding(.horizontal, 25).padding(.top, 8)
            Group {
                switch tab {
                case 1: insights
                case 2: VentureAssistantPage(store: store, locale: locale)
                case 3: VentureCarePage(store: store, locale: locale, calling: callingService)
                default: home
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: tab)
            HStack(spacing: 0) {
                tabButton(0, .home, "circle.grid.2x2")
                tabButton(1, .insights, "waveform.path")
                tabButton(2, .assistant, "bubble.left.and.bubble.right")
                tabButton(3, .care, "heart")
            }.padding(.horizontal, 6).padding(.vertical, 8)
                .background(VentureCanvas.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(VentureCanvas.line, lineWidth: 0.8) }
                .shadow(color: VentureCanvas.ink.opacity(0.045), radius: 18, y: 6)
                .padding(.horizontal, 20).padding(.bottom, 8)
        }
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 10) {
                    Image(systemName: "mic").font(.system(size: 17, weight: .regular))
                    Text(locale.support(.voiceCheck)).font(.footnote.weight(.medium))
                    Spacer()
                    if store.scanCompletedToday { Image(systemName: "checkmark.circle.fill").foregroundStyle(VentureCanvas.accent) }
                }.foregroundStyle(VentureCanvas.accent)
                ZStack {
                    Circle().fill(VentureCanvas.accent.opacity(0.06)).padding(1)
                    Circle().stroke(VentureCanvas.accent.opacity(0.12), lineWidth: 1).padding(14)
                    Circle().fill(
                        RadialGradient(colors: [VentureCanvas.surface, VentureTheme.surfaceMuted, VentureTheme.sage.opacity(0.3)], center: .init(x: 0.35, y: 0.28), startRadius: 0, endRadius: 190)
                    ).padding(34)
                    Circle().stroke(VentureCanvas.surface.opacity(0.8), lineWidth: 1).padding(34)
                    Image(systemName: "waveform").font(.system(size: 58, weight: .ultraLight)).foregroundStyle(VentureCanvas.accent)
                }.frame(maxWidth: .infinity).frame(height: 230).accessibilityHidden(true)
                VentureAction(title: locale.t(.start), symbol: "arrow.up.right") { scan = true }
                    .accessibilityIdentifier("start-scan")
                HStack {
                    Text(locale.t(.screening)).font(.footnote).foregroundStyle(VentureCanvas.muted)
                    Spacer()
                }
                if session == nil { Text(locale.t(.guestNote)).font(.footnote).foregroundStyle(VentureCanvas.muted) }
                HStack(spacing: 12) {
                    shortcut(.insights, "waveform.path", 1)
                    shortcut(.assistant, "bubble.left", 2)
                    shortcut(.care, "heart", 3)
                }
            }.padding(28)
        }.scrollIndicators(.hidden)
    }

    private var insights: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(locale.support(.results)).font(.system(size: 32, weight: .regular, design: .rounded)).tracking(-0.8)
                    .accessibilityIdentifier("voice-results-title")
                if let latest = voiceSnapshots.last {
                    VentureVoiceResultsCard(snapshot: latest, locale: locale)
                    if latest.voiceAcousticSummary?.isUsable == false {
                        VentureAction(title: locale.t(.retry), symbol: "mic") { scan = true }
                            .accessibilityIdentifier("retake-voice")
                    }
                    nextStep
                    if voiceSnapshots.count > 1 {
                        Text(locale.t(.insights)).font(.title3.weight(.medium)).padding(.top, 4)
                        ForEach(voiceSnapshots.dropLast().reversed(), id: \.capturedAt) { sample in
                            HStack(spacing: 14) {
                                Image(systemName: "waveform").foregroundStyle(VentureCanvas.accent)
                                Text(sample.capturedAt, format: .dateTime.day().month().hour().minute()).font(.subheadline)
                                Spacer()
                                Text(locale.t(.saved)).font(.caption).foregroundStyle(VentureCanvas.muted)
                            }.padding(20).ventureSurface(cornerRadius: 22)
                        }
                    }
                } else {
                    Image(systemName: "waveform.path").font(.system(size: 50, weight: .ultraLight)).foregroundStyle(VentureCanvas.accent).padding(.top, 40)
                    Text(locale.t(.empty)).foregroundStyle(VentureCanvas.muted).accessibilityIdentifier("no-voice-measurements")
                    VentureAction(title: locale.t(.start), symbol: "arrow.right") { scan = true }
                    nextStep
                }
                Text(locale.t(.screening)).font(.footnote).foregroundStyle(VentureCanvas.muted)
                if !locale.hasTranslatedSupport { Text(locale.support(.englishNotice)).font(.caption).foregroundStyle(VentureCanvas.muted) }
            }.padding(28)
        }.scrollIndicators(.hidden).safeAreaInset(edge: .bottom, spacing: 0) {
            VentureAction(title: locale.support(.getHelp), symbol: "heart") { help = true }
                .accessibilityIdentifier("get-help").padding(.horizontal, 28).padding(.top, 10).padding(.bottom, 14)
                .background(VentureCanvas.background.opacity(0.97))
        }
    }

    private var voiceSnapshots: [CognitiveSnapshot] {
        store.snapshots.filter { $0.voiceAcousticSummary != nil || $0.voiceActivityRatio != nil || $0.spontaneousWordCount != nil || $0.voiceResearchResult?.isUsable == true }
    }

    private var nextStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "leaf").foregroundStyle(VentureCanvas.accent)
                Text(locale.support(.nextTitle)).font(.subheadline.weight(.semibold))
            }
            Text(locale.support(.nextNote)).font(.subheadline).foregroundStyle(VentureCanvas.muted).lineSpacing(3)
        }.padding(24).background(VentureCanvas.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func shortcut(_ key: VentureCopy, _ icon: String, _ destination: Int) -> some View {
        Button { tab = destination } label: {
            VStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 21, weight: .light)).foregroundStyle(VentureCanvas.accent)
                Text(key == .care ? locale.support(.getHelp) : locale.t(key)).font(.caption.weight(.medium))
            }.frame(maxWidth: .infinity).frame(minHeight: 96).ventureSurface(cornerRadius: 24)
        }
    }

    private func tabButton(_ destination: Int, _ key: VentureCopy, _ icon: String) -> some View {
        Button { Haptics.selected(); tab = destination } label: {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 20, weight: tab == destination ? .medium : .regular))
                    .frame(width: 44, height: 28)
                    .background(tab == destination ? VentureCanvas.accent.opacity(0.09) : .clear, in: Capsule())
                Text(key == .care ? locale.support(.getHelp) : locale.t(key)).font(.system(size: 10, weight: tab == destination ? .semibold : .regular))
            }.foregroundStyle(tab == destination ? VentureCanvas.accent : VentureCanvas.muted).frame(maxWidth: .infinity).frame(minHeight: 48)
        }.accessibilityIdentifier("tab-\(destination)")
    }

    private var settingsView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(locale.t(.language)).font(.title2)
                    ForEach(VentureLanguage.all) { language in
                        Button { locale.language = language; Haptics.selected() } label: {
                            HStack { Text(language.name); Spacer(); if locale.language == language { Image(systemName: "checkmark") } }.padding(.vertical, 8)
                        }
                    }
                    Text(session?.email ?? locale.t(.guest)).font(.footnote).foregroundStyle(VentureCanvas.muted)
                    Text(locale.t(.screening)).font(.footnote)
                    Link("VOICED · Cesari et al. · ODC-By 1.0", destination: URL(string: "https://physionet.org/content/voiced/1.0.0/")!).font(.caption)
                    if session == nil { Text(locale.t(.guestNote)).font(.footnote) }
                    Button(locale.t(.signOut)) {
                        Task {
                            await auth.clearSession()
                            await store.beginSession(userID: nil)
                            session = nil; settings = false; step = 1
                        }
                    }
                }.padding(28)
            }.background(VentureCanvas.background).navigationTitle(locale.t(.settings))
                .toolbar { Button(locale.t(.done)) { settings = false } }
        }.foregroundStyle(VentureCanvas.ink).tint(VentureCanvas.accent)
            .environment(\.locale, Locale(identifier: locale.language.id))
            .environment(\.layoutDirection, locale.language.isRTL ? .rightToLeft : .leftToRight)
    }

    private func route() {
        guard step == 4, let pending = VentureSystemRouteStore.consume() else { return }
        if pending == .scan { scan = true } else { tab = 2 }
    }
}

enum VentureCanvas {
    static let background = VentureTheme.background
    static let surface = VentureTheme.surface
    static let ink = VentureTheme.ink
    static let muted = VentureTheme.secondary
    static let accent = VentureTheme.primaryFill
    static let line = VentureTheme.line
}

struct VentureQuietButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.contentShape(Rectangle())
            .opacity(enabled ? (configuration.isPressed ? 0.82 : 1) : 0.48)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct VentureAction: View {
    let title: String
    var symbol: String = "arrow.right"
    var action: () -> Void
    var body: some View {
        Button { Haptics.strong(); action() } label: {
            HStack { Text(title).font(.system(size: 16, weight: .semibold)); Spacer(); Image(systemName: symbol).font(.system(size: 15, weight: .medium)) }
                .padding(.horizontal, 22).padding(.vertical, 21).foregroundStyle(.white)
                .background(VentureCanvas.accent, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 0.8) }
                .shadow(color: VentureCanvas.accent.opacity(0.13), radius: 14, y: 5)
        }.frame(minHeight: 60)
    }
}

extension View {
    func ventureSurface(cornerRadius: CGFloat = 24) -> some View {
        self
            .background(VentureCanvas.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(VentureCanvas.line, lineWidth: 0.8) }
    }
}

struct VenturePermissionsView: View {
    var locale: VentureLocale
    var onContinue: () -> Void
    @State private var microphone = AVAudioSession.sharedInstance().recordPermission == .granted
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            Text(locale.t(.permissions)).font(.largeTitle.weight(.light))
            permission(.microphone, "mic", microphone) {
                microphone = await SensorAuthorizationService().requestMicrophoneAccess()
            }
            Text(locale.support(.voiceTip)).font(.subheadline).foregroundStyle(VentureCanvas.muted)
            Text(locale.t(.screening)).font(.footnote).foregroundStyle(VentureCanvas.muted)
            Spacer()
            VentureAction(title: locale.t(.next)) { onContinue() }
        }.padding(28).background(VentureCanvas.background)
    }
    private func permission(_ key: VentureCopy, _ symbol: String, _ allowed: Bool, action: @escaping () async -> Void) -> some View {
        HStack {
            Image(systemName: symbol).font(.title2).frame(width: 40)
            Text(locale.t(key)); Spacer()
            Button { Task { await action() } } label: {
                if allowed { Image(systemName: "checkmark.circle.fill").foregroundStyle(VentureCanvas.accent) }
                else { Text(locale.t(.allow)) }
            }.frame(minWidth: 60, minHeight: 48)
        }.padding(20).background(VentureCanvas.surface, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct VentureVoiceResultsCard: View {
    let snapshot: CognitiveSnapshot
    let locale: VentureLocale
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text(snapshot.capturedAt, format: .dateTime.day().month().hour().minute())
                    .font(.caption).foregroundStyle(VentureCanvas.muted)
                Spacer()
                Image(systemName: "waveform").font(.title3.weight(.light)).foregroundStyle(VentureCanvas.accent)
            }
            VStack(alignment: .leading, spacing: 15) {
                Text(locale.support(.measured)).font(.caption.weight(.medium)).foregroundStyle(VentureCanvas.accent)
                Text(locale.support(.resultIntro)).font(.system(size: 27, weight: .regular, design: .rounded)).tracking(-0.5)
                if let acoustic = snapshot.voiceAcousticSummary {
                    Label(locale.support(acoustic.isUsable ? .recordingCaptured : .retryQuality), systemImage: acoustic.isUsable ? "checkmark.circle" : "arrow.clockwise")
                        .font(.footnote.weight(.medium)).foregroundStyle(VentureCanvas.accent)
                        .padding(.horizontal, 13).padding(.vertical, 10)
                        .background(VentureCanvas.accent.opacity(0.07), in: Capsule())
                        .accessibilityIdentifier("recording-quality-status")
                }
            }
            if let acoustic = snapshot.voiceAcousticSummary {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text(locale.support(.quality)).font(.caption).foregroundStyle(VentureCanvas.muted)
                        Spacer()
                        Text(acoustic.recordingQuality, format: .number.precision(.fractionLength(2)))
                            .font(.caption.monospacedDigit()).foregroundStyle(VentureCanvas.accent)
                        Text("/ 1").font(.caption).foregroundStyle(VentureCanvas.muted)
                    }
                    ProgressView(value: min(1, max(0, acoustic.recordingQuality)))
                        .tint(VentureCanvas.accent).accessibilityLabel(locale.support(.quality))
                }
            }
            if !facts.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading)] + (typeSize.isAccessibilitySize ? [] : [GridItem(.flexible(), alignment: .leading)]), spacing: 12) {
                    ForEach(facts, id: \.key) { fact in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(locale.support(fact.key)).font(.caption).foregroundStyle(VentureCanvas.muted)
                            Text(fact.value).font(.system(size: 24, weight: .regular, design: .rounded)).monospacedDigit()
                                .foregroundStyle(VentureCanvas.ink).minimumScaleFactor(0.8)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(17)
                            .background(VentureTheme.surfaceMuted.opacity(0.42), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .accessibilityElement(children: .combine).accessibilityIdentifier("voice-fact-\(fact.key.rawValue)")
                    }
                }
                Text(locale.support(.variationNote)).font(.caption).foregroundStyle(VentureCanvas.muted).lineSpacing(2)
            }
            if let research = snapshot.voiceResearchResult, research.isUsable {
                VStack(alignment: .leading, spacing: 12) {
                    Label(locale.support(.researchTitle), systemImage: "flask")
                        .font(.subheadline.weight(.medium)).foregroundStyle(VentureCanvas.accent)
                    HStack {
                        Text(locale.support(.researchSimilarity)).font(.caption).foregroundStyle(VentureCanvas.muted)
                        Spacer()
                        Text(research.researchMatch, format: .number.precision(.fractionLength(2)))
                            .font(.title3.monospacedDigit())
                        Text("/ 1").font(.caption).foregroundStyle(VentureCanvas.muted)
                    }
                    Text(locale.support(.researchNote)).font(.footnote).foregroundStyle(VentureCanvas.muted).lineSpacing(3)
                    Link("SSL4PR · HuBERT · source", destination: URL(string: "https://github.com/K-STMLab/SSL4PR")!).font(.caption)
                }.padding(18).background(VentureCanvas.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 20))
                    .accessibilityIdentifier("voice-research-result")
            }
            VStack(alignment: .leading, spacing: 9) {
                Label(locale.support(.modelTitle), systemImage: "info.circle")
                    .font(.subheadline.weight(.medium)).foregroundStyle(VentureCanvas.accent)
                    .accessibilityIdentifier("disease-model-status")
                Text(locale.support(.modelNote)).font(.footnote).foregroundStyle(VentureCanvas.muted).lineSpacing(3)
            }
        }.padding(24).ventureSurface(cornerRadius: 30)
    }

    private var facts: [Fact] {
        var result: [Fact] = []
        // A poor recording cannot supply apparently reliable vocal features.
        if let acoustic = snapshot.voiceAcousticSummary, acoustic.isUsable {
            if let pitch = acoustic.pitchHz { result.append(Fact(key: .pitch, value: String(format: "%.0f Hz", pitch))) }
            result.append(Fact(key: .voicedTime, value: String(format: "%.1f s", acoustic.voicedSeconds)))
            if let variation = acoustic.pitchVariation { result.append(Fact(key: .pitchVariation, value: String(format: "%.2f", variation))) }
            if let variation = acoustic.amplitudeVariation { result.append(Fact(key: .loudnessVariation, value: String(format: "%.2f", variation))) }
        }
        if let words = snapshot.spontaneousWordCount, words > 0 { result.append(Fact(key: .words, value: String(words))) }
        return result
    }

    private struct Fact { let key: VentureSupportCopy; let value: String }
}

enum VentureVoiceEvidenceSummary {
    static func text(snapshot: CognitiveSnapshot?) -> String {
        guard let sample = snapshot?.screeningContext else { return "no voice measurements have been captured." }
        var lines = ["venture voice summary", sample.capturedAt.formatted(date: .abbreviated, time: .shortened)]
        if let acoustic = sample.voiceAcousticSummary {
            lines.append(String(format: "recording quality: %.2f / 1", acoustic.recordingQuality))
            if acoustic.isUsable {
                if let pitch = acoustic.pitchHz { lines.append(String(format: "average voice pitch: %.0f Hz", pitch)) }
                lines.append(String(format: "voiced time: %.1f seconds", acoustic.voicedSeconds))
                if let variation = acoustic.pitchVariation { lines.append(String(format: "pitch variation: %.3f coefficient of variation", variation)) }
                if let variation = acoustic.amplitudeVariation { lines.append(String(format: "loudness variation: %.3f coefficient of variation", variation)) }
            } else { lines.append("recording quality is too low to interpret voice features; repeat in a quiet place.") }
        }
        if let words = sample.spontaneousWordCount, words > 0 { lines.append("words transcribed on device: \(words)") }
        if let research = sample.voiceResearchResult, research.isUsable {
            lines.append(String(format: "SSL4PR source study similarity: %.2f / 1. comparison with a small spanish research dataset, not a personal disease probability.", research.researchMatch))
            lines.append("these voice measurements and this research comparison cannot identify or rule out alzheimer's, parkinson's or a form of dementia.")
        } else {
            lines.append("these are recording features, not a diagnosis or a disease probability. no alzheimer's, parkinson's or dementia result was calculated.")
        }
        return lines.joined(separator: "\n")
    }
}
