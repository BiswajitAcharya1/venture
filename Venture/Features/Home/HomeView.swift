import SwiftUI

struct HomeView: View {
    @Bindable var store: VentureStore
    @Binding var presentedSheet: AppSheet?
    let onAskVenture: () -> Void

    @State private var selectedFolderID: String?
    @State private var entered = false
    @State private var selectedFinding: FolderFinding?

    private var folders: [SignalFolder] {
        SignalFolder.all(groups: store.metricGroups, forecasts: store.mentalHealthSummary.forecasts)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                driftReading
                currentGuidance
                checkInActions
                folderLibrary
                if let folder = selectedFolder {
                    folderPage(folder)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 132)
        }
        .background(VentureAtmosphereView().ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            withAnimation(.spring(response: 0.85, dampingFraction: 0.88)) { entered = true }
        }
        .sheet(item: $selectedFinding) { finding in
            FolderFindingDetail(
                finding: finding,
                protection: store.supportService.recommendation,
                protectionActive: store.supportService.protectionActive,
                onApply: {
                    guard finding.intervention == .focusProtection else { return }
                    Task {
                        await store.supportService.activateProtection(
                            sleepHours: store.healthService.latest.sleepHours
                        )
                    }
                }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.caption)
                .foregroundStyle(VentureTheme.secondary)
            Text("venture")
                .font(.system(size: 35, weight: .medium, design: .rounded))
                .tracking(-1.5)
                FlipText(
                    words: [
                    "reading the quiet signal",
                    "finding the shape of change",
                    "turning measurements into context"
                ],
                interval: .seconds(2.8)
            )
            .font(.caption)
            .foregroundStyle(VentureTheme.secondary)
            .frame(height: 18, alignment: .leading)
        }
        .opacity(entered ? 1 : 0)
        .offset(y: entered ? 0 : -10)
    }

    private var driftReading: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("today's signal load")
                    .font(.caption)
                    .foregroundStyle(VentureTheme.secondary)
                if store.driftScore != nil {
                    Text(signalLoadLabel)
                        .font(.system(size: 35, weight: .light, design: .rounded))
                } else {
                    FlipText(words: ["learning", "listening", "calibrating"], interval: .seconds(2.6))
                        .font(.system(size: 35, weight: .light, design: .rounded))
                        .frame(height: 44, alignment: .leading)
                }
            }
            Spacer()
            Text("from your recent checks")
                .font(.caption2)
                .foregroundStyle(VentureTheme.secondary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 130)
        }
    }

    private var signalLoadLabel: String {
        guard let score = store.driftScore else { return "learning" }
        switch score {
        case ..<35: return "steady today"
        case ..<65: return "a little different"
        default: return "worth a closer look"
        }
    }

    private var currentGuidance: some View {
        let summary = store.mentalHealthSummary
        let assessment = summary.priorityAssessment
        let needsAttention = assessment.map {
            $0.level == .changed || $0.level == .clinicianReview
        } ?? false

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                LivingPortalView(
                    size: 36,
                    intensity: needsAttention ? 0.82 : 0.48,
                    activity: needsAttention ? 0.68 : 0.24,
                    motion: needsAttention ? 1.5 : 0.8,
                    interactive: false
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(needsAttention ? "what needs attention" : "current read")
                        .font(.caption2)
                        .foregroundStyle(VentureTheme.secondary)
                    Text(assessment?.domain.rawValue.lowercased() ?? "more measurement needed")
                        .font(.headline)
                }
                Spacer()
                if let assessment {
                    Text(assessment.level.rawValue.lowercased())
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(VentureTheme.surfaceMuted, in: Capsule())
                }
            }

            GuidanceLine(
                label: "measured",
                text: assessment == nil ? "No completed scan or connected health measurement is available." : "Your recent measurements are ready to review."
            )
            GuidanceLine(
                label: "next",
                text: assessment?.action ?? "Begin a scan or connect Apple Health. venture will leave missing signals unavailable."
            )
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 18)
        .background(
            VentureTheme.surface,
            in: RoundedRectangle(cornerRadius: 25, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(needsAttention ? VentureTheme.warm.opacity(0.5) : VentureTheme.line, lineWidth: 0.8)
        }
        .opacity(entered ? 1 : 0)
        .offset(y: entered ? 0 : 12)
        .animation(.spring(response: 0.72, dampingFraction: 0.88).delay(0.08), value: entered)
    }

    private var selectedFolder: SignalFolder? {
        folders.first { $0.id == selectedFolderID }
    }

    private var checkInActions: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 3) {
                Text("choose your next step")
                    .font(.headline)
                Text("Address the same concern your way: capture a fresh check, or make sense of what is already measured.")
                    .font(.caption)
                    .foregroundStyle(VentureTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(store.scanCompletedToday ? "check in again" : "start a check-in", action: openScan)
                .buttonStyle(VenturePrimaryButtonStyle())

            Button(action: openAssistant) {
                Label("talk through today's signals", systemImage: "bubble.left.and.bubble.right")
            }
            .buttonStyle(VentureSecondaryButtonStyle())
        }
        .padding(17)
        .background(VentureTheme.surface, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(VentureTheme.line, lineWidth: 0.8)
        }
        .opacity(entered ? 1 : 0)
        .offset(y: entered ? 0 : 12)
        .animation(.spring(response: 0.72, dampingFraction: 0.88).delay(0.12), value: entered)
    }

    private var folderLibrary: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("review what was measured")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VentureTheme.secondary)
                Spacer()
                Text("tap for details")
                    .font(.caption2)
                    .foregroundStyle(VentureTheme.secondary)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 16) {
                    ForEach(Array(folders.enumerated()), id: \.element.id) { index, folder in
                        Button {
                            Haptics.strong()
                            withAnimation(.spring(response: 0.62, dampingFraction: 0.82)) {
                                if selectedFolderID == folder.id {
                                    selectedFolderID = nil
                                } else {
                                    selectedFolderID = folder.id
                                }
                            }
                        } label: {
                            SignalSystemSelector(folder: folder, isSelected: selectedFolderID == folder.id)
                        }
                        .buttonStyle(HapticPlainButtonStyle())
                        .opacity(entered ? 1 : 0)
                        .offset(y: entered ? 0 : CGFloat(12 + index * 3))
                        .animation(.spring(response: 0.72, dampingFraction: 0.88).delay(Double(index) * 0.045), value: entered)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 5)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func folderPage(_ folder: SignalFolder) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 11) {
                LivingPortalView(size: 42, intensity: 0.62, activity: 0.32, motion: 1.2, interactive: false)
                    .hueRotation(.degrees(Double(folders.firstIndex { $0.id == folder.id } ?? 0) * 17))
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.title.lowercased())
                        .font(.system(.title2, design: .serif, weight: .semibold))
                    Text(folder.purpose)
                        .font(.caption2)
                        .foregroundStyle(VentureTheme.secondary)
                }
                Spacer()
                Text(folder.statusText)
                    .font(.caption2)
                    .foregroundStyle(VentureTheme.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 170)
            }
            .padding(.bottom, 14)

            HStack {
                Text("source")
                    .font(.caption2.weight(.semibold))
                Spacer()
                Text(folder.source)
                    .font(.caption2)
                    .foregroundStyle(VentureTheme.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.bottom, 8)

            if let metrics = folder.group?.metrics, !metrics.isEmpty {
                signalSectionTitle("measurements")
                    .padding(.top, 8)
                VStack(spacing: 0) {
                    ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                        MetricPageRow(metric: metric)
                        if index < metrics.count - 1 { Divider().opacity(0.45) }
                    }
                }
            } else if folder.signalCount == 0 {
                SignalFolderSkeleton(message: folder.emptyMessage)
                    .padding(.vertical, 12)
            }

            let domainFindings = findings(for: folder)
            if !domainFindings.isEmpty {
                signalSectionTitle("meaning and next action")
                    .padding(.top, 14)
                FolderFindingsSection(findings: domainFindings) { selectedFinding = $0 }
            }

            if folder.id == "recovery" {
                BloodPressurePage(store: store)
                    .padding(.top, 12)
                WatchECGPage(store: store)
                    .padding(.top, 12)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .background(VentureTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(VentureTheme.line, lineWidth: 0.8) }
        .id(folder.id)
        .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)).combined(with: .move(edge: .top)))
    }

    private func openScan() {
        Haptics.soft()
        presentedSheet = .scan
    }

    private func openAssistant() {
        Haptics.progress()
        onAskVenture()
    }

    private func signalSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(VentureTheme.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func findings(for folder: SignalFolder) -> [FolderFinding] {
        let latest = store.snapshots.max(by: { $0.capturedAt < $1.capturedAt })
        let summary = store.mentalHealthSummary

        switch folder.id {
        case "eyes":
            guard let latest else { return [] }
            let measured = [
                latest.pupilResponse.map { "relative response \(Int($0 * 100))%" },
                latest.pupilSymmetry.map { "symmetry \(Int($0 * 100))%" },
                latest.pupilVariability.map { "estimate variability \(Int($0 * 100))%" },
                latest.fixationStability.map { "fixation stability \(Int($0 * 100))%" },
                latest.gazeTrackingScore.map { "gaze target tracking \(Int($0 * 100))%" }
            ].compactMap { $0 }
            guard !measured.isEmpty else { return [] }
            var results = [
                FolderFinding(
                    id: "pupil-change",
                    title: "pupil signal summary",
                    value: "camera measurement complete",
                    symbol: "eye",
                    evidence: measured.joined(separator: " · "),
                    explanation: "venture measured relative light response, left-right similarity, estimate variability, and fixation. Lighting, glare, eyelids, camera angle, movement, fatigue, and medication can all affect these signals.",
                    action: "Repeat under similar lighting and compare the pattern with your own history. Seek professional eye or medical assessment for persistent symptoms or a repeated visible change.",
                    limitation: "No pupil disease-classification model is installed. These camera measurements cannot identify an eye, retinal, or neurological disease."
                )
            ]
            if let symmetry = latest.pupilSymmetry, symmetry < 0.8 {
                results.append(
                    FolderFinding(
                        id: "pupil-asymmetry",
                        title: "left-right pupil difference",
                        value: "\(Int(((1 - symmetry) * 100).rounded()))% camera-estimated difference",
                        symbol: "exclamationmark.triangle",
                        evidence: "pupil symmetry estimate \(Int((symmetry * 100).rounded()))%",
                        explanation: "The camera estimated a larger left-right difference than this app accepts as a stable symmetric capture. Camera angle, glare, eyelid position, and true pupil asymmetry can look similar to this measurement.",
                        action: "Repeat once with the phone level and even light. If unequal pupils are new or visible without the app, especially with severe headache, eye pain, drooping, weakness, or confusion, seek urgent medical care.",
                        limitation: "This threshold is a capture-quality flag, not a diagnosis or a clinical anisocoria measurement."
                    )
                )
            }
            if let variability = latest.pupilVariability, variability > 0.22 {
                results.append(
                    FolderFinding(
                        id: "pupil-variability",
                        title: "variable pupil estimate",
                        value: "\(Int((variability * 100).rounded()))% variability",
                        symbol: "camera",
                        evidence: "the pupil estimate changed substantially across captured frames",
                        explanation: "Movement, changing reflections, blinking, mascara, eyelid position, and unstable lighting can make the camera estimate fluctuate.",
                        action: "Clean the front camera, use even indoor light, remove glare, hold the phone level, and repeat only once.",
                        limitation: "A variable camera estimate is primarily a measurement-quality problem and should not be interpreted as disease."
                    )
                )
            }
            if let stability = latest.fixationStability, stability < 0.55 {
                results.append(
                    FolderFinding(
                        id: "fixation-instability",
                        title: "fixation changed",
                        value: "\(Int((stability * 100).rounded()))% stability",
                        symbol: "viewfinder",
                        evidence: "eye-landmark position moved during the guided capture",
                        explanation: "Phone movement, looking away, fatigue, distraction, or difficulty holding gaze can reduce this measurement.",
                        action: "Repeat when rested with the phone supported. Discuss persistent vision, balance, or eye-movement symptoms with a clinician.",
                        limitation: "Front-camera fixation tracking is not an eye examination or neurological test."
                    )
                )
            }
            if let gaze = latest.gazeTrackingScore {
                results.append(
                    FolderFinding(
                        id: "gaze-target-task",
                        title: "gaze target task",
                        value: "\(Int((gaze * 100).rounded()))% tracking score",
                        symbol: "scope",
                        evidence: "relative pupil-center movement while following center, horizontal, and vertical targets",
                        explanation: "This task measures whether front-camera pupil-center estimates move consistently with guided targets. Similar saccade and visual-attention tasks appear in Alzheimer’s eye-tracking research, but the research dataset uses dedicated binocular 3D hardware.",
                        action: gaze < 0.55 ? "Repeat once with the phone supported. Persistent new eye-movement, balance, memory, or daily-function changes need clinical evaluation." : "Compare repeated results under similar lighting rather than interpreting one score.",
                        limitation: "This is not the ADEM_TEST classifier and is not an Alzheimer’s, dementia, or neurological diagnosis."
                    )
                )
            }
            return results
        case "voice":
            guard let latest else { return [] }
            let activity = latest.voiceActivityRatio.map { " · active speech \(Int($0 * 100))%" } ?? ""
            let evidence = latest.speechStability.map { "speech timing \(Int($0 * 100))%" + activity } ?? "no timed reading result"
            var results: [FolderFinding] = []
            if latest.speechStability != nil {
                results.append(
                    FolderFinding(
                        id: "speech-change",
                        title: "speech timing",
                        value: assessmentValue(summary, domain: .voice),
                        symbol: "waveform",
                        evidence: evidence,
                        explanation: "venture measured pauses and timing from a voice sample and compares them with your own history.",
                        action: assessmentAction(summary, domain: .voice),
                        limitation: "Speech timing is a screening signal, not a diagnosis."
                    )
                )
            }
            if let dementia = SpeechLanguageDementiaScreeningIndexCalculator.score(snapshot: latest) {
                results.append(
                    FolderFinding(
                        id: "speech-language-dementia-screen",
                        title: "speech-language screen",
                        value: "\(dementia.score)% pattern match",
                        symbol: "text.bubble",
                        evidence: dementia.evidence.joined(separator: " · "),
                        explanation: "venture combines open-speech length, lexical diversity, speech timing, and available cognitive-task context into a speech-language screening index.",
                        action: dementia.score >= 50 ? "Repeat with a quiet, longer open-speech sample. If language, memory, or daily-function changes persist, seek clinical assessment." : "Use repeated scans under similar conditions to build a personal trend.",
                        limitation: "This is an in-app screening index inspired by speech-language research. It is not WavBERT and cannot diagnose or rule out Alzheimer’s disease or dementia."
                    )
                )
            }
            if let mood = VoiceMoodStrainScreeningIndexCalculator.score(snapshot: latest) {
                results.append(
                    FolderFinding(
                        id: "voice-mood-strain-screen",
                        title: "voice mood-strain screen",
                        value: "\(mood.score)% follow-up signal",
                        symbol: "waveform.and.person.filled",
                        evidence: mood.evidence.joined(separator: " · "),
                        explanation: "venture uses measured voice activity, speech timing, recording noise, and open-speech quantity as mood-strain context alongside the PHQ-2 screen when available.",
                        action: mood.score >= 50 ? "Consider the PHQ-2 mood screen and reduce optional interruptions today. If low mood, loss of interest, or safety concerns persist, contact a qualified professional." : "Treat this as context, not a diagnosis, and compare future scans under similar recording conditions.",
                        limitation: "Voice mood strain is not a depression diagnosis and cannot determine whether you do or do not have depression."
                    )
                )
            }
            if let wheeze = latest.respiratoryWheezeLikelihood {
                let quality = latest.respiratoryRecordingQuality.map { " · sample quality \(Int(($0 * 100).rounded()))%" } ?? ""
                let airflow = latest.respiratoryAirflowIrregularity.map { " · airflow irregularity \(Int(($0 * 100).rounded()))%" } ?? ""
                results.append(
                    FolderFinding(
                        id: "respiratory-acoustic-screen",
                        title: "respiratory acoustic screen",
                        value: "\(Int((wheeze * 100).rounded()))% wheeze-like signal",
                        symbol: "wind",
                        evidence: "wheeze-like acoustic signal \(Int((wheeze * 100).rounded()))%" + quality + airflow,
                        explanation: "venture screened the breathing sample for sustained narrowband acoustic patterns often described as wheeze-like, plus recording quality and airflow variability.",
                        action: wheeze >= 0.65 ? "Repeat once in a quiet room. Persistent wheeze, shortness of breath, chest pain, blue lips, or breathing distress needs medical care." : "No elevated wheeze-like acoustic pattern was measured in this sample.",
                        limitation: "This is not COPD, asthma, infection, or pulmonary disease diagnosis. It does not replace a clinician or lung-function testing."
                    )
                )
            }
            return results
        case "cognition":
            let evidence = assessmentEvidence(summary, domain: .cognition)
            guard evidence != "No completed cognitive task." else { return [] }
            let screeningIndex = latest.flatMap { CognitiveScreeningIndexCalculator.score(snapshot: $0) }
            var results = [
                FolderFinding(
                    id: "cognitive-change",
                    title: "cognitive change",
                    value: assessmentValue(summary, domain: .cognition),
                    symbol: "brain.head.profile",
                    evidence: evidence,
                    explanation: "This combines measured memory, attention switching, and interference-control performance.",
                    action: assessmentAction(summary, domain: .cognition),
                    limitation: "Short app tasks can show personal change but cannot diagnose cognitive impairment.",
                    intervention: .focusProtection
                ),
                FolderFinding(
                    id: "cognitive-screening-index",
                    title: "cognitive screening index",
                    value: screeningIndex.map { "\($0.score)%" } ?? "not enough data",
                    symbol: "chart.line.uptrend.xyaxis",
                    evidence: screeningIndex?.evidence.joined(separator: " · ") ?? evidence,
                    explanation: "This percentage is derived only from today's measured memory, attention, and interference-control task performance. Higher means lower task performance in this scan.",
                    action: (screeningIndex?.score ?? 0) >= 50 ? "Repeat when rested. If repeated results stay elevated or daily function changes, seek clinical assessment." : "Keep measuring under similar conditions to build a trend.",
                    limitation: "This is a short cognitive screening signal, not an Alzheimer’s or dementia diagnosis.",
                    intervention: (screeningIndex?.score ?? 0) >= 50 ? .focusProtection : nil
                )
            ]
            if let attention = latest?.attentionScore {
                let attentionConcern = Int(((1 - attention) * 100).rounded())
                results.append(
                    FolderFinding(
                        id: "attention-switch-screen",
                        title: "attention-switch screen",
                        value: "\(attentionConcern)% follow-up signal",
                        symbol: "arrow.left.arrow.right",
                        evidence: "attention task performance \(Int((attention * 100).rounded()))%",
                        explanation: "This result comes directly from the randomized opposite-arrow task. Higher follow-up signal means lower performance on this scan, not a diagnosis.",
                        action: attentionConcern >= 50 ? "Repeat when rested, reduce interruptions, and compare with memory and interference-control results before interpreting a trend." : "Attention switching did not show a large follow-up signal in this scan.",
                        limitation: "This is a short attention task and cannot diagnose ADHD, dementia, Alzheimer disease, anxiety, or another condition.",
                        intervention: attentionConcern >= 50 ? .focusProtection : nil
                    )
                )
            }
            return results
        case "mood":
            guard let latest, let score = latest.phq2Score else { return [] }
            let pupilContext = latest.pupilResponse.map { " · pupil light response \(Int(($0 * 100).rounded()))%" } ?? ""
            let guidance = PHQ2Screen.guidance(score: score)
            return [
                FolderFinding(
                    id: "phq2-screen",
                    title: "depression follow-up screen",
                    value: "PHQ-2 \(score)/6",
                    symbol: "heart.text.clipboard",
                    evidence: "two-week self-report score \(score)/6" + pupilContext,
                    explanation: "PHQ-2 is a validated two-question depression screen. PupilSense research supports pupil measurements as experimental context, but venture does not turn pupil size into a depression probability.",
                    action: [guidance.action, guidance.safety].compactMap { $0 }.joined(separator: " "),
                    limitation: "This screen is not a diagnosis. Lighting, medication, sleep, and camera conditions can change pupil measurements."
                )
            ]
        case "recovery":
            var results: [FolderFinding] = []
            let health = store.healthService.latest
            if let strain = RecoveryStrainCalculator.score(snapshots: store.snapshots) {
                results.append(
                    FolderFinding(
                        id: "recovery-strain",
                        title: "recovery strain",
                        value: "\(strain.score)/100",
                        symbol: "waveform.path.ecg",
                        evidence: strain.evidence.joined(separator: " · "),
                        explanation: "This is a personal-deviation index from HRV and sleep.",
                        action: strain.score >= 50 ? "Protect sleep and reduce optional interruptions today." : "Recovery inputs are close to your measured reference.",
                        limitation: "This is a recovery screening signal, not a stress or anxiety diagnosis.",
                        intervention: strain.score >= 50 ? .focusProtection : nil
                    )
                )
            }
            if
                let rawLevel = health.nightSignalLevel,
                let level = NightSignalAssessment.Level(rawValue: rawLevel),
                let overnight = health.nightSignalOvernightHeartRateBPM,
                let baseline = health.nightSignalBaselineBPM
            {
                let nights = health.nightSignalSampleNights ?? 0
                results.append(
                    FolderFinding(
                        id: "night-signal",
                        title: "wearable anomaly",
                        value: level.title,
                        symbol: "applewatch.radiowaves.left.and.right",
                        evidence: "overnight inactive heart rate \(Int(overnight.rounded())) bpm · personal median \(Int(baseline.rounded())) bpm · \(nights) nights",
                        explanation: "venture runs the supplied Stanford NightSignal thresholds on real Apple Watch heart-rate and step history. Two consecutive elevated nights are required before an alert appears.",
                        action: level == .nearBaseline ? "Continue building the personal baseline." : "Check for illness, poor sleep, alcohol, hard training, medication changes, or sensor error. Seek care for concerning symptoms.",
                        limitation: "This is a wearable anomaly signal. It cannot identify COVID-19, another infection, or any specific condition."
                    )
                )
            }
            if let systolic = health.bloodPressureSystolicMMHg,
               let diastolic = health.bloodPressureDiastolicMMHg {
                let band = BloodPressureBand.classify(systolic: systolic, diastolic: diastolic)
                results.append(
                    FolderFinding(
                        id: "blood-pressure",
                        title: "blood pressure",
                        value: "\(Int(systolic.rounded()))/\(Int(diastolic.rounded()))",
                        symbol: "heart.circle",
                        evidence: "\(band.rawValue) · \(health.bloodPressureSource ?? "Apple Health")",
                        explanation: "This is the latest cuff-recorded blood-pressure sample from Apple Health or a cuff value you entered directly.",
                        action: band.guidance,
                        limitation: "A single reading does not establish hypertension. venture stores measured cuff values and does not estimate blood pressure from camera pixels."
                    )
                )
            }
            if let classification = health.electrocardiogramClassification {
                let guidance = AppleECGGuidance.make(classification: classification)
                results.append(
                    FolderFinding(
                        id: "ecg-classification",
                        title: "ECG rhythm",
                        value: classification.lowercased(),
                        symbol: "waveform.path.ecg.rectangle",
                        evidence: health.electrocardiogramAverageHeartRateBPM.map { "Apple classification · \(Int($0.rounded())) bpm" } ?? "Apple classification",
                        explanation: guidance.meaning,
                        action: guidance.action,
                        limitation: "This is Apple Watch rhythm information, not a full cardiac diagnosis."
                    )
                )
            }
            return results
        case "trajectory":
            let forecasts = summary.forecasts
            guard !forecasts.isEmpty else { return [] }
            return forecasts.map { forecast in
                FolderFinding(
                    id: "forecast-\(forecast.id)",
                    title: forecast.title,
                    value: "\(forecast.bandText) · \(forecast.score)%",
                    symbol: forecastSymbol(for: forecast.domain),
                    evidence: forecast.evidence.joined(separator: " · "),
                    explanation: "venture projects the next follow-up band from measured signals already captured in this app. Higher bands mean the app has more reason to ask for repeat measurement or outside review.",
                    action: forecast.action,
                    limitation: forecast.limitation,
                    intervention: forecast.domain == .depressionFollowUp || forecast.domain == .recovery ? .focusProtection : nil
                )
            }
        default:
            return []
        }
    }

    private func forecastSymbol(for domain: MentalSignalForecast.Domain) -> String {
        switch domain {
        case .parkinsonVoice: "waveform.badge.magnifyingglass"
        case .pupilResponse: "eye"
        case .dementiaPattern: "brain.head.profile"
        case .depressionFollowUp: "heart.text.clipboard"
        case .stressAnxiety: "wind"
        case .respiratory: "lungs"
        case .cardiac: "waveform.path.ecg.rectangle"
        case .recovery: "moon.zzz"
        }
    }

    private func assessmentValue(_ summary: MentalHealthSummary, domain: MentalSignalAssessment.Domain) -> String {
        summary.assessments.first { $0.domain == domain }?.level.rawValue.lowercased() ?? "not enough data"
    }

    private func assessmentEvidence(_ summary: MentalHealthSummary, domain: MentalSignalAssessment.Domain) -> String {
        summary.assessments.first { $0.domain == domain }?.evidence ?? "Not enough data."
    }

    private func assessmentAction(_ summary: MentalHealthSummary, domain: MentalSignalAssessment.Domain) -> String {
        summary.assessments.first { $0.domain == domain }?.action ?? "Complete another measurement under similar conditions."
    }
}

