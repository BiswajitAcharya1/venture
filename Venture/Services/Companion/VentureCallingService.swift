import AVFoundation
import Combine
import Foundation
import Speech

enum VentureCallExperiment: String, CaseIterable, Identifiable, Sendable {
    case clinic = "clinic-receptionist"
    case nova = "nova-dear-care"
    case rural = "rural-health-ai"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .clinic: "ai clinic receptionist"
        case .nova: "nova dear care"
        case .rural: "rural health ai"
        }
    }
    var detail: String {
        switch self {
        case .clinic: "claude · appointment conversation"
        case .nova: "amazon nova · care conversation"
        case .rural: "english rules adaptation · no tflite inference"
        }
    }
}

struct VentureCallMessage: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    let role: String
    let content: String
    enum CodingKeys: String, CodingKey { case role, content }
}

struct VentureCallProviderStatus: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let model: String
    let kind: String
    let configured: Bool
    let detail: String
}

struct VentureCallReply: Decodable, Sendable {
    let provider: String
    let text: String
    let model: String
    let kind: String
    let latency_ms: Int
}

struct VentureCallRequest: Encodable {
    let provider: String
    let messages: [VentureCallMessage]
    let language: String
    let context: String
}

struct VenturePhoneCall: Decodable, Sendable {
    let provider: String
    let call_sid: String
    let status: String
}

struct VenturePhoneRequest: Encodable {
    let provider: String
    let to_number: String
    let language: String
    let context: String
    let goal: String
    let opted_in: Bool
    let request_id: String
}

enum VentureCallContext {
    static func summary(snapshot sample: CognitiveSnapshot?) -> String {
        guard let sample else { return "no completed scan measurements are available. vital signs and symptoms are not supplied." }
        var lines = ["scan captured: \(sample.capturedAt.formatted(date: .abbreviated, time: .shortened))."]
        if let activity = sample.voiceActivityRatio { lines.append("detected voice activity: \(Int(activity * 100))%.") }
        if let stability = sample.speechStability { lines.append("speech timing stability: \(Int(stability * 100))%.") }
        if let pupil = sample.pupilResponse { lines.append("relative pupil response: \(String(format: "%.3f", pupil)).") }
        lines.append("these are extracted screening measurements, not a diagnosis. vital signs and symptoms are not supplied.")
        return lines.joined(separator: " ")
    }

    static func context(snapshot: CognitiveSnapshot?, optedIn: Bool, hospital: String?) -> String {
        var value = optedIn ? summary(snapshot: snapshot) : ""
        if let hospital, !hospital.isEmpty { value += "\nuser-selected hospital: \(hospital). appointment availability and booking are unknown." }
        return value
    }
}

enum VentureCallError: LocalizedError {
    case configuration, service(String), invalidResponse
    var errorDescription: String? {
        switch self {
        case .configuration: "enter an https service URL and its test token."
        case .service(let message): message
        case .invalidResponse: "the service returned an invalid response."
        }
    }
}

