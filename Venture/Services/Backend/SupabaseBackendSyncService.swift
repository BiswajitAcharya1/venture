import Foundation

struct SupabaseScanSessionPayload: Encodable, Equatable {
    var userID: UUID
    var capturedAt: Date
    var driftScore: Int?
    var appVersion: String?
    var deviceModel: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case capturedAt = "captured_at"
        case driftScore = "drift_score"
        case appVersion = "app_version"
        case deviceModel = "device_model"
    }
}

struct SupabaseProfilePayload: Encodable, Equatable {
    var userID: UUID
    var email: String
    var displayName: String
    var termsVersion: String
    var acceptedTermsAt: Date?
    var acceptedPrivacyAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case email
        case displayName = "display_name"
        case termsVersion = "terms_version"
        case acceptedTermsAt = "accepted_terms_at"
        case acceptedPrivacyAt = "accepted_privacy_at"
    }
}

struct SupabaseSignalMetricPayload: Encodable, Equatable {
    var userID: UUID
    var scanID: UUID?
    var domain: String
    var name: String
    var value: Double
    var unit: String
    var baseline: Double?
    var inverse: Bool
    var evidence: [String]
    var measuredAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case scanID = "scan_id"
        case domain
        case name
        case value
        case unit
        case baseline
        case inverse
        case evidence
        case measuredAt = "measured_at"
    }
}

struct SupabaseModelOutputPayload: Encodable, Equatable {
    enum OutputType: String, Encodable, Equatable {
        case likelihood
        case classification
        case quality
        case summary
        case unavailable
    }

    var userID: UUID
    var scanID: UUID?
    var modelID: String
    var modelName: String
    var runtime: RuntimeModelArtifact.Runtime
    var state: RuntimeModelArtifact.State
    var outputType: OutputType
    var label: String
    var likelihoodPercent: Double?
    var evidence: [String]
    var action: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case scanID = "scan_id"
        case modelID = "model_id"
        case modelName = "model_name"
        case runtime
        case state
        case outputType = "output_type"
        case label
        case likelihoodPercent = "likelihood_percent"
        case evidence
        case action
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encodeIfPresent(scanID, forKey: .scanID)
        try container.encode(modelID, forKey: .modelID)
        try container.encode(modelName, forKey: .modelName)
        try container.encode(runtime.rawValue, forKey: .runtime)
        try container.encode(state.rawValue, forKey: .state)
        try container.encode(outputType.rawValue, forKey: .outputType)
        try container.encode(label, forKey: .label)
        try container.encodeIfPresent(likelihoodPercent, forKey: .likelihoodPercent)
        try container.encode(evidence, forKey: .evidence)
        try container.encodeIfPresent(action, forKey: .action)
    }
}

struct SupabaseAuditEventPayload: Encodable, Equatable {
    var userID: UUID
    var eventType: String
    var metadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case eventType = "event_type"
        case metadata
    }
}

struct SupabaseModelArtifactAuditPayload: Encodable, Equatable {
    var userID: UUID
    var modelID: String
    var modelName: String
    var runtime: RuntimeModelArtifact.Runtime
    var declaredState: RuntimeModelArtifact.State
    var status: RuntimeModelArtifactAudit.Status
    var executable: Bool
    var sourcePath: String?
    var capability: String
    var evidence: String
    var action: String
    var auditedAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case modelID = "model_id"
        case modelName = "model_name"
        case runtime
        case declaredState = "declared_state"
        case status
        case executable
        case sourcePath = "source_path"
        case capability
        case evidence
        case action
        case auditedAt = "audited_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(modelID, forKey: .modelID)
        try container.encode(modelName, forKey: .modelName)
        try container.encode(runtime.rawValue, forKey: .runtime)
        try container.encode(declaredState.rawValue, forKey: .declaredState)
        try container.encode(status.rawValue, forKey: .status)
        try container.encode(executable, forKey: .executable)
        try container.encodeIfPresent(sourcePath, forKey: .sourcePath)
        try container.encode(capability, forKey: .capability)
        try container.encode(evidence, forKey: .evidence)
        try container.encode(action, forKey: .action)
        try container.encode(auditedAt, forKey: .auditedAt)
    }
}