private struct FolderFinding: Identifiable {
    let id: String
    let title: String
    let value: String
    let symbol: String
    let evidence: String
    let explanation: String
    let action: String
    let limitation: String
    var intervention: SuggestedIntervention? = nil
}

private struct GuidanceLine: View {
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(VentureTheme.secondary)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private enum SuggestedIntervention: Equatable {
    case focusProtection
}

private struct FolderFindingsSection: View {
    let findings: [FolderFinding]
    let onSelect: (FolderFinding) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(findings.enumerated()), id: \.element.id) { index, finding in
                Button {
                    Haptics.selected()
                    onSelect(finding)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: finding.symbol)
                            .font(.system(size: 16, weight: .medium))
                            .frame(width: 30, height: 30)
                            .background(VentureTheme.surfaceMuted, in: Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(finding.title)
                                .font(.subheadline.weight(.semibold))
                            Text("tap for details")
                                .font(.caption)
                                .foregroundStyle(VentureTheme.secondary)
                                .lineLimit(1)
                        }

                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(VentureTheme.secondary)
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 12)
                }
                .buttonStyle(HapticPlainButtonStyle())

                if index < findings.count - 1 { Divider().opacity(0.45) }
            }
        }
        .padding(.horizontal, 14)
        .background(VentureTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct FolderFindingDetail: View {
    @Environment(\.dismiss) private var dismiss
    let finding: FolderFinding
    let protection: FocusProtectionRecommendation
    let protectionActive: Bool
    let onApply: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 13) {
                        Image(systemName: finding.symbol)
                            .font(.system(size: 20, weight: .medium))
                            .frame(width: 44, height: 44)
                            .background(VentureTheme.surfaceMuted, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(finding.title)
                                .font(.title2.weight(.semibold))
                            Text(finding.value)
                                .font(.subheadline)
                                .foregroundStyle(VentureTheme.secondary)
                        }
                    }

                    FindingDetailBlock(title: "measured", text: finding.evidence)
                    FindingDetailBlock(title: "meaning", text: finding.explanation)
                    FindingDetailBlock(title: "next", text: finding.action)
                    FindingDetailBlock(title: "limit", text: finding.limitation)

                    if finding.intervention == .focusProtection {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("adaptive support")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(VentureTheme.secondary)
                            Text(protection.reason)
                                .font(.subheadline)
                            Button(protectionActive ? "protection is active" : "protect selected distractions") {
                                Haptics.strong()
                                onApply()
                            }
                            .buttonStyle(VenturePrimaryButtonStyle())
                            .disabled(protectionActive)
                            Text("venture shields only apps, categories, and websites you selected. Screen Time access and Apple’s Family Controls entitlement are required.")
                                .font(.caption2)
                                .foregroundStyle(VentureTheme.secondary)
                        }
                    }
                }
                .padding(22)
            }
            .background(VentureTheme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.soft()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(HapticPlainButtonStyle())
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(30)
    }
}

