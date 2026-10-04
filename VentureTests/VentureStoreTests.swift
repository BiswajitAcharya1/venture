import XCTest
@testable import Venture

@MainActor
final class VentureStoreTests: XCTestCase {
    func testSecurePayloadCodecCompressesAndRestoresStructuredData() {
        let source = Data(String(repeating: #"{"signal":42,"source":"measured"},"#, count: 300).utf8)

        let packed = SecurePayloadCodec.pack(source)

        XCTAssertLessThan(packed.count, source.count)
        XCTAssertEqual(SecurePayloadCodec.unpack(packed), source)
    }

    func testSecurePayloadCodecKeepsLegacyUncompressedDataReadable() {
        let legacy = Data(#"{"schemaVersion":4}"#.utf8)

        XCTAssertEqual(SecurePayloadCodec.unpack(legacy), legacy)
    }

    func testSystemRouteStoreConsumesEachShortcutRequestOnce() {
        let suiteName = "VentureStoreTests.system-route.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        VentureSystemRouteStore.request(.scan, defaults: defaults)
        XCTAssertEqual(VentureSystemRouteStore.consume(defaults: defaults), .scan)
        XCTAssertNil(VentureSystemRouteStore.consume(defaults: defaults))

        VentureSystemRouteStore.request(.assistant, defaults: defaults)
        XCTAssertEqual(VentureSystemRouteStore.consume(defaults: defaults), .assistant)
        XCTAssertNil(VentureSystemRouteStore.consume(defaults: defaults))
    }

    func testNewStoreContainsNoSampleMeasurements() {
        let store = VentureStore()

        XCTAssertTrue(store.snapshots.isEmpty)
        XCTAssertNil(store.driftScore)
        XCTAssertTrue(store.metricGroups.isEmpty)
    }

    func testDeletingSensorHistoryPreservesOtherMeasuredSignals() {
        let store = VentureStore()
        store.snapshots = CognitiveSnapshot.sampleHistory

        store.deleteEyeHistory()
        store.deleteVoiceHistory()

        XCTAssertTrue(store.snapshots.allSatisfy { $0.fixationStability == nil })
        XCTAssertTrue(store.snapshots.allSatisfy { $0.pupilResponse == nil })
        XCTAssertTrue(store.snapshots.allSatisfy { $0.pupilSymmetry == nil })
        XCTAssertTrue(store.snapshots.allSatisfy { $0.speechStability == nil })
        XCTAssertTrue(store.snapshots.allSatisfy { $0.voiceActivityRatio == nil })
        XCTAssertTrue(store.snapshots.allSatisfy { $0.noiseLevel == nil })
        XCTAssertEqual(store.snapshots.last?.memoryScore, 0)
    }

    func testClearAllScansReturnsToUnmeasuredState() {
        let store = VentureStore()
        store.snapshots = CognitiveSnapshot.sampleHistory
        store.driftScore = 22

        store.clearAllScans()

        XCTAssertTrue(store.snapshots.isEmpty)
        XCTAssertNil(store.driftScore)
        XCTAssertTrue(store.metricGroups.isEmpty)
    }

    func testBackendSyncBatchUsesLatestMeasuredSignals() {
        let store = VentureStore()
        store.completeScan(result: ScanResult(
            cameraAuthorized: true,
            microphoneAuthorized: true,
            eyeConfidence: 0.91,
            fixationStability: 0.72,
            blinkCount: 3,
            pupilResponse: 0.42,
            pupilSymmetry: 0.94,
            pupilVariability: 0.18,
            gazeTrackingScore: 0.81,
            speechStability: 0.66,
            voiceActivityRatio: 0.74,
            noiseLevel: 0.14,
            parkinsonsVoiceProbability: 37,
            parkinsonsVoiceQuality: 0.88,
            spontaneousWordCount: 96,
            spontaneousLexicalDiversity: 0.52,
            respiratoryWheezeLikelihood: nil,
            respiratoryRecordingQuality: nil,
            respiratoryBreathSeconds: nil,
            respiratoryAirflowIrregularity: nil,
            memoryScore: 0.7,
            attentionScore: 0.78,
            executiveFunctionScore: 0.69,
            phq2Score: 2
        ))

        let userID = UUID()
        let batch = store.makeBackendSyncBatch(
            userID: userID,
            appVersion: "test",
            deviceModel: "simulator"
        )

        XCTAssertEqual(batch?.scan.userID, userID)
        XCTAssertEqual(batch?.scan.appVersion, "test")
        XCTAssertNil(store.snapshots.last?.parkinsonsVoiceProbability)
        XCTAssertNil(store.snapshots.last?.parkinsonsVoiceQuality)
        XCTAssertFalse(batch?.metrics.contains { $0.name == "Voice research-model match" } == true)
        XCTAssertFalse(batch?.metrics.contains { $0.name == "Voice model sample quality" } == true)
        XCTAssertFalse(batch?.modelOutputs.contains { $0.modelID == "parkinson-voice-coreml" } == true)
        XCTAssertFalse(batch?.modelOutputs.contains { $0.modelID == "speech-language-dementia-index" } == true)
        XCTAssertNil(store.snapshots.last?.pupilResponse)
        XCTAssertFalse(batch?.metrics.contains { $0.domain == "eyes" } == true)
    }
    func testAcousticMeasurementsPersistAndVoiceDeletionClearsThem() throws {
        let acoustic = VoiceAcousticSummary(pitchHz: 180, pitchVariation: 0.05, amplitudeVariation: 0.08, voicedSeconds: 3, recordingQuality: 0.8, clippingRatio: 0)
        let snapshot = CognitiveSnapshot(capturedAt: .now, voiceAcousticSummary: acoustic)
        let restored = try JSONDecoder().decode(CognitiveSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(restored.voiceAcousticSummary, acoustic)
        let store = VentureStore()
        store.snapshots = [restored]
        store.deleteVoiceHistory()
        XCTAssertNil(store.snapshots.first?.voiceAcousticSummary)
    }

    func testOlderSnapshotsRemainReadableWithoutAcousticSummary() throws {
        let old = Data(#"{"capturedAt":0,"speechStability":0.7}"#.utf8)
        let snapshot = try JSONDecoder().decode(CognitiveSnapshot.self, from: old)
        XCTAssertNil(snapshot.voiceAcousticSummary)
        XCTAssertEqual(snapshot.speechStability, 0.7)
    }

}
