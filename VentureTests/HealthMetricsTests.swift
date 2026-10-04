import XCTest
@testable import Venture

final class HealthMetricsTests: XCTestCase {
    func testLegacyParkinsonHeadCannotExecuteWithoutCompatibleFeatures() {
        XCTAssertThrowsError(try ParkinsonVoiceScreeningEngine.screen(
            samples: vowel(rate: 16_000, pitch: 220), sampleRate: 16_000
        ))
    }

    func testMeasuredVoiceFindsFundamentalAcrossPhoneSampleRates() throws {
        for rate in [8_000.0, 16_000.0, 44_100.0, 48_000.0] {
            let summary = try VoiceAcousticAnalyzer.analyze(samples: vowel(rate: rate, pitch: 220), sampleRate: rate)
            XCTAssertEqual(try XCTUnwrap(summary.pitchHz), 220, accuracy: 2)
            XCTAssertTrue(summary.isUsable)
            XCTAssertGreaterThan(summary.voicedSeconds, 2.5)
            XCTAssertLessThanOrEqual(summary.voicedSeconds, 3)
            XCTAssertLessThan(try XCTUnwrap(summary.pitchVariation), 0.02)
        }
    }

    func testMeasuredVoiceSilenceNoiseClippingAndInvalidInputsNeverPassQuality() throws {
        let silence = try VoiceAcousticAnalyzer.analyze(samples: [Float](repeating: 0, count: 48_000), sampleRate: 16_000)
        XCTAssertNil(silence.pitchHz)
        XCTAssertFalse(silence.isUsable)
        let clipped = vowel(rate: 16_000, pitch: 220).map { min(1, max(-1, $0 * 20)) }
        XCTAssertFalse(try VoiceAcousticAnalyzer.analyze(samples: clipped, sampleRate: 16_000).isUsable)
        XCTAssertThrowsError(try VoiceAcousticAnalyzer.analyze(samples: [Float](repeating: .nan, count: 48_000), sampleRate: 16_000))
        XCTAssertThrowsError(try VoiceAcousticAnalyzer.analyze(samples: vowel(rate: 16_000, pitch: 220), sampleRate: .infinity))
        XCTAssertThrowsError(try VoiceAcousticAnalyzer.analyze(samples: [Float](repeating: 0.1, count: 100), sampleRate: 16_000))
        var state: UInt64 = 42
        let noise = (0..<48_000).map { _ -> Float in
            state = state &* 6_364_136_223_846_793_005 &+ 1
            return (Float(state >> 40) / Float(1 << 24) - 0.5) * 0.2
        }
        XCTAssertFalse(try VoiceAcousticAnalyzer.analyze(samples: noise, sampleRate: 16_000).isUsable)
    }

    func testCombiningSamplesCannotHideAnUnusableTake() throws {
        let good = try VoiceAcousticAnalyzer.analyze(samples: vowel(rate: 16_000, pitch: 220), sampleRate: 16_000)
        let poor = VoiceAcousticSummary(pitchHz: 220, pitchVariation: 0.01, amplitudeVariation: 0.01, voicedSeconds: 5, recordingQuality: 0.1, clippingRatio: 0.5)
        XCTAssertEqual(good.combined(with: poor), good)
        XCTAssertEqual(poor.combined(with: good), good)
        XCTAssertFalse(poor.combined(with: poor).isUsable)
    }

    private func vowel(rate: Double, pitch: Double) -> [Float] {
        (0..<Int(rate * 3)).map { index in
            let phase = 2 * Double.pi * pitch * Double(index) / rate
            return Float(0.12 * (sin(phase) + 0.3 * sin(phase * 2)))
        }
    }

