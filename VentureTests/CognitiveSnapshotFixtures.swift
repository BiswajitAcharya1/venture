import Foundation
@testable import Venture

extension CognitiveSnapshot {
    static let sampleHistory: [CognitiveSnapshot] = [
        .init(capturedAt: .now.addingTimeInterval(-6 * 86_400), driftScore: 18, fixationStability: 0.88, speechStability: 0.91, heartRateVariability: 58, sleepHours: 7.6, memoryScore: 1, attentionScore: 0.91),
        .init(capturedAt: .now.addingTimeInterval(-5 * 86_400), driftScore: 16, fixationStability: 0.90, speechStability: 0.92, heartRateVariability: 61, sleepHours: 7.8, memoryScore: 1, attentionScore: 0.93),
        .init(capturedAt: .now.addingTimeInterval(-4 * 86_400), driftScore: 19, fixationStability: 0.85, speechStability: 0.90, heartRateVariability: 55, sleepHours: 7.1, memoryScore: 1, attentionScore: 0.89),
        .init(capturedAt: .now.addingTimeInterval(-3 * 86_400), driftScore: 17, fixationStability: 0.87, speechStability: 0.91, heartRateVariability: 57, sleepHours: 7.4, memoryScore: 1, attentionScore: 0.91),
        .init(capturedAt: .now.addingTimeInterval(-2 * 86_400), driftScore: 21, fixationStability: 0.79, speechStability: 0.88, heartRateVariability: 51, sleepHours: 6.8, memoryScore: 1, attentionScore: 0.85),
        .init(capturedAt: .now.addingTimeInterval(-86_400), driftScore: 20, fixationStability: 0.81, speechStability: 0.88, heartRateVariability: 52, sleepHours: 6.7, memoryScore: 1, attentionScore: 0.86),
        .init(
            capturedAt: .now,
            driftScore: 22,
            fixationStability: 0.74,
            pupilResponse: 0.18,
            pupilSymmetry: 0.91,
            pupilVariability: 0.08,
            gazeTrackingScore: 0.77,
            speechStability: 0.87,
            voiceActivityRatio: 0.72,
            noiseLevel: 0.11,
            heartRateVariability: 48,
            sleepHours: 6.4,
            memoryScore: 0,
            attentionScore: 0.82,
            phq2Score: 3
        )
    ]
}
