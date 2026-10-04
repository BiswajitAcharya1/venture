import SwiftUI

struct BaselineIntroView: View {
    let onBegin: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            LivingPortalView(size: 150, intensity: 0.78)
            VStack(spacing: 7) {
                Text("find your baseline")
                    .font(.system(size: 32, weight: .regular, design: .serif))
                    .tracking(-0.7)
                Text("a short guided scan gives venture its first reference point. each task ends when it has enough usable input, and later signals are compared with you rather than population averages.")
                    .font(.subheadline)
                    .foregroundStyle(VentureTheme.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            VStack(spacing: 12) {
                baselineItem(symbol: "eye", text: "pupil alignment and light response")
                baselineItem(symbol: "waveform", text: "guided voice reading")
                baselineItem(symbol: "scope", text: "randomized memory and attention")
            }
            .padding(.top, 12)
            Spacer()
            Button("build my baseline", action: onBegin)
                .buttonStyle(VenturePrimaryButtonStyle())
            Text("you can skip any task. unmeasured signals stay unavailable.")
                .font(.caption2)
                .foregroundStyle(VentureTheme.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .foregroundStyle(VentureTheme.ink)
        .background(VentureTheme.background.ignoresSafeArea())
    }

    private func baselineItem(symbol: String, text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(VentureTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(VentureTheme.line, lineWidth: 0.8)
            }
    }
}