private struct FindingDetailBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(VentureTheme.secondary)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SignalFolder: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let accent: Color
    let purpose: String
    let source: String
    let emptyMessage: String
    let group: MetricGroup?
    var forecastCount = 0

    var signalCount: Int {
        group?.metrics.count ?? forecastCount
    }

    var statusText: String {
        if let group { return group.summary.lowercased() }
        if forecastCount > 0 { return "\(forecastCount) forecast bands" }
        return "not measured yet"
    }

    var statusLabel: String {
        if group != nil || forecastCount > 0 { return "ready" }
        return "waiting"
    }

    static func all(groups: [MetricGroup], forecasts: [MentalSignalForecast]) -> [SignalFolder] {
        let lookup = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        return [
            SignalFolder(id: "eyes", title: "pupils", subtitle: "light response and stability", symbol: "eye", accent: Color(red: 0.25, green: 0.29, blue: 0.36), purpose: "how your pupils responded to controlled light", source: "front camera · Vision landmarks", emptyMessage: "complete the camera-guided pupil scan to add measured data.", group: lookup["eyes"]),
            SignalFolder(id: "voice", title: "voice", subtitle: "activity and noise", symbol: "waveform", accent: Color(red: 0.32, green: 0.30, blue: 0.36), purpose: "signal quality extracted from your sustained voice sample", source: "microphone · Silero VAD", emptyMessage: "complete the sustained voice sample to add measured data.", group: lookup["voice"]),
            SignalFolder(id: "cognition", title: "cognition", subtitle: "memory and attention", symbol: "scope", accent: Color(red: 0.29, green: 0.33, blue: 0.35), purpose: "performance from randomized memory and switching tasks", source: "direct task performance", emptyMessage: "complete the working-memory and attention tasks to add measured data.", group: lookup["cognition"]),
            SignalFolder(id: "mood", title: "mood", subtitle: "validated self-report context", symbol: "heart.text.clipboard", accent: Color(red: 0.35, green: 0.31, blue: 0.34), purpose: "a brief depression follow-up screen with separately labeled pupil context", source: "PHQ-2 self-report · front camera context", emptyMessage: "complete the optional two-question mood screen to add measured data.", group: lookup["mood"]),
            SignalFolder(id: "recovery", title: "recovery", subtitle: "sleep, heart, movement", symbol: "heart.text.square", accent: Color(red: 0.35, green: 0.30, blue: 0.31), purpose: "recovery context that can influence every other signal", source: "Apple Health · Apple Watch when available", emptyMessage: "connect Apple Health to add measured recovery signals.", group: lookup["recovery"]),
            SignalFolder(id: "trajectory", title: "trajectory", subtitle: "5-band follow-up", symbol: "point.topleft.down.curvedto.point.bottomright.up", accent: Color(red: 0.30, green: 0.31, blue: 0.37), purpose: "where measured signals point if the same pattern repeats", source: "app-native forecast · measured signals only", emptyMessage: "complete voice, cognition, mood, ECG, or recovery measurements to create a forecast.", group: nil, forecastCount: forecasts.count)
        ]
    }
}

