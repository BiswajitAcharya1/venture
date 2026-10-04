import Foundation
import Observation

@MainActor
@Observable
final class VentureStore {
    private static let persistedSchemaVersion = 4

    var driftScore: Int?
    var scanCompletedToday = false
    var selectedTab: AppTab = .home
    var snapshots: [CognitiveSnapshot] = []
    var isReady = false
    var isGuestSession = false

    let healthService = HealthService()
    let supportService = CognitiveSupportService()
    let mentalHealthCore = MentalHealthCore()
    @ObservationIgnored private var persistenceAccountID: String?

    func beginSession(userID: String?) async {
        isGuestSession = true
        await jobs.cancel(id: "persist")
        snapshots = []
        driftScore = nil
        scanCompletedToday = false
        persistenceAccountID = nil
        healthService.restoreCached(.empty)
        guard let userID else { return }
        await secureStore.selectAccount(userID)
        if let state = await secureStore.load(), state.schemaVersion == Self.persistedSchemaVersion {
            snapshots = state.snapshots
            scanCompletedToday = state.scanCompletedToday
            driftScore = state.driftScore
        }
        persistenceAccountID = userID
        isGuestSession = false
    }

    @ObservationIgnored private let secureStore = SecureMetricsStore()
    @ObservationIgnored private let jobs = VentureJobPipeline()

    var driftHistory: [Int] {
        snapshots.suffix(7).compactMap(\.driftScore)
    }

    var metricGroups: [MetricGroup] {
        MetricGroup.measured(health: healthService.latest, snapshots: snapshots)
    }

    var mentalHealthSummary: MentalHealthSummary {
        mentalHealthCore.evaluate(snapshots: snapshots, health: healthService.latest)
    }

    func makeBackendSyncBatch(
        userID: UUID,
        email: String? = nil,
        displayName: String? = nil,
        appVersion: String?,
        deviceModel: String?
    ) -> SupabaseModelSyncBatch? {
        guard let latest = snapshots.last else { return nil }
        let groups = metricGroups
        let summary = mentalHealthSummary
        return SupabaseModelSyncBatchBuilder.makeBatch(
            userID: userID,
            email: email,
            displayName: displayName,
            capturedAt: latest.capturedAt,
            driftScore: latest.driftScore,
            appVersion: appVersion,
            deviceModel: deviceModel,
            metrics: SupabaseModelSyncBatchBuilder.metricValues(from: groups, measuredAt: latest.capturedAt),
            screeningResults: SupabaseModelSyncBatchBuilder.screeningResults(from: groups)
                + SupabaseModelSyncBatchBuilder.forecastResults(from: summary.forecasts)
        )
    }

    var recoveryEvidence: String {
        if let hrv = healthService.latest.heartRateVariabilityMilliseconds {
            return "HRV \(Int(hrv.rounded())) ms from Apple Health"
        }
        if let hrv = snapshots.last?.heartRateVariability {
            return "HRV \(Int(hrv.rounded())) ms from latest scan"
        }
        return "Connect Apple Health to add recovery data"
    }

    var recoveryCause: String {
        guard let sleep = healthService.latest.sleepHours else { return "Not enough recovery data" }
        return sleep < 7 ? "Short sleep" : "Recovery pattern"
    }

