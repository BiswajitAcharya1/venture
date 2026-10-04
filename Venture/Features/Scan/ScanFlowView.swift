import SwiftUI
import UIKit

struct ScanFlowView: View {
    @Environment(\.dismiss) private var dismiss

    let store: VentureStore
    var completionAction: (() -> Void)? = nil

    @State private var phase: ScanPhase = .introduction
    @State private var eyeResult = EyeResult()
    @State private var voiceResult = VoiceResult()
    @State private var cognitiveResult = CognitiveResult()

    init(store: VentureStore, completionAction: (() -> Void)? = nil) {
        self.store = store
        self.completionAction = completionAction
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-eyePreview") {
            _phase = State(initialValue: .eyes)
        } else if arguments.contains("-voicePreview") {
            _phase = State(initialValue: .voice)
        } else if arguments.contains("-moodResultPreview") {
            _phase = State(initialValue: .cognition)
        }
#endif
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VentureAtmosphereView().ignoresSafeArea()

                Group {
                    switch phase {
                    case .introduction:
                        ScanIntroductionView { transition(to: .eyes) }
                    case .eyes:
                        EyeTrackingTaskView { result in
                            eyeResult = result
                            transition(to: .voice)
                        }
                    case .voice:
                        VoicePromptTaskView { result in
                            voiceResult = result
                            transition(to: .cognition)
                        }
                    case .cognition:
                        CognitiveTaskView { result in
                            cognitiveResult = result
                            transition(to: .complete)
                        }
                    case .complete:
                        ScanCompletionView(action: finish)
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.97)),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AnimatedCloseButton { dismiss() }
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        }
    }

    private func transition(to newPhase: ScanPhase) {
        Haptics.progress()
        withAnimation(.spring(response: 0.68, dampingFraction: 0.88)) {
            phase = newPhase
        }
    }

    private func finish() {
        store.completeScan(result: ScanResult(
            cameraAuthorized: eyeResult.cameraAuthorized,
            microphoneAuthorized: voiceResult.microphoneAuthorized,
            eyeConfidence: eyeResult.confidence,
            fixationStability: eyeResult.fixationStability,
            blinkCount: eyeResult.blinkCount,
            pupilResponse: eyeResult.pupilResponse,
            pupilSymmetry: eyeResult.pupilSymmetry,
            pupilVariability: eyeResult.pupilVariability,
            gazeTrackingScore: eyeResult.gazeTrackingScore,
            speechStability: voiceResult.speechStability,
            voiceActivityRatio: voiceResult.voiceActivityRatio,
            noiseLevel: voiceResult.noiseLevel,
            parkinsonsVoiceProbability: voiceResult.parkinsonsVoiceProbability,
            parkinsonsVoiceQuality: voiceResult.parkinsonsVoiceQuality,
            spontaneousWordCount: voiceResult.spontaneousWordCount,
            spontaneousLexicalDiversity: voiceResult.spontaneousLexicalDiversity,
            respiratoryWheezeLikelihood: voiceResult.respiratoryWheezeLikelihood,
            respiratoryRecordingQuality: voiceResult.respiratoryRecordingQuality,
            respiratoryBreathSeconds: voiceResult.respiratoryBreathSeconds,
            respiratoryAirflowIrregularity: voiceResult.respiratoryAirflowIrregularity,
            memoryScore: cognitiveResult.memoryScore,
            attentionScore: cognitiveResult.attentionScore,
            executiveFunctionScore: cognitiveResult.executiveFunctionScore,
            phq2Score: cognitiveResult.phq2Score
        ))
        if let completionAction { completionAction() } else { dismiss() }
    }
}

private struct ScanIntroductionView: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            LivingPortalView(size: 145, intensity: 0.78)
            VStack(spacing: 7) {
                Text("A quiet check of today")
                    .font(.system(size: 27, weight: .medium, design: .rounded))
                    .tracking(-0.8)
                Text("Three short checks build a clear picture of today.")
                    .font(.subheadline)
                    .foregroundStyle(VentureTheme.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 0) {
                FlowStep(symbol: "eye", title: "Pupils", detail: "Controlled light-response measurement")
                FlowStep(symbol: "waveform", title: "Voice", detail: "One reading and one longer “ahhh”")
                FlowStep(symbol: "point.3.connected.trianglepath.dotted", title: "Cognition", detail: "Memory, reaction, and mood context")
            }
            .padding(.vertical, 5)

            Spacer()
            Button("Begin live scan", action: action)
                .buttonStyle(VenturePrimaryButtonStyle())
            Text("Each task is optional and reports only what it measured.")
                .font(.caption2)
                .foregroundStyle(VentureTheme.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
    }
}

private struct FlowStep: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(VentureTheme.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 10)
    }
}

private struct EyeTrackingTaskView: View {
    @StateObject private var tracker = EyeTrackingService()
    @State private var lightController = ScreenLightController()
    @State private var completed = false
    @State private var stage: PupilCaptureStage = .aligning
    @State private var captureTask: Task<Void, Never>?
    @State private var captureNotice: String?
    @State private var brightProgress = 0.0
    @State private var gazeTarget: GazeTarget?
    @State private var gazeTrackingScore: Double?
    @State private var gazeTargetIndex = 0

    let onComplete: (EyeResult) -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                TaskHeader(
                    step: "01",
                    title: stage.title,
                    detail: stage.detail,
                    skip: { complete(cameraAuthorized: false) }
                )