struct SupabaseModelSyncBatch: Equatable {
    var profile: SupabaseProfilePayload?
    var scan: SupabaseScanSessionPayload
    var metrics: [SupabaseSignalMetricPayload]
    var modelOutputs: [SupabaseModelOutputPayload]
    var modelArtifactAudits: [SupabaseModelArtifactAuditPayload]
    var auditEvents: [SupabaseAuditEventPayload]
}

enum SupabaseBackendSyncError: LocalizedError, Equatable {
    case invalidProjectURL
    case invalidResponse
    case missingInsertedScanID
    case httpFailure(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidProjectURL:
            "Supabase project URL is invalid."
        case .invalidResponse:
            "Supabase returned an invalid response."
        case .missingInsertedScanID:
            "Supabase did not return the inserted scan id."
        case .httpFailure(let statusCode, let message):
            "Supabase request failed with \(statusCode): \(message)"
        }
    }
}

final class SupabaseBackendSyncService {
    private struct InsertedScanSession: Decodable {
        let id: UUID
    }

    private let projectURL: URL
    private let anonKey: String
    private let accessToken: String
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(projectURL: URL, anonKey: String, accessToken: String, session: URLSession = .shared) {
        self.projectURL = projectURL
        self.anonKey = anonKey
        self.accessToken = accessToken
        self.session = session
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func sync(_ batch: SupabaseModelSyncBatch) async throws {
        if let profile = batch.profile {
            try await send(makeUpsertRequest(
                table: "profiles",
                conflictTarget: "user_id",
                payload: profile
            ))
        }

        let scanRequest = try makeInsertRequest(
            table: "scan_sessions",
            queryItems: [URLQueryItem(name: "select", value: "id")],
            prefer: "return=representation",
            payload: batch.scan
        )
        let scanData = try await send(scanRequest)
        let inserted = try decoder.decode([InsertedScanSession].self, from: scanData)
        guard let scanID = inserted.first?.id else {
            throw SupabaseBackendSyncError.missingInsertedScanID
        }

        let metrics = batch.metrics.map { metric -> SupabaseSignalMetricPayload in
            var value = metric
            value.scanID = scanID
            return value
        }
        if !metrics.isEmpty {
            try await send(makeInsertRequest(table: "signal_metrics", payload: metrics))
        }

        let modelOutputs = batch.modelOutputs.map { output -> SupabaseModelOutputPayload in
            var value = output
            value.scanID = scanID
            return value
        }
        if !modelOutputs.isEmpty {
            try await send(makeInsertRequest(table: "model_outputs", payload: modelOutputs))
        }

        if !batch.modelArtifactAudits.isEmpty {
            try await send(makeUpsertRequest(
                table: "model_artifact_audits",
                conflictTarget: "user_id,model_id",
                payload: batch.modelArtifactAudits
            ))
        }

        if !batch.auditEvents.isEmpty {
            try await send(makeInsertRequest(table: "audit_events", payload: batch.auditEvents))
        }
    }

    func makeInsertRequest<T: Encodable>(
        table: String,
        queryItems: [URLQueryItem] = [],
        prefer: String = "return=minimal",
        payload: T
    ) throws -> URLRequest {
        var components = URLComponents(url: projectURL.appendingPathComponent("rest/v1/\(table)"), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else {
            throw SupabaseBackendSyncError.invalidProjectURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(prefer, forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(payload)
        return request
    }

    func makeUpsertRequest<T: Encodable>(
        table: String,
        conflictTarget: String,
        payload: T
    ) throws -> URLRequest {
        try makeInsertRequest(
            table: table,
            queryItems: [URLQueryItem(name: "on_conflict", value: conflictTarget)],
            prefer: "resolution=merge-duplicates,return=minimal",
            payload: payload
        )
    }

    @discardableResult
    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseBackendSyncError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "no response body"
            throw SupabaseBackendSyncError.httpFailure(statusCode: http.statusCode, message: message)
        }
        return data
    }
}
