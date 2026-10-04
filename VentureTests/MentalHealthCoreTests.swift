import FamilyControls
import XCTest
@testable import Venture

final class MentalHealthCoreTests: XCTestCase {
    func testPoorQualityVoiceRequestsRetakeWithoutDiseaseInterpretation() throws {
        let acoustic = VoiceAcousticSummary(pitchHz: 180, pitchVariation: 0.3, amplitudeVariation: 0.3, voicedSeconds: 2, recordingQuality: 0.3, clippingRatio: 0)
        let snapshot = CognitiveSnapshot(capturedAt: .now, speechStability: 0.2, spontaneousWordCount: 20, voiceAcousticSummary: acoustic)
        let voice = try XCTUnwrap(MentalHealthCore().evaluate(snapshots: [snapshot], health: .empty).assessments.first { $0.domain == .voice })
        XCTAssertEqual(voice.level, .unavailable)
        XCTAssertTrue(voice.action.contains("Repeat"))
        XCTAssertFalse(voice.evidence.contains("dementia"))
        XCTAssertFalse(voice.evidence.contains("mood"))
    }

    func testEyeHistoryCannotProduceScreeningResults() {
        let snapshot = CognitiveSnapshot(capturedAt: .now, fixationStability: 0.2, pupilResponse: 0.1, pupilSymmetry: 0.2, pupilVariability: 0.8, gazeTrackingScore: 0.1)
        let summary = MentalHealthCore().evaluate(snapshots: [snapshot], health: .empty)
        XCTAssertEqual(summary.measuredSignalCount, 0)
        XCTAssertFalse(summary.forecasts.contains { $0.domain == .pupilResponse })
        XCTAssertTrue(MetricGroup.measured(health: .empty, snapshots: [snapshot]).isEmpty)
    }

    func testGazeChallengeUsesMeasuredTargetMovement() throws {
        let targets = [
            CGPoint(x: 0.5, y: 0.5),
            CGPoint(x: 0.2, y: 0.5),
            CGPoint(x: 0.8, y: 0.5),
            CGPoint(x: 0.5, y: 0.2),
            CGPoint(x: 0.5, y: 0.8)
        ]
        let score = try XCTUnwrap(GazeChallengeScorer.score(targets: targets, measurements: targets))
        XCTAssertEqual(score, 1, accuracy: 0.001)
    }

    func testPHQ2FollowUpThresholdIsThree() {
        XCTAssertEqual(PHQ2Screen.score(firstAnswer: 1, secondAnswer: 2), 3)
        XCTAssertTrue(PHQ2Screen.needsFollowUp(score: 3))
        XCTAssertFalse(PHQ2Screen.needsFollowUp(score: 2))
    }

    func testScoreRequiresThreePriorMeasurements() {
        let snapshots = Array(CognitiveSnapshot.sampleHistory.suffix(3))

        let summary = MentalHealthCore().evaluate(snapshots: snapshots, health: .empty)

        XCTAssertNil(summary.signalLoadScore)
        XCTAssertEqual(summary.assessments.count, 6)
    }

    func testScoreUsesPersonalHistoryAndStaysBounded() {
        let summary = MentalHealthCore().evaluate(
            snapshots: CognitiveSnapshot.sampleHistory,
            health: .empty
        )

        let score = try? XCTUnwrap(summary.signalLoadScore)
        XCTAssertNotNil(score)
        XCTAssertTrue((0...100).contains(score ?? -1))
        XCTAssertGreaterThan(summary.measuredSignalCount, 0)
    }

    func testAppleAtrialFibrillationClassificationRequestsClinicianReview() throws {
        var health = HealthMetrics.empty
        health.electrocardiogramClassification = "Atrial fibrillation"

        let summary = MentalHealthCore().evaluate(
            snapshots: CognitiveSnapshot.sampleHistory,
            health: health
        )
        let cardiac = try XCTUnwrap(summary.assessments.first { $0.domain == .cardiac })

        XCTAssertEqual(cardiac.level, .clinicianReview)
        XCTAssertTrue(cardiac.evidence.contains("Apple classification"))
    }

