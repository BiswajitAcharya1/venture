import Foundation
import CoreML
import AVFoundation
import Accelerate

struct VoiceResearchModelResult: Codable, Sendable, Equatable {
    let modelID: String
    let label: String
    let researchMatch: Double
    let recordingQuality: Double

    var isUsable: Bool {
        modelID == "ssl4pr-hubert-coreml" && researchMatch.isFinite
            && recordingQuality.isFinite && (0...1).contains(researchMatch)
            && (0.55...1).contains(recordingQuality)
    }
}

enum VoiceResearchModelError: LocalizedError {
    case unavailable
    case unsupportedProtocol
    case insufficientAudio
    case poorQuality
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .unavailable: "the speech research model is not installed in this build."
        case .unsupportedProtocol: "this research model was studied with Spanish speech. no comparison is available for this language."
        case .insufficientAudio: "speak comfortably for at least ten seconds to capture a research sample."
        case .poorQuality: "the research sample needs clearer speech in a quieter place. your voice measurements are still available."
        case .invalidOutput: "the research model could not process this sample."
        }
    }
}

enum SSL4PRSpeechResearchEngine {
    static let modelID = "ssl4pr-hubert-coreml"
    static let artifactName = "SSL4PRHuBERT"
    static let sourceURL = URL(string: "https://github.com/K-STMLab/SSL4PR")!

    static var isInstalled: Bool { artifactURL != nil }

    private static var artifactURL: URL? {
        ([Bundle.main] + Bundle.allBundles + Bundle.allFrameworks).lazy.compactMap {
            $0.url(forResource: artifactName, withExtension: "mlmodelc")
        }.first
    }

    static func screen(samples: [Float], sampleRate: Double, languageCode: String, speechActivityRatio: Double?) throws -> VoiceResearchModelResult {
        guard languageCode == "es" else { throw VoiceResearchModelError.unsupportedProtocol }
        guard sampleRate.isFinite, (8_000...192_000).contains(sampleRate), samples.allSatisfy(\.isFinite),
              Double(samples.count) / sampleRate >= 10 else { throw VoiceResearchModelError.insufficientAudio }
        let bounded = Array(samples.suffix(Int(sampleRate * 10.5)))
        let clipping = Double(bounded.filter { abs($0) >= 0.98 }.count) / Double(bounded.count)
        let rms = sqrt(bounded.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(bounded.count))
        guard let speechActivityRatio, speechActivityRatio.isFinite, (0...1).contains(speechActivityRatio),
              rms >= 0.006, clipping < 0.03 else { throw VoiceResearchModelError.poorQuality }
        let quality = speechActivityRatio * max(0, 1 - clipping / 0.03)
        guard quality >= 0.55 else { throw VoiceResearchModelError.poorQuality }
        guard let url = artifactURL else { throw VoiceResearchModelError.unavailable }
        let audio = try prepareInput(samples: bounded, sampleRate: sampleRate)
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        let model = try MLModel(contentsOf: url, configuration: configuration)
        let input = try MLMultiArray(shape: [1, 160_000], dataType: .float32)
        for index in 0..<160_000 { input[index] = NSNumber(value: audio[index]) }
        let provider = try MLDictionaryFeatureProvider(dictionary: ["audio": input])
        let output = try model.prediction(from: provider)
        guard let match = output.featureValue(for: "research_match")?.multiArrayValue?[0].doubleValue,
              match.isFinite, (0...1).contains(match) else { throw VoiceResearchModelError.invalidOutput }
        return VoiceResearchModelResult(
            modelID: modelID,
            label: "Spanish speech research comparison",
            researchMatch: match,
            recordingQuality: quality
        )
    }

    /// Upstream float mono, 16 kHz, no amplitude normalization. Keep the last
    /// ten seconds, including normal pauses. Never send sustained vowels here.
    static func prepareInput(samples: [Float], sampleRate: Double) throws -> [Float] {
        if sampleRate == 16_000 {
            guard samples.count >= 160_000 else { throw VoiceResearchModelError.insufficientAudio }
            return Array(samples.suffix(160_000))
        }
        guard let sourceFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let destination = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(ceil(Double(samples.count) * 16_000 / sampleRate) + 64)),
              let sourceChannel = source.floatChannelData?[0],
              let converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
        else { throw VoiceResearchModelError.invalidOutput }
        source.frameLength = AVAudioFrameCount(samples.count)
        for index in samples.indices { sourceChannel[index] = samples[index] }
        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: destination, error: &conversionError) { _, inputStatus in
            if supplied { inputStatus.pointee = .endOfStream; return nil }
            supplied = true
            inputStatus.pointee = .haveData
            return source
        }
        guard status != .error, conversionError == nil, destination.frameLength >= 160_000,
              let channel = destination.floatChannelData?[0] else { throw VoiceResearchModelError.invalidOutput }
        let offset = Int(destination.frameLength) - 160_000
        return Array(UnsafeBufferPointer(start: channel.advanced(by: offset), count: 160_000))
    }
}