private struct SignalFolderCover: View {
    let folder: SignalFolder

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(folder.accent)
                .frame(width: 150, height: 70)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 18)
                .padding(.top, 7)

            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [folder.accent, VentureTheme.deepSurface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 214)
                .offset(y: 10)
                .overlay {
                    FolderTexture(accent: folder.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .opacity(0.28)
                }
                .overlay { RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.22), lineWidth: 0.8) }

            HStack(alignment: .center, spacing: 16) {
                Image(systemName: folder.symbol)
                    .font(.system(size: 24, weight: .light))
                    .frame(width: 54, height: 54)
                    .background(.white.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(folder.title)
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                    Text(folder.subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                    Text(folder.statusLabel)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.62))
                }
                Spacer()
                LivingPortalView(size: 48, intensity: 0.48, activity: 0.22, motion: 1.1, interactive: false)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.bottom, 26)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 6)
        .accessibilityElement(children: .combine)
    }
}

private struct SignalSystemSelector: View {
    let folder: SignalFolder
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(isSelected ? VentureTheme.primaryFill : VentureTheme.surfaceMuted)
                Circle()
                    .stroke(isSelected ? Color.white.opacity(0.22) : VentureTheme.line, lineWidth: 0.8)
                Image(systemName: folder.symbol)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white : VentureTheme.ink)
            }
            .frame(width: 58, height: 58)

            Text(folder.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(VentureTheme.ink)
            Text(folder.statusLabel)
                .font(.caption2)
                .foregroundStyle(VentureTheme.secondary)
        }
        .frame(width: 72)
        .scaleEffect(isSelected ? 1.04 : 1)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(folder.title), \(folder.statusLabel)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct FolderTexture: View {
    let accent: Color

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            for index in 0..<48 {
                let seed = Double(index * 37 % 101) / 101
                var path = Path()
                let startY = size.height * CGFloat(seed)
                path.move(to: CGPoint(x: -20, y: startY))
                path.addCurve(
                    to: CGPoint(x: size.width + 20, y: startY + CGFloat((index % 5) - 2) * 18),
                    control1: CGPoint(x: size.width * 0.3, y: startY + CGFloat(sin(Double(index)) * 45)),
                    control2: CGPoint(x: size.width * 0.7, y: startY + CGFloat(cos(Double(index)) * 48))
                )
                context.stroke(path, with: .color(index.isMultiple(of: 3) ? .white.opacity(0.15) : accent.opacity(0.16)), lineWidth: CGFloat(1 + index % 3))
            }
        }
    }
}

