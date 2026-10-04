import SwiftUI

struct AppLockView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onUnlocked: () -> Void

    @State private var authenticating = false
    @State private var entering = false
    @State private var message: String?
    private let biometrics = BiometricService()

    var body: some View {
        ZStack {
            VentureAtmosphereView().ignoresSafeArea()

            if entering {
                LivingPortalView(size: 220, intensity: 1.4, interactive: false)
                    .scaleEffect(reduceMotion ? 1 : 7.2)
                    .blur(radius: reduceMotion ? 0 : 24)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
            }

            VStack(spacing: 0) {
                VStack(spacing: 3) {
                    Text("venture")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .tracking(-1.1)
                    Text("your measured history is locked")
                        .font(.caption2)
                        .foregroundStyle(VentureTheme.secondary)
                }
                .padding(.top, 34)

                Spacer()

                Button(action: unlock) {
                    ZStack {
                        LivingPortalView(size: 250, intensity: authenticating ? 1.2 : 0.92, interactive: false)
                            .allowsHitTesting(false)
                        if authenticating {
                            ProgressView()
                                .controlSize(.small)
                                .tint(VentureTheme.ink)
                        }
                    }
                }
                .frame(width: 290, height: 290)
                .contentShape(Circle())
                .buttonStyle(HapticPlainButtonStyle())
                .disabled(authenticating || entering)
                .accessibilityLabel("Unlock venture")
                .accessibilityHint("Unlocks the app")

                VStack(spacing: 6) {
                    Text("your private space")
                        .font(.system(size: 29, weight: .regular, design: .serif))
                        .tracking(-0.7)
                    Text(message ?? "tap the orb to unlock")
                        .font(.subheadline)
                        .foregroundStyle(message == nil ? VentureTheme.secondary : VentureTheme.warm)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 10)

                Spacer()

                Spacer().frame(height: 28)
            }
            .opacity(entering ? 0 : 1)
            .scaleEffect(entering && !reduceMotion ? 0.98 : 1)
        }
        .foregroundStyle(VentureTheme.ink)
    }

    private func unlock() {
        guard !authenticating, !entering else { return }
        authenticating = true
        message = nil
        Haptics.strong()
        Task { @MainActor in
            let success = await biometrics.authenticate(reason: "Unlock your private venture measurements")
            authenticating = false
            guard success else {
                message = "authentication was not completed"
                Haptics.soft()
                return
            }
            Haptics.success()
            withAnimation(.spring(response: 0.7, dampingFraction: 0.84)) { entering = true }
            try? await Task.sleep(for: .milliseconds(680))
            onUnlocked()
        }
    }
}
