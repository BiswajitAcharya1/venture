import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct CompanionRuntimeInfo: Sendable {
    enum Runtime: String, Sendable {
        case gemma4 = "Gemma 4 E2B · on device"
        case lfm25 = "LFM2.5 230M · on device"
        case systemModel = "Apple on-device model"
        case metricEngine = "Local measured-signal engine"
    }

    let runtime: Runtime
    let detail: String

    static var current: CompanionRuntimeInfo {
        if BundledLlamaEngine.isReady {
            switch LocalCompanionModel.active {
            case .gemma4E2B:
                return CompanionRuntimeInfo(runtime: .gemma4, detail: "Gemma 4 E2B Q4 inference through llama.cpp")
            case .lfm25:
                return CompanionRuntimeInfo(runtime: .lfm25, detail: "LFM2.5 inference through llama.cpp")
            }
        }
#if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            return CompanionRuntimeInfo(runtime: .systemModel, detail: "Private on-device generation grounded in your measurements")
        }
#endif
        return CompanionRuntimeInfo(runtime: .metricEngine, detail: "Private deterministic answers grounded in your measurements")
    }
}

struct CompanionContext: Sendable {
    let snapshots: [CognitiveSnapshot]
    let health: HealthMetrics
    let mentalHealth: MentalHealthSummary
    let screenTimeSelectionCount: Int
    let screenTimeProtectionActive: Bool
    let recentConversation: [String]

    init(snapshots: [CognitiveSnapshot], health: HealthMetrics, mentalHealth: MentalHealthSummary, screenTimeSelectionCount: Int, screenTimeProtectionActive: Bool, recentConversation: [String] = []) {
        self.snapshots = snapshots.map(\.screeningContext)
        self.health = health
        self.mentalHealth = mentalHealth
        self.screenTimeSelectionCount = screenTimeSelectionCount
        self.screenTimeProtectionActive = screenTimeProtectionActive
        self.recentConversation = recentConversation
    }
}

actor AdaptiveCompanionEngine: StreamingLocalCompanionProviding {
    private let metricEngine: MetricCompanionEngine
    private let bundledModel: any LocalCompanionProviding
    private let bundledModelAvailable: Bool

    init(
        metricEngine: MetricCompanionEngine = MetricCompanionEngine(),
        bundledModel: any LocalCompanionProviding = BundledLlamaEngine.shared,
        bundledModelAvailable: Bool = BundledLlamaEngine.isBundled
    ) {
        self.metricEngine = metricEngine
        self.bundledModel = bundledModel
        self.bundledModelAvailable = bundledModelAvailable
    }

    func respond(to message: String, context: CompanionContext) async -> String {
        if let immediate = CompanionSafetyPolicy.immediateResponse(for: message) {
            return immediate
        }
        if let healthBoundary = GeneralHealthBoundary.response(for: message) {
            return healthBoundary
        }
        if let knowledgeBoundary = GeneralKnowledgeBoundary.response(for: message) {
            return knowledgeBoundary
        }
        if let instant = InstantCompanionAnswer.make(for: message) {
            return instant
        }
        if CompanionSafetyPolicy.prefersFastGroundedResponse(for: message)
            || CompanionSafetyPolicy.isMeasuredDomainQuestion(message) {
            return await metricEngine.respond(to: message, context: context)
        }
        if bundledModelAvailable {
            let response = await bundledModel.respond(to: message, context: context)
            if !response.isEmpty, CompanionSafetyPolicy.accepts(response) {
                return response
            }
            let retry = await bundledModel.respond(
                to: "\(message)\nAnswer the question directly in one factual sentence. If unsure, say you are unsure.",
                context: context
            )
            if CompanionSafetyPolicy.accepts(retry) {
                return retry
            }
            return await metricEngine.respond(to: message, context: context)
        }
#if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            do {
                let session = LanguageModelSession(instructions: CompanionPrompt.instructions)
                let response = try await session.respond(to: CompanionPrompt.make(userMessage: message, context: context))
                guard CompanionSafetyPolicy.accepts(response.content) else {
                    return await metricEngine.respond(to: message, context: context)
                }
                return response.content
            } catch {
                return await metricEngine.respond(to: message, context: context)
            }
        }
