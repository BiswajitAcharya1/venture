import Foundation
import Combine
import llama

private import func os.Logger
private import func os.Logger.warning
private import var os.Logger.category
private import var os.Logger.subsystem

enum LocalCompanionModel: String, CaseIterable, Identifiable, Sendable {
    case gemma4E2B
    case lfm25

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemma4E2B: "Gemma 4 E2B"
        case .lfm25: "LFM2.5 230M"
        }
    }

    var resourceName: String {
        switch self {
        case .gemma4E2B: "gemma-4-E2B-it-Q4_0"
        case .lfm25: "lfm2_5_230m_q4_k_m"
        }
    }

    var minimumBytes: Int {
        switch self {
        case .gemma4E2B: 2_500_000_000
        case .lfm25: 140_000_000
        }
    }

    var downloadURL: URL? {
        switch self {
        case .gemma4E2B:
            URL(string: "https://huggingface.co/ggml-org/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_0.gguf?download=true")
        case .lfm25:
            nil
        }
    }

    var downloadDescription: String {
        switch self {
        case .gemma4E2B: "Optional 2.8 GB local download"
        case .lfm25: "Bundled local fallback"
        }
    }

    var installedURL: URL? {
        let bundleURL = Bundle.main.url(forResource: resourceName, withExtension: "gguf")
        let diskURL = Self.modelsDirectory.appendingPathComponent("\(resourceName).gguf")
        for candidate in [bundleURL, diskURL].compactMap({ $0 }) {
            if (try? candidate.resourceValues(forKeys: [.fileSizeKey]).fileSize).map({ $0 >= minimumBytes }) == true {
                return candidate
            }
        }
        return nil
    }

    var isInstalled: Bool { installedURL != nil }

    static var active: LocalCompanionModel {
        gemma4E2B.isInstalled ? .gemma4E2B : .lfm25
    }

    static var modelsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Venture/Models", isDirectory: true)
    }

    var optimalContextSize: Int {
        switch self {
        case .gemma4E2B: 512
        case .lfm25: 1024
        }
    }

    var optimalGPULayers: Int32 {
        switch self {
        case .gemma4E2B: 32
        case .lfm25: 99
        }
    }

    var optimalThreadCount: Int32 {
        switch self {
        case .gemma4E2B: 4
        case .lfm25: 2
        }
    }
}

@MainActor
final class LocalModelManager: ObservableObject {
    enum DownloadState: Equatable {
        case idle
        case downloading
        case ready
        case failed(String)
    }

    @Published private(set) var state: DownloadState = LocalCompanionModel.gemma4E2B.isInstalled ? .ready : .idle
    private var downloadTask: Task<Void, Never>?

    deinit { downloadTask?.cancel() }

    func downloadGemma4() {
        guard LocalCompanionModel.gemma4E2B.installedURL == nil,
              downloadTask == nil,
              let source = LocalCompanionModel.gemma4E2B.downloadURL
        else { return }

        state = .downloading
        downloadTask = Task {
            do {
                let (temporaryURL, _) = try await URLSession.shared.download(from: source)
                try Task.checkCancellation()
                let directory = LocalCompanionModel.modelsDirectory
                let destination = directory.appendingPathComponent("\(LocalCompanionModel.gemma4E2B.resourceName).gguf")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
                guard LocalCompanionModel.gemma4E2B.isInstalled else {
                    throw LocalizedDownloadError.incompleteFile
                }
                state = .ready
            } catch is CancellationError {
                state = .idle
            } catch {
                state = .failed((error as? LocalizedError)?.errorDescription ?? "Gemma 4 could not be downloaded.")
            }
            downloadTask = nil
        }
    }

    private enum LocalizedDownloadError: LocalizedError {
        case incompleteFile

        var errorDescription: String? {
            "Gemma 4 downloaded incompletely. Check available storage and try again."
        }
    }
}

