import XCTest
@testable import Venture

final class MetricCompanionEngineTests: XCTestCase {
    func testCompanionSafetyPolicyInterceptsCrisisLanguage() {
        XCTAssertEqual(
            CompanionSafetyPolicy.immediateResponse(for: "I want to hurt myself"),
            CompanionSafetyPolicy.crisisResponse
        )
        XCTAssertNil(CompanionSafetyPolicy.immediateResponse(for: "Explain my sleep"))
    }

    func testCompanionSafetyPolicyRejectsDiagnosticCertainty() {
        XCTAssertFalse(CompanionSafetyPolicy.accepts("You have Parkinson's disease."))
        XCTAssertFalse(CompanionSafetyPolicy.accepts("Your chance of having dementia is 70%."))
        XCTAssertTrue(CompanionSafetyPolicy.accepts("The research-model match was 70%, which is not a diagnosis."))
    }

    func testAdaptiveCompanionAnswersSimpleArithmeticWithoutModelDelay() async {
        let clock = ContinuousClock()
        let started = clock.now
        let response = await AdaptiveCompanionEngine().respond(to: "what is 1 + 1?", context: context())

        XCTAssertEqual(response, "1 + 1 = 2.")
        XCTAssertLessThan(started.duration(to: clock.now), .seconds(1))
    }

    func testAdaptiveCompanionDoesNotInventPersonalCancerProbability() async {
        let response = await AdaptiveCompanionEngine().respond(
            to: "What are my chances of contracting cancer?",
            context: context()
        )

        XCTAssertTrue(response.contains("cannot calculate your personal chance"))
        XCTAssertTrue(response.contains("clinician"))
        XCTAssertFalse(response.contains("%"))
    }

    func testAdaptiveCompanionDoesNotGuessLivingPersonFamilyOrder() async {
        let response = await AdaptiveCompanionEngine().respond(
            to: "What is the name of Elon Musk's third son?",
            context: context()
        )

        XCTAssertTrue(response.contains("ambiguous"))
        XCTAssertTrue(response.contains("will not guess"))
        XCTAssertFalse(response.contains("Elon Musk Jr"))
    }

    func testAdaptiveCompanionUsesBundledModelForGeneralKnowledge() async {
        let response = await AdaptiveCompanionEngine(
            bundledModel: GeneralKnowledgeCompanionStub(),
            bundledModelAvailable: true
        ).respond(
            to: "Who was the first person to walk on the Moon? Answer briefly.",
            context: context()
        )
        let normalized = response.lowercased()

        XCTAssertTrue(normalized.contains("neil") || normalized.contains("armstrong"))
    }

    func testAdaptiveCompanionFallsBackToMeasuredEngineWhenBundledModelIsRejected() async {
        let response = await AdaptiveCompanionEngine(
            bundledModel: RejectedCompanionStub(),
            bundledModelAvailable: true
        ).respond(
            to: "tell me something useful",
            context: context()
        )

        XCTAssertFalse(response.contains("could not produce a reliable local answer"))
        XCTAssertFalse(response.contains("<issue_"))
        XCTAssertTrue(response.contains("Ask about") || response.contains("Personal signal load") || response.contains("Latest measured values"))
    }

    func testGeneralQuestionsWithHealthWordsAreNotMisroutedToScanData() {
        XCTAssertFalse(CompanionSafetyPolicy.isMeasuredDomainQuestion("What is the heart of a star?"))
        XCTAssertFalse(CompanionSafetyPolicy.isMeasuredDomainQuestion("Who invented the Apple Watch?"))
        XCTAssertFalse(CompanionSafetyPolicy.isMeasuredDomainQuestion("What is voice acting?"))
        XCTAssertTrue(CompanionSafetyPolicy.isMeasuredDomainQuestion("How was my heart rate today?"))
        XCTAssertTrue(CompanionSafetyPolicy.isMeasuredDomainQuestion("Explain my voice scan"))
    }

    func testAdaptiveCompanionForwardsIncrementalModelUpdates() async {
        let engine = AdaptiveCompanionEngine(
            bundledModel: StreamingGeneralKnowledgeCompanionStub(),
            bundledModelAvailable: true
        )
        var updates: [String] = []

        for await update in engine.streamResponse(
            to: "Who walked on the Moon first?",
            context: context()
        ) {
            updates.append(update)
        }

        XCTAssertEqual(updates, [
            "Neil",
            "Neil Armstrong",
            "Neil Armstrong walked on the Moon first."
        ])
    }

