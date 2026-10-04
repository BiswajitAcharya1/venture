import CryptoKit
import Foundation
import Security

struct AuthSession: Codable, Sendable, Equatable {
    let userID: String
    let email: String
    let displayName: String
    let emailVerified: Bool
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
}

struct SignUpOutcome: Sendable, Equatable {
    let email: String
    let requiresEmailVerification: Bool
    let debugVerificationCode: String?
}

struct PendingPasswordResetContext: Codable, Sendable, Equatable {
    let email: String
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= .now.addingTimeInterval(30)
    }
}

struct LegalConsent: Codable, Sendable, Equatable {
    static let currentTermsVersion = "2026-06-20"
    static let currentPrivacyVersion = "2026-06-20"

    let acceptedAt: Date
    let termsVersion: String
    let privacyVersion: String

    static func current(acceptedAt: Date = .now) -> LegalConsent {
        LegalConsent(
            acceptedAt: acceptedAt,
            termsVersion: currentTermsVersion,
            privacyVersion: currentPrivacyVersion
        )
    }
}

enum AccountAuthError: LocalizedError, Equatable {
    case invalidEmail
    case weakPassword
    case emailRejected(String)
    case accountExists
    case accountNotFound
    case wrongPassword
    case emailNotVerified
    case invalidVerificationCode
    case tooManyAttempts(seconds: Int)
    case backendNotConfigured
    case networkUnavailable
    case serverRejected(String)
    case secureStorageUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            "Use a complete email address."
        case .weakPassword:
            "Use a stronger password."
        case .emailRejected(let reason):
            reason
        case .accountExists:
            "An account already exists for this email."
        case .accountNotFound:
            "No account was found for this email."
        case .wrongPassword:
            "The password did not match."
        case .emailNotVerified:
            "Verify your email before continuing."
        case .invalidVerificationCode:
            "The verification code did not match."
        case .tooManyAttempts(let seconds):
            "Too many sign-in attempts. Try again in \(seconds) seconds."
        case .backendNotConfigured:
            "Production account sync needs a HTTPS auth backend."
        case .networkUnavailable:
            "The account service could not be reached."
        case .serverRejected(let message):
            message
        case .secureStorageUnavailable:
            "The session could not be stored securely."
        }
    }
}

enum AuthDeepLinkNoticeStore {
    private static let key = "com.venture.auth.deep-link-notice"

    static func save(_ message: String, defaults: UserDefaults = .standard) {
        defaults.set(message, forKey: key)
    }

    static func consume(defaults: UserDefaults = .standard) -> String? {
        let value = defaults.string(forKey: key)
        defaults.removeObject(forKey: key)
        return value
    }
}

private extension AccountAuthError {
    var countsAgainstSignInLimit: Bool {
        switch self {
        case .wrongPassword, .accountNotFound, .emailNotVerified:
            true
        case .invalidEmail,
             .weakPassword,
             .emailRejected,
             .accountExists,
             .invalidVerificationCode,
             .tooManyAttempts,
             .backendNotConfigured,
             .networkUnavailable,
             .serverRejected,
             .secureStorageUnavailable:
            false
        }
    }
}

