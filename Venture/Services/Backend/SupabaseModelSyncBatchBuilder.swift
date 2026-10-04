import Foundation

struct SupabaseMetricValue: Equatable {
    var domain: String
    var name: String
    var value: Double
    var unit: String
    var baseline: Double?
    var inverse: Bool
    var evidence: [String]
    var measuredAt: Date
}

struct SupabaseScreeningResult: Equatable {
    var modelID: String
    var outputType: SupabaseModelOutputPayload.OutputType
    var label: String
    var likelihoodPercent: Double?
    var evidence: [String]
    var action: String?
}

enum SupabaseModelSyncBatchBuilder {
    private static let disabledMetrics: Set<String> = ["Voice research-model match", "Pupil response screen", "Speech-language dementia screen", "Voice mood-strain screen", "Dementia-pattern screen", "Alzheimer composite screen", "Depression composite screen", "Depression follow-up likelihood"]

    static func metricValues(from groups: [MetricGroup], measuredAt: Date) -> [SupabaseMetricValue] {
        groups.filter { $0.id != "eyes" }.flatMap { group in
            group.metrics.filter { !disabledMetrics.contains($0.name) }.map { metric in
                SupabaseMetricValue(
                    domain: group.id,
                    name: metric.name,
                    value: metric.value,
                    unit: metric.unit,
                    baseline: metric.baseline,
                    inverse: metric.inverse,
                    evidence: [group.summary],
                    measuredAt: measuredAt
                )
            }
        }
    }

    static func screeningResults(from groups: [MetricGroup]) -> [SupabaseScreeningResult] {
        groups.filter { $0.id != "eyes" }.flatMap { group in
            group.metrics.compactMap { metric in
                guard !disabledMetrics.contains(metric.name), let modelID = modelID(for: metric.name, domain: group.id) else { return nil }
                return SupabaseScreeningResult(
                    modelID: modelID,
                    outputType: group.id == "recovery" ? .classification : .likelihood,
                    label: metric.name,
                    likelihoodPercent: normalizedLikelihood(metric.value, unit: metric.unit),
                    evidence: evidence(for: metric, in: group),
                    action: action(for: metric.name)
                )
            }
        }
    }

    static func forecastResults(from forecasts: [MentalSignalForecast]) -> [SupabaseScreeningResult] {
        forecasts.filter { $0.domain != .pupilResponse && $0.domain != .dementiaPattern && $0.domain != .parkinsonVoice }.map { forecast in
            SupabaseScreeningResult(
                modelID: "venture-progression-forecast",
                outputType: .summary,
                label: "\(forecast.domain.rawValue): \(forecast.bandText)",
                likelihoodPercent: nil,
                evidence: forecast.evidence + [
                    "timeframe: \(forecast.timeframe)",
                    forecast.limitation
                ],
                action: forecast.action
            )
        }
    }

    static func artifactAuditPayloads(
        userID: UUID,
        audits: [RuntimeModelArtifactAudit] = ModelRuntimeManifest.audit(),
        auditedAt: Date = .now
    ) -> [SupabaseModelArtifactAuditPayload] {
        audits.map { audit in
            SupabaseModelArtifactAuditPayload(
                userID: userID,
                modelID: audit.artifact.id,
                modelName: audit.artifact.displayName,
                runtime: audit.artifact.runtime,
                declaredState: audit.artifact.state,
                status: audit.status,
                executable: audit.isExecutable,
                sourcePath: audit.artifact.sourcePath,
                capability: audit.artifact.capability,
                evidence: audit.evidence,
                action: audit.action,
                auditedAt: auditedAt
            )
        }
    }

