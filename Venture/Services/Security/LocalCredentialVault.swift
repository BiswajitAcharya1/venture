import CryptoKit
import Foundation
import Security

struct LocalCredentialVault {
    static let keychainAccessibility = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

    private let service: String

    init(service: String = "com.venture.brain-drift.local-credential") {
        self.service = service
    }

    func create(name: String, email: String, password: String, consent: LegalConsent = .current()) throws {
        try createPending(name: name, email: email, password: password, verificationCode: nil, consent: consent)
    }

    func createPending(name: String, email: String, password: String, verificationCode: String?, consent: LegalConsent = .current()) throws {
        let salt = try randomBytes(count: 32)
        let verificationSalt = try randomBytes(count: 32)
        let credential = StoredCredential(
            schemaVersion: PasswordKeyDerivation.currentVersion,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            email: normalize(email),
            salt: salt,
            passwordDigest: try PasswordKeyDerivation.derive(password: password, salt: salt),
            emailVerified: verificationCode == nil,
            verificationSalt: verificationCode == nil ? nil : verificationSalt,
            verificationDigest: verificationCode.map { EmailVerificationCode.digest($0, salt: verificationSalt) },
            legalConsent: consent
        )
        try store(credential)
    }

    func verify(email: String, password: String) -> Bool {
        verifyForSignIn(email: email, password: password)?.emailVerified == true
    }

    func verifyForSignIn(email: String, password: String) -> LocalSignInResult? {
        guard let credential = try? load(), credential.email == normalize(email) else { return nil }
        let candidate: Data
        if credential.schemaVersion >= PasswordKeyDerivation.currentVersion {
            guard let derived = try? PasswordKeyDerivation.derive(password: password, salt: credential.salt) else { return nil }
            candidate = derived
        } else {
            candidate = legacyDigest(password: password, salt: credential.salt)
        }
        guard constantTimeEqual(credential.passwordDigest, candidate) else { return nil }
        if credential.schemaVersion < PasswordKeyDerivation.currentVersion {
            try? migrate(credential: credential, password: password)
        }
        return LocalSignInResult(
            emailVerified: credential.emailVerified,
            session: AuthSession(
                userID: "local-\(credential.email.sha256Prefix)",
                email: credential.email,
                displayName: credential.name,
                emailVerified: credential.emailVerified,
                accessToken: "local-development-session",
                refreshToken: nil,
                expiresAt: nil
            )
        )
    }

    func reset(email: String, password: String) throws {
        var credential = try load()
        guard credential.email == normalize(email) else {
            throw CredentialError.accountNotFound
        }
        let salt = try randomBytes(count: 32)
        credential.schemaVersion = PasswordKeyDerivation.currentVersion
        credential.salt = salt
        credential.passwordDigest = try PasswordKeyDerivation.derive(password: password, salt: salt)
        try store(credential)
    }

    func reset(email: String, password: String, verificationCode code: String) throws {
        var credential = try load()
        guard credential.email == normalize(email) else { throw CredentialError.accountNotFound }
        guard let verificationSalt = credential.verificationSalt,
              let verificationDigest = credential.verificationDigest,
              constantTimeEqual(verificationDigest, EmailVerificationCode.digest(code, salt: verificationSalt))
        else {
            throw CredentialError.invalidVerificationCode
        }
        let salt = try randomBytes(count: 32)
        credential.schemaVersion = PasswordKeyDerivation.currentVersion
        credential.salt = salt
        credential.passwordDigest = try PasswordKeyDerivation.derive(password: password, salt: salt)
        credential.emailVerified = true
        credential.verificationSalt = nil
        credential.verificationDigest = nil
        try store(credential)
    }

    func verifyEmail(email: String, code: String) throws -> AuthSession? {
        var credential = try load()
        guard credential.email == normalize(email) else { throw CredentialError.accountNotFound }
        guard let verificationSalt = credential.verificationSalt,
              let verificationDigest = credential.verificationDigest
        else {
            return LocalSignInResult(
                emailVerified: credential.emailVerified,
                session: AuthSession(
                    userID: "local-\(credential.email.sha256Prefix)",
                    email: credential.email,
                    displayName: credential.name,
                    emailVerified: credential.emailVerified,
                    accessToken: "local-development-session",
                    refreshToken: nil,
                    expiresAt: nil
                )
            ).session
        }
        let candidate = EmailVerificationCode.digest(code, salt: verificationSalt)
        guard constantTimeEqual(verificationDigest, candidate) else { return nil }
        credential.emailVerified = true
        credential.verificationSalt = nil
        credential.verificationDigest = nil
        try store(credential)
        return AuthSession(
            userID: "local-\(credential.email.sha256Prefix)",
            email: credential.email,
            displayName: credential.name,
            emailVerified: true,
            accessToken: "local-development-session",
            refreshToken: nil,
            expiresAt: nil
        )
    }

    func rotateVerificationCode(email: String) throws -> String {
        var credential = try load()
        guard credential.email == normalize(email) else { throw CredentialError.accountNotFound }
        guard !credential.emailVerified else { return "" }
        let code = EmailVerificationCode.generate()
        let salt = try randomBytes(count: 32)
        credential.verificationSalt = salt
        credential.verificationDigest = EmailVerificationCode.digest(code, salt: salt)
        try store(credential)
        return code
    }