actor AccountAuthService {
    private let credentials: LocalCredentialVault
    private let sessionStore: AuthSessionStore
    private let pendingPasswordResetStore: PendingPasswordResetStore
    private let backend: (any AccountBackendClient)?
    private let emailVerifier: EmailDeliverabilityClient?
    private let allowsLocalDevelopmentFallback: Bool
    private var signInLimiter: SignInRateLimiter

    init(
        credentials: LocalCredentialVault = LocalCredentialVault(),
        sessionStore: AuthSessionStore = AuthSessionStore(),
        pendingPasswordResetStore: PendingPasswordResetStore = PendingPasswordResetStore(),
        configuration: AccountBackendConfiguration = .fromBundle,
        backendClient: (any AccountBackendClient)? = nil,
        signInLimiter: SignInRateLimiter = SignInRateLimiter()
    ) {
        self.credentials = credentials
        self.sessionStore = sessionStore
        self.pendingPasswordResetStore = pendingPasswordResetStore
        self.signInLimiter = signInLimiter
        if let backendClient {
            backend = backendClient
        } else if let supabase = configuration.supabase {
            backend = SupabaseAccountClient(
                projectURL: supabase.projectURL,
                anonKey: supabase.anonKey
            )
        } else {
            backend = configuration.authBaseURL.map { RemoteAccountClient(baseURL: $0) }
        }
        allowsLocalDevelopmentFallback = configuration.allowsLocalDevelopmentFallback
        emailVerifier = configuration.emailVerifierBaseURL.map {
            EmailDeliverabilityClient(baseURL: $0, provider: configuration.emailVerifierProvider)
        }
    }

    var usesProductionBackend: Bool { backend != nil }

    func signUp(name: String, email rawEmail: String, password: String, consent: LegalConsent = .current()) async throws -> SignUpOutcome {
        let email = try validate(email: rawEmail)
        guard PasswordStrength(password: password).isAcceptable else { throw AccountAuthError.weakPassword }
        if let report = try await emailVerifier?.check(email: email) {
            try report.requireAcceptable()
        }

        if let backend {
            return try await backend.signUp(name: name.trimmingCharacters(in: .whitespacesAndNewlines), email: email, password: password, consent: consent)
        }
        guard allowsLocalDevelopmentFallback else { throw AccountAuthError.backendNotConfigured }

        do {
            guard !credentials.containsAccount(email: email) else { throw AccountAuthError.accountExists }
            try credentials.create(name: name, email: email, password: password, consent: consent)
            return SignUpOutcome(email: email, requiresEmailVerification: false, debugVerificationCode: nil)
        } catch let error as AccountAuthError {
            throw error
        } catch {
            throw AccountAuthError.secureStorageUnavailable
        }
    }

    func verifyEmail(email rawEmail: String, code: String) async throws -> AuthSession {
        let email = try validate(email: rawEmail)
        if let backend {
            let session = try await backend.verifyEmail(email: email, code: code)
            try sessionStore.save(session)
            return session
        }
        guard allowsLocalDevelopmentFallback else { throw AccountAuthError.backendNotConfigured }

        do {
            guard let session = try credentials.verifyEmail(email: email, code: code) else {
                throw AccountAuthError.invalidVerificationCode
            }
            try sessionStore.save(session)
            return session
        } catch CredentialError.accountNotFound {
            throw AccountAuthError.accountNotFound
        } catch CredentialError.invalidVerificationCode {
            throw AccountAuthError.invalidVerificationCode
        }
    }

    func resendVerification(email rawEmail: String) async throws -> String? {
        let email = try validate(email: rawEmail)
        if let backend {
            try await backend.resendVerification(email: email)
            return nil
        }
        guard allowsLocalDevelopmentFallback else { throw AccountAuthError.backendNotConfigured }
        do {
            return try credentials.rotateVerificationCode(email: email)
        } catch CredentialError.accountNotFound {
            throw AccountAuthError.accountNotFound
        } catch {
            throw AccountAuthError.secureStorageUnavailable
        }
    }

    func requestPasswordReset(email rawEmail: String) async throws -> String? {
        let email = try validate(email: rawEmail)
        if let backend {
            try await backend.requestPasswordReset(email: email)
            return nil
        }
        guard allowsLocalDevelopmentFallback else { throw AccountAuthError.backendNotConfigured }
        do {
            return try credentials.beginPasswordReset(email: email)
        } catch CredentialError.accountNotFound {
            throw AccountAuthError.accountNotFound
        } catch {
            throw AccountAuthError.secureStorageUnavailable
        }
    }

    func resetPassword(email rawEmail: String, code: String, newPassword: String) async throws {
        let email = try validate(email: rawEmail)
        guard PasswordStrength(password: newPassword).isAcceptable else { throw AccountAuthError.weakPassword }
        if let backend {
            try await backend.resetPassword(email: email, code: code, newPassword: newPassword)
            sessionStore.delete()
            return
        }
        guard allowsLocalDevelopmentFallback else { throw AccountAuthError.backendNotConfigured }
        do {
            try credentials.reset(email: email, password: newPassword, verificationCode: code)
            sessionStore.delete()
        } catch CredentialError.accountNotFound {
            throw AccountAuthError.accountNotFound
        } catch CredentialError.invalidVerificationCode {
            throw AccountAuthError.invalidVerificationCode
        } catch {
            throw AccountAuthError.secureStorageUnavailable
        }
    }

    func resetPasswordWithRecoveryLink(newPassword: String) async throws {
        guard PasswordStrength(password: newPassword).isAcceptable else { throw AccountAuthError.weakPassword }
        guard let backend else { throw AccountAuthError.backendNotConfigured }
        guard let context = pendingPasswordResetStore.load(), !context.isExpired else {
            pendingPasswordResetStore.delete()
            throw AccountAuthError.invalidVerificationCode
        }
        try await backend.updatePassword(accessToken: context.accessToken, newPassword: newPassword)
        pendingPasswordResetStore.delete()
        sessionStore.delete()
    }

    func handlePasswordRecoveryURL(_ url: URL) async throws -> Bool {
        if try storePasswordRecoveryLink(url) {
            return true
        }
        if let errorMessage = SupabasePasswordRecoveryLinkParser.parseRecoveryError(url) {
            throw AccountAuthError.serverRejected(errorMessage)
        }
        guard let tokenHash = SupabasePasswordRecoveryLinkParser.parseTokenHash(url) else {
            return false
        }
        guard let backend else { throw AccountAuthError.backendNotConfigured }
        let session = try await backend.verifyPasswordRecoveryTokenHash(tokenHash: tokenHash)
        try pendingPasswordResetStore.save(PendingPasswordResetContext(
            email: session.email,
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            expiresAt: session.expiresAt
        ))
        return true
    }

    func storePasswordRecoveryLink(_ url: URL) throws -> Bool {
        guard let context = SupabasePasswordRecoveryLinkParser.parse(url) else { return false }
        try pendingPasswordResetStore.save(context)
        return true
    }

    func pendingPasswordResetContext() -> PendingPasswordResetContext? {
        guard let context = pendingPasswordResetStore.load(), !context.isExpired else {
            pendingPasswordResetStore.delete()
            return nil
        }
        return context
    }

    func clearPendingPasswordResetContext() {
        pendingPasswordResetStore.delete()
    }

    func signIn(email rawEmail: String, password: String) async throws -> AuthSession {
        let email = try validate(email: rawEmail)
        try signInLimiter.requireAllowed(identifier: email)

        do {
            if let backend {
                let session = try await backend.signIn(email: email, password: password)
                guard session.emailVerified else { throw AccountAuthError.emailNotVerified }
                try sessionStore.save(session)
                signInLimiter.recordSuccess(identifier: email)
                return session
            }
            guard allowsLocalDevelopmentFallback else { throw AccountAuthError.backendNotConfigured }

            guard let result = credentials.verifyForSignIn(email: email, password: password) else {
                if credentials.containsAccount(email: email) { throw AccountAuthError.wrongPassword }
                throw AccountAuthError.accountNotFound
            }
            guard result.emailVerified else { throw AccountAuthError.emailNotVerified }
            let session = result.session
            try sessionStore.save(session)
            signInLimiter.recordSuccess(identifier: email)
            return session
        } catch let error as AccountAuthError {
            if error.countsAgainstSignInLimit {
                signInLimiter.recordFailure(identifier: email)
            }
            throw error
        }
    }

    func clearSession() {
        sessionStore.delete()
    }

    func currentSession() -> AuthSession? {
        sessionStore.load()
    }

    func refreshSessionIfNeeded() async throws -> AuthSession? {
        guard let current = sessionStore.load() else { return nil }
        guard let expiry = current.expiresAt, expiry <= .now.addingTimeInterval(300) else {
            return current
        }
        guard let refreshToken = current.refreshToken, let backend else {
            sessionStore.delete()
            return nil
        }
        do {
            let refreshed = try await backend.refreshSession(refreshToken: refreshToken)
            try sessionStore.save(refreshed)
            return refreshed
        } catch {
            sessionStore.delete()
            throw error
        }
    }

    func deleteCurrentAccount() async throws {
        if let backend {
            guard var session = sessionStore.load() else { throw AccountAuthError.accountNotFound }
            if let expiry = session.expiresAt, expiry <= .now {
                guard let refreshToken = session.refreshToken else {
                    sessionStore.delete()
                    throw AccountAuthError.accountNotFound
                }
                session = try await backend.refreshSession(refreshToken: refreshToken)
                try sessionStore.save(session)
            }
            try await backend.deleteAccount(accessToken: session.accessToken)
        } else {
            guard allowsLocalDevelopmentFallback else { throw AccountAuthError.backendNotConfigured }
            credentials.deleteAccount()
        }
        sessionStore.delete()
    }

    private func validate(email rawEmail: String) throws -> String {
        let email = EmailAddressValidator.normalized(rawEmail)
        guard EmailAddressValidator.isValid(email) else { throw AccountAuthError.invalidEmail }
        return email
    }
}