    func testAdaptiveCompanionStreamsFirstSafeModelUpdateBeforeCompletion() async {
        let engine = AdaptiveCompanionEngine(
            bundledModel: SlowStreamingGeneralKnowledgeCompanionStub(),
            bundledModelAvailable: true
        )
        let clock = ContinuousClock()
        let started = clock.now
        let firstUpdate = await firstStreamUpdate(
            from: engine.streamResponse(
            to: "Who walked on the Moon first?",
            context: context()
            )
        )

        XCTAssertEqual(firstUpdate, "Neil")
        XCTAssertLessThan(started.duration(to: clock.now), .milliseconds(250))
    }

    func testCompanionSafetyPolicyAllowsShortSafeStreamingPartials() {
        XCTAssertTrue(CompanionSafetyPolicy.acceptsStreamingPartial("Neil"))
        XCTAssertFalse(CompanionSafetyPolicy.acceptsStreamingPartial("<issue_"))
        XCTAssertFalse(CompanionSafetyPolicy.acceptsStreamingPartial("You have Parkinson's disease."))
    }

    func testAdaptiveCompanionDoesNotStreamRejectedModelText() async {
        let engine = AdaptiveCompanionEngine(
            bundledModel: RejectedStreamingCompanionStub(),
            bundledModelAvailable: true
        )
        var updates: [String] = []

        for await update in engine.streamResponse(
            to: "tell me something useful",
            context: context()
        ) {
            updates.append(update)
        }

        XCTAssertFalse(updates.contains(where: { $0.contains("<issue_") }))
        XCTAssertTrue(
            updates.last?.contains("Ask about") == true
                || updates.last?.contains("Personal signal load") == true
                || updates.last?.contains("Latest measured values") == true
        )
    }

    private let snapshots = CognitiveSnapshot.sampleHistory

    private func firstStreamUpdate(
        from stream: AsyncStream<String>,
        timeout: Duration = .seconds(1)
    ) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                for await update in stream {
                    return update
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }

            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    func testSleepQuestionCitesRecoveryMetrics() async {
        let response = await MetricCompanionEngine().respond(to: "How did sleep affect me?", context: context())
        XCTAssertTrue(response.contains("6.4 hours"))
        XCTAssertTrue(response.contains("HRV"))
    }

    func testDifferentQuestionsProduceDifferentAnswers() async {
        let engine = MetricCompanionEngine()
        let voice = await engine.respond(to: "How was my voice?", context: context())
        let privacy = await engine.respond(to: "What data do you store?", context: context())
        XCTAssertNotEqual(voice, privacy)
        XCTAssertTrue(voice.contains("87%"))
        XCTAssertTrue(privacy.contains("encrypted"))
    }

    func testEmptyHistoryDoesNotInventMetrics() async {
        var empty = context()
        empty = CompanionContext(snapshots: [], health: empty.health, mentalHealth: .empty, screenTimeSelectionCount: 0, screenTimeProtectionActive: false, recentConversation: [])
        let response = await MetricCompanionEngine().respond(to: "What changed?", context: empty)
        XCTAssertTrue(response.contains("No completed scan"))
    }

    func testHealthOnlyBloodPressureProducesProblemAndAction() async {
        var health = HealthMetrics.empty
        health.bloodPressureSystolicMMHg = 148
        health.bloodPressureDiastolicMMHg = 94
        health.bloodPressureDate = .now
        health.bloodPressureSource = BloodPressureReading.manualSource
        let summary = MentalHealthCore().evaluate(snapshots: [], health: health)
        let measured = CompanionContext(
            snapshots: [],
            health: health,
            mentalHealth: summary,
            screenTimeSelectionCount: 0,
            screenTimeProtectionActive: false,
            recentConversation: []
        )

        let response = await MetricCompanionEngine().respond(to: "What changed?", context: measured)

        XCTAssertTrue(response.contains("148/94"))
        XCTAssertTrue(response.contains("validated cuff"))
    }

    func testPrivacyQuestionWorksWithoutScanHistory() async {
        let empty = CompanionContext(
            snapshots: [],
            health: .empty,
            mentalHealth: .empty,
            screenTimeSelectionCount: 0,
            screenTimeProtectionActive: false,
            recentConversation: []
        )
        let response = await MetricCompanionEngine().respond(to: "How is my data secured?", context: empty)
        XCTAssertTrue(response.contains("AES-256-GCM"))
        XCTAssertTrue(response.contains("PBKDF2"))
    }

    func testSummaryCitesMeasuredSignals() async {
        let response = await MetricCompanionEngine().respond(to: "Summarize everything measured today", context: context())
        XCTAssertFalse(response.contains("pupil response"))
        XCTAssertTrue(response.contains("voice activity 72%"))
        XCTAssertTrue(response.contains("memory 0%"))
    }

