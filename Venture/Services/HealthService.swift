import Foundation
import HealthKit
import Observation

struct BloodPressureReading: Codable, Identifiable, Sendable, Equatable {
    static let manualSource = "Manual cuff entry"

    let id: UUID
    let systolicMMHg: Double
    let diastolicMMHg: Double
    let measuredAt: Date
    let source: String

    init(
        id: UUID = UUID(),
        systolicMMHg: Double,
        diastolicMMHg: Double,
        measuredAt: Date,
        source: String
    ) {
        self.id = id
        self.systolicMMHg = systolicMMHg
        self.diastolicMMHg = diastolicMMHg
        self.measuredAt = measuredAt
        self.source = source
    }

    static func validated(
        systolicMMHg: Double,
        diastolicMMHg: Double,
        measuredAt: Date = .now,
        source: String = manualSource
    ) throws -> Self {
        guard systolicMMHg.isFinite, diastolicMMHg.isFinite else {
            throw BloodPressureEntryError.invalidNumbers
        }
        guard (50...260).contains(systolicMMHg), (30...180).contains(diastolicMMHg) else {
            throw BloodPressureEntryError.outOfRange
        }
        guard systolicMMHg > diastolicMMHg else {
            throw BloodPressureEntryError.inverted
        }
        guard measuredAt <= Date.now.addingTimeInterval(60) else {
            throw BloodPressureEntryError.futureDate
        }
        return Self(
            systolicMMHg: systolicMMHg,
            diastolicMMHg: diastolicMMHg,
            measuredAt: measuredAt,
            source: source
        )
    }

    var band: BloodPressureBand {
        BloodPressureBand.classify(systolic: systolicMMHg, diastolic: diastolicMMHg)
    }
}

enum BloodPressureEntryError: LocalizedError, Equatable {
    case invalidNumbers
    case outOfRange
    case inverted
    case futureDate

    var errorDescription: String? {
        switch self {
        case .invalidNumbers:
            "Enter systolic and diastolic numbers from a cuff."
        case .outOfRange:
            "That value is outside the supported cuff range. Check the reading and enter it again."
        case .inverted:
            "Systolic pressure must be higher than diastolic pressure."
        case .futureDate:
            "The measurement time cannot be in the future."
        }
    }
}

struct HealthMetrics: Codable, Sendable, Equatable {
    var heartRateVariabilityMilliseconds: Double?
    var restingHeartRateBPM: Double?
    var sleepHours: Double?
    var sleepQuality: Double?
    var oxygenSaturationPercent: Double?
    var stepCount: Double?
    var activeEnergyKilocalories: Double?
    var bloodPressureSystolicMMHg: Double? = nil
    var bloodPressureDiastolicMMHg: Double? = nil
    var bloodPressureDate: Date? = nil
    var bloodPressureSource: String? = nil
    var bloodPressureHistory: [BloodPressureReading]? = nil
    var electrocardiogramDate: Date? = nil
    var electrocardiogramDurationSeconds: Double? = nil
    var electrocardiogramAverageHeartRateBPM: Double? = nil
    var electrocardiogramVoltageSampleCount: Int? = nil
    var electrocardiogramClassification: String? = nil
    var electrocardiogramSymptoms: String? = nil
    var electrocardiogramSource: String? = nil
    var electrocardiogramLeadIWaveformMillivolts: [Double]? = nil
    var nightSignalLevel: Int? = nil
    var nightSignalOvernightHeartRateBPM: Double? = nil
    var nightSignalBaselineBPM: Double? = nil
    var nightSignalSampleNights: Int? = nil
    var nightSignalDate: Date? = nil
    var updatedAt: Date?

    static let empty = HealthMetrics()

    var bloodPressureReadings: [BloodPressureReading] {
        if let bloodPressureHistory, !bloodPressureHistory.isEmpty {
            return bloodPressureHistory.sorted { $0.measuredAt > $1.measuredAt }
        }
        guard
            let systolic = bloodPressureSystolicMMHg,
            let diastolic = bloodPressureDiastolicMMHg,
            let date = bloodPressureDate
        else { return [] }
        return [
            BloodPressureReading(
                systolicMMHg: systolic,
                diastolicMMHg: diastolic,
                measuredAt: date,
                source: bloodPressureSource ?? "Apple Health"
            )
        ]
    }

    var hasData: Bool {
        heartRateVariabilityMilliseconds != nil || restingHeartRateBPM != nil || sleepHours != nil
            || oxygenSaturationPercent != nil || stepCount != nil || activeEnergyKilocalories != nil
            || bloodPressureDate != nil || electrocardiogramDate != nil || nightSignalDate != nil
    }
}

enum BloodPressureBand: String, Sendable, Equatable {
    case low = "Low range"
    case normal = "Normal range"
    case elevated = "Elevated range"
    case stageOne = "High range · stage 1"
    case stageTwo = "High range · stage 2"
    case severe = "Severe range"