struct AccountBackendConfiguration: Sendable {
    struct Supabase: Sendable {
        let projectURL: URL
        let anonKey: String
    }

    let authBaseURL: URL?
    let emailVerifierBaseURL: URL?
    let emailVerifierProvider: EmailVerifierProvider
    let allowsLocalDevelopmentFallback: Bool
    let supabase: Supabase?

    init(
        authBaseURL: URL?,
        emailVerifierBaseURL: URL?,
        emailVerifierProvider: EmailVerifierProvider,
        allowsLocalDevelopmentFallback: Bool = true,
        supabase: Supabase? = nil
    ) {
        self.authBaseURL = authBaseURL
        self.emailVerifierBaseURL = emailVerifierBaseURL
        self.emailVerifierProvider = emailVerifierProvider
        self.allowsLocalDevelopmentFallback = allowsLocalDevelopmentFallback
        self.supabase = supabase
    }

    static var fromBundle: AccountBackendConfiguration {
        let bundle = Bundle.main
#if DEBUG
        // Keep Supabase wiring in the codebase, but use local auth in debug so
        // simulator testing never depends on the network account service.
        let supabase: Supabase? = nil
#else
        let supabase = supabaseConfiguration(bundle: bundle)
#endif
        return AccountBackendConfiguration(
            authBaseURL: urlValue("VentureAuthBaseURL", bundle: bundle),
            emailVerifierBaseURL: urlValue("VentureEmailVerifierBaseURL", bundle: bundle),
            emailVerifierProvider: EmailVerifierProvider(
                rawValue: (bundle.object(forInfoDictionaryKey: "VentureEmailVerifierProvider") as? String)?.lowercased() ?? ""
            ) ?? .reacher,
            allowsLocalDevelopmentFallback: localDevelopmentFallbackEnabled,
            supabase: supabase
        )
    }

    var supportsAccountFlow: Bool {
        supabase != nil || authBaseURL != nil || allowsLocalDevelopmentFallback
    }

    var requiresAuthenticatedSession: Bool {
        supabase != nil || authBaseURL != nil
    }

    var checksEmailDeliverability: Bool {
        emailVerifierBaseURL != nil
    }

    private static var localDevelopmentFallbackEnabled: Bool {
#if DEBUG
        true
#else
        false
#endif
    }

    private static func urlValue(_ key: String, bundle: Bundle) -> URL? {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String,
              value.hasPrefix("https://"),
              let url = URL(string: value)
        else { return nil }
        return url
    }

    private static func supabaseConfiguration(bundle: Bundle) -> Supabase? {
        guard
            let projectURL = urlValue("VentureSupabaseURL", bundle: bundle),
            let anonKey = bundle.object(forInfoDictionaryKey: "VentureSupabaseAnonKey") as? String,
            !anonKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !anonKey.contains("$(")
        else { return nil }
        return Supabase(projectURL: projectURL, anonKey: anonKey)
    }
}