private final class VentureCallNetworkDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor final class VentureCallingService: ObservableObject {
    @Published private(set) var statuses: [VentureCallProviderStatus] = []
    @Published private(set) var checking = false
    @Published private(set) var error: String?
    @Published private(set) var results: [String: String] = [:]
    @Published private(set) var connected = false
    @Published private(set) var phoneConfigured = false
    @Published private(set) var phoneDetail = "connect the calling service to check phone availability."
    @Published private(set) var phoneCalls: [String: VenturePhoneCall] = [:]
    @Published private(set) var phoneRequests: [String: VenturePhoneRequest] = [:]
    @Published private(set) var dialingProviders: Set<String> = []
    private struct PhoneConnection { let url: URL; let token: String }
    private var phoneConnections: [String: PhoneConnection] = [:]
    private var baseURL: URL?
    // Session-only. Vendor API credentials always stay on the service.
    private var token = ""
    private var generation = UUID()
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 70
        config.timeoutIntervalForResource = 75
        session = URLSession(configuration: config, delegate: VentureCallNetworkDelegate(), delegateQueue: nil)
    }

    static func validatedURL(_ value: String) -> URL? {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return nil }
        if url.scheme == "https" { return url }
        #if DEBUG
        // An explicit localhost development service only; production always requires TLS.
        if url.scheme == "http", ["localhost", "127.0.0.1", "::1"].contains(host) { return url }
        #endif
        return nil
    }

    static func normalizedPhoneNumber(_ value: String) -> String? {
        guard value.allSatisfy({ "+0123456789 ()-.".contains($0) }) else { return nil }
        let cleaned = value.filter { "+0123456789".contains($0) }
        guard cleaned.range(of: "^\\+[1-9][0-9]{7,14}$", options: .regularExpression) != nil else { return nil }
        return cleaned
    }

    func connect(url: String, token: String) async {
        guard !checking else { return }
        generation = UUID()
        let attempt = generation
        connected = false; statuses = []; results = [:]; error = nil
        guard let endpoint = Self.validatedURL(url), token.count >= 24 else {
            error = VentureCallError.configuration.localizedDescription; return
        }
        self.baseURL = endpoint; self.token = token; checking = true
        defer { if generation == attempt { checking = false } }
        do {
            struct Telephony: Decodable { let configured: Bool; let detail: String }
            struct List: Decodable { let providers: [VentureCallProviderStatus]; let telephony: Telephony? }
            let response: List = try await request(path: "providers", body: Optional<Data>.none)
            guard generation == attempt else { return }
            statuses = response.providers; connected = true
            phoneConfigured = response.telephony?.configured == true
            phoneDetail = response.telephony?.detail ?? "this service does not have Twilio configured."
        } catch {
            guard generation == attempt else { return }
            self.error = error.localizedDescription
        }
    }

    func disconnect() {
        generation = UUID(); baseURL = nil; token = ""
        statuses = []; results = [:]; connected = false; checking = false; error = nil
        phoneConfigured = false; phoneDetail = "connect the calling service to check phone availability."
        session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
    }

    func respond(experiment: VentureCallExperiment, messages: [VentureCallMessage], language: String, context: String) async throws -> VentureCallReply {
        guard connected else { throw VentureCallError.configuration }
        let attempt = generation
        do {
            let payload = VentureCallRequest(provider: experiment.id, messages: Array(messages.suffix(19)), language: language, context: context)
            let reply: VentureCallReply = try await request(path: "v1/respond", body: JSONEncoder().encode(payload))
            try Task.checkCancellation()
            guard generation == attempt, reply.provider == experiment.id, !reply.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VentureCallError.invalidResponse
            }
            results[experiment.id] = "response received · \(reply.latency_ms) ms"
            return reply
        } catch {
            if generation == attempt, !Task.isCancelled { results[experiment.id] = "test failed" }
            throw error
        }
    }

    func dial(_ payload: VenturePhoneRequest) async throws -> VenturePhoneCall {
        guard payload.opted_in, !dialingProviders.contains(payload.provider) else { throw VentureCallError.service("a call is already being started.") }
        if let existing = phoneCalls[payload.provider] { return existing }
        let frozen: VenturePhoneRequest
        if let previous = phoneRequests[payload.provider] { frozen = previous }
        else {
            guard Self.normalizedPhoneNumber(payload.to_number) == payload.to_number else {
                throw VentureCallError.service("enter the clinic's international number beginning with + and its country code.")
            }
            guard !payload.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, payload.goal.count <= 1000 else {
                throw VentureCallError.service("keep the appointment goal between 1 and 1,000 characters.")
            }
            guard connected, phoneConfigured, let baseURL else { throw VentureCallError.service("enable the automated call option and configure Twilio first.") }
            frozen = payload
            phoneRequests[payload.provider] = payload
            phoneConnections[payload.provider] = PhoneConnection(url: baseURL, token: token)
        }
        dialingProviders.insert(payload.provider)
        defer { dialingProviders.remove(payload.provider) }
        let result: VenturePhoneCall = try await request(path: "v1/calls", body: JSONEncoder().encode(frozen), connection: phoneConnections[payload.provider])
        guard result.provider == payload.provider else { throw VentureCallError.invalidResponse }
        phoneCalls[payload.provider] = result
        return result
    }

    func phoneStatus(_ sid: String) async throws -> VenturePhoneCall {
        guard let provider = phoneCalls.first(where: { $0.value.call_sid == sid })?.key else { throw VentureCallError.invalidResponse }
        let result: VenturePhoneCall = try await request(path: "v1/calls/\(sid)", body: Optional<Data>.none, connection: phoneConnections[provider])
        phoneCalls[provider] = result
        return result
    }

    func endCall(_ sid: String) async throws -> VenturePhoneCall {
        guard let provider = phoneCalls.first(where: { $0.value.call_sid == sid })?.key else { throw VentureCallError.invalidResponse }
        let result: VenturePhoneCall = try await request(path: "v1/calls/\(sid)", body: Optional<Data>.none, method: "DELETE", connection: phoneConnections[provider])
        phoneCalls[provider] = result
        return result
    }

    func checkPhoneAttempt(_ experiment: VentureCallExperiment) async throws {
        guard let attempt = phoneRequests[experiment.id] else { return }
        let result: VenturePhoneCall = try await request(path: "v1/call-attempts/\(attempt.request_id)", body: Optional<Data>.none, connection: phoneConnections[experiment.id])
        guard result.provider == experiment.id else { throw VentureCallError.invalidResponse }
        phoneCalls[experiment.id] = result
    }

    func clearFinishedCall(_ experiment: VentureCallExperiment) {
        guard let call = phoneCalls[experiment.id], ["completed", "canceled", "failed", "busy", "no-answer"].contains(call.status) else { return }
        phoneCalls.removeValue(forKey: experiment.id); phoneRequests.removeValue(forKey: experiment.id)
        phoneConnections.removeValue(forKey: experiment.id)
    }

    private struct ServiceFailure: Decodable {
        let detail: String
    }

    private func request<T: Decodable>(path: String, body: Data?, method: String? = nil, connection: PhoneConnection? = nil) async throws -> T {
        guard let endpoint = connection?.url ?? baseURL else { throw VentureCallError.configuration }
        let authorization = connection?.token ?? token
        guard !authorization.isEmpty else { throw VentureCallError.configuration }
        var request = URLRequest(url: endpoint.appendingPathComponent(path))
        request.httpMethod = method ?? (body == nil ? "GET" : "POST")
        request.httpBody = body
        request.setValue("Bearer \(authorization)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw VentureCallError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONDecoder().decode(ServiceFailure.self, from: data))?.detail
            throw VentureCallError.service(detail ?? "the calling service could not complete this test (\(http.statusCode)).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

@MainActor final class VentureCallVoiceInput: ObservableObject {
    @Published private(set) var recording = false
    @Published private(set) var transcript = ""
    @Published private(set) var error: String?
    private let engine = AVAudioEngine()
    private var recognition: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var tapped = false
    private var generation = UUID()

    func start(language: String) async {
        stop(); error = nil; transcript = ""
        let attempt = generation
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard generation == attempt, !Task.isCancelled else { return }
        let microphone = await SensorAuthorizationService().requestMicrophoneAccess()
        guard generation == attempt, !Task.isCancelled else { return }
        guard speech, microphone else { error = "allow microphone and speech access in iOS settings, or type your message."; return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            error = "on-device transcription is unavailable for this language. type your message."; return
        }
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try audioSession.setActive(true)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw VentureCallError.service("the microphone is unavailable.") }
            let bufferRequest = SFSpeechAudioBufferRecognitionRequest()
            bufferRequest.shouldReportPartialResults = true
            bufferRequest.requiresOnDeviceRecognition = true
            request = bufferRequest
            recognition = recognizer.recognitionTask(with: bufferRequest) { [weak self] result, failure in
                let words = result?.bestTranscription.formattedString
                let finished = result?.isFinal == true
                let failed = failure != nil
                Task { @MainActor in
                    guard let self, self.generation == attempt else { return }
                    if let words { self.transcript = words }
                    if failed || finished {
                        self.stop()
                        if failed { self.error = "transcription stopped. review the text or try again." }
                    }
                }
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in bufferRequest.append(buffer) }
            tapped = true
            engine.prepare(); try engine.start(); recording = true
        } catch { stop(); self.error = error.localizedDescription }
    }

    func stop() {
        generation = UUID()
        if engine.isRunning { engine.stop() }
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        request?.endAudio(); recognition?.cancel(); request = nil; recognition = nil; recording = false
    }
}