    static func classify(systolic: Double, diastolic: Double) -> Self {
        if systolic > 180 || diastolic > 120 { return .severe }
        if systolic >= 140 || diastolic >= 90 { return .stageTwo }
        if systolic >= 130 || diastolic >= 80 { return .stageOne }
        if systolic >= 120 && diastolic < 80 { return .elevated }
        if systolic < 90 && diastolic < 60 { return .low }
        return .normal
    }

    var guidance: String {
        switch self {
        case .low:
            "A low reading is often harmless, but dizziness, fainting, confusion, or weakness should be discussed with a clinician."
        case .normal:
            "This reading is in the normal adult range. A single reading does not establish a trend."
        case .elevated, .stageOne, .stageTwo:
            "Recheck with a validated cuff and review repeated readings with your health care team."
        case .severe:
            "Wait one minute and recheck. If it remains above 180/120, contact a clinician; call emergency services for chest pain, weakness, vision change, or trouble speaking."
        }
    }
}

struct AppleECGGuidance: Sendable, Equatable {
    enum Level: Sendable {
        case nearReference
        case changed
        case clinicianReview
    }

    let classification: String
    let level: Level
    let meaning: String
    let action: String

    static func make(classification: String) -> AppleECGGuidance {
        switch classification {
        case "Sinus rhythm":
            .init(
                classification: classification,
                level: .nearReference,
                meaning: "Apple classified this single-lead recording as sinus rhythm.",
                action: "Keep measuring only when useful. Seek medical review for persistent symptoms even when a recording shows sinus rhythm."
            )
        case "Atrial fibrillation":
            .init(
                classification: classification,
                level: .clinicianReview,
                meaning: "Apple classified this recording as atrial fibrillation.",
                action: "Contact a clinician. Seek urgent help for chest pain, fainting, severe shortness of breath, weakness, or trouble speaking."
            )
        case "Inconclusive · low heart rate":
            .init(
                classification: classification,
                level: .changed,
                meaning: "Apple could not classify the rhythm because the recorded heart rate was below its supported classification range.",
                action: "Repeat when seated and still. Discuss repeated low-rate results, dizziness, fainting, weakness, or other symptoms with a clinician."
            )
        case "Inconclusive · high heart rate":
            .init(
                classification: classification,
                level: .changed,
                meaning: "Apple could not classify the rhythm because the recorded heart rate was above its supported classification range.",
                action: "Rest and repeat when appropriate. Seek prompt medical care for persistent rapid heart rate, chest pain, fainting, or severe shortness of breath."
            )
        case "Inconclusive · poor reading":
            .init(
                classification: classification,
                level: .changed,
                meaning: "Apple could not classify the recording because signal quality was insufficient.",
                action: "Rest your arms, keep the Watch snug, clean the sensors, and record again. Keep repeated poor readings for clinician review if symptoms persist."
            )
        default:
            .init(
                classification: classification,
                level: .changed,
                meaning: "Apple did not provide a conclusive rhythm classification for this recording.",
                action: "Record another ECG under calm, still conditions. Discuss repeated inconclusive recordings or concerning symptoms with a clinician."
            )
        }
    }
}

struct ECGTwelveLeadReconstruction: Sendable, Equatable {
    let leadNames: [String]
    let sampleCount: Int
    let qualityScore: Int
    let meanAbsoluteMillivolts: Double
    let peakToPeakMillivolts: Double
    let beatCount: Int
    let irregularityScore: Int
    let repolarizationShiftScore: Int
    let conductionDelayScore: Int
    let lowVoltageScore: Int

    var qualityNote: String {
        "\(sampleCount) lead-I samples -> \(leadNames.count)-lead reconstructed screening vector"
    }
}

enum ECGTwelveLeadReconstructor {
    private static let targetSampleCount = 240
    private static let leadNames = ["I", "II", "III", "aVR", "aVL", "aVF", "V1", "V2", "V3", "V4", "V5", "V6"]

    static func reconstruct(fromLeadI waveform: [Double]) -> ECGTwelveLeadReconstruction? {
        let cleaned = preprocess(waveform)
        guard cleaned.count >= 24 else { return nil }
        let leads = syntheticLeads(from: cleaned)
        guard leads.count == leadNames.count else { return nil }

        let peakToPeak = (cleaned.max() ?? 0) - (cleaned.min() ?? 0)
        let meanAbsolute = cleaned.reduce(0) { $0 + abs($1) } / Double(cleaned.count)
        let beatIndexes = qrsPeakIndexes(in: cleaned)
        let irregularity = irregularityScore(from: beatIndexes)
        let repolarization = repolarizationShiftScore(from: leads)
        let conduction = conductionDelayScore(from: cleaned, peaks: beatIndexes)
        let lowVoltage = boundedPercent((0.5 - min(0.5, peakToPeak)) / 0.5 * 100)
        let quality = qualityScore(sampleCount: cleaned.count, peakToPeak: peakToPeak, beats: beatIndexes.count)

        return ECGTwelveLeadReconstruction(
            leadNames: leadNames,
            sampleCount: cleaned.count,
            qualityScore: quality,
            meanAbsoluteMillivolts: meanAbsolute,
            peakToPeakMillivolts: peakToPeak,
            beatCount: beatIndexes.count,
            irregularityScore: irregularity,
            repolarizationShiftScore: repolarization,
            conductionDelayScore: conduction,
            lowVoltageScore: lowVoltage
        )
    }