    func completeScan(result: ScanResult = ScanResult(
        cameraAuthorized: false,
        microphoneAuthorized: false,
        eyeConfidence: 0,
        fixationStability: 0,
        blinkCount: 0,
        pupilResponse: nil,
        pupilSymmetry: nil,
        pupilVariability: nil,
        gazeTrackingScore: nil,
        speechStability: nil,
        voiceActivityRatio: nil,
        noiseLevel: nil,
        parkinsonsVoiceProbability: nil,
        parkinsonsVoiceQuality: nil,
        spontaneousWordCount: nil,
        spontaneousLexicalDiversity: nil,
        respiratoryWheezeLikelihood: nil,
        respiratoryRecordingQuality: nil,
        respiratoryBreathSeconds: nil,
        respiratoryAirflowIrregularity: nil,
        memoryScore: nil,
        attentionScore: nil,
        executiveFunctionScore: nil,
        phq2Score: nil
    )) {
        scanCompletedToday = true
        let previous = snapshots
        let provisional = CognitiveSnapshot(
            capturedAt: .now,
            driftScore: nil,
            fixationStability: nil,
            pupilResponse: nil,
            pupilSymmetry: nil,
            pupilVariability: nil,
            gazeTrackingScore: nil,
            speechStability: result.microphoneAuthorized ? result.speechStability : nil,
            voiceActivityRatio: result.microphoneAuthorized ? result.voiceActivityRatio : nil,
            noiseLevel: result.microphoneAuthorized ? result.noiseLevel : nil,
            parkinsonsVoiceProbability: nil,
            parkinsonsVoiceQuality: nil,
            spontaneousWordCount: result.microphoneAuthorized ? result.spontaneousWordCount : nil,
            spontaneousLexicalDiversity: result.microphoneAuthorized ? result.spontaneousLexicalDiversity : nil,
            respiratoryWheezeLikelihood: result.microphoneAuthorized ? Self.normalizedFraction(result.respiratoryWheezeLikelihood) : nil,
            respiratoryRecordingQuality: result.microphoneAuthorized ? Self.normalizedFraction(result.respiratoryRecordingQuality) : nil,
            respiratoryBreathSeconds: result.microphoneAuthorized ? result.respiratoryBreathSeconds : nil,
            respiratoryAirflowIrregularity: result.microphoneAuthorized ? Self.normalizedFraction(result.respiratoryAirflowIrregularity) : nil,
            heartRateVariability: healthService.latest.heartRateVariabilityMilliseconds,
            sleepHours: healthService.latest.sleepHours,
            memoryScore: result.memoryScore,
            attentionScore: result.attentionScore,
            executiveFunctionScore: result.executiveFunctionScore,
            phq2Score: result.phq2Score,
            voiceAcousticSummary: result.microphoneAuthorized ? result.voiceAcousticSummary : nil,
            voiceResearchResult: result.microphoneAuthorized && result.voiceResearchResult?.isUsable == true ? result.voiceResearchResult : nil
        )
        let calculated = mentalHealthCore.evaluate(snapshots: previous + [provisional], health: healthService.latest).signalLoadScore
        let snapshot = provisional.replacing(driftScore: calculated)
        snapshots.removeAll { Calendar.current.isDate($0.capturedAt, inSameDayAs: snapshot.capturedAt) }
        snapshots.append(snapshot)
        driftScore = snapshot.driftScore
        supportService.updateContext(
            sleepHours: healthService.latest.sleepHours,
            signalLoad: driftScore
        )
        Haptics.success()
        schedulePersistence()
    }