    func testAppleECGGuidanceProvidesSpecificActionsWithoutDiseasePercentages() {
        let sinus = AppleECGGuidance.make(classification: "Sinus rhythm")
        let highRate = AppleECGGuidance.make(classification: "Inconclusive · high heart rate")
        let poorReading = AppleECGGuidance.make(classification: "Inconclusive · poor reading")
        let atrialFibrillation = AppleECGGuidance.make(classification: "Atrial fibrillation")

        XCTAssertEqual(sinus.level, .nearReference)
        XCTAssertTrue(sinus.action.contains("persistent symptoms"))
        XCTAssertEqual(highRate.level, .changed)
        XCTAssertTrue(highRate.action.contains("Rest and repeat"))
        XCTAssertTrue(poorReading.action.contains("Watch snug"))
        XCTAssertEqual(atrialFibrillation.level, .clinicianReview)
        XCTAssertTrue(atrialFibrillation.action.contains("Contact a clinician"))
    }

    func testSevereMeasuredBloodPressureSurfacesProblemAndAction() throws {
        var health = HealthMetrics.empty
        health.bloodPressureSystolicMMHg = 184
        health.bloodPressureDiastolicMMHg = 122
        health.bloodPressureDate = .now
        health.bloodPressureSource = BloodPressureReading.manualSource

        let summary = MentalHealthCore().evaluate(
            snapshots: CognitiveSnapshot.sampleHistory,
            health: health
        )
        let cardiac = try XCTUnwrap(summary.assessments.first { $0.domain == .cardiac })

        XCTAssertEqual(cardiac.level, .clinicianReview)
        XCTAssertTrue(cardiac.evidence.contains("184/122"))
        XCTAssertTrue(cardiac.action.contains("recheck"))
        XCTAssertTrue(cardiac.action.contains("emergency services"))
    }

    func testStageTwoMeasuredBloodPressureProvidesCuffFollowUp() throws {
        var health = HealthMetrics.empty
        health.bloodPressureSystolicMMHg = 148
        health.bloodPressureDiastolicMMHg = 94
        health.bloodPressureDate = .now

        let summary = MentalHealthCore().evaluate(
            snapshots: CognitiveSnapshot.sampleHistory,
            health: health
        )
        let cardiac = try XCTUnwrap(summary.assessments.first { $0.domain == .cardiac })

        XCTAssertEqual(cardiac.level, .changed)
        XCTAssertTrue(cardiac.action.contains("validated cuff"))
    }

    func testBloodPressureIsEvaluatedBeforeFirstScan() throws {
        var health = HealthMetrics.empty
        health.bloodPressureSystolicMMHg = 184
        health.bloodPressureDiastolicMMHg = 122
        health.bloodPressureDate = .now
        health.bloodPressureSource = BloodPressureReading.manualSource

        let summary = MentalHealthCore().evaluate(snapshots: [], health: health)
        let priority = try XCTUnwrap(summary.priorityAssessment)

        XCTAssertNil(summary.signalLoadScore)
        XCTAssertEqual(summary.assessments.count, 6)
        XCTAssertEqual(summary.measuredSignalCount, 1)
        XCTAssertEqual(priority.domain, .cardiac)
        XCTAssertEqual(priority.level, .clinicianReview)
        XCTAssertTrue(priority.evidence.contains("184/122"))
        XCTAssertTrue(priority.action.contains("emergency services"))
    }

    func testCurrentHealthRecoverySignalsAreUsedWithoutScanCopy() throws {
        var health = HealthMetrics.empty
        health.sleepHours = 6.1
        health.heartRateVariabilityMilliseconds = 42

        let summary = MentalHealthCore().evaluate(snapshots: [], health: health)
        let autonomic = try XCTUnwrap(summary.assessments.first { $0.domain == .autonomic })

        XCTAssertEqual(summary.measuredSignalCount, 2)
        XCTAssertEqual(autonomic.level, .nearReference)
        XCTAssertTrue(autonomic.evidence.contains("sleep 6.1 hr"))
        XCTAssertTrue(autonomic.evidence.contains("HRV 42 ms"))
    }

    func testCognitiveBatteryScoresMeasuredTrials() {
        let score = CognitiveBatteryScorer.score(
            immediateCorrect: true,
            recalledWords: ["river", "velvet"],
            targetWords: ["river", "velvet", "lantern"],
            switchCorrect: 6,
            switchTrials: 8,
            inhibitionCorrect: 5,
            inhibitionTrials: 6
        )

        XCTAssertEqual(score.memory ?? 0, 5.0 / 6.0, accuracy: 0.001)
        XCTAssertEqual(score.attention ?? 0, 0.75, accuracy: 0.001)
        XCTAssertEqual(score.executiveFunction ?? 0, 5.0 / 6.0, accuracy: 0.001)
    }

