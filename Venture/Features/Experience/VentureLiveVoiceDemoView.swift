import SwiftUI

// A local conversation rehearsal, never a connection to a hospital.
struct VentureLiveVoiceDemoView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var store: VentureStore
    var locale: VentureLocale
    @StateObject private var microphone = VentureCallVoiceInput()
    @StateObject private var speech = VentureSpeechService()
    @State private var ready = false
    @State private var preparing = true
    @State private var thinking = false
    @State private var handsFree = false
    @State private var listening = false
    @State private var draft = ""
    @State private var answer = ""
    @State private var history: [String] = []
    @State private var responseJob: Task<Void, Never>?
    @State private var silenceJob: Task<Void, Never>?
    @State private var turn = UUID()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(locale.t(.demo)).font(.footnote).foregroundStyle(VentureCanvas.muted).multilineTextAlignment(.center)
                Spacer(minLength: 12)
                ZStack {
                    Circle().fill(VentureCanvas.surface)
                    Circle().stroke(VentureCanvas.accent.opacity(listening || speech.playing ? 0.8 : 0.25), lineWidth: 2).padding(18)
                    if thinking || preparing { ProgressView().scaleEffect(1.5) }
                    else { Image(systemName: listening ? "waveform" : speech.playing ? "speaker.wave.2" : "mic").font(.system(size: 55, weight: .ultraLight)) }
                }.frame(width: 200, height: 200).accessibilityHidden(true)
                ScrollView {
                    VStack(spacing: 18) {
                        if !microphone.transcript.isEmpty && listening { Text(microphone.transcript).foregroundStyle(VentureCanvas.muted) }
                        if !answer.isEmpty { Text(answer).textSelection(.enabled) }
                    }.frame(maxWidth: .infinity)
                }.frame(maxHeight: 180).scrollIndicators(.hidden)
                if microphone.error != nil || speech.failed || (!preparing && !ready) {
                    Text(locale.t(.unavailable)).font(.footnote).foregroundStyle(VentureCanvas.muted)
                }
                Text(locale.t(.voiceNotice)).font(.caption).foregroundStyle(VentureCanvas.muted)
                HStack(spacing: 18) {
                    Button {
                        if handsFree { stop() }
                        else { handsFree = true; Task { await listen() } }
                    } label: {
                        Image(systemName: handsFree ? "stop.fill" : "mic.fill").frame(width: 68, height: 68)
                            .foregroundStyle(VentureCanvas.background).background(VentureCanvas.accent, in: Circle())
                    }.disabled(!ready || preparing).accessibilityLabel(locale.t(handsFree ? .stop : .start)).accessibilityIdentifier("live-voice-toggle")
                    Button { submit(microphone.transcript) } label: {
                        Image(systemName: "arrow.up").frame(width: 52, height: 52)
                    }.disabled(!listening || microphone.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel(locale.t(.send))
                }
                HStack {
                    TextField(locale.t(.message), text: $draft).textFieldStyle(.plain).padding(18)
                        .background(VentureCanvas.surface, in: RoundedRectangle(cornerRadius: 22))
                    Button { submit(draft); draft = "" } label: { Image(systemName: "arrow.up").frame(width: 44, height: 44) }
                        .disabled(!ready || thinking || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel(locale.t(.send)).accessibilityIdentifier("live-demo-send")
                }
            }.padding(28).background(VentureCanvas.background).foregroundStyle(VentureCanvas.ink)
                .navigationTitle(locale.t(.demo)).navigationBarTitleDisplayMode(.inline)
                .toolbar { Button(locale.t(.done)) { stop(); dismiss() } }
                .task { ready = await BundledLlamaEngine.shared.prepare(); preparing = false }
                .onChange(of: microphone.transcript) { _, text in
                    guard listening, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    silenceJob?.cancel()
                    silenceJob = Task {
                        try? await Task.sleep(for: .milliseconds(1800))
                        guard !Task.isCancelled, listening else { return }
                        submit(microphone.transcript)
                    }
                }
                .onChange(of: speech.playing) { old, new in
                    if old && !new && handsFree && !thinking { Task { await listen() } }
                }
                .onChange(of: scenePhase) { _, value in if value != .active { stop() } }
                .onDisappear { stop() }
        }.tint(VentureCanvas.accent).buttonStyle(VentureQuietButtonStyle())
            .environment(\.locale, Locale(identifier: locale.language.id))
            .environment(\.layoutDirection, locale.language.isRTL ? .rightToLeft : .leftToRight)
    }

    private func listen() async {
        guard handsFree, ready, !thinking, !speech.playing, !listening else { return }
        Haptics.soft(); listening = true
        await microphone.start(language: locale.language.speechIdentifier)
        if !microphone.recording { listening = false; handsFree = false }
    }

    private func submit(_ value: String) {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ready, !thinking, !text.isEmpty else { return }
        silenceJob?.cancel(); microphone.stop(); speech.stop(); listening = false; thinking = true
        let token = UUID(); turn = token; answer = ""
        let context = CompanionContext(snapshots: [], health: .empty, mentalHealth: .empty,
            screenTimeSelectionCount: 0, screenTimeProtectionActive: false, recentConversation: Array(history.suffix(6)))
        let language = locale.language
        responseJob = Task {
            let prompt = "Respond entirely in \(language.name) (\(language.id)). This is a fictional appointment conversation rehearsal, not a real call. Play a receptionist who helps the user prepare a routine appointment request. Do not claim a booking, real hospital connection, disease diagnosis, or disease probability. Ask at most one short question. User: \(text)"
            for await partial in BundledLlamaEngine.shared.streamResponse(to: prompt, context: context) {
                guard !Task.isCancelled, token == turn else { return }
                answer = VentureClinicalOutputPolicy.allows(partial) ? partial : locale.t(.screening)
            }
            guard !Task.isCancelled, token == turn else { return }
            thinking = false
            if answer.isEmpty { answer = locale.t(.unavailable); handsFree = false; return }
            history.append("user: \(text)"); history.append("assistant: \(answer)")
            speech.speak(answer, language: language.id)
        }
    }
    private func stop() {
        handsFree = false; listening = false; thinking = false; turn = UUID()
        responseJob?.cancel(); silenceJob?.cancel(); microphone.stop(); speech.stop()
    }
}

extension VentureLanguage {
    var speechIdentifier: String {
        ["en": "en-US", "hi": "hi-IN", "es": "es-ES", "fr": "fr-FR", "de": "de-DE",
         "pt": "pt-BR", "it": "it-IT", "ar": "ar-SA", "bn": "bn-IN", "ur": "ur-PK",
         "pa": "pa-IN", "ta": "ta-IN", "te": "te-IN", "mr": "mr-IN", "gu": "gu-IN",
         "kn": "kn-IN", "ml": "ml-IN", "zh-Hans": "zh-CN", "ja": "ja-JP", "ko": "ko-KR",
         "ru": "ru-RU", "tr": "tr-TR", "vi": "vi-VN", "th": "th-TH", "id": "id-ID",
         "pl": "pl-PL", "nl": "nl-NL"][id] ?? id
    }
}
