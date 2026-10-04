import SwiftUI

struct BootstrapView: View {
    @State private var messageIndex = 0

    private let messages = [
        "securing your private space",
        "warming local intelligence",
        "preparing your baseline"
    ]

    var body: some View {
        ZStack {
            VentureAtmosphereView().ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()
                LivingPortalView(size: 210, intensity: 0.82)
                VStack(spacing: 7) {
                    Text("venture")
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                        .tracking(-1.3)
                    Text(messages[messageIndex])
                        .font(.caption)
                        .foregroundStyle(VentureTheme.secondary)
                        .contentTransition(.opacity)
                        .id(messageIndex)
                }
                Spacer()
                ProgressView()
                    .controlSize(.small)
                    .tint(VentureTheme.secondary)
                    .padding(.bottom, 34)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(650))
                withAnimation(.easeInOut(duration: 0.25)) {
                    messageIndex = min(messageIndex + 1, messages.count - 1)
                }
                if messageIndex == messages.count - 1 { return }
            }
        }
    }
}