    func testRespiratoryAcousticScreenRespondsToWheezeLikeBreathingFixture() throws {
        let sampleRate = 16_000.0
        let duration = 4.0
        let wheeze = (0..<Int(sampleRate * duration)).map { index -> Float in
            let time = Double(index) / sampleRate
            let envelope = 0.7 + 0.3 * sin(2 * .pi * 0.35 * time)
            let tone = sin(2 * .pi * 920 * time)
            let breathNoise = 0.08 * sin(2 * .pi * 170 * time)
            return Float(0.08 * envelope * tone + 0.02 * breathNoise)
        }
        let broadBreath = (0..<Int(sampleRate * duration)).map { index -> Float in
            let time = Double(index) / sampleRate
            let low = sin(2 * .pi * 180 * time)
            let mid = 0.45 * sin(2 * .pi * 310 * time + 0.7)
            let modulation = 0.65 + 0.35 * sin(2 * .pi * 0.25 * time)
            return Float(0.07 * modulation * (low + mid))
        }

        let wheezeResult = try RespiratoryAcousticScreeningEngine.screen(samples: wheeze, sampleRate: sampleRate)
        let broadResult = try RespiratoryAcousticScreeningEngine.screen(samples: broadBreath, sampleRate: sampleRate)

        XCTAssertGreaterThan(wheezeResult.breathSeconds, 3)
        XCTAssertGreaterThan(wheezeResult.recordingQuality, 0.3)
        XCTAssertGreaterThan(wheezeResult.wheezeLikelihood, broadResult.wheezeLikelihood)
        XCTAssertTrue((0...1).contains(wheezeResult.airflowIrregularity))
    }

    func testBundledSileroVADModelLoadsAndExecutes() throws {
        let probability = try SileroVoiceActivityDetector.verifyBundledModelExecution()

        XCTAssertTrue(probability.isFinite)
        XCTAssertTrue((0...1).contains(probability))
    }

    func testSileroVADRejectsNonFiniteProbabilities() {
        XCTAssertNil(SileroVoiceActivityDetector.normalizedProbability(.nan))
        XCTAssertNil(SileroVoiceActivityDetector.normalizedProbability(.infinity))
        XCTAssertEqual(SileroVoiceActivityDetector.normalizedProbability(-0.4), 0)
        XCTAssertEqual(SileroVoiceActivityDetector.normalizedProbability(1.4), 1)
    }

    func testLegacyModelPercentagesCannotTriggerConfirmationOrDiagnosis() {
        XCTAssertFalse(ParkinsonVoiceScreenResult(probability: 0.99, quality: 0.82, voicedSeconds: 3).needsConfirmation)
        XCTAssertEqual(ParkinsonVoiceScreenResult(probability: 0.99, quality: 0.82, voicedSeconds: 3).classification, "research model unavailable")
    }

    func testRequestedResearchModelsNeverReportRunningWithoutArtifacts() {
        XCTAssertGreaterThanOrEqual(ScreeningModelCatalog.all.count, 11)
        XCTAssertEqual(
            Set(ScreeningModelCatalog.all.filter { $0.state == .active && $0.id != "local-companion-lfm2-5" }.map(\.name)),
            Set([
                "venture stress and anxiety strain screen",
                "venture respiratory acoustic screen",
                "PHQ-2 depression follow-up screen",
                "Apple Watch ECG classification screen",
                "NightSignal wearable anomaly",
                "Single-to-twelve-lead ECG reconstruction",
                "ECG ischemia follow-up screen"
            ])
        )
        XCTAssertTrue(
            ScreeningModelCatalog.all.contains {
                $0.id == "local-companion-lfm2-5"
                    && ($0.state == .available || $0.state == .active)
            }
        )
        XCTAssertTrue(ScreeningModelCatalog.all.contains { $0.id == "wavbert" && $0.state == .unavailable })
        XCTAssertTrue(ScreeningModelCatalog.all.contains { $0.id == "hubert-ecg" && $0.state == .informsTest })
        XCTAssertTrue(ScreeningModelCatalog.all.contains { $0.id == "ecg-reconstruction" && $0.state == .active })
        XCTAssertTrue(ScreeningModelCatalog.all.contains { $0.id == "ecg-mi-risk" && $0.state == .active })
        XCTAssertTrue(ScreeningModelCatalog.all.contains { $0.id == "qwen25" && $0.state == .unavailable })
        XCTAssertTrue(ScreeningModelCatalog.all.contains { $0.id == "bp-ppg" && $0.state == .unavailable })
        let newlyRequestedUnavailableModels = [
            "open-pupilext",
            "pupil-dlc",
            "parkinson-lvwarren",
            "parkinson-imadtoubal",
            "parkinson-reps-learning",
            "parkinson-mahesh",
            "depression-sukesh",
            "depression-hein",
            "depression-ser",
            "anxiety-depression-hariharitha",
            "alzheimers-42bismuth",
            "copd-acoustics",
            "respiratory-dnn",
            "respirenet",
            "copd-severity-lung-sounds"
        ]
        for id in newlyRequestedUnavailableModels {
            XCTAssertTrue(
                ScreeningModelCatalog.all.contains { $0.id == id && $0.state == .unavailable },
                "expected \(id) to be cataloged as unavailable until a real iOS artifact is bundled"
            )
        }
        XCTAssertTrue(ScreeningModelCatalog.all.contains { $0.id == "opensmile" && $0.state == .informsTest })
        XCTAssertTrue(ScreeningModelCatalog.all.contains { $0.id == "fhs-dementia-biomarkers" && $0.state == .informsTest })
        XCTAssertGreaterThanOrEqual(ScreeningModelCatalog.references(for: "voice").count, 2)
        XCTAssertGreaterThanOrEqual(ScreeningModelCatalog.references(for: "recovery").count, 5)
    }