    func beginPasswordReset(email: String) throws -> String {
        var credential = try load()
        guard credential.email == normalize(email) else { throw CredentialError.accountNotFound }
        let code = EmailVerificationCode.generate()
        let salt = try randomBytes(count: 32)
        credential.verificationSalt = salt
        credential.verificationDigest = EmailVerificationCode.digest(code, salt: salt)
        try store(credential)
        return code
    }

    func containsAccount(email: String) -> Bool {
        guard let credential = try? load() else { return false }
        return credential.email == normalize(email)
    }

    func hasAccount() -> Bool {
        (try? load()) != nil
    }

    func deleteAccount() {
        SecItemDelete(baseQuery as CFDictionary)
        if let simulatorFallbackURL {
            try? FileManager.default.removeItem(at: simulatorFallbackURL)
        }
    }

    private func store(_ credential: StoredCredential) throws {
        let data = try JSONEncoder().encode(credential)
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

    private func load() throws -> StoredCredential {
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
            throw CredentialError.accountNotFound
        }
        return try JSONDecoder().decode(StoredCredential.self, from: data)
    }

    private func saveSimulatorFallback(_ data: Data) throws {
        guard let simulatorFallbackURL else { throw CredentialError.keychainFailure }
        try FileManager.default.createDirectory(
            at: simulatorFallbackURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: simulatorFallbackURL, options: [.atomic, .completeFileProtection])
    }

    private func loadSimulatorFallback() -> Data? {
        guard let simulatorFallbackURL else { return nil }
        return try? Data(contentsOf: simulatorFallbackURL, options: [.mappedIfSafe])
    }

    private func clearSimulatorFallback() {
        guard let simulatorFallbackURL else { return }
        try? FileManager.default.removeItem(at: simulatorFallbackURL)
    }

    private func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw CredentialError.keychainFailure
        }
        return Data(bytes)
    }

    private func legacyDigest(password: String, salt: Data) -> Data {
        var input = salt
        input.append(Data(password.utf8))
        return Data(SHA256.hash(data: input))
    }

    private func migrate(credential: StoredCredential, password: String) throws {
        let salt = try randomBytes(count: 32)
        let migrated = StoredCredential(
            schemaVersion: PasswordKeyDerivation.currentVersion,
            name: credential.name,
            email: credential.email,
            salt: salt,
            passwordDigest: try PasswordKeyDerivation.derive(password: password, salt: salt),
            emailVerified: credential.emailVerified,
            verificationSalt: credential.verificationSalt,
            verificationDigest: credential.verificationDigest,
            legalConsent: credential.legalConsent
        )
        try store(migrated)
    }

    private func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "local-account",
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    private var simulatorFallbackURL: URL? {
#if DEBUG && targetEnvironment(simulator)
        let identifier = Data(SHA256.hash(data: Data(service.utf8)))
            .prefix(12)
            .map { String(format: "%02x", $0) }
            .joined()
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Venture/DevelopmentAuth", directoryHint: .isDirectory)
            .appending(path: "credential-\(identifier).protected")
#else
        return nil
#endif
    }
}

struct LocalSignInResult: Sendable, Equatable {
    let emailVerified: Bool
    let session: AuthSession
}

private struct StoredCredential: Codable {
    var schemaVersion: Int
    let name: String
    let email: String
    var salt: Data
    var passwordDigest: Data
    var emailVerified: Bool
    var verificationSalt: Data?
    var verificationDigest: Data?
    var legalConsent: LegalConsent?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, name, email, salt, passwordDigest, emailVerified, verificationSalt, verificationDigest, legalConsent
    }

    init(
        schemaVersion: Int,
        name: String,
        email: String,
        salt: Data,
        passwordDigest: Data,
        emailVerified: Bool = true,
        verificationSalt: Data? = nil,
        verificationDigest: Data? = nil,
        legalConsent: LegalConsent? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.email = email
        self.salt = salt
        self.passwordDigest = passwordDigest
        self.emailVerified = emailVerified
        self.verificationSalt = verificationSalt
        self.verificationDigest = verificationDigest
        self.legalConsent = legalConsent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        name = try container.decode(String.self, forKey: .name)
        email = try container.decode(String.self, forKey: .email)
        salt = try container.decode(Data.self, forKey: .salt)
        passwordDigest = try container.decode(Data.self, forKey: .passwordDigest)
        emailVerified = try container.decodeIfPresent(Bool.self, forKey: .emailVerified) ?? true
        verificationSalt = try container.decodeIfPresent(Data.self, forKey: .verificationSalt)
        verificationDigest = try container.decodeIfPresent(Data.self, forKey: .verificationDigest)
        legalConsent = try container.decodeIfPresent(LegalConsent.self, forKey: .legalConsent)
    }
}

enum CredentialError: Error {
    case accountNotFound
    case keychainFailure
    case invalidVerificationCode
}

private extension String {
    var sha256Prefix: String {
        Data(SHA256.hash(data: Data(utf8))).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