    static func makeBatch(
        userID: UUID,
        email: String? = nil,
        displayName: String? = nil,
        capturedAt: Date,
        driftScore: Int?,
        appVersion: String?,
        deviceModel: String?,
        metrics: [SupabaseMetricValue],
        screeningResults: [SupabaseScreeningResult],
        includeUnavailableResearchModels: Bool = false
    ) -> SupabaseModelSyncBatch {
        let scan = SupabaseScanSessionPayload(
            userID: userID,
            capturedAt: capturedAt,
            driftScore: driftScore,
            appVersion: appVersion,
            deviceModel: deviceModel
        )
        let normalizedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let profile = normalizedEmail.map {
            SupabaseProfilePayload(
                userID: userID,
                email: $0,
                displayName: displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                termsVersion: LegalConsent.currentTermsVersion,
                acceptedTermsAt: nil,
                acceptedPrivacyAt: nil
            )
        }

        let metricPayloads = metrics.filter { $0.domain != "eyes" && !disabledMetrics.contains($0.name) }.map {
            SupabaseSignalMetricPayload(
                userID: userID,
                scanID: nil,
                domain: $0.domain,
                name: $0.name,
                value: $0.value,
                unit: $0.unit,
                baseline: $0.baseline,
                inverse: $0.inverse,
                evidence: $0.evidence,
                measuredAt: $0.measuredAt
            )
        }

        let modelByID = Dictionary(uniqueKeysWithValues: ModelRuntimeManifest.all.map { ($0.id, $0) })
        var outputPayloads = screeningResults.compactMap { result -> SupabaseModelOutputPayload? in
            guard let model = modelByID[result.modelID], model.state != .unavailable else { return nil }
            return SupabaseModelOutputPayload(
                userID: userID,
                scanID: nil,
                modelID: model.id,
                modelName: model.displayName,
                runtime: model.runtime,
                state: model.state,
                outputType: result.outputType,
                label: result.label,
                likelihoodPercent: result.likelihoodPercent,
                evidence: result.evidence,
                action: result.action
            )
        }

        if includeUnavailableResearchModels {
            outputPayloads.append(contentsOf: ModelRuntimeManifest.unavailableExternalResearch.map { model in
                SupabaseModelOutputPayload(
                    userID: userID,
                    scanID: nil,
                    modelID: model.id,
                    modelName: model.displayName,
                    runtime: model.runtime,
                    state: model.state,
                    outputType: .unavailable,
                    label: "not bundled",
                    likelihoodPercent: nil,
                    evidence: ["No executable iOS artifact is bundled for this model."],
                    action: "Keep this result unavailable until a validated mobile artifact is added."
                )
            })
        }

        let audit = SupabaseAuditEventPayload(
            userID: userID,
            eventType: "scan_sync_prepared",
            metadata: [
                "metric_count": "\(metricPayloads.count)",
                "model_output_count": "\(outputPayloads.count)",
                "model_artifact_audit_count": "\(ModelRuntimeManifest.all.count)"
            ]
        )

        return SupabaseModelSyncBatch(
            profile: profile,
            scan: scan,
            metrics: metricPayloads,
            modelOutputs: outputPayloads,
            modelArtifactAudits: artifactAuditPayloads(userID: userID, auditedAt: capturedAt),
            auditEvents: [audit]
        )
    }

    private static func modelID(for metricName: String, domain: String) -> String? {
        switch metricName {
        case "Voice research-model match":
            "parkinson-voice-coreml"
        case "Pupil response screen":
            "pupil-autonomic-screen"
        case "Speech-language dementia screen":
            "speech-language-dementia-index"
        case "Voice mood-strain screen":
            "voice-mood-strain-index"
        case "Respiratory wheeze-like screen":
            "respiratory-acoustic-screen"
        case "Dementia-pattern screen":
            "cognitive-dementia-pattern-index"
        case "Alzheimer composite screen":
            domain == "cognition" ? "alzheimer-composite-screen" : nil
        case "Attention-switch screen":
            "attention-switch-screen"
        case "Depression follow-up likelihood":
            "phq2-depression-followup"
        case "Depression composite screen":
            domain == "mood" ? "depression-composite-screen" : nil
        case "sinus rhythm screen", "atrial fibrillation screen", "low-rate ECG screen", "high-rate ECG screen", "ECG quality issue", "inconclusive ECG screen":
            domain == "recovery" ? "apple-watch-ecg" : nil
        case "reconstructed ischemia follow-up screen", "reconstructed conduction-delay screen", "reconstructed low-voltage screen", "reconstructed rhythm-irregularity screen":
            domain == "recovery" ? "ecg-reconstructed-cardiac-screen" : nil
        case "Systolic pressure", "Diastolic pressure":
            domain == "recovery" ? "blood-pressure-cuff-screen" : nil
        case "Overnight inactive heart rate":
            domain == "recovery" ? "night-signal-wearable-anomaly" : nil
        case "HRV", "Sleep":
            domain == "recovery" ? "recovery-strain-index" : nil
        default:
            nil
        }
    }

    private static func normalizedLikelihood(_ value: Double, unit: String) -> Double? {
        guard unit == "%", value.isFinite else { return nil }
        return min(100, max(0, value))
    }