    func testFaceCapturePositionRequiresCloseCenteredFace() {
        XCTAssertEqual(FaceCapturePosition.classify(bounds: .zero), .noFace)
        XCTAssertEqual(FaceCapturePosition.classify(bounds: CGRect(x: 0.3, y: 0.2, width: 0.3, height: 0.45)), .tooFar)
        XCTAssertEqual(FaceCapturePosition.classify(bounds: CGRect(x: 0.08, y: 0.08, width: 0.84, height: 0.84)), .tooClose)
        XCTAssertEqual(FaceCapturePosition.classify(bounds: CGRect(x: 0.03, y: 0.2, width: 0.48, height: 0.58)), .offCenter)
        XCTAssertEqual(FaceCapturePosition.classify(bounds: CGRect(x: 0.25, y: 0.17, width: 0.5, height: 0.62)), .ready)
    }

    func testLegacyEyeMeasurementsDoNotProduceResults() throws {
        let snapshot = CognitiveSnapshot(
            capturedAt: .now,
            fixationStability: 0.52,
            pupilResponse: 0.24,
            pupilSymmetry: 0.78,
            pupilVariability: 0.24,
            gazeTrackingScore: 0.49
        )

        let groups = MetricGroup.measured(health: .empty, snapshots: [snapshot])
        XCTAssertFalse(groups.contains { $0.id == "eyes" })
        let summary = MentalHealthCore().evaluate(snapshots: [snapshot], health: .empty)
        XCTAssertFalse(summary.forecasts.contains { $0.domain == .pupilResponse })
        XCTAssertEqual(summary.measuredSignalCount, 0)

    }

    func testAppleHealthValuesReplaceRecoveryFallbacks() throws {
        let health = HealthMetrics(
            heartRateVariabilityMilliseconds: 63,
            restingHeartRateBPM: 54,
            sleepHours: 7.8,
            sleepQuality: 0.91,
            oxygenSaturationPercent: 99,
            stepCount: 8_000,
            activeEnergyKilocalories: 420,
            updatedAt: .now
        )

        let recovery = try XCTUnwrap(
            MetricGroup.measured(health: health, snapshots: CognitiveSnapshot.sampleHistory)
                .first { $0.id == "recovery" }
        )

        XCTAssertEqual(recovery.metrics.first { $0.name == "HRV" }?.value, 63)
        XCTAssertEqual(recovery.metrics.first { $0.name == "Sleep" }?.value, 7.8)
        XCTAssertEqual(recovery.metrics.first { $0.name == "Steps" }?.value, 8_000)
        XCTAssertEqual(recovery.summary, "Read from Apple Health")
    }

