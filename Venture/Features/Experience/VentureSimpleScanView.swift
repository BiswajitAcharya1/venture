import SwiftUI

struct VentureSimpleScanView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var store: VentureStore
    var locale: VentureLocale
    var onComplete: () -> Void
    @StateObject private var voice = VoiceCaptureService()
    @StateObject private var example = VentureSpeechService()
    @State private var phase = 0
    @State private var summaries: [VoiceAcousticSummary] = []
    @State private var activity: [Double] = []
    @State private var noises: [Double] = []
    @State private var wordCount: Int?
    @State private var lexicalDiversity: Double?
    @State private var speechStability: Double?
    @State private var researchResult: VoiceResearchModelResult?
    @State private var progress = 0.0
    @State private var recording = false
    @State private var analyzing = false
    @State private var retry = false
    @State private var saved = false
    @State private var attempt = UUID()
    @State private var timer: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 6) {
                ForEach(0..<4) { index in
                    Capsule().fill(index < summaries.count || (index == 3 && phase == 2) ? VentureCanvas.accent : VentureCanvas.surface)
                        .frame(height: 4)
                }
            }.accessibilityLabel("\(locale.support(.progress)): \(summaries.count) / 3")
            ScrollView {
                VStack(spacing: 24) {
                    if phase < 2 { voiceView }
                    else { completionView }
                }.frame(maxWidth: .infinity).padding(.vertical, 20)
            }.scrollIndicators(.hidden)
            if phase < 2 {
                Button(locale.t(.skip)) { skip() }.frame(minHeight: 44)
                    .foregroundStyle(dimmedEyeCapture ? Color.white.opacity(0.8) : VentureCanvas.muted)
                    .accessibilityIdentifier("skip-test")
            }
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(VentureCanvas.background).foregroundStyle(VentureCanvas.ink).tint(VentureCanvas.accent)
            .onDisappear { stopEverything() }
            .onChange(of: scenePhase) { _, value in
                if value != .active { stopEverything(); retry = true }
            }
    }

    private var voiceView: some View {
        VStack(spacing: 26) {
            HStack {
                Text(locale.support(.voiceCheck)).font(.footnote.weight(.medium)).foregroundStyle(VentureCanvas.muted)
                Spacer()
                Text(phase == 0 ? "\(min(3, summaries.count + 1)) / 3" : "20 s")
                    .font(.footnote.monospacedDigit()).foregroundStyle(VentureCanvas.accent)
            }
            ZStack {
                Circle().fill(VentureCanvas.accent.opacity(0.055))
                Circle().stroke(VentureCanvas.surface, lineWidth: 6).padding(6)
                Circle().trim(from: 0, to: progress)
                    .stroke(VentureCanvas.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90)).padding(6)
                Image(systemName: phase == 0 ? "waveform" : "quote.bubble")
                    .font(.system(size: 61, weight: .ultraLight)).foregroundStyle(VentureCanvas.accent)
                    .scaleEffect(1 + min(0.12, voice.audioLevel * 0.12))
            }.frame(width: 200, height: 200).accessibilityHidden(true)
            VStack(spacing: 12) {
                Text(phase == 0 ? locale.t(.ahh) : locale.support(.openSpeech))
                    .font(.system(size: 27, weight: .regular, design: .rounded)).multilineTextAlignment(.center)
                Text(locale.support(phase == 0 ? .voiceTip : .speechPrompt))
                    .font(.subheadline).foregroundStyle(VentureCanvas.muted).multilineTextAlignment(.center)
            }
            if phase == 0 {
                HStack(spacing: 14) {
                    ForEach(0..<3) { index in
                        Image(systemName: index < summaries.count ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(index < summaries.count ? VentureCanvas.accent : VentureCanvas.muted.opacity(0.45))
                    }
                }.font(.title3).accessibilityHidden(true)
            } else {
                Text(locale.support(.speechNote)).font(.footnote).foregroundStyle(VentureCanvas.muted).multilineTextAlignment(.center)
            }
            if analyzing { HStack(spacing: 10) { ProgressView(); Text(locale.support(.analyzing)) }.font(.footnote) }
            if retry || voice.permissionDenied {
                Text(voice.permissionDenied ? locale.t(.unavailable) : locale.support(.retryQuality))
                    .font(.footnote).foregroundStyle(VentureCanvas.muted).multilineTextAlignment(.center)
                    .accessibilityIdentifier("recording-retry")
            }
            HStack(spacing: 14) {
                if phase == 0 {
                    Button { Haptics.soft(); example.playExample() } label: {
                        Group {
                            if example.preparing { ProgressView() }
                            else { Image(systemName: example.playing && !example.paused ? "pause.fill" : "play.fill") }
                        }.frame(width: 64, height: 64).background(VentureCanvas.surface, in: Circle())
                    }.disabled(recording || analyzing)
                        .accessibilityLabel(locale.t(example.playing && !example.paused ? .pause : .example)).accessibilityIdentifier("play-example")
                }
                VentureAction(title: locale.t(recording ? .stop : .start), symbol: recording ? "stop.fill" : "mic") {
                    if recording { cancelSample() }
                    else if phase == 0 { captureVowel() }
                    else { captureSpeech() }
                }.disabled(analyzing).accessibilityIdentifier(phase == 0 ? "record-ahh" : "record-open-speech")
            }
            if example.failed { Text(locale.t(.unavailable)).font(.footnote) }
            if !locale.hasTranslatedSupport { Text(locale.support(.englishNotice)).font(.caption).foregroundStyle(VentureCanvas.muted) }
        }
    }

    private var completionView: some View {
        VStack(spacing: 26) {
            Image(systemName: summaries.isEmpty && wordCount == nil ? "waveform.circle" : "checkmark.circle")
                .font(.system(size: 80, weight: .ultraLight)).foregroundStyle(VentureCanvas.accent)
            Text(locale.t(.done)).font(.largeTitle.weight(.light))
            Text(locale.t(.screening)).font(.footnote).multilineTextAlignment(.center).foregroundStyle(VentureCanvas.muted)
            VentureAction(title: locale.t(.next)) { save(); onComplete() }.accessibilityIdentifier("finish-scan")
        }.padding(.vertical, 36)
    }

    private func captureVowel() {
        let token = beginAttempt()
        timer = Task {
            await voice.start()
            guard attempt == token, !Task.isCancelled else { voice.stop(); return }
            guard voice.isRecording else { recording = false; retry = true; return }
            voice.beginMotorSample()
            guard await advance(ticks: 50, token: token) else { return }
            recording = false; analyzing = true
            await voice.finishMotorSample()
            guard attempt == token, !Task.isCancelled else { return }
            voice.stop(); analyzing = false
            guard let summary = voice.voiceAcousticSummary, summary.isUsable else {
                progress = 0; retry = true; return
            }
            summaries.append(summary)
            collectActivity()
            Haptics.success(); progress = 0
            if summaries.count == 3 { phase = 1; retry = false }
        }
    }

    private func captureSpeech() {
        let token = beginAttempt()
        timer = Task {
            await voice.start(spontaneousLocale: Locale(identifier: locale.language.id))
            guard attempt == token, !Task.isCancelled else { voice.stop(); return }
            guard voice.isRecording else { recording = false; retry = true; return }
            voice.beginSpontaneousSample()
            guard await advance(ticks: 200, token: token) else { return }
            voice.finishSpontaneousSample()
            wordCount = voice.spontaneousWordCount > 0 ? voice.spontaneousWordCount : nil
            lexicalDiversity = voice.spontaneousLexicalDiversity
            speechStability = voice.speechStability
            collectActivity()
            recording = false; analyzing = true
            await voice.finishResearchSpeechSample()
            guard attempt == token, !Task.isCancelled else { return }
            researchResult = voice.voiceResearchResult
            voice.stop(); analyzing = false; phase = 2; progress = 0; Haptics.success()
        }
    }

    private func beginAttempt() -> UUID {
        example.stop(); timer?.cancel(); retry = false; progress = 0; recording = true
        let token = UUID(); attempt = token; return token
    }

    private func advance(ticks: Int, token: UUID) async -> Bool {
        for tick in 1...ticks {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return false }
            guard !Task.isCancelled, attempt == token else { return false }
            progress = Double(tick) / Double(ticks)
            if tick.isMultiple(of: ticks / 5) { Haptics.progress() }
        }
        return true
    }

    private func collectActivity() {
        if let ratio = voice.voiceActivityRatio { activity.append(ratio) }
        if let noise = voice.noiseLevel { noises.append(noise) }
    }

    private func cancelSample() { stopEverything(); progress = 0; retry = true }
    private func skip() { stopEverything(); progress = 0; retry = false; phase += 1 }
    private func stopEverything() {
        attempt = UUID(); timer?.cancel(); timer = nil; voice.stop(); example.stop(); recording = false; analyzing = false
    }

    private func save() {
        guard !saved else { return }; saved = true
        // Skips never become measurements. No eye signal or disease likelihood is saved.
        guard !summaries.isEmpty || wordCount != nil || researchResult?.isUsable == true else { return }
        let acoustic = summaries.dropFirst().reduce(summaries.first) { combined, next in combined?.combined(with: next) }
        store.completeScan(result: ScanResult(
            cameraAuthorized: false, microphoneAuthorized: true, eyeConfidence: 0, fixationStability: 0, blinkCount: 0,
            pupilResponse: nil, pupilSymmetry: nil, pupilVariability: nil, gazeTrackingScore: nil,
            speechStability: speechStability, voiceActivityRatio: activity.isEmpty ? nil : activity.reduce(0, +) / Double(activity.count),
            noiseLevel: noises.isEmpty ? nil : noises.reduce(0, +) / Double(noises.count),
            parkinsonsVoiceProbability: nil, parkinsonsVoiceQuality: nil, spontaneousWordCount: wordCount, spontaneousLexicalDiversity: lexicalDiversity,
            respiratoryWheezeLikelihood: nil, respiratoryRecordingQuality: nil, respiratoryBreathSeconds: nil, respiratoryAirflowIrregularity: nil,
            memoryScore: nil, attentionScore: nil, executiveFunctionScore: nil, phq2Score: nil, voiceAcousticSummary: acoustic,
            voiceResearchResult: researchResult?.isUsable == true ? researchResult : nil
        ))
    }
}
