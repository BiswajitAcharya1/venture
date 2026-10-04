import XCTest
import Security
@testable import Venture

final class AccountAuthServiceTests: XCTestCase {
    override func tearDown() {
        SupabaseURLProtocol.handler = nil
        super.tearDown()
    }

    func testDebugBundleConfigurationUsesLocalAuthDespiteSupabaseSettings() {
#if DEBUG
        let configuration = AccountBackendConfiguration.fromBundle

        XCTAssertNil(configuration.supabase)
        XCTAssertTrue(configuration.allowsLocalDevelopmentFallback)
        XCTAssertFalse(configuration.requiresAuthenticatedSession)
#endif
    }

    func testLocalDevelopmentSignUpCanSignInWithoutVerificationCode() async throws {
        let suffix = UUID().uuidString
        let credentials = LocalCredentialVault(service: "com.venture.tests.credentials.\(suffix)")
        let sessionStore = AuthSessionStore(service: "com.venture.tests.session.\(suffix)")
        let service = AccountAuthService(
            credentials: credentials,
            sessionStore: sessionStore,
            configuration: AccountBackendConfiguration(
                authBaseURL: nil,
                emailVerifierBaseURL: nil,
                emailVerifierProvider: .reacher
            )
        )
        defer {
            credentials.deleteAccount()
            sessionStore.delete()
        }

        let email = "new-user-\(suffix)@example.com"
        let password = "ventureSecure42!"
        let outcome = try await service.signUp(name: "New User", email: email, password: password)

        XCTAssertFalse(outcome.requiresEmailVerification)
        XCTAssertNil(outcome.debugVerificationCode)

        let session = try await service.signIn(email: email, password: password)
        XCTAssertTrue(session.emailVerified)
        XCTAssertEqual(session.email, email.lowercased())
    }

    func testPendingLocalCredentialCanStillBeVerifiedWithCode() async throws {
        let suffix = UUID().uuidString
        let credentials = LocalCredentialVault(service: "com.venture.tests.pending.credentials.\(suffix)")
        let sessionStore = AuthSessionStore(service: "com.venture.tests.pending.session.\(suffix)")
        let service = AccountAuthService(
            credentials: credentials,
            sessionStore: sessionStore,
            configuration: AccountBackendConfiguration(
                authBaseURL: nil,
                emailVerifierBaseURL: nil,
                emailVerifierProvider: .reacher
            )
        )
        defer {
            credentials.deleteAccount()
            sessionStore.delete()
        }

        let email = "pending-\(suffix)@example.com"
        let code = EmailVerificationCode.generate()
        try credentials.createPending(
            name: "Pending User",
            email: email,
            password: "ventureSecure42!",
            verificationCode: code
        )

        do {
            _ = try await service.signIn(email: email, password: "ventureSecure42!")
            XCTFail("pending local account should still require verification")
        } catch AccountAuthError.emailNotVerified {
            // Expected.
        }

        let verified = try await service.verifyEmail(email: email, code: code)
        XCTAssertTrue(verified.emailVerified)
        XCTAssertEqual(verified.email, email.lowercased())
        XCTAssertEqual(sessionStore.load(), verified)
    }

    func testRepeatedBadSignInAttemptsAreLocallyRateLimited() async throws {
        let suffix = UUID().uuidString
        let credentials = LocalCredentialVault(service: "com.venture.tests.rate.credentials.\(suffix)")
        let sessionStore = AuthSessionStore(service: "com.venture.tests.rate.session.\(suffix)")
        let clock = MutableTestClock(Date(timeIntervalSince1970: 1_820_000_000))
        let service = AccountAuthService(
            credentials: credentials,
            sessionStore: sessionStore,
            configuration: AccountBackendConfiguration(
                authBaseURL: nil,
                emailVerifierBaseURL: nil,
                emailVerifierProvider: .reacher
            ),
            signInLimiter: SignInRateLimiter(
                policy: SignInRateLimitPolicy(freeFailures: 2, baseLockout: 10, maximumLockout: 60),
                now: { clock.now }
            )
        )
        defer {
            credentials.deleteAccount()
            sessionStore.delete()
        }

        let outcome = try await service.signUp(
            name: "Rate User",
            email: "rate-\(suffix)@example.com",
            password: "ventureSecure42!"
        )

        for _ in 0..<2 {
            do {
                _ = try await service.signIn(email: outcome.email, password: "wrong-password")
                XCTFail("bad password should fail")
            } catch AccountAuthError.wrongPassword {
                // Expected.
            }
        }

        do {
            _ = try await service.signIn(email: outcome.email, password: "wrong-password")
            XCTFail("third attempt should be locally throttled")
        } catch AccountAuthError.tooManyAttempts(let seconds) {
            XCTAssertEqual(seconds, 10)
        }

        clock.now = clock.now.addingTimeInterval(11)
        let session = try await service.signIn(email: outcome.email, password: "ventureSecure42!")

        XCTAssertEqual(session.email, outcome.email)
        XCTAssertEqual(sessionStore.load(), session)
    }