enum BundledLlamaError: LocalizedError {
    case modelMissing
    case modelLoadFailed
    case contextCreationFailed
    case tokenizationFailed
    case promptTooLong
    case decodeFailed
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .modelMissing: "The selected local model is not installed."
        case .modelLoadFailed: "The selected local model could not be loaded."
        case .contextCreationFailed: "The local model context could not be created."
        case .tokenizationFailed: "The local model could not tokenize this request."
        case .promptTooLong: "The measured context is too large for the local model."
        case .decodeFailed: "The local model stopped while generating."
        case .emptyResponse: "The local model returned no usable text."
        }
    }
}

actor BundledLlamaEngine: StreamingLocalCompanionProviding {
    static let shared = BundledLlamaEngine()

    private nonisolated(unsafe) static var runtimeReady = false
    private nonisolated static let readinessLock = NSLock()
    private var runtime: Runtime?
    private var lastUsed = Date.distantPast
    private let maxIdleDuration: Duration = .seconds(60)
    private let logger = Logger(subsystem: "com.venture", category: "llm")

    init() {
        MemoryPressureMonitor.shared.addHandler { [weak self] level in
            Task { await self?.handleMemoryPressure(level) }
        }
    }

    nonisolated static var modelURL: URL? {
        LocalCompanionModel.active.installedURL
    }

    nonisolated static var isBundled: Bool {
        modelURL != nil
    }

    nonisolated static var isReady: Bool {
        readinessLock.withLock { runtimeReady }
    }

    func prepare() -> Bool {
        do {
            let runtime = try loadRuntime()
            let context = CompanionContext(
                snapshots: [],
                health: .empty,
                mentalHealth: .empty,
                screenTimeSelectionCount: 0,
                screenTimeProtectionActive: false,
                recentConversation: []
            )
            let prompt = try runtime.makePrompt(userMessage: "Reply with ready.", context: context)
            let response = try runtime.generate(
                prompt: prompt.text,
                addSpecialTokens: prompt.addSpecialTokens,
                maximumOutputTokens: 4,
                stopAfterFirstSentence: false
            )
            guard !BundledLlamaPrompt.clean(response).isEmpty else {
                throw BundledLlamaError.emptyResponse
            }
            Self.setReady(true)
            lastUsed = .now
            return true
        } catch {
            throwawayRuntimeAfterFatalError(error)
            Self.setReady(false)
            return false
        }
    }

    func release() {
        runtime = nil
        Self.setReady(false)
    }

    func respond(to message: String, context: CompanionContext) async -> String {
        await maybeReleaseIfIdle()
        do {
            let runtime = try loadRuntime()
            let prompt = try runtime.makePrompt(userMessage: message, context: context)
            let policy = generationPolicy(for: message)
            let response = try runtime.generate(
                prompt: prompt.text,
                addSpecialTokens: prompt.addSpecialTokens,
                maximumOutputTokens: policy.maximumOutputTokens,
                stopAfterFirstSentence: policy.stopAfterFirstSentence
            )
            let cleaned = BundledLlamaPrompt.clean(response)
            guard !cleaned.isEmpty else { throw BundledLlamaError.emptyResponse }
            Self.setReady(true)
            lastUsed = .now
            return cleaned
        } catch {
            throwawayRuntimeAfterFatalError(error)
            return ""
        }
    }

    nonisolated func streamResponse(to message: String, context: CompanionContext) -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                await self.generateStreaming(
                    message: message,
                    context: context,
                    continuation: continuation
                )
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func generateStreaming(
        message: String,
        context: CompanionContext,
        continuation: AsyncStream<String>.Continuation
    ) {
        defer { continuation.finish() }
        await maybeReleaseIfIdle()
        do {
            let runtime = try loadRuntime()
            let prompt = try runtime.makePrompt(userMessage: message, context: context)
            let policy = generationPolicy(for: message)
            let response = try runtime.generate(
                prompt: prompt.text,
                addSpecialTokens: prompt.addSpecialTokens,
                maximumOutputTokens: policy.maximumOutputTokens,
                stopAfterFirstSentence: policy.stopAfterFirstSentence
            ) { partial in
                guard !Task.isCancelled else { return }
                let cleaned = BundledLlamaPrompt.clean(partial)
                if !cleaned.isEmpty {
                    continuation.yield(cleaned)
                }
            }
            let cleaned = BundledLlamaPrompt.clean(response)
            guard !cleaned.isEmpty else { throw BundledLlamaError.emptyResponse }
            Self.setReady(true)
            lastUsed = .now
            continuation.yield(cleaned)
        } catch is CancellationError {
            return
        } catch {
            throwawayRuntimeAfterFatalError(error)
        }
    }

    private func maybeReleaseIfIdle() {
        let idle = Date().timeIntervalSince(lastUsed)
        if idle > maxIdleDuration.timeInterval, runtime != nil {
            runtime = nil
            Self.setReady(false)
        }
    }

    private func handleMemoryPressure(_ level: MemoryPressureLevel) {
        switch level {
        case .normal:
            break
        case .warning:
            logger.warning("Memory warning - releasing LLM runtime")
            runtime = nil
            Self.setReady(false)
        case .critical:
            logger.warning("Memory critical - forcing LLM runtime release")
            runtime = nil
            Self.setReady(false)
        }
    }

    private func loadRuntime() throws -> Runtime {
        if let runtime { return runtime }
        guard let modelURL = Self.modelURL else { throw BundledLlamaError.modelMissing }
        let loaded = try Runtime(modelURL: modelURL)
        runtime = loaded
        return loaded
    }

    private func generationPolicy(for message: String) -> GenerationPolicy {
        if message.hasPrefix("Respond entirely in ") {
            return GenerationPolicy(maximumOutputTokens: 128, stopAfterFirstSentence: false)
        }
        return CompanionSafetyPolicy.isMeasuredDomainQuestion(message)
            ? GenerationPolicy(maximumOutputTokens: 40, stopAfterFirstSentence: false)
            : GenerationPolicy(maximumOutputTokens: 22, stopAfterFirstSentence: true)
    }

    private func throwawayRuntimeAfterFatalError(_ error: Error) {
        switch error {
        case BundledLlamaError.decodeFailed,
             BundledLlamaError.contextCreationFailed,
             BundledLlamaError.modelLoadFailed:
            runtime = nil
            Self.setReady(false)
        default:
            break
        }
    }

    nonisolated private static func setReady(_ ready: Bool) {
        readinessLock.withLock { runtimeReady = ready }
    }

    private struct GenerationPolicy {
        let maximumOutputTokens: Int
        let stopAfterFirstSentence: Bool
    }
}

