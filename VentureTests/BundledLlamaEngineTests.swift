import XCTest
@testable import Venture

final class BundledLlamaEngineTests: XCTestCase {
    func testBundledModelAssetIsPresent() throws {
        let url = try XCTUnwrap(BundledLlamaEngine.modelURL)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        let model = LocalCompanionModel.active
        XCTAssertGreaterThanOrEqual(size ?? 0, model.minimumBytes)
        XCTAssertTrue(url.lastPathComponent.contains(model.resourceName))
    }

    func testBundledModelAnswersGeneralKnowledge() async {
        let context = CompanionContext(
            snapshots: [],
            health: .empty,
            mentalHealth: .empty,
            screenTimeSelectionCount: 0,
            screenTimeProtectionActive: false,
            recentConversation: []
        )

        var updates: [String] = []
        for await update in BundledLlamaEngine.shared.streamResponse(
            to: "Who was the first person to walk on the Moon? Answer in one short sentence.",
            context: context
        ) {
            updates.append(update)
        }
        let response = updates.last ?? ""
        let normalized = response.lowercased()

        XCTAssertGreaterThan(updates.count, 1, "updates: \(updates)")
        XCTAssertTrue(
            normalized.contains("neil") || normalized.contains("armstrong"),
            "response: \(response)"
        )
        XCTAssertTrue(CompanionSafetyPolicy.accepts(response), "response: \(response)")
        XCTAssertTrue(BundledLlamaEngine.isReady)
    }

    func testPrepareExecutesModelBeforeReportingReady() async {
        await BundledLlamaEngine.shared.release()
        XCTAssertFalse(BundledLlamaEngine.isReady)

        let prepared = await BundledLlamaEngine.shared.prepare()

        XCTAssertTrue(prepared)
        XCTAssertTrue(BundledLlamaEngine.isReady)
    }
}
