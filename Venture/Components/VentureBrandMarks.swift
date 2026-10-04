import SwiftUI

struct VentureAccountMark: View {
    var body: some View {
        ZStack {
            Circle().fill(VentureTheme.surface)
            Circle()
                .stroke(VentureTheme.ink.opacity(0.18), lineWidth: 1)
                .padding(6)
            AccountSignalGlyph()
                .stroke(VentureTheme.ink, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                .padding(9)
            Circle()
                .fill(VentureTheme.primaryFill)
                .frame(width: 4.5, height: 4.5)
        }
        .frame(width: 36, height: 36)
    }
}

struct GoogleMark: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 24
            context.scaleBy(x: scale, y: scale)

            let center = CGPoint(x: 12, y: 12)
            let radius: CGFloat = 8.1
            let stroke = StrokeStyle(lineWidth: 3.6, lineCap: .butt, lineJoin: .round)

            drawArc(in: &context, center: center, radius: radius, from: -43, to: -136, color: .googleRed, stroke: stroke)
            drawArc(in: &context, center: center, radius: radius, from: -136, to: -193, color: .googleYellow, stroke: stroke)
            drawArc(in: &context, center: center, radius: radius, from: -193, to: -310, color: .googleGreen, stroke: stroke)
            drawArc(in: &context, center: center, radius: radius, from: -310, to: -360, color: .googleBlue, stroke: stroke)

            var crossbar = Path()
            crossbar.move(to: CGPoint(x: 12, y: 12))
            crossbar.addLine(to: CGPoint(x: 20.4, y: 12))
            context.stroke(crossbar, with: .color(.googleBlue), style: stroke)
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }

    private func drawArc(
        in context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        from start: Double,
        to end: Double,
        color: Color,
        stroke: StrokeStyle
    ) {
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(start),
            endAngle: .degrees(end),
            clockwise: true
        )
        context.stroke(path, with: .color(color), style: stroke)
    }
}

private extension Color {
    static let googleBlue = Color(red: 0.259, green: 0.522, blue: 0.957)
    static let googleRed = Color(red: 0.918, green: 0.263, blue: 0.208)
    static let googleYellow = Color(red: 0.984, green: 0.737, blue: 0.020)
    static let googleGreen = Color(red: 0.204, green: 0.659, blue: 0.325)
}

private struct AccountSignalGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.16, y: rect.height * 0.55))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.84, y: rect.height * 0.45),
            control1: CGPoint(x: rect.width * 0.34, y: rect.height * 0.13),
            control2: CGPoint(x: rect.width * 0.65, y: rect.height * 0.13)
        )
        path.move(to: CGPoint(x: rect.width * 0.16, y: rect.height * 0.55))
        path.addCurve(
            to: CGPoint(x: rect.width * 0.84, y: rect.height * 0.45),
            control1: CGPoint(x: rect.width * 0.36, y: rect.height * 0.90),
            control2: CGPoint(x: rect.width * 0.66, y: rect.height * 0.90)
        )
        return path
    }
}
