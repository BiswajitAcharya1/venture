import SwiftUI

struct VentureAtmosphereView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            VentureTheme.background
            if reduceMotion {
                StaticAtmosphere()
            } else {
                TimelineView(.periodic(from: .now, by: 1.0 / 8.0)) { timeline in
                    AtmosphericCanvas(time: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
            LinearGradient(
                colors: [Color.white.opacity(0.36), .clear, VentureTheme.surfaceMuted.opacity(0.24)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct AtmosphericCanvas: View {
    let time: TimeInterval

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let radius = min(size.width, size.height) * 0.95
            let first = CGPoint(x: size.width * (0.12 + sin(time * 0.055) * 0.035), y: size.height * 0.18)
            let second = CGPoint(x: size.width * 0.9, y: size.height * (0.72 + cos(time * 0.04) * 0.035))
            drawGlow(context: context, center: first, radius: radius, color: VentureTheme.deepSurface.opacity(0.42))
            drawGlow(context: context, center: second, radius: radius * 0.9, color: Color(red: 0.90, green: 0.83, blue: 0.72).opacity(0.28))
        }
    }

    private func drawGlow(context: GraphicsContext, center: CGPoint, radius: CGFloat, color: Color) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [color, .clear]), center: center, startRadius: 0, endRadius: radius))
    }
}

private struct StaticAtmosphere: View {
    var body: some View {
        ZStack {
            RadialGradient(colors: [VentureTheme.deepSurface.opacity(0.42), .clear], center: .topLeading, startRadius: 0, endRadius: 500)
            RadialGradient(colors: [Color(red: 0.90, green: 0.83, blue: 0.72).opacity(0.28), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 520)
        }
    }
}