private extension BundledLlamaEngine {
    final class Runtime {
        private let model: OpaquePointer
        private let context: OpaquePointer
        private let vocabulary: OpaquePointer
        private let sampler: UnsafeMutablePointer<llama_sampler>
        private var batch: llama_batch

        private let modelType = LocalCompanionModel.active
        private let contextSize: Int
        private let maximumBatchTokens = 256

        init(modelURL: URL) throws {
            llama_backend_init()

            var modelParameters = llama_model_default_params()
            modelParameters.use_mmap = true
            modelParameters.use_mlock = false
#if targetEnvironment(simulator)
            modelParameters.n_gpu_layers = 0
#else
            modelParameters.n_gpu_layers = modelType.optimalGPULayers
#endif

            guard let model = llama_model_load_from_file(modelURL.path, modelParameters) else {
                llama_backend_free()
                throw BundledLlamaError.modelLoadFailed
            }
            self.model = model
            vocabulary = llama_model_get_vocab(model)

            let threadCount = modelType.optimalThreadCount
            let contextSize = modelType.optimalContextSize
            self.contextSize = contextSize
            var contextParameters = llama_context_default_params()
            contextParameters.n_ctx = UInt32(contextSize)
            contextParameters.n_batch = UInt32(maximumBatchTokens)
            contextParameters.n_ubatch = UInt32(maximumBatchTokens)
            contextParameters.n_threads = threadCount
            contextParameters.n_threads_batch = threadCount
            contextParameters.offload_kqv = true

            guard let context = llama_init_from_model(model, contextParameters) else {
                llama_model_free(model)
                llama_backend_free()
                throw BundledLlamaError.contextCreationFailed
            }
            self.context = context

            let samplerParameters = llama_sampler_chain_default_params()
            guard let sampler = llama_sampler_chain_init(samplerParameters) else {
                llama_free(context)
                llama_model_free(model)
                llama_backend_free()
                throw BundledLlamaError.contextCreationFailed
            }
            self.sampler = sampler
            llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40))
            llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.9, 1))
            llama_sampler_chain_add(sampler, llama_sampler_init_penalties(64, 1.08, 0, 0))
            llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.2))
            llama_sampler_chain_add(sampler, llama_sampler_init_dist(0x534F4E44))

            batch = llama_batch_init(Int32(maximumBatchTokens), 0, 1)
        }

        deinit {
            llama_batch_free(batch)
            llama_sampler_free(sampler)
            llama_free(context)
            llama_model_free(model)
            llama_backend_free()
        }

        func generate(
            prompt: String,
            addSpecialTokens: Bool,
            maximumOutputTokens: Int,
            stopAfterFirstSentence: Bool,
            onUpdate: ((String) -> Void)? = nil
        ) throws -> String {
            llama_memory_clear(llama_get_memory(context), true)
            llama_sampler_reset(sampler)

            let tokens = try tokenize(prompt, addSpecialTokens: addSpecialTokens)
            guard tokens.count + maximumOutputTokens <= contextSize else {
                throw BundledLlamaError.promptTooLong
            }

            var position = 0
            while position < tokens.count {
                guard !Task.isCancelled else { throw CancellationError() }
                let end = min(position + maximumBatchTokens, tokens.count)
                clearBatch()
                for index in position..<end {
                    addToBatch(
                        token: tokens[index],
                        position: Int32(index),
                        logits: index == tokens.count - 1
                    )
                }
                guard llama_decode(context, batch) == 0 else {
                    throw BundledLlamaError.decodeFailed
                }
                position = end
            }

            var generated = ""
            var invalidUTF8: [CChar] = []

            for outputIndex in 0..<maximumOutputTokens {
                guard !Task.isCancelled else { throw CancellationError() }
                let token = llama_sampler_sample(sampler, context, batch.n_tokens - 1)
                if llama_vocab_is_eog(vocabulary, token) { break }

                invalidUTF8.append(contentsOf: tokenPiece(token))
                if let valid = String(validatingUTF8: invalidUTF8 + [0]) {
                    generated += valid
                    invalidUTF8.removeAll(keepingCapacity: true)
                    if BundledLlamaPrompt.containsStopSequence(generated) { break }
                    onUpdate?(generated)
                    if stopAfterFirstSentence,
                       outputIndex >= 6,
                       generated.trimmingCharacters(in: .whitespacesAndNewlines).last.map({ ".!?".contains($0) }) == true {
                        break
                    }
                }

                clearBatch()
                addToBatch(
                    token: token,
                    position: Int32(tokens.count + outputIndex),
                    logits: true
                )
                guard llama_decode(context, batch) == 0 else {
                    throw BundledLlamaError.decodeFailed
                }
            }

            if !invalidUTF8.isEmpty {
                generated += String(decoding: invalidUTF8.map(UInt8.init(bitPattern:)), as: UTF8.self)
                onUpdate?(generated)
            }
            if stopAfterFirstSentence {
                generated = BundledLlamaPrompt.finishShortAnswer(generated)
            }
            return generated
        }

        func makePrompt(userMessage: String, context: CompanionContext) throws -> BundledLlamaPrompt.FormattedPrompt {
            let messages = BundledLlamaPrompt.messages(userMessage: userMessage, context: context)
            guard let template = llama_model_chat_template(model, nil) else {
                return BundledLlamaPrompt.legacyPrompt(from: messages)
            }

            return try "system".withCString { systemRole in
                try "user".withCString { userRole in
                    try messages.system.withCString { systemContent in
                        try messages.user.withCString { userContent in
                            var chat = [
                                llama_chat_message(role: systemRole, content: systemContent),
                                llama_chat_message(role: userRole, content: userContent)
                            ]
                            let required = llama_chat_apply_template(
                                template,
                                &chat,
                                chat.count,
                                true,
                                nil,
                                0
                            )
                            guard required > 0 else { throw BundledLlamaError.tokenizationFailed }

                            var buffer = [CChar](repeating: 0, count: Int(required) + 1)
                            let written = llama_chat_apply_template(
                                template,
                                &chat,
                                chat.count,
                                true,
                                &buffer,
                                Int32(buffer.count)
                            )
                            guard written > 0, written <= required else {
                                throw BundledLlamaError.tokenizationFailed
                            }
                            return BundledLlamaPrompt.FormattedPrompt(
                                text: String(decoding: buffer.prefix(Int(written)).map(UInt8.init(bitPattern:)), as: UTF8.self),
                                addSpecialTokens: false
                            )
                        }
                    }
                }
            }
        }

        private func tokenize(_ text: String, addSpecialTokens: Bool) throws -> [llama_token] {
            let utf8Count = Int32(text.utf8.count)
            let required = llama_tokenize(vocabulary, text, utf8Count, nil, 0, addSpecialTokens, true)
            guard required < 0 else {
                if required == 0 { throw BundledLlamaError.tokenizationFailed }
                return []
            }

            var tokens = [llama_token](repeating: 0, count: Int(-required))
            let count = tokens.withUnsafeMutableBufferPointer { buffer in
                llama_tokenize(
                    vocabulary,
                    text,
                    utf8Count,
                    buffer.baseAddress,
                    Int32(buffer.count),
                    addSpecialTokens,
                    true
                )
            }
            guard count > 0 else { throw BundledLlamaError.tokenizationFailed }
            return Array(tokens.prefix(Int(count)))
        }

        private func clearBatch() {
            batch.n_tokens = 0
        }

        private func addToBatch(token: llama_token, position: llama_pos, logits: Bool) {
            let index = Int(batch.n_tokens)
            batch.token[index] = token
            batch.pos[index] = position
            batch.n_seq_id[index] = 1
            batch.seq_id[index]![0] = 0
            batch.logits[index] = logits ? 1 : 0
            batch.n_tokens += 1
        }

        private func tokenPiece(_ token: llama_token) -> [CChar] {
            var small = [CChar](repeating: 0, count: 16)
            let smallCount = llama_token_to_piece(
                vocabulary,
                token,
                &small,
                Int32(small.count),
                0,
                false
            )
            if smallCount >= 0 {
                return Array(small.prefix(Int(smallCount)))
            }

            var expanded = [CChar](repeating: 0, count: Int(-smallCount))
            let expandedCount = llama_token_to_piece(
                vocabulary,
                token,
                &expanded,
                Int32(expanded.count),
                0,
                false
            )
            guard expandedCount > 0 else { return [] }
            return Array(expanded.prefix(Int(expandedCount)))
        }
    }
}