/// Measurements from the sustained vowel only. Frame-level variation is not
/// cycle-level MDVP jitter or shimmer and must never be passed to those slots.
struct VoiceAcousticSummary: Codable, Sendable, Equatable {
    let pitchHz: Double?
    let pitchVariation: Double?
    let amplitudeVariation: Double?
    let voicedSeconds: Double
    let recordingQuality: Double
    let clippingRatio: Double

    var isUsable: Bool {
        guard let pitchHz, pitchHz.isFinite, (55...500).contains(pitchHz),
              voicedSeconds.isFinite, recordingQuality.isFinite, clippingRatio.isFinite,
              [pitchVariation, amplitudeVariation].compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 >= 0 })
        else { return false }
        return (0.55...1).contains(recordingQuality) && voicedSeconds >= 1.5 && (0..<0.03).contains(clippingRatio)
    }

    func combined(with other: VoiceAcousticSummary) -> VoiceAcousticSummary {
        if isUsable && !other.isUsable { return self }
        if other.isUsable && !isUsable { return other }
        let firstWeight = max(0, voicedSeconds * recordingQuality)
        let secondWeight = max(0, other.voicedSeconds * other.recordingQuality)
        func weighted(_ first: Double?, _ second: Double?) -> Double? {
            guard let first, let second else { return first ?? second }
            let total = firstWeight + secondWeight
            return total > 0 ? (first * firstWeight + second * secondWeight) / total : nil
        }
        return VoiceAcousticSummary(
            pitchHz: weighted(pitchHz, other.pitchHz),
            pitchVariation: weighted(pitchVariation, other.pitchVariation),
            amplitudeVariation: weighted(amplitudeVariation, other.amplitudeVariation),
            voicedSeconds: max(0, voicedSeconds) + max(0, other.voicedSeconds),
            recordingQuality: min(recordingQuality, other.recordingQuality),
            clippingRatio: max(clippingRatio, other.clippingRatio)
        )
    }
}

enum VoiceAcousticError: LocalizedError {
    case invalidAudio
    case insufficientAudio

    var errorDescription: String? {
        switch self {
        case .invalidAudio: "the microphone sample could not be read. please record again."
        case .insufficientAudio: "hold a comfortable ahh for at least two seconds, then try again."
        }
    }
}

enum VoiceAcousticAnalyzer {
    /// Local signal measurement; quality gates are recording rules, not
    /// clinically validated cutoffs. No raw samples are returned or retained.
    static func analyze(samples: [Float], sampleRate: Double) throws -> VoiceAcousticSummary {
        guard sampleRate.isFinite, (8_000...192_000).contains(sampleRate),
              samples.allSatisfy(\.isFinite) else { throw VoiceAcousticError.invalidAudio }
        guard Double(samples.count) / sampleRate >= 2 else { throw VoiceAcousticError.insufficientAudio }
        let bounded = Array(samples.suffix(Int(sampleRate * 6.5)))
        var clippingRatio: Double = 0
        vDSP_meamgv(bounded, 1, &clippingRatio, vDSP_Length(bounded.count))
        let clipping = clippingRatio >= 0.98 ? 1.0 : 0.0
        let signal = downsample(bounded, sourceRate: sampleRate)
        let analysisRate = 8_000.0
        let frameSize = 512
        let hop = 160
        var mean: Double = 0
        vDSP_meanv(signal, 1, &mean, vDSP_Length(signal.count))
        var centered = [Double](repeating: 0, count: signal.count)
        var negMean = -mean
        vDSP_vsaddD(signal, 1, &negMean, &centered, 1, vDSP_Length(signal.count))
        var pitches: [Double] = []
        var amplitudes: [Double] = []
        var periodicities: [Double] = []
        var frames = 0
        var reuseFrame = [Double](repeating: 0, count: frameSize)
        for start in stride(from: 0, through: centered.count - frameSize, by: hop) {
            frames += 1
            for i in 0..<frameSize { reuseFrame[i] = centered[start + i] }
            var rms: Double = 0
            vDSP_measqv(reuseFrame, 1, &rms, vDSP_Length(frameSize))
            rms = sqrt(rms)
            guard rms >= 0.006,
                  let pitch = yinPitch(reuseFrame, sampleRate: analysisRate) else { continue }
            pitches.append(pitch.hz)
            amplitudes.append(rms)
            periodicities.append(pitch.periodicity)
        }
        let voicedSeconds = Double(pitches.count * hop) / analysisRate
        let fraction = Double(pitches.count) / Double(max(frames, 1))
        let periodicity = average(periodicities) ?? 0
        let quality = min(1, max(0, fraction * periodicity * min(1, voicedSeconds / 2) * max(0, 1 - clipping / 0.03)))
        return VoiceAcousticSummary(
            pitchHz: average(pitches),
            pitchVariation: coefficientOfVariation(pitches),
            amplitudeVariation: coefficientOfVariation(amplitudes),
            voicedSeconds: voicedSeconds,
            recordingQuality: quality,
            clippingRatio: clipping
        )
    }

