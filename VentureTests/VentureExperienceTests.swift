import XCTest
import AVFoundation
import KokoroCoreML
@testable import Venture

final class VentureExperienceTests: XCTestCase {
    func testAll27LanguagesHaveEveryAuthoredString() {
        XCTAssertEqual(VentureLanguage.all.count, 27)
        XCTAssertEqual(Set(VentureLanguage.all.map(\.id)).count, 27)
        for language in VentureLanguage.all {
            XCTAssertEqual(language.words.count, VentureCopy.allCases.count)
            for key in VentureCopy.allCases { XCTAssertFalse(language.text(key).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(language.id): \(key)") }
        }
    }
    func testHindiIncludesTranslatedTestAndNavigation() {
        let hindi = VentureLanguage.all.first { $0.id == "hi" }!
        XCTAssertEqual(hindi.text(.settings), "सेटिंग्स")
        XCTAssertEqual(hindi.text(.ahh), "5 सेकंड आह कहें")
    }
    func testRightToLeftLanguages() {
        XCTAssertEqual(Set(VentureLanguage.all.filter(\.isRTL).map(\.id)), Set(["ar", "ur"]))
    }
    func testUnvalidatedProbabilityCannotBeShownEvenBelowCap() {
        XCTAssertFalse(VentureClinicalOutputPolicy.allows("84%"))
        XCTAssertFalse(VentureClinicalOutputPolicy.allows("12٪"))
        XCTAssertFalse(VentureClinicalOutputPolicy.allows("92％"))
        XCTAssertTrue(VentureClinicalOutputPolicy.allows("Measurements are not a diagnosis."))
    }
    @MainActor func testNewVoiceAndCareGuidanceHasEveryAuthoredString() {
        for language in ["en", "hi", "es"] {
            for key in VentureSupportCopy.allCases {
                XCTAssertFalse(VentureSupportCopy.text(key, language: language).isEmpty, "\(language): \(key)")
            }
        }
    }
    func testSharedVoiceSummarySuppressesLegacyEyeAndDiseaseScores() {
        let sample = CognitiveSnapshot(capturedAt: .now, pupilResponse: 0.42, parkinsonsVoiceProbability: 0.9,
            voiceAcousticSummary: VoiceAcousticSummary(pitchHz: 188, pitchVariation: 0.08, amplitudeVariation: 0.13,
                voicedSeconds: 4.7, recordingQuality: 0.84, clippingRatio: 0.001))
        let summary = VentureVoiceEvidenceSummary.text(snapshot: sample)
        XCTAssertTrue(summary.contains("188 Hz"))
        XCTAssertFalse(summary.contains("pupil"))
        XCTAssertFalse(summary.contains("90%"))
        XCTAssertTrue(summary.contains("no alzheimer's, parkinson's or dementia result was calculated"))
    }
    func testSharedVoiceSummarySuppressesPoorRecordingFeatures() {
        let sample = CognitiveSnapshot(capturedAt: .now,
            voiceAcousticSummary: VoiceAcousticSummary(pitchHz: 188, pitchVariation: 0.08, amplitudeVariation: 0.13,
                voicedSeconds: 0.5, recordingQuality: 0.2, clippingRatio: 0.001))
        let summary = VentureVoiceEvidenceSummary.text(snapshot: sample)
        XCTAssertFalse(summary.contains("188 Hz"))
        XCTAssertTrue(summary.contains("too low"))
    }
    func testBundledHumanExampleIsFiveSeconds() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "ahh-example", withExtension: "wav"))
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(Double(file.length) / file.processingFormat.sampleRate, 5, accuracy: 0.02)
    }
    func testKokoroActuallySynthesizesFiniteAudio() async throws {
        let directory = try XCTUnwrap(Bundle.main.url(forResource: "KokoroModels", withExtension: nil))
        let result = try await Task.detached {
            let engine = try KokoroEngine(modelDirectory: directory, forceCPU: true)
            return try engine.synthesize(ipa: "hˈɛloʊ", voice: "af_heart")
        }.value
        XCTAssertGreaterThan(result.samples.count, 1000)
        XCTAssertTrue(result.samples.allSatisfy(\.isFinite))
        XCTAssertGreaterThan(result.samples.map(abs).max() ?? 0, 0.001)
    }
    @MainActor func testGuestSessionDoesNotExposeExistingHistory() async {
        let store = VentureStore()
        store.snapshots = [CognitiveSnapshot(capturedAt: .now, pupilResponse: 0.12)]
        await store.beginSession(userID: nil)
        XCTAssertTrue(store.isGuestSession)
        XCTAssertTrue(store.snapshots.isEmpty)
        XCTAssertNil(store.driftScore)
        XCTAssertFalse(store.scanCompletedToday)
    }
}