private enum BundledLlamaPrompt {
    private static let stopSequences = ["<|im_end|>", "<|im_start|>", "<|endoftext|>"]

    struct Messages {
        let system: String
        let user: String
    }

    struct FormattedPrompt {
        let text: String
        let addSpecialTokens: Bool
    }

    static func messages(userMessage: String, context: CompanionContext) -> Messages {
        if !CompanionSafetyPolicy.isMeasuredDomainQuestion(userMessage) {
            let priorConversation = context.recentConversation.dropLast().suffix(4).joined(separator: "\n")
            let userContent = priorConversation.isEmpty
                ? userMessage
                : "Recent conversation:\n\(priorConversation)\nCurrent question: \(userMessage)"
            return Messages(
                system: "You are venture, a concise on-device assistant. Answer the user's question directly in the language requested by the user, in at most three short factual sentences. Do not repeat or number the question. Never invent a name, cause, date, number or medical diagnosis. Never estimate disease probabilities. If uncertain or the answer may have changed, say you are unsure.",
                user: userContent
            )
        }

        let latest = context.snapshots.max(by: { $0.capturedAt < $1.capturedAt })
        let measurements = [
            latest?.driftScore.map { "signal_load=\($0)" },
            latest?.memoryScore.map { "memory=\(percent($0))%" },
            latest?.attentionScore.map { "attention=\(percent($0))%" },
            latest?.executiveFunctionScore.map { "control=\(percent($0))%" },
            latest?.speechStability.map { "speech_timing=\(percent($0))%" },
            latest?.voiceActivityRatio.map { "voice_activity_fraction=\($0) (recording evidence, not disease risk)" },
            latest?.pupilResponse.map { "pupil_response=\(percent($0))%" },
            latest?.pupilSymmetry.map { "pupil_symmetry=\(percent($0))%" },
            latest?.phq2Score.map { "phq2=\($0)/6" },
            context.health.sleepHours.map { "sleep=\($0.formatted(.number.precision(.fractionLength(1))))h" },
            context.health.heartRateVariabilityMilliseconds.map { "hrv=\(Int($0.rounded()))ms" },
            context.health.restingHeartRateBPM.map { "resting_hr=\(Int($0.rounded()))bpm" },
            context.health.electrocardiogramClassification.map { "apple_ecg=\($0)" }
        ].compactMap { $0 }.joined(separator: ", ")
        let priority = context.mentalHealth.priorityAssessment
        let action = priority.map { "\($0.evidence) Next action: \($0.action)" } ?? "No priority action is measured."
        let history = context.recentConversation.dropLast().suffix(2).joined(separator: " | ")
        return Messages(
            system: """
            \(CompanionPrompt.instructions)
            Respond in the language explicitly requested by the user, overriding any default language. Do not provide disease probabilities or a diagnosis.
            If the question is about the user's health, use only supplied measurements. Answer in at most three short sentences.
            """,
            user: """
        Measurements: \(measurements.isEmpty ? "none" : measurements)
        Priority: \(action)
        Screen Time: selected=\(context.screenTimeSelectionCount), active=\(context.screenTimeProtectionActive)
        Recent: \(history.isEmpty ? "none" : history)
        Question: \(userMessage)
        """
        )
    }

    static func legacyPrompt(from messages: Messages) -> FormattedPrompt {
        FormattedPrompt(
            text: """
            <|im_start|>system
            \(messages.system)<|im_end|>
            <|im_start|>user
            \(messages.user)<|im_end|>
            <|im_start|>assistant
            """,
            addSpecialTokens: true
        )
    }

    static func containsStopSequence(_ text: String) -> Bool {
        stopSequences.contains(where: text.contains)
    }

    static func clean(_ text: String) -> String {
        var result = text
        if let stop = stopSequences.compactMap({ result.range(of: $0)?.lowerBound }).min() {
            result = String(result[..<stop])
        }
        return result
            .replacingOccurrences(of: "<|im_start|>assistant", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func finishShortAnswer(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for marker in [", who ", ", which ", ", that "] {
            if let range = result.range(of: marker, options: [.caseInsensitive]) {
                result = String(result[..<range.lowerBound])
                break
            }
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return result }
        if result.last.map({ ".!?".contains($0) }) != true {
            result += "."
        }
        return result
    }

    private static func percent(_ value: Double) -> Int {
        Int((value * 100).rounded())
    }
}