    func testCognitiveBatteryDoesNotInventSkippedDomains() {
        let score = CognitiveBatteryScorer.score(
            immediateCorrect: nil,
            recalledWords: [],
            targetWords: ["river", "velvet", "lantern"],
            switchCorrect: 0,
            switchTrials: 0,
            inhibitionCorrect: 0,
            inhibitionTrials: 0
        )

        XCTAssertNil(score.memory)
        XCTAssertNil(score.attention)
        XCTAssertNil(score.executiveFunction)
    }

    func testGazeChallengeScoresMirroredCameraMovement() throws {
        let targets = [
            CGPoint(x: 0.5, y: 0.5),
            CGPoint(x: 0.2, y: 0.5),
            CGPoint(x: 0.8, y: 0.5),
            CGPoint(x: 0.5, y: 0.2),
            CGPoint(x: 0.5, y: 0.8)
        ]
        let mirroredMeasurements = [
            CGPoint(x: 0.5, y: 0.5),
            CGPoint(x: 0.68, y: 0.5),
            CGPoint(x: 0.32, y: 0.5),
            CGPoint(x: 0.5, y: 0.35),
            CGPoint(x: 0.5, y: 0.65)
        ]

        let score = try XCTUnwrap(GazeChallengeScorer.score(targets: targets, measurements: mirroredMeasurements))

        XCTAssertGreaterThan(score, 0.95)
    }

    func testPHQ2RequiresBothAnswersAndFlagsFollowUpAtThree() {
        XCTAssertNil(PHQ2Screen.score(firstAnswer: 2, secondAnswer: nil))
        XCTAssertEqual(PHQ2Screen.score(firstAnswer: 1, secondAnswer: 2), 3)
        XCTAssertTrue(PHQ2Screen.needsFollowUp(score: 3))
        XCTAssertFalse(PHQ2Screen.needsFollowUp(score: 2))
    }

    func testPHQ2GuidanceUsesOneFollowUpAndSafetyContract() {
        let lower = PHQ2Screen.guidance(score: 2)
        let followUp = PHQ2Screen.guidance(score: 3)

        XCTAssertFalse(lower.needsFollowUp)
        XCTAssertNil(lower.safety)
        XCTAssertTrue(lower.action.contains("does not rule depression out"))
        XCTAssertTrue(followUp.needsFollowUp)
        XCTAssertTrue(followUp.action.contains("PHQ-9"))
        XCTAssertTrue(followUp.safety?.contains("988") == true)
    }

    func testMoodAssessmentUsesPHQ2WithoutCallingItDiagnosis() throws {
        let snapshot = CognitiveSnapshot(capturedAt: .now, phq2Score: 4)

        let summary = MentalHealthCore().evaluate(snapshots: [snapshot], health: .empty)
        let mood = try XCTUnwrap(summary.assessments.first { $0.domain == .mood })

        XCTAssertEqual(mood.level, .clinicianReview)
        XCTAssertTrue(mood.evidence.contains("4/6"))
        XCTAssertFalse(mood.evidence.contains("%"))
        XCTAssertTrue(mood.action.contains("full clinical assessment"))
    }

    func testCognitionAssessmentSurfacesMeasuredDementiaPatternScreen() throws {
        let snapshot = CognitiveSnapshot(
            capturedAt: .now,
            spontaneousWordCount: 42,
            spontaneousLexicalDiversity: 0.28,
            memoryScore: 0.4,
            attentionScore: 0.6,
            executiveFunctionScore: 0.5
        )

        let summary = MentalHealthCore().evaluate(snapshots: [snapshot], health: .empty)
        let cognition = try XCTUnwrap(summary.assessments.first { $0.domain == .cognition })

        XCTAssertFalse(cognition.evidence.contains("dementia-pattern screen"))
        XCTAssertTrue(cognition.evidence.contains("memory task 40%"))
    }

    func testVoiceAssessmentDoesNotSurfaceLegacyParkinsonModelValues() throws {
        let snapshot = CognitiveSnapshot(
            capturedAt: .now,
            speechStability: 0.82,
            parkinsonsVoiceProbability: 0.79,
            parkinsonsVoiceQuality: 0.74
        )

        let summary = MentalHealthCore().evaluate(snapshots: [snapshot], health: .empty)
        let voice = try XCTUnwrap(summary.assessments.first { $0.domain == .voice })

        XCTAssertEqual(voice.level, .recorded)
        XCTAssertFalse(voice.evidence.contains("Parkinson"))
        XCTAssertFalse(voice.action.contains("advanced voice screen"))
    }

