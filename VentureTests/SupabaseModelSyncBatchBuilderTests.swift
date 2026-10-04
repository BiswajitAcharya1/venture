import XCTest
@testable import Venture

final class SupabaseModelSyncBatchBuilderTests: XCTestCase {
    func testMetricGroupsBecomeBackendMetricsAndScreeningResults() throws {
        let measuredAt = Date(timeIntervalSince1970: 1_800_000_111)
        let groups = [
            MetricGroup(
                id: "eyes",
                title: "Pupils",
                summary: "Relative camera estimates from the latest scan",
                symbol: "eye",
                metrics: [
                    Metric(name: "Pupil light response", value: 24, baseline: nil, unit: "%"),
                    Metric(name: "Pupil symmetry estimate", value: 78, baseline: nil, unit: "%"),
                    Metric(name: "Pupil estimate variability", value: 24, baseline: nil, unit: "%", inverse: true),
                    Metric(name: "Fixation stability", value: 52, baseline: nil, unit: "%"),
                    Metric(name: "Gaze target tracking", value: 49, baseline: nil, unit: "%"),
                    Metric(name: "Pupil response screen", value: 36, baseline: nil, unit: "%", inverse: true)
                ]
            ),
            MetricGroup(
                id: "voice",
                title: "Voice",
                summary: "Measured during the guided reading",
                symbol: "waveform",
                metrics: [
                    Metric(name: "Voice research-model match", value: 64, baseline: nil, unit: "%", inverse: true),
                    Metric(name: "Voice model sample quality", value: 88, baseline: nil, unit: "%"),
                    Metric(name: "Detected voice activity", value: 74, baseline: nil, unit: "%"),
                    Metric(name: "Background noise", value: 14, baseline: nil, unit: "%", inverse: true),
                    Metric(name: "Speech-language dementia screen", value: 22, baseline: nil, unit: "%", inverse: true),
                    Metric(name: "Voice mood-strain screen", value: 28, baseline: nil, unit: "%", inverse: true),
                    Metric(name: "Respiratory wheeze-like screen", value: 72, baseline: nil, unit: "%", inverse: true),
                    Metric(name: "Respiratory sample quality", value: 91, baseline: nil, unit: "%"),
                    Metric(name: "Breathing sample length", value: 3.9, baseline: nil, unit: " sec"),
                    Metric(name: "Airflow irregularity", value: 38, baseline: nil, unit: "%", inverse: true)
                ]
            ),
            MetricGroup(
                id: "cognition",
                title: "Cognition",
                summary: "Measured from task performance",
                symbol: "scope",
                metrics: [
                    Metric(name: "Attention", value: 71, baseline: nil, unit: "%"),
                    Metric(name: "Attention-switch screen", value: 29, baseline: nil, unit: "%", inverse: true),
                    Metric(name: "Dementia-pattern screen", value: 32, baseline: nil, unit: "%", inverse: true),
                    Metric(name: "Alzheimer composite screen", value: 35, baseline: nil, unit: "%", inverse: true)
                ]
            ),
            MetricGroup(
                id: "mood",
                title: "Mood",
                summary: "PHQ-2 self-report with measured pupil context",
                symbol: "heart.text.clipboard",
                metrics: [
                    Metric(name: "PHQ-2 screen", value: 4, baseline: nil, unit: "/6", inverse: true),
                    Metric(name: "Depression follow-up likelihood", value: 67, baseline: nil, unit: "%", inverse: true),
                    Metric(name: "Depression composite screen", value: 59, baseline: nil, unit: "%", inverse: true)
                ]
            ),
            MetricGroup(
                id: "recovery",
                title: "Recovery",
                summary: "Read from Apple Health",
                symbol: "moon",
                metrics: [
                    Metric(name: "sinus rhythm screen", value: 92, baseline: nil, unit: "%"),
                    Metric(name: "HRV", value: 63, baseline: 61, unit: " ms"),
                    Metric(name: "Sleep", value: 6.4, baseline: 7.3, unit: " hr"),
                    Metric(name: "Overnight inactive heart rate", value: 74, baseline: 66, unit: " bpm", inverse: true),
                    Metric(name: "Systolic pressure", value: 138, baseline: nil, unit: " mmHg", inverse: true),
                    Metric(name: "Diastolic pressure", value: 84, baseline: nil, unit: " mmHg", inverse: true)
                ]
            )
        ]

        let metrics = SupabaseModelSyncBatchBuilder.metricValues(from: groups, measuredAt: measuredAt)
        XCTAssertEqual(metrics.count, 16)
        XCTAssertEqual(metrics.first?.domain, "voice")
        XCTAssertEqual(metrics.first?.evidence, ["Measured during the guided reading"])
        XCTAssertEqual(metrics.first?.measuredAt, measuredAt)

        let outputs = SupabaseModelSyncBatchBuilder.screeningResults(from: groups)
        XCTAssertEqual(Set(outputs.map(\.modelID)), Set([
            "respiratory-acoustic-screen",
            "attention-switch-screen",
            "apple-watch-ecg",
            "recovery-strain-index",
            "night-signal-wearable-anomaly",
            "blood-pressure-cuff-screen"
        ]))
        XCTAssertEqual(outputs.first { $0.modelID == "recovery-strain-index" && $0.label == "HRV" }?.likelihoodPercent, nil)
        XCTAssertEqual(outputs.first { $0.modelID == "night-signal-wearable-anomaly" }?.evidence.contains("personal median 66 bpm"), true)
        XCTAssertEqual(outputs.first { $0.modelID == "blood-pressure-cuff-screen" }?.evidence.contains("cuff reading 138/84 mmHg"), true)
        XCTAssertEqual(outputs.first { $0.modelID == "attention-switch-screen" }?.evidence.contains("attention task performance 71%"), true)
        XCTAssertFalse(outputs.contains { ["parkinson-voice-coreml", "alzheimer-composite-screen", "pupil-autonomic-screen", "depression-composite-screen"].contains($0.modelID) })
        XCTAssertFalse(metrics.contains { $0.domain == "eyes" || $0.name == "Alzheimer composite screen" })
        XCTAssertEqual(outputs.first { $0.modelID == "apple-watch-ecg" }?.outputType, .classification)
        XCTAssertEqual(outputs.first { $0.modelID == "apple-watch-ecg" }?.likelihoodPercent, 92)
        XCTAssertEqual(outputs.first { $0.modelID == "respiratory-acoustic-screen" }?.evidence, [
            "Measured during the guided reading",
            "Respiratory wheeze-like screen 72%",
            "sample quality 91%",
            "breathing sample 3.9 sec",
            "airflow irregularity 38%"
        ])
    }