    private static func preprocess(_ waveform: [Double]) -> [Double] {
        let finite = waveform.filter { $0.isFinite }
        guard finite.count >= 24 else { return [] }
        let sampled = downsample(finite, limit: targetSampleCount)
        let mean = sampled.reduce(0, +) / Double(sampled.count)
        let centered = sampled.map { $0 - mean }
        return movingAverageDenoise(centered, radius: 1)
    }

    private static func syntheticLeads(from leadI: [Double]) -> [[Double]] {
        let derivative = firstDerivative(leadI)
        let leadII = zip(leadI, derivative).map { 0.72 * $0 + 0.18 * $1 }
        let leadIII = zip(leadII, leadI).map { $0 - $1 }
        let aVR = zip(leadI, leadII).map { -($0 + $1) / 2 }
        let aVL = zip(leadI, leadII).map { $0 - $1 / 2 }
        let aVF = zip(leadII, leadI).map { $0 - $1 / 2 }
        let v1 = zip(leadI, derivative).map { -0.42 * $0 + 0.12 * $1 }
        let v2 = zip(leadI, derivative).map { -0.20 * $0 + 0.16 * $1 }
        let v3 = zip(leadI, derivative).map { 0.08 * $0 + 0.14 * $1 }
        let v4 = zip(leadI, derivative).map { 0.38 * $0 + 0.08 * $1 }
        let v5 = zip(leadI, derivative).map { 0.62 * $0 + 0.04 * $1 }
        let v6 = leadI.map { 0.78 * $0 }
        return [leadI, leadII, leadIII, aVR, aVL, aVF, v1, v2, v3, v4, v5, v6]
    }

    private static func firstDerivative(_ values: [Double]) -> [Double] {
        guard !values.isEmpty else { return [] }
        var result = Array(repeating: 0.0, count: values.count)
        for index in 1..<values.count {
            result[index] = values[index] - values[index - 1]
        }
        return result
    }

    private static func movingAverageDenoise(_ values: [Double], radius: Int) -> [Double] {
        guard radius > 0, values.count > radius * 2 else { return values }
        var result = values
        for index in values.indices {
            let lower = max(values.startIndex, index - radius)
            let upper = min(values.index(before: values.endIndex), index + radius)
            let window = values[lower...upper]
            result[index] = window.reduce(0, +) / Double(window.count)
        }
        return result
    }

    private static func qrsPeakIndexes(in values: [Double]) -> [Int] {
        guard values.count >= 12 else { return [] }
        let maximum = values.map(abs).max() ?? 0
        guard maximum > 0.08 else { return [] }
        let threshold = maximum * 0.55
        let refractory = max(5, values.count / 18)
        var peaks: [Int] = []
        var lastPeak = -refractory
        for index in 1..<(values.count - 1) {
            let magnitude = abs(values[index])
            guard magnitude >= threshold, magnitude >= abs(values[index - 1]), magnitude >= abs(values[index + 1]) else {
                continue
            }
            if index - lastPeak < refractory {
                if let previous = peaks.indices.last, magnitude > abs(values[peaks[previous]]) {
                    peaks[previous] = index
                    lastPeak = index
                }
            } else {
                peaks.append(index)
                lastPeak = index
            }
        }
        return peaks
    }

    private static func irregularityScore(from peaks: [Int]) -> Int {
        guard peaks.count >= 4 else { return 0 }
        let intervals = zip(peaks.dropFirst(), peaks).map { Double($0 - $1) }
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        guard mean > 0 else { return 0 }
        let variance = intervals.reduce(0) { $0 + pow($1 - mean, 2) } / Double(intervals.count)
        return boundedPercent(sqrt(variance) / mean * 240)
    }

    private static func repolarizationShiftScore(from leads: [[Double]]) -> Int {
        guard let lead = leads.dropFirst(6).max(by: { meanAbsolute($0) < meanAbsolute($1) }), lead.count >= 12 else {
            return 0
        }
        let baselineEnd = max(1, lead.count / 5)
        let stStart = min(lead.count - 1, lead.count / 2)
        let stEnd = min(lead.count - 1, stStart + max(2, lead.count / 12))
        let baseline = lead[..<baselineEnd].reduce(0, +) / Double(baselineEnd)
        let stWindow = lead[stStart...stEnd]
        let stMean = stWindow.reduce(0, +) / Double(stWindow.count)
        return boundedPercent(abs(stMean - baseline) / 0.24 * 100)
    }

