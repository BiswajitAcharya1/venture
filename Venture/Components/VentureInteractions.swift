import SwiftUI

struct AnimatedBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(HapticPlainButtonStyle())
        .accessibilityLabel("Back")
    }
}

struct AnimatedCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(HapticPlainButtonStyle())
        .accessibilityLabel("Close")
    }

    private func close() {
        Haptics.progress()
        action()
    }
}

struct RotatingAssistantButton: View {
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            Haptics.progress()
            isExpanded.toggle()
        } label: {
            Image(systemName: isExpanded ? "xmark" : "bubble.left.and.bubble.right.fill")
                .font(.system(size: 19, weight: .medium))
                .frame(width: 52, height: 52)
                .foregroundStyle(.white)
                .background(VentureTheme.primaryFill, in: Circle())
                .overlay { Circle().stroke(.white.opacity(0.2), lineWidth: 0.7) }
        }
        .buttonStyle(HapticPlainButtonStyle())
        .accessibilityLabel(isExpanded ? "Close venture" : "Ask venture")
    }
}

struct FlipText: View {
    let words: [String]
    var interval: Duration = .seconds(2.4)

    @State private var index = 0

    var body: some View {
        Text(words[index])
            .lineLimit(1)
            .contentTransition(.numericText())
            .task {
                guard words.count > 1 else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: interval)
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                        index = (index + 1) % words.count
                    }
                }
            }
    }
}

struct VanishingPromptField: View {
    @Binding var text: String
    let placeholders: [String]
    let isResponding: Bool
    let onSubmit: (String) -> Void
    let onStop: () -> Void

    @State private var placeholderIndex = 0
    @State private var vanishing = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholders[placeholderIndex])
                        .foregroundStyle(VentureTheme.secondary)
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .allowsHitTesting(false)
                }
                TextField("", text: $text)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(submit)
                    .disabled(isResponding)
            }
            .font(.subheadline)
            .opacity(vanishing ? 0 : 1)
            .blur(radius: vanishing ? 7 : 0)
            .offset(x: vanishing ? 24 : 0)

            Button(action: isResponding ? onStop : submit) {
                Image(systemName: isResponding ? "stop.fill" : "arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(.white)
                    .background(VentureTheme.primaryFill, in: Circle())
            }
            .buttonStyle(HapticPlainButtonStyle())
            .disabled(!isResponding && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(isResponding ? "Stop response" : "Send")
        }
        .padding(6)
        .padding(.leading, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().stroke(VentureTheme.line, lineWidth: 0.7) }
        .task {
            guard placeholders.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard text.isEmpty, !focused, !isResponding else { continue }
                withAnimation(.easeInOut(duration: 0.25)) {
                    placeholderIndex = (placeholderIndex + 1) % placeholders.count
                }
            }
        }
    }

    private func submit() {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !vanishing, !isResponding else { return }
        withAnimation(.easeOut(duration: 0.18)) { vanishing = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            text = ""
            vanishing = false
            onSubmit(value)
        }
    }
}

struct GlowBorderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(.white)
            .background(VentureTheme.primaryFill, in: Capsule())
            .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: configuration.isPressed)
    }
}

struct HapticPlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .sensoryFeedback(.impact(weight: .medium, intensity: 1), trigger: configuration.isPressed)
    }
}

struct StrongHapticButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: configuration.isPressed)
    }
}
