import Foundation

struct CognitiveSnapshot: Codable, Sendable, Equatable {
    let capturedAt: Date
    let driftScore: Int?
    let fixationStability: Double?
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
    let heartRateVariability: Double?
    let sleepHours: Double?
    let memoryScore: Double?
    let attentionScore: Double?
    let executiveFunctionScore: Double?
    let phq2Score: Int?
    let voiceAcousticSummary: VoiceAcousticSummary?
    let voiceResearchResult: VoiceResearchModelResult?

    init(
        capturedAt: Date,
        driftScore: Int? = nil,
        fixationStability: Double? = nil,
        pupilResponse: Double? = nil,
        pupilSymmetry: Double? = nil,
        pupilVariability: Double? = nil,
        gazeTrackingScore: Double? = nil,
        speechStability: Double? = nil,
        voiceActivityRatio: Double? = nil,
        noiseLevel: Double? = nil,
        parkinsonsVoiceProbability: Double? = nil,
        parkinsonsVoiceQuality: Double? = nil,
        spontaneousWordCount: Int? = nil,
        spontaneousLexicalDiversity: Double? = nil,
        respiratoryWheezeLikelihood: Double? = nil,
        respiratoryRecordingQuality: Double? = nil,
        respiratoryBreathSeconds: Double? = nil,
        respiratoryAirflowIrregularity: Double? = nil,
        heartRateVariability: Double? = nil,
        sleepHours: Double? = nil,
        memoryScore: Double? = nil,
        attentionScore: Double? = nil,
        executiveFunctionScore: Double? = nil,
        phq2Score: Int? = nil,
        voiceAcousticSummary: VoiceAcousticSummary? = nil,
        voiceResearchResult: VoiceResearchModelResult? = nil
    ) {
        self.capturedAt = capturedAt
        self.driftScore = driftScore
        self.fixationStability = fixationStability
        self.pupilResponse = pupilResponse
        self.pupilSymmetry = pupilSymmetry
        self.pupilVariability = pupilVariability
        self.gazeTrackingScore = gazeTrackingScore
        self.speechStability = speechStability
        self.voiceActivityRatio = voiceActivityRatio
        self.noiseLevel = noiseLevel
        self.parkinsonsVoiceProbability = parkinsonsVoiceProbability
        self.parkinsonsVoiceQuality = parkinsonsVoiceQuality
        self.spontaneousWordCount = spontaneousWordCount
        self.spontaneousLexicalDiversity = spontaneousLexicalDiversity
        self.respiratoryWheezeLikelihood = respiratoryWheezeLikelihood
        self.respiratoryRecordingQuality = respiratoryRecordingQuality
        self.respiratoryBreathSeconds = respiratoryBreathSeconds
        self.respiratoryAirflowIrregularity = respiratoryAirflowIrregularity
        self.heartRateVariability = heartRateVariability
        self.sleepHours = sleepHours
        self.memoryScore = memoryScore
        self.attentionScore = attentionScore
        self.executiveFunctionScore = executiveFunctionScore
        self.phq2Score = phq2Score
        self.voiceAcousticSummary = voiceAcousticSummary
        self.voiceResearchResult = voiceResearchResult
    }
}

// Legacy eye measurements remain readable for deletion/migration, but are never
// part of the current voice screening or assistant context.
extension CognitiveSnapshot {
    var screeningContext: CognitiveSnapshot {
        CognitiveSnapshot(
            capturedAt: capturedAt, driftScore: nil,
            speechStability: speechStability, voiceActivityRatio: voiceActivityRatio,
            noiseLevel: noiseLevel, spontaneousWordCount: spontaneousWordCount,
            spontaneousLexicalDiversity: spontaneousLexicalDiversity,
            respiratoryWheezeLikelihood: respiratoryWheezeLikelihood,
            respiratoryRecordingQuality: respiratoryRecordingQuality,
            respiratoryBreathSeconds: respiratoryBreathSeconds,
            respiratoryAirflowIrregularity: respiratoryAirflowIrregularity,
            heartRateVariability: heartRateVariability, sleepHours: sleepHours,
            memoryScore: memoryScore, attentionScore: attentionScore,
            executiveFunctionScore: executiveFunctionScore, phq2Score: phq2Score,
            voiceAcousticSummary: voiceAcousticSummary,
            voiceResearchResult: voiceResearchResult
        )
    }
}
