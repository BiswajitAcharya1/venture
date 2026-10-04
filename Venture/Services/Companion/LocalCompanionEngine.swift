import Foundation

protocol LocalCompanionProviding: Sendable {
    func respond(to message: String, context: CompanionContext) async -> String
}

protocol StreamingLocalCompanionProviding: LocalCompanionProviding {
    nonisolated func streamResponse(to message: String, context: CompanionContext) -> AsyncStream<String>
}

actor MetricCompanionEngine: LocalCompanionProviding {
    func respond(to message: String, context: CompanionContext) async -> String {
        let lower = message.lowercased()
        let trimmed = lower.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

        if isGreeting(lower) {
            return greetingAnswer(context)
        }
        if trimmed.count <= 2 {
            return "I’m here. Ask about today’s scan, voice, cognition, Apple Health, ECG, privacy, or what to do next."
        }
        if isLowSignalInput(trimmed) {
            return "I can answer, but I need a real question. Try asking: what changed today, explain my voice screen, show my cognitive index, or what should I do next."
        }
        if containsAny(lower, ["thank you", "thanks", "thx"]) {
            return "You're welcome. I can explain a measurement, compare it with your reference, or show what is still unavailable."
        }
        if containsAny(lower, ["suicide", "kill myself", "harm myself", "not safe"]) {
            return "If you may harm yourself or are in immediate danger, call or text 988 in the United States now, or call emergency services. venture cannot provide crisis care."
        }
        if containsAny(lower, ["private", "privacy", "store", "stored", "deleted", "secure", "security", "encrypt"]) {
            return "venture keeps extracted measurements in an AES-256-GCM encrypted file protected by a device-only Keychain key. Production sign-in stores session tokens in Keychain and does not keep the account password locally. Development fallback passwords use salted PBKDF2-SHA256. Camera frames are not saved, and temporary voice audio is deleted when capture ends."
        }
        if containsAny(lower, ["model", "llm", "local ai", "offline", "on device"]) {
            return modelAnswer()
        }
        if containsAny(lower, ["screen time", "protect", "block", "distraction", "notification"]) {
            return protectionAnswer(context)
        }
        if containsAny(lower, ["blood pressure", "systolic", "diastolic", "bp "]) {
            return bloodPressureAnswer(context.health)
        }
        if containsAny(lower, ["ecg", "heart", "arrhythmia", "atrial", "cardiac"]) {
            return ecgAnswer(context.health)
        }
        if containsAny(lower, ["parkinson", "alzheimer", "dementia", "depression", "diagnos", "disease", "emotion"]) {
            return clinicalBoundaryAnswer(question: lower, context: context)
        }
        if containsAny(lower, ["what should i do", "help me", "next step", "action", "solution", "recommend"]) {
            return nextActionAnswer(context)
        }
        if containsAny(lower, ["health", "apple health", "watch data"]) {
            return healthAnswer(context.health)
        }
        if containsAny(lower, ["tell me", "report", "explain", "overview", "status"]) {
            if let latest = context.snapshots.max(by: { $0.capturedAt < $1.capturedAt }) {
                return summaryAnswer(latest: latest, context: context)
            }
            if context.health.hasData {
                return healthAnswer(context.health)
            }
        }

        guard let latest = context.snapshots.max(by: { $0.capturedAt < $1.capturedAt }) else {
            if let priority = context.mentalHealth.priorityAssessment {
                return "Measured reason: \(priority.evidence). Next step: \(priority.action)"
            }
            return "No completed scan is available yet. I can still explain connected Apple Health or Watch ECG data, privacy, security, and what each scan measures."
        }
        if lower.contains("sleep") || lower.contains("recover") || lower.contains("hrv") {
            guard let sleep = context.health.sleepHours ?? latest.sleepHours else { return "No sleep measurement is available from Apple Health." }
            let hrv = (context.health.heartRateVariabilityMilliseconds ?? latest.heartRateVariability).map { " HRV was \(Int($0.rounded())) ms." } ?? ""
            return "Latest sleep was \(sleep.formatted(.number.precision(.fractionLength(1)))) hours.\(hrv) These are recovery measurements, not a mental-health diagnosis."
        }
        if lower.contains("infection") || lower.contains("wearable anomaly") || lower.contains("night signal") || lower.contains("nightsignal") {
            guard
                let rawLevel = context.health.nightSignalLevel,
                let level = NightSignalAssessment.Level(rawValue: rawLevel),
                let overnight = context.health.nightSignalOvernightHeartRateBPM,
                let baseline = context.health.nightSignalBaselineBPM
            else {
                return "NightSignal needs at least seven nights of Apple Watch heart-rate and movement history. No result is available yet."
            }
            return "NightSignal is \(level.title.lowercased()). Overnight inactive heart rate was \(Int(overnight.rounded())) bpm versus a running personal median of \(Int(baseline.rounded())) bpm across \(context.health.nightSignalSampleNights ?? 0) nights. This is an anomaly signal, not an infection diagnosis."
        }
        if lower.contains("voice") || lower.contains("speech") || lower.contains("tremor") {
            if let acoustic = latest.voiceAcousticSummary {
                guard acoustic.isUsable else { return "The voice recording needs another attempt in a quiet place. A limited recording cannot support interpretation." }
                let pitch = acoustic.pitchHz.map { " Average pitch was \(Int($0.rounded())) Hz." } ?? ""
                return "The recording contained \(acoustic.voicedSeconds.formatted(.number.precision(.fractionLength(1)))) seconds of voiced sound.\(pitch) These are acoustic measurements, not Parkinson’s, dementia, or mood predictions."
            }
            guard let value = latest.speechStability else { return "No completed voice measurement is available." }
            let activity = latest.voiceActivityRatio.map { " Voice activity was \(Int($0 * 100))%." } ?? ""
            return "Speech timing stability measured \(Int(value * 100))%.\(activity) This can reveal personal timing change, but it cannot identify Parkinson’s disease or depression."
        }
        if lower.contains("eye") || lower.contains("pupil") {
            return "Eye-test results are not provided. This check measures voice and offers practical next steps."
        }
        if containsAny(lower, ["memory", "attention", "cognition", "cognitive"]) {
            let values = [
                latest.memoryScore.map { "working memory \(Int($0 * 100))%" },
                latest.attentionScore.map { "attention \(Int($0 * 100))%" },
                latest.executiveFunctionScore.map { "interference control \(Int($0 * 100))%" }
            ].compactMap { $0 }
            return values.isEmpty ? "No completed memory or attention task is available." : "Latest task performance: \(values.joined(separator: ", ")). Compare repeated sessions under similar conditions; one session is not a cognitive diagnosis."
        }
        if containsAny(lower, ["summary", "everything", "all data", "today", "overall", "what changed"]) {
            return summaryAnswer(latest: latest, context: context)
        }

        let score = context.mentalHealth.signalLoadScore.map { "Personal signal load is \($0). " } ?? "venture is still learning your personal reference. "
        let evidence = context.mentalHealth.assessments.map { "\($0.domain.rawValue): \($0.level.rawValue)" }.joined(separator: "; ")
        return score + evidence + ". Ask about voice, cognition, sleep, blood pressure, ECG, privacy, or your next measured action."
    }

    private func modelAnswer() -> String {
        let active = ScreeningModelCatalog.all
            .filter { $0.state == .active }
            .map(\.name)
            .joined(separator: ", ")
        switch CompanionRuntimeInfo.current.runtime {
        case .gemma4:
            return "This device is running Gemma 4 E2B locally through llama.cpp. Active measurement models are: \(active). venture supplies measured context and rejects diagnostic certainty."
        case .lfm25:
            return "This device is running the LFM2.5 chat model locally through llama.cpp. Active measurement models are: \(active). venture supplies measured context and rejects diagnostic certainty."
        case .systemModel:
            return "This device is using Apple’s private on-device language model for chat when available. Active measurement models are: \(active). venture supplies measured context and blocks diagnostic claims."
        case .metricEngine:
            return "This device is using venture’s local measured-signal engine. Active measurement models are: \(active). It answers from scan and HealthKit values without sending them to an external AI service."
        }
    }

    private func protectionAnswer(_ context: CompanionContext) -> String {
        if context.screenTimeSelectionCount == 0 {
            return "No apps or categories are selected. Open account center, then focus protection, approve Screen Time when available, and choose what venture may shield."
        }
        return context.screenTimeProtectionActive
            ? "Screen Time protection is active for \(context.screenTimeSelectionCount) selected items."
            : "Protection is ready for \(context.screenTimeSelectionCount) selected items. Ask me to protect distractions to activate it."
    }

    private func bloodPressureAnswer(_ health: HealthMetrics) -> String {
        guard let systolic = health.bloodPressureSystolicMMHg, let diastolic = health.bloodPressureDiastolicMMHg else {
            return "No cuff-recorded blood pressure is available. Add the result from a validated upper-arm cuff or import one from Apple Health. venture does not estimate blood pressure from camera pixels."
        }
        let band = BloodPressureBand.classify(systolic: systolic, diastolic: diastolic)
        let source = health.bloodPressureSource ?? "measured cuff"
        return "Latest cuff blood pressure is \(Int(systolic.rounded()))/\(Int(diastolic.rounded())) mmHg from \(source), in venture’s \(band.rawValue.lowercased()). \(band.guidance)"
    }

    private func ecgAnswer(_ health: HealthMetrics) -> String {
        guard let classification = health.electrocardiogramClassification else {
            return "No Apple Watch ECG is imported. Record one in Apple’s ECG app, then use import latest Watch ECG."
        }
        let guidance = AppleECGGuidance.make(classification: classification)
        let heartRate = health.electrocardiogramAverageHeartRateBPM.map { " Average heart rate was \(Int($0.rounded())) bpm." } ?? ""
        return "\(guidance.meaning)\(heartRate) \(guidance.action) venture does not generate percentages for additional conditions because no validated condition-specific output head is installed for Apple Watch lead-I input."
    }

    private func clinicalBoundaryAnswer(question: String, context: CompanionContext) -> String {
        let latest = context.snapshots.max(by: { $0.capturedAt < $1.capturedAt })
        if question.contains("parkinson") {
            let voice = latest?.voiceActivityRatio.map { "A sustained voice sample was captured with \(Int($0 * 100))% detected voice activity. " } ?? "No completed voice sample is available. "
            return voice + "This app does not estimate Parkinson’s probability or diagnose Parkinson’s disease. Persistent tremor, slowed movement, balance, or speech changes should be reviewed by a clinician."
        }
        if question.contains("alzheimer") || question.contains("dementia") {
            let words = latest?.spontaneousWordCount.map { "Your open-speech sample contained \($0) transcribed words. " } ?? "No open-speech measurement is available. "
            return words + "The app has no verified voice model that can identify Alzheimer’s disease or distinguish types of dementia. Persistent memory, language, or daily-function changes need clinical testing. Get help offers visit preparation, telehealth, and community clinic options."
        }
        if question.contains("depression") || question.contains("emotion") {
            let sleep = context.health.sleepHours.map { "Latest sleep was \($0.formatted(.number.precision(.fractionLength(1)))) hours. " } ?? "No sleep measurement is available. "
            let recovery = RecoveryStrainCalculator.score(snapshots: context.snapshots).map { "Recovery strain is \($0.score)/100 from \($0.evidence.joined(separator: ", ")). " } ?? ""
            let mood = latest?.phq2Score.map { score in
                let guidance = PHQ2Screen.guidance(score: score)
                let safety = guidance.safety.map { " \($0)" } ?? ""
                return "PHQ-2 was \(score)/6. \(guidance.action)\(safety) "
            } ?? "No PHQ-2 screen is available. "
            return mood + sleep + recovery + "Voice and recovery changes are context and cannot diagnose depression."
        }
        return "venture measures personal changes; it cannot diagnose or rule out a disease. Persistent memory, movement, speech, mood, heart, or daily-function changes should be assessed by a qualified clinician."
    }

    private func nextActionAnswer(_ context: CompanionContext) -> String {
        let assessments = context.mentalHealth.assessments
        if let review = assessments.first(where: { $0.level == .clinicianReview }) {
            return "Measured reason: \(review.evidence). Next step: \(review.action)"
        }
        if let changed = assessments.first(where: { $0.level == .changed }) {
            return "Measured reason: \(changed.evidence). Next step: \(changed.action)"
        }
        if context.snapshots.isEmpty {
            return "Complete one scan, or connect Apple Health, so the next action can cite a measured signal."
        }
        return "No large personal deviation is available. Keep the next measurement under similar lighting, noise, and time-of-day conditions."
    }

    private func healthAnswer(_ health: HealthMetrics) -> String {
        let values = [
            health.sleepHours.map { "sleep \($0.formatted(.number.precision(.fractionLength(1)))) hr" },
            health.heartRateVariabilityMilliseconds.map { "HRV \(Int($0.rounded())) ms" },
            health.restingHeartRateBPM.map { "resting heart rate \(Int($0.rounded())) bpm" },
            health.oxygenSaturationPercent.map { "oxygen saturation \($0.formatted(.number.precision(.fractionLength(1))))%" },
            health.stepCount.map { "steps \(Int($0.rounded()))" },
            health.nightSignalOvernightHeartRateBPM.map { "overnight inactive heart rate \(Int($0.rounded())) bpm" },
            formattedBloodPressure(health),
            health.electrocardiogramClassification.map { "Apple ECG \($0)" }
        ].compactMap { $0 }
        return values.isEmpty ? "No Apple Health measurements are available yet." : "Latest Apple Health measurements: \(values.joined(separator: "; "))."
    }

    private func summaryAnswer(latest: CognitiveSnapshot, context: CompanionContext) -> String {
        let values = [
            latest.driftScore.map { "signal load \($0)" },
            latest.speechStability.map { "speech timing \(Int($0 * 100))%" },
            latest.voiceActivityRatio.map { "voice activity \(Int($0 * 100))%" },
            latest.memoryScore.map { "memory \(Int($0 * 100))%" },
            latest.attentionScore.map { "attention \(Int($0 * 100))%" },
            latest.executiveFunctionScore.map { "interference control \(Int($0 * 100))%" },
            formattedSleep(context.health.sleepHours ?? latest.sleepHours),
            (context.health.heartRateVariabilityMilliseconds ?? latest.heartRateVariability).map { "HRV \(Int($0.rounded())) ms" },
            formattedBloodPressure(context.health),
            context.health.electrocardiogramClassification.map { "Apple ECG \($0)" }
        ].compactMap { $0 }
        return "Latest measured values: \(values.joined(separator: "; ")). These are measurements and personal-change estimates, not diagnostic findings."
    }

    private func containsAny(_ text: String, _ terms: [String]) -> Bool {
        terms.contains { text.contains($0) }
    }

    private func normalizedPercent(_ value: Double) -> Int {
        Int(min(100, max(0, value > 1 ? value : value * 100)).rounded())
    }

    private func isGreeting(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return ["hi", "hello", "hey", "good morning", "good afternoon", "good evening"].contains(normalized)
    }

    private func isLowSignalInput(_ text: String) -> Bool {
        let tokens = text
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        guard tokens.count >= 2 else { return false }
        return tokens.allSatisfy { $0.count <= 1 }
    }

    private func greetingAnswer(_ context: CompanionContext) -> String {
        if let score = context.mentalHealth.signalLoadScore {
            return "Hi. Today's measured signal load is \(score). Ask me about cognition, voice, pupils, recovery, blood pressure, or the latest Watch ECG."
        }
        return "Hi. I'm ready. Ask me about a scan, Apple Health, Watch ECG, or what venture still needs to measure."
    }

    private func formattedSleep(_ value: Double?) -> String? {
        guard let value else { return nil }
        return "sleep \(value.formatted(.number.precision(.fractionLength(1)))) hr"
    }

    private func formattedBloodPressure(_ health: HealthMetrics) -> String? {
        guard
            let systolic = health.bloodPressureSystolicMMHg,
            let diastolic = health.bloodPressureDiastolicMMHg
        else { return nil }
        return "cuff blood pressure \(Int(systolic.rounded()))/\(Int(diastolic.rounded())) mmHg"
    }
}
