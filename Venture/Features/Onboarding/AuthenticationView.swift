import SwiftUI

struct AuthenticationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onAuthenticated: () -> Void

    @State private var route: AuthRoute = .providers
    @State private var mode: AuthMode = .signUp
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var notice: String?
    @State private var controlsVisible = false
    @State private var legalDocument: LegalDocument?
    @State private var resettingPassword = false
    @State private var enteringApp = false
    @State private var failedAttempts = 0
    @State private var lockedUntil: Date?
    @State private var passwordVisible = false
    @State private var confirmationVisible = false
    @State private var verificationCode = ""
    @State private var pendingVerificationEmail = ""
    @State private var authWorking = false
    @State private var debugVerificationCode: String?
    @State private var resetCode = ""
    @State private var resetCodeSent = false
    @State private var resetRecoveryLinked = false
    @State private var debugResetCode: String?
    @State private var acceptedLegalTerms = false
    @FocusState private var focusedField: Field?

    private let authConfiguration: AccountBackendConfiguration
    private let authService: AccountAuthService

    init(onAuthenticated: @escaping () -> Void) {
        let configuration = AccountBackendConfiguration.fromBundle
        self.onAuthenticated = onAuthenticated
        authConfiguration = configuration
        authService = AccountAuthService(configuration: configuration)
    }

    private var passwordStrength: PasswordStrength {
        PasswordStrength(password: password)
    }

    private var formIsValid: Bool {
        guard validEmail else { return false }
        if mode == .signIn { return password.count >= 8 && password.count <= 128 }
        return !name.trimmingCharacters(in: .whitespaces).isEmpty
            && passwordStrength.isAcceptable
            && password == confirmation
            && acceptedLegalTerms
    }

    var body: some View {
        ZStack {
            VentureAtmosphereView().ignoresSafeArea()
            AuthModeAtmosphere(mode: mode)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 16)

                ZStack {
                    providerContent
                        .opacity(route == .providers ? 1 : 0)
                        .scaleEffect(route == .providers || reduceMotion ? 1 : 0.985)
                        .blur(radius: route == .providers || reduceMotion ? 0 : 4)
                        .allowsHitTesting(route == .providers)
                        .accessibilityHidden(route != .providers)

                    emailContent
                        .opacity(route == .email ? 1 : 0)
                        .scaleEffect(route == .email || reduceMotion ? 1 : 1.015)
                        .blur(radius: route == .email || reduceMotion ? 0 : 4)
                        .allowsHitTesting(route == .email)
                        .accessibilityHidden(route != .email)

                    recoveryContent
                        .opacity(route == .recovery ? 1 : 0)
                        .scaleEffect(route == .recovery || reduceMotion ? 1 : 1.015)
                        .blur(radius: route == .recovery || reduceMotion ? 0 : 4)
                        .allowsHitTesting(route == .recovery)
                        .accessibilityHidden(route != .recovery)

                    verificationContent
                        .opacity(route == .verifyEmail ? 1 : 0)
                        .scaleEffect(route == .verifyEmail || reduceMotion ? 1 : 1.015)
                        .blur(radius: route == .verifyEmail || reduceMotion ? 0 : 4)
                        .allowsHitTesting(route == .verifyEmail)
                        .accessibilityHidden(route != .verifyEmail)
                }
                .frame(maxWidth: 460)

                Spacer(minLength: 12)
                if route != .email || mode != .signUp {
                    HStack(spacing: 18) {
                        legalFooterButton("terms", document: .terms)
                        legalFooterButton("privacy", document: .privacy)
                    }
                    .foregroundStyle(VentureTheme.secondary)
                    .padding(.bottom, 18)
                }
            }
            .padding(.horizontal, 24)

            if enteringApp {
                AuthenticationPortalTransition()
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .foregroundStyle(VentureTheme.ink)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.7, dampingFraction: 0.92).delay(0.12)) {
                controlsVisible = true
            }
            preparePendingPasswordReset()
        }
        .sheet(item: $legalDocument) { LegalDocumentView(document: $0) }
    }

    private var header: some View {
        HStack {
            if route != .providers {
                AnimatedBackButton(action: showProviders)
                .transition(.scale.combined(with: .opacity))
            } else {
                Color.clear.frame(width: 42, height: 42)
            }
            Spacer()
            VStack(spacing: 5) {
                Text("venture")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .tracking(-0.6)
                Text(mode == .signUp ? "create account" : "welcome back")
                    .font(.caption2)
                    .foregroundStyle(VentureTheme.secondary)
            }
            Spacer()
            Color.clear.frame(width: 42, height: 42)
        }
        .padding(.top, 16)
    }

    private var providerContent: some View {
        VStack(spacing: 20) {
            Button(action: showEmail) {
                LivingPortalView(size: 142, intensity: 0.82, interactive: false)
            }
            .buttonStyle(HapticPlainButtonStyle())
            .accessibilityLabel("continue to venture")

            VStack(spacing: 10) {
                Text(mode == .signUp ? "begin with venture" : "return to venture")
                    .font(.system(size: 32, weight: .regular, design: .serif))
                    .tracking(-0.8)
                Text(mode == .signUp ? "learn your baseline. see meaningful change." : "your measured history, ready when you are.")
                .font(.subheadline)
                .foregroundStyle(VentureTheme.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            }
            .padding(.bottom, 8)

            VStack(spacing: 10) {
#if DEBUG
                providerButton("continue with apple", icon: {
                    Image(systemName: "apple.logo").font(.system(size: 19, weight: .medium))
                }, action: {
                    providerUnavailable("Apple")
                })
                    .authReveal(controlsVisible, delay: 0)
#endif

                providerButton("continue with google", icon: {
                    GoogleProviderMark()
                }, action: {
                    providerUnavailable("Google")
                })
                    .authReveal(controlsVisible, delay: 0.04)

                if authConfiguration.supportsAccountFlow {
                    providerButton("continue with email", primary: true, icon: {
                        Image(systemName: "envelope").font(.system(size: 18, weight: .regular))
                    }, action: showEmail)
                        .authReveal(controlsVisible, delay: 0.08)
                } else {
                    providerButton("continue on this device", primary: true, icon: {
                        Image(systemName: "iphone").font(.system(size: 18, weight: .regular))
                    }, action: completeAuthentication)
                        .authReveal(controlsVisible, delay: 0.08)
                }
            }

            Label("measurements stay private on this device", systemImage: "lock.shield")
                .font(.caption2)
                .foregroundStyle(VentureTheme.secondary)

            if let notice {
                authNotice(notice, subtle: true)
            }

            if authConfiguration.supportsAccountFlow {
                Button(action: toggleMode) {
                    HStack(spacing: 4) {
                        Text(mode == .signUp ? "already have an account?" : "new to venture?")
                            .foregroundStyle(VentureTheme.secondary)
                        Text(mode == .signUp ? "sign in" : "create account")
                            .fontWeight(.semibold)
                            .foregroundStyle(VentureTheme.primaryFill)
                    }
                    .font(.caption)
                    .padding(.vertical, 11)
                }
                .buttonStyle(HapticPlainButtonStyle())
            }
        }
    }

    private var emailContent: some View {
        GeometryReader { proxy in
            ScrollView {
                emailForm
                    .frame(
                        minHeight: max(0, proxy.size.height - 28),
                        alignment: mode == .signIn ? .center : .top
                    )
                    .frame(maxWidth: mode == .signIn ? 370 : 420)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var emailForm: some View {
        VStack(spacing: mode == .signIn ? 16 : 18) {
            VStack(spacing: 8) {
                Text(mode == .signUp ? "create your account" : "sign in")
                    .font(.system(size: mode == .signUp ? 30 : 28, weight: .regular, design: .serif))
                    .tracking(-0.7)
                Text(mode == .signUp ? "a private place for your measured timeline" : "continue your measured timeline")
                    .font(.subheadline)
                    .foregroundStyle(VentureTheme.secondary)
            }
            .frame(maxWidth: .infinity, alignment: mode == .signIn ? .center : .leading)
            .multilineTextAlignment(mode == .signIn ? .center : .leading)
            .padding(.bottom, mode == .signIn ? 4 : 8)

            if mode == .signUp {
                authSection("your details") {
                    curvedTextField("name", text: $name, symbol: "person", field: .name, contentType: .name)
                    curvedTextField("email", text: $email, symbol: "envelope", field: .email, contentType: .emailAddress)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                signInIdentity
                authSection("") {
                    curvedTextField("email", text: $email, symbol: "envelope", field: .email, contentType: .emailAddress)
                }
            }

            authSection(mode == .signUp ? "security" : "") {
                curvedSecureField(
                    "password",
                    text: $password,
                    symbol: "lock",
                    field: .password,
                    visible: $passwordVisible,
                    contentType: mode == .signUp ? .newPassword : .password
                )

                if mode == .signUp {
                    PasswordStrengthView(password: password, confirmation: confirmation)
                    curvedSecureField(
                        "confirm password",
                        text: $confirmation,
                        symbol: "checkmark.shield",
                        field: .confirmation,
                        visible: $confirmationVisible,
                        contentType: .newPassword
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            if mode == .signUp {
                legalAcceptanceRow
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if let notice {
                authNotice(notice)
            }

            Button(action: submitEmail) {
                Text(authWorking ? "working…" : (mode == .signUp ? "create account" : "sign in"))
            }
            .buttonStyle(GlowBorderButtonStyle())
            .disabled(!formIsValid || authWorking)
            .opacity(formIsValid ? 1 : 0.42)

            Button(action: toggleMode) {
                Text(mode == .signUp ? "i already have an account" : "create a new account")
                    .font(.caption.weight(.semibold))
                    .frame(height: 34)
            }
            .buttonStyle(HapticPlainButtonStyle())
            .padding(.top, 2)

            if mode == .signIn {
                Button("forgot password?") { showRecovery() }
                    .font(.caption.weight(.semibold))
                    .frame(height: 34)
                    .buttonStyle(HapticPlainButtonStyle())
            }
        }
        .frame(maxWidth: mode == .signIn ? 370 : 420)
        .frame(maxWidth: .infinity)
    }

    private var verificationContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 5) {
                    Text("verify your email")
                    .font(.system(size: 30, weight: .regular, design: .serif))
                        .tracking(-0.9)
                    Text("enter the code sent to \(pendingVerificationEmail.isEmpty ? email : pendingVerificationEmail)")
                        .font(.caption)
                        .foregroundStyle(VentureTheme.secondary)
                        .multilineTextAlignment(.center)
                }
                Text("this confirms the address can receive mail and belongs to you")
                    .font(.caption2)
                    .foregroundStyle(VentureTheme.secondary)
                    .multilineTextAlignment(.center)

                authSection("confirmation code") {
                    curvedTextField("6-digit code", text: verificationCodeBinding, symbol: "number", field: .verificationCode, contentType: .oneTimeCode)
                        .keyboardType(.numberPad)
                    CombinationCodeDisplay(code: verificationDigits, label: "email lock")
                }

                Text(verificationHelp)
                    .font(.caption2)
                    .foregroundStyle(VentureTheme.secondary)
                    .multilineTextAlignment(.center)

                if let notice {
                    authNotice(notice)
                }

                Button(authWorking ? "verifying…" : "verify email") {
                    verifyEmail()
                }
                .buttonStyle(GlowBorderButtonStyle())
                .disabled(verificationDigits.count < 6 || authWorking)
                .opacity(verificationDigits.count >= 6 ? 1 : 0.42)

                Button("send a new code") {
                    resendVerification()
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(HapticPlainButtonStyle())
                .disabled(authWorking)
            }
            .padding(.vertical, 14)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var recoveryContent: some View {
        ScrollView {
            VStack(spacing: 15) {
                VStack(spacing: 5) {
                    Text("reset password")
                    .font(.system(size: 30, weight: .regular, design: .serif))
                        .tracking(-0.9)
                    Text(resetCodeSent ? resetPasswordInstructions : resetStartInstructions)
                        .font(.caption)
                        .foregroundStyle(VentureTheme.secondary)
                        .multilineTextAlignment(.center)
                }
                curvedTextField("email", text: $email, symbol: "envelope", field: .email, contentType: .emailAddress)
                if resetCodeSent {
                    if resetRecoveryLinked {
                        PasswordResetLinkBadge()
                    } else {
                        if resetSupportsRecoveryLink {
                            PasswordResetAwaitingLinkBadge()
                        }
                        curvedTextField("verification code", text: resetCodeBinding, symbol: "number", field: .verificationCode, contentType: .oneTimeCode)
                            .keyboardType(.numberPad)
                        CombinationCodeDisplay(code: resetDigits, label: "reset lock")
                    }
                    curvedSecureField(
                        "new password",
                        text: $password,
                        symbol: "lock.rotation",
                        field: .password,
                        visible: $passwordVisible,
                        contentType: .newPassword
                    )
                    PasswordStrengthView(password: password, confirmation: confirmation)
                    curvedSecureField(
                        "confirm new password",
                        text: $confirmation,
                        symbol: "checkmark.shield",
                        field: .confirmation,
                        visible: $confirmationVisible,
                        contentType: .newPassword
                    )
                    if let debugResetCode {
                        Text("development reset code: \(debugResetCode)")
                            .font(.caption2)
                            .foregroundStyle(VentureTheme.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                if let notice {
                    authNotice(notice)
                }
                Button(resettingPassword ? "working…" : resetButtonTitle, action: resetPassword)
                    .buttonStyle(GlowBorderButtonStyle())
                    .disabled(!recoveryCanContinue || resettingPassword)
                    .opacity(recoveryCanContinue ? 1 : 0.42)
            }
            .padding(.vertical, 14)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var recoveryIsValid: Bool {
        validEmail && passwordStrength.isAcceptable && password == confirmation
    }

    private var recoveryCanContinue: Bool {
        resetCodeSent
            ? recoveryIsValid && (resetRecoveryLinked || resetDigits.count >= 6)
            : validEmail
    }

    private var resetSupportsRecoveryLink: Bool {
        authConfiguration.supabase != nil && debugResetCode == nil
    }

    private var resetStartInstructions: String {
        authConfiguration.supabase != nil
            ? "send a secure email link before changing the password."
            : "send a secure reset code before changing the password."
    }

    private var resetPasswordInstructions: String {
        if resetRecoveryLinked { return "reset link verified. choose a new password." }
        return resetSupportsRecoveryLink
            ? "open the reset link or enter the email code."
            : "enter the email code and choose a new password."
    }

    private var resetButtonTitle: String {
        if resetCodeSent { return "reset password" }
        return authConfiguration.supabase != nil ? "send reset link" : "send reset code"
    }

    private var validEmail: Bool {
        EmailAddressValidator.isValid(EmailAddressValidator.normalized(email))
    }

    private var verificationHelp: String {
        if let debugVerificationCode {
            return "development build code: \(debugVerificationCode). Production sends this by email through the account backend."
        }
        return "Enter the six-digit code sent by the configured account service."
    }

    private var verificationDigits: String {
        String(verificationCode.filter(\.isNumber).prefix(6))
    }

    private var resetDigits: String {
        String(resetCode.filter(\.isNumber).prefix(6))
    }

    private var verificationCodeBinding: Binding<String> {
        Binding(
            get: { verificationCode },
            set: { verificationCode = String($0.filter(\.isNumber).prefix(6)) }
        )
    }

    private var resetCodeBinding: Binding<String> {
        Binding(
            get: { resetCode },
            set: { resetCode = String($0.filter(\.isNumber).prefix(6)) }
        )
    }

    private var legalAcceptanceRow: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    acceptedLegalTerms.toggle()
                }
                acceptedLegalTerms ? Haptics.success() : Haptics.strong()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(acceptedLegalTerms ? VentureTheme.primaryFill : VentureTheme.surface)
                            .frame(width: 28, height: 28)
                        Image(systemName: acceptedLegalTerms ? "checkmark" : "circle")
                            .font(.system(size: acceptedLegalTerms ? 12 : 13, weight: .semibold))
                            .foregroundStyle(acceptedLegalTerms ? Color.white : VentureTheme.secondary)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("i agree to the terms of service")
                        Text("and privacy policy")
                    }
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 56)
                .background(VentureTheme.surfaceMuted.opacity(acceptedLegalTerms ? 1 : 0.5), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(acceptedLegalTerms ? VentureTheme.primaryFill.opacity(0.24) : VentureTheme.line, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(HapticPlainButtonStyle())

            HStack(spacing: 8) {
                legalButton("terms", document: .terms)
                legalButton("privacy", document: .privacy)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Accept Terms of Service and Privacy Policy")
        .accessibilityValue(acceptedLegalTerms ? "accepted" : "not accepted")
    }

    private func legalButton(_ title: String, document: LegalDocument) -> some View {
        Button(title) { legalDocument = document }
            .font(.caption2.weight(.semibold))
            .frame(height: 32)
            .buttonStyle(HapticPlainButtonStyle())
    }

    private func authNotice(_ message: String, subtle: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: subtle ? "info.circle" : "exclamationmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
            Text(message)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(subtle ? VentureTheme.secondary : VentureTheme.ink)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VentureTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(subtle ? VentureTheme.line : VentureTheme.warm.opacity(0.42), lineWidth: 0.8)
        }
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    private func legalFooterButton(_ title: String, document: LegalDocument) -> some View {
        Button(title) { legalDocument = document }
            .font(.system(size: 10, weight: .medium))
            .frame(height: 30)
            .buttonStyle(HapticPlainButtonStyle())
    }

    private func providerButton<Icon: View>(
        _ title: String,
        primary: Bool = false,
        @ViewBuilder icon: () -> Icon,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon().frame(width: 22, height: 22)
                Text(title)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .opacity(0.65)
            }
        }
        .buttonStyle(AnyVentureButtonStyle(primary: primary))
    }

    private func curvedTextField(_ title: String, text: Binding<String>, symbol: String, field: Field, contentType: UITextContentType?) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol).foregroundStyle(VentureTheme.secondary).frame(width: 19)
            TextField(title, text: text)
                .textContentType(contentType)
                .textInputAutocapitalization(field == .name ? .words : .never)
                .keyboardType(field == .email ? .emailAddress : .default)
                .submitLabel(submitLabel(for: field))
                .onSubmit { submitField(field) }
                .autocorrectionDisabled()
                .privacySensitive(field == .email)
                .focused($focusedField, equals: field)
        }
        .modifier(AuthFieldBackground(focused: focusedField == field))
    }

    private func curvedSecureField(
        _ title: String,
        text: Binding<String>,
        symbol: String,
        field: Field,
        visible: Binding<Bool>,
        contentType: UITextContentType
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol).foregroundStyle(VentureTheme.secondary).frame(width: 19)
            Group {
                if visible.wrappedValue {
                    TextField(title, text: text)
                } else {
                    SecureField(title, text: text)
                }
            }
            .textContentType(contentType)
            .textInputAutocapitalization(.never)
            .submitLabel(submitLabel(for: field))
            .onSubmit { submitField(field) }
            .autocorrectionDisabled()
            .focused($focusedField, equals: field)
            .privacySensitive()

            Button {
                visible.wrappedValue.toggle()
            } label: {
                Image(systemName: visible.wrappedValue ? "eye.slash" : "eye")
                    .foregroundStyle(VentureTheme.secondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(HapticPlainButtonStyle())
            .accessibilityLabel(visible.wrappedValue ? "Hide password" : "Show password")
        }
        .modifier(AuthFieldBackground(focused: focusedField == field))
    }

    private func authSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(VentureTheme.secondary)
                    .padding(.leading, 4)
            }
            content()
        }
    }

    private func submitLabel(for field: Field) -> SubmitLabel {
        switch (mode, field) {
        case (.signUp, .name), (.signUp, .email), (.signUp, .password), (.signIn, .email):
            .next
        default:
            .done
        }
    }

    private func submitField(_ field: Field) {
        switch (mode, field) {
        case (.signUp, .name):
            focusedField = .email
        case (.signUp, .email):
            focusedField = .password
        case (.signUp, .password):
            focusedField = .confirmation
        case (.signIn, .email):
            focusedField = .password
        case (.signUp, .confirmation), (.signIn, .password):
            submitEmail()
        default:
            focusedField = nil
        }
    }

    private var signInIdentity: some View {
        VStack(spacing: 4) {
            LivingPortalView(size: 58, intensity: 0.72, activity: 0.36, motion: 1.4, interactive: false)
            VStack(spacing: 1) {
                Text("your venture account")
                    .font(.footnote.weight(.semibold))
                Text("sign in to continue your timeline")
                    .font(.caption2)
                    .foregroundStyle(VentureTheme.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    private func showEmail() {
        guard authConfiguration.supportsAccountFlow else {
            completeAuthentication()
            return
        }
        notice = nil
        Haptics.soft()
        withAnimation(.spring(response: 0.64, dampingFraction: 0.86)) { route = .email }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            focusedField = mode == .signUp ? .name : .email
        }
    }

    private func providerUnavailable(_ provider: String) {
        Haptics.strong()
        withAnimation(.easeInOut(duration: 0.2)) {
            notice = "\(provider) sign-in needs its provider configuration. Email sign-in is ready now."
        }
    }

    private func showProviders() {
        focusedField = nil
        notice = nil
        verificationCode = ""
        withAnimation(.spring(response: 0.64, dampingFraction: 0.86)) { route = .providers }
    }

    private func showRecovery() {
        notice = nil
        password = ""
        confirmation = ""
        resetCode = ""
        resetCodeSent = false
        resetRecoveryLinked = false
        debugResetCode = nil
        passwordVisible = false
        confirmationVisible = false
        withAnimation(.spring(response: 0.64, dampingFraction: 0.86)) { route = .recovery }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(360))
            focusedField = .email
        }
    }

    private func toggleMode() {
        Haptics.selected()
        notice = nil
        passwordVisible = false
        confirmationVisible = false
        if mode == .signIn { acceptedLegalTerms = false }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
            mode = mode == .signUp ? .signIn : .signUp
        }
    }

    private func submitEmail() {
        guard formIsValid else {
            notice = mode == .signUp
                ? "Use a valid email, matching strong password, and accept the terms before creating an account."
                : "Enter a valid email and password."
            return
        }
        if let lockedUntil, lockedUntil > .now {
            notice = "Too many attempts. Wait before trying again."
            return
        }
        authWorking = true
        focusedField = nil
        Task { @MainActor in
            do {
                switch mode {
                case .signUp:
                    let outcome = try await authService.signUp(name: name, email: email, password: password, consent: .current())
                    guard outcome.requiresEmailVerification else {
                        _ = try await authService.signIn(email: outcome.email, password: password)
                        failedAttempts = 0
                        lockedUntil = nil
                        completeAuthentication()
                        authWorking = false
                        return
                    }
                    pendingVerificationEmail = outcome.email
                    debugVerificationCode = outcome.debugVerificationCode
                    verificationCode = ""
                    notice = outcome.debugVerificationCode == nil
                        ? "Check your inbox for the verification code."
                        : "Email verification is required before this account can continue."
                    withAnimation(.spring(response: 0.58, dampingFraction: 0.86)) { route = .verifyEmail }
                    try? await Task.sleep(for: .milliseconds(300))
                    focusedField = .verificationCode
                case .signIn:
                    _ = try await authService.signIn(email: email, password: password)
                    failedAttempts = 0
                    lockedUntil = nil
                    completeAuthentication()
                }
                Haptics.success()
            } catch AccountAuthError.emailNotVerified {
                pendingVerificationEmail = EmailAddressValidator.normalized(email)
                notice = "Verify your email before signing in."
                withAnimation(.spring(response: 0.58, dampingFraction: 0.86)) { route = .verifyEmail }
                Haptics.soft()
            } catch let authError as AccountAuthError where authError == .wrongPassword || authError == .accountNotFound {
                registerFailedAttempt()
                notice = authError.errorDescription ?? "The account could not be verified."
                Haptics.soft()
            } catch {
                notice = (error as? LocalizedError)?.errorDescription ?? "The account could not be verified securely."
                Haptics.soft()
            }
            authWorking = false
        }
    }

    private func verifyEmail() {
        guard verificationDigits.count >= 6, !authWorking else { return }
        authWorking = true
        focusedField = nil
        let targetEmail = pendingVerificationEmail.isEmpty ? email : pendingVerificationEmail
        Task { @MainActor in
            do {
                _ = try await authService.verifyEmail(email: targetEmail, code: verificationDigits)
                failedAttempts = 0
                lockedUntil = nil
                completeAuthentication()
            } catch {
                notice = (error as? LocalizedError)?.errorDescription ?? "The email could not be verified."
                Haptics.soft()
            }
            authWorking = false
        }
    }

    private func resendVerification() {
        guard !authWorking else { return }
        authWorking = true
        let targetEmail = pendingVerificationEmail.isEmpty ? email : pendingVerificationEmail
        Task { @MainActor in
            do {
                debugVerificationCode = try await authService.resendVerification(email: targetEmail)
                notice = debugVerificationCode == nil ? "A new code was sent." : "A new development code was created."
                Haptics.success()
            } catch {
                notice = (error as? LocalizedError)?.errorDescription ?? "A new code could not be sent."
                Haptics.soft()
            }
            authWorking = false
        }
    }

    private func resetPassword() {
        guard recoveryCanContinue, !resettingPassword else { return }
        resettingPassword = true
        focusedField = nil
        Task { @MainActor in
            do {
                if resetCodeSent {
                    if resetRecoveryLinked {
                        try await authService.resetPasswordWithRecoveryLink(newPassword: password)
                    } else {
                        try await authService.resetPassword(email: email, code: resetDigits, newPassword: password)
                    }
                    mode = .signIn
                    notice = "Password reset. Sign in with the new password."
                    password = ""
                    confirmation = ""
                    resetCode = ""
                    resetCodeSent = false
                    resetRecoveryLinked = false
                    debugResetCode = nil
                    withAnimation(.spring(response: 0.58, dampingFraction: 0.86)) { route = .email }
                    Haptics.success()
                } else {
                    debugResetCode = try await authService.requestPasswordReset(email: email)
                    resetCodeSent = true
                    notice = resetSupportsRecoveryLink ? "Check your inbox for the reset link or code." : "A reset code was created."
                    Haptics.success()
                    try? await Task.sleep(for: .milliseconds(300))
                    focusedField = .verificationCode
                }
            } catch {
                notice = (error as? LocalizedError)?.errorDescription ?? "The password could not be reset securely."
                Haptics.soft()
            }
            resettingPassword = false
        }
    }

    private func preparePendingPasswordReset() {
        Task { @MainActor in
            if let incomingNotice = AuthDeepLinkNoticeStore.consume() {
                mode = .signIn
                password = ""
                confirmation = ""
                resetCode = ""
                resetCodeSent = false
                resetRecoveryLinked = false
                debugResetCode = nil
                notice = incomingNotice
                withAnimation(.spring(response: 0.64, dampingFraction: 0.86)) {
                    route = .recovery
                }
            }
            guard let context = await authService.pendingPasswordResetContext() else { return }
            mode = .signIn
            if !context.email.isEmpty {
                email = context.email
            }
            password = ""
            confirmation = ""
            resetCode = ""
            resetCodeSent = true
            resetRecoveryLinked = true
            debugResetCode = nil
            notice = "Reset link verified. Create a new password."
            withAnimation(.spring(response: 0.64, dampingFraction: 0.86)) {
                route = .recovery
            }
            try? await Task.sleep(for: .milliseconds(360))
            focusedField = .password
        }
    }

    private func registerFailedAttempt() {
        failedAttempts += 1
        if failedAttempts >= 5 {
            lockedUntil = .now.addingTimeInterval(30)
            failedAttempts = 0
        }
    }

    private func completeAuthentication() {
        guard !enteringApp else { return }
        focusedField = nil
        Haptics.success()
        withAnimation(.spring(response: 0.68, dampingFraction: 0.84)) {
            enteringApp = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(680))
            onAuthenticated()
        }
    }
}

private enum AuthRoute { case providers, email, recovery, verifyEmail }
private enum AuthMode: Equatable { case signUp, signIn }
private enum Field { case name, email, password, confirmation, verificationCode }

private struct GoogleProviderMark: View {
    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.08, to: 0.28)
                .stroke(Color(red: 0.251, green: 0.522, blue: 0.957), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                .rotationEffect(.degrees(-18))
            Circle()
                .trim(from: 0.29, to: 0.49)
                .stroke(Color(red: 0.984, green: 0.737, blue: 0.020), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                .rotationEffect(.degrees(-18))
            Circle()
                .trim(from: 0.50, to: 0.71)
                .stroke(Color(red: 0.204, green: 0.659, blue: 0.325), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                .rotationEffect(.degrees(-18))
            Circle()
                .trim(from: 0.72, to: 0.97)
                .stroke(Color(red: 0.918, green: 0.263, blue: 0.208), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                .rotationEffect(.degrees(-18))
            RoundedRectangle(cornerRadius: 1.4, style: .continuous)
                .fill(Color(red: 0.251, green: 0.522, blue: 0.957))
                .frame(width: 9.5, height: 3.2)
                .offset(x: 4.6, y: 0.5)
            RoundedRectangle(cornerRadius: 1.4, style: .continuous)
                .fill(Color(red: 0.251, green: 0.522, blue: 0.957))
                .frame(width: 3.2, height: 8.2)
                .offset(x: 8.0, y: 3.0)
        }
        .frame(width: 21, height: 21)
        .accessibilityHidden(true)
    }
}

private struct AnyVentureButtonStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .foregroundStyle(primary ? Color.white : VentureTheme.ink)
            .background(primary ? VentureTheme.primaryFill : VentureTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(primary ? VentureTheme.primaryFill : VentureTheme.line, lineWidth: 0.8)
            }
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: configuration.isPressed)
    }
}

