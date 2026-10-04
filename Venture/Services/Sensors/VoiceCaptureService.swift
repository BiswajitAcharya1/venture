import AVFoundation
import Combine
import Speech

@MainActor
final class VoiceCaptureService: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var audioLevel: Double = 0
    @Published private(set) var transcript = ""
    @Published private(set) var completedWordCount = 0
    @Published private(set) var speechStability: Double?
    @Published private(set) var voiceActivityProbability = 0.0
    @Published private(set) var voiceActivityRatio: Double?
    @Published private(set) var noiseLevel: Double?
    @Published private(set) var audioProcessor = "Preparing audio"
    @Published private(set) var permissionDenied = false
    @Published private(set) var voiceAcousticSummary: VoiceAcousticSummary?
    @Published private(set) var voiceAcousticError: String?
    @Published private(set) var transcriptionAvailable = false
    @Published private(set) var motorSampleDuration = 0.0
    @Published private(set) var parkinsonsScreen: ParkinsonVoiceScreenResult?
    @Published private(set) var parkinsonsScreenError: String?
    @Published private(set) var isAnalyzingMotorSample = false
    @Published private(set) var respiratorySampleDuration = 0.0
    @Published private(set) var respiratoryScreen: RespiratoryAcousticScreenResult?
    @Published private(set) var respiratoryScreenError: String?
    @Published private(set) var isAnalyzingRespiratorySample = false
    @Published private(set) var voiceResearchResult: VoiceResearchModelResult?
    @Published private(set) var researchModelError: String?
    @Published private(set) var isAnalyzingResearchSample = false
    @Published private(set) var spontaneousWordCount = 0
    @Published private(set) var spontaneousLexicalDiversity: Double?

    private let engine = AVAudioEngine()
    private var captureGeneration = UUID()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var promptWords: [String] = []
    private var tapInstalled = false
    private var collectingMotorSample = false
    private var motorSamples: [Float] = []
    private var motorSampleRate = 0.0
    private var collectingRespiratorySample = false
    private var respiratorySamples: [Float] = []
    private var respiratorySampleRate = 0.0
    private var spontaneousStartTokenCount = 0
    private var spontaneousLanguageCode: String?
    private var collectingResearchSpeech = false
    private var researchSpeechSamples: [Float] = []
    private var researchSpeechSampleRate = 0.0
    private let maxMotorSamples = 6.5 * 48000
    private let maxRespiratorySamples = 4.0 * 48000
    private var levelUpdateCounter = 0
    private lazy var voiceActivityDetector = SileroVoiceActivityDetector { [weak self] metrics in
        self?.voiceActivityProbability = metrics.probability
        self?.voiceActivityRatio = metrics.speechRatio
        self?.noiseLevel = metrics.noiseLevel
        self?.audioProcessor = metrics.backend
    }

    var progress: Double {
        guard !promptWords.isEmpty else { return 0 }
        return min(1, Double(completedWordCount) / Double(promptWords.count))
    }

    func start(prompt: String? = nil, spontaneousLocale: Locale? = nil) async {
        stop()
        let generation = captureGeneration
        spontaneousLanguageCode = spontaneousLocale?.language.languageCode?.identifier
        voiceResearchResult = nil
        researchModelError = nil
        isAnalyzingResearchSample = false
        promptWords = tokens(in: prompt ?? "")
        completedWordCount = 0
        transcript = ""
        speechStability = nil
        voiceActivityProbability = 0
        voiceActivityRatio = nil
        noiseLevel = nil
        audioProcessor = "Preparing audio"
        voiceActivityDetector.reset()
        permissionDenied = false
        motorSampleDuration = 0
        parkinsonsScreen = nil
        parkinsonsScreenError = nil
        voiceAcousticSummary = nil
        voiceAcousticError = nil
        transcriptionAvailable = false
        isAnalyzingMotorSample = false
        respiratorySampleDuration = 0
        respiratoryScreen = nil
        respiratoryScreenError = nil
        isAnalyzingRespiratorySample = false
        collectingMotorSample = false
        collectingRespiratorySample = false
        motorSamples.removeAll(keepingCapacity: true)
        respiratorySamples.removeAll(keepingCapacity: true)
        spontaneousWordCount = 0
        spontaneousLexicalDiversity = nil
        spontaneousStartTokenCount = 0
        levelUpdateCounter = 0

        let microphone = await requestMicrophonePermission()
        let speech: Bool
        if promptWords.isEmpty && spontaneousLocale == nil {
            speech = true
        } else {
            speech = await requestSpeechPermission()
        }
        guard generation == captureGeneration else { return }
        guard microphone else {
            permissionDenied = true
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let input = engine.inputNode
            try? input.setVoiceProcessingEnabled(false)
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                permissionDenied = true
                stop()
                return
            }

            motorSamples.reserveCapacity(Int(maxMotorSamples))
            respiratorySamples.reserveCapacity(Int(maxRespiratorySamples))

            let wantsTranscription = !promptWords.isEmpty || spontaneousLocale != nil
            let recognizer = wantsTranscription && speech
                ? SFSpeechRecognizer(locale: spontaneousLocale ?? Locale(identifier: "en-US"))
                : nil
            if recognizer?.supportsOnDeviceRecognition == true && recognizer?.isAvailable == true {
                let request = SFSpeechAudioBufferRecognitionRequest()
                request.shouldReportPartialResults = true
                request.requiresOnDeviceRecognition = true
                recognitionRequest = request
                transcriptionAvailable = true
                recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, _ in
                    guard let result else { return }
                    Task { @MainActor in
                        guard self?.captureGeneration == generation else { return }
                        self?.updateTranscript(result.bestTranscription)
                    }
                }
            } else if wantsTranscription {
                recognitionRequest = nil
                recognitionTask = nil
                audioProcessor = "on-device transcription unavailable"
            }

            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
                self?.voiceActivityDetector.ingest(buffer)
                let level = Self.rms(buffer: buffer)
                let samples = Self.monoSamples(buffer: buffer)
                let sampleRate = format.sampleRate
                Task { @MainActor in
                    guard let self, self.isRecording, self.captureGeneration == generation else { return }
                    self.levelUpdateCounter += 1
                    if self.levelUpdateCounter % 2 == 0 {
                        self.audioLevel = self.audioLevel * 0.68 + level * 0.32
                    }
                    if self.collectingMotorSample {
                        self.motorSampleRate = sampleRate
                        self.motorSamples.append(contentsOf: samples)
                        if self.motorSamples.count > Int(self.maxMotorSamples) {
                            self.motorSamples.removeFirst(self.motorSamples.count - Int(self.maxMotorSamples))
                        }
                        self.motorSampleDuration = Double(self.motorSamples.count) / sampleRate
                    }
                    if self.collectingResearchSpeech {
                        self.researchSpeechSampleRate = sampleRate
                        self.researchSpeechSamples.append(contentsOf: samples)
                        let limit = Int(sampleRate * 10.5)
                        if self.researchSpeechSamples.count > limit {
                            self.researchSpeechSamples.removeFirst(self.researchSpeechSamples.count - limit)
                        }
                    }
                    if self.collectingRespiratorySample {
                        self.respiratorySampleRate = sampleRate
                        self.respiratorySamples.append(contentsOf: samples)
                        if self.respiratorySamples.count > Int(self.maxRespiratorySamples) {
                            self.respiratorySamples.removeFirst(self.respiratorySamples.count - Int(self.maxRespiratorySamples))
                        }
                        self.respiratorySampleDuration = Double(self.respiratorySamples.count) / sampleRate
                    }
                }
            }
            tapInstalled = true
            engine.prepare()
            try engine.start()
            isRecording = true
        } catch {
            permissionDenied = true
            stop()
        }
    }

    func stop() {
        captureGeneration = UUID()
        collectingResearchSpeech = false
        researchSpeechSamples.removeAll(keepingCapacity: false)
        isAnalyzingResearchSample = false
        isAnalyzingMotorSample = false
        isAnalyzingRespiratorySample = false
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        transcript = ""
        transcriptionAvailable = false
        isRecording = false
        collectingMotorSample = false
        collectingRespiratorySample = false
        motorSamples.removeAll(keepingCapacity: false)
        respiratorySamples.removeAll(keepingCapacity: false)
        audioLevel = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func beginMotorSample() {
        guard isRecording else { return }
        parkinsonsScreen = nil
        parkinsonsScreenError = nil
        motorSampleDuration = 0
        voiceAcousticSummary = nil
        voiceAcousticError = nil
        motorSamples.removeAll(keepingCapacity: true)
        collectingMotorSample = true
        audioProcessor = "collecting sustained vowel"
    }

    func beginRespiratorySample() {
        guard isRecording else { return }
        respiratoryScreen = nil
        respiratoryScreenError = nil
        respiratorySampleDuration = 0
        respiratorySamples.removeAll(keepingCapacity: true)
        collectingRespiratorySample = true
        audioProcessor = "collecting breathing audio"
    }

    func beginSpontaneousSample() {
        guard isRecording else { return }
        researchSpeechSamples.removeAll(keepingCapacity: true)
        voiceResearchResult = nil
        researchModelError = nil
        collectingResearchSpeech = spontaneousLanguageCode == "es"
        voiceActivityDetector.reset()
        voiceActivityRatio = nil
        spontaneousStartTokenCount = tokens(in: transcript).count
        spontaneousWordCount = 0
        spontaneousLexicalDiversity = nil
        audioProcessor = "capturing open speech"
    }

    func finishSpontaneousSample() {
        let allTokens = tokens(in: transcript)
        let sample = Array(allTokens.dropFirst(min(spontaneousStartTokenCount, allTokens.count)))
        spontaneousWordCount = sample.count
        spontaneousLexicalDiversity = sample.count < 20
            ? nil
            : Double(Set(sample).count) / Double(sample.count)
    }

    func finishMotorSample() async {
        guard collectingMotorSample, !isAnalyzingMotorSample else { return }
        collectingMotorSample = false
        isAnalyzingMotorSample = true
        audioProcessor = "measuring voice acoustics"
        let samples = motorSamples
        let sampleRate = motorSampleRate
        let generation = captureGeneration
        motorSamples.removeAll(keepingCapacity: false)
        parkinsonsScreen = nil
        parkinsonsScreenError = nil
        defer { if captureGeneration == generation { isAnalyzingMotorSample = false } }
        do {
            let summary = try await Task.detached(priority: .userInitiated) {
                try VoiceAcousticAnalyzer.analyze(samples: samples, sampleRate: sampleRate)
            }.value
            guard generation == captureGeneration else { return }
            voiceAcousticSummary = summary
            voiceAcousticError = summary.isUsable ? nil : "try again in a quiet room. hold a comfortable ahh with the phone an arm’s length away."
            audioProcessor = "local voice measurements"
        } catch {
            guard generation == captureGeneration else { return }
            voiceAcousticSummary = nil
            voiceAcousticError = error.localizedDescription
        }
    }

    func finishRespiratorySample() async {
        guard collectingRespiratorySample, !isAnalyzingRespiratorySample else { return }
        collectingRespiratorySample = false
        isAnalyzingRespiratorySample = true
        audioProcessor = "respiratory acoustic screen"
        let samples = respiratorySamples
        let sampleRate = respiratorySampleRate
        respiratorySamples.removeAll(keepingCapacity: false)
        defer { isAnalyzingRespiratorySample = false }
        do {
            respiratoryScreen = try await Task.detached(priority: .userInitiated) {
                try RespiratoryAcousticScreeningEngine.screen(samples: samples, sampleRate: sampleRate)
            }.value
            respiratoryScreenError = nil
        } catch {
            respiratoryScreen = nil
            respiratoryScreenError = error.localizedDescription
        }
    }

    func finishResearchSpeechSample() async {
        guard collectingResearchSpeech, !isAnalyzingResearchSample else { return }
        collectingResearchSpeech = false
        isAnalyzingResearchSample = true
        let samples = researchSpeechSamples
        let sampleRate = researchSpeechSampleRate
        let languageCode = spontaneousLanguageCode ?? ""
        let activity = voiceActivityRatio
        let generation = captureGeneration
        researchSpeechSamples.removeAll(keepingCapacity: false)
        defer { if captureGeneration == generation { isAnalyzingResearchSample = false } }
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try SSL4PRSpeechResearchEngine.screen(samples: samples, sampleRate: sampleRate, languageCode: languageCode, speechActivityRatio: activity)
            }.value
            guard captureGeneration == generation else { return }
            voiceResearchResult = result
            researchModelError = nil
        } catch {
            guard captureGeneration == generation else { return }
            voiceResearchResult = nil
            researchModelError = error.localizedDescription
        }
    }

    private func updateTranscript(_ transcription: SFTranscription) {
        transcript = transcription.formattedString
        let spoken = tokens(in: transcription.formattedString)
        var matched = 0
        for promptWord in promptWords {
            guard matched < spoken.count else { break }
            if spoken[matched] == promptWord || levenshteinClose(spoken[matched], promptWord) {
                matched += 1
            } else if let later = spoken[matched...].firstIndex(of: promptWord) {
                matched = later + 1
            }
        }
        // Speech recognition often revises partial results. Never move the
        // reading highlight backward when that happens.
        completedWordCount = max(completedWordCount, min(promptWords.count, matched))
        speechStability = timingStability(segments: transcription.segments)
    }

    private func timingStability(segments: [SFTranscriptionSegment]) -> Double? {
        guard segments.count >= 4 else { return nil }
        let gaps = zip(segments, segments.dropFirst()).map { current, next in
            max(0, next.timestamp - (current.timestamp + current.duration))
        }
        let durations = segments.map(\.duration).filter { $0 > 0 }
        guard !durations.isEmpty else { return nil }
        let mean = durations.reduce(0, +) / Double(durations.count)
        let variance = durations.reduce(0) { $0 + pow($1 - mean, 2) } / Double(durations.count)
        let rhythmVariation = min(1, sqrt(variance) / max(mean, 0.08))
        let longPauseRatio = Double(gaps.filter { $0 > 0.8 }.count) / Double(max(1, gaps.count))
        return max(0, min(1, 1 - rhythmVariation * 0.55 - longPauseRatio * 0.45))
    }

    private func tokens(in text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private func levenshteinClose(_ lhs: String, _ rhs: String) -> Bool {
        guard abs(lhs.count - rhs.count) <= 1, min(lhs.count, rhs.count) > 3 else { return false }
        return zip(lhs, rhs).filter(!=).count <= 1
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    nonisolated private static func rms(buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<count { sum += channel[index] * channel[index] }
        let rms = sqrt(sum / Float(count))
        return min(1, max(0, Double(rms) * 14))
    }

    nonisolated private static func monoSamples(buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }
}