private struct MetricPageRow: View {
    let metric: Metric

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(metric.name.lowercased()).font(.subheadline)
                Text(referenceText).font(.caption2).foregroundStyle(VentureTheme.secondary)
            }
            Spacer()
            Text(metric.baseline == nil ? "learning" : "measured")
                .font(.caption.weight(.semibold))
                .foregroundStyle(VentureTheme.secondary)
        }
        .padding(.vertical, 12)
    }

    private var referenceText: String {
        guard metric.baseline != nil else { return "personal reference still learning" }
        return "compared with your personal reference"
    }
}

private struct SignalFolderSkeleton: View {
    let message: String
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(VentureTheme.ink.opacity(pulse ? 0.09 : 0.045))
                        .frame(width: CGFloat(10 + index * 4), height: CGFloat(10 + index * 4))
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Capsule()
                    .fill(VentureTheme.ink.opacity(pulse ? 0.09 : 0.045))
                    .frame(width: 170, height: 10)
                Capsule()
                    .fill(VentureTheme.ink.opacity(pulse ? 0.07 : 0.035))
                    .frame(maxWidth: .infinity)
                    .frame(height: 10)
                Capsule()
                    .fill(VentureTheme.ink.opacity(pulse ? 0.06 : 0.03))
                    .frame(width: 210, height: 10)
            }
            Text(message)
                .font(.caption)
                .foregroundStyle(VentureTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(VentureTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("waiting for measured data. \(message)")
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct BloodPressurePage: View {
    let store: VentureStore

    @State private var showingEntry = false
    @State private var systolic = ""
    @State private var diastolic = ""

    private var metrics: HealthMetrics { store.healthService.latest }
    private var readings: [BloodPressureReading] { Array(metrics.bloodPressureReadings.prefix(7)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().opacity(0.45)
            HStack {
                Text("blood pressure")
                    .font(.headline)
                Spacer()
                Button(showingEntry ? "cancel" : "add cuff reading") {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                        showingEntry.toggle()
                    }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(HapticPlainButtonStyle())
            }

            if showingEntry {
                cuffEntry
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let systolic = metrics.bloodPressureSystolicMMHg,
               let diastolic = metrics.bloodPressureDiastolicMMHg {
                let band = BloodPressureBand.classify(systolic: systolic, diastolic: diastolic)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("\(Int(systolic.rounded()))/\(Int(diastolic.rounded()))")
                        .font(.system(size: 34, weight: .light, design: .rounded).monospacedDigit())
                    Text("mmHg").font(.caption).foregroundStyle(VentureTheme.secondary)
                }
                Text(band.rawValue.lowercased()).font(.subheadline.weight(.semibold))
                Text(band.guidance).font(.caption2).foregroundStyle(VentureTheme.secondary)
                if let date = metrics.bloodPressureDate {
                    Text("\(date.formatted(.dateTime.month().day().hour().minute())) · \(metrics.bloodPressureSource ?? "Apple Health")")
                        .font(.caption2)
                        .foregroundStyle(VentureTheme.secondary)
                }
                Text("range labels follow American Heart Association adult categories and do not diagnose hypertension.")
                    .font(.caption2)
                    .foregroundStyle(VentureTheme.secondary)

                if readings.count > 1 {
                    BloodPressureTrend(readings: Array(readings.reversed()))
                        .frame(height: 92)
                        .padding(.top, 4)
                    HStack(spacing: 16) {
                        PressureLegend(color: VentureTheme.ink, label: "systolic")
                        PressureLegend(color: VentureTheme.sage, label: "diastolic")
                    }
                }

                if readings.count > 1 {
                    VStack(spacing: 0) {
                        ForEach(Array(readings.prefix(5).enumerated()), id: \.element.id) { index, reading in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(Int(reading.systolicMMHg.rounded()))/\(Int(reading.diastolicMMHg.rounded()))")
                                        .font(.subheadline.monospacedDigit().weight(.semibold))
                                    Text(reading.source)
                                        .font(.caption2)
                                        .foregroundStyle(VentureTheme.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(reading.band.rawValue.lowercased())
                                        .font(.caption2)
                                    Text(reading.measuredAt.formatted(.dateTime.month().day()))
                                        .font(.caption2)
                                        .foregroundStyle(VentureTheme.secondary)
                                }
                            }
                            .padding(.vertical, 9)
                            if index < min(readings.count, 5) - 1 {
                                Divider().opacity(0.4)
                            }
                        }
                    }
                }
            } else {
                Text("no cuff reading yet")
                    .font(.caption)
                    .foregroundStyle(VentureTheme.secondary)
                Text("Use a validated upper-arm cuff, sit quietly for five minutes, keep your feet flat and arm supported, then enter the displayed result.")
                    .font(.caption2)
                    .foregroundStyle(VentureTheme.secondary)
            }
            Button(store.healthService.isRefreshing ? "checking Apple Health…" : "refresh blood pressure") {
                Task {
                    if store.healthService.state == .connected {
                        await store.refreshHealth()
                    } else {
                        await store.healthService.requestAccess()
                        await store.refreshHealth()
                    }
                }
            }
            .buttonStyle(VentureSecondaryButtonStyle())
            .disabled(store.healthService.isRefreshing)

            if let message = store.healthService.bloodPressureMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(VentureTheme.secondary)
                    .transition(.opacity)
            }
        }
    }

    private var cuffEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("enter the numbers shown by your cuff")
                .font(.caption)
                .foregroundStyle(VentureTheme.secondary)

            HStack(spacing: 10) {
                PressureField(title: "systolic", text: $systolic)
                PressureField(title: "diastolic", text: $diastolic)
            }

            Button("save measured reading", action: saveReading)
                .buttonStyle(VenturePrimaryButtonStyle())
                .disabled(parsedSystolic == nil || parsedDiastolic == nil)
        }
        .padding(.vertical, 4)
    }

    private var parsedSystolic: Double? {
        Double(systolic.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var parsedDiastolic: Double? {
        Double(diastolic.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func saveReading() {
        guard let parsedSystolic, let parsedDiastolic else { return }
        guard store.recordCuffBloodPressure(systolic: parsedSystolic, diastolic: parsedDiastolic) else { return }
        systolic = ""
        diastolic = ""
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            showingEntry = false
        }
    }
}

private struct PressureField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(VentureTheme.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                TextField("—", text: $text)
                    .keyboardType(.numberPad)
                    .font(.title3.monospacedDigit())
                    .frame(minWidth: 54)
                Text("mmHg")
                    .font(.caption2)
                    .foregroundStyle(VentureTheme.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(VentureTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(VentureTheme.line, lineWidth: 0.8)
            }
        }
    }
}

private struct BloodPressureTrend: View {
    let readings: [BloodPressureReading]

    var body: some View {
        Canvas { context, size in
            let values = readings.flatMap { [$0.systolicMMHg, $0.diastolicMMHg] }
            guard
                readings.count > 1,
                let minimum = values.min(),
                let maximum = values.max()
            else { return }
            let span = max(20, maximum - minimum)
            let floor = minimum - span * 0.12
            let ceiling = maximum + span * 0.12

            draw(
                readings.map(\.systolicMMHg),
                color: VentureTheme.ink,
                floor: floor,
                ceiling: ceiling,
                context: &context,
                size: size
            )
            draw(
                readings.map(\.diastolicMMHg),
                color: VentureTheme.sage,
                floor: floor,
                ceiling: ceiling,
                context: &context,
                size: size
            )
        }
        .accessibilityLabel("Blood pressure trend from \(readings.count) measured cuff readings")
    }

    private func draw(
        _ values: [Double],
        color: Color,
        floor: Double,
        ceiling: Double,
        context: inout GraphicsContext,
        size: CGSize
    ) {
        var path = Path()
        for (index, value) in values.enumerated() {
            let x = size.width * CGFloat(index) / CGFloat(max(1, values.count - 1))
            let ratio = (value - floor) / max(1, ceiling - floor)
            let point = CGPoint(x: x, y: size.height * (1 - CGFloat(ratio)))
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)),
                with: .color(color)
            )
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }
}

