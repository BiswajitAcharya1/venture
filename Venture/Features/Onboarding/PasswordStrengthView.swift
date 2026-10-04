import SwiftUI

struct PasswordStrengthView: View {
    let password: String
    let confirmation: String

    private var strength: PasswordStrength { PasswordStrength(password: password) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("10+ chars · 3 types · no spaces")
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer()
                Text(strength.label)
                    .fontWeight(.semibold)
                    .foregroundStyle(statusColor)
            }
            .font(.caption)
            .foregroundStyle(VentureTheme.secondary)

            HStack(spacing: 5) {
                ForEach(1...4, id: \.self) { level in
                    Capsule()
                        .fill(level <= strength.score ? statusColor : VentureTheme.secondary.opacity(0.16))
                        .frame(height: 5)
                }
            }

            if !confirmation.isEmpty {
                requirement("passwords match", met: password == confirmation)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .animation(.easeInOut(duration: 0.2), value: strength.score)
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        switch strength.score {
        case 0, 1: return VentureTheme.warm
        case 2: return VentureTheme.secondary
        case 3: return VentureTheme.sage
        default: return VentureTheme.primaryFill
        }
    }

    private func requirement(_ title: String, met: Bool) -> some View {
        Label(title, systemImage: met ? "checkmark.circle.fill" : "circle")
            .font(.caption2)
            .foregroundStyle(met ? VentureTheme.ink : VentureTheme.secondary)
    }
}