    private static func conductionDelayScore(from values: [Double], peaks: [Int]) -> Int {
        guard !peaks.isEmpty else { return 0 }
        let maximum = values.map(abs).max() ?? 0
        guard maximum > 0 else { return 0 }
        let threshold = maximum * 0.35
        let widths = peaks.map { peak -> Double in
            var lower = peak
            var upper = peak
            while lower > values.startIndex, abs(values[lower]) > threshold { lower -= 1 }
            while upper < values.index(before: values.endIndex), abs(values[upper]) > threshold { upper += 1 }
            return Double(upper - lower) / Double(values.count)
        }
        let width = widths.reduce(0, +) / Double(widths.count)
        return boundedPercent(max(0, width - 0.035) / 0.08 * 100)
    }

    private static func qualityScore(sampleCount: Int, peakToPeak: Double, beats: Int) -> Int {
        let sampleComponent = min(1, Double(sampleCount) / 180)
        let amplitudeComponent = min(1, max(0, peakToPeak) / 0.7)
        let beatComponent = min(1, Double(beats) / 3)
        return boundedPercent((sampleComponent * 0.35 + amplitudeComponent * 0.35 + beatComponent * 0.3) * 100)
    }

    private static func meanAbsolute(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0) { $0 + abs($1) } / Double(values.count)
    }

    private static func downsample(_ values: [Double], limit: Int) -> [Double] {
        guard values.count > limit, limit > 1 else { return values }
        let stride = Double(values.count - 1) / Double(limit - 1)
        return (0..<limit).map { values[min(Int((Double($0) * stride).rounded()), values.count - 1)] }
    }

    private static func boundedPercent(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(100, max(0, value)).rounded())
    }
}

struct ECGScreeningProfile: Sendable, Equatable {
    struct Finding: Sendable, Equatable {
        let name: String
        let likelihood: Int
        let evidence: String
    }

    let source: String
    let findings: [Finding]
    let qualityNote: String
    let reconstruction: ECGTwelveLeadReconstruction?

    static func make(from health: HealthMetrics) -> ECGScreeningProfile? {
        let reconstruction = health.electrocardiogramLeadIWaveformMillivolts.flatMap {
            ECGTwelveLeadReconstructor.reconstruct(fromLeadI: $0)
        }
        guard health.electrocardiogramClassification != nil || reconstruction != nil else { return nil }
        let samples = health.electrocardiogramVoltageSampleCount ?? health.electrocardiogramLeadIWaveformMillivolts?.count ?? 0
        let sampleEvidence = reconstruction?.qualityNote ?? (samples > 0 ? "\(samples) voltage samples" : "classification metadata only")
        let source = health.electrocardiogramSource ?? "Apple Watch ECG"
        let rate = health.electrocardiogramAverageHeartRateBPM
        let rateEvidence = rate.map { " · average HR \(Int($0.rounded())) bpm" } ?? ""

        var findings: [Finding] = []
        if let classification = health.electrocardiogramClassification {
            let guidance = AppleECGGuidance.make(classification: classification)
            switch classification {
            case "Atrial fibrillation":
                findings.append(contentsOf: [
                .init(name: "atrial fibrillation screen", likelihood: 92, evidence: guidance.meaning),
                .init(name: "sinus rhythm screen", likelihood: 8, evidence: "Apple did not classify this recording as sinus rhythm.")
                ])
            case "Sinus rhythm":
                findings.append(contentsOf: [
                .init(name: "sinus rhythm screen", likelihood: 92, evidence: guidance.meaning),
                .init(name: "atrial fibrillation screen", likelihood: 8, evidence: "Apple did not classify this single-lead recording as atrial fibrillation.")
                ])
            case "Inconclusive · low heart rate":
                findings.append(contentsOf: [
                .init(name: "low-rate ECG screen", likelihood: 72, evidence: guidance.meaning + rateEvidence),
                .init(name: "atrial fibrillation screen", likelihood: 0, evidence: "Apple did not provide a rhythm classification.")
                ])
            case "Inconclusive · high heart rate":
                findings.append(contentsOf: [
                .init(name: "high-rate ECG screen", likelihood: 72, evidence: guidance.meaning + rateEvidence),
                .init(name: "atrial fibrillation screen", likelihood: 0, evidence: "Apple did not provide a rhythm classification.")
                ])
            case "Inconclusive · poor reading":
                findings.append(contentsOf: [
                .init(name: "ECG quality issue", likelihood: 85, evidence: guidance.meaning),
                .init(name: "atrial fibrillation screen", likelihood: 0, evidence: "Signal quality was insufficient for a rhythm screen.")
                ])
            default:
                findings.append(contentsOf: [
                .init(name: "inconclusive ECG screen", likelihood: 60, evidence: guidance.meaning),
                .init(name: "atrial fibrillation screen", likelihood: 0, evidence: "Apple did not provide a supported rhythm classification.")
                ])
            }
        }

        if let reconstruction {
            let qualityEvidence = "Reconstructed \(reconstruction.leadNames.count)-lead screening vector from Apple Watch Lead I; quality \(reconstruction.qualityScore)%."
            findings.append(contentsOf: [
                .init(
                    name: "reconstructed ischemia follow-up screen",
                    likelihood: reconstruction.qualityScore < 45 ? 0 : reconstruction.repolarizationShiftScore,
                    evidence: qualityEvidence
                ),
                .init(
                    name: "reconstructed conduction-delay screen",
                    likelihood: reconstruction.qualityScore < 45 ? 0 : reconstruction.conductionDelayScore,
                    evidence: "QRS-width surrogate from reconstructed limb and chest-lead features."
                ),
                .init(
                    name: "reconstructed low-voltage screen",
                    likelihood: reconstruction.qualityScore < 45 ? 0 : reconstruction.lowVoltageScore,
                    evidence: "Peak-to-peak amplitude \(String(format: "%.2f", reconstruction.peakToPeakMillivolts)) mV across imported Lead I."
                ),
                .init(
                    name: "reconstructed rhythm-irregularity screen",
                    likelihood: reconstruction.qualityScore < 45 ? 0 : reconstruction.irregularityScore,
                    evidence: "Beat-spacing variability from \(reconstruction.beatCount) detected QRS candidates."
                )
            ])
        }

        return ECGScreeningProfile(
            source: source,
            findings: findings,
            qualityNote: sampleEvidence,
            reconstruction: reconstruction
        )
    }
}