    private static func evidence(for metric: Metric, in group: MetricGroup) -> [String] {
        var values = [group.summary, "\(metric.name) \(formatted(metric.value))\(metric.unit)"]
        if metric.name == "Voice research-model match" {
            if let quality = group.metrics.first(where: { $0.name == "Voice model sample quality" }) {
                values.append("sample quality \(formatted(quality.value))\(quality.unit)")
            }
            if let voiceActivity = group.metrics.first(where: { $0.name == "Detected voice activity" }) {
                values.append("voice activity \(formatted(voiceActivity.value))\(voiceActivity.unit)")
            }
            if let noise = group.metrics.first(where: { $0.name == "Background noise" }) {
                values.append("background noise \(formatted(noise.value))\(noise.unit)")
            }
        }
        if metric.name == "Attention-switch screen" {
            if let attention = group.metrics.first(where: { $0.name == "Attention" }) {
                values.append("attention task performance \(formatted(attention.value))\(attention.unit)")
            }
        }
        if metric.name == "Alzheimer composite screen" {
            for related in ["Working memory", "Attention", "Interference control", "Dementia-pattern screen"] {
                if let value = group.metrics.first(where: { $0.name == related }) {
                    values.append("\(related.lowercased()) \(formatted(value.value))\(value.unit)")
                }
            }
        }
        if metric.name == "Pupil response screen" {
            for related in ["Pupil light response", "Pupil symmetry estimate", "Pupil estimate variability", "Fixation stability", "Gaze target tracking"] {
                if let value = group.metrics.first(where: { $0.name == related }) {
                    values.append("\(related.lowercased()) \(formatted(value.value))\(value.unit)")
                }
            }
        }
        if metric.name == "Respiratory wheeze-like screen" {
            if let quality = group.metrics.first(where: { $0.name == "Respiratory sample quality" }) {
                values.append("sample quality \(formatted(quality.value))\(quality.unit)")
            }
            if let seconds = group.metrics.first(where: { $0.name == "Breathing sample length" }) {
                values.append("breathing sample \(formatted(seconds.value))\(seconds.unit)")
            }
            if let airflow = group.metrics.first(where: { $0.name == "Airflow irregularity" }) {
                values.append("airflow irregularity \(formatted(airflow.value))\(airflow.unit)")
            }
        }
        if metric.name == "Systolic pressure" || metric.name == "Diastolic pressure" {
            if let systolic = group.metrics.first(where: { $0.name == "Systolic pressure" }),
               let diastolic = group.metrics.first(where: { $0.name == "Diastolic pressure" }) {
                values.append("cuff reading \(formatted(systolic.value))/\(formatted(diastolic.value)) mmHg")
            }
        }
        if metric.name == "Overnight inactive heart rate" {
            if let baseline = metric.baseline {
                values.append("personal median \(formatted(baseline))\(metric.unit)")
            }
        }
        if metric.name == "HRV" || metric.name == "Sleep" {
            if let baseline = metric.baseline {
                values.append("personal reference \(formatted(baseline))\(metric.unit)")
            }
        }
        if metric.name == "Depression composite screen" {
            if let phq = group.metrics.first(where: { $0.name == "PHQ-2 screen" }) {
                values.append("PHQ-2 \(formatted(phq.value))\(phq.unit)")
            }
            if let followUp = group.metrics.first(where: { $0.name == "Depression follow-up likelihood" }) {
                values.append("PHQ-2 follow-up \(formatted(followUp.value))\(followUp.unit)")
            }
        }
        return values
    }

    private static func action(for metricName: String) -> String? {
        switch metricName {
        case "Voice research-model match":
            "Repeat the advanced voice screen if this remains elevated."
        case "Pupil response screen":
            "Repeat once with even lighting and seek care for new visible pupil, severe headache, eye pain, weakness, confusion, or vision changes."
        case "Speech-language dementia screen", "Dementia-pattern screen", "Alzheimer composite screen":
            "Review the cognitive and speech evidence, then consider clinical follow-up if this remains elevated."
        case "Attention-switch screen":
            "Repeat when rested and compare with memory and interference-control results before interpreting a trend."
        case "Voice mood-strain screen", "Depression follow-up likelihood", "Depression composite screen":
            "Use this as a follow-up signal and seek professional support if symptoms are persistent or urgent."
        case "Respiratory wheeze-like screen":
            "Repeat in a quiet room and seek medical care for persistent wheeze, shortness of breath, chest pain, or breathing distress."
        case "sinus rhythm screen", "atrial fibrillation screen", "low-rate ECG screen", "high-rate ECG screen", "ECG quality issue", "inconclusive ECG screen":
            "Follow Apple ECG guidance and seek urgent care for concerning symptoms."
        case "Systolic pressure", "Diastolic pressure":
            "Recheck with a validated cuff and review repeated out-of-range readings with a clinician."
        case "Overnight inactive heart rate":
            "Check sleep, illness, alcohol, training, medication changes, and sensor fit if this stays elevated."
        case "HRV", "Sleep":
            "Use sleep protection and lower optional interruptions if recovery strain stays elevated."
        default:
            nil
        }
    }

    private static func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value.rounded() == value ? 0 : 1)))
    }
}