private struct PressureLegend: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption2).foregroundStyle(VentureTheme.secondary)
        }
    }
}

private struct WatchECGPage: View {
    let store: VentureStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().opacity(0.45)
            Text("apple watch ecg").font(.headline)
            if let date = store.healthService.latest.electrocardiogramDate {
                if let classification = store.healthService.latest.electrocardiogramClassification {
                    let guidance = AppleECGGuidance.make(classification: classification)
                    Text(guidance.meaning)
                        .font(.caption)
                    Text(guidance.action)
                        .font(.caption2)
                        .foregroundStyle(VentureTheme.secondary)
                }
                if let waveform = store.healthService.latest.electrocardiogramLeadIWaveformMillivolts, waveform.count > 2 {
                    ECGWaveform(values: waveform).frame(height: 92)
                }
                if let profile = ECGScreeningProfile.make(from: store.healthService.latest),
                   let reconstruction = profile.reconstruction {
                    DetailLine(label: "reconstructed leads", value: "\(reconstruction.leadNames.count) screening leads · quality \(reconstruction.qualityScore)%")
                    let highlighted = profile.findings
                        .filter { $0.name.hasPrefix("reconstructed") }
                        .sorted { $0.likelihood > $1.likelihood }
                        .prefix(2)
                    ForEach(Array(highlighted), id: \.name) { finding in
                        DetailLine(label: finding.name.replacingOccurrences(of: "reconstructed ", with: ""), value: "\(finding.likelihood)%")
                    }
                }
                DetailLine(label: "recorded", value: date.formatted(.dateTime.month().day().hour().minute()))
                DetailLine(label: "average rate", value: store.healthService.latest.electrocardiogramAverageHeartRateBPM.map { "\(Int($0.rounded())) bpm" } ?? "not available")
                ECGClassificationMap(current: store.healthService.latest.electrocardiogramClassification)
            } else {
                Text("no watch ecg has been imported.").font(.caption).foregroundStyle(VentureTheme.secondary)
            }
            Button(store.healthService.isImportingECG ? "checking Apple Health…" : "import latest watch ecg") {
                Task { await store.importLatestECG() }
            }
            .buttonStyle(VentureSecondaryButtonStyle())
            .disabled(store.healthService.isImportingECG)
            if let message = store.healthService.ecgMessage {
                Text(message).font(.caption2).foregroundStyle(VentureTheme.secondary)
            }
        }
    }
}

