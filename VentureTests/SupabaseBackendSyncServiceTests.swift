import XCTest
@testable import Venture

final class SupabaseBackendSyncServiceTests: XCTestCase {
    func testScanInsertRequestUsesAuthenticatedSupabaseRESTEndpoint() throws {
        let service = SupabaseBackendSyncService(
            projectURL: try XCTUnwrap(URL(string: "https://example.supabase.co")),
            anonKey: "anon-key",
            accessToken: "access-token"
        )
        let userID = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let payload = SupabaseScanSessionPayload(
            userID: userID,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
            driftScore: 42,
            appVersion: "1.0",
            deviceModel: "iPhone"
        )

        let request = try service.makeInsertRequest(
            table: "scan_sessions",
            queryItems: [URLQueryItem(name: "select", value: "id")],
            prefer: "return=representation",
            payload: payload
        )

        XCTAssertEqual(request.url?.absoluteString, "https://example.supabase.co/rest/v1/scan_sessions?select=id")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "anon-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Prefer"), "return=representation")
        let body = try XCTUnwrap(request.httpBody).jsonObject()
        XCTAssertEqual(body["user_id"] as? String, userID.uuidString)
        XCTAssertEqual(body["drift_score"] as? Int, 42)
        XCTAssertEqual(body["app_version"] as? String, "1.0")
    }

    func testModelOutputPayloadEncodesRuntimeStateAndLikelihood() throws {
        let userID = try XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let payload = SupabaseModelOutputPayload(
            userID: userID,
            scanID: nil,
            modelID: "parkinson-voice-coreml",
            modelName: "Parkinson voice Core ML screen",
            runtime: .coreML,
            state: .bundledExecutable,
            outputType: .likelihood,
            label: "voice-model match",
            likelihoodPercent: 64,
            evidence: ["voiced seconds 3.4", "quality 88%"],
            action: "repeat advanced voice screen if this remains elevated"
        )

        let data = try JSONEncoder().encode(payload)
        let body = try data.jsonObject()

        XCTAssertEqual(body["model_id"] as? String, "parkinson-voice-coreml")
        XCTAssertEqual(body["runtime"] as? String, "Core ML")
        XCTAssertEqual(body["state"] as? String, "bundledExecutable")
        XCTAssertEqual(body["output_type"] as? String, "likelihood")
        XCTAssertEqual(body["likelihood_percent"] as? Int, 64)
        XCTAssertEqual(body["evidence"] as? [String], ["voiced seconds 3.4", "quality 88%"])
    }

    func testProfileUpsertUsesAuthenticatedSupabaseRESTEndpoint() throws {
        let service = SupabaseBackendSyncService(
            projectURL: try XCTUnwrap(URL(string: "https://example.supabase.co")),
            anonKey: "anon-key",
            accessToken: "access-token"
        )
        let userID = try XCTUnwrap(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let payload = SupabaseProfilePayload(
            userID: userID,
            email: "person@example.com",
            displayName: "Person",
            termsVersion: LegalConsent.currentTermsVersion,
            acceptedTermsAt: nil,
            acceptedPrivacyAt: nil
        )

        let request = try service.makeUpsertRequest(
            table: "profiles",
            conflictTarget: "user_id",
            payload: payload
        )

        XCTAssertEqual(request.url?.absoluteString, "https://example.supabase.co/rest/v1/profiles?on_conflict=user_id")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "anon-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Prefer"), "resolution=merge-duplicates,return=minimal")
        let body = try XCTUnwrap(request.httpBody).jsonObject()
        XCTAssertEqual(body["user_id"] as? String, userID.uuidString)
        XCTAssertEqual(body["email"] as? String, "person@example.com")
        XCTAssertEqual(body["display_name"] as? String, "Person")
        XCTAssertEqual(body["terms_version"] as? String, LegalConsent.currentTermsVersion)
    }

    func testModelArtifactAuditPayloadEncodesAndUpsertsByUserAndModel() throws {
        let service = SupabaseBackendSyncService(
            projectURL: try XCTUnwrap(URL(string: "https://example.supabase.co")),
            anonKey: "anon-key",
            accessToken: "access-token"
        )
        let userID = try XCTUnwrap(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
        let payload = SupabaseModelArtifactAuditPayload(
            userID: userID,
            modelID: "local-companion-lfm2-5",
            modelName: "LFM2.5 230M Instruct",
            runtime: .llamaCPP,
            declaredState: .bundledExecutable,
            status: .installed,
            executable: true,
            sourcePath: "Venture/Resources/Models/LocalLLM/lfm2_5_230m_q4_k_m.gguf",
            capability: "local companion responses",
            evidence: "artifact is present",
            action: "run execution test",
            auditedAt: Date(timeIntervalSince1970: 1_800_000_222)
        )

        let request = try service.makeUpsertRequest(
            table: "model_artifact_audits",
            conflictTarget: "user_id,model_id",
            payload: [payload]
        )

        XCTAssertEqual(request.url?.absoluteString, "https://example.supabase.co/rest/v1/model_artifact_audits?on_conflict=user_id,model_id")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Prefer"), "resolution=merge-duplicates,return=minimal")
        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [[String: Any]])
        let body = try XCTUnwrap(array.first)
        XCTAssertEqual(body["user_id"] as? String, userID.uuidString)
        XCTAssertEqual(body["model_id"] as? String, "local-companion-lfm2-5")
        XCTAssertEqual(body["runtime"] as? String, "llama.cpp")
        XCTAssertEqual(body["declared_state"] as? String, "bundledExecutable")
        XCTAssertEqual(body["status"] as? String, "installed")
        XCTAssertEqual(body["executable"] as? Bool, true)
    }
}

private extension Data {
    func jsonObject() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: self) as? [String: Any])
    }
}
