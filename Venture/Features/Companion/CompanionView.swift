import SwiftUI

struct CompanionView: View {
    @Bindable var store: VentureStore
    let onClose: () -> Void

    @State private var messages = [
        ChatMessage(role: .venture, text: "Ask anything, or ask me to explain a measured signal.")
    ]
    @State private var draft = ""
    @State private var isResponding = false
    @State private var responseTask: Task<Void, Never>?
    @State private var activeResponseID: UUID?
    @State private var prewarmTask: Task<Void, Never>?
    @State private var runtimeInfo = CompanionRuntimeInfo.current
    @State private var localModelPreparing = false

    private let companion = AdaptiveCompanionEngine()
    private let suggestions = [
        "what changed?",
        "explain my voice screen",
        "show my attention result"
    ]
    private let placeholders = [
        "Ask anything",
        "Compare my baseline",
        "Explain a signal"
    ]

    var body: some View {
        VStack(spacing: 0) {
            CompanionHeader(
                runtimeInfo: runtimeInfo,
                isPreparing: localModelPreparing,
                onClose: onClose
            )
            Divider().opacity(0.5)
            conversation
            VanishingPromptField(
                text: $draft,
                placeholders: placeholders,
                isResponding: isResponding,
                onSubmit: send,
                onStop: stopResponse
            )
                .padding(.top, 10)
        }
        .padding(16)
        .onAppear(perform: prewarmLocalModel)
        .onDisappear {
            stopResponse()
            prewarmTask?.cancel()
            prewarmTask = nil
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(messages) { message in
                        MessageBubble(
                            message: message,
                            isStreaming: isResponding
                                && message.role == .venture
                                && message.id == messages.last?.id
                        )
                            .id(message.id)
                    }

                    if messages.count == 1 {
                        CompanionSuggestions(suggestions: suggestions, action: send)
                    }
                }
                .padding(.vertical, 14)
            }
            .onChange(of: messages.count) {
                if let id = messages.last?.id {
                    withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            .onChange(of: messages.last?.text) {
                if let id = messages.last?.id {
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func send(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !isResponding else { return }
        messages.append(ChatMessage(role: .user, text: clean))
        let responseID = UUID()
        activeResponseID = responseID
        isResponding = true
        responseTask = Task { @MainActor in
            if requestsProtection(clean) {
                await store.supportService.activateProtection(sleepHours: store.healthService.latest.sleepHours)
            }
            guard !Task.isCancelled else {
                finishResponse(responseID)
                return
            }
            let context = CompanionContext(
                snapshots: store.snapshots,
                health: store.healthService.latest,
                mentalHealth: store.mentalHealthSummary,
                screenTimeSelectionCount: store.supportService.selectedCount,
                screenTimeProtectionActive: store.supportService.protectionActive,
                recentConversation: messages.suffix(6).map { message in
                    "\(message.role == .user ? "user" : "venture"): \(message.text)"
                }
            )
            await render(companion.streamResponse(to: clean, context: context))
            if !Task.isCancelled {
                Haptics.soft()
            }
            finishResponse(responseID)
        }
    }

    @MainActor
    private func render(_ stream: AsyncStream<String>) async {
        let message = ChatMessage(role: .venture, text: "")
        messages.append(message)
        var receivedText = false
        for await partial in stream {
            guard !Task.isCancelled else {
                if !receivedText {
                    messages.removeAll { $0.id == message.id }
                }
                return
            }
            guard let messageIndex = messages.firstIndex(where: { $0.id == message.id }) else { return }
            receivedText = true
            messages[messageIndex].text = partial
        }
        if !receivedText, !Task.isCancelled,
           let messageIndex = messages.firstIndex(where: { $0.id == message.id }) {
            messages[messageIndex].text = "I could not form a local response. Try asking again."
        }
    }

    private func stopResponse() {
        guard isResponding else { return }
        responseTask?.cancel()
        responseTask = nil
        activeResponseID = nil
        isResponding = false
        Haptics.soft()
    }

    private func finishResponse(_ responseID: UUID) {
        guard activeResponseID == responseID else { return }
        isResponding = false
        responseTask = nil
        activeResponseID = nil
    }

    private func requestsProtection(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("protect") || lower.contains("block distractions") || lower.contains("start screen time")
    }

    private func prewarmLocalModel() {
        guard prewarmTask == nil, BundledLlamaEngine.isBundled else { return }
        localModelPreparing = true
        prewarmTask = Task.detached(priority: .utility) {
            let prepared = await BundledLlamaEngine.shared.prepare()
            await MainActor.run {
                localModelPreparing = false
                runtimeInfo = prepared ? CompanionRuntimeInfo.current : CompanionRuntimeInfo(
                    runtime: .metricEngine,
                    detail: "Private deterministic answers grounded in your measurements"
                )
            }
        }
    }
}

private struct CompanionHeader: View {
    let runtimeInfo: CompanionRuntimeInfo
    let isPreparing: Bool
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            LivingPortalView(size: 44, intensity: 0.72, interactive: false)
            VStack(alignment: .leading, spacing: 2) {
                Text("venture")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                HStack(spacing: 4) {
                    Text("here to")
                    FlipText(words: ["explain", "compare", "clarify"])
                        .frame(width: 52, alignment: .leading)
                }
                .font(.caption2)
                .foregroundStyle(VentureTheme.secondary)
                Label(isPreparing ? "loading local model" : runtimeInfo.runtime.rawValue.lowercased(), systemImage: isPreparing ? "circle.dotted" : "lock")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(VentureTheme.secondary)
                    .lineLimit(1)
            }
            Spacer()
            AnimatedCloseButton(action: onClose)
        }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    let isStreaming: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.46)) { context in
            let cursorVisible = Int(context.date.timeIntervalSinceReferenceDate / 0.46).isMultiple(of: 2)
            (Text(message.text) + Text(isStreaming && cursorVisible ? "  ▍" : ""))
                .font(.caption)
                .lineSpacing(3)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(message.role == .user ? VentureTheme.primaryFill : VentureTheme.surfaceMuted)
                .foregroundStyle(VentureTheme.ink)
                .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                .frame(maxWidth: 330, alignment: message.role == .user ? .trailing : .leading)
                .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        }
    }
}

private struct CompanionSuggestions: View {
    let suggestions: [String]
    let action: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(suggestions, id: \.self) { suggestion in
                Button(suggestion) { action(suggestion) }
                    .font(.caption)
                    .foregroundStyle(VentureTheme.ink)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(VentureTheme.surfaceMuted, in: Capsule())
                    .buttonStyle(HapticPlainButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChatMessage: Identifiable {
    enum Role { case user, venture }
    let id = UUID()
    let role: Role
    var text: String
}