    func testDiseaseQuestionRefusesClassification() async {
        let response = await MetricCompanionEngine().respond(to: "Does my voice mean Parkinson's?", context: context())
        XCTAssertTrue(response.contains("does not estimate") || response.contains("cannot determine"))
        XCTAssertTrue(response.contains("clinician"))
    }

    func testDementiaQuestionUsesMeasuredCognitiveIndexWithoutDiagnosis() async {
        let response = await MetricCompanionEngine().respond(to: "Do I have dementia?", context: context())

        XCTAssertTrue(response.contains("no verified voice model"))
        XCTAssertFalse(response.contains("composite screen"))
        XCTAssertTrue(response.contains("clinical testing"))
    }

    func testParkinsonQuestionDoesNotExposeLegacyModelScores() async {
        let snapshot = CognitiveSnapshot(
            capturedAt: .now,
            driftScore: nil,
            fixationStability: nil,
            voiceActivityRatio: 0.8,
            parkinsonsVoiceProbability: 0.64,
            parkinsonsVoiceQuality: 0.88,
            heartRateVariability: nil,
            sleepHours: nil,
            attentionScore: nil
        )
        let measured = CompanionContext(
            snapshots: [snapshot],
            health: .empty,
            mentalHealth: .empty,
            screenTimeSelectionCount: 0,
            screenTimeProtectionActive: false,
            recentConversation: []
        )

        let response = await MetricCompanionEngine().respond(to: "What did the Parkinson screen find?", context: measured)

        XCTAssertTrue(response.contains("does not estimate"))
        XCTAssertFalse(response.contains("64%"))
        XCTAssertFalse(response.contains("88%"))
    }

    func testGreetingRespondsConversationally() async {
        let response = await MetricCompanionEngine().respond(to: "hi", context: context())

        XCTAssertTrue(response.hasPrefix("Hi."))
        XCTAssertTrue(response.contains("Ask me"))
    }

    func testLowContextInputStillGetsUsefulResponse() async {
        let response = await MetricCompanionEngine().respond(to: "a", context: context())

        XCTAssertTrue(response.contains("Ask about"))
        XCTAssertTrue(response.contains("Apple Health"))
    }

    func testNonsenseInputGetsGuidedPrompt() async {
        let response = await MetricCompanionEngine().respond(to: "a,b,c,d", context: context())

        XCTAssertTrue(response.contains("real question"))
        XCTAssertTrue(response.contains("cognitive index"))
    }

    private func context() -> CompanionContext {
        var health = HealthMetrics.empty
        health.sleepHours = 6.4
        health.heartRateVariabilityMilliseconds = 48
        let summary = MentalHealthCore().evaluate(snapshots: snapshots, health: health)
        return CompanionContext(snapshots: snapshots, health: health, mentalHealth: summary, screenTimeSelectionCount: 0, screenTimeProtectionActive: false, recentConversation: [])
    }
}

private struct SlowStreamingGeneralKnowledgeCompanionStub: StreamingLocalCompanionProviding {
    func respond(to message: String, context: CompanionContext) async -> String {
        "Neil Armstrong walked on the Moon first."
    }

    nonisolated func streamResponse(to message: String, context: CompanionContext) -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                continuation.yield("Neil")
                try? await Task.sleep(for: .milliseconds(600))
                continuation.yield("Neil Armstrong walked on the Moon first.")
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private struct GeneralKnowledgeCompanionStub: LocalCompanionProviding {
    func respond(to message: String, context: CompanionContext) async -> String {
        "Neil Armstrong was the first person to walk on the Moon."
    }
}

private struct StreamingGeneralKnowledgeCompanionStub: StreamingLocalCompanionProviding {
    func respond(to message: String, context: CompanionContext) async -> String {
        "Neil Armstrong walked on the Moon first."
    }

    nonisolated func streamResponse(to message: String, context: CompanionContext) -> AsyncStream<String> {
        AsyncStream { continuation in
            continuation.yield("Neil")
            continuation.yield("Neil Armstrong")
            continuation.yield("Neil Armstrong walked on the Moon first.")
            continuation.finish()
        }
    }
}

private struct RejectedCompanionStub: LocalCompanionProviding {
    func respond(to message: String, context: CompanionContext) async -> String {
        "<issue_comment>tool_calls</issue_comment>"
    }
}

private struct RejectedStreamingCompanionStub: StreamingLocalCompanionProviding {
    func respond(to message: String, context: CompanionContext) async -> String {
        "<issue_comment>tool_calls</issue_comment>"
    }

    nonisolated func streamResponse(to message: String, context: CompanionContext) -> AsyncStream<String> {
        AsyncStream { continuation in
            continuation.yield("<issue_")
            continuation.yield("<issue_comment>tool_calls</issue_comment>")
            continuation.finish()
        }
    }
}