    func testEmailAddressValidatorNormalizesAndRejectsInvalidAddresses() {
        XCTAssertEqual(EmailAddressValidator.normalized("  USER@Example.COM  "), "user@example.com")
        XCTAssertTrue(EmailAddressValidator.isValid("user@example.com"))
        XCTAssertFalse(EmailAddressValidator.isValid("user@example"))
        XCTAssertFalse(EmailAddressValidator.isValid("@example.com"))
        XCTAssertFalse(EmailAddressValidator.isValid("user@example."))
        XCTAssertFalse(EmailAddressValidator.isValid("user..name@example.com"))
    }

    func testDeliverabilityReportRejectsDisposableOrInvalidAddresses() {
        XCTAssertNoThrow(try EmailDeliverabilityReport(
            reachability: .safe,
            syntaxValid: true,
            acceptsMail: true,
            disposable: false,
            suggestion: nil
        ).requireAcceptable())

        XCTAssertThrowsError(try EmailDeliverabilityReport(
            reachability: .safe,
            syntaxValid: true,
            acceptsMail: true,
            disposable: true,
            suggestion: nil
        ).requireAcceptable())

        XCTAssertThrowsError(try EmailDeliverabilityReport(
            reachability: .invalid,
            syntaxValid: true,
            acceptsMail: true,
            disposable: false,
            suggestion: nil
        ).requireAcceptable())
    }