    func testVoiceAssessmentReportsLanguageMeasurementsWithoutDiseaseScores() throws {
        let snapshot = CognitiveSnapshot(
            capturedAt: .now,
            speechStability: 0.55,
            voiceActivityRatio: 0.31,
            noiseLevel: 0.18,
            spontaneousWordCount: 44,
            spontaneousLexicalDiversity: 0.28
        )

        let summary = MentalHealthCore().evaluate(snapshots: [snapshot], health: .empty)
        let voice = try XCTUnwrap(summary.assessments.first { $0.domain == .voice })

        XCTAssertFalse(voice.evidence.contains("dementia screen"))
        XCTAssertTrue(voice.evidence.contains("open speech 44 words"))
        XCTAssertFalse(voice.evidence.contains("mood-strain screen"))
    }

    func testAdaptiveFocusRecommendationRespondsToMeasuredContext() {
        let rested = FocusProtectionRecommendation.make(sleepHours: 7.8, signalLoad: 18)
        let shortSleep = FocusProtectionRecommendation.make(sleepHours: 6.2, signalLoad: 18)
        let highLoad = FocusProtectionRecommendation.make(sleepHours: 7.8, signalLoad: 72)

        XCTAssertEqual(rested.durationMinutes, 25)
        XCTAssertEqual(shortSleep.durationMinutes, 45)
        XCTAssertEqual(highLoad.durationMinutes, 60)
        XCTAssertTrue(shortSleep.shouldStartAutomatically)
        XCTAssertTrue(highLoad.shouldStartAutomatically)
    }

    @MainActor
    func testAdaptiveProtectionPreferencePersistsAcrossServiceInstances() {
        let suite = "CognitiveSupportServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = CognitiveSupportService(defaults: defaults)
        first.automaticLowSleepProtection = true

        let restored = CognitiveSupportService(defaults: defaults)
        XCTAssertTrue(restored.automaticLowSleepProtection)
    }

    @MainActor
    func testScreenTimeSelectionPersistsAcrossServiceInstances() {
        let suite = "CognitiveSupportSelectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let account = "test.\(UUID().uuidString)"
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = CognitiveSupportService(defaults: defaults, selectionAccount: account)
        defer { first.clearPersistedSelection() }
        first.selection = FamilyActivitySelection()

        let restored = CognitiveSupportService(defaults: defaults, selectionAccount: account)
        XCTAssertEqual(restored.selectedCount, 0)
        XCTAssertTrue(restored.hasPersistedSelection)
    }

    func testVoiceModelRequestsConfirmationOnlyAtSeventyFivePercent() {
        let accepted = ParkinsonVoiceScreenResult(probability: 0.31, quality: 0.72, voicedSeconds: 3)
        let elevated = ParkinsonVoiceScreenResult(probability: 0.79, quality: 0.76, voicedSeconds: 3)
        let limited = ParkinsonVoiceScreenResult(probability: 0.24, quality: 0.36, voicedSeconds: 2.2)

        XCTAssertFalse(accepted.needsConfirmation)
        XCTAssertTrue(elevated.needsConfirmation)
        XCTAssertFalse(limited.needsConfirmation)
    }

    func testCognitiveScreeningIndexUsesOnlyMeasuredTaskPerformance() throws {
        let snapshot = CognitiveSnapshot(
            capturedAt: .now,
            memoryScore: 0.5,
            attentionScore: 0.75,
            executiveFunctionScore: 1
        )

        let index = try XCTUnwrap(CognitiveScreeningIndexCalculator.score(snapshot: snapshot))

        XCTAssertEqual(index.score, 25)
        XCTAssertEqual(index.evidence, ["memory 50%", "attention 75%", "interference 100%"])
    }

    func testCognitiveScreeningIndexIsUnavailableWhenTasksAreSkipped() {
        let index = CognitiveScreeningIndexCalculator.score(snapshot: CognitiveSnapshot(capturedAt: .now))

        XCTAssertNil(index)
    }

    func testDementiaPatternScreeningIndexUsesCognitiveAndLanguageMeasures() throws {
        let snapshot = CognitiveSnapshot(
            capturedAt: .now,
            spontaneousWordCount: 50,
            spontaneousLexicalDiversity: 0.31,
            memoryScore: 0.5,
            attentionScore: 0.75,
            executiveFunctionScore: 1
        )

        let index = try XCTUnwrap(DementiaPatternScreeningIndexCalculator.score(snapshot: snapshot))

        XCTAssertTrue((0...100).contains(index.score))
        XCTAssertTrue(index.evidence.contains("memory 50%"))
        XCTAssertTrue(index.evidence.contains("spoken words 50"))
    }