                ZStack {
                    CameraPreviewView(session: tracker.session)
                        .overlay(Color.black.opacity(tracker.permissionDenied ? 0.72 : 0.08))
                    if tracker.faceDetected {
                        FaceModelOverlay(
                            leftEye: tracker.leftEye,
                            rightEye: tracker.rightEye,
                            leftContour: tracker.leftEyeContour,
                            rightContour: tracker.rightEyeContour
                        )
                    }
                    if stage == .gaze, let gazeTarget {
                        GazeTargetOverlay(target: gazeTarget)
                    }
                    ModelStatusPill(
                        symbol: tracker.capturePosition == .ready ? "eye.fill" : "viewfinder",
                        text: alignmentMessage,
                        active: tracker.capturePosition == .ready
                    )
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(12)
                }
                .frame(height: 290)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.52), lineWidth: 0.7) }

                HStack(spacing: 18) {
                    paperMetric("baseline", value: tracker.baselinePupilSampleCount.formatted())
                    paperMetric("bright", value: tracker.brightPupilSampleCount.formatted())
                    paperMetric(
                        stage == .gaze ? "gaze" : "symmetry",
                        value: stage == .gaze
                            ? "\(gazeTargetIndex)/\(GazeTarget.sequence.count)"
                            : tracker.pupilSymmetry?.formatted(.percent.precision(.fractionLength(0))) ?? "—"
                    )
                }

                if let captureNotice {
                    Text(captureNotice)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(VentureTheme.ink)
                        .multilineTextAlignment(.center)
                }

                Text("The camera keeps only pupil measurements, not photos. Results show personal change and cannot diagnose stress or disease.")
                    .font(.caption)
                    .foregroundStyle(VentureTheme.secondary)
                    .multilineTextAlignment(.center)

                Spacer(minLength: 4)

                if stage == .ready {
                    Button("Begin light response", action: beginCapture)
                        .buttonStyle(VenturePrimaryButtonStyle())
                    Text("The screen becomes steadily bright and ends after enough usable pupil samples are collected. Stop if the light is uncomfortable.")
                        .font(.caption2)
                        .foregroundStyle(VentureTheme.secondary)
                        .multilineTextAlignment(.center)
                } else if tracker.permissionDenied {
                    Button("Continue without camera") { complete(cameraAuthorized: false) }
                        .buttonStyle(VentureSecondaryButtonStyle())
                } else if stage == .baseline {
                    ProgressView("Measuring current pupil size")
                        .font(.caption)
                } else if stage == .gaze {
                    ProgressView("Following gaze targets")
                        .font(.caption)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)

            if stage == .bright {
                BrightPupilCaptureOverlay(
                    sampleCount: tracker.brightPupilSampleCount,
                    progress: brightProgress,
                    onStop: stopBrightCapture
                )
                    .transition(.opacity)
            }
        }
        .task {
            await tracker.start()
            while !Task.isCancelled, !completed, stage == .aligning {
                try? await Task.sleep(for: .milliseconds(180))
                if tracker.capturePosition == .ready, tracker.confidence >= 0.32 {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { stage = .ready }
                    Haptics.success()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            cancelCapture()
        }
        .onDisappear {
            cancelCapture()
            tracker.stop()
        }
    }

    private func beginCapture() {
        guard stage == .ready, captureTask == nil else { return }
        Haptics.strong()
        captureNotice = nil
        captureTask = Task { @MainActor in
            stage = .baseline
            tracker.setPupilSamplingPhase(.baseline)
            while tracker.baselinePupilSampleCount < 12 {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
            }
            guard !Task.isCancelled else { return }

            lightController.begin()
            tracker.setPupilSamplingPhase(.bright)
            brightProgress = 0
            withAnimation(.easeInOut(duration: 0.3)) { stage = .bright }
            let exposureStarted = ContinuousClock.now
            let minimumExposure = Duration.seconds(2)
            let safetyCeiling = Duration.seconds(5)
            while exposureStarted.duration(to: .now) < safetyCeiling {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                let elapsed = exposureStarted.duration(to: .now)
                brightProgress = min(1, Double(tracker.brightPupilSampleCount) / 12)
                if elapsed >= minimumExposure, tracker.brightPupilSampleCount >= 12, tracker.pupilResponse != nil {
                    break
                }
            }
            brightProgress = 1
            lightController.restore()
            tracker.setPupilSamplingPhase(.idle)
            guard tracker.brightPupilSampleCount >= 8, tracker.pupilResponse != nil else {
                failCapture("The light-response scan did not capture enough pupil detail. Hold still, keep both eyes open, and retry.")
                return
            }
            await beginGazeCapture()
        }
    }

    private func beginGazeCapture() async {
        tracker.setPupilSamplingPhase(.gaze)
        gazeTargetIndex = 0
        var targets: [CGPoint] = []
        var measurements: [CGPoint] = []
        withAnimation(.easeInOut(duration: 0.25)) { stage = .gaze }

        for (index, target) in GazeTarget.sequence.enumerated() {
            guard !Task.isCancelled else { return }
            gazeTargetIndex = index + 1
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                gazeTarget = target
            }
            let startingSamples = tracker.gazeSampleCount
            try? await Task.sleep(for: .milliseconds(720))
            var attempts = 0
            while tracker.gazeSampleCount <= startingSamples, attempts < 8 {
                try? await Task.sleep(for: .milliseconds(120))
                attempts += 1
            }
            guard !Task.isCancelled else { return }
            if let measurement = tracker.currentGazePoint {
                targets.append(target.normalizedPoint)
                measurements.append(measurement)
            }
        }

        tracker.setPupilSamplingPhase(.idle)
        gazeTarget = nil
        guard let score = GazeChallengeScorer.score(targets: targets, measurements: measurements) else {
            failCapture("The gaze task did not capture enough pupil-center movement. Keep the phone still and follow each point with your eyes.")
            return
        }
        gazeTrackingScore = score
        complete(cameraAuthorized: true)
    }

    private func failCapture(_ message: String) {
        lightController.restore()
        tracker.setPupilSamplingPhase(.idle)
        captureTask = nil
        captureNotice = message
        Haptics.strong()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            stage = tracker.capturePosition == .ready ? .ready : .aligning
        }
    }

    private func cancelCapture() {
        captureTask?.cancel()
        captureTask = nil
        tracker.setPupilSamplingPhase(.idle)
        lightController.restore()
        brightProgress = 0
        gazeTarget = nil
        if !completed, stage == .baseline || stage == .bright || stage == .gaze {
            withAnimation(.easeOut(duration: 0.25)) {
                stage = tracker.capturePosition == .ready ? .ready : .aligning
            }
        }
    }

    private func stopBrightCapture() {
        guard stage == .bright else { return }
        cancelCapture()
        captureNotice = "The light response was stopped. No incomplete pupil response was saved."
        Haptics.strong()
    }

    private func complete(cameraAuthorized: Bool) {
        guard !completed else { return }
        completed = true
        cancelCapture()
        tracker.stop()
        onComplete(EyeResult(
            cameraAuthorized: cameraAuthorized,
            confidence: tracker.confidence,
            fixationStability: tracker.fixationStability,
            blinkCount: tracker.blinkCount,
            pupilResponse: tracker.pupilResponse,
            pupilSymmetry: tracker.pupilSymmetry,
            pupilVariability: tracker.pupilVariability,
            gazeTrackingScore: gazeTrackingScore
        ))
    }

    private func paperMetric(_ title: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.caption2.monospacedDigit().weight(.semibold))
            Text(title).font(.system(size: 9)).foregroundStyle(VentureTheme.secondary)
        }
        .foregroundStyle(VentureTheme.ink)
        .frame(maxWidth: .infinity)
    }

    private var alignmentMessage: String {
        if tracker.permissionDenied { return "camera unavailable" }
        switch tracker.capturePosition {
        case .noFace: return "center both eyes"
        case .tooFar: return "move the phone closer"
        case .tooClose: return "move slightly farther away"
        case .offCenter: return "center your face"
        case .ready: return "distance and pupils ready"
        }
    }
}

private struct BrightPupilCaptureOverlay: View {
    let sampleCount: Int
    let progress: Double
    let onStop: () -> Void

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(Color.black.opacity(0.12), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.black, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Circle().fill(Color.black).frame(width: 8, height: 8)
                }
                .frame(width: 74, height: 74)
                Text("keep looking at the center")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(sampleCount) usable pupil samples")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("stop light test", action: onStop)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.07), in: Capsule())
            }
        }
    }
}

