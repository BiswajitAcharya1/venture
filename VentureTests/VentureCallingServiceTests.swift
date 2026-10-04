import Foundation
import XCTest
@testable import Venture

@MainActor final class VentureCallingServiceTests: XCTestCase {
    func testExperimentsHaveDistinctStableBackendIDs() {
        XCTAssertEqual(VentureCallExperiment.allCases.map(\.id), [
            "clinic-receptionist", "nova-dear-care", "rural-health-ai"
        ])
        XCTAssertEqual(Set(VentureCallExperiment.allCases.map(\.id)).count, 3)
        XCTAssertTrue(VentureCallExperiment.allCases.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty })
    }

    func testServiceURLsRequireTLSAndRejectEmbeddedCredentialsOrQueryData() {
        XCTAssertEqual(VentureCallingService.validatedURL(" https://calls.example.test/api ")?.absoluteString,
                       "https://calls.example.test/api")
        XCTAssertNotNil(VentureCallingService.validatedURL("https://192.0.2.5:8443/calls"))
        for value in [
            "http://calls.example.test", "http://192.168.1.4:8000", "http://localhost.example.test:8000",
            "https://user:secret@calls.example.test", "https://user@calls.example.test",
            "https://calls.example.test?token=private", "https://calls.example.test?",
            "https://calls.example.test#private", "file:///tmp/calls", "javascript:alert(1)", ""
        ] {
            XCTAssertNil(VentureCallingService.validatedURL(value), value)
        }
        #if DEBUG
        XCTAssertNotNil(VentureCallingService.validatedURL("http://localhost:8000"))
        XCTAssertNotNil(VentureCallingService.validatedURL("http://127.0.0.1:8000"))
        XCTAssertNotNil(VentureCallingService.validatedURL("http://[::1]:8000"))
        #else
        XCTAssertNil(VentureCallingService.validatedURL("http://localhost:8000"))
        XCTAssertNil(VentureCallingService.validatedURL("http://127.0.0.1:8000"))
        XCTAssertNil(VentureCallingService.validatedURL("http://[::1]:8000"))
        #endif
    }

    func testWireMessagesExcludeLocalIdentifiers() throws {
        let first = VentureCallMessage(role: "user", content: "help me prepare an appointment request")
        let second = VentureCallMessage(role: "assistant", content: "which care team?")
        XCTAssertNotEqual(first.id, second.id)
        let data = try JSONEncoder().encode([first, second])
        let wire = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: String]])
        XCTAssertEqual(wire, [
            ["role": "user", "content": first.content],
            ["role": "assistant", "content": second.content]
        ])
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(first.id.uuidString))
        let roundTrip = try JSONDecoder().decode([VentureCallMessage].self, from: data)
        XCTAssertEqual(roundTrip.map(\.content), [first.content, second.content])
        XCTAssertNotEqual(roundTrip[0].id, first.id)
    }

    func testSummaryIncludesOnlyAvailableExtractedMeasurements() {
        let sample = CognitiveSnapshot(
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            pupilResponse: 0.125, speechStability: 0.8, voiceActivityRatio: 0.5
        )
        let summary = VentureCallContext.summary(snapshot: sample)
        XCTAssertTrue(summary.contains("detected voice activity: 50%"))
        XCTAssertTrue(summary.contains("speech timing stability: 80%"))
        XCTAssertTrue(summary.contains("relative pupil response: 0.125"))
        XCTAssertTrue(summary.contains("not a diagnosis"))
        XCTAssertTrue(summary.contains("vital signs and symptoms are not supplied"))
        XCTAssertFalse(summary.contains("heart rate:"))
        XCTAssertFalse(summary.contains("blood pressure:"))
    }

    func testEncodedRequestContainsSelectedProviderAndNoLocalUUID() throws {
        let message = VentureCallMessage(role: "user", content: "please help prepare a care call")
        let payload = VentureCallRequest(
            provider: VentureCallExperiment.nova.id, messages: [message], language: "en", context: ""
        )
        let data = try JSONEncoder().encode(payload)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["provider", "messages", "language", "context"])
        XCTAssertEqual(object["provider"] as? String, "nova-dear-care")
        XCTAssertEqual(object["context"] as? String, "")
        let wireMessages = try XCTUnwrap(object["messages"] as? [[String: String]])
        XCTAssertEqual(wireMessages, [["role": "user", "content": message.content]])
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(message.id.uuidString))
    }

    func testMissingScanAndOptOutNeverProduceMeasuredValues() {
        let missing = VentureCallContext.summary(snapshot: nil)
        XCTAssertTrue(missing.contains("no completed scan measurements"))
        XCTAssertFalse(missing.contains("%"))
        let emptyScan = VentureCallContext.summary(snapshot: CognitiveSnapshot(capturedAt: .now))
        XCTAssertFalse(emptyScan.contains("detected voice activity:"))
        XCTAssertFalse(emptyScan.contains("speech timing stability:"))
        XCTAssertFalse(emptyScan.contains("relative pupil response:"))
        let sample = CognitiveSnapshot(capturedAt: .now, voiceActivityRatio: 0.64)
        XCTAssertEqual(VentureCallContext.context(snapshot: sample, optedIn: false, hospital: nil), "")
        let hospitalOnly = VentureCallContext.context(snapshot: sample, optedIn: false, hospital: "Selected clinic")
        XCTAssertTrue(hospitalOnly.contains("user-selected hospital: Selected clinic"))
        XCTAssertTrue(hospitalOnly.contains("availability and booking are unknown"))
        XCTAssertFalse(hospitalOnly.contains("64%"))
    }

    func testSummaryReflectsTheCurrentSnapshot() {
        let first = CognitiveSnapshot(capturedAt: .now, voiceActivityRatio: 0.64)
        let second = CognitiveSnapshot(capturedAt: .now, voiceActivityRatio: 0.27)
        let firstSummary = VentureCallContext.context(snapshot: first, optedIn: true, hospital: nil)
        let secondSummary = VentureCallContext.context(snapshot: second, optedIn: true, hospital: nil)
        XCTAssertTrue(firstSummary.contains("64%"))
        XCTAssertFalse(firstSummary.contains("27%"))
        XCTAssertTrue(secondSummary.contains("27%"))
        XCTAssertFalse(secondSummary.contains("64%"))
        XCTAssertNotEqual(firstSummary, secondSummary)
    }

    func testPhoneRequestKeepsConsentAndRetryIdentifierExplicit() throws {
        let request = VenturePhoneRequest(
            provider: "clinic-receptionist", to_number: "+15555550123", language: "en", context: "",
            goal: "ask about a routine appointment", opted_in: false, request_id: "same-attempt"
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(object["opted_in"] as? Bool, false)
        XCTAssertEqual(object["request_id"] as? String, "same-attempt")
        XCTAssertEqual(object["context"] as? String, "")
        XCTAssertEqual(object["provider"] as? String, "clinic-receptionist")
    }

    func testUnconnectedServiceCannotGenerateAResponse() async {
        let service = VentureCallingService()
        XCTAssertFalse(service.connected)
        XCTAssertTrue(service.statuses.isEmpty)
        XCTAssertTrue(service.results.isEmpty)
        do {
            _ = try await service.respond(
                experiment: .clinic, messages: [VentureCallMessage(role: "user", content: "hello")],
                language: "en", context: ""
            )
            XCTFail("an unconfigured service must not pretend to have a reply")
        } catch let error as VentureCallError {
            guard case .configuration = error else { return XCTFail("unexpected calling error: \(error)") }
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertTrue(service.results.isEmpty)
    }

    func testInvalidURLIsRejectedBeforeConnection() async {
        let service = VentureCallingService()
        await service.connect(url: "http://public.example.test", token: String(repeating: "x", count: 32))
        XCTAssertFalse(service.connected)
        XCTAssertFalse(service.checking)
        XCTAssertTrue(service.statuses.isEmpty)
        XCTAssertNotNil(service.error)
        service.disconnect()
        XCTAssertNil(service.error)
        XCTAssertTrue(service.results.isEmpty)
    }
}