private struct AuthFieldBackground: ViewModifier {
    let focused: Bool

    func body(content: Content) -> some View {
        content
            .font(.subheadline)
            .foregroundStyle(VentureTheme.ink)
            .padding(.horizontal, 17)
            .frame(height: 56)
            .background(VentureTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(focused ? VentureTheme.primaryFill.opacity(0.65) : VentureTheme.line, lineWidth: focused ? 1.2 : 0.8)
            }
            .shadow(color: focused ? VentureTheme.primaryFill.opacity(0.06) : .clear, radius: 10, y: 3)
            .animation(.easeInOut(duration: 0.2), value: focused)
    }
}

private extension View {
    func authReveal(_ visible: Bool, delay: Double) -> some View {
        modifier(AuthRevealModifier(visible: visible, delay: delay))
    }
}

private struct AuthRevealModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let visible: Bool
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 12)
            .animation(.easeOut(duration: reduceMotion ? 0.2 : 0.45).delay(delay), value: visible)
    }
}

private struct AuthenticationPortalTransition: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    var body: some View {
        ZStack {
            VentureAtmosphereView().ignoresSafeArea()
            LivingPortalView(size: 220, intensity: 1.38, interactive: false)
                .scaleEffect(reduceMotion ? 1 : (expanded ? 7.2 : 0.55))
                .blur(radius: expanded && !reduceMotion ? 24 : 0)
                .opacity(expanded ? 0.9 : 1)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 0.72)) { expanded = true }
        }
        .accessibilityHidden(true)
    }
}