    func testBuildsVoiceAndECGModelOutputsFromMeasuredResults() throws {
        let userID = try XCTUnwrap(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let batch = SupabaseModelSyncBatchBuilder.makeBatch(
            userID: userID,
            email: "PERSON@Example.COM ",
            displayName: " Person ",
            capturedAt: capturedAt,
            driftScore: 37,
            appVersion: "1.0",
            deviceModel: "iPhone 13 Pro Max",
            metrics: [
                SupabaseMetricValue(
                    domain: "voice",
                    name: "Voice research-model match",
                    value: 64,
                    unit: "%",
                    baseline: nil,
                    inverse: true,
                    evidence: ["quality 88%", "voiced seconds 3.4"],
                    measuredAt: capturedAt
                )
            ],
            screeningResults: [
                SupabaseScreeningResult(
                    modelID: "parkinson-voice-coreml",
                    outputType: .likelihood,
                    label: "voice-model match",
                    likelihoodPercent: 64,
                    evidence: ["quality 88%"],
                    action: "repeat advanced voice screen if this remains elevated"
                ),
                SupabaseScreeningResult(
                    modelID: "apple-watch-ecg",
                    outputType: .classification,
                    label: "sinus rhythm screen",
                    likelihoodPercent: 92,
                    evidence: ["Apple classified the imported ECG as sinus rhythm."],
                    action: "keep monitoring if symptoms change"
                )
            ],
            includeUnavailableResearchModels: false
        )

        XCTAssertEqual(batch.scan.userID, userID)
        XCTAssertEqual(batch.scan.driftScore, 37)
        XCTAssertEqual(batch.profile?.email, "person@example.com")
        XCTAssertEqual(batch.profile?.displayName, "Person")
        XCTAssertEqual(batch.profile?.termsVersion, LegalConsent.currentTermsVersion)
        XCTAssertTrue(batch.metrics.isEmpty)

        XCTAssertFalse(batch.modelOutputs.contains { $0.modelID == "parkinson-voice-coreml" })

        let ecg = try XCTUnwrap(batch.modelOutputs.first { $0.modelID == "apple-watch-ecg" })
        XCTAssertEqual(ecg.modelName, "Apple Watch ECG classification")
        XCTAssertEqual(ecg.runtime, .healthKit)
        XCTAssertEqual(ecg.state, .sourceBound)
        XCTAssertEqual(ecg.outputType, .classification)
        XCTAssertEqual(ecg.likelihoodPercent, 92)
        XCTAssertFalse(batch.modelArtifactAudits.isEmpty)
        XCTAssertTrue(batch.modelArtifactAudits.contains { $0.modelID == "local-companion-lfm2-5" })
        XCTAssertTrue(batch.modelArtifactAudits.contains { $0.modelID == "wavbert" && $0.status == .unavailable })
    }

    func testDefaultBatchDoesNotUploadUnavailableResearchReferences() throws {
        let userID = try XCTUnwrap(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))

        let batch = SupabaseModelSyncBatchBuilder.makeBatch(
            userID: userID,
            capturedAt: .now,
            driftScore: nil,
            appVersion: nil,
            deviceModel: nil,
            metrics: [],
            screeningResults: []
        )

        XCTAssertTrue(batch.modelOutputs.isEmpty)
        XCTAssertFalse(batch.modelArtifactAudits.isEmpty)
        XCTAssertEqual(batch.auditEvents.first?.metadata["model_output_count"], "0")
    }