enum EmailAddressValidator {
    static func normalized(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isValid(_ email: String) -> Bool {
        guard email.count <= 254,
              let at = email.firstIndex(of: "@"),
              at != email.startIndex,
              email[email.index(after: at)...].contains("."),
              !email.hasSuffix("."),
              !email.contains("..")
        else { return false }
        return true
    }
}

struct SignInRateLimitPolicy: Sendable, Equatable {
    let freeFailures: Int
    let baseLockout: TimeInterval
    let maximumLockout: TimeInterval

    static let production = SignInRateLimitPolicy(
        freeFailures: 5,
        baseLockout: 30,
        maximumLockout: 15 * 60
    )
}

struct SignInRateLimiter {
    private struct Record {
        var failures: Int = 0
        var lockedUntil: Date?
    }

    private var records: [String: Record] = [:]
    private let policy: SignInRateLimitPolicy
    private let now: @Sendable () -> Date

    init(
        policy: SignInRateLimitPolicy = .production,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.policy = policy
        self.now = now
    }

    mutating func requireAllowed(identifier: String) throws {
        let key = normalized(identifier)
        guard let lockedUntil = records[key]?.lockedUntil else { return }
        let remaining = lockedUntil.timeIntervalSince(now())
        if remaining > 0 {
            throw AccountAuthError.tooManyAttempts(seconds: max(1, Int(ceil(remaining))))
        }
        records[key]?.lockedUntil = nil
    }

    mutating func recordFailure(identifier: String) {
        let key = normalized(identifier)
        var record = records[key] ?? Record()
        record.failures += 1
        if record.failures >= policy.freeFailures {
            let lockoutStep = record.failures - policy.freeFailures
            let multiplier = pow(2.0, Double(min(lockoutStep, 6)))
            let duration = min(policy.maximumLockout, policy.baseLockout * multiplier)
            record.lockedUntil = now().addingTimeInterval(duration)
        }
        records[key] = record
    }

    mutating func recordSuccess(identifier: String) {
        records.removeValue(forKey: normalized(identifier))
    }

    private func normalized(_ identifier: String) -> String {
        identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum EmailVerifierProvider: String, Sendable {
    case reacher
    case afterShip = "aftership"
}

struct EmailDeliverabilityReport: Sendable, Equatable {
    enum Reachability: String, Sendable {
        case safe
        case risky
        case invalid
        case unknown
    }

    let reachability: Reachability
    let syntaxValid: Bool
    let acceptsMail: Bool?
    let disposable: Bool?
    let suggestion: String?

    func requireAcceptable() throws {
        guard syntaxValid else { throw AccountAuthError.emailRejected("That email address is not syntactically valid.") }
        if disposable == true { throw AccountAuthError.emailRejected("Use a non-disposable email address for your venture account.") }
        if acceptsMail == false { throw AccountAuthError.emailRejected("That domain does not appear to accept email.") }
        if reachability == .invalid { throw AccountAuthError.emailRejected("That mailbox could not be verified. Check the address and try again.") }
    }
}

struct EmailDeliverabilityClient: Sendable {
    let baseURL: URL
    let provider: EmailVerifierProvider
    var session: URLSession = SecureNetworkSession.make()

    func check(email: String) async throws -> EmailDeliverabilityReport {
        switch provider {
        case .reacher:
            var request = URLRequest(url: baseURL.appending(path: "v1/check_email"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["to_email": email])
            let data = try await data(for: request)
            return try ReacherEmailCheck.decode(data)
        case .afterShip:
            let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? email
            let data = try await data(for: URLRequest(url: baseURL.appending(path: "v1/\(encoded)/verification")))
            return try AfterShipEmailCheck.decode(data)
        }
    }

    private func data(for request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw AccountAuthError.networkUnavailable
            }
            return data
        } catch let error as AccountAuthError {
            throw error
        } catch {
            throw AccountAuthError.networkUnavailable
        }
    }
}

private struct ReacherEmailCheck: Decodable {
    struct Syntax: Decodable { let isValidSyntax: Bool; let suggestion: String? }
    struct MX: Decodable { let acceptsMail: Bool? }
    struct Misc: Decodable { let isDisposable: Bool? }

    let isReachable: String
    let syntax: Syntax
    let mx: MX?
    let misc: Misc?

    enum CodingKeys: String, CodingKey {
        case isReachable = "is_reachable"
        case syntax, mx, misc
    }

    static func decode(_ data: Data) throws -> EmailDeliverabilityReport {
        let value = try JSONDecoder.reacher.decode(Self.self, from: data)
        return EmailDeliverabilityReport(
            reachability: EmailDeliverabilityReport.Reachability(rawValue: value.isReachable) ?? .unknown,
            syntaxValid: value.syntax.isValidSyntax,
            acceptsMail: value.mx?.acceptsMail,
            disposable: value.misc?.isDisposable,
            suggestion: value.syntax.suggestion
        )
    }
}

private struct AfterShipEmailCheck: Decodable {
    struct Syntax: Decodable { let valid: Bool; let suggestion: String? }

    let reachable: String?
    let syntax: Syntax
    let hasMXRecords: Bool?
    let disposable: Bool?

    enum CodingKeys: String, CodingKey {
        case reachable, syntax, disposable
        case hasMXRecords = "has_mx_records"
    }

