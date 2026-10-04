import AVFoundation
import SwiftUI

struct VentureCallExperimentList: View {
    @ObservedObject var service: VentureCallingService
    var select: (VentureCallExperiment) -> Void
    @AppStorage("venture.call-tests.url") private var url = ""
    @AppStorage("venture.call-tests.hidden") private var hidden = ""
    @State private var token = ""
    @State private var settings = false

    private var hiddenIDs: Set<String> { Set(hidden.split(separator: ",").map(String.init)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("test calling assistants").font(.title2.weight(.light))
            Text("interactive appointment demos. each test starts a separate conversation.")
                .font(.footnote).foregroundStyle(VentureCanvas.muted)
            ForEach(VentureCallExperiment.allCases.filter { !hiddenIDs.contains($0.id) }) { experiment in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(experiment.title).font(.headline)
                        Spacer()
                        Menu {
                            Button("remove test", role: .destructive) {
                                var values = hiddenIDs; values.insert(experiment.id)
                                hidden = values.sorted().joined(separator: ",")
                            }
                        } label: { Image(systemName: "ellipsis").frame(width: 40, height: 30) }
                            .accessibilityIdentifier("call-test-options-\(experiment.id)")
                    }
                    Text(experiment.detail).font(.caption).foregroundStyle(VentureCanvas.muted)
                    Text(status(experiment)).font(.caption).foregroundStyle(VentureCanvas.muted)
                        .accessibilityIdentifier("call-status-\(experiment.id)")
                    Button { select(experiment) } label: {
                        HStack { Image(systemName: "phone.bubble"); Text("test \(experiment.title)"); Spacer(); Image(systemName: "arrow.up.right") }
                    }.accessibilityIdentifier("test-call-\(experiment.id)")
                }.padding(20).ventureSurface(cornerRadius: 24)
            }
            if !hiddenIDs.isEmpty {
                Button("restore all tests") { hidden = "" }.font(.footnote).accessibilityIdentifier("restore-call-tests")
            }
            DisclosureGroup("calling service", isExpanded: $settings) {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("https://your-service.example", text: $url)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("call-service-url")
                    SecureField("service test token", text: $token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("call-service-token")
                    Text("vendor keys stay on the server. the test token is kept only for this session.")
                        .font(.caption).foregroundStyle(VentureCanvas.muted)
                    Button {
                        Task { await service.connect(url: url, token: token) }
                    } label: {
                        HStack { Text("check service"); Spacer(); if service.checking { ProgressView() } else { Image(systemName: "arrow.right") } }
                    }.disabled(service.checking).accessibilityIdentifier("check-call-service")
                    if let error = service.error { Text(error).font(.footnote).foregroundStyle(VentureCanvas.muted) }
                    if service.connected { Text("service connected").font(.footnote).foregroundStyle(VentureCanvas.accent) }
                }.padding(.top, 16)
            }.onChange(of: url) { _, _ in service.disconnect() }
                .onChange(of: token) { _, _ in service.disconnect() }
                .accessibilityIdentifier("call-service-settings")
        }
    }

    private func status(_ experiment: VentureCallExperiment) -> String {
        if let result = service.results[experiment.id] { return result }
        guard service.connected else { return "connect the calling service to test" }
        guard let status = service.statuses.first(where: { $0.id == experiment.id }) else { return "removed from service" }
        return status.configured ? "configured · not tested" : status.detail
    }
}