private struct AuthModeAtmosphere: View {
    let mode: AuthMode

    var body: some View {
        ZStack {
            LivingPortalView(
                size: mode == .signUp ? 360 : 290,
                intensity: mode == .signUp ? 0.32 : 0.44,
                activity: mode == .signUp ? 0.28 : 0.46,
                motion: 1.5,
                interactive: false
            )
            .hueRotation(mode == .signUp ? .degrees(0) : .degrees(42))
            .blur(radius: 18)
            .opacity(mode == .signUp ? 0.20 : 0.28)
            .offset(x: mode == .signUp ? -160 : 150, y: mode == .signUp ? 300 : -280)

            if mode == .signIn {
                Circle()
                    .fill(VentureTheme.sage.opacity(0.07))
                    .frame(width: 430, height: 430)
                    .blur(radius: 48)
                    .offset(x: -170, y: 280)
            }
        }
        .animation(.spring(response: 0.72, dampingFraction: 0.88), value: mode)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CombinationCodeDisplay: View {
    let code: String
    let label: String

    private var enteredCount: Int { min(code.count, 6) }

    private var digits: [String] {
        let entered = Array(code.prefix(6)).map(String.init)
        return entered + Array(repeating: "•", count: max(0, 6 - entered.count))
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: enteredCount == 6 ? "lock.open.fill" : "lock.rotation")
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.caption2.weight(.semibold))
                Spacer()
                Text("\(enteredCount) of 6")
                    .font(.caption2.monospacedDigit().weight(.semibold))
            }
            .foregroundStyle(VentureTheme.secondary)
            .padding(.horizontal, 3)