    static func decode(_ data: Data) throws -> EmailDeliverabilityReport {
        let value = try JSONDecoder.reacher.decode(Self.self, from: data)
        return EmailDeliverabilityReport(
            reachability: EmailDeliverabilityReport.Reachability(rawValue: value.reachable ?? "unknown") ?? .unknown,
            syntaxValid: value.syntax.valid,
            acceptsMail: value.hasMXRecords,
            disposable: value.disposable,
            suggestion: value.syntax.suggestion
        )
    }
}

private extension JSONDecoder {
    static var reacher: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    static var supabase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

private extension JSONEncoder {
    static var supabase: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

protocol AccountBackendClient: Sendable {
    func signUp(name: String, email: String, password: String, consent: LegalConsent) async throws -> SignUpOutcome
    func verifyEmail(email: String, code: String) async throws -> AuthSession
    func resendVerification(email: String) async throws
    func requestPasswordReset(email: String) async throws
    func resetPassword(email: String, code: String, newPassword: String) async throws
    func updatePassword(accessToken: String, newPassword: String) async throws
    func verifyPasswordRecoveryTokenHash(tokenHash: String) async throws -> AuthSession
    func signIn(email: String, password: String) async throws -> AuthSession
    func refreshSession(refreshToken: String) async throws -> AuthSession
    func deleteAccount(accessToken: String) async throws
}

struct RemoteAccountClient: AccountBackendClient {
    let baseURL: URL
    var session: URLSession = SecureNetworkSession.make()

    func signUp(name: String, email: String, password: String, consent: LegalConsent) async throws -> SignUpOutcome {
        let request = try request(path: "v1/auth/signup", body: SignUpRequest(name: name, email: email, password: password, consent: consent))
        let response: SignUpResponse = try await send(request)
        return SignUpOutcome(email: response.email, requiresEmailVerification: response.requiresEmailVerification, debugVerificationCode: nil)
    }

    func verifyEmail(email: String, code: String) async throws -> AuthSession {
        let request = try request(path: "v1/auth/verify-email", body: VerifyEmailRequest(email: email, code: code))
        return try await send(request)
    }

    func resendVerification(email: String) async throws {
        let request = try request(path: "v1/auth/resend-verification", body: EmailRequest(email: email))
        let _: EmptyResponse = try await send(request)
    }

    func requestPasswordReset(email: String) async throws {
        let request = try request(path: "v1/auth/password-reset/request", body: EmailRequest(email: email))
        let _: EmptyResponse = try await send(request)
    }

    func resetPassword(email: String, code: String, newPassword: String) async throws {
        let request = try request(path: "v1/auth/password-reset/confirm", body: ResetPasswordRequest(email: email, code: code, newPassword: newPassword))
        let _: EmptyResponse = try await send(request)
    }

    func updatePassword(accessToken: String, newPassword: String) async throws {
        throw AccountAuthError.serverRejected("Recovery links are only supported by the Supabase backend.")
    }

    func verifyPasswordRecoveryTokenHash(tokenHash: String) async throws -> AuthSession {
        throw AccountAuthError.serverRejected("Recovery token links are only supported by the Supabase backend.")
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        let request = try request(path: "v1/auth/signin", body: SignInRequest(email: email, password: password))
        return try await send(request)
    }

    func refreshSession(refreshToken: String) async throws -> AuthSession {
        let request = try request(path: "v1/auth/refresh", body: RefreshSessionRequest(refreshToken: refreshToken))
        return try await send(request)
    }

    func deleteAccount(accessToken: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "v1/auth/account"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AccountAuthError.networkUnavailable
            }
            guard (200..<300).contains(http.statusCode) else {
                throw AccountAuthError.serverRejected("The account service could not delete this account.")
            }
        } catch let error as AccountAuthError {
            throw error
        } catch {
            throw AccountAuthError.networkUnavailable
        }
    }

    private func request<Body: Encodable>(path: String, body: Body) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AccountAuthError.networkUnavailable }
            if (200..<300).contains(http.statusCode) {
                return try JSONDecoder().decode(Response.self, from: data)
            }
            if let error = try? JSONDecoder().decode(ServerErrorResponse.self, from: data), !error.message.isEmpty {
                throw AccountAuthError.serverRejected(error.message)
            }
            throw AccountAuthError.networkUnavailable
        } catch let error as AccountAuthError {
            throw error
        } catch {
            throw AccountAuthError.networkUnavailable
        }
    }
}

struct SupabaseAccountClient: AccountBackendClient {
    let projectURL: URL
    let anonKey: String
    var session: URLSession = SecureNetworkSession.make()

    func signUp(name: String, email: String, password: String, consent: LegalConsent) async throws -> SignUpOutcome {
        let body = SupabaseSignUpRequest(
            email: email,
            password: password,
            data: .init(
                displayName: name,
                termsVersion: consent.termsVersion,
                privacyVersion: consent.privacyVersion,
                legalAcceptedAt: consent.acceptedAt
            )
        )
        let response: SupabaseAuthEnvelope = try await send(path: "auth/v1/signup", body: body)
        return SignUpOutcome(
            email: response.resolvedUser?.email ?? email,
            requiresEmailVerification: response.resolvedSession == nil || response.resolvedUser?.emailConfirmedAt == nil,
            debugVerificationCode: nil
        )
    }

    func verifyEmail(email: String, code: String) async throws -> AuthSession {
        let response: SupabaseAuthEnvelope = try await send(
            path: "auth/v1/verify",
            body: SupabaseVerifyRequest(email: email, token: code, type: "signup")
        )
        return try response.makeSession(fallbackEmail: email)
    }