struct VentureCallTestView: View {
    let experiment: VentureCallExperiment
    @ObservedObject var service: VentureCallingService
    @Bindable var store: VentureStore
    let locale: VentureLocale
    let hospital: String?
    let phoneNumber: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var voice = VentureCallVoiceInput()
    @State private var messages: [VentureCallMessage] = []
    @State private var draft = ""
    @State private var shareSummary = false
    @State private var readReplies = true
    @State private var responding = false
    @State private var error: String?
    @State private var lastReply: VentureCallReply?
    @State private var job: Task<Void, Never>?
    @State private var microphoneJob: Task<Void, Never>?
    @State private var generation = UUID()
    @State private var speaker = AVSpeechSynthesizer()
    @State private var goal = ""
    @State private var phoneOptIn = false
    @State private var number = ""
    @State private var phoneSettings = false
    @State private var personalization = false
    private var dialRequest: VenturePhoneRequest? { service.phoneRequests[experiment.id] }
    private var phoneCall: VenturePhoneCall? { service.phoneCalls[experiment.id] }
    private var dialing: Bool { service.dialingProviders.contains(experiment.id) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(experiment.detail).font(.caption).foregroundStyle(VentureCanvas.muted)
                Text("practice an appointment conversation, or opt in to an automated clinic call below.")
                    .font(.footnote).foregroundStyle(VentureCanvas.muted)
                Text("in-app tests send submitted text to your service\(experiment == .rural ? "" : " and its model provider"). in-app dictation stays on this device.")
                    .font(.caption).foregroundStyle(VentureCanvas.muted)
                if !service.connected {
                    Text("connect the calling service on the care page, then reopen this test.").font(.footnote)
                        .accessibilityIdentifier("call-needs-service")
                }
                if let hospital { Text(hospital).font(.footnote) }
                DisclosureGroup("personalize this conversation", isExpanded: $personalization) {
                ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                Toggle("share measured summary", isOn: $shareSummary).font(.footnote).disabled(responding)
                    .accessibilityIdentifier("call-share-summary")
                    .onChange(of: shareSummary) { _, _ in
                        cancel(); messages = []; lastReply = nil; error = nil
                    }
                if shareSummary {
                    Text(measuredSummary).font(.caption).foregroundStyle(VentureCanvas.muted).accessibilityIdentifier("call-measured-summary")
                }
                Toggle("read replies aloud", isOn: $readReplies).font(.footnote)
                    .accessibilityIdentifier("call-read-replies")
                    .onChange(of: readReplies) { _, value in if !value { speaker.stopSpeaking(at: .immediate) } }
                TextField("appointment goal (optional)", text: $goal).font(.footnote)
                    .disabled(responding || dialRequest != nil).accessibilityIdentifier("call-appointment-goal")
                Button {
                    draft = "Generate the opening message for an automated appointment assistant speaking on my behalf to a clinic. Personalize it using only my supplied measured context. My goal: \(goal.isEmpty ? "ask how to arrange a routine appointment" : goal). Explain unknown information honestly and do not claim a booking."
                    send()
                } label: { Label("start personalized demo", systemImage: "phone.bubble") }
                    .font(.footnote).disabled(!shareSummary || !service.connected || responding)
                    .accessibilityIdentifier("start-personalized-call-demo")
                DisclosureGroup("real phone call · Twilio", isExpanded: $phoneSettings) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(service.phoneConfigured ? "calls use English speech. Twilio call charges may apply." : service.phoneDetail)
                            .font(.caption).foregroundStyle(VentureCanvas.muted)
                        TextField("clinic number (+country code)", text: $number)
                            .keyboardType(.phonePad).disabled(dialRequest != nil)
                            .accessibilityIdentifier("call-clinic-number")
                        Toggle("allow automated call and share my summary", isOn: $phoneOptIn).font(.footnote)
                            .disabled(dialing || phoneCall != nil)
                        Text(dialRequest?.context ?? measuredSummary).font(.caption).foregroundStyle(VentureCanvas.muted)
                        Text("the selected assistant will introduce itself and discuss your appointment goal using this summary. the clinic must confirm any appointment.")
                            .font(.caption).foregroundStyle(VentureCanvas.muted)
                        Text("Twilio carries call audio and transcribes the clinic's replies. reply text and the summary go to this service\(experiment == .rural ? "" : " and its model provider").")
                            .font(.caption).foregroundStyle(VentureCanvas.muted)
                        if let call = phoneCall {
                            Text("call status: \(call.status)").font(.footnote).accessibilityIdentifier("twilio-call-status")
                            HStack {
                                Button("refresh status") { Task {
                                    if call.call_sid.isEmpty { await checkAttempt() } else { await refreshCall() }
                                } }
                                Spacer()
                                if !call.call_sid.isEmpty { Button("end call") { Task { await endCall() } } }
                            }.font(.footnote)
                            if ["completed", "canceled", "failed", "busy", "no-answer"].contains(call.status) {
                                Button("prepare a new call") { service.clearFinishedCall(experiment); phoneOptIn = false }.font(.footnote)
                            }
                        } else {
                            Button(dialRequest == nil ? "start automated call" : "check or retry same call") { Task { await dial() } }
                                .font(.footnote).disabled(!phoneOptIn || !service.phoneConfigured || dialing || locale.language.id != "en")
                                .accessibilityIdentifier("start-twilio-call")
                            if dialRequest != nil { Button("check attempt status") { Task { await checkAttempt() } }.font(.footnote) }
                        }
                        if dialing { ProgressView() }
                        if locale.language.id != "en" { Text("real phone calls currently support English. in-app tests use your selected language.").font(.caption) }
                    }.padding(.top, 12)
                }.font(.footnote)
                }.padding(.top, 12)
                }.frame(maxHeight: 220)
                }.font(.footnote).accessibilityIdentifier("call-personalization")
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            if messages.isEmpty {
                                Text("try: help me request a routine appointment.")
                                    .font(.body).foregroundStyle(VentureCanvas.muted).padding(.vertical, 25)
                            }
                            ForEach(messages) { message in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(message.role == "user" ? "you" : experiment.title).font(.caption).foregroundStyle(VentureCanvas.muted)
                                    Text(message.content).textSelection(.enabled)
                                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                    .ventureSurface(cornerRadius: 20).id(message.id)
                            }
                            if responding { ProgressView().padding() }
                        }
                    }.scrollIndicators(.hidden)
                        .onChange(of: messages.count) { _, _ in if let id = messages.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
                }
                if let reply = lastReply {
                    Text("\(reply.kind.lowercased()) · \(reply.latency_ms) ms").font(.caption).foregroundStyle(VentureCanvas.muted)
                        .accessibilityIdentifier("call-reply-received")
                }
                if let error = error ?? voice.error {
                    Text(error).font(.footnote).foregroundStyle(VentureCanvas.muted).accessibilityIdentifier("call-test-error")
                }
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("type or dictate", text: $draft, axis: .vertical).lineLimit(1...3)
                        .padding(16).ventureSurface(cornerRadius: 20)
                        .disabled(responding).accessibilityIdentifier("call-test-message")
                    Button {
                        if voice.recording { voice.stop() }
                        else {
                            speaker.stopSpeaking(at: .immediate)
                            microphoneJob?.cancel()
                            microphoneJob = Task { await voice.start(language: locale.language.id) }
                        }
                    } label: {
                        Image(systemName: voice.recording ? "mic.fill" : "mic").frame(width: 44, height: 52)
                    }.disabled(responding).accessibilityLabel(voice.recording ? "stop dictation" : "dictate message")
                    Button {
                        if responding { cancel() } else { send() }
                    } label: {
                        Image(systemName: responding ? "stop.fill" : "arrow.up").frame(width: 46, height: 52)
                            .foregroundStyle(.white).background(VentureCanvas.accent, in: Capsule())
                    }.disabled(!responding && (!service.connected || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                        .accessibilityLabel(responding ? "stop response" : "send message").accessibilityIdentifier("send-call-test")
                }
            }.padding(22).background(VentureCanvas.background).foregroundStyle(VentureCanvas.ink)
                .navigationTitle(experiment.title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("reset") { cancel(); messages = []; lastReply = nil; draft = ""; error = nil }
                            .accessibilityIdentifier("reset-call-test")
                    }
                    ToolbarItem(placement: .topBarTrailing) { Button(locale.t(.done)) { dismiss() } }
                }
        }.tint(VentureCanvas.accent).onAppear {
            number = dialRequest?.to_number ?? phoneNumber ?? ""
            goal = dialRequest?.goal ?? ""
            if dialRequest != nil { personalization = true; phoneSettings = true; phoneOptIn = true }
        }
            .onChange(of: voice.transcript) { _, value in draft = value }
            .onChange(of: scenePhase) { _, value in if value != .active { cancel() } }
            .onDisappear { cancel(); messages = [] }
    }

    private var measuredSummary: String {
        VentureCallContext.summary(snapshot: store.snapshots.last)
    }

    private func dial() async {
        guard phoneOptIn, !dialing, phoneCall == nil else { return }
        cancel(); error = nil
        let payload = dialRequest ?? VenturePhoneRequest(provider: experiment.id, to_number: VentureCallingService.normalizedPhoneNumber(number) ?? number.trimmingCharacters(in: .whitespacesAndNewlines),
                language: "en", context: VentureCallContext.context(snapshot: store.snapshots.last, optedIn: true, hospital: hospital),
                goal: goal.isEmpty ? "ask how to arrange a routine appointment" : goal,
                opted_in: true, request_id: UUID().uuidString)
        do { _ = try await service.dial(payload) }
        catch { error = error.localizedDescription }
    }

    private func refreshCall() async {
        guard let call = phoneCall else { return }
        do { _ = try await service.phoneStatus(call.call_sid) }
        catch { self.error = error.localizedDescription }
    }

    private func checkAttempt() async {
        do { try await service.checkPhoneAttempt(experiment) }
        catch { self.error = error.localizedDescription }
    }

    private func endCall() async {
        guard let call = phoneCall else { return }
        do { _ = try await service.endCall(call.call_sid) }
        catch { self.error = error.localizedDescription }
    }

    private func cancel() {
        generation = UUID(); job?.cancel(); job = nil; microphoneJob?.cancel(); microphoneJob = nil
        voice.stop(); speaker.stopSpeaking(at: .immediate); responding = false
    }

    private func send() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !responding, question.count <= 4000 else {
            if question.count > 4000 { error = "keep each message under 4,000 characters." }
            return
        }
        microphoneJob?.cancel(); microphoneJob = nil; voice.stop(); speaker.stopSpeaking(at: .immediate)
        error = nil; draft = ""; responding = true; lastReply = nil
        let attempt = UUID(); generation = attempt
        // Failed/cancelled messages stay out of subsequent provider history.
        let outgoing = messages + [VentureCallMessage(role: "user", content: question)]
        let submittedContext = VentureCallContext.context(snapshot: store.snapshots.last, optedIn: shareSummary, hospital: hospital)
        job = Task {
            do {
                let reply = try await service.respond(experiment: experiment, messages: outgoing,
                                                      language: locale.language.id, context: submittedContext)
                guard !Task.isCancelled, generation == attempt else { return }
                messages = outgoing + [VentureCallMessage(role: "assistant", content: reply.text)]
                lastReply = reply
                if readReplies {
                    if let installedVoice = AVSpeechSynthesisVoice.speechVoices().first(where: {
                        $0.language.lowercased().hasPrefix(locale.language.id.lowercased())
                    }) {
                        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                        try? AVAudioSession.sharedInstance().setActive(true)
                        let utterance = AVSpeechUtterance(string: reply.text)
                        utterance.voice = installedVoice
                        speaker.speak(utterance)
                    } else { error = "reply received. install a voice for this language in iOS settings to hear it." }
                }
            } catch {
                guard !Task.isCancelled, generation == attempt else { return }
                self.error = error.localizedDescription; draft = question
            }
            if generation == attempt { responding = false }
        }
    }
}