    func testVerificationCodeDigestUsesSalt() {
        let code = "123456"
        let first = EmailVerificationCode.digest(code, salt: Data(repeating: 1, count: 32))
        let second = EmailVerificationCode.digest(code, salt: Data(repeating: 2, count: 32))

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first, EmailVerificationCode.digest(" 123456 ", salt: Data(repeating: 1, count: 32)))
    }

    func testAccountSecretsUseUnlockedDeviceOnlyKeychainAccessibility() {
        XCTAssertEqual(
            AuthSessionStore.keychainAccessibility as String,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        )
        XCTAssertEqual(
            LocalCredentialVault.keychainAccessibility as String,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        )
    }

    func testAccountNetworkSessionDoesNotPersistCookiesOrCache() {
        let session = SecureNetworkSession.make()
        let configuration = session.configuration

        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(configuration.timeoutIntervalForRequest, 20)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 30)
    }

    func testAccountRedirectPolicyRequiresSameHostHTTPS() throws {
        let original = try XCTUnwrap(URL(string: "https://accounts.example.com/v1/auth/signin"))

        XCTAssertTrue(SecureNetworkSession.allowsRedirect(
            from: original,
            to: URL(string: "https://accounts.example.com/v2/auth/signin")
        ))
        XCTAssertFalse(SecureNetworkSession.allowsRedirect(
            from: original,
            to: URL(string: "http://accounts.example.com/v2/auth/signin")
        ))
        XCTAssertFalse(SecureNetworkSession.allowsRedirect(
            from: original,
            to: URL(string: "https://attacker.example/v2/auth/signin")
        ))
    }

    func testReleaseConfigurationRejectsLocalCredentialFallback() async {
        let suffix = UUID().uuidString
        let service = AccountAuthService(
            credentials: LocalCredentialVault(service: "com.venture.tests.release.credentials.\(suffix)"),
            sessionStore: AuthSessionStore(service: "com.venture.tests.release.session.\(suffix)"),
            configuration: AccountBackendConfiguration(
                authBaseURL: nil,
                emailVerifierBaseURL: nil,
                emailVerifierProvider: .reacher,
                allowsLocalDevelopmentFallback: false
            )
        )

        do {
            _ = try await service.signUp(
                name: "Release User",
                email: "release@example.com",
                password: "ventureSecure42!"
            )
            XCTFail("release builds must not create device-only email credentials")
        } catch AccountAuthError.backendNotConfigured {
            // Expected.
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testDeletingLocalAccountRemovesCredentialAndSession() async throws {
        let suffix = UUID().uuidString
        let credentials = LocalCredentialVault(service: "com.venture.tests.delete.credentials.\(suffix)")
        let sessionStore = AuthSessionStore(service: "com.venture.tests.delete.session.\(suffix)")
        let service = AccountAuthService(
            credentials: credentials,
            sessionStore: sessionStore,
            configuration: AccountBackendConfiguration(
                authBaseURL: nil,
                emailVerifierBaseURL: nil,
                emailVerifierProvider: .reacher
            )
        )
        defer {
            credentials.deleteAccount()
            sessionStore.delete()
        }

        let outcome = try await service.signUp(
            name: "Delete User",
            email: "delete-\(suffix)@example.com",
            password: "ventureSecure42!"
        )
        XCTAssertFalse(outcome.requiresEmailVerification)

        try await service.deleteCurrentAccount()

        XCTAssertFalse(credentials.hasAccount())
        XCTAssertNil(sessionStore.load())
    }

    func testSupabaseSignupSendsPublishableKeyAndLegalMetadata() async throws {
        let session = makeSupabaseSession()
        let projectURL = try XCTUnwrap(URL(string: "https://venture-test.supabase.co"))
        let client = SupabaseAccountClient(
            projectURL: projectURL,
            anonKey: "public-anon-key",
            session: session
        )
        SupabaseURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/auth/v1/signup")
            XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "public-anon-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer public-anon-key")
            let body = try self.requestBody(request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["email"] as? String, "person@example.com")
            let metadata = try XCTUnwrap(json["data"] as? [String: Any])
            XCTAssertEqual(metadata["display_name"] as? String, "Person")
            XCTAssertEqual(metadata["terms_version"] as? String, LegalConsent.currentTermsVersion)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"user":{"id":"user-1","email":"person@example.com","email_confirmed_at":null,"user_metadata":{"display_name":"Person"}},"session":null}"#.utf8)
            )
        }

        let outcome = try await client.signUp(
            name: "Person",
            email: "person@example.com",
            password: "ventureSecure42!",
            consent: .current()
        )

        XCTAssertEqual(outcome.email, "person@example.com")
        XCTAssertTrue(outcome.requiresEmailVerification)
        XCTAssertNil(outcome.debugVerificationCode)
    }

    func testSupabaseOTPVerificationProducesRefreshableSession() async throws {
        let session = makeSupabaseSession()
        let client = SupabaseAccountClient(
            projectURL: try XCTUnwrap(URL(string: "https://venture-test.supabase.co")),
            anonKey: "public-anon-key",
            session: session
        )
        SupabaseURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/auth/v1/verify")
            let body = try self.requestBody(request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["token"] as? String, "123456")
            XCTAssertEqual(json["type"] as? String, "signup")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"access_token":"access","refresh_token":"refresh","expires_in":3600,"user":{"id":"user-1","email":"person@example.com","email_confirmed_at":"2026-06-20T00:00:00Z","user_metadata":{"display_name":"Person"}}}"#.utf8)
            )
        }

        let result = try await client.verifyEmail(email: "person@example.com", code: "123456")

        XCTAssertEqual(result.userID, "user-1")
        XCTAssertEqual(result.email, "person@example.com")
        XCTAssertEqual(result.displayName, "Person")
        XCTAssertTrue(result.emailVerified)
        XCTAssertEqual(result.accessToken, "access")
        XCTAssertEqual(result.refreshToken, "refresh")
        XCTAssertNotNil(result.expiresAt)
    }

    func testSupabaseRefreshUsesRefreshGrantAndRotatesTokens() async throws {
        let client = SupabaseAccountClient(
            projectURL: try XCTUnwrap(URL(string: "https://venture-test.supabase.co")),
            anonKey: "public-anon-key",
            session: makeSupabaseSession()
        )
        SupabaseURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/auth/v1/token")
            XCTAssertEqual(
                URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "grant_type" })?.value,
                "refresh_token"
            )
            let body = try self.requestBody(request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["refresh_token"] as? String, "old-refresh")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600,"user":{"id":"user-1","email":"person@example.com","email_confirmed_at":"2026-06-20T00:00:00Z","user_metadata":{"display_name":"Person"}}}"#.utf8)
            )
        }

        let result = try await client.refreshSession(refreshToken: "old-refresh")

        XCTAssertEqual(result.accessToken, "new-access")
        XCTAssertEqual(result.refreshToken, "new-refresh")
    }

    func testSupabaseErrorMappingHandlesCommonAuthFailures() async throws {
        let client = SupabaseAccountClient(
            projectURL: try XCTUnwrap(URL(string: "https://venture-test.supabase.co")),
            anonKey: "public-anon-key",
            session: makeSupabaseSession()
        )

        SupabaseURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/auth/v1/token")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!,
                Data(#"{"error":"invalid_grant","error_description":"Invalid login credentials"}"#.utf8)
            )
        }

        do {
            _ = try await client.signIn(email: "person@example.com", password: "wrong-password")
            XCTFail("invalid Supabase credentials should map to wrongPassword")
        } catch AccountAuthError.wrongPassword {
            // Expected.
        }

        SupabaseURLProtocol.handler = { request in
            return (
                HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!,
                Data(#"{"code":"email_not_confirmed","message":"Email not confirmed"}"#.utf8)
            )
        }

        do {
            _ = try await client.signIn(email: "person@example.com", password: "ventureSecure42!")
            XCTFail("unconfirmed Supabase email should map to emailNotVerified")
        } catch AccountAuthError.emailNotVerified {
            // Expected.
        }

        SupabaseURLProtocol.handler = { request in
            return (
                HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!,
                Data(#"{"message":"Too many requests"}"#.utf8)
            )
        }

        do {
            _ = try await client.signIn(email: "person@example.com", password: "ventureSecure42!")
            XCTFail("Supabase rate limiting should surface as a retry delay")
        } catch AccountAuthError.tooManyAttempts(let seconds) {
            XCTAssertEqual(seconds, 60)
        }
    }

    func testSupabaseDeleteAccountCallsAuthenticatedEdgeFunction() async throws {
        let client = SupabaseAccountClient(
            projectURL: try XCTUnwrap(URL(string: "https://venture-test.supabase.co")),
            anonKey: "public-anon-key",
            session: makeSupabaseSession()
        )

        SupabaseURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/functions/v1/delete-account")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "public-anon-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer user-access-token")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("{}".utf8)
            )
        }

        try await client.deleteAccount(accessToken: "user-access-token")
    }

    func testSupabasePasswordRecoverySendsAppRedirectRequest() async throws {
        let client = SupabaseAccountClient(
            projectURL: try XCTUnwrap(URL(string: "https://venture-test.supabase.co")),
            anonKey: "public-anon-key",
            session: makeSupabaseSession()
        )

        SupabaseURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/auth/v1/recover")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "public-anon-key")
            let redirect = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "redirect_to" })?
                .value
            XCTAssertEqual(redirect, "venture://auth/reset")
            let body = try self.requestBody(request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["email"] as? String, "person@example.com")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("{}".utf8)
            )
        }

        try await client.requestPasswordReset(email: "person@example.com")
    }

    func testPasswordRecoveryLinkStoresPendingContext() async throws {
        let suffix = UUID().uuidString
        let pendingStore = PendingPasswordResetStore(
            service: "com.venture.tests.recovery.\(suffix)",
            account: "pending"
        )
        let service = AccountAuthService(
            pendingPasswordResetStore: pendingStore,
            configuration: AccountBackendConfiguration(
                authBaseURL: nil,
                emailVerifierBaseURL: nil,
                emailVerifierProvider: .reacher
            )
        )
        defer { pendingStore.delete() }

        let handled = try await service.storePasswordRecoveryLink(try XCTUnwrap(URL(
            string: "venture://auth/reset#type=recovery&access_token=recovery-access&refresh_token=recovery-refresh&expires_in=600&email=person%40example.com"
        )))
        let pending = await service.pendingPasswordResetContext()

        XCTAssertTrue(handled)
        XCTAssertEqual(pending?.email, "person@example.com")
        XCTAssertEqual(pending?.accessToken, "recovery-access")
        XCTAssertEqual(pending?.refreshToken, "recovery-refresh")
        XCTAssertNotNil(pending?.expiresAt)
    }

    func testPasswordRecoveryLinkAcceptsPlainAuthSiteURLFragment() throws {
        let context = try XCTUnwrap(SupabasePasswordRecoveryLinkParser.parse(try XCTUnwrap(URL(
            string: "venture://auth#type=recovery&access_token=site-access&refresh_token=site-refresh&expires_in=600&email=person%40example.com"
        ))))

        XCTAssertEqual(context.email, "person@example.com")
        XCTAssertEqual(context.accessToken, "site-access")
        XCTAssertEqual(context.refreshToken, "site-refresh")
        XCTAssertNotNil(context.expiresAt)
    }

    func testPasswordRecoveryLinkAcceptsQueryTokenFormat() throws {
        let context = try XCTUnwrap(SupabasePasswordRecoveryLinkParser.parse(try XCTUnwrap(URL(
            string: "venture://auth/reset?type=recovery&access_token=query-access&refresh_token=query-refresh&expires_at=1820000600"
        ))))

        XCTAssertEqual(context.accessToken, "query-access")
        XCTAssertEqual(context.refreshToken, "query-refresh")
        XCTAssertEqual(context.expiresAt, Date(timeIntervalSince1970: 1_820_000_600))
    }

    func testPasswordRecoveryLinkAcceptsTokenHashFormat() throws {
        let tokenHash = SupabasePasswordRecoveryLinkParser.parseTokenHash(try XCTUnwrap(URL(
            string: "venture://auth/reset?type=recovery&token_hash=hashed-recovery-token"
        )))

        XCTAssertEqual(tokenHash, "hashed-recovery-token")
    }

    func testPasswordRecoveryLinkAcceptsAlternateCustomSchemeRoutes() throws {
        let hostOnlyContext = try XCTUnwrap(SupabasePasswordRecoveryLinkParser.parse(try XCTUnwrap(URL(
            string: "venture://reset#type=recovery&access_token=host-access&refresh_token=host-refresh"
        ))))
        let tripleSlashContext = try XCTUnwrap(SupabasePasswordRecoveryLinkParser.parse(try XCTUnwrap(URL(
            string: "venture:///auth/reset#type=recovery&access_token=path-access&refresh_token=path-refresh"
        ))))

        XCTAssertEqual(hostOnlyContext.accessToken, "host-access")
        XCTAssertEqual(hostOnlyContext.refreshToken, "host-refresh")
        XCTAssertEqual(tripleSlashContext.accessToken, "path-access")
        XCTAssertEqual(tripleSlashContext.refreshToken, "path-refresh")
    }

    func testPasswordRecoveryLinkSurfacesSupabaseErrorFragment() throws {
        let message = SupabasePasswordRecoveryLinkParser.parseRecoveryError(try XCTUnwrap(URL(
            string: "venture://auth/reset#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired"
        )))

        XCTAssertEqual(
            message,
            "reset link could not be verified: email link is invalid or has expired"
        )
    }

    func testPasswordRecoveryLinkRejectsNonRecoveryTokens() throws {
        XCTAssertNil(SupabasePasswordRecoveryLinkParser.parse(try XCTUnwrap(URL(
            string: "venture://auth#type=signup&access_token=signup-access"
        ))))
        XCTAssertNil(SupabasePasswordRecoveryLinkParser.parseTokenHash(try XCTUnwrap(URL(
            string: "venture://auth/reset?type=signup&token_hash=signup-token"
        ))))
    }

    func testSupabasePasswordUpdateUsesRecoveryAccessToken() async throws {
        let client = SupabaseAccountClient(
            projectURL: try XCTUnwrap(URL(string: "https://venture-test.supabase.co")),
            anonKey: "public-anon-key",
            session: makeSupabaseSession()
        )

        SupabaseURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/auth/v1/user")
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer recovery-access")
            let body = try self.requestBody(request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["password"] as? String, "NewventureSecure42!")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"id":"user-1","email":"person@example.com","email_confirmed_at":"2026-06-20T00:00:00Z","user_metadata":{"display_name":"Person"}}"#.utf8)
            )
        }

        try await client.updatePassword(accessToken: "recovery-access", newPassword: "NewventureSecure42!")
    }

    func testSupabasePasswordRecoveryTokenHashProducesPendingResetContext() async throws {
        let suffix = UUID().uuidString
        let pendingStore = PendingPasswordResetStore(
            service: "com.venture.tests.recovery-token.\(suffix)",
            account: "pending"
        )
        let supabaseURL = try XCTUnwrap(URL(string: "https://venture-test.supabase.co"))
        let service = AccountAuthService(
            pendingPasswordResetStore: pendingStore,
            configuration: AccountBackendConfiguration(
                authBaseURL: nil,
                emailVerifierBaseURL: nil,
                emailVerifierProvider: .reacher,
                supabase: .init(
                    projectURL: supabaseURL,
                    anonKey: "public-anon-key"
                )
            ),
            backendClient: SupabaseAccountClient(
                projectURL: supabaseURL,
                anonKey: "public-anon-key",
                session: makeSupabaseSession()
            )
        )
        defer {
            pendingStore.delete()
            SupabaseURLProtocol.handler = nil
        }

        SupabaseURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/auth/v1/verify")
            XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "public-anon-key")
            let body = try self.requestBody(request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["token_hash"] as? String, "hashed-recovery-token")
            XCTAssertNil(json["token"])
            XCTAssertNil(json["email"])
            XCTAssertEqual(json["type"] as? String, "recovery")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"access_token":"recovery-access","refresh_token":"recovery-refresh","expires_in":900,"user":{"id":"user-1","email":"person@example.com","email_confirmed_at":"2026-06-20T00:00:00Z","user_metadata":{"display_name":"Person"}}}"#.utf8)
            )
        }

        let handled = try await service.handlePasswordRecoveryURL(try XCTUnwrap(URL(
            string: "venture://auth/reset?type=recovery&token_hash=hashed-recovery-token"
        )))
        let pending = await service.pendingPasswordResetContext()

        XCTAssertTrue(handled)
        XCTAssertEqual(pending?.email, "person@example.com")
        XCTAssertEqual(pending?.accessToken, "recovery-access")
        XCTAssertEqual(pending?.refreshToken, "recovery-refresh")
        XCTAssertNotNil(pending?.expiresAt)
    }

    func testSupabasePasswordResetVerifiesRecoveryOTPThenUpdatesUserPassword() async throws {
        let client = SupabaseAccountClient(
            projectURL: try XCTUnwrap(URL(string: "https://venture-test.supabase.co")),
            anonKey: "public-anon-key",
            session: makeSupabaseSession()
        )
        var step = 0

        SupabaseURLProtocol.handler = { request in
            step += 1
            if step == 1 {
                XCTAssertEqual(request.url?.path, "/auth/v1/verify")
                let body = try self.requestBody(request)
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(json["email"] as? String, "person@example.com")
                XCTAssertEqual(json["token"] as? String, "654321")
                XCTAssertEqual(json["type"] as? String, "recovery")
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"access_token":"recovery-access","refresh_token":"recovery-refresh","expires_in":900,"user":{"id":"user-1","email":"person@example.com","email_confirmed_at":"2026-06-20T00:00:00Z","user_metadata":{"display_name":"Person"}}}"#.utf8)
                )
            }

            XCTAssertEqual(step, 2)
            XCTAssertEqual(request.url?.path, "/auth/v1/user")
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer recovery-access")
            let body = try self.requestBody(request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["password"] as? String, "NewventureSecure42!")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"id":"user-1","email":"person@example.com","email_confirmed_at":"2026-06-20T00:00:00Z","user_metadata":{"display_name":"Person"}}"#.utf8)
            )
        }

        try await client.resetPassword(email: "person@example.com", code: "654321", newPassword: "NewventureSecure42!")
        XCTAssertEqual(step, 2)
    }

    func testRemoteBackendConfigurationRequiresStoredSession() throws {
        let supabaseURL = try XCTUnwrap(URL(string: "https://venture-test.supabase.co"))
        let configuration = AccountBackendConfiguration(
            authBaseURL: nil,
            emailVerifierBaseURL: nil,
            emailVerifierProvider: .reacher,
            supabase: .init(projectURL: supabaseURL, anonKey: "public-anon-key")
        )

        XCTAssertTrue(configuration.supportsAccountFlow)
        XCTAssertTrue(configuration.requiresAuthenticatedSession)
    }

    func testSensitiveFilesAreExcludedFromBackup() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "venture-sensitive-\(UUID().uuidString)")
        try Data("encrypted".utf8).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        try SensitiveFileProtection.apply(to: url)

        let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
#if targetEnvironment(simulator)
        XCTAssertEqual(SensitiveFileProtection.protection, .complete)
#else
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual(
            attributes[.protectionKey] as? FileProtectionType,
            .complete
        )
#endif
    }

    private func makeSupabaseSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SupabaseURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func requestBody(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
            if count == 0 { break }
            result.append(buffer, count: count)
        }
        return result
    }
}

private final class SupabaseURLProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class MutableTestClock: @unchecked Sendable {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}
