import SwiftUI

struct VentureAssistantPage: View {
    @Bindable var store: VentureStore
    var locale: VentureLocale
    @StateObject private var manager = LocalModelManager()
    @State private var draft = ""
    @State private var messages: [Message] = []
    @State private var responding = false
    @State private var ready = false
    @State private var preparing = false
    @State private var job: Task<Void, Never>?
    private struct Message: Identifiable { let id = UUID(); let user: Bool; var text: String }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(locale.t(.assistant)).font(.system(size: 32, weight: .regular, design: .rounded)).tracking(-0.7)
                    HStack(spacing: 7) {
                        Circle().fill(ready ? VentureCanvas.accent : VentureCanvas.muted).frame(width: 5, height: 5)
                        Text(ready ? LocalCompanionModel.active.displayName : locale.t(preparing ? .preparing : .unavailable)).font(.caption).foregroundStyle(VentureCanvas.muted)
                    }
                }
                Spacer()
            }
            if !LocalCompanionModel.gemma4E2B.isInstalled {
                Button { manager.downloadGemma4() } label: {
                    HStack { Image(systemName: "arrow.down.circle"); Text("Gemma 4"); Spacer(); Text(locale.t(.download)) }
                        .padding(18).ventureSurface(cornerRadius: 20)
                }
                switch manager.state {
                case .downloading: ProgressView(); Text(locale.t(.preparing)).font(.caption)
                case .failed: Text(locale.t(.retry)).font(.caption)
                default: EmptyView()
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if messages.isEmpty {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 40, weight: .ultraLight)).foregroundStyle(VentureCanvas.accent)
                                .frame(width: 90, height: 90).background(VentureCanvas.surface, in: Circle()).padding(.top, 40)
                            Text(locale.language.name).font(.title3).foregroundStyle(VentureCanvas.muted)
                        }
                        ForEach(messages) { item in
                            HStack {
                                if item.user { Spacer(minLength: 36) }
                                Text(item.text).textSelection(.enabled).padding(18)
                                    .background(item.user ? VentureTheme.surfaceMuted : VentureCanvas.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                                    .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(VentureCanvas.line.opacity(0.6), lineWidth: 0.8) }
                                if !item.user { Spacer(minLength: 18) }
                            }.id(item.id)
                        }
                        if responding { ProgressView().padding(.horizontal, 18) }
                    }
                }.scrollIndicators(.hidden)
                    .onChange(of: messages.last?.text) { _, _ in if let id = messages.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
            }
            HStack(spacing: 12) {
                TextField(locale.t(.message), text: $draft, axis: .vertical).lineLimit(1...4).padding(18)
                    .ventureSurface(cornerRadius: 23)
                Button { if responding { job?.cancel(); responding = false } else { send() } } label: {
                    Image(systemName: responding ? "stop.fill" : "arrow.up").frame(width: 52, height: 52)
                        .foregroundStyle(.white).background(VentureCanvas.accent, in: Circle())
                }.disabled((draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !responding) || !ready)
                    .accessibilityLabel(locale.t(responding ? .stop : .send))
            }
        }.padding(26).task { await prepare() }
            .onChange(of: LocalCompanionModel.gemma4E2B.isInstalled) { _, value in if value { Task { await prepare() } } }
            .onDisappear { job?.cancel(); responding = false }
    }

    private func prepare() async {
        guard !preparing else { return }; preparing = true
        ready = await BundledLlamaEngine.shared.prepare()
        preparing = false
    }

    private func send() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !responding, ready else { return }
        Haptics.soft(); draft = ""; responding = true
        let history = messages.suffix(6).map { ($0.user ? "user: " : "assistant: ") + $0.text }
        messages.append(Message(user: true, text: question)); messages.append(Message(user: false, text: ""))
        let id = messages.last!.id
        let measured = store.snapshots.suffix(7).map(\.screeningContext)
        let context = CompanionContext(snapshots: measured, health: .empty,
            mentalHealth: .empty, screenTimeSelectionCount: 0, screenTimeProtectionActive: false, recentConversation: history)
        let language = locale.language
        job = Task {
            for await text in BundledLlamaEngine.shared.streamResponse(
                to: "Respond entirely in \(language.name) (\(language.id)). Do not diagnose or estimate disease probabilities.\n\(question)", context: context
            ) {
                guard !Task.isCancelled, let index = messages.firstIndex(where: { $0.id == id }) else { break }
                messages[index].text = VentureClinicalOutputPolicy.allows(text) ? text : locale.t(.screening)
            }
            if let index = messages.firstIndex(where: { $0.id == id }), messages[index].text.isEmpty { messages[index].text = locale.t(.unavailable) }
            responding = false
        }
    }
}

enum VentureClinicalOutputPolicy {
    // No percentage is a validated personal disease probability in this build.
    // Do not turn an uncalibrated score into an apparently credible capped score.
    static func allows(_ text: String) -> Bool {
        !text.contains("%") && !text.contains("％") && !text.contains("٪")
    }
}