private struct ECGClassificationMap: View {
    let current: String?

    private let classifications = [
        "Sinus rhythm",
        "Atrial fibrillation",
        "Inconclusive · low heart rate",
        "Inconclusive · high heart rate",
        "Inconclusive · poor reading",
        "Inconclusive",
        "Not classified",
        "Unrecognized"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("apple result")
                .font(.caption.weight(.semibold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                ForEach(classifications, id: \.self) { classification in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(classification == current ? VentureTheme.warm : VentureTheme.line)
                            .frame(width: 7, height: 7)
                        Text(classification.lowercased())
                            .font(.system(size: 10, weight: classification == current ? .semibold : .regular))
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 9)
                    .frame(minHeight: 36)
                    .background(
                        classification == current ? VentureTheme.surfaceMuted : VentureTheme.surface,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(VentureTheme.line, lineWidth: 0.7) }
                }
            }
            Text("single-lead watch ECG · no additional disease probabilities")
                .font(.caption2)
                .foregroundStyle(VentureTheme.secondary)
        }
    }
}

private struct ECGWaveform: View {
    let values: [Double]

    var body: some View {
        Canvas { context, size in
            guard let minimum = values.min(), let maximum = values.max(), maximum > minimum else { return }
            var path = Path()
            for (index, value) in values.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
                let y = size.height * CGFloat(1 - (value - minimum) / (maximum - minimum))
                if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(VentureTheme.ink), style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
        }
        .accessibilityLabel("imported Apple Watch lead one ECG waveform")
    }
}

private struct DetailLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.caption)
            Spacer()
            Text(value).font(.caption.monospacedDigit()).multilineTextAlignment(.trailing)
        }
    }
}