            HStack(spacing: 7) {
                ForEach(0..<6, id: \.self) { index in
                    Text(digits[index])
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(index < enteredCount ? VentureTheme.surfaceMuted : VentureTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(index < enteredCount ? VentureTheme.primaryFill.opacity(0.4) : VentureTheme.line, lineWidth: 0.8)
                        }
                        .animation(.easeInOut(duration: 0.18), value: code)
                }
            }
            ProgressView(value: Double(enteredCount), total: 6)
                .progressViewStyle(.linear)
                .tint(VentureTheme.primaryFill)
                .frame(height: 3)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(VentureTheme.surfaceMuted.opacity(0.45), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(VentureTheme.line, lineWidth: 0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(enteredCount) of 6 digits entered")
        .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: enteredCount)
    }
}

private struct PasswordResetLinkBadge: View {
    @State private var unlocked = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(VentureTheme.surfaceMuted)
                    .frame(width: 44, height: 44)
                Image(systemName: unlocked ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(VentureTheme.ink)
                    .contentTransition(.symbolEffect(.replace))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("reset link verified")
                    .font(.caption.weight(.semibold))
                Text("choose a new password to finish")
                    .font(.caption2)
                    .foregroundStyle(VentureTheme.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(VentureTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(VentureTheme.line, lineWidth: 0.8)
        }
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.62).delay(0.12)) {
                unlocked = true
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PasswordResetAwaitingLinkBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(VentureTheme.surfaceMuted)
                    .frame(width: 44, height: 44)
                Circle()
                    .stroke(VentureTheme.ink.opacity(pulse ? 0.16 : 0.36), lineWidth: 1.2)
                    .frame(width: pulse ? 42 : 30, height: pulse ? 42 : 30)
                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(VentureTheme.ink)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("secure link sent")
                    .font(.caption.weight(.semibold))
                Text("open it from your inbox to unlock reset")
                    .font(.caption2)
                    .foregroundStyle(VentureTheme.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(VentureTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(VentureTheme.line, lineWidth: 0.8)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityElement(children: .combine)
    }
}
