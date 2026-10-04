import SwiftUI

struct LivingPortalView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isTouching = false
    @State private var touchPoint = CGPoint(x: 0.5, y: 0.5)

    var size: CGFloat = 240
    var intensity: Double = 1
    var activity: Double = 0
    var motion: Double = 1
    var interactive = true
    var outlineProgress: CGFloat = 0

    var body: some View {
        Group {
            if interactive {
                portal
                    .simultaneousGesture(interactionGesture)
            } else {
                portal
                    .allowsHitTesting(false)
            }
        }
        .accessibilityHidden(true)
    }

    private var portal: some View {
        Group {
            if reduceMotion {
                artwork(time: 0)
            } else {
                TimelineView(.animation(minimumInterval: refreshInterval)) { timeline in
                    artwork(time: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
    }

    private var refreshInterval: TimeInterval {
        if size > 200 {
            return 1.0 / 20.0
        }
        return motion > 1.5 ? 1.0 / 24.0 : 1.0 / 20.0
    }

    private func artwork(time: TimeInterval) -> some View {
        PortalCanvas(
            time: time,
            intensity: intensity,
            activity: max(0, min(1, activity)),
            motion: reduceMotion ? 0 : max(0, min(3.5, motion)),
            touchPoint: touchPoint,
            isTouching: isTouching,
            visualDiameter: size,
            outlineProgress: outlineProgress
        )
        .frame(width: size * 1.36, height: size * 1.36)
    }

    private var interactionGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .updating($isTouching) { _, state, _ in
                guard interactive else { return }
                state = true
            }
            .onChanged { value in
                guard interactive else { return }
                touchPoint = CGPoint(
                    x: max(0, min(1, value.location.x / size)),
                    y: max(0, min(1, value.location.y / size))
                )
            }
            .onEnded { _ in
                guard interactive else { return }
                withAnimation(reduceMotion ? nil : .spring(response: 0.65, dampingFraction: 0.86)) {
                    touchPoint = CGPoint(x: 0.5, y: 0.5)
                }
            }
    }

}

private struct PortalCanvas: View {
    let time: TimeInterval
    let intensity: Double
    let activity: Double
    let motion: Double
    let touchPoint: CGPoint
    let isTouching: Bool
    let visualDiameter: CGFloat
    let outlineProgress: CGFloat

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let phase = time * (0.18 + motion * 0.065)
            let energy = min(1.2, activity * 0.65 + (isTouching ? 0.22 : 0))
            let movement = motion / 3.5
            let responsiveCenter = CGPoint(
                x: center.x + (touchPoint.x - 0.5) * visualDiameter * (isTouching ? 0.08 : 0)
                    + CGFloat(sin(phase * 0.71)) * visualDiameter * 0.013 * movement,
                y: center.y + (touchPoint.y - 0.5) * visualDiameter * (isTouching ? 0.08 : 0)
                    + CGFloat(cos(phase * 0.59)) * visualDiameter * 0.011 * movement
            )
            let breath = 1 + sin(phase * 0.9) * 0.018 * movement
            let radius = visualDiameter * CGFloat(0.385 + energy * 0.012) * breath
            let shell = organicPath(center: responsiveCenter, radius: radius, phase: phase, energy: energy)
            let haloRadius = radius * 1.62
            let halo = CGRect(
                x: responsiveCenter.x - haloRadius,
                y: responsiveCenter.y - haloRadius,
                width: haloRadius * 2,
                height: haloRadius * 2
            )

            context.fill(
                Path(ellipseIn: halo),
                with: .radialGradient(
                    Gradient(colors: [VentureTheme.deepSurface.opacity(0.40 * intensity), .clear]),
                    center: responsiveCenter,
                    startRadius: radius * 0.65,
                    endRadius: haloRadius
                )
            )

            context.drawLayer { shadow in
                shadow.addFilter(.blur(radius: visualDiameter * 0.052))
                let ground = CGRect(
                    x: responsiveCenter.x - radius * 0.72,
                    y: responsiveCenter.y + radius * 0.87,
                    width: radius * 1.44,
                    height: radius * 0.12
                )
                shadow.fill(Path(ellipseIn: ground), with: .color(VentureTheme.sage.opacity(0.17)))
            }

            context.fill(
                shell,
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: Color(red: 1, green: 0.993, blue: 0.979), location: 0),
                        .init(color: Color(red: 0.941, green: 0.906, blue: 0.973), location: 0.30),
                        .init(color: Color(red: 0.812, green: 0.753, blue: 0.886), location: 0.68),
                        .init(color: Color(red: 0.631, green: 0.549, blue: 0.745), location: 0.92),
                        .init(color: Color(red: 0.859, green: 0.792, blue: 0.906), location: 1)
                    ]),
                    center: CGPoint(x: responsiveCenter.x - radius * 0.38, y: responsiveCenter.y - radius * 0.48),
                    startRadius: 0,
                    endRadius: radius * 1.72
                )
            )

            context.drawLayer { pearl in
                pearl.clip(to: shell)

                for index in 0..<2 {
                    let offset = Double(index) * 2.4
                    let drift = CGFloat(sin(phase * 0.65 + offset)) * radius * 0.12 * movement
                    var ribbon = Path()
                    ribbon.move(to: CGPoint(x: responsiveCenter.x - radius * 1.1, y: responsiveCenter.y + radius * 0.35 + drift))
                    ribbon.addCurve(
                        to: CGPoint(x: responsiveCenter.x + radius * 1.1, y: responsiveCenter.y - radius * 0.52 + drift),
                        control1: CGPoint(x: responsiveCenter.x - radius * 0.35, y: responsiveCenter.y - radius * 0.72 - drift),
                        control2: CGPoint(x: responsiveCenter.x + radius * 0.22, y: responsiveCenter.y + radius * 0.60 + drift)
                    )
                    pearl.drawLayer { veil in
                        veil.addFilter(.blur(radius: radius * 0.11))
                        veil.stroke(
                            ribbon,
                            with: .linearGradient(
                                Gradient(colors: [Color.white.opacity(0.34), VentureTheme.warm.opacity(0.10), Color.white.opacity(0.22)]),
                                startPoint: CGPoint(x: responsiveCenter.x - radius, y: responsiveCenter.y - radius),
                                endPoint: CGPoint(x: responsiveCenter.x + radius, y: responsiveCenter.y + radius)
                            ),
                            lineWidth: radius * (index == 0 ? 0.26 : 0.15)
                        )
                    }
                }

                let highlightCenter = CGPoint(
                    x: responsiveCenter.x - radius * (0.32 + CGFloat(sin(phase)) * 0.045 * movement),
                    y: responsiveCenter.y - radius * 0.47
                )
                let highlight = CGRect(
                    x: highlightCenter.x - radius * 0.53,
                    y: highlightCenter.y - radius * 0.30,
                    width: radius * 1.06,
                    height: radius * 0.60
                )
                pearl.addFilter(.blur(radius: radius * 0.065))
                pearl.fill(
                    Path(ellipseIn: highlight),
                    with: .radialGradient(
                        Gradient(colors: [Color.white.opacity(min(0.88, 0.62 * intensity)), .clear]),
                        center: highlightCenter,
                        startRadius: 0,
                        endRadius: radius * 0.60
                    )
                )
            }

            context.stroke(
                shell,
                with: .linearGradient(
                    Gradient(colors: [Color.white.opacity(0.92), VentureTheme.sage.opacity(0.18), Color.white.opacity(0.54)]),
                    startPoint: CGPoint(x: responsiveCenter.x - radius, y: responsiveCenter.y - radius),
                    endPoint: CGPoint(x: responsiveCenter.x + radius, y: responsiveCenter.y + radius)
                ),
                lineWidth: max(0.55, visualDiameter * 0.003)
            )

            let progress = min(1, max(0, outlineProgress))
            if progress > 0 {
                context.stroke(
                    shell.trimmedPath(from: 0, to: progress),
                    with: .color(VentureTheme.primaryFill.opacity(0.64)),
                    style: StrokeStyle(lineWidth: max(0.8, visualDiameter * 0.005), lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    private func organicPath(center: CGPoint, radius: CGFloat, phase: Double, energy: Double) -> Path {
        let count = 72
        let points = (0..<count).map { index -> CGPoint in
            let angle = Double(index) / Double(count) * Double.pi * 2
            let movement = 0.45 + motion * 0.15
            let modulation = 1
                + (0.035 + energy * 0.018) * movement * sin(angle * 3 + phase)
                + (0.020 + energy * 0.012) * movement * sin(angle * 5 - phase * 1.35)
                + 0.012 * movement * cos(angle * 2 + phase * 0.7)
            let xScale = 1 + 0.018 * movement * sin(phase * 0.8)
            let yScale = 1 + 0.016 * movement * cos(phase * 0.67)
            return CGPoint(
                x: center.x + cos(angle) * radius * modulation * xScale,
                y: center.y + sin(angle) * radius * modulation * yScale
            )
        }

        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: midpoint(last, first))
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            path.addQuadCurve(to: midpoint(current, next), control: current)
        }
        path.closeSubpath()
        return path
    }

    private func midpoint(_ first: CGPoint, _ second: CGPoint) -> CGPoint {
        CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
    }
}

struct VenturePrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [VentureTheme.primaryFill, VentureTheme.primaryFill.opacity(0.94)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
            .overlay { Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.8) }
            .shadow(color: VentureTheme.primaryFill.opacity(configuration.isPressed ? 0.08 : 0.16), radius: 12, y: configuration.isPressed ? 2 : 6)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.65), trigger: configuration.isPressed)
    }
}

struct VentureSecondaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(VentureTheme.ink)
            .background(VentureTheme.surface, in: Capsule())
            .overlay { Capsule().stroke(VentureTheme.line, lineWidth: 0.8) }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: configuration.isPressed)
    }
}

struct CurvedFieldBackground: ViewModifier {
    var focused = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 17)
            .frame(height: 54)
            .background(VentureTheme.surface.opacity(0.92), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(focused ? VentureTheme.primaryFill.opacity(0.66) : VentureTheme.line, lineWidth: focused ? 1.2 : 0.8)
            }
            .shadow(color: focused ? VentureTheme.primaryFill.opacity(0.08) : .clear, radius: 12)
    }
}