    func resendVerification(email: String) async throws {
        let _: SupabaseEmptyResponse = try await send(
            path: "auth/v1/resend",
            body: SupabaseResendRequest(email: email, type: "signup")
        )
    }

    func requestPasswordReset(email: String) async throws {
        let _: SupabaseEmptyResponse = try await send(
            path: "auth/v1/recover",
            queryItems: [URLQueryItem(name: "redirect_to", value: "venture://auth/reset")],
            body: SupabaseEmailRequest(email: email)
        )
    }

    func resetPassword(email: String, code: String, newPassword: String) async throws {
        let verification: SupabaseAuthEnvelope = try await send(
            path: "auth/v1/verify",
            body: SupabaseVerifyRequest(email: email, token: code, type: "recovery")
        )
        let recoverySession = try verification.makeSession(fallbackEmail: email)
        let _: SupabaseUser = try await send(
            path: "auth/v1/user",
            method: "PUT",
            body: SupabasePasswordUpdateRequest(password: newPassword),
            accessToken: recoverySession.accessToken
        )
    }

    func verifyPasswordRecoveryTokenHash(tokenHash: String) async throws -> AuthSession {
        let verification: SupabaseAuthEnvelope = try await send(
            path: "auth/v1/verify",
            body: SupabaseVerifyRequest(tokenHash: tokenHash, type: "recovery")
        )
        return try verification.makeSession()
    }

    func updatePassword(accessToken: String, newPassword: String) async throws {
        let _: SupabaseUser = try await send(
            path: "auth/v1/user",
            method: "PUT",
            body: SupabasePasswordUpdateRequest(password: newPassword),
            accessToken: accessToken
        )
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        let response: SupabaseAuthEnvelope = try await send(
            path: "auth/v1/token",
            queryItems: [URLQueryItem(name: "grant_type", value: "password")],
            body: SupabasePasswordGrantRequest(email: email, password: password)
        )
        return try response.makeSession(fallbackEmail: email)
    }

    func refreshSession(refreshToken: String) async throws -> AuthSession {
        let response: SupabaseAuthEnvelope = try await send(
            path: "auth/v1/token",
            queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            body: SupabaseRefreshRequest(refreshToken: refreshToken)
        )
        return try response.makeSession()
    }

    func deleteAccount(accessToken: String) async throws {
        let _: SupabaseEmptyResponse = try await send(
            path: "functions/v1/delete-account",
            method: "POST",
            body: SupabaseEmptyRequest(),
            accessToken: accessToken
        )
    }

    private func send<Request: Encodable, Response: Decodable>(
        path: String,
        method: String = "POST",
        queryItems: [URLQueryItem] = [],
        body: Request,
        accessToken: String? = nil
    ) async throws -> Response {
        var components = URLComponents(
            url: projectURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else { throw AccountAuthError.backendNotConfigured }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken ?? anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder.supabase.encode(body)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AccountAuthError.networkUnavailable
            }
            guard (200..<300).contains(http.statusCode) else {
                throw mapSupabaseError(data: data, statusCode: http.statusCode)
            }
            if data.isEmpty, let empty = SupabaseEmptyResponse() as? Response {
                return empty
            }
            return try JSONDecoder.supabase.decode(Response.self, from: data)
        } catch let error as AccountAuthError {
            throw error
        } catch {
            throw AccountAuthError.networkUnavailable
        }
    }

    private func mapSupabaseError(data: Data, statusCode: Int) -> AccountAuthError {
        let payload = try? JSONDecoder.supabase.decode(SupabaseErrorResponse.self, from: data)
        let code = [
            payload?.code,
            payload?.errorCode,
            payload?.error
        ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        let message = payload?.message
            ?? payload?.msg
            ?? payload?.errorDescription
            ?? payload?.error
            ?? "The account service rejected this request."
        let normalizedMessage = message.lowercased()
        if code.contains("email_not_confirmed") || normalizedMessage.contains("email not confirmed") {
            return .emailNotVerified
        }
        if code.contains("invalid_credentials")
            || code.contains("invalid_grant")
            || normalizedMessage.contains("invalid login credentials") {
            return .wrongPassword
        }
        if code.contains("otp_expired")
            || code.contains("invalid_otp")
            || normalizedMessage.contains("token has expired")
            || normalizedMessage.contains("invalid otp") {
            return .invalidVerificationCode
        }
        if code.contains("user_already_exists") || normalizedMessage.contains("already registered") {
            return .accountExists
        }
        if code.contains("user_not_found") || statusCode == 404 { return .accountNotFound }
        if statusCode == 429 { return .tooManyAttempts(seconds: 60) }
        return .serverRejected(message)
    }
}

enum SecureNetworkSession {
    static func make() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        return URLSession(
            configuration: configuration,
            delegate: HTTPSRedirectPolicy(),
            delegateQueue: nil
        )
    }

    static func allowsRedirect(from originalURL: URL?, to destinationURL: URL?) -> Bool {
        guard
            destinationURL?.scheme?.lowercased() == "https",
            destinationURL?.host?.lowercased() == originalURL?.host?.lowercased()
        else { return false }
        return true
    }
}

private final class HTTPSRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard SecureNetworkSession.allowsRedirect(
            from: task.originalRequest?.url,
            to: request.url
        ) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