private enum PupilCaptureStage {
    case aligning
    case ready
    case baseline
    case bright
    case gaze

    var title: String {
        switch self {
        case .aligning: "Center your pupils"
        case .ready: "Pupils centered"
        case .baseline: "Hold still"
        case .bright: "Measuring response"
        case .gaze: "Follow each point"
        }
    }

    var detail: String {
        switch self {
        case .aligning: "Bring the phone close enough for both pupils to fill the guide, then hold it centered."
        case .ready: "A steady brightness step measures relative pupil response."
        case .baseline: "venture is measuring your starting pupil estimate."
        case .bright: "Keep looking at the center point."
        case .gaze: "Move only your eyes while the target changes position."
        }
    }
}

private enum GazeTarget: CaseIterable {
    case center
    case left
    case right
    case top
    case bottom

    static let sequence: [GazeTarget] = [.center, .left, .right, .top, .bottom]

    var normalizedPoint: CGPoint {
        switch self {
        case .center: CGPoint(x: 0.5, y: 0.5)
        case .left: CGPoint(x: 0.18, y: 0.5)
        case .right: CGPoint(x: 0.82, y: 0.5)
        case .top: CGPoint(x: 0.5, y: 0.2)
        case .bottom: CGPoint(x: 0.5, y: 0.8)
        }
    }
}

private struct GazeTargetOverlay: View {
    let target: GazeTarget

    var body: some View {
        GeometryReader { proxy in
            Circle()
                .fill(.white)
                .frame(width: 18, height: 18)
                .overlay { Circle().stroke(VentureTheme.ink.opacity(0.55), lineWidth: 2) }
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                .position(
                    x: proxy.size.width * target.normalizedPoint.x,
                    y: proxy.size.height * target.normalizedPoint.y
                )
                .animation(.spring(response: 0.4, dampingFraction: 0.82), value: target.normalizedPoint)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct FaceModelOverlay: View {
    let leftEye: CGPoint
    let rightEye: CGPoint
    let leftContour: [CGPoint]
    let rightContour: [CGPoint]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                eyeBand(in: proxy.size)

                contour(leftContour, in: proxy.size)
                contour(rightContour, in: proxy.size)
                eyeMarker(leftEye, in: proxy.size)
                eyeMarker(rightEye, in: proxy.size)
            }
        }
        .allowsHitTesting(false)
    }

    private func eyeBand(in size: CGSize) -> some View {
        let left = previewPoint(leftEye, in: size)
        let right = previewPoint(rightEye, in: size)
        let center = CGPoint(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2)
        let width = max(abs(right.x - left.x) + 92, 190)
        return Capsule(style: .continuous)
            .stroke(.white.opacity(0.72), style: StrokeStyle(lineWidth: 1.2, dash: [7, 6]))
            .frame(width: min(width, size.width - 28), height: 82)
            .position(center)
    }

    private func eyeMarker(_ point: CGPoint, in size: CGSize) -> some View {
        Circle()
            .stroke(.white.opacity(0.88), lineWidth: 1.5)
            .frame(width: 19, height: 19)
            .overlay { Circle().fill(.white).frame(width: 3, height: 3) }
            .position(previewPoint(point, in: size))
    }

    private func contour(_ points: [CGPoint], in size: CGSize) -> some View {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: previewPoint(first, in: size))
            for point in points.dropFirst() { path.addLine(to: previewPoint(point, in: size)) }
            path.closeSubpath()
        }
        .stroke(VentureTheme.sage.opacity(0.95), lineWidth: 2)
    }

    private func previewPoint(_ point: CGPoint, in viewSize: CGSize) -> CGPoint {
        let imageSize = CGSize(width: 480, height: 640)
        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let rendered = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let offset = CGPoint(x: (viewSize.width - rendered.width) / 2, y: (viewSize.height - rendered.height) / 2)
        return CGPoint(x: offset.x + point.x * rendered.width, y: offset.y + point.y * rendered.height)
    }

}