    /// Windowed-sinc low-pass resampling prevents higher harmonics from
    /// aliasing into the 55–500 Hz pitch band. At most 52k output samples.
    private static func downsample(_ input: [Float], sourceRate: Double) -> [Double] {
        let targetRate = 8_000.0
        if sourceRate == targetRate { return input.map(Double.init) }
        let count = Int(Double(input.count) * targetRate / sourceRate)
        let cutoff = min(1, targetRate / sourceRate) * 0.9
        let radius = max(12, Int(ceil(12 / cutoff)))
        var output = [Double]()
        output.reserveCapacity(count)
        for index in 0..<count {
            let position = Double(index) * sourceRate / targetRate
            let center = Int(position)
            var value = 0.0
            var weightTotal = 0.0
            for sourceIndex in max(0, center - radius)...min(input.count - 1, center + radius) {
                let distance = Double(sourceIndex) - position
                let normalized = distance / Double(radius)
                guard abs(normalized) <= 1 else { continue }
                let phase = .pi * distance * cutoff
                let sinc = abs(phase) < 1e-9 ? 1 : sin(phase) / phase
                let weight = sinc * cutoff * (0.5 + 0.5 * cos(.pi * normalized))
                value += Double(input[sourceIndex]) * weight
                weightTotal += weight
            }
            output.append(weightTotal == 0 ? 0 : value / weightTotal)
        }
        return output
    }

    /// YIN difference function and cumulative mean normalization (de
    /// Cheveigné & Kawahara, 2002). Estimates fundamental pitch, not peaks of
    /// all harmonics. The first credible local minimum avoids octave errors.
    private static func yinPitch(_ frame: [Double], sampleRate: Double) -> (hz: Double, periodicity: Double)? {
        let minimumLag = Int(sampleRate / 500)
        let maximumLag = Int(sampleRate / 55)
        let length = frame.count - maximumLag
        var difference = [Double](repeating: 1, count: maximumLag + 1)
        var running = 0.0
        for lag in 1...maximumLag {
            var sum = 0.0
            for index in 0..<length {
                let delta = frame[index] - frame[index + lag]
                sum += delta * delta
            }
            running += sum
            difference[lag] = running > 1e-12 ? sum * Double(lag) / running : 1
        }
        var lag = minimumLag
        while lag < maximumLag {
            if difference[lag] < 0.18 {
                while lag + 1 < maximumLag && difference[lag + 1] < difference[lag] { lag += 1 }
                let left = difference[lag - 1]
                let middle = difference[lag]
                let right = difference[lag + 1]
                let denominator = left - 2 * middle + right
                let shift = abs(denominator) > 1e-12 ? 0.5 * (left - right) / denominator : 0
                let refined = Double(lag) + min(0.5, max(-0.5, shift))
                let pitch = sampleRate / refined
                guard pitch.isFinite, (55...500).contains(pitch) else { return nil }
                return (pitch, min(1, max(0, 1 - middle)))
            }
            lag += 1
        }
        return nil
    }

    private static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func coefficientOfVariation(_ values: [Double]) -> Double? {
        guard values.count >= 4, let mean = average(values), mean > 0 else { return nil }
        var variance: Double = 0
        var diff = [Double](repeating: 0, count: values.count)
        vDSP_vsubD(values, 1, &mean, &diff, 1, vDSP_Length(values.count))
        vDSP_measqv(diff, 1, &variance, vDSP_Length(values.count))
        return sqrt(variance) / mean
    }
}

// Preserve the historical serialized result contract while blocking new
// disease output. Its legacy 22-feature head has no verified mobile feature
// extractor; renaming unrelated acoustic statistics does not satisfy MDVP.
struct ParkinsonVoiceScreenResult: Sendable, Equatable {
    let probability: Double
    let quality: Double
    let voicedSeconds: Double

    var classification: String { "research model unavailable" }
    var needsConfirmation: Bool { false }
    var confirmationReason: String { "a verified voice model is required before interpreting this sample." }

    func combined(with other: ParkinsonVoiceScreenResult) -> ParkinsonVoiceScreenResult {
        let firstWeight = max(quality, 0.1)
        let secondWeight = max(other.quality, 0.1)
        return ParkinsonVoiceScreenResult(
            probability: (probability * firstWeight + other.probability * secondWeight) / (firstWeight + secondWeight),
            quality: (quality + other.quality) / 2,
            voicedSeconds: voicedSeconds + other.voicedSeconds
        )
    }
}

enum ParkinsonVoiceScreeningError: LocalizedError {
    case modelUnavailable

    var errorDescription: String? {
        "a verified Parkinson voice model is not available for this recording protocol. measured voice features are still available."
    }
}

enum ParkinsonVoiceScreeningEngine {
    static func screen(samples: [Float], sampleRate: Double) throws -> ParkinsonVoiceScreenResult {
        throw ParkinsonVoiceScreeningError.modelUnavailable
    }
}
