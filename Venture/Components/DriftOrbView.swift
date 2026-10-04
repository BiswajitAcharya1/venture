import SwiftUI

struct DriftOrbView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var score: Int?
    var isActive = false
    var size: CGFloat = 230

    @State private var breathing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(VentureTheme.deepSurface.opacity(0.48))
                .blur(radius: 24)
                .scaleEffect(breathing ? 1.06 : 0.98)

            OrganicOrbShape(progress: breathing ? 1 : 0)
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1, green: 0.993, blue: 0.979),
                            Color(red: 0.941, green: 0.906, blue: 0.973),
                            Color(red: 0.812, green: 0.753, blue: 0.886),
                            Color(red: 0.859, green: 0.792, blue: 0.906)
                        ],
                        center: .topLeading,
                        startRadius: 8,
                        endRadius: size * 0.72
                    )
                )
                .overlay {
                    OrganicOrbShape(progress: breathing ? 1 : 0)
                        .stroke(.white.opacity(0.84), lineWidth: 0.85)
                }
                .shadow(color: VentureTheme.sage.opacity(0.16), radius: 18, y: 12)
                .padding(size * 0.11)

            if let score {
                VStack(spacing: 0) {
                    Text("brain drift")
                        .font(.caption2.weight(.semibold))
                    Text(score.formatted())
                        .font(.system(size: 62, weight: .regular, design: .rounded))
                        .tracking(-4)
                    Text(isActive ? "shield active" : "stable today")
                        .font(.caption2)
                        .foregroundStyle(VentureTheme.secondary)
                }
                .foregroundStyle(VentureTheme.ink)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("brain drift \(score), \(isActive ? "shield active" : "stable today")")
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            startBreathing()
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced {
                withAnimation(nil) { breathing = false }
            } else {
                startBreathing()
            }
        }
    }

    private func startBreathing() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 5.8).repeatForever(autoreverses: true)) {
            breathing = true
        }
    }
}

private struct OrganicOrbShape: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let inset = rect.width * 0.04
        let bounds = rect.insetBy(dx: inset, dy: inset)
        let offset = rect.width * 0.018 * progress
        var path = Path()
        path.move(to: CGPoint(x: bounds.midX, y: bounds.minY + offset))
        path.addCurve(
            to: CGPoint(x: bounds.maxX - offset, y: bounds.midY),
            control1: CGPoint(x: bounds.maxX * 0.77, y: bounds.minY - offset),
            control2: CGPoint(x: bounds.maxX + offset, y: bounds.minY + bounds.height * 0.25)
        )
        path.addCurve(
            to: CGPoint(x: bounds.midX - offset, y: bounds.maxY),
            control1: CGPoint(x: bounds.maxX, y: bounds.maxY * 0.76),
            control2: CGPoint(x: bounds.maxX * 0.72, y: bounds.maxY + offset)
        )
        path.addCurve(
            to: CGPoint(x: bounds.minX + offset, y: bounds.midY - offset),
            control1: CGPoint(x: bounds.minX + bounds.width * 0.25, y: bounds.maxY),
            control2: CGPoint(x: bounds.minX - offset, y: bounds.maxY * 0.72)
        )
        path.addCurve(
            to: CGPoint(x: bounds.midX, y: bounds.minY + offset),
            control1: CGPoint(x: bounds.minX, y: bounds.minY + bounds.height * 0.28),
            control2: CGPoint(x: bounds.minX + bounds.width * 0.26, y: bounds.minY)
        )
        path.closeSubpath()
        return path
    }
}

#Preview {
    DriftOrbView(score: 22)
        .padding()
        .background(VentureTheme.background)
}