private struct ModelScanSweep: View {
    var body: some View {
        GeometryReader { proxy in
            TimelineView(.periodic(from: .now, by: 1.0 / 12.0)) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
                Rectangle()
                    .fill(.linearGradient(colors: [.clear, .white.opacity(0.72), .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1)
                    .shadow(color: VentureTheme.sage.opacity(0.7), radius: 5)
                    .position(x: proxy.size.width / 2, y: proxy.size.height * phase)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct VoicePromptTaskView: View {
    @StateObject private var voice = VoiceCaptureService()
    @State private var completed = false
    @State private var stage: VoiceCaptureStage = .ready
    @State private var analysisTask: Task<Void, Never>?
    @State private var countdownTask: Task<Void, Never>?
    @State private var isPreparingVoice = false
    @State private var countdownValue: Int?
    @State private var firstMotorResult: ParkinsonVoiceScreenResult?
    @State private var finalMotorResult: ParkinsonVoiceScreenResult?
    @State private var finalRespiratoryResult: RespiratoryAcousticScreenResult?
    @State private var confirmationCompleted = false
    private let motorTargetSeconds = 6.0
    private let respiratoryTargetSeconds = 4.0
    let onComplete: (VoiceResult) -> Void

    var body: some View {
        VStack(spacing: 18) {
            TaskHeader(step: "02", title: stage.title, detail: stage.detail, skip: { complete(microphoneAuthorized: false) })

            VStack(spacing: 2) {
                LivingPortalView(
                    size: 142,
                    intensity: voice.isRecording ? 1.08 : 0.72,
                    activity: voice.audioLevel,
                    interactive: false
                )
                .accessibilityLabel(voice.isRecording ? "Voice activity responding to your speech" : "Voice activity idle")

                LiveWaveform(level: voice.audioLevel, active: voice.isRecording)
                    .frame(height: 46)
            }

            MicrophonePlacementGuide(level: voice.audioLevel)

            if stage == .ready {
                VoiceSampleIntroduction()
            } else if stage.isCountdown {
                VoiceCountdownView(value: countdownValue ?? 3, title: stage.countdownTitle)
            } else if stage.usesVowelCapture {
                SustainedVowelView(
                    progress: min(1, voice.motorSampleDuration / motorTargetSeconds),
                    analyzing: stage == .analyzing || stage == .repeatAnalyzing
                )
            } else if stage == .repeatPrompt {
                ConfirmationVoicePrompt(firstResult: firstMotorResult)
            } else if stage == .breathIntro {
                BreathSampleIntroduction()
            } else if stage.usesBreathCapture {
                BreathingSampleView(
                    progress: min(1, voice.respiratorySampleDuration / respiratoryTargetSeconds),
                    analyzing: stage == .breathAnalyzing
                )
            } else if stage == .breathResult {
                RespiratoryModelResultView(result: finalRespiratoryResult, error: voice.respiratoryScreenError)
            }

            VStack(alignment: .leading, spacing: 10) {
                ModelStatusPill(
                    symbol: voice.voiceActivityProbability >= 0.5 ? "waveform" : "waveform.slash",
                    text: voice.isRecording ? voice.audioProcessor : voice.permissionDenied ? "microphone unavailable" : "preparing microphone",
                    active: voice.isRecording
                )
                VoiceProcessView(
                    stage: stage,
                    vowelProgress: min(1, voice.motorSampleDuration / motorTargetSeconds)
                )
            }

            Spacer()

            if voice.permissionDenied {
                Button("continue without voice") { complete(microphoneAuthorized: false) }
                    .buttonStyle(VentureSecondaryButtonStyle())
            } else if stage == .ready {
                Button(action: startVowelSample) {
                    if isPreparingVoice {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("start six-second ahhh")
                    }
                }
                    .buttonStyle(VenturePrimaryButtonStyle())
                    .disabled(isPreparingVoice)
            } else if stage.isCountdown {
                Text("starting in \(countdownValue ?? 3)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(VentureTheme.secondary)
            } else if stage == .sampleIntro {
                Button("start steady sample", action: beginMotorCountdown)
                    .buttonStyle(VenturePrimaryButtonStyle())
            } else if stage == .vowel || stage == .repeatVowel {
                Text("keep the sound steady until the ring closes.")
                    .font(.caption)
                    .foregroundStyle(VentureTheme.secondary)
            } else if stage == .analyzing || stage == .repeatAnalyzing {
                ProgressView("saving the local voice sample")
                    .font(.caption)
            } else if stage == .repeatPrompt {
                Button("record confirmation sample", action: beginRepeatMotorCountdown)
                    .buttonStyle(VenturePrimaryButtonStyle())
                Button("skip confirmation and continue") {
                    Haptics.soft()
                    finalMotorResult = firstMotorResult
                    complete(microphoneAuthorized: true)
                }
                .buttonStyle(VentureSecondaryButtonStyle())
            } else if stage == .result {
                VoiceModelResultView()
                Button("continue to cognition", action: {
                    Haptics.success()
                    complete(microphoneAuthorized: true)
                })
                    .buttonStyle(VenturePrimaryButtonStyle())
            } else if stage == .breathIntro {
                Button("start breathing sample", action: beginBreathCountdown)
                    .buttonStyle(VenturePrimaryButtonStyle())
                Button("skip breathing sample") {
                    Haptics.soft()
                    complete(microphoneAuthorized: true)
                }
                .buttonStyle(VentureSecondaryButtonStyle())
            } else if stage == .breath {
                Text("breathe normally near the microphone until the ring closes.")
                    .font(.caption)
                    .foregroundStyle(VentureTheme.secondary)
            } else if stage == .breathAnalyzing {
                ProgressView("running the respiratory acoustic screen")
                    .font(.caption)
            } else if stage == .breathResult {
                Button("continue", action: {
                    Haptics.success()
                    complete(microphoneAuthorized: true)
                })
                    .buttonStyle(VenturePrimaryButtonStyle())
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .onChange(of: voice.motorSampleDuration) { _, duration in
            guard duration >= motorTargetSeconds else { return }
            if stage == .vowel {
                analyzeMotorSample(isRepeat: false)
            } else if stage == .repeatVowel {
                analyzeMotorSample(isRepeat: true)
            }
        }
        .onChange(of: voice.respiratorySampleDuration) { _, duration in
            guard duration >= respiratoryTargetSeconds, stage == .breath else { return }
            analyzeBreathSample()
        }
        .onAppear {
            #if DEBUG
            guard ProcessInfo.processInfo.arguments.contains("-voiceAutoStartPreview") else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                guard stage == .ready else { return }
                startVowelSample()
            }
            #endif
        }
        .onDisappear {
            analysisTask?.cancel()
            countdownTask?.cancel()
            voice.stop()
        }
    }

    private func startVowelSample() {
        guard stage == .ready else { return }
        Haptics.strong()
        isPreparingVoice = true
        Task { @MainActor in
            await voice.start()
            isPreparingVoice = false
            guard voice.isRecording else { return }
            beginMotorCountdown()
        }
    }

    private func beginMotorCountdown() {
        guard voice.isRecording, stage == .ready || stage == .sampleIntro || stage == .result else { return }
        Haptics.strong()
        countdownTask?.cancel()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
            stage = .vowelCountdown
        }
        countdownTask = Task { @MainActor in
            await runCountdown()
            guard !Task.isCancelled else { return }
            beginMotorScreen()
            countdownTask = nil
        }
    }

    private func beginMotorScreen() {
        guard voice.isRecording, stage == .sampleIntro || stage == .result || stage == .vowelCountdown else { return }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.84)) { stage = .vowel }
        voice.beginMotorSample()
    }

    private func beginRepeatMotorCountdown() {
        guard voice.isRecording, stage == .repeatPrompt else { return }
        Haptics.strong()
        countdownTask?.cancel()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
            stage = .repeatCountdown
        }
        countdownTask = Task { @MainActor in
            await runCountdown()
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.84)) { stage = .repeatVowel }
            voice.beginMotorSample()
            countdownTask = nil
        }
    }

    private func showBreathIntroduction() {
        guard voice.isRecording else { return }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
            stage = .breathIntro
        }
    }

    private func beginBreathCountdown() {
        guard voice.isRecording, stage == .breathIntro else { return }
        Haptics.strong()
        countdownTask?.cancel()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
            stage = .breathCountdown
        }
        countdownTask = Task { @MainActor in
            await runCountdown()
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.84)) { stage = .breath }
            voice.beginRespiratorySample()
            countdownTask = nil
        }
    }

    private func runCountdown() async {
        for value in [3, 2, 1] {
            countdownValue = value
            Haptics.soft()
            try? await Task.sleep(nanoseconds: 700_000_000)
        }
        countdownValue = nil
    }

    private func analyzeMotorSample(isRepeat: Bool) {
        guard analysisTask == nil else { return }
        withAnimation(.easeInOut(duration: 0.25)) { stage = isRepeat ? .repeatAnalyzing : .analyzing }
        analysisTask = Task { @MainActor in
            await voice.finishMotorSample()
            guard !Task.isCancelled else { return }
            finalMotorResult = nil
            confirmationCompleted = false
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { stage = .result }
            analysisTask = nil
            Haptics.success()
        }
    }

    private func analyzeBreathSample() {
        guard analysisTask == nil else { return }
        withAnimation(.easeInOut(duration: 0.25)) { stage = .breathAnalyzing }
        analysisTask = Task { @MainActor in
            await voice.finishRespiratorySample()
            guard !Task.isCancelled else { return }
            finalRespiratoryResult = voice.respiratoryScreen
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { stage = .breathResult }
            analysisTask = nil
            voice.respiratoryScreen == nil ? Haptics.strong() : Haptics.success()
        }
    }

    private func complete(microphoneAuthorized: Bool) {
        guard !completed else { return }
        completed = true
        let result = VoiceResult(
            microphoneAuthorized: microphoneAuthorized,
            completion: min(1, voice.motorSampleDuration / motorTargetSeconds),
            speechStability: nil,
            voiceActivityRatio: voice.voiceActivityRatio,
            noiseLevel: voice.noiseLevel,
            parkinsonsVoiceProbability: nil,
            parkinsonsVoiceQuality: nil,
            spontaneousWordCount: nil,
            spontaneousLexicalDiversity: nil,
            respiratoryWheezeLikelihood: finalRespiratoryResult?.wheezeLikelihood,
            respiratoryRecordingQuality: finalRespiratoryResult?.recordingQuality,
            respiratoryBreathSeconds: finalRespiratoryResult?.breathSeconds,
            respiratoryAirflowIrregularity: finalRespiratoryResult?.airflowIrregularity
        )
        voice.stop()
        onComplete(result)
    }

}