    func testAlzheimerCompositeUsesCognitionLanguageAndGazeSignals() throws {
        let snapshot = CognitiveSnapshot(
            capturedAt: .now,
            fixationStability: 0.42,
            gazeTrackingScore: 0.39,
            speechStability: 0.48,
            spontaneousWordCount: 38,
            spontaneousLexicalDiversity: 0.25,
            memoryScore: 0.46,
            attentionScore: 0.52,
            executiveFunctionScore: 0.49
        )

        let index = try XCTUnwrap(AlzheimerCompositeScreeningIndexCalculator.score(snapshot: snapshot))

        XCTAssertTrue((0...100).contains(index.score))
        XCTAssertTrue(index.evidence.contains { $0.contains("cognitive screen") })
        XCTAssertTrue(index.evidence.contains { $0.contains("speech-language screen") })
        XCTAssertTrue(index.evidence.contains("gaze tracking 39%"))
        XCTAssertTrue(index.evidence.contains("fixation stability 42%"))
    }

    func testSpeechLanguageDementiaScreenUsesMeasuredVoiceFeaturesOnly() throws {
        let snapshot = CognitiveSnapshot(
            capturedAt: .now,
            speechStability: 0.52,
            spontaneousWordCount: 38,
            spontaneousLexicalDiversity: 0.25
        )

        let index = try XCTUnwrap(SpeechLanguageDementiaScreeningIndexCalculator.score(snapshot: snapshot))

        XCTAssertTrue((0...100).contains(index.score))
        XCTAssertTrue(index.evidence.contains("speech timing 52%"))
        XCTAssertTrue(index.evidence.contains("spoken words 38"))
        XCTAssertTrue(index.evidence.contains("lexical diversity 25%"))
    }

    func testSpeechLanguageDementiaScreenRequiresAtLeastTwoVoiceSignals() {
        let index = SpeechLanguageDementiaScreeningIndexCalculator.score(
            snapshot: CognitiveSnapshot(capturedAt: .now, speechStability: 0.52)
        )

        XCTAssertNil(index)
    }

    func testVoiceMoodStrainScreenUsesVoiceActivityAndSpeechFeatures() throws {
        let snapshot = CognitiveSnapshot(
            capturedAt: .now,
            speechStability: 0.5,
            voiceActivityRatio: 0.3,
            noiseLevel: 0.2,
            spontaneousWordCount: 42
        )

        let index = try XCTUnwrap(VoiceMoodStrainScreeningIndexCalculator.score(snapshot: snapshot))

        XCTAssertTrue((0...100).contains(index.score))
        XCTAssertTrue(index.evidence.contains("voice activity 30%"))
        XCTAssertTrue(index.evidence.contains("speech timing 50%"))
        XCTAssertTrue(index.evidence.contains("spoken words 42"))
    }

    func testDepressionScreeningIndexUsesPHQ2ScoreOnly() {
        let index = DepressionScreeningIndexCalculator.score(phq2Score: 4)

        XCTAssertEqual(index.score, 67)
        XCTAssertEqual(index.evidence, ["PHQ-2 4/6"])
    }

    func testDepressionCompositeUsesPHQVoicePupilAndRecoverySignals() throws {
        let now = Date()
        let prior = [
            CognitiveSnapshot(capturedAt: now.addingTimeInterval(-86_400 * 2), heartRateVariability: 72, sleepHours: 8.0),
            CognitiveSnapshot(capturedAt: now.addingTimeInterval(-86_400), heartRateVariability: 70, sleepHours: 7.8)
        ]
        var health = HealthMetrics.empty
        health.sleepHours = 5.7
        health.heartRateVariabilityMilliseconds = 46
        health.stepCount = 900
        let snapshot = CognitiveSnapshot(
            capturedAt: now,
            pupilResponse: 0.2,
            pupilSymmetry: 0.74,
            pupilVariability: 0.22,
            speechStability: 0.48,
            voiceActivityRatio: 0.28,
            noiseLevel: 0.18,
            spontaneousWordCount: 38,
            phq2Score: 4
        )

        let index = try XCTUnwrap(DepressionCompositeScreeningIndexCalculator.score(snapshot: snapshot, health: health, prior: prior))

        XCTAssertTrue((0...100).contains(index.score))
        XCTAssertTrue(index.evidence.contains("PHQ-2 4/6"))
        XCTAssertTrue(index.evidence.contains { $0.contains("voice mood-strain screen") })
        XCTAssertTrue(index.evidence.contains { $0.contains("pupil-autonomic screen") })
        XCTAssertTrue(index.evidence.contains { $0.contains("sleep") })
        XCTAssertTrue(index.evidence.contains { $0.contains("HRV") })
    }