@MainActor
@Observable
final class HealthService {
    enum ConnectionState: String {
        case notConnected = "Not connected"
        case connected = "Connected"
        case unavailable = "Unavailable"
    }

    private let healthStore = HKHealthStore()
    private var observerQueries: [HKObserverQuery] = []

    var state: ConnectionState = HKHealthStore.isHealthDataAvailable() ? .notConnected : .unavailable
    var latest = HealthMetrics.empty
    var isRefreshing = false
    var isImportingECG = false
    var errorMessage: String?
    var ecgMessage: String?
    var bloodPressureMessage: String?

    private var readTypes: Set<HKObjectType> {
        var types = Set([
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
            HKObjectType.quantityType(forIdentifier: .heartRate),
            HKObjectType.quantityType(forIdentifier: .restingHeartRate),
            HKObjectType.quantityType(forIdentifier: .oxygenSaturation),
            HKObjectType.quantityType(forIdentifier: .stepCount),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
            HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic),
            HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic),
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        ].compactMap { $0 })
        types.insert(HKObjectType.electrocardiogramType())
        return types
    }

    func prepare() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            state = .unavailable
            return
        }

        do {
            let status = try await authorizationRequestStatus()
            guard status == .unnecessary else { return }
            state = .connected
            await refresh()
            startObservers()
        } catch {
            applyHealthAccessFailure(error, fallback: "Apple Health status could not be checked.")
        }
    }

    func requestAccess() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            state = .unavailable
            return
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            state = .connected
            errorMessage = nil
            await refresh()
            startObservers()
        } catch {
            applyHealthAccessFailure(error, fallback: "Apple Health access was not completed.")
        }
    }

    func refresh() async {
        guard state == .connected, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let cachedManualReadings = latest.bloodPressureReadings.filter { $0.source == BloodPressureReading.manualSource }

        async let hrv = latestQuantity(
            .heartRateVariabilitySDNN,
            unit: HKUnit.secondUnit(with: .milli),
            lookback: 7 * 86_400
        )
        async let restingHeartRate = latestQuantity(
            .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            lookback: 7 * 86_400
        )
        async let oxygen = latestQuantity(
            .oxygenSaturation,
            unit: .percent(),
            lookback: 7 * 86_400
        )
        async let steps = cumulativeQuantity(.stepCount, unit: .count(), since: .startOfToday)
        async let activeEnergy = cumulativeQuantity(.activeEnergyBurned, unit: .kilocalorie(), since: .startOfToday)
        async let sleep = sleepSummary()
        async let bloodPressure = recentBloodPressureReadings()
        async let electrocardiogram = latestElectrocardiogram()
        async let nightSignal = nightSignalSummary()

        let values = await (hrv, restingHeartRate, oxygen, steps, activeEnergy, sleep, bloodPressure, electrocardiogram, nightSignal)
        let pressureHistory = Self.mergeBloodPressureReadings(
            cachedManualReadings + values.6
        )
        let latestPressure = pressureHistory.first
        latest = HealthMetrics(
            heartRateVariabilityMilliseconds: values.0,
            restingHeartRateBPM: values.1,
            sleepHours: values.5.hours,
            sleepQuality: values.5.quality,
            oxygenSaturationPercent: values.2.map { $0 * 100 },
            stepCount: values.3,
            activeEnergyKilocalories: values.4,
            bloodPressureSystolicMMHg: latestPressure?.systolicMMHg,
            bloodPressureDiastolicMMHg: latestPressure?.diastolicMMHg,
            bloodPressureDate: latestPressure?.measuredAt,
            bloodPressureSource: latestPressure?.source,
            bloodPressureHistory: pressureHistory,
            electrocardiogramDate: values.7?.date,
            electrocardiogramDurationSeconds: values.7?.duration,
            electrocardiogramAverageHeartRateBPM: values.7?.averageHeartRate,
            electrocardiogramVoltageSampleCount: values.7?.sampleCount,
            electrocardiogramClassification: values.7?.classification,
            electrocardiogramSymptoms: values.7?.symptoms,
            electrocardiogramSource: values.7?.source,
            electrocardiogramLeadIWaveformMillivolts: values.7?.waveform,
            nightSignalLevel: values.8?.level.rawValue,
            nightSignalOvernightHeartRateBPM: values.8?.overnightRestingHeartRateBPM,
            nightSignalBaselineBPM: values.8?.runningMedianBPM,
            nightSignalSampleNights: values.8?.measuredNights,
            nightSignalDate: values.8?.date,
            updatedAt: .now
        )
        errorMessage = latest.hasData ? nil : "No recent Apple Health samples were available."
    }

    func restoreCached(_ metrics: HealthMetrics?) {
        guard let metrics else { return }
        latest = metrics
    }

    func clearCachedMetrics() {
        latest = .empty
    }

    @discardableResult
    func recordCuffReading(systolic: Double, diastolic: Double, measuredAt: Date = .now) -> Bool {
        do {
            let reading = try BloodPressureReading.validated(
                systolicMMHg: systolic,
                diastolicMMHg: diastolic,
                measuredAt: measuredAt
            )
            let history = Self.mergeBloodPressureReadings([reading] + latest.bloodPressureReadings)
            latest.bloodPressureSystolicMMHg = reading.systolicMMHg
            latest.bloodPressureDiastolicMMHg = reading.diastolicMMHg
            latest.bloodPressureDate = reading.measuredAt
            latest.bloodPressureSource = reading.source
            latest.bloodPressureHistory = history
            latest.updatedAt = .now
            bloodPressureMessage = "Cuff reading saved securely on this device."
            return true
        } catch {
            bloodPressureMessage = (error as? LocalizedError)?.errorDescription ?? "The cuff reading could not be saved."
            return false
        }
    }

    func importLatestElectrocardiogram() async {
        if state != .connected {
            await requestAccess()
        }
        guard state == .connected else {
            ecgMessage = "Apple Health access is required to import a Watch ECG."
            return
        }
        isImportingECG = true
        defer { isImportingECG = false }
        guard let summary = await latestElectrocardiogram() else {
            ecgMessage = "No Apple Watch ECG was available. Record one in the ECG app on Apple Watch, then try again."
            return
        }
        latest.electrocardiogramDate = summary.date
        latest.electrocardiogramDurationSeconds = summary.duration
        latest.electrocardiogramAverageHeartRateBPM = summary.averageHeartRate
        latest.electrocardiogramVoltageSampleCount = summary.sampleCount
        latest.electrocardiogramClassification = summary.classification
        latest.electrocardiogramSymptoms = summary.symptoms
        latest.electrocardiogramSource = summary.source
        latest.electrocardiogramLeadIWaveformMillivolts = summary.waveform
        latest.updatedAt = .now
        ecgMessage = summary.waveform.isEmpty
            ? "ECG metadata imported, but Apple Health did not return its voltage samples."
            : "Latest Watch ECG and lead-I voltage samples imported."
    }

    private func applyHealthAccessFailure(_ error: Error, fallback: String) {
        let description = (error as NSError).localizedDescription.lowercased()
        if description.contains("entitlement") || description.contains("health data is unavailable") {
            state = .unavailable
            errorMessage = "Apple Health is unavailable in this build or on this device."
        } else {
            state = .notConnected
            errorMessage = fallback
        }
    }

    private func authorizationRequestStatus() async throws -> HKAuthorizationRequestStatus {
        try await withCheckedThrowingContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(toShare: [], read: readTypes) { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    private func latestQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        lookback: TimeInterval
    ) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-lookback),
            end: .now,
            options: .strictEndDate
        )

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    private func cumulativeQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        since start: Date
    ) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) {
                _, result, _ in
                continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }

    private func sleepSummary() async -> (hours: Double?, quality: Double?) {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return (nil, nil) }
        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-36 * 3_600),
            end: .now,
            options: .strictEndDate
        )

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                let sleepSamples = (samples as? [HKCategorySample]) ?? []
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue
                ]
                let restorativeValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue
                ]
                let asleep = Self.mergedDuration(sleepSamples.filter { asleepValues.contains($0.value) })
                let restorative = Self.mergedDuration(sleepSamples.filter { restorativeValues.contains($0.value) })
                guard asleep > 0 else {
                    continuation.resume(returning: (nil, nil))
                    return
                }
                let hours = asleep / 3_600
                let durationScore = min(1, hours / 8)
                let restorativeScore = min(1, (restorative / asleep) / 0.4)
                continuation.resume(returning: (hours, durationScore * 0.6 + restorativeScore * 0.4))
            }
            healthStore.execute(query)
        }
    }

    private func recentBloodPressureReadings() async -> [BloodPressureReading] {
        guard
            let type = HKObjectType.correlationType(forIdentifier: .bloodPressure),
            let systolicType = HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic),
            let diastolicType = HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)
        else { return [] }

        let correlations: [HKCorrelation] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 30,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKCorrelation]) ?? [])
            }
            healthStore.execute(query)
        }
        let unit = HKUnit.millimeterOfMercury()
        return correlations.compactMap { correlation in
            guard
                let systolic = (correlation.objects(for: systolicType).first as? HKQuantitySample)?.quantity.doubleValue(for: unit),
                let diastolic = (correlation.objects(for: diastolicType).first as? HKQuantitySample)?.quantity.doubleValue(for: unit),
                let reading = try? BloodPressureReading.validated(
                    systolicMMHg: systolic,
                    diastolicMMHg: diastolic,
                    measuredAt: correlation.endDate,
                    source: correlation.sourceRevision.source.name
                )
            else { return nil }
            return reading
        }
    }

    nonisolated static func mergeBloodPressureReadings(_ readings: [BloodPressureReading]) -> [BloodPressureReading] {
        var result: [BloodPressureReading] = []
        for reading in readings.sorted(by: { $0.measuredAt > $1.measuredAt }) {
            let duplicate = result.contains {
                abs($0.measuredAt.timeIntervalSince(reading.measuredAt)) < 2
                    && abs($0.systolicMMHg - reading.systolicMMHg) < 0.5
                    && abs($0.diastolicMMHg - reading.diastolicMMHg) < 0.5
            }
            if !duplicate {
                result.append(reading)
            }
            if result.count == 30 { break }
        }
        return result
    }

    private func latestElectrocardiogram() async -> ECGSummary? {
        let type = HKObjectType.electrocardiogramType()
        let sample: HKElectrocardiogram? = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, _ in
                continuation.resume(returning: samples?.first as? HKElectrocardiogram)
            }
            healthStore.execute(query)
        }
        guard let sample else { return nil }
        let waveform = await leadIWaveform(for: sample)
        return ECGSummary(
            date: sample.endDate,
            duration: sample.endDate.timeIntervalSince(sample.startDate),
            averageHeartRate: sample.averageHeartRate?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())),
            sampleCount: sample.numberOfVoltageMeasurements,
            classification: Self.classificationName(sample.classification),
            symptoms: Self.symptomsName(sample.symptomsStatus),
            source: sample.sourceRevision.source.name,
            waveform: waveform
        )
    }

    private func nightSignalSummary() async -> NightSignalAssessment? {
        guard
            let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate),
            let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)
        else { return nil }

        let start = Calendar.current.date(byAdding: .day, value: -35, to: .now) ?? .now.addingTimeInterval(-35 * 86_400)
        async let heartRates = quantitySamples(type: heartRateType, since: start)
        async let steps = quantitySamples(type: stepType, since: start)
        let samples = await (heartRates, steps)
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let countUnit = HKUnit.count()
        let movementIntervals = Self.mergedIntervals(samples.1.compactMap { sample -> DateInterval? in
            guard sample.quantity.doubleValue(for: countUnit) > 0 else { return nil }
            return DateInterval(start: sample.startDate, end: sample.endDate)
        })

        var nightlyValues: [Date: [Double]] = [:]
        let calendar = Calendar.current
        for sample in samples.0 {
            let source = sample.sourceRevision.source.name.lowercased()
            let product = sample.sourceRevision.productType?.lowercased() ?? ""
            guard source.contains("watch") || product.contains("watch") else { continue }
            let hour = calendar.component(.hour, from: sample.startDate)
            guard (0...6).contains(hour) else { continue }
            let moving = Self.contains(sample.startDate, in: movementIntervals)
            guard !moving else { continue }
            let bpm = sample.quantity.doubleValue(for: bpmUnit)
            guard bpm.isFinite, (25...240).contains(bpm) else { continue }
            nightlyValues[calendar.startOfDay(for: sample.startDate), default: []].append(bpm)
        }

        let inputs = nightlyValues.compactMap { date, values -> NightSignalDailyInput? in
            guard values.count >= 2 else { return nil }
            return NightSignalDailyInput(date: date, overnightRestingHeartRateBPM: values.reduce(0, +) / Double(values.count))
        }
        return NightSignalCalculator.evaluate(inputs, calendar: calendar)
    }

    private func quantitySamples(type: HKQuantityType, since start: Date) async -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: .strictEndDate)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }
    }

    private func leadIWaveform(for electrocardiogram: HKElectrocardiogram) async -> [Double] {
        await withCheckedContinuation { continuation in
            let collector = ECGVoltageCollector(limit: 240)
            let query = HKElectrocardiogramQuery(electrocardiogram) { _, result in
                switch result {
                case .measurement(let measurement):
                    if let quantity = measurement.quantity(for: .appleWatchSimilarToLeadI) {
                        collector.append(quantity.doubleValue(for: HKUnit.voltUnit(with: .milli)))
                    }
                case .done:
                    continuation.resume(returning: collector.downsampled())
                case .error:
                    continuation.resume(returning: [])
                @unknown default:
                    continuation.resume(returning: [])
                }
            }
            healthStore.execute(query)
        }
    }

    private func startObservers() {
        guard observerQueries.isEmpty else { return }
        for case let sampleType as HKSampleType in readTypes {
            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completion, _ in
                completion()
                Task { @MainActor [weak self] in
                    await self?.refresh()
                }
            }
            observerQueries.append(query)
            healthStore.execute(query)
            healthStore.enableBackgroundDelivery(for: sampleType, frequency: .hourly) { _, _ in }
        }
    }

    nonisolated private static func mergedDuration(_ samples: [HKCategorySample]) -> TimeInterval {
        let intervals = samples
            .map { DateInterval(start: $0.startDate, end: $0.endDate) }
            .sorted { $0.start < $1.start }
        guard var current = intervals.first else { return 0 }
        var total: TimeInterval = 0

        for interval in intervals.dropFirst() {
            if interval.start <= current.end {
                current = DateInterval(start: current.start, end: max(current.end, interval.end))
            } else {
                total += current.duration
                current = interval
            }
        }
        return total + current.duration
    }

    nonisolated private static func mergedIntervals(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.sorted { $0.start < $1.start }
        guard var current = sorted.first else { return [] }
        var result: [DateInterval] = []
        for interval in sorted.dropFirst() {
            if interval.start <= current.end {
                current = DateInterval(start: current.start, end: max(current.end, interval.end))
            } else {
                result.append(current)
                current = interval
            }
        }
        result.append(current)
        return result
    }

    nonisolated private static func contains(_ date: Date, in sortedIntervals: [DateInterval]) -> Bool {
        var lower = 0
        var upper = sortedIntervals.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if sortedIntervals[middle].start <= date {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        guard lower > 0 else { return false }
        return sortedIntervals[lower - 1].contains(date)
    }

    nonisolated private static func classificationName(_ classification: HKElectrocardiogram.Classification) -> String {
        switch classification {
        case .sinusRhythm: "Sinus rhythm"
        case .atrialFibrillation: "Atrial fibrillation"
        case .inconclusiveLowHeartRate: "Inconclusive · low heart rate"
        case .inconclusiveHighHeartRate: "Inconclusive · high heart rate"
        case .inconclusivePoorReading: "Inconclusive · poor reading"
        case .inconclusiveOther: "Inconclusive"
        case .notSet: "Not classified"
        case .unrecognized: "Unrecognized"
        @unknown default: "Unrecognized"
        }
    }

    nonisolated private static func symptomsName(_ status: HKElectrocardiogram.SymptomsStatus) -> String {
        switch status {
        case .none: "None reported"
        case .present: "Reported during recording"
        case .notSet: "Not specified"
        @unknown default: "Not specified"
        }
    }
}

private struct ECGSummary: Sendable {
    let date: Date
    let duration: Double
    let averageHeartRate: Double?
    let sampleCount: Int
    let classification: String
    let symptoms: String
    let source: String
    let waveform: [Double]
}

private final class ECGVoltageCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var values: [Double] = []

    init(limit: Int) {
        self.limit = limit
        values.reserveCapacity(limit * 4)
    }

    func append(_ value: Double) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func downsampled() -> [Double] {
        lock.lock()
        let snapshot = values
        lock.unlock()
        guard snapshot.count > limit else { return snapshot }
        let stride = Double(snapshot.count - 1) / Double(limit - 1)
        return (0..<limit).map { snapshot[min(Int((Double($0) * stride).rounded()), snapshot.count - 1)] }
    }
}

private extension Date {
    static var startOfToday: Date { Calendar.current.startOfDay(for: .now) }
}