private enum VoiceCaptureStage {
    case ready
    case sampleIntro
    case vowelCountdown
    case vowel
    case analyzing
    case repeatPrompt
    case repeatCountdown
    case repeatVowel
    case repeatAnalyzing
    case result
    case breathIntro
    case breathCountdown
    case breath
    case breathAnalyzing
    case breathResult

    var title: String {
        switch self {
        case .ready: "voice sample"
        case .sampleIntro: "one longer ahhh"
        case .vowelCountdown: "steady breath"
        case .vowel: "hold a steady ahhh"
        case .analyzing: "making the signal visible"
        case .repeatPrompt: "confirmation needed"
        case .repeatCountdown: "second sample"
        case .repeatVowel: "repeat the steady ahhh"
        case .repeatAnalyzing: "comparing both samples"
        case .result: "voice check complete"
        case .breathIntro: "breathing sample"
        case .breathCountdown: "quiet breath"
        case .breath: "breathe normally"
        case .breathAnalyzing: "screening breath acoustics"
        case .breathResult: "respiratory acoustic screen"
        }
    }

    var detail: String {
        switch self {
        case .ready: "hold one comfortable ahhh for six seconds."
        case .sampleIntro: "one sustained sound gives the local voice check a clean sample."
        case .vowelCountdown: "after the countdown, hold ahhh at a normal pitch and volume."
        case .vowel: "take a comfortable breath, then sustain ahhh at a normal pitch and volume."
        case .analyzing: "checking this voice sample locally."
        case .repeatPrompt: "the first sample was elevated or too limited to report without a second check."
        case .repeatCountdown: "match the first sample as closely as you comfortably can."
        case .repeatVowel: "keep the same comfortable pitch and volume while the second ring closes."
        case .repeatAnalyzing: "both on-device results are being quality-weighted."
        case .result: "your measured voice sample is saved. no disease score is created."
        case .breathIntro: "this optional sample measures wheeze-like acoustic patterns from real breathing audio."
        case .breathCountdown: "hold the phone close and breathe normally after the countdown."
        case .breath: "breathe through your mouth at a normal pace near the bottom microphone."
        case .breathAnalyzing: "breathing audio is being checked locally for acoustic patterns and quality."
        case .breathResult: "this is an acoustic screen, not a respiratory disease diagnosis."
        }
    }

    var usesVowelCapture: Bool {
        self == .vowel || self == .analyzing || self == .repeatVowel || self == .repeatAnalyzing
    }

    var isCountdown: Bool {
        self == .vowelCountdown || self == .repeatCountdown || self == .breathCountdown
    }

    var usesBreathCapture: Bool {
        self == .breath || self == .breathAnalyzing
    }

    var countdownTitle: String {
        switch self {
        case .vowelCountdown: "hold ahhh when the countdown ends"
        case .repeatCountdown: "repeat the steady voice sample"
        case .breathCountdown: "breathe normally after the countdown"
        default: "starting"
        }
    }

}

private struct VoiceCountdownView: View {
    let value: Int
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                LivingPortalView(size: 126, intensity: 0.9, activity: 0.5, motion: 2.2, interactive: false)
                Text("\(value)")
                    .font(.system(size: 46, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(VentureTheme.ink)
                    .contentTransition(.numericText())
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(VentureTheme.secondary)
        }
        .padding(.vertical, 10)
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
    }
}