    func bootstrap() async {
        Haptics.prepare()
        if let saved = await secureStore.load() {
            if saved.schemaVersion == Self.persistedSchemaVersion {
                snapshots = saved.snapshots
                driftScore = saved.driftScore
                scanCompletedToday = saved.scanCompletedToday
                healthService.restoreCached(saved.healthMetrics)
            } else {
                // Prototype builds included seeded values. Never migrate them into measured history.
                await secureStore.clear()
            }
        }
        isReady = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            await healthService.prepare()
            ingestHealthUpdate()
        }
    }

    func refreshHealth() async {
        await healthService.refresh()
        ingestHealthUpdate()
    }

    func importLatestECG() async {
        await healthService.importLatestElectrocardiogram()
        ingestHealthUpdate()
    }

    @discardableResult
    func recordCuffBloodPressure(systolic: Double, diastolic: Double, measuredAt: Date = .now) -> Bool {
        guard healthService.recordCuffReading(
            systolic: systolic,
            diastolic: diastolic,
            measuredAt: measuredAt
        ) else {
            Haptics.strong()
            return false
        }
        ingestHealthUpdate()
        Haptics.success()
        return true
    }

    func ingestHealthUpdate() {
        guard healthService.latest.hasData else { return }
        applyHealthToLatestSnapshot()
        refreshDriftScore()
        supportService.updateContext(
            sleepHours: healthService.latest.sleepHours,
            signalLoad: driftScore
        )
        schedulePersistence()
    }

    func deleteEyeHistory() {
        snapshots = snapshots.map {
            $0.replacing(
                fixationStability: .some(nil),
                pupilResponse: .some(nil),
                pupilSymmetry: .some(nil),
                pupilVariability: .some(nil),
                gazeTrackingScore: .some(nil)
            )
        }
        finishHistoryChange()
    }

    func deleteVoiceHistory() {
        snapshots = snapshots.map {
            $0.replacing(
                speechStability: .some(nil),
                voiceActivityRatio: .some(nil),
                noiseLevel: .some(nil),
                parkinsonsVoiceProbability: .some(nil),
                parkinsonsVoiceQuality: .some(nil),
                spontaneousWordCount: .some(nil),
                spontaneousLexicalDiversity: .some(nil),
                respiratoryWheezeLikelihood: .some(nil),
                respiratoryRecordingQuality: .some(nil),
                respiratoryBreathSeconds: .some(nil),
                respiratoryAirflowIrregularity: .some(nil),
                voiceAcousticSummary: .some(nil),
                voiceResearchResult: .some(nil)
            )
        }
        finishHistoryChange()
    }

    func deleteHealthHistory() {
        snapshots = snapshots.map {
            $0.replacing(heartRateVariability: .some(nil), sleepHours: .some(nil))
        }
        healthService.clearCachedMetrics()
        finishHistoryChange()
    }

    func clearAllScans() {
        snapshots = []
        driftScore = nil
        scanCompletedToday = false
        finishHistoryChange()
    }

    func wipeLocalData() async {
        await jobs.cancelAll()
        snapshots = []
        driftScore = nil
        scanCompletedToday = false
        healthService.clearCachedMetrics()
        supportService.stopProtection()
        supportService.clearPersistedSelection()
        await secureStore.destroy()
        Haptics.success()
    }

    private func applyHealthToLatestSnapshot() {
        guard let latest = snapshots.last, healthService.latest.hasData else { return }
        let updated = CognitiveSnapshot(
            capturedAt: latest.capturedAt,
            driftScore: latest.driftScore,
            fixationStability: latest.fixationStability,
            pupilResponse: latest.pupilResponse,
            pupilSymmetry: latest.pupilSymmetry,
            pupilVariability: latest.pupilVariability,
            gazeTrackingScore: latest.gazeTrackingScore,
            speechStability: latest.speechStability,
            voiceActivityRatio: latest.voiceActivityRatio,
            noiseLevel: latest.noiseLevel,
            parkinsonsVoiceProbability: latest.parkinsonsVoiceProbability,
            parkinsonsVoiceQuality: latest.parkinsonsVoiceQuality,
            spontaneousWordCount: latest.spontaneousWordCount,
            spontaneousLexicalDiversity: latest.spontaneousLexicalDiversity,
            respiratoryWheezeLikelihood: latest.respiratoryWheezeLikelihood,
            respiratoryRecordingQuality: latest.respiratoryRecordingQuality,
            respiratoryBreathSeconds: latest.respiratoryBreathSeconds,
            respiratoryAirflowIrregularity: latest.respiratoryAirflowIrregularity,
            heartRateVariability: healthService.latest.heartRateVariabilityMilliseconds ?? latest.heartRateVariability,
            sleepHours: healthService.latest.sleepHours ?? latest.sleepHours,
            memoryScore: latest.memoryScore,
            attentionScore: latest.attentionScore,
            executiveFunctionScore: latest.executiveFunctionScore,
            phq2Score: latest.phq2Score,
            voiceAcousticSummary: latest.voiceAcousticSummary,
            voiceResearchResult: latest.voiceResearchResult
        )
        snapshots[snapshots.count - 1] = updated
    }

    private func refreshDriftScore() {
        guard let latest = snapshots.last else { return }
        let score = mentalHealthCore.evaluate(snapshots: snapshots, health: healthService.latest).signalLoadScore
        snapshots[snapshots.count - 1] = latest.replacing(driftScore: score)
        driftScore = score
    }

    private func schedulePersistence() {
        guard !isGuestSession else { return }
        let value = PersistedVentureState(
            schemaVersion: Self.persistedSchemaVersion,
            snapshots: Array(snapshots.suffix(365)),
            driftScore: driftScore,
            scanCompletedToday: scanCompletedToday,
            healthMetrics: healthService.latest
        )
        let accountID = persistenceAccountID
        Task { [jobs, secureStore] in
            await jobs.replace(id: "persist", priority: .utility) {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await secureStore.save(value, expectedAccount: accountID)
            }
        }
    }

    private func finishHistoryChange() {
        refreshDriftScore()
        schedulePersistence()
        Haptics.success()
    }

    private static func normalizedFraction(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        let fraction = value > 1 ? value / 100 : value
        return min(1, max(0, fraction))
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case insights

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .insights: "Insights"
        }
    }

    var symbol: String {
        switch self {
        case .home: "circle"
        case .insights: "waveform.path.ecg"
        }
    }
}

