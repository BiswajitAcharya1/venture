import SwiftUI

struct VentureAccountView: View {
    var locale: VentureLocale
    var onChooseLanguage: (() -> Void)? = nil
    var onContinue: (AuthSession?) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var code = ""
    @State private var consent = false
    @State private var signingIn = false
    @State private var verifying = false
    @State private var busy = false
    @State private var error = false
    @State private var legal: LegalDocument?
    private let auth = AccountAuthService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("venture").font(.system(size: 28, weight: .medium, design: .rounded)).tracking(-0.8)
                    Spacer()
                    if let onChooseLanguage {
                        Button(action: onChooseLanguage) {
                            Image(systemName: "globe").font(.system(size: 19, weight: .regular))
                                .foregroundStyle(VentureCanvas.accent).frame(width: 44, height: 44)
                                .ventureSurface(cornerRadius: 22)
                        }.accessibilityLabel(locale.t(.language)).accessibilityIdentifier("account-language-button")
                    }
                }.padding(.top, 14)
                HStack(spacing: 14) {
                    VentureAccountMark().frame(width: 40, height: 40).accessibilityHidden(true)
                    Text(locale.t(verifying ? .verify : signingIn ? .signIn : .account))
                        .font(.system(size: 30, weight: .regular, design: .rounded)).tracking(-0.7)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(.top, 10).padding(.bottom, 6)
                if verifying {
                    Text(email).foregroundStyle(VentureCanvas.muted)
                    field(.code, text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                } else {
                    VStack(spacing: 12) {
                        if !signingIn { field(.name, text: $name).textContentType(.name) }
                        field(.email, text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never).textContentType(.emailAddress)
                        HStack(spacing: 12) {
                            Image(systemName: "lock").font(.system(size: 16, weight: .regular)).foregroundStyle(VentureCanvas.muted).frame(width: 20)
                            SecureField(locale.t(.password), text: $password)
                                .textContentType(signingIn ? .password : .newPassword)
                        }.padding(.horizontal, 18).padding(.vertical, 16).ventureSurface(cornerRadius: 20)
                    }
                    if !signingIn {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(locale.t(.agree), isOn: $consent).font(.footnote).foregroundStyle(VentureCanvas.muted)
                            HStack(spacing: 24) {
                                Button(locale.t(.terms)) { legal = .terms }
                                Button(locale.t(.privacy)) { legal = .privacy }
                            }.font(.footnote.weight(.medium)).foregroundStyle(VentureCanvas.accent)
                        }
                    }
                }
                if error {
                    Label(locale.t(.retry), systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(VentureCanvas.accent).accessibilityIdentifier("auth-error")
                }
                if busy { ProgressView().tint(VentureCanvas.accent).frame(maxWidth: .infinity) }
                VentureAction(title: locale.t(verifying ? .verify : signingIn ? .signIn : .account)) { submit() }
                    .disabled(busy || (!verifying && (email.isEmpty || password.isEmpty || (!signingIn && !consent))))
                if !verifying {
                    Button(locale.t(signingIn ? .account : .signIn)) { signingIn.toggle(); error = false }
                        .font(.subheadline.weight(.medium)).foregroundStyle(VentureCanvas.accent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                Button {
                    Task { await auth.clearSession(); onContinue(nil) }
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle").font(.system(size: 20, weight: .light)).foregroundStyle(VentureCanvas.accent)
                        Text(locale.t(.guest)).font(.subheadline.weight(.medium))
                        Spacer()
                        Image(systemName: "arrow.right").font(.system(size: 14, weight: .medium)).foregroundStyle(VentureCanvas.muted)
                    }.padding(.horizontal, 22).padding(.vertical, 18).ventureSurface(cornerRadius: 24)
                }.disabled(busy).accessibilityIdentifier("continue-guest")
                Label(locale.t(.guestNote), systemImage: "lock.shield")
                    .font(.footnote).foregroundStyle(VentureCanvas.muted).fixedSize(horizontal: false, vertical: true)
            }.padding(24).frame(maxWidth: 480).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively).background(VentureCanvas.background)
            .foregroundStyle(VentureCanvas.ink).tint(VentureCanvas.accent)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: signingIn)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: verifying)
            .sheet(item: $legal) { kind in
                NavigationStack {
                    VStack(alignment: .leading, spacing: 28) {
                        Text(locale.t(.screening))
                        Text(locale.t(.guestNote))
                        Text(locale.t(.demo))
                        Text(locale.t(.voiceNotice))
                        HStack { Image(systemName: "lock.shield"); Text(locale.t(.account)); Spacer(); Text(locale.t(.saved)) }
                        HStack { Image(systemName: "mic"); Text(locale.t(.microphone)); Spacer(); Image(systemName: "trash") }
                        HStack { Image(systemName: "camera"); Text(locale.t(.camera)); Spacer(); Image(systemName: "trash") }
                        Spacer()
                    }.padding(28).background(VentureCanvas.background).foregroundStyle(VentureCanvas.ink)
                        .navigationTitle(locale.t(kind == .terms ? .terms : .privacy))
                        .toolbar { Button(locale.t(.done)) { legal = nil } }
                }
            }
    }

    private func field(_ key: VentureCopy, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: key == .email ? "envelope" : key == .code ? "key" : "person")
                .font(.system(size: 16, weight: .regular)).foregroundStyle(VentureCanvas.muted).frame(width: 20)
            TextField(locale.t(key), text: text).autocorrectionDisabled()
        }.padding(.horizontal, 18).padding(.vertical, 16).ventureSurface(cornerRadius: 20)
    }

    private func submit() {
        guard !busy else { return }
        busy = true; error = false
        Task {
            defer { busy = false }
            do {
                if verifying { onContinue(try await auth.verifyEmail(email: email, code: code)) }
                else if signingIn { onContinue(try await auth.signIn(email: email, password: password)) }
                else {
                    let outcome = try await auth.signUp(name: name, email: email, password: password, consent: .current())
                    if outcome.requiresEmailVerification { verifying = true }
                    else { onContinue(await auth.currentSession()) }
                }
            } catch { self.error = true; Haptics.soft() }
        }
    }
}