    func testLegacyParkinsonVoiceValuesDoNotAppearAsMeasuredMetrics() throws {
        let snapshot = CognitiveSnapshot(
            capturedAt: .now,
            driftScore: nil,
            fixationStability: nil,
            speechStability: 0.81,
            parkinsonsVoiceProbability: 0.64,
            parkinsonsVoiceQuality: 0.88,
            spontaneousWordCount: 42,
            spontaneousLexicalDiversity: 0.71,
            heartRateVariability: nil,
            sleepHours: nil,
            attentionScore: nil
        )
        let voice = try XCTUnwrap(MetricGroup.measured(health: .empty, snapshots: [snapshot]).first { $0.id == "voice" })
        XCTAssertNil(voice.metrics.first { $0.name == "Voice research-model match" })
        XCTAssertNil(voice.metrics.first { $0.name == "Voice model sample quality" })
        XCTAssertEqual(voice.metrics.first { $0.name == "Open speech words" }?.value, 42)
        XCTAssertEqual(voice.metrics.first { $0.name == "Lexical diversity" }?.value, 71)
        XCTAssertNil(voice.metrics.first { $0.name == "Speech-language dementia screen" }?.value)
        XCTAssertNil(voice.metrics.first { $0.name == "Voice mood-strain screen" }?.value)
    }

    func testRespiratoryScreenAppearsAsMeasuredMetricAndForecast() throws {
        let snapshot = CognitiveSnapshot(
            capturedAt: .now,
            respiratoryWheezeLikelihood: 0.72,
            respiratoryRecordingQuality: 0.91,
            respiratoryBreathSeconds: 3.9,
            respiratoryAirflowIrregularity: 0.38
        )

        let voice = try XCTUnwrap(MetricGroup.measured(health: .empty, snapshots: [snapshot]).first { $0.id == "voice" })
        XCTAssertEqual(voice.metrics.first { $0.name == "Respiratory wheeze-like screen" }?.value, 72)
        XCTAssertEqual(voice.metrics.first { $0.name == "Respiratory sample quality" }?.value, 91)
        XCTAssertEqual(voice.metrics.first { $0.name == "Breathing sample length" }?.value, 3.9)
        XCTAssertEqual(voice.metrics.first { $0.name == "Airflow irregularity" }?.value, 38)

        let summary = MentalHealthCore().evaluate(snapshots: [snapshot], health: .empty)
        let forecast = try XCTUnwrap(summary.forecasts.first { $0.domain == .respiratory })
        XCTAssertEqual(forecast.title, "breathing follow-up")
        XCTAssertTrue(forecast.evidence.contains("wheeze-like acoustic signal 72%"))
    }

    func testLegacyParkinsonVoiceValuesAloneDoNotCreateAVoiceMetricGroup() {
        let snapshot = CognitiveSnapshot(
            capturedAt: .now,
            parkinsonsVoiceProbability: 64,
            parkinsonsVoiceQuality: 88
        )
        XCTAssertNil(MetricGroup.measured(health: .empty, snapshots: [snapshot]).first { $0.id == "voice" })
    }

    func testMeasuredTaskAndPHQ2ScoresDoNotBecomeDiseasePercentages() throws {
        let snapshot = CognitiveSnapshot(
            capturedAt: .now,
            spontaneousWordCount: 62,
            spontaneousLexicalDiversity: 0.41,
            memoryScore: 0.62,
            attentionScore: 0.70,
            executiveFunctionScore: 0.58,
            phq2Score: 4
        )
        let groups = MetricGroup.measured(health: .empty, snapshots: [snapshot])
        let cognition = try XCTUnwrap(groups.first { $0.id == "cognition" })
        let mood = try XCTUnwrap(groups.first { $0.id == "mood" })

        XCTAssertNil(cognition.metrics.first { $0.name == "Dementia-pattern screen" }?.value)
        XCTAssertNil(cognition.metrics.first { $0.name == "Alzheimer composite screen" }?.value)
        XCTAssertEqual(mood.metrics.first { $0.name == "PHQ-2 screen" }?.value, 4)
        XCTAssertNil(mood.metrics.first { $0.name == "Depression follow-up likelihood" }?.value)
        XCTAssertNil(mood.metrics.first { $0.name == "Depression composite screen" }?.value)
    }

