import XCTest
@testable import Venture

final class ModelRuntimeManifestTests: XCTestCase {
    func testBundledExecutableManifestMatchesRepositoryArtifacts() throws {
        let root = repositoryRoot
        for artifact in ModelRuntimeManifest.bundledExecutable {
            let sourcePath = try XCTUnwrap(artifact.sourcePath)
            let url = root.appendingPathComponent(sourcePath)
            var isDirectory: ObjCBool = false
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                "\(artifact.displayName) is marked bundled but \(sourcePath) is missing"
            )
        }
    }

    func testRuntimeAuditReportsBundledRepositoryArtifactsAsInstalled() throws {
        let root = repositoryRoot
        let audits = ModelRuntimeManifest.audit(repositoryRoot: root)
        let bundled = audits.filter { $0.artifact.state == .bundledExecutable }

        XCTAssertFalse(bundled.isEmpty)
        XCTAssertTrue(bundled.allSatisfy { $0.status == .installed }, bundled.map { "\($0.artifact.id): \($0.status.rawValue)" }.joined(separator: ", "))
        XCTAssertTrue(bundled.allSatisfy(\.isExecutable))
    }

    func testRuntimeAuditKeepsUnavailableResearchUnavailable() {
        let audits = ModelRuntimeManifest.audit(repositoryRoot: URL(fileURLWithPath: "/tmp/does-not-exist"))
        let unavailable = audits.filter { $0.artifact.state == .unavailable }

        XCTAssertFalse(unavailable.isEmpty)
        XCTAssertTrue(unavailable.allSatisfy { $0.status == .unavailable && !$0.isExecutable })
    }

    func testQuickExecutionHealthCheckIncludesRunnableModelIDs() async {
        let checks = await ModelExecutionHealthCheck.runQuickChecks(includeLLMPrepare: false)
        let ids = Set(checks.map(\.modelID))

        XCTAssertTrue(ids.contains("parkinson-voice-coreml"))
        XCTAssertTrue(ids.contains("voice-acoustic-measurements"))
        XCTAssertEqual(checks.first { $0.modelID == "parkinson-voice-coreml" }?.status, .skipped)
        XCTAssertFalse(checks.contains { $0.modelID == "alzheimer-composite-screen" && $0.status == .passed })
        XCTAssertTrue(ids.contains("silero-vad-coreml"))
        XCTAssertTrue(ids.contains("local-companion-lfm2-5"))
        XCTAssertTrue(ids.contains("attention-switch-screen"))
        XCTAssertTrue(ids.contains("phq2-depression-followup"))
        XCTAssertTrue(ids.contains("single-to-twelve-ecg"))
        XCTAssertTrue(ids.contains("ecg-reconstructed-cardiac-screen"))
        XCTAssertTrue(checks.allSatisfy { !$0.evidence.isEmpty })
    }

    func testRuntimeManifestNamesActualLocalLLMArtifact() throws {
        let localCompanion = try XCTUnwrap(ModelRuntimeManifest.bundledExecutable.first { $0.id == "local-companion-lfm2-5" })

        XCTAssertEqual(localCompanion.displayName, "LFM2.5 230M Instruct")
        XCTAssertEqual(localCompanion.runtime, .llamaCPP)
        XCTAssertEqual(localCompanion.sourcePath, "Venture/Resources/Models/LocalLLM/lfm2_5_230m_q4_k_m.gguf")
        XCTAssertFalse(ModelRuntimeManifest.bundledExecutable.contains { $0.displayName.localizedCaseInsensitiveContains("qwen") })
        XCTAssertFalse(ModelRuntimeManifest.bundledExecutable.contains { $0.displayName.localizedCaseInsensitiveContains("tinyllama") })
    }

    func testUnavailableResearchModelsDoNotPretendToBeBundled() {
        let unavailable = Set(ModelRuntimeManifest.unavailableExternalResearch.map(\.id))

        XCTAssertTrue(unavailable.contains("wavbert"))
        XCTAssertTrue(unavailable.contains("parkinson-voice-coreml"))
        XCTAssertTrue(unavailable.contains("alzheimer-composite-screen"))
        XCTAssertTrue(unavailable.contains("hubert-ecg"))
        XCTAssertTrue(unavailable.contains("external-ecg-recon-coreml"))
        XCTAssertTrue(unavailable.contains("external-ecg-mi-risk"))
        XCTAssertTrue(unavailable.contains("bp-ppg"))
        XCTAssertTrue(ModelRuntimeManifest.unavailableExternalResearch.allSatisfy { $0.state == .unavailable && $0.sourcePath == nil })
    }

    func testNativeECGReconstructionScreensAreSourceBound() throws {
        let reconstruction = try XCTUnwrap(ModelRuntimeManifest.sourceBound.first { $0.id == "single-to-twelve-ecg" })
        let screening = try XCTUnwrap(ModelRuntimeManifest.sourceBound.first { $0.id == "ecg-reconstructed-cardiac-screen" })

        XCTAssertEqual(reconstruction.runtime, .appNative)
        XCTAssertEqual(screening.runtime, .appNative)
        XCTAssertEqual(reconstruction.state, .sourceBound)
        XCTAssertEqual(screening.state, .sourceBound)
    }

    func testMeasuredSignalForecastIsSourceBound() throws {
        let forecast = try XCTUnwrap(ModelRuntimeManifest.sourceBound.first { $0.id == "venture-progression-forecast" })

        XCTAssertEqual(forecast.displayName, "venture measured-signal forecast")
        XCTAssertEqual(forecast.runtime, .appNative)
        XCTAssertEqual(forecast.state, .sourceBound)
        XCTAssertNil(forecast.sourcePath)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
