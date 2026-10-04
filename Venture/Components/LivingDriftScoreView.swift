import SwiftUI

struct LivingDriftScoreView: View {
    let score: Int
    let protected: Bool

    var body: some View {
        ZStack {
            LivingPortalView(size: 252, intensity: protected ? 0.76 : 1, activity: protected ? 0.12 : 0.26)
            VStack(spacing: 0) {
                Text("brain drift")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(VentureTheme.secondary)
                Text(score.formatted())
                    .font(.system(size: 60, weight: .regular, design: .rounded))
                    .tracking(-4)
                    .contentTransition(.numericText())
                    .foregroundStyle(VentureTheme.ink)
                Text(protected ? "shield active" : "stable today")
                    .font(.caption2)
                    .foregroundStyle(VentureTheme.secondary)
            }
            .allowsHitTesting(false)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Brain drift \(score), \(protected ? "shield active" : "stable today")")
    }
}