    func testScreeningPercentagesStayHiddenWithoutSourceMeasurements() throws {
        let snapshot = CognitiveSnapshot(capturedAt: .now, speechStability: 0.82)
        let groups = MetricGroup.measured(health: .empty, snapshots: [snapshot])

        XCTAssertNil(groups.first { $0.id == "voice" }?.metrics.first { $0.name == "Speech-language dementia screen" })
        XCTAssertNil(groups.first { $0.id == "voice" }?.metrics.first { $0.name == "Voice mood-strain screen" })
        XCTAssertNil(groups.first { $0.id == "cognition" }?.metrics.first { $0.name == "Dementia-pattern screen" })
        XCTAssertNil(groups.first { $0.id == "mood" })
    }

    func testStressAnxietyStrainUsesMeasuredRecoveryVoiceAndMoodInputs() throws {
        let now = Date()
        let prior = [
            CognitiveSnapshot(capturedAt: now.addingTimeInterval(-86_400), heartRateVariability: 72, sleepHours: 8.0),
            CognitiveSnapshot(capturedAt: now.addingTimeInterval(-172_800), heartRateVariability: 68, sleepHours: 7.8)
        ]
        let latest = CognitiveSnapshot(
            capturedAt: now,
            speechStability: 0.43,
            voiceActivityRatio: 0.21,
            phq2Score: 3
        )
        var health = HealthMetrics.empty
        health.heartRateVariabilityMilliseconds = 42
        health.sleepHours = 5.4

        let score = try XCTUnwrap(
            StressAnxietyStrainIndexCalculator.score(latest: latest, health: health, prior: prior)
        )
        XCTAssertGreaterThanOrEqual(score.score, 60)
        XCTAssertTrue(score.evidence.contains { $0.contains("HRV") })
        XCTAssertTrue(score.evidence.contains { $0.contains("sleep") })
        XCTAssertTrue(score.evidence.contains { $0.contains("voice activity") })

        let summary = MentalHealthCore().evaluate(snapshots: prior + [latest], health: health)
        XCTAssertEqual(summary.assessments.first { $0.domain == .stress }?.level, .changed)
        XCTAssertNotNil(summary.forecasts.first { $0.domain == .stressAnxiety })
    }

    func testParkinsonRepeatUsesQualityWeightedLikelihood() {
        let first = ParkinsonVoiceScreenResult(probability: 0.8, quality: 0.9, voicedSeconds: 3)
        let second = ParkinsonVoiceScreenResult(probability: 0.4, quality: 0.3, voicedSeconds: 3)
        let combined = first.combined(with: second)

        XCTAssertEqual(combined.probability, 0.7, accuracy: 0.001)
        XCTAssertEqual(combined.quality, 0.6, accuracy: 0.001)
        XCTAssertEqual(combined.voicedSeconds, 6, accuracy: 0.001)
    }