#endif
        return await metricEngine.respond(to: message, context: context)
    }

    nonisolated func streamResponse(to message: String, context: CompanionContext) -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                await self.produceStream(
                    message: message,
                    context: context,
                    continuation: continuation
                )
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func produceStream(
        message: String,
        context: CompanionContext,
        continuation: AsyncStream<String>.Continuation
    ) async {
        defer { continuation.finish() }

        if let immediate = CompanionSafetyPolicy.immediateResponse(for: message) {
            await emitAnimated(immediate, to: continuation)
            return
        }
        if let healthBoundary = GeneralHealthBoundary.response(for: message) {
            await emitAnimated(healthBoundary, to: continuation)
            return
        }
        if let knowledgeBoundary = GeneralKnowledgeBoundary.response(for: message) {
            await emitAnimated(knowledgeBoundary, to: continuation)
            return
        }
        if let instant = InstantCompanionAnswer.make(for: message) {
            await emitAnimated(instant, to: continuation)
            return
        }
        if CompanionSafetyPolicy.prefersFastGroundedResponse(for: message)
            || CompanionSafetyPolicy.isMeasuredDomainQuestion(message) {
            let response = await metricEngine.respond(to: message, context: context)
            await emitAnimated(response, to: continuation)
            return
        }

        if bundledModelAvailable,
           let streamingModel = bundledModel as? any StreamingLocalCompanionProviding {
            var latest = ""
            var didStreamAcceptedUpdate = false
            for await partial in streamingModel.streamResponse(to: message, context: context) {
                guard !Task.isCancelled else { return }
                latest = partial
                guard CompanionSafetyPolicy.acceptsStreamingPartial(partial) else { continue }
                didStreamAcceptedUpdate = true
                continuation.yield(partial)
            }
            if CompanionSafetyPolicy.accepts(latest) {
                if !didStreamAcceptedUpdate, !latest.isEmpty {
                    continuation.yield(latest)
                }
                return
            }
            let retry = await bundledModel.respond(
                to: "\(message)\nAnswer the question directly in one factual sentence. If unsure, say you are unsure.",
                context: context
            )
            let fallback = CompanionSafetyPolicy.accepts(retry)
                ? retry
                : await metricEngine.respond(to: message, context: context)
            await emitAnimated(fallback, to: continuation)
            return
        }

        let response = await respond(to: message, context: context)
        await emitAnimated(response, to: continuation)
    }

    private func emitAnimated(
        _ response: String,
        to continuation: AsyncStream<String>.Continuation
    ) async {
        let words = response.split(separator: " ", omittingEmptySubsequences: true)
        var visible = ""
        for (index, word) in words.enumerated() {
            guard !Task.isCancelled else { return }
            visible += (index == 0 ? "" : " ") + word
            continuation.yield(visible)
            if index.isMultiple(of: 3) {
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
    }
}

private enum InstantCompanionAnswer {
    static func make(for message: String) -> String? {
        let normalized = message
            .lowercased()
            .replacingOccurrences(of: "what is", with: "")
            .replacingOccurrences(of: "what's", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let compact = normalized.replacingOccurrences(of: " ", with: "")

        let operators: [(Character, (Double, Double) -> Double?)] = [
            ("+", { $0 + $1 }),
            ("-", { $0 - $1 }),
            ("*", { $0 * $1 }),
            ("×", { $0 * $1 }),
            ("/", { $1 == 0 ? nil : $0 / $1 }),
            ("÷", { $1 == 0 ? nil : $0 / $1 })
        ]
        for (symbol, operation) in operators {
            guard let index = compact.dropFirst().firstIndex(of: symbol) else { continue }
            let left = String(compact[..<index])
            let right = String(compact[compact.index(after: index)...])
            guard let lhs = Double(left), let rhs = Double(right), let answer = operation(lhs, rhs), answer.isFinite else {
                continue
            }
            return "\(format(lhs)) \(symbol) \(format(rhs)) = \(format(answer))."
        }
        return nil
    }

    private static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : value.formatted(.number.precision(.fractionLength(0...4)))
    }
}

private enum GeneralHealthBoundary {
    static func response(for message: String) -> String? {
        let normalized = message.lowercased()
        guard normalized.contains("cancer"),
              normalized.contains("chance")
                || normalized.contains("risk")
                || normalized.contains("likelihood")
                || normalized.contains("contract")
        else { return nil }

        return """
        I cannot calculate your personal chance of developing cancer from venture's scans. Risk varies by cancer type, age, family history, exposures, and screening history. A clinician can review those factors and recommend evidence-based screening; seek prompt care for a new persistent lump, unexplained bleeding, unexplained weight loss, or another concerning change.
        """
    }
}

private enum GeneralKnowledgeBoundary {
    static func response(for message: String) -> String? {
        let normalized = message.lowercased()
        if normalized.contains("elon musk"),
           normalized.contains("son") || normalized.contains("child") {
            return "That family-order question is ambiguous because public lists differ in how they count birth order and later identity changes. I do not have live web access, so I will not guess at a person’s name."
        }

        let asksForCurrentFact = [
            "latest", "right now", "currently", "today's", "today’s"
        ].contains(where: normalized.contains)
        if asksForCurrentFact {
            return "I do not have live web access, so I cannot verify a current answer. Ask me a stable general-knowledge question or check a current source."
        }
        return nil
    }
}

enum CompanionSafetyPolicy {
    static let crisisResponse = "If you may harm yourself or are in immediate danger, call or text 988 in the United States now, or call emergency services. venture cannot provide crisis care."

    static func immediateResponse(for message: String) -> String? {
        let normalized = message.lowercased()
        let crisisTerms = [
            "suicide",
            "kill myself",
            "harm myself",
            "hurt myself",
            "end my life",
            "not safe"
        ]
        return crisisTerms.contains(where: normalized.contains) ? crisisResponse : nil
    }

    static func prefersFastGroundedResponse(for message: String) -> Bool {
        let normalized = message
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let conversational = [
            "hi", "hello", "hey", "yo",
            "thanks", "thank you", "thx"
        ]
        return normalized.count <= 2 || conversational.contains(normalized)
    }

    static func isMeasuredDomainQuestion(_ message: String) -> Bool {
        let normalized = message.lowercased()
        let directAppPhrases = [
            "my scan", "today's scan", "today’s scan", "my signal", "signal load",
            "my baseline", "my health", "apple health", "my sleep", "my hrv",
            "my heart rate", "my ecg", "my blood pressure", "my watch ecg",
            "screen time", "protect distractions", "block distractions", "focus protection",
            "my voice", "my speech", "my memory", "my attention", "my cognition",
            "my pupils", "my eyes", "my mood", "my depression", "my stress", "my anxiety",
            "what changed", "what should i do", "next step", "my results", "my measurements",
            "my data", "privacy", "secure", "venture"
        ]
        if directAppPhrases.contains(where: normalized.contains) {
            return true
        }

        let tokens = Set(
            normalized
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
        let personalTokens: Set<String> = ["my", "mine", "me"]
        let measuredTokens: Set<String> = [
            "scan", "baseline", "hrv", "ecg", "sleep", "pupil", "pupils", "cognition",
            "parkinson", "parkinsons", "alzheimer", "alzheimers", "dementia",
            "depression", "anxiety", "stress"
        ]
        return !tokens.isDisjoint(with: personalTokens)
            && !tokens.isDisjoint(with: measuredTokens)
    }

    static func accepts(_ response: String) -> Bool {
        let normalized = response.lowercased()
        let forbiddenControlText = [
            "<|",
            "<issue_",
            "<filename>",
            "issue_comment",
            "assistant to=",
            "tool_calls"
        ]
        guard response.count >= 12,
              response.unicodeScalars.filter(CharacterSet.letters.contains).count >= 8,
              containsUsableLanguage(response),
              !forbiddenControlText.contains(where: normalized.contains)
        else { return false }
        let conditions = ["parkinson", "alzheimer", "dementia", "depression", "heart disease"]
        let certaintyPrefixes = [
            "you have ",
            "you do not have ",
            "you don't have ",
            "your diagnosis is ",
            "i diagnose "
        ]
        if certaintyPrefixes.contains(where: normalized.contains),
           conditions.contains(where: normalized.contains) {
            return false
        }
        let probabilityClaims = ["chance of having", "likelihood of having", "probability of having"]
        return !probabilityClaims.contains(where: normalized.contains)
    }

    static func acceptsStreamingPartial(_ response: String) -> Bool {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return false }

        let normalized = trimmed.lowercased()
        let forbiddenControlText = [
            "<|",
            "<issue_",
            "<filename>",
            "issue_comment",
            "assistant to=",
            "tool_calls"
        ]
        guard !forbiddenControlText.contains(where: normalized.contains) else { return false }

        let conditions = ["parkinson", "alzheimer", "dementia", "depression", "heart disease"]
        let certaintyPrefixes = [
            "you have ",
            "you do not have ",
            "you don't have ",
            "your diagnosis is ",
            "i diagnose "
        ]
        if certaintyPrefixes.contains(where: normalized.contains),
           conditions.contains(where: normalized.contains) {
            return false
        }

        let probabilityClaims = ["chance of having", "likelihood of having", "probability of having"]
        return !probabilityClaims.contains(where: normalized.contains)
    }

    private static func containsUsableLanguage(_ response: String) -> Bool {
        let scalars = response.unicodeScalars
        guard !scalars.isEmpty else { return false }
        let readable = scalars.filter {
            CharacterSet.letters.contains($0)
                || CharacterSet.whitespacesAndNewlines.contains($0)
                || CharacterSet.decimalDigits.contains($0)
                || ".,:;!?'-/%".unicodeScalars.contains($0)
        }.count
        let words = response.split { !$0.isLetter }.filter { $0.count >= 2 }
        return Double(readable) / Double(scalars.count) >= 0.72 && words.count >= 2
    }
}

enum CompanionLanguage: String, CaseIterable, Identifiable, Sendable {
    case english, spanish, french, german, hindi, japanese, portuguese

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: "English"
        case .spanish: "Spanish"
        case .french: "French"
        case .german: "German"
        case .hindi: "Hindi"
        case .japanese: "Japanese"
        case .portuguese: "Portuguese"
        }
    }

    static var selected: CompanionLanguage {
        CompanionLanguage(rawValue: UserDefaults.standard.string(forKey: "venture.companion.language") ?? "") ?? .english
    }
}