    func testRecoveryStrainUsesOnlyPersonalHRVAndSleepHistory() throws {
        let score = try XCTUnwrap(RecoveryStrainCalculator.score(snapshots: CognitiveSnapshot.sampleHistory))

        XCTAssertTrue((0...100).contains(score.score))
        XCTAssertFalse(score.evidence.isEmpty)
    }

    func testRecoveryStrainIsUnavailableWithoutAReference() {
        let score = RecoveryStrainCalculator.score(snapshots: [CognitiveSnapshot.sampleHistory[0]])

        XCTAssertNil(score)
    }

    func testForecastsCreateFiveBandFollowUpWithoutDiagnosticCertaintyOrDiseaseStages() throws {
        let snapshot = CognitiveSnapshot(
            capturedAt: .now,
            speechStability: 0.54,
            voiceActivityRatio: 0.3,
            parkinsonsVoiceProbability: 0.82,
            parkinsonsVoiceQuality: 0.9,
            spontaneousWordCount: 38,
            spontaneousLexicalDiversity: 0.25,
            memoryScore: 0.42,
            attentionScore: 0.55,
            executiveFunctionScore: 0.51,
            phq2Score: 4
        )

        let forecasts = MentalSignalForecastCalculator.make(
            snapshots: [snapshot],
            health: .empty,
            signalLoadScore: 66
        )

        XCTAssertFalse(forecasts.isEmpty)
        XCTAssertTrue(forecasts.allSatisfy { (1...5).contains($0.band) })
        XCTAssertFalse(forecasts.contains { $0.domain == .parkinsonVoice })

        let combinedText = forecasts
            .flatMap { [$0.title, $0.action, $0.limitation, $0.bandText] + $0.evidence }
            .joined(separator: " ")
            .lowercased()
        XCTAssertTrue(combinedText.contains("not a"))
        XCTAssertFalse(combinedText.contains("diagnosed"))
        XCTAssertFalse(combinedText.contains("disease stage"))
    }

    func testForecastsStayUnavailableWithoutMeasuredInputs() {
        let forecasts = MentalSignalForecastCalculator.make(
            snapshots: [CognitiveSnapshot(capturedAt: .now)],
            health: .empty,
            signalLoadScore: nil
        )

        XCTAssertTrue(forecasts.isEmpty)
    }

    func testNightSignalRequiresEnoughMeasuredNights() {
        let inputs = (0..<6).map {
            NightSignalDailyInput(date: Date(timeIntervalSince1970: Double($0) * 86_400), overnightRestingHeartRateBPM: 60)
        }
        XCTAssertNil(NightSignalCalculator.evaluate(inputs, calendar: utcCalendar))
    }

    func testNightSignalRequiresTwoConsecutiveElevatedNights() throws {
        let values = [60, 60, 60, 60, 60, 60, 64, 64]
        let inputs = values.enumerated().map {
            NightSignalDailyInput(date: Date(timeIntervalSince1970: Double($0.offset) * 86_400), overnightRestingHeartRateBPM: Double($0.element))
        }
        let result = try XCTUnwrap(NightSignalCalculator.evaluate(inputs, calendar: utcCalendar))
        XCTAssertEqual(result.level, .high)
        XCTAssertEqual(result.overnightRestingHeartRateBPM, 64)
        XCTAssertEqual(result.runningMedianBPM, 60)
        XCTAssertEqual(result.measuredNights, 8)
    }

    func testNightSignalDoesNotAlertForOneElevatedNight() throws {
        let values = [60, 60, 60, 60, 60, 60, 60, 64]
        let inputs = values.enumerated().map {
            NightSignalDailyInput(date: Date(timeIntervalSince1970: Double($0.offset) * 86_400), overnightRestingHeartRateBPM: Double($0.element))
        }
        let result = try XCTUnwrap(NightSignalCalculator.evaluate(inputs, calendar: utcCalendar))
        XCTAssertEqual(result.level, .nearBaseline)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