private struct VoiceSampleIntroduction: View {
    var body: some View {
        VStack(spacing: 14) {
            LivingPortalView(size: 112, intensity: 0.82, activity: 0.42, motion: 1.8, interactive: false)
            Text("take a comfortable breath")
                .font(.title3.weight(.semibold))
            Text("When you start, hold “ahhh” at your normal pitch until the orb completes. This six-second sample is saved as a local signal only.")
                .font(.caption)
                .foregroundStyle(VentureTheme.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 10)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

private struct MicrophonePlacementGuide: View {
    let level: Double

    private var guidance: String {
        if level < 0.025 { return "move the phone closer to your mouth" }
        if level > 0.72 { return "move slightly away from the microphone" }
        return "microphone distance looks good"
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 15, weight: .medium))
            VStack(alignment: .leading, spacing: 1) {
                Text(guidance).font(.caption.weight(.semibold))
                Text("Hold the phone about a hand-width away, with the bottom edge facing your mouth.")
                    .font(.caption2)
                    .foregroundStyle(VentureTheme.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(VentureTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ConfirmationVoicePrompt: View {
    let firstResult: ParkinsonVoiceScreenResult?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 34, weight: .light))
            Text("one more sample helps")
                .font(.caption.weight(.semibold))
            Text(firstResult?.confirmationReason ?? "A second sample can reduce the influence of one noisy recording.")
                .font(.caption2)
                .foregroundStyle(VentureTheme.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 12)
    }
}

private struct BreathSampleIntroduction: View {
    var body: some View {
        VStack(spacing: 14) {
            LivingPortalView(size: 112, intensity: 0.76, activity: 0.34, motion: 1.6, interactive: false)
            Text("one quiet breathing sample")
                .font(.title3.weight(.semibold))
            Text("Hold the bottom microphone near your mouth or upper chest. venture measures wheeze-like acoustic patterns and sample quality from the audio.")
                .font(.caption)
                .foregroundStyle(VentureTheme.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 10)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

private struct BreathingSampleView: View {
    let progress: Double
    let analyzing: Bool

    var body: some View {
        ZStack {
            Circle().stroke(VentureTheme.line, lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(VentureTheme.ink.opacity(0.78), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.12), value: progress)
            VStack(spacing: 4) {
                Image(systemName: analyzing ? "waveform.path.ecg" : "wind")
                    .font(.system(size: 26, weight: .light))
                Text(analyzing ? "screening" : "breathe")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(VentureTheme.ink)
        }
        .frame(width: 132, height: 132)
        .padding(.vertical, 8)
    }
}

private struct SustainedVowelView: View {
    let progress: Double
    let analyzing: Bool

    var body: some View {
        ZStack {
            Circle().stroke(VentureTheme.line, lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(VentureTheme.ink, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.12), value: progress)
            Text(analyzing ? "listening" : "ahhh")
                .font(.system(size: analyzing ? 17 : 48, weight: .light, design: .rounded))
        }
        .frame(width: 132, height: 132)
        .padding(.vertical, 8)
    }
}

private struct RespiratoryModelResultView: View {
    let result: RespiratoryAcousticScreenResult?
    let error: String?

    var body: some View {
        VStack(spacing: 10) {
            if let result {
                Text(result.wheezeLikelihood, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 42, weight: .light, design: .rounded).monospacedDigit())
                Text(result.classification)
                    .font(.caption.weight(.semibold))
                HStack(spacing: 14) {
                    metric("quality", result.recordingQuality)
                    metric("airflow", result.airflowIrregularity)
                    VStack(spacing: 2) {
                        Text(result.breathSeconds, format: .number.precision(.fractionLength(1)))
                            .font(.caption.monospacedDigit().weight(.semibold))
                        Text("seconds")
                            .font(.system(size: 9))
                            .foregroundStyle(VentureTheme.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                Text(result.needsFollowUp
                     ? "repeat in a quiet room. persistent breathing symptoms should be reviewed with a qualified clinician."
                     : "no elevated wheeze-like pattern was measured in this sample.")
                    .font(.caption2)
                    .foregroundStyle(VentureTheme.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("breathing screen unavailable")
                    .font(.headline)
                Text(error ?? "the breathing audio could not be screened.")
                    .font(.caption)
                    .foregroundStyle(VentureTheme.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 12)
    }

    private func metric(_ title: String, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text(value, format: .percent.precision(.fractionLength(0)))
                .font(.caption.monospacedDigit().weight(.semibold))
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(VentureTheme.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct VoiceModelResultView: View {
    var body: some View {
        VStack(spacing: 5) {
            Text("voice sample captured")
                .font(.headline)
            Text("six-second sustained sound recorded locally")
                .font(.caption2)
                .foregroundStyle(VentureTheme.secondary)
            Text("This check does not produce a Parkinson’s probability or diagnosis.")
                .font(.caption2)
                .foregroundStyle(VentureTheme.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

private struct VoiceProcessView: View {
    let stage: VoiceCaptureStage
    let vowelProgress: Double

    private var preparationComplete: Bool {
        switch stage {
        case .ready, .vowelCountdown:
            return false
        default:
            return true
        }
    }

    private var vowelComplete: Bool {
        switch stage {
        case .result, .breathIntro, .breathCountdown, .breath, .breathAnalyzing, .breathResult:
            return true
        default:
            return false
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            VoiceProcessStep(title: "prepare", active: stage == .ready || stage == .vowelCountdown, complete: preparationComplete, progress: stage == .vowelCountdown ? 0.5 : 0)
            VoiceProcessStep(title: "ahhh", active: stage.usesVowelCapture || stage == .vowelCountdown || stage == .repeatCountdown, complete: vowelComplete, progress: vowelProgress)
            VoiceProcessStep(title: "next", active: stage == .result, complete: false, progress: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Voice check progress")
    }
}

private struct VoiceProcessStep: View {
    let title: String
    let active: Bool
    let complete: Bool
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Capsule()
                .fill(complete ? VentureTheme.sage : active ? VentureTheme.ink : VentureTheme.line)
                .frame(height: 4)
                .overlay(alignment: .leading) {
                    if active {
                        Capsule()
                            .fill(VentureTheme.sage)
                            .frame(width: max(8, CGFloat(progress) * 80), height: 4)
                    }
                }
            Text(title)
                .font(.system(size: 10, weight: active || complete ? .semibold : .regular))
                .foregroundStyle(active || complete ? VentureTheme.ink : VentureTheme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LiveWaveform: View {
    let level: Double
    let active: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 15.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<24, id: \.self) { index in
                    let oscillation = abs(sin(time * 4 + Double(index) * 0.78))
                    Capsule()
                        .fill(index.isMultiple(of: 3) ? VentureTheme.sage : VentureTheme.ink.opacity(0.7))
                        .frame(width: 3, height: 8 + (active ? max(level, 0.08) : 0.03) * oscillation * 82)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().stroke(.white.opacity(0.62), lineWidth: 0.7) }
    }
}

private struct CognitiveTaskView: View {
    @State private var stage: CognitiveStage = .memoryShowing
    @State private var memoryChoice: String?
    @State private var switchTrial = 0
    @State private var switchCorrect = 0
    @State private var switchDirections = [true, false, true, false].shuffled()
    @State private var inhibitionTrial = 0
    @State private var inhibitionCorrect = 0
    @State private var inhibitionTrials = InhibitionTrial.makeSet()
    @State private var memoryTrial = MemoryTrial.make()
    @State private var recalledWords: Set<String> = []
    @State private var completed = false
    @State private var moodQuestionIndex = 0
    @State private var moodAnswers: [Int?] = [nil, nil]

    let onComplete: (CognitiveResult) -> Void

    init(onComplete: @escaping (CognitiveResult) -> Void) {
        self.onComplete = onComplete
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-moodResultPreview") {
            _stage = State(initialValue: .moodResult)
            _moodAnswers = State(initialValue: [2, 2])
        }
#endif
    }

    var body: some View {
        VStack(spacing: 20) {
            TaskHeader(
                step: "03",
                title: title,
                detail: instruction,
                skip: stage == .moodResult ? nil : stage == .mood ? finishCognition : skipCognition
            )
            CognitiveStageProgress(stage: stage)
            Spacer()
            taskContent
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
    }

    @ViewBuilder private var taskContent: some View {
        switch stage {
        case .memoryShowing:
            VStack(spacing: 24) {
                Text(memoryTrial.target)
                    .font(.system(size: 62, weight: .medium, design: .rounded).monospacedDigit())
                    .tracking(12)
                    .transition(.scale.combined(with: .opacity))
                HStack(spacing: 8) {
                    ForEach(memoryTrial.words, id: \.self) { word in
                        Text(word)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                Button("i'm ready") {
                    Haptics.selected()
                    withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) { stage = .memoryAnswer }
                }
                .buttonStyle(VenturePrimaryButtonStyle())
            }
        case .memoryAnswer:
            VStack(spacing: 11) {
                ForEach(memoryTrial.options, id: \.self) { option in
                    Button(option) { answerMemory(option) }
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .buttonStyle(VentureSecondaryButtonStyle())
                }
            }
        case .switching:
            VStack(spacing: 26) {
                Image(systemName: currentSwitchDirection ? "arrow.right" : "arrow.left")
                    .font(.system(size: 76, weight: .light))
                    .contentTransition(.symbolEffect(.replace))
                Text("tap the opposite direction")
                    .font(.caption)
                    .foregroundStyle(VentureTheme.secondary)
                HStack(spacing: 14) {
                    directionButton("arrow.left", choseRight: false)
                    directionButton("arrow.right", choseRight: true)
                }
            }
        case .inhibition:
            VStack(spacing: 24) {
                Text(currentInhibition.word)
                    .font(.system(size: 48, weight: .medium, design: .rounded))
                    .foregroundStyle(currentInhibition.ink.color)
                    .contentTransition(.numericText())
                Text("tap the ink color")
                    .font(.caption)
                    .foregroundStyle(VentureTheme.secondary)
                HStack(spacing: 14) {
                    inhibitionButton(.blue)
                    inhibitionButton(.violet)
                }
            }
        case .delayedRecall:
            VStack(spacing: 18) {
                Text("select the three words shown earlier")
                    .font(.caption)
                    .foregroundStyle(VentureTheme.secondary)
                FlowLayout(spacing: 9) {
                    ForEach(memoryTrial.recallOptions, id: \.self) { word in
                        Button {
                            toggleRecall(word)
                        } label: {
                            Text(word)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 16)
                                .frame(height: 46)
                                .background(
                                    recalledWords.contains(word) ? VentureTheme.ink : Color.clear,
                                    in: Capsule()
                                )
                                .foregroundStyle(recalledWords.contains(word) ? .white : VentureTheme.ink)
                                .overlay { Capsule().stroke(VentureTheme.line, lineWidth: 0.8) }
                        }
                        .buttonStyle(HapticPlainButtonStyle())
                    }
                }
                if recalledWords.count == memoryTrial.words.count {
                    Button("continue to mood check") {
                        Haptics.selected()
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                            stage = .mood
                        }
                    }
                        .buttonStyle(VenturePrimaryButtonStyle())
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        case .mood:
            VStack(spacing: 18) {
                Text("over the last 2 weeks")
                    .font(.caption)
                    .foregroundStyle(VentureTheme.secondary)
                Text(MoodQuestion.all[moodQuestionIndex].prompt)
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
                VStack(spacing: 10) {
                    ForEach(Array(MoodQuestion.answers.enumerated()), id: \.offset) { value, label in
                        Button(label) { answerMood(value) }
                            .buttonStyle(VentureSecondaryButtonStyle())
                    }
                }
                Text("PHQ-2 is a brief screen. It does not diagnose depression.")
                    .font(.caption2)
                    .foregroundStyle(VentureTheme.secondary)
                    .multilineTextAlignment(.center)
            }
        case .moodResult:
            let guidance = PHQ2Screen.guidance(score: moodScore ?? 0)
            VStack(spacing: 18) {
                Image(systemName: guidance.needsFollowUp ? "heart.text.clipboard.fill" : "heart.text.clipboard")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(guidance.needsFollowUp ? VentureTheme.warm : VentureTheme.ink)

                VStack(spacing: 5) {
                    Text(guidance.status)
                        .font(.system(size: 30, weight: .light, design: .rounded))
                    Text("mood context")
                        .font(.subheadline.weight(.semibold))
                }

                Text(guidance.action)
                    .font(.subheadline)
                    .foregroundStyle(VentureTheme.secondary)
                    .multilineTextAlignment(.center)

                if let safety = guidance.safety {
                    Text(safety)
                        .font(.caption)
                        .foregroundStyle(VentureTheme.secondary)
                        .multilineTextAlignment(.center)
                }

                Button("save measured result", action: finishCognition)
                    .buttonStyle(VenturePrimaryButtonStyle())
            }
        }
    }

    private var title: String {
        switch stage {
        case .memoryShowing, .memoryAnswer: "Working memory"
        case .switching: "Quick reaction"
        case .inhibition: "Interference control"
        case .delayedRecall: "Delayed recall"
        case .mood, .moodResult: "Mood screen"
        }
    }

    private var instruction: String {
        switch stage {
        case .memoryShowing: "Remember this sequence, then continue when you are ready."
        case .memoryAnswer: "Choose the sequence you saw."
        case .switching: "Tap the opposite arrow four times."
        case .inhibition: "Ignore the word. Choose its color."
        case .delayedRecall: "Recall information after an attention task."
        case .mood: "Two validated self-report questions add context that pupil measurements cannot provide alone."
        case .moodResult: "Review the measured screen and one next action before saving it."
        }
    }

    private func answerMemory(_ option: String) {
        memoryChoice = option
        Haptics.selected()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.84)) { stage = .switching }
    }

    private func skipCognition() {
        completed = true
        onComplete(CognitiveResult(memoryScore: nil, attentionScore: nil, executiveFunctionScore: nil, phq2Score: nil))
    }

    private func answerMood(_ value: Int) {
        moodAnswers[moodQuestionIndex] = value
        Haptics.selected()
        if moodQuestionIndex < MoodQuestion.all.count - 1 {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.84)) {
                moodQuestionIndex += 1
            }
        } else {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                stage = .moodResult
            }
        }
    }

    private var moodScore: Int? {
        PHQ2Screen.score(firstAnswer: moodAnswers[0], secondAnswer: moodAnswers[1])
    }

    private func directionButton(_ symbol: String, choseRight: Bool) -> some View {
        Button {
            let expectedRight = !currentSwitchDirection
            if choseRight == expectedRight { switchCorrect += 1 }
            switchTrial += 1
            Haptics.selected()
            if switchTrial >= switchDirections.count {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                    stage = .mood
                }
            }
        } label: {
            Image(systemName: symbol).font(.title2)
        }
        .buttonStyle(VentureSecondaryButtonStyle())
    }

    private var currentSwitchDirection: Bool {
        switchDirections[min(switchTrial, switchDirections.count - 1)]
    }

    private var currentInhibition: InhibitionTrial {
        inhibitionTrials[min(inhibitionTrial, inhibitionTrials.count - 1)]
    }

    private func inhibitionButton(_ choice: InhibitionColor) -> some View {
        Button {
            if choice == currentInhibition.ink { inhibitionCorrect += 1 }
            inhibitionTrial += 1
            Haptics.selected()
            if inhibitionTrial >= inhibitionTrials.count {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                    stage = .delayedRecall
                }
            }
        } label: {
            Circle()
                .fill(choice.color)
                .frame(width: 66, height: 66)
                .overlay { Circle().stroke(.white, lineWidth: 2) }
        }
        .buttonStyle(HapticPlainButtonStyle())
        .accessibilityLabel(choice.accessibilityName)
    }

    private func toggleRecall(_ word: String) {
        Haptics.selected()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            if recalledWords.contains(word) {
                recalledWords.remove(word)
            } else if recalledWords.count < memoryTrial.words.count {
                recalledWords.insert(word)
            }
        }
    }

    private func finishCognition() {
        guard !completed else { return }
        completed = true
        let score = CognitiveBatteryScorer.score(
            immediateCorrect: memoryChoice.map { $0 == memoryTrial.target },
            recalledWords: recalledWords,
            targetWords: Set(memoryTrial.words),
            switchCorrect: switchCorrect,
            switchTrials: switchTrial,
            inhibitionCorrect: inhibitionCorrect,
            inhibitionTrials: inhibitionTrial
        )
        onComplete(CognitiveResult(
            memoryScore: score.memory,
            attentionScore: score.attention,
            executiveFunctionScore: score.executiveFunction,
            phq2Score: PHQ2Screen.score(firstAnswer: moodAnswers[0], secondAnswer: moodAnswers[1])
        ))
    }
}

private struct CognitiveStageProgress: View {
    let stage: CognitiveStage

    private let labels = ["memory", "reaction", "mood"]

    private var currentIndex: Int {
        switch stage {
        case .memoryShowing, .memoryAnswer: 0
        case .switching: 1
        case .inhibition, .delayedRecall: 1
        case .mood, .moodResult: 2
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                VStack(spacing: 5) {
                    Capsule()
                        .fill(index <= currentIndex ? VentureTheme.ink : VentureTheme.line)
                        .frame(height: 3)
                    Text(label)
                        .font(.system(size: 9))
                        .foregroundStyle(index == currentIndex ? VentureTheme.ink : VentureTheme.secondary)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: currentIndex)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cognitive task \(currentIndex + 1) of \(labels.count): \(labels[currentIndex])")
    }
}

private enum MoodQuestion {
    static let all = [
        MoodQuestionItem(prompt: "little interest or pleasure in doing things"),
        MoodQuestionItem(prompt: "feeling down, depressed, or hopeless")
    ]
    static let answers = ["not at all", "several days", "more than half the days", "nearly every day"]
}

private struct MoodQuestionItem {
    let prompt: String
}

private enum InhibitionColor: CaseIterable {
    case blue
    case violet

    var color: Color {
        switch self {
        case .blue: Color(red: 0.20, green: 0.39, blue: 0.78)
        case .violet: Color(red: 0.52, green: 0.27, blue: 0.68)
        }
    }

    var accessibilityName: String {
        switch self {
        case .blue: "blue"
        case .violet: "violet"
        }
    }
}

private struct InhibitionTrial {
    let word: String
    let ink: InhibitionColor

    static func makeSet() -> [InhibitionTrial] {
        [
            InhibitionTrial(word: "blue", ink: .violet),
            InhibitionTrial(word: "violet", ink: .blue),
            InhibitionTrial(word: "blue", ink: .blue),
            InhibitionTrial(word: "violet", ink: .violet),
            InhibitionTrial(word: "violet", ink: .blue),
            InhibitionTrial(word: "blue", ink: .violet)
        ].shuffled()
    }
}

private struct MemoryTrial {
    let target: String
    let options: [String]
    let words: [String]
    let recallOptions: [String]

    static func make() -> MemoryTrial {
        let digits = (0..<4).map { _ in String(Int.random(in: 0...9)) }.joined()
        var choices: Set<String> = [digits]
        while choices.count < 3 {
            var candidate = Array(digits)
            let index = Int.random(in: candidate.indices)
            var replacement = Character(String(Int.random(in: 0...9)))
            while replacement == candidate[index] {
                replacement = Character(String(Int.random(in: 0...9)))
            }
            candidate[index] = replacement
            choices.insert(String(candidate))
        }
        let wordPools = [
            ["river", "velvet", "lantern"],
            ["garden", "silver", "window"],
            ["forest", "coffee", "button"]
        ]
        let words = (wordPools.randomElement() ?? wordPools[0]).shuffled()
        let wordSet = Set(words)
        let distractors = ["pencil", "ocean", "basket", "cloud", "marble", "bridge"]
            .filter { !wordSet.contains($0) }
            .shuffled()
            .prefix(3)
        return MemoryTrial(
            target: digits,
            options: Array(choices).shuffled(),
            words: words,
            recallOptions: (words + Array(distractors)).shuffled()
        )
    }
}

private struct ScanCompletionView: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            LivingPortalView(size: 170, intensity: 0.76)
            Text("Baseline updated")
                .font(.system(size: 29, weight: .medium, design: .rounded))
            Text("Completed measurements were saved. Skipped tasks remain unavailable.")
                .font(.subheadline)
                .foregroundStyle(VentureTheme.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Enter venture", action: action)
                .buttonStyle(VenturePrimaryButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
    }
}

private struct TaskHeader: View {
    let step: String
    let title: String
    let detail: String
    var skip: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Text(step)
                .font(.caption.monospacedDigit().weight(.semibold))
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(VentureTheme.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let skip {
                Button(action: skip) {
                    Image(systemName: "forward.end")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay { Circle().stroke(.white.opacity(0.7), lineWidth: 0.8) }
                }
                    .foregroundStyle(VentureTheme.ink)
                    .buttonStyle(HapticPlainButtonStyle())
                    .accessibilityLabel("skip")
                    .accessibilityHint("Continues without saving this measurement")
            }
        }
        .padding(.top, 10)
    }
}

private struct ModelStatusPill: View {
    let symbol: String
    let text: String
    let active: Bool

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(active ? Color.white : Color.white.opacity(0.76))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.black.opacity(0.34), in: Capsule())
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private enum ScanPhase { case introduction, eyes, voice, cognition, complete }
private enum CognitiveStage: Hashable { case memoryShowing, memoryAnswer, switching, inhibition, delayedRecall, mood, moodResult }

private extension Duration {
    var seconds: Double {
        let components = self.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
private struct EyeResult {
    var cameraAuthorized = false
    var confidence = 0.0
    var fixationStability = 0.0
    var blinkCount = 0
    var pupilResponse: Double?
    var pupilSymmetry: Double?
    var pupilVariability: Double?
    var gazeTrackingScore: Double?
}
private struct VoiceResult {
    var microphoneAuthorized = false
    var completion = 0.0
    var speechStability: Double?
    var voiceActivityRatio: Double?
    var noiseLevel: Double?
    var parkinsonsVoiceProbability: Double?
    var parkinsonsVoiceQuality: Double?
    var spontaneousWordCount: Int?
    var spontaneousLexicalDiversity: Double?
    var respiratoryWheezeLikelihood: Double?
    var respiratoryRecordingQuality: Double?
    var respiratoryBreathSeconds: Double?
    var respiratoryAirflowIrregularity: Double?
}
private struct CognitiveResult {
    var memoryScore: Double? = nil
    var attentionScore: Double? = nil
    var executiveFunctionScore: Double? = nil
    var phq2Score: Int? = nil
}
