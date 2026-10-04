import AVFoundation
import Combine
import KokoroCoreML

private actor VentureKokoroRuntime {
    static let shared = VentureKokoroRuntime()
    private var engine: KokoroEngine?

    private func loadedEngine() throws -> KokoroEngine {
        if let engine { return engine }
        guard let directory = Bundle.main.url(forResource: "KokoroModels", withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
#if targetEnvironment(simulator)
        let model = try KokoroEngine(modelDirectory: directory, forceCPU: true)
#else
        let model = try KokoroEngine(modelDirectory: directory)
#endif
        engine = model
        return model
    }

    func synthesize(_ text: String) throws -> [Float] {
        try loadedEngine().synthesize(text: text, voice: "af_heart").samples
    }

    func example() throws -> [Float] {
        // An explicitly synthetic example, never used as the user's measurement.
        let source = try loadedEngine().synthesize(ipa: "ɑːɑːɑːɑːɑː", voice: "af_heart", speed: 0.5).samples
        guard source.count > 1 else { throw CocoaError(.fileReadCorruptFile) }
        let count = KokoroEngine.sampleRate * 5
        return (0..<count).map { index in
            let position = Double(index) * Double(source.count - 1) / Double(count - 1)
            let low = Int(position), high = min(source.count - 1, low + 1)
            let fraction = Float(position - Double(low))
            let envelope = Float(min(1, min(Double(index) / 480, Double(count - index) / 480)))
            return (source[low] * (1 - fraction) + source[high] * fraction) * envelope
        }
    }
}

@MainActor final class VentureSpeechService: NSObject, ObservableObject, @preconcurrency AVSpeechSynthesizerDelegate {
    @Published private(set) var preparing = false
    @Published private(set) var playing = false
    @Published private(set) var paused = false
    @Published private(set) var failed = false
    private let audio = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var job: Task<Void, Never>?
    private var generation = UUID()
    private var attached = false
    private var exampleSamples: [Float]?
    private let native = AVSpeechSynthesizer()
    private var nativeUtterance: AVSpeechUtterance?

    override init() {
        super.init()
        native.delegate = self
    }

    func playExample() {
        if playing { togglePause(); return }
        stop(); failed = false
        let token = generation
        do {
            guard let url = Bundle.main.url(forResource: "ahh-example", withExtension: "wav") else { throw CocoaError(.fileNoSuchFile) }
            let file = try AVAudioFile(forReading: url)
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1),
                  let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                  let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 120_000),
                  let converter = AVAudioConverter(from: file.processingFormat, to: format) else { throw CocoaError(.fileReadCorruptFile) }
            try file.read(into: source)
            var supplied = false
            var conversionError: NSError?
            converter.convert(to: converted, error: &conversionError) { _, status in
                if supplied { status.pointee = .endOfStream; return nil }
                supplied = true; status.pointee = .haveData; return source
            }
            if let conversionError { throw conversionError }
            guard let channel = converted.floatChannelData?[0], converted.frameLength > 0 else { throw CocoaError(.fileReadCorruptFile) }
            try play(Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength))), token: token)
        } catch { failed = true }
    }

    func speak(_ text: String, language: String = "en") {
        if playing { togglePause(); return }
        if !language.hasPrefix("en") {
            stop(); failed = false
            guard let voice = AVSpeechSynthesisVoice(language: language) else { failed = true; return }
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .spokenAudio)
                try session.setActive(true)
                let utterance = AVSpeechUtterance(string: text)
                utterance.voice = voice
                nativeUtterance = utterance
                playing = true
                native.speak(utterance)
            } catch { failed = true }
            return
        }
        generate(example: false, text: text)
    }

    func togglePause() {
        if nativeUtterance != nil {
            if paused { native.continueSpeaking() } else { native.pauseSpeaking(at: .word) }
            paused.toggle(); return
        }
        if paused { player.play() } else { player.pause() }
        paused.toggle()
    }

    func stop() {
        generation = UUID(); job?.cancel(); job = nil
        player.stop(); audio.stop()
        nativeUtterance = nil; native.stopSpeaking(at: .immediate)
        preparing = false; playing = false; paused = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard nativeUtterance === utterance else { return }
        nativeUtterance = nil; playing = false; paused = false
    }

    private func generate(example: Bool, text: String) {
        guard !preparing else { return }
        stop(); failed = false; preparing = true
        let token = generation
        job = Task {
            do {
                let samples: [Float]
                if example, let cached = exampleSamples { samples = cached }
                else if example { samples = try await VentureKokoroRuntime.shared.example(); exampleSamples = samples }
                else { samples = try await VentureKokoroRuntime.shared.synthesize(text) }
                guard !Task.isCancelled, generation == token else { return }
                try play(samples, token: token)
            } catch {
                guard generation == token else { return }
                failed = true; preparing = false; playing = false
            }
        }
    }

    private func play(_ samples: [Float], token: UUID) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { throw CocoaError(.fileReadCorruptFile) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in channel.update(from: source.baseAddress!, count: samples.count) }
        if !attached { audio.attach(player); attached = true }
        audio.connect(player, to: audio.mainMixerNode, format: format)
        try audio.start()
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.playing = false; self.paused = false
            }
        }
        preparing = false; playing = true; player.play()
    }
}