struct PersistedVentureState: Codable, Sendable {
    let schemaVersion: Int?
    let snapshots: [CognitiveSnapshot]
    let driftScore: Int?
    let scanCompletedToday: Bool
    let healthMetrics: HealthMetrics?
}

struct Metric: Identifiable, Equatable {
    let id: String
    let name: String
    let value: Double
    let baseline: Double?
    let unit: String
    var inverse = false

    init(name: String, value: Double, baseline: Double?, unit: String, inverse: Bool = false) {
        self.id = name
        self.name = name
        self.value = value
        self.baseline = baseline
        self.unit = unit
        self.inverse = inverse
    }

    var differenceText: String {
        guard let baseline else { return "learning baseline" }
        let difference = abs(value - baseline)
        let formatted = difference.formatted(.number.precision(.fractionLength(difference.rounded() == difference ? 0 : 1)))
        return "\(formatted)\(unit) off"
    }
}

struct MetricGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let summary: String
    let symbol: String
    let metrics: [Metric]

    static func measured(health: HealthMetrics, snapshots: [CognitiveSnapshot]) -> [MetricGroup] {
        let context = snapshots.map(\.screeningContext)
        let latest = context.last
        let history = context.dropLast()
        var groups: [MetricGroup] = []

        var voiceMetrics: [Metric] = []
        if let value = latest?.speechStability {
            voiceMetrics.append(Metric(name: "Speech timing stability", value: value * 100, baseline: history.compactMap(\.speechStability).meanOrNil.map { $0 * 100 }, unit: "%"))
        }
        if let ratio = latest?.voiceActivityRatio {
            voiceMetrics.append(Metric(name: "Detected voice activity", value: ratio * 100, baseline: history.compactMap(\.voiceActivityRatio).meanOrNil.map { $0 * 100 }, unit: "%"))
        }
        if let noise = latest?.noiseLevel {
            voiceMetrics.append(Metric(name: "Background noise", value: noise * 100, baseline: history.compactMap(\.noiseLevel).meanOrNil.map { $0 * 100 }, unit: "%", inverse: true))
        }
        if let words = latest?.spontaneousWordCount {
            voiceMetrics.append(Metric(name: "Open speech words", value: Double(words), baseline: history.compactMap(\.spontaneousWordCount).map(Double.init).meanOrNil, unit: ""))
        }
        if let diversity = latest?.spontaneousLexicalDiversity {
            voiceMetrics.append(Metric(name: "Lexical diversity", value: diversity * 100, baseline: history.compactMap(\.spontaneousLexicalDiversity).meanOrNil.map { $0 * 100 }, unit: "%"))
        }
        if let wheeze = latest?.respiratoryWheezeLikelihood {
            voiceMetrics.append(Metric(name: "Respiratory wheeze-like screen", value: percentValue(from: wheeze), baseline: nil, unit: "%", inverse: true))
        }
        if let quality = latest?.respiratoryRecordingQuality {
            voiceMetrics.append(Metric(name: "Respiratory sample quality", value: percentValue(from: quality), baseline: nil, unit: "%"))
        }
        if let seconds = latest?.respiratoryBreathSeconds {
            voiceMetrics.append(Metric(name: "Breathing sample length", value: seconds, baseline: nil, unit: " sec"))
        }
        if let irregularity = latest?.respiratoryAirflowIrregularity {
            voiceMetrics.append(Metric(name: "Airflow irregularity", value: percentValue(from: irregularity), baseline: nil, unit: "%", inverse: true))
        }
        if let acoustic = latest?.voiceAcousticSummary {
            voiceMetrics.append(Metric(name: "Voice sample quality", value: acoustic.recordingQuality * 100, baseline: nil, unit: "%"))
            voiceMetrics.append(Metric(name: "Voiced sample length", value: acoustic.voicedSeconds, baseline: nil, unit: " sec"))
            if acoustic.isUsable, let pitch = acoustic.pitchHz {
                voiceMetrics.append(Metric(name: "Average pitch", value: pitch, baseline: history.compactMap(\.voiceAcousticSummary).filter(\.isUsable).compactMap(\.pitchHz).meanOrNil, unit: " Hz"))
            }
            if acoustic.isUsable, let variation = acoustic.pitchVariation {
                voiceMetrics.append(Metric(name: "Pitch variation", value: variation * 100, baseline: nil, unit: "%"))
            }
            if acoustic.isUsable, let variation = acoustic.amplitudeVariation {
                voiceMetrics.append(Metric(name: "Loudness variation", value: variation * 100, baseline: nil, unit: "%"))
            }
        }
        if !voiceMetrics.isEmpty {
            groups.append(MetricGroup(id: "voice", title: "Voice", summary: "Measured during the sustained voice sample", symbol: "waveform", metrics: voiceMetrics))
        }

        var cognition: [Metric] = []
        if let value = latest?.memoryScore {
            cognition.append(Metric(name: "Working memory", value: value * 100, baseline: history.compactMap(\.memoryScore).meanOrNil.map { $0 * 100 }, unit: "%"))
        }
        if let value = latest?.attentionScore {
            cognition.append(Metric(name: "Attention", value: value * 100, baseline: history.compactMap(\.attentionScore).meanOrNil.map { $0 * 100 }, unit: "%"))
            cognition.append(Metric(name: "Attention-switch screen", value: (1 - value) * 100, baseline: nil, unit: "%", inverse: true))
        }
        if let value = latest?.executiveFunctionScore {
            cognition.append(Metric(name: "Interference control", value: value * 100, baseline: history.compactMap(\.executiveFunctionScore).meanOrNil.map { $0 * 100 }, unit: "%"))
        }
        if !cognition.isEmpty {
            groups.append(MetricGroup(id: "cognition", title: "Cognition", summary: "Measured cognition and language screening context", symbol: "scope", metrics: cognition))
        }

        if let score = latest?.phq2Score {
            groups.append(MetricGroup(
                id: "mood", title: "Mood", summary: "Optional PHQ-2 responses; follow-up guidance, not diagnosis",
                symbol: "heart.text.clipboard",
                metrics: [Metric(name: "PHQ-2 screen", value: Double(score), baseline: history.compactMap(\.phq2Score).map(Double.init).meanOrNil, unit: "/6", inverse: true)]
            ))
        }

        var recovery: [Metric] = []
        if let value = health.heartRateVariabilityMilliseconds { recovery.append(Metric(name: "HRV", value: value, baseline: history.compactMap(\.heartRateVariability).meanOrNil, unit: " ms")) }
        if let value = health.sleepHours { recovery.append(Metric(name: "Sleep", value: value, baseline: history.compactMap(\.sleepHours).meanOrNil, unit: " hr")) }
        if let value = health.restingHeartRateBPM { recovery.append(Metric(name: "Resting heart rate", value: value, baseline: nil, unit: " bpm", inverse: true)) }
        if let value = health.oxygenSaturationPercent { recovery.append(Metric(name: "Oxygen saturation", value: value, baseline: nil, unit: "%")) }
        if let value = health.stepCount { recovery.append(Metric(name: "Steps", value: value, baseline: nil, unit: "")) }
        if let value = health.nightSignalOvernightHeartRateBPM {
            recovery.append(Metric(name: "Overnight inactive heart rate", value: value, baseline: health.nightSignalBaselineBPM, unit: " bpm", inverse: true))
        }
        if let value = health.bloodPressureSystolicMMHg { recovery.append(Metric(name: "Systolic pressure", value: value, baseline: nil, unit: " mmHg", inverse: true)) }
        if let value = health.bloodPressureDiastolicMMHg { recovery.append(Metric(name: "Diastolic pressure", value: value, baseline: nil, unit: " mmHg", inverse: true)) }
        if let ecgProfile = ECGScreeningProfile.make(from: health) {
            for finding in ecgProfile.findings {
                recovery.append(Metric(name: finding.name, value: Double(finding.likelihood), baseline: nil, unit: "%", inverse: finding.name != "sinus rhythm screen"))
            }
        }
        if !recovery.isEmpty {
            let summary = health.bloodPressureSource == BloodPressureReading.manualSource
                ? "Apple Health and measured cuff entry"
                : "Read from Apple Health"
            groups.append(MetricGroup(id: "recovery", title: "Recovery", summary: summary, symbol: "moon", metrics: recovery))
        }
        return groups
    }
}