private struct SignUpRequest: Encodable { let name: String; let email: String; let password: String; let consent: LegalConsent }
private struct VerifyEmailRequest: Encodable { let email: String; let code: String }
private struct SignInRequest: Encodable { let email: String; let password: String }
private struct ResetPasswordRequest: Encodable { let email: String; let code: String; let newPassword: String }
private struct RefreshSessionRequest: Encodable { let refreshToken: String }
private struct EmailRequest: Encodable { let email: String }
private struct EmptyResponse: Decodable {}
private struct ServerErrorResponse: Decodable { let message: String }
private struct SignUpResponse: Decodable {
    let email: String
    let requiresEmailVerification: Bool
}

private struct SupabaseSignUpRequest: Encodable {
    struct Metadata: Encodable {
        let displayName: String
        let termsVersion: String
        let privacyVersion: String
        let legalAcceptedAt: Date
    }

    let email: String
    let password: String
    let data: Metadata
}

private struct SupabaseVerifyRequest: Encodable {
    let email: String?
    let token: String?
    let tokenHash: String?
    let type: String

    init(email: String, token: String, type: String) {
        self.email = email
        self.token = token
        self.tokenHash = nil
        self.type = type
    }

    init(tokenHash: String, type: String) {
        self.email = nil
        self.token = nil
        self.tokenHash = tokenHash
        self.type = type
    }
}

private struct SupabaseResendRequest: Encodable {
    let email: String
    let type: String
}

private struct SupabaseEmailRequest: Encodable {
    let email: String
}

private struct SupabasePasswordGrantRequest: Encodable {
    let email: String
    let password: String
}

private struct SupabaseRefreshRequest: Encodable {
    let refreshToken: String
}

private struct SupabasePasswordUpdateRequest: Encodable {
    let password: String
}

private struct SupabaseEmptyRequest: Encodable {}
private struct SupabaseEmptyResponse: Codable {
    init() {}
}

private struct SupabaseAuthEnvelope: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Double?
    let expiresAt: Double?
    let tokenType: String?
    let user: SupabaseUser?
    let session: SupabaseSession?
    let id: String?
    let email: String?
    let emailConfirmedAt: String?
    let userMetadata: SupabaseUser.Metadata?

    var resolvedSession: SupabaseSession? {
        if let session { return session }
        guard let accessToken else { return nil }
        return SupabaseSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresIn: expiresIn,
            expiresAt: expiresAt,
            tokenType: tokenType,
            user: user
        )
    }

    var resolvedUser: SupabaseUser? {
        if let user { return user }
        if let sessionUser = session?.user { return sessionUser }
        guard let id else { return nil }
        return SupabaseUser(
            id: id,
            email: email,
            emailConfirmedAt: emailConfirmedAt,
            userMetadata: userMetadata
        )
    }

    func makeSession(fallbackEmail: String? = nil) throws -> AuthSession {
        guard let resolvedSession, let accessToken = resolvedSession.accessToken else {
            throw AccountAuthError.emailNotVerified
        }
        let user = resolvedSession.user ?? resolvedUser
        guard let userID = user?.id else {
            throw AccountAuthError.serverRejected("The account service returned no user identifier.")
        }
        let expiry: Date?
        if let epoch = resolvedSession.expiresAt {
            expiry = Date(timeIntervalSince1970: epoch)
        } else if let seconds = resolvedSession.expiresIn {
            expiry = .now.addingTimeInterval(seconds)
        } else {
            expiry = nil
        }
        return AuthSession(
            userID: userID,
            email: user?.email ?? fallbackEmail ?? "",
            displayName: user?.userMetadata?.displayName ?? "",
            emailVerified: user?.emailConfirmedAt != nil,
            accessToken: accessToken,
            refreshToken: resolvedSession.refreshToken,
            expiresAt: expiry
        )
    }
}

private struct SupabaseSession: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Double?
    let expiresAt: Double?
    let tokenType: String?
    let user: SupabaseUser?
}

private struct SupabaseUser: Decodable {
    struct Metadata: Decodable {
        let displayName: String?
    }

    let id: String
    let email: String?
    let emailConfirmedAt: String?
    let userMetadata: Metadata?
}

private struct SupabaseErrorResponse: Decodable {
    let code: String?
    let errorCode: String?
    let message: String?
    let msg: String?
    let error: String?
    let errorDescription: String?
}

struct AuthSessionStore: Sendable {
    static let keychainAccessibility = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

    private let service: String
    private let account: String

    init(
        service: String = "com.venture.brain-drift.auth-session",
        account: String = "current-session"
    ) {
        self.service = service
        self.account = account
    }