    func testPersistedStateWithoutHealthCacheStillDecodes() throws {
        let state = PersistedVentureState(
            schemaVersion: 2,
            snapshots: CognitiveSnapshot.sampleHistory,
            driftScore: 22,
            scanCompletedToday: false,
            healthMetrics: .empty
        )
        let encoded = try JSONEncoder().encode(state)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "healthMetrics")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(PersistedVentureState.self, from: legacyData)
        XCTAssertNil(decoded.healthMetrics)
        XCTAssertEqual(decoded.driftScore, 22)
        XCTAssertEqual(decoded.schemaVersion, 2)
    }

    func testBloodPressureBandsUseAdultAHAThresholds() {
        XCTAssertEqual(BloodPressureBand.classify(systolic: 88, diastolic: 58), .low)
        XCTAssertEqual(BloodPressureBand.classify(systolic: 118, diastolic: 76), .normal)
        XCTAssertEqual(BloodPressureBand.classify(systolic: 126, diastolic: 76), .elevated)
        XCTAssertEqual(BloodPressureBand.classify(systolic: 132, diastolic: 82), .stageOne)
        XCTAssertEqual(BloodPressureBand.classify(systolic: 148, diastolic: 94), .stageTwo)
        XCTAssertEqual(BloodPressureBand.classify(systolic: 182, diastolic: 108), .severe)
    }

    func testBloodPressureAppearsInRecoveryMetrics() throws {
        var health = HealthMetrics.empty
        health.bloodPressureSystolicMMHg = 121
        health.bloodPressureDiastolicMMHg = 77
        health.bloodPressureDate = .now

        let recovery = try XCTUnwrap(
            MetricGroup.measured(health: health, snapshots: CognitiveSnapshot.sampleHistory)
                .first { $0.id == "recovery" }
        )
        XCTAssertEqual(recovery.metrics.first { $0.name == "Systolic pressure" }?.value, 121)
        XCTAssertEqual(recovery.metrics.first { $0.name == "Diastolic pressure" }?.value, 77)
    }

    func testImportedECGScreeningFindingsAppearInRecoveryMetrics() throws {
        var health = HealthMetrics.empty
        health.electrocardiogramClassification = "Sinus rhythm"
        health.electrocardiogramVoltageSampleCount = 480
        health.electrocardiogramSource = "Apple Watch"

        let recovery = try XCTUnwrap(
            MetricGroup.measured(health: health, snapshots: [])
                .first { $0.id == "recovery" }
        )

        XCTAssertEqual(recovery.metrics.first { $0.name == "sinus rhythm screen" }?.value, 92)
        XCTAssertEqual(recovery.metrics.first { $0.name == "atrial fibrillation screen" }?.value, 8)
    }

    func testSingleLeadECGReconstructionProducesBoundedTwelveLeadScreeningVector() throws {
        let waveform = (0..<480).map { index in
            let phase = Double(index) / 480 * 2 * .pi * 6
            return 0.7 * sin(phase) + 0.12 * sin(phase * 3)
        }

        let reconstruction = try XCTUnwrap(ECGTwelveLeadReconstructor.reconstruct(fromLeadI: waveform))

        XCTAssertEqual(reconstruction.leadNames.count, 12)
        XCTAssertEqual(reconstruction.sampleCount, 240)
        XCTAssertTrue((0...100).contains(reconstruction.qualityScore))
        XCTAssertTrue((0...100).contains(reconstruction.repolarizationShiftScore))
        XCTAssertTrue((0...100).contains(reconstruction.conductionDelayScore))
        XCTAssertTrue((0...100).contains(reconstruction.lowVoltageScore))
        XCTAssertTrue((0...100).contains(reconstruction.irregularityScore))
    }

    func testECGProfileAddsReconstructedDiseaseFollowUpScreensFromLeadIWaveform() throws {
        var health = HealthMetrics.empty
        health.electrocardiogramClassification = "Sinus rhythm"
        health.electrocardiogramAverageHeartRateBPM = 78
        health.electrocardiogramVoltageSampleCount = 480
        health.electrocardiogramLeadIWaveformMillivolts = (0..<480).map { index in
            let phase = Double(index) / 480 * 2 * .pi * 5
            return 0.55 * sin(phase) + 0.08 * sin(phase * 2.4)
        }

        let profile = try XCTUnwrap(ECGScreeningProfile.make(from: health))

        XCTAssertNotNil(profile.reconstruction)
        XCTAssertTrue(profile.qualityNote.contains("12-lead reconstructed screening vector"))
        XCTAssertTrue(profile.findings.contains { $0.name == "reconstructed ischemia follow-up screen" })
        XCTAssertTrue(profile.findings.contains { $0.name == "reconstructed conduction-delay screen" })
        XCTAssertTrue(profile.findings.contains { $0.name == "reconstructed low-voltage screen" })
        XCTAssertTrue(profile.findings.contains { $0.name == "reconstructed rhythm-irregularity screen" })
    }

    func testAppleECGScreeningProfileUsesImportedClassification() throws {
        var health = HealthMetrics.empty
        health.electrocardiogramClassification = "Atrial fibrillation"
        health.electrocardiogramAverageHeartRateBPM = 91
        health.electrocardiogramVoltageSampleCount = 512
        health.electrocardiogramSource = "Apple Watch"

        let profile = try XCTUnwrap(ECGScreeningProfile.make(from: health))

        XCTAssertEqual(profile.source, "Apple Watch")
        XCTAssertEqual(profile.qualityNote, "512 voltage samples")
        XCTAssertEqual(profile.findings.first?.name, "atrial fibrillation screen")
        XCTAssertEqual(profile.findings.first?.likelihood, 92)
        XCTAssertTrue(profile.findings.first?.evidence.contains("Apple classified") == true)
    }

    func testAppleECGProfileDoesNotExistWithoutImportedECG() {
        XCTAssertNil(ECGScreeningProfile.make(from: .empty))
    }

    func testCardiacAssessmentDisplaysECGScreeningFindings() throws {
        var health = HealthMetrics.empty
        health.electrocardiogramClassification = "Sinus rhythm"
        health.electrocardiogramVoltageSampleCount = 480

        let summary = MentalHealthCore().evaluate(snapshots: [], health: health)
        let cardiac = try XCTUnwrap(summary.assessments.first { $0.domain == .cardiac })

        XCTAssertEqual(cardiac.level, .nearReference)
        XCTAssertTrue(cardiac.evidence.contains("Apple classification: Sinus rhythm"))
        XCTAssertTrue(cardiac.evidence.contains("sinus rhythm screen 92%"))
        XCTAssertTrue(cardiac.evidence.contains("480 voltage samples"))
    }

    func testCuffReadingValidationRejectsInvertedAndImplausibleValues() throws {
        let accepted = try BloodPressureReading.validated(
            systolicMMHg: 118,
            diastolicMMHg: 76,
            measuredAt: .now
        )
        XCTAssertEqual(accepted.band, .normal)
        XCTAssertEqual(accepted.source, BloodPressureReading.manualSource)

        XCTAssertThrowsError(
            try BloodPressureReading.validated(systolicMMHg: 72, diastolicMMHg: 110)
        ) { error in
            XCTAssertEqual(error as? BloodPressureEntryError, .inverted)
        }
        XCTAssertThrowsError(
            try BloodPressureReading.validated(systolicMMHg: 320, diastolicMMHg: 80)
        ) { error in
            XCTAssertEqual(error as? BloodPressureEntryError, .outOfRange)
        }
    }

    func testBloodPressureHistoryMergesNewestFirstAndRemovesDuplicates() throws {
        let older = try BloodPressureReading.validated(
            systolicMMHg: 124,
            diastolicMMHg: 78,
            measuredAt: Date(timeIntervalSince1970: 100)
        )
        let newer = try BloodPressureReading.validated(
            systolicMMHg: 132,
            diastolicMMHg: 84,
            measuredAt: Date(timeIntervalSince1970: 200),
            source: "Health"
        )
        let duplicate = BloodPressureReading(
            systolicMMHg: 132,
            diastolicMMHg: 84,
            measuredAt: Date(timeIntervalSince1970: 201),
            source: "Duplicate import"
        )

        let merged = HealthService.mergeBloodPressureReadings([older, duplicate, newer])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first?.systolicMMHg, 132)
        XCTAssertEqual(merged.last?.systolicMMHg, 124)
    }

    func testBloodPressureHistoryDecodesWhenOlderCacheHasNoHistoryKey() throws {
        var health = HealthMetrics.empty
        health.bloodPressureSystolicMMHg = 126
        health.bloodPressureDiastolicMMHg = 79
        health.bloodPressureDate = Date(timeIntervalSince1970: 100)
        health.bloodPressureSource = "Apple Health"

        let encoded = try JSONEncoder().encode(health)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "bloodPressureHistory")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(HealthMetrics.self, from: legacyData)
        XCTAssertEqual(decoded.bloodPressureReadings.count, 1)
        XCTAssertEqual(decoded.bloodPressureReadings.first?.systolicMMHg, 126)
    }
}
