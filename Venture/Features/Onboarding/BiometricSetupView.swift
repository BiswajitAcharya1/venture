import SwiftUI

struct BiometricSetupView: View {
    let onContinue: () -> Void

    @State private var isAuthenticating = false
    private let biometrics = BiometricService()

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "faceid")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(VentureTheme.primaryFill)
                .frame(width: 92, height: 92)
                .background(VentureTheme.surfaceMuted, in: Circle())

            VStack(spacing: 7) {
                Text("protect your baseline")
                    .font(.system(size: 32, weight: .regular, design: .serif))
                    .tracking(-0.7)
                Text("use \(biometrics.availableKind().rawValue) to keep cognitive and health metrics private on this device.")
                    .font(.subheadline)
                    .foregroundStyle(VentureTheme.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Spacer()

            Button(isAuthenticating ? "verifying…" : "enable \(biometrics.availableKind().rawValue)") {
                Task {
                    isAuthenticating = true
                    _ = await biometrics.authenticate(reason: "Protect your venture baseline")
                    isAuthenticating = false
                    onContinue()
                }
            }
            .buttonStyle(VenturePrimaryButtonStyle())
            .disabled(isAuthenticating)

            Button("not now", action: onContinue)
                .font(.subheadline)
                .foregroundStyle(VentureTheme.secondary)
                .buttonStyle(HapticPlainButtonStyle())
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .foregroundStyle(VentureTheme.ink)
        .background(VentureTheme.background.ignoresSafeArea())
    }
}