    func save(_ session: AuthSession) throws {
        let data = try JSONEncoder().encode(session)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: Self.keychainAccessibility
        ]
        let update = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if update == errSecItemNotFound {
            var insert = baseQuery
            attributes.forEach { insert[$0.key] = $0.value }
            let status = SecItemAdd(insert as CFDictionary, nil)
            guard status == errSecSuccess else {
                try saveSimulatorFallback(data)
                return
            }
            clearSimulatorFallback()
        } else if update != errSecSuccess {
            try saveSimulatorFallback(data)
        } else {
            clearSimulatorFallback()
        }
    }

    func load() -> AuthSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        let data: Data
        if status == errSecSuccess, let keychainData = item as? Data {
            data = keychainData
        } else if let fallback = loadSimulatorFallback() {
            data = fallback
        } else {
            return nil
        }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
        if let simulatorFallbackURL {
            try? FileManager.default.removeItem(at: simulatorFallbackURL)
        }
    }

    private func saveSimulatorFallback(_ data: Data) throws {
        guard let simulatorFallbackURL else { throw AccountAuthError.secureStorageUnavailable }
        try FileManager.default.createDirectory(
            at: simulatorFallbackURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            try data.write(to: simulatorFallbackURL, options: [.atomic, .completeFileProtection])
        } catch CocoaError.fileNoSuchFile {
            try data.write(to: simulatorFallbackURL, options: [.completeFileProtection])
        }
    }

    private func loadSimulatorFallback() -> Data? {
        guard let simulatorFallbackURL else { return nil }
        return try? Data(contentsOf: simulatorFallbackURL, options: [.mappedIfSafe])
    }

    private func clearSimulatorFallback() {
        guard let simulatorFallbackURL else { return }
        try? FileManager.default.removeItem(at: simulatorFallbackURL)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    private var simulatorFallbackURL: URL? {
#if DEBUG && targetEnvironment(simulator)
        let identity = "\(service)|\(account)"
        let identifier = Data(SHA256.hash(data: Data(identity.utf8)))
            .prefix(12)
            .map { String(format: "%02x", $0) }
            .joined()
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Venture/DevelopmentAuth", directoryHint: .isDirectory)
            .appending(path: "session-\(identifier).protected")
#else
        return nil
#endif
    }
}

struct PendingPasswordResetStore: Sendable {
    private let store: AuthSessionStore

    init(
        service: String = "com.venture.brain-drift.password-reset",
        account: String = "pending-recovery"
    ) {
        store = AuthSessionStore(service: service, account: account)
    }

    func save(_ context: PendingPasswordResetContext) throws {
        let session = AuthSession(
            userID: "password-recovery",
            email: context.email,
            displayName: "",
            emailVerified: true,
            accessToken: context.accessToken,
            refreshToken: context.refreshToken,
            expiresAt: context.expiresAt
        )
        try store.save(session)
    }

    func load() -> PendingPasswordResetContext? {
        guard let session = store.load() else { return nil }
        return PendingPasswordResetContext(
            email: session.email,
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            expiresAt: session.expiresAt
        )
    }

    func delete() {
        store.delete()
    }
}

enum SupabasePasswordRecoveryLinkParser {
    static func parse(_ url: URL) -> PendingPasswordResetContext? {
        guard let values = recoveryValues(from: url) else { return nil }
        guard let accessToken = values["access_token"], !accessToken.isEmpty else { return nil }

        let expiry: Date?
        if let epoch = values["expires_at"].flatMap(Double.init) {
            expiry = Date(timeIntervalSince1970: epoch)
        } else if let seconds = values["expires_in"].flatMap(Double.init) {
            expiry = .now.addingTimeInterval(seconds)
        } else {
            expiry = nil
        }

        return PendingPasswordResetContext(
            email: values["email"] ?? "",
            accessToken: accessToken,
            refreshToken: values["refresh_token"],
            expiresAt: expiry
        )
    }

    static func parseTokenHash(_ url: URL) -> String? {
        guard let values = recoveryValues(from: url) else { return nil }
        let tokenHash = values["token_hash"] ?? values["tokenHash"]
        guard let tokenHash, !tokenHash.isEmpty else { return nil }
        return tokenHash
    }

    static func parseRecoveryError(_ url: URL) -> String? {
        guard let values = recoveryValues(from: url, allowErrorPayload: true) else { return nil }
        guard values["error"] != nil || values["error_code"] != nil || values["error_description"] != nil else {
            return nil
        }
        let description = values["error_description"]?
            .replacingOccurrences(of: "+", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let description, !description.isEmpty {
            return "reset link could not be verified: \(description.lowercased())"
        }
        return "reset link could not be verified. send a new link."
    }

    private static func recoveryValues(from url: URL, allowErrorPayload: Bool = false) -> [String: String]? {
        guard url.scheme?.lowercased() == "venture",
              isRecoveryRoute(url)
        else { return nil }

        let values = tokenValues(from: url)
        let type = values["type"]?.lowercased()
        if !allowErrorPayload {
            guard type == nil || type == "recovery" else { return nil }
        } else if let type, type != "recovery" {
            return nil
        }
        return values
    }

    private static func isRecoveryRoute(_ url: URL) -> Bool {
        let host = url.host?.lowercased()
        let path = normalizedPath(url.path)
        if host == "auth", isRecoveryPath(path) { return true }
        if host == "reset", path.isEmpty { return true }
        if host == nil, path == "auth/reset" { return true }
        return false
    }

    private static func isRecoveryPath(_ path: String) -> Bool {
        let normalized = normalizedPath(path)
        return normalized.isEmpty || normalized == "reset"
    }

    private static func normalizedPath(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }

    private static func tokenValues(from url: URL) -> [String: String] {
        var values: [String: String] = [:]
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .forEach { values[$0.name] = $0.value }

        if let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment {
            URLComponents(string: "venture://fragment?\(fragment)")?
                .queryItems?
                .forEach { values[$0.name] = $0.value }
        }
        return values
    }
}

enum EmailVerificationCode {
    static func generate() -> String {
        var number: UInt32 = 0
        _ = SecRandomCopyBytes(kSecRandomDefault, MemoryLayout<UInt32>.size, &number)
        return String(format: "%06d", Int(number % 1_000_000))
    }

    static func digest(_ code: String, salt: Data) -> Data {
        var data = salt
        data.append(Data(code.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
        return Data(SHA256.hash(data: data))
    }
}
