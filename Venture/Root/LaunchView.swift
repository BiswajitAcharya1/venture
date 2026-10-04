import SwiftUI

struct LaunchView: View {
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    @State private var entering = false
    @State private var entryTask: Task<Void, Never>?
    @State private var legalDocument: LegalDocument?

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width * 0.76, 310)
            let orbCenter = CGPoint(x: geometry.size.width / 2, y: geometry.size.height * 0.51)
            // Cover the farthest corner from the orb, including the safe areas.
            let fullScreenScale = hypot(geometry.size.width, geometry.size.height) * 3 / diameter

            ZStack {
                VentureAtmosphereView().ignoresSafeArea()

                VStack(spacing: 0) {
                    Text("venture")
                        .font(.system(size: 25, weight: .medium, design: .rounded))
                        .tracking(-1.2)
                        .padding(.top, 26)

                    Text("every mind holds worlds\ninvisible to others")
                        .font(.system(size: 29, weight: .regular, design: .serif))
                        .tracking(-0.7)
                        .lineSpacing(3)
                        .multilineTextAlignment(.center)
                        .padding(.top, 34)

                    Spacer()

                    HStack(spacing: 10) {
                        Text("tap to enter")
                            .font(.system(size: 13, weight: .medium))
                            .tracking(0.4)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(VentureTheme.secondary)
                    .padding(.bottom, 42)

                    HStack(spacing: 18) {
                        Button("terms") { legalDocument = .terms }
                            .frame(minWidth: 44, minHeight: 44)
                        Rectangle()
                            .fill(VentureTheme.line)
                            .frame(width: 1, height: 12)
                            .accessibilityHidden(true)
                        Button("privacy") { legalDocument = .privacy }
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(VentureTheme.secondary)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 28)
                .opacity(revealed && !entering ? 1 : 0)
                .offset(y: reduceMotion ? 0 : revealed ? entering ? -8 : 0 : 12)

                // The tapped orb stays in place as it expands into the screen.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                VentureTheme.surface,
                                VentureTheme.sage.opacity(0.35),
                                VentureTheme.warm.opacity(0.2)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: diameter / 2
                        )
                    )
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(entering && !reduceMotion ? fullScreenScale : 0.72)
                    .opacity(entering ? 1 : 0)
                    .position(orbCenter)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                Button(action: enter) {
                    LivingPortalView(
                        size: diameter,
                        intensity: entering ? 1.16 : 1,
                        activity: entering ? 0.7 : 0.18,
                        motion: entering ? 1.25 : 0.7,
                        interactive: false
                    )
                    .frame(width: diameter, height: diameter)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(entering)
                .scaleEffect(reduceMotion ? 1 : entering ? fullScreenScale : revealed ? 1 : 0.94)
                .rotationEffect(.degrees(entering && !reduceMotion ? 12 : 0))
                .blur(radius: entering && !reduceMotion ? 14 : 0)
                .opacity(revealed ? entering && reduceMotion ? 0 : 1 : 0)
                .position(orbCenter)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("launch-orb-button")
                .accessibilityLabel("enter venture")
                .accessibilityHint("tap to open account setup")
            }
            .foregroundStyle(VentureTheme.ink)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.8)) {
                revealed = true
            }
        }
        .onDisappear {
            entryTask?.cancel()
            entryTask = nil
        }
        .sheet(item: $legalDocument) { LegalDocumentView(document: $0) }
    }

    private func enter() {
        guard !entering else { return }
        Haptics.soft()
        let duration = reduceMotion ? 0.22 : 0.86
        withAnimation(
            reduceMotion
                ? .easeOut(duration: duration)
                : .timingCurve(0.66, 0, 0.2, 1, duration: duration)
        ) {
            entering = true
        }
        entryTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(duration))
                guard !Task.isCancelled else { return }
                onContinue()
            } catch {
                // Leaving the launch screen cancels its pending handoff.
            }
        }
    }
}