enum CompanionPrompt {
    static var instructions: String { """
    You are venture, a concise on-device assistant. Answer ordinary general-knowledge questions from your built-in knowledge.
    Do not pretend that old model knowledge is current, and say when you are unsure.
    Respond in \(CompanionLanguage.selected.displayName) unless the user explicitly asks for another language.
    For questions about this user's health, use only measurements supplied in the prompt and never invent missing values.
    Never diagnose or rule out Alzheimer's disease, Parkinson's disease, depression, or another disorder.
    Never calculate a personal cancer or disease probability from general population facts.
    Never infer an ECG condition beyond Apple's supplied classification.
    Cite exact measured values. Distinguish measurements, personal-reference estimates, and unavailable data.
    If persistent memory, speech, movement, mood, or daily-function changes are described, recommend clinician review.
    If the user says they may harm themselves or are in immediate danger, tell them to call or text 988 in the United States or call emergency services.
    Keep the answer concise and direct.
    """ }

    static func make(userMessage: String, context: CompanionContext) -> String {
        let recent = context.snapshots.suffix(7).map { snapshot in
            [
                "date=\(snapshot.capturedAt.formatted(.iso8601))",
                snapshot.driftScore.map { "signal_load=\($0)" },
                snapshot.fixationStability.map { "fixation=\($0)" },
                snapshot.pupilResponse.map { "pupil_response=\($0)" },
                snapshot.pupilSymmetry.map { "pupil_symmetry=\($0)" },
                snapshot.pupilVariability.map { "pupil_variability=\($0)" },
                snapshot.gazeTrackingScore.map { "gaze_tracking=\($0)" },
                snapshot.speechStability.map { "speech_timing=\($0)" },
                snapshot.voiceActivityRatio.map { "voice_activity=\($0)" },
                snapshot.noiseLevel.map { "noise=\($0)" },
                snapshot.spontaneousWordCount.map { "spontaneous_words=\($0)" },
                snapshot.spontaneousLexicalDiversity.map { "lexical_diversity=\($0)" },
                snapshot.heartRateVariability.map { "hrv_ms=\(Int($0))" },
                snapshot.sleepHours.map { "sleep_hours=\($0)" },
                snapshot.memoryScore.map { "memory=\($0)" },
                snapshot.attentionScore.map { "attention=\($0)" },
                snapshot.executiveFunctionScore.map { "interference_control=\($0)" },
                snapshot.phq2Score.map { "phq2=\($0)/6" }
            ].compactMap { $0 }.joined(separator: ", ")
        }.joined(separator: "\n")

        let assessments = context.mentalHealth.assessments.map {
            "\($0.domain.rawValue): \($0.level.rawValue); \($0.evidence); action=\($0.action)"
        }.joined(separator: "\n")

        return """
        Recent measurements:
        \(recent.isEmpty ? "No scan measurements available." : recent)

        Current Apple Health:
        sleep=\(format(context.health.sleepHours)); hrv_ms=\(format(context.health.heartRateVariabilityMilliseconds)); resting_hr_bpm=\(format(context.health.restingHeartRateBPM)); oxygen_percent=\(format(context.health.oxygenSaturationPercent)); steps=\(format(context.health.stepCount)); active_energy_kcal=\(format(context.health.activeEnergyKilocalories)); cuff_systolic_mmhg=\(format(context.health.bloodPressureSystolicMMHg)); cuff_diastolic_mmhg=\(format(context.health.bloodPressureDiastolicMMHg)); cuff_source=\(context.health.bloodPressureSource ?? "unavailable"); night_signal_level=\(context.health.nightSignalLevel.map(String.init) ?? "unavailable"); night_signal_overnight_bpm=\(format(context.health.nightSignalOvernightHeartRateBPM)); night_signal_baseline_bpm=\(format(context.health.nightSignalBaselineBPM)); apple_ecg_classification=\(context.health.electrocardiogramClassification ?? "unavailable")

        Mental signal core:
        score=\(context.mentalHealth.signalLoadScore.map(String.init) ?? "learning baseline")
        \(assessments)

        Screen Time:
        selected_items=\(context.screenTimeSelectionCount); protection_active=\(context.screenTimeProtectionActive)

        User: \(userMessage)

        Recent conversation:
        \(context.recentConversation.isEmpty ? "None." : context.recentConversation.joined(separator: "\n"))
        """
    }

    private static func format(_ value: Double?) -> String {
        value?.formatted(.number.precision(.fractionLength(1))) ?? "unavailable"
    }
}
