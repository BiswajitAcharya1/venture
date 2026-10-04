import AVFoundation
import CoreML

struct VoiceActivityMetrics: Sendable {
    let probability: Double
    let speechRatio: Double
    let noiseLevel: Double
    let backend: String
}

final class SileroVoiceActivityDetector: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.venture.silero-vad", qos: .userInitiated)
    private let callback: @MainActor @Sendable (VoiceActivityMetrics) -> Void

    private var model: MLModel?
    private var pendingSamples: [Float] = []
    private var context = [Float](repeating: 0, count: 64)
    private var hiddenState = [Float](repeating: 0, count: 128)
    private var cellState = [Float](repeating: 0, count: 128)
    private var processedChunks = 0
    private var activeChunks = 0
    private var inactiveNoiseTotal = 0.0
    private var inactiveNoiseChunks = 0

    private let chunkSize = 4096
    private let hopSize = 4096
    private var inferenceCounter = 0
    private let inferenceStride = 2

    private var reusableAudio: MLMultiArray?
    private var reusableHidden: MLMultiArray?
    private var reusableCell: MLMultiArray?
    private var reusableProvider: MLDictionaryFeatureProvider?

    /// The bundled ML Program faults inside Core ML's Intel Simulator runtime
    /// during live inference. Use the lightweight signal gate there; phones
    /// still use the bundled model on CPU/Neural Engine.
    private static let supportsRealtimeCoreML: Bool = {
#if targetEnvironment(simulator)
        false
#else
        true
#endif
    }()

    init(callback: @escaping @MainActor @Sendable (VoiceActivityMetrics) -> Void) {
        self.callback = callback
        queue.async { [weak self] in self?.loadModel() }
    }

    func reset() {
        queue.async { [weak self] in
            guard let self else { return }
            pendingSamples.removeAll(keepingCapacity: true)
            context = [Float](repeating: 0, count: 64)
            hiddenState = [Float](repeating: 0, count: 128)
            cellState = [Float](repeating: 0, count: 128)
            processedChunks = 0
            activeChunks = 0
            inactiveNoiseTotal = 0
            inactiveNoiseChunks = 0
            inferenceCounter = 0
            reusableAudio = nil
            reusableHidden = nil
            reusableCell = nil
            reusableProvider = nil
        }
    }

    func ingest(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let inputCount = Int(buffer.frameLength)
        guard inputCount > 0 else { return }
        let copied = Array(UnsafeBufferPointer(start: channel, count: inputCount))
        let sampleRate = buffer.format.sampleRate
        queue.async { [weak self] in
            self?.appendResampled(copied, sourceRate: sampleRate)
        }
    }

    private func loadModel() {
        guard Self.supportsRealtimeCoreML else { return }
        model = try? Self.loadBundledModel()
        if model != nil {
            preallocateBuffers()
        }
    }

    private func preallocateBuffers() {
        do {
            reusableAudio = try MLMultiArray(shape: [1, 4_160], dataType: .float32)
            reusableHidden = try MLMultiArray(shape: [1, 128], dataType: .float32)
            reusableCell = try MLMultiArray(shape: [1, 128], dataType: .float32)
        } catch {
            reusableAudio = nil
            reusableHidden = nil
            reusableCell = nil
        }
    }

    static func loadBundledModel() throws -> MLModel {
        guard supportsRealtimeCoreML else {
            throw SileroVADModelError.unavailableInSimulator
        }
        let bundles = [Bundle.main] + Bundle.allBundles + Bundle.allFrameworks
        guard let url = bundles.lazy.compactMap({
            $0.url(forResource: "SileroVAD", withExtension: "mlmodelc")
        }).first else {
            throw SileroVADModelError.modelUnavailable
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        return try MLModel(contentsOf: url, configuration: configuration)
    }

    static func verifyBundledModelExecution() throws -> Double {
        let model = try loadBundledModel()
        let audio = try MLMultiArray(shape: [1, 4_160], dataType: .float32)
        let hidden = try MLMultiArray(shape: [1, 128], dataType: .float32)
        let cell = try MLMultiArray(shape: [1, 128], dataType: .float32)
        for index in 0..<4_160 {
            let sample = index < 64 ? 0 : 0.08 * sin(2 * .pi * 220 * Double(index - 64) / 16_000)
            audio[index] = NSNumber(value: Float(sample))
        }
        for index in 0..<128 {
            hidden[index] = 0
            cell[index] = 0
        }
        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "audio_input": audio,
            "hidden_state": hidden,
            "cell_state": cell
        ])
        let output = try model.prediction(from: provider)
        guard
            let probability = output.featureValue(for: "vad_output")?.multiArrayValue?[0].doubleValue,
            output.featureValue(for: "new_hidden_state")?.multiArrayValue?.count == 128,
            output.featureValue(for: "new_cell_state")?.multiArrayValue?.count == 128
        else {
            throw SileroVADModelError.invalidOutput
        }
        guard let probability = normalizedProbability(probability) else {
            throw SileroVADModelError.invalidOutput
        }
        return probability
    }

    static func normalizedProbability(_ value: Double) -> Double? {
        guard value.isFinite else { return nil }
        return min(1, max(0, value))
    }

    private func appendResampled(_ input: [Float], sourceRate: Double) {
        guard sourceRate > 0 else { return }
        let scale = 16_000 / sourceRate
        let outputCount = max(1, Int((Double(input.count) * scale).rounded(.down)))
        var resampled = [Float]()
        resampled.reserveCapacity(outputCount)
        for outputIndex in 0..<outputCount {
            let sourcePosition = Double(outputIndex) / scale
            let lower = min(input.count - 1, Int(sourcePosition))
            let upper = min(input.count - 1, lower + 1)
            let fraction = Float(sourcePosition - Double(lower))
            resampled.append(input[lower] + (input[upper] - input[lower]) * fraction)
        }
        pendingSamples.append(contentsOf: resampled)

        while pendingSamples.count >= chunkSize {
            let chunk = Array(pendingSamples.prefix(chunkSize))
            pendingSamples.removeFirst(chunkSize)
            process(chunk)
        }
    }

    private func process(_ chunk: [Float]) {
        let rms = sqrt(chunk.reduce(0.0) { $0 + Double($1 * $1) } / Double(chunk.count))
        let probability: Double
        if let model, inferenceCounter % inferenceStride == 0 {
            probability = prediction(chunk: chunk, model: model) ?? min(1, max(0, (rms - 0.006) / 0.045))
        } else {
            probability = min(1, max(0, (rms - 0.006) / 0.045))
        }
        inferenceCounter += 1

        let isActive = probability >= 0.5
        processedChunks += 1
        if isActive {
            activeChunks += 1
        } else {
            inactiveNoiseTotal += rms
            inactiveNoiseChunks += 1
        }
        let speechRatio = Double(activeChunks) / Double(max(1, processedChunks))
        let meanNoise = inactiveNoiseChunks > 0 ? inactiveNoiseTotal / Double(inactiveNoiseChunks) : rms
        let metrics = VoiceActivityMetrics(
            probability: probability,
            speechRatio: speechRatio,
            noiseLevel: min(1, meanNoise * 18),
            backend: modelProbability == nil ? "energy gate" : "Silero VAD · Core ML"
        )
        Task { @MainActor [callback] in callback(metrics) }
    }

    private func prediction(chunk: [Float], model: MLModel) -> Double? {
        guard let audio = reusableAudio,
              let hidden = reusableHidden,
              let cell = reusableCell else {
            return try? predictFresh(chunk: chunk, model: model)
        }

        for index in 0..<64 { audio[index] = NSNumber(value: context[index]) }
        for index in 0..<4_096 { audio[index + 64] = NSNumber(value: chunk[index]) }
        for index in 0..<128 {
            hidden[index] = NSNumber(value: hiddenState[index])
            cell[index] = NSNumber(value: cellState[index])
        }

        let provider: MLDictionaryFeatureProvider
        if let reusable = reusableProvider {
            provider = reusable
        } else {
            do {
                let newProvider = try MLDictionaryFeatureProvider(dictionary: [
                    "audio_input": audio,
                    "hidden_state": hidden,
                    "cell_state": cell
                ])
                reusableProvider = newProvider
                provider = newProvider
            } catch {
                return try? predictFresh(chunk: chunk, model: model)
            }
        }

        guard
            let output = try? model.prediction(from: provider),
            let probabilityArray = output.featureValue(for: "vad_output")?.multiArrayValue,
            let newHidden = output.featureValue(for: "new_hidden_state")?.multiArrayValue,
            let newCell = output.featureValue(for: "new_cell_state")?.multiArrayValue,
            let probability = Self.normalizedProbability(probabilityArray[0].doubleValue),
            (0..<128).allSatisfy({
                newHidden[$0].doubleValue.isFinite && newCell[$0].doubleValue.isFinite
            })
        else { return nil }

        context = Array(chunk.suffix(64))
        for index in 0..<128 {
            hiddenState[index] = newHidden[index].floatValue
            cellState[index] = newCell[index].floatValue
        }
        return probability
    }

    private func predictFresh(chunk: [Float], model: MLModel) -> Double? {
        guard
            let audio = try? MLMultiArray(shape: [1, 4_160], dataType: .float32),
            let hidden = try? MLMultiArray(shape: [1, 128], dataType: .float32),
            let cell = try? MLMultiArray(shape: [1, 128], dataType: .float32)
        else { return nil }

        for index in 0..<64 { audio[index] = NSNumber(value: context[index]) }
        for index in 0..<4_096 { audio[index + 64] = NSNumber(value: chunk[index]) }
        for index in 0..<128 {
            hidden[index] = NSNumber(value: hiddenState[index])
            cell[index] = NSNumber(value: cellState[index])
        }

        guard
            let provider = try? MLDictionaryFeatureProvider(dictionary: [
                "audio_input": audio,
                "hidden_state": hidden,
                "cell_state": cell
            ]),
            let output = try? model.prediction(from: provider),
            let probabilityArray = output.featureValue(for: "vad_output")?.multiArrayValue,
            let newHidden = output.featureValue(for: "new_hidden_state")?.multiArrayValue,
            let newCell = output.featureValue(for: "new_cell_state")?.multiArrayValue,
            let probability = Self.normalizedProbability(probabilityArray[0].doubleValue),
            (0..<128).allSatisfy({
                newHidden[$0].doubleValue.isFinite && newCell[$0].doubleValue.isFinite
            })
        else { return nil }

        context = Array(chunk.suffix(64))
        for index in 0..<128 {
            hiddenState[index] = newHidden[index].floatValue
            cellState[index] = newCell[index].floatValue
        }
        return probability
    }
}

enum SileroVADModelError: Error {
    case modelUnavailable
    case unavailableInSimulator
    case invalidOutput
}