private extension Collection where Element == Double {
    var mean: Double { reduce(0, +) / Double(count) }
    var meanOrNil: Double? { isEmpty ? nil : mean }
}

private func percentValue(from fractionOrPercent: Double) -> Double {
    guard fractionOrPercent.isFinite else { return 0 }
    let fraction = fractionOrPercent > 1 ? fractionOrPercent / 100 : fractionOrPercent
    return min(100, max(0, fraction * 100))
}

enum AppSheet: Identifiable {
    case scan

    var id: String { "scan" }
}

private extension CognitiveSnapshot {
    func replacing(
        driftScore: Int?? = nil,
        fixationStability: Double?? = nil,
        pupilResponse: Double?? = nil,
        pupilSymmetry: Double?? = nil,
        pupilVariability: Double?? = nil,
        gazeTrackingScore: Double?? = nil,
        speechStability: Double?? = nil,
        voiceActivityRatio: Double?? = nil,
        noiseLevel: Double?? = nil,
        parkinsonsVoiceProbability: Double?? = nil,
        parkinsonsVoiceQuality: Double?? = nil,
        spontaneousWordCount: Int?? = nil,
        spontaneousLexicalDiversity: Double?? = nil,
        respiratoryWheezeLikelihood: Double?? = nil,
        respiratoryRecordingQuality: Double?? = nil,
        respiratoryBreathSeconds: Double?? = nil,
        respiratoryAirflowIrregularity: Double?? = nil,
        heartRateVariability: Double?? = nil,
        sleepHours: Double?? = nil,
        phq2Score: Int?? = nil,
        voiceAcousticSummary: VoiceAcousticSummary?? = nil,
        voiceResearchResult: VoiceResearchModelResult?? = nil
    ) -> CognitiveSnapshot {
        CognitiveSnapshot(
            capturedAt: capturedAt,
            driftScore: driftScore ?? self.driftScore,
            fixationStability: fixationStability ?? self.fixationStability,
            pupilResponse: pupilResponse ?? self.pupilResponse,
            pupilSymmetry: pupilSymmetry ?? self.pupilSymmetry,
            pupilVariability: pupilVariability ?? self.pupilVariability,
            gazeTrackingScore: gazeTrackingScore ?? self.gazeTrackingScore,
            speechStability: speechStability ?? self.speechStability,
            voiceActivityRatio: voiceActivityRatio ?? self.voiceActivityRatio,
            noiseLevel: noiseLevel ?? self.noiseLevel,
            parkinsonsVoiceProbability: parkinsonsVoiceProbability ?? self.parkinsonsVoiceProbability,
            parkinsonsVoiceQuality: parkinsonsVoiceQuality ?? self.parkinsonsVoiceQuality,
            spontaneousWordCount: spontaneousWordCount ?? self.spontaneousWordCount,
            spontaneousLexicalDiversity: spontaneousLexicalDiversity ?? self.spontaneousLexicalDiversity,
            respiratoryWheezeLikelihood: respiratoryWheezeLikelihood ?? self.respiratoryWheezeLikelihood,
            respiratoryRecordingQuality: respiratoryRecordingQuality ?? self.respiratoryRecordingQuality,
            respiratoryBreathSeconds: respiratoryBreathSeconds ?? self.respiratoryBreathSeconds,
            respiratoryAirflowIrregularity: respiratoryAirflowIrregularity ?? self.respiratoryAirflowIrregularity,
            heartRateVariability: heartRateVariability ?? self.heartRateVariability,
            sleepHours: sleepHours ?? self.sleepHours,
            memoryScore: memoryScore,
            attentionScore: attentionScore,
            executiveFunctionScore: executiveFunctionScore,
            phq2Score: phq2Score ?? self.phq2Score,
            voiceAcousticSummary: voiceAcousticSummary ?? self.voiceAcousticSummary,
            voiceResearchResult: voiceResearchResult ?? self.voiceResearchResult
        )
    }
}
