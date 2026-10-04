import CoreGraphics
import Foundation

struct ScanResult: Sendable {
    let cameraAuthorized: Bool
    let microphoneAuthorized: Bool
    let eyeConfidence: Double
    let fixationStability: Double
    let blinkCount: Int
    let pupilResponse: Double?
    let pupilSymmetry: Double?
    let pupilVariability: Double?
    let gazeTrackingScore: Double?
    let speechStability: Double?
    let voiceActivityRatio: Double?
    let noiseLevel: Double?
    let parkinsonsVoiceProbability: Double?
    let parkinsonsVoiceQuality: Double?
    let spontaneousWordCount: Int?
    let spontaneousLexicalDiversity: Double?
    let respiratoryWheezeLikelihood: Double?
    let respiratoryRecordingQuality: Double?
    let respiratoryBreathSeconds: Double?
    let respiratoryAirflowIrregularity: Double?
    let memoryScore: Double?
    let attentionScore: Double?
    let executiveFunctionScore: Double?
    let phq2Score: Int?
    var voiceAcousticSummary: VoiceAcousticSummary? = nil
    var voiceResearchResult: VoiceResearchModelResult? = nil
}

struct CognitiveBatteryScore: Sendable, Equatable {
    let memory: Double?
    let attention: Double?
    let executiveFunction: Double?
}

enum CognitiveBatteryScorer {
    static func score(
        immediateCorrect: Bool?,
        recalledWords: Set<String>,
        targetWords: Set<String>,
        switchCorrect: Int,
        switchTrials: Int,
        inhibitionCorrect: Int,
        inhibitionTrials: Int
    ) -> CognitiveBatteryScore {
        let immediate = immediateCorrect.map { $0 ? 1.0 : 0.0 }
        let delayed: Double? = targetWords.isEmpty || recalledWords.isEmpty
            ? nil
            : Double(recalledWords.intersection(targetWords).count) / Double(targetWords.count)
        let memoryValues = [immediate, delayed].compactMap { $0 }
        let memory = memoryValues.isEmpty ? nil : memoryValues.reduce(0, +) / Double(memoryValues.count)
        let attention = ratio(correct: switchCorrect, trials: switchTrials)
        let executive = ratio(correct: inhibitionCorrect, trials: inhibitionTrials)
        return CognitiveBatteryScore(memory: memory, attention: attention, executiveFunction: executive)
    }

    private static func ratio(correct: Int, trials: Int) -> Double? {
        guard trials > 0 else { return nil }
        return min(1, max(0, Double(correct) / Double(trials)))
    }
}

enum GazeChallengeScorer {
    static func score(targets: [CGPoint], measurements: [CGPoint]) -> Double? {
        guard targets.count == measurements.count, targets.count >= 4 else { return nil }
        guard
            let horizontal = absoluteCorrelation(targets.map { Double($0.x) }, measurements.map { Double($0.x) }),
            let vertical = absoluteCorrelation(targets.map { Double($0.y) }, measurements.map { Double($0.y) })
        else { return nil }
        return min(1, max(0, (horizontal + vertical) / 2))
    }

    private static func absoluteCorrelation(_ lhs: [Double], _ rhs: [Double]) -> Double? {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return nil }
        let lhsMean = lhs.reduce(0, +) / Double(lhs.count)
        let rhsMean = rhs.reduce(0, +) / Double(rhs.count)
        let lhsCentered = lhs.map { $0 - lhsMean }
        let rhsCentered = rhs.map { $0 - rhsMean }
        let denominator = sqrt(
            lhsCentered.reduce(0) { $0 + $1 * $1 }
                * rhsCentered.reduce(0) { $0 + $1 * $1 }
        )
        guard denominator > 0.000_001 else { return nil }
        let numerator = zip(lhsCentered, rhsCentered).reduce(0) { $0 + $1.0 * $1.1 }
        return abs(numerator / denominator)
    }
}

enum PHQ2Screen {
    struct Guidance: Sendable, Equatable {
        let score: Int
        let needsFollowUp: Bool
        let status: String
        let action: String
        let safety: String?
    }

    static func score(firstAnswer: Int?, secondAnswer: Int?) -> Int? {
        guard let firstAnswer, let secondAnswer, (0...3).contains(firstAnswer), (0...3).contains(secondAnswer) else {
            return nil
        }
        return firstAnswer + secondAnswer
    }

    static func needsFollowUp(score: Int) -> Bool {
        score >= 3
    }

    static func guidance(score: Int) -> Guidance {
        let followUp = needsFollowUp(score: score)
        return Guidance(
            score: score,
            needsFollowUp: followUp,
            status: followUp ? "follow-up recommended" : "below the follow-up threshold",
            action: followUp
                ? "Complete a full clinical assessment such as PHQ-9 or speak with a qualified professional."
                : "This result does not rule depression out. Seek professional support for persistent low mood, loss of interest, or changes in daily function.",
            safety: followUp
                ? "If you may harm yourself or cannot stay safe, call or text 988 in the United States or contact emergency services."
                : nil
        )
    }
}