    func testForecastResultsSyncAsMeasuredSummaryOutputs() throws {
        let userID = try XCTUnwrap(UUID(uuidString: "55555555-5555-5555-5555-555555555555"))
        let forecast = MentalSignalForecast(
            domain: .recovery,
            title: "recovery follow-up",
            band: 4,
            score: 82,
            timeframe: "repeat soon and compare",
            evidence: ["sleep 5.5 hours", "personal reference 7.4 hours"],
            action: "protect recovery time",
            limitation: "not a disease prediction"
        )

        let batch = SupabaseModelSyncBatchBuilder.makeBatch(
            userID: userID,
            capturedAt: .now,
            driftScore: 58,
            appVersion: "1.0",
            deviceModel: "iPhone",
            metrics: [],
            screeningResults: SupabaseModelSyncBatchBuilder.forecastResults(from: [forecast])
        )

        let output = try XCTUnwrap(batch.modelOutputs.first)
        XCTAssertEqual(output.modelID, "venture-progression-forecast")
        XCTAssertEqual(output.modelName, "venture measured-signal forecast")
        XCTAssertEqual(output.runtime, .appNative)
        XCTAssertEqual(output.state, .sourceBound)
        XCTAssertEqual(output.outputType, .summary)
        XCTAssertNil(output.likelihoodPercent)
        XCTAssertTrue(output.label.contains("band 4/5"))
        XCTAssertTrue(output.evidence.contains("timeframe: repeat soon and compare"))
    }

    func testArtifactAuditPayloadsPreserveInstalledSourceBoundAndUnavailableStates() throws {
        let userID = try XCTUnwrap(UUID(uuidString: "66666666-6666-6666-6666-666666666666"))
        let auditedAt = Date(timeIntervalSince1970: 1_800_000_333)
        let installed = RuntimeModelArtifactAudit(
            artifact: RuntimeModelArtifact(
                id: "local-companion-lfm2-5",
                displayName: "LFM2.5 230M Instruct",
                runtime: .llamaCPP,
                state: .bundledExecutable,
                sourcePath: "model.gguf",
                capability: "local companion responses"
            ),
            status: .installed,
            evidence: "LFM2.5 artifact is present.",
            action: "Run execution test."
        )
        let sourceBound = RuntimeModelArtifactAudit(
            artifact: RuntimeModelArtifact(
                id: "attention-switch-screen",
                displayName: "venture attention-switch screen",
                runtime: .appNative,
                state: .sourceBound,
                sourcePath: nil,
                capability: "attention task screen"
            ),
            status: .sourceBound,
            evidence: "Runs from measured task input.",
            action: "Keep tied to measured input."
        )
        let unavailable = RuntimeModelArtifactAudit(
            artifact: RuntimeModelArtifact(
                id: "wavbert",
                displayName: "WavBERT",
                runtime: .coreML,
                state: .unavailable,
                sourcePath: nil,
                capability: "external Alzheimer speech model"
            ),
            status: .unavailable,
            evidence: "No executable iOS artifact.",
            action: "Do not show likelihoods."
        )

        let payloads = SupabaseModelSyncBatchBuilder.artifactAuditPayloads(
            userID: userID,
            audits: [installed, sourceBound, unavailable],
            auditedAt: auditedAt
        )

        XCTAssertEqual(Set(payloads.map(\.modelID)), Set(["local-companion-lfm2-5", "attention-switch-screen", "wavbert"]))
        XCTAssertTrue(payloads.allSatisfy { $0.userID == userID && $0.auditedAt == auditedAt })
        XCTAssertEqual(payloads.first { $0.modelID == "local-companion-lfm2-5" }?.status, .installed)
        XCTAssertEqual(payloads.first { $0.modelID == "attention-switch-screen" }?.status, .sourceBound)
        XCTAssertEqual(payloads.first { $0.modelID == "wavbert" }?.status, .unavailable)
        XCTAssertEqual(payloads.first { $0.modelID == "wavbert" }?.executable, false)
    }

    func testDiagnosticBatchCanListUnavailableResearchModelsWithoutLikelihoods() throws {
        let userID = try XCTUnwrap(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))

        let batch = SupabaseModelSyncBatchBuilder.makeBatch(
            userID: userID,
            capturedAt: .now,
            driftScore: nil,
            appVersion: nil,
            deviceModel: nil,
            metrics: [],
            screeningResults: [],
            includeUnavailableResearchModels: true
        )

        let unavailable = batch.modelOutputs.filter { $0.outputType == .unavailable }
        XCTAssertTrue(Set(unavailable.map(\.modelID)).isSuperset(of: ["wavbert", "hubert-ecg", "external-ecg-recon-coreml", "external-ecg-mi-risk", "bp-ppg"]))
        XCTAssertTrue(unavailable.allSatisfy { $0.state == .unavailable })
        XCTAssertTrue(unavailable.allSatisfy { $0.likelihoodPercent == nil })
        XCTAssertEqual(batch.auditEvents.first?.metadata["model_output_count"], "\(unavailable.count)")
    }
}
