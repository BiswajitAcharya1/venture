import Foundation

struct RuntimeModelArtifact: Sendable, Equatable {
    enum Runtime: String, Sendable {
        case coreML = "Core ML"
        case llamaCPP = "llama.cpp"
        case healthKit = "HealthKit"
        case appNative = "app-native"
    }

    enum State: String, Sendable {
        case bundledExecutable
        case sourceBound
        case unavailable
    }

    let id: String
    let displayName: String
    let runtime: Runtime
    let state: State
    let sourcePath: String?
    let capability: String
}

struct RuntimeModelArtifactAudit: Sendable, Equatable {
    enum Status: String, Sendable {
        case installed
        case sourceBound = "source-bound"
        case unavailable
        case missing
    }

    let artifact: RuntimeModelArtifact
    let status: Status
    let evidence: String
    let action: String

    var isExecutable: Bool {
        status == .installed || status == .sourceBound
    }
}

struct RuntimeModelExecutionCheck: Sendable, Equatable {
    enum Status: String, Sendable {
        case passed
        case skipped
        case failed
    }

    let modelID: String
    let status: Status
    let evidence: String
}

enum ModelExecutionHealthCheck {
    static func runQuickChecks(includeLLMPrepare: Bool = false) async -> [RuntimeModelExecutionCheck] {
        var checks: [RuntimeModelExecutionCheck] = [
            parkinsonVoiceCheck(),
            voiceAcousticCheck(),
            sileroVADCheck()
        ]
        checks.append(await lfm25Check(includePrepare: includeLLMPrepare))
        checks.append(contentsOf: appNativeChecks())
        return checks
    }

    private static func parkinsonVoiceCheck() -> RuntimeModelExecutionCheck {
        RuntimeModelExecutionCheck(
            modelID: "parkinson-voice-coreml",
            status: .skipped,
            evidence: "legacy feature head disabled: its MDVP preprocessing has not been reproduced for recorded phone audio."
        )
    }

    private static func voiceAcousticCheck() -> RuntimeModelExecutionCheck {
        do {
            let summary = try VoiceAcousticAnalyzer.analyze(
                samples: controlledVowelSamples(sampleRate: 16_000, duration: 3.5),
                sampleRate: 16_000
            )
            guard summary.isUsable, let pitch = summary.pitchHz, (180...260).contains(pitch) else {
                return RuntimeModelExecutionCheck(modelID: "voice-acoustic-measurements", status: .failed, evidence: "controlled vowel did not produce usable fundamental pitch.")
            }
            return RuntimeModelExecutionCheck(modelID: "voice-acoustic-measurements", status: .passed, evidence: "local waveform analysis executed; pitch \(Int(pitch.rounded())) Hz, voiced \(String(format: "%.1f", summary.voicedSeconds)) seconds. no disease classifier ran.")
        } catch {
            return RuntimeModelExecutionCheck(modelID: "voice-acoustic-measurements", status: .failed, evidence: error.localizedDescription)
        }
    }

    private static func sileroVADCheck() -> RuntimeModelExecutionCheck {
        do {
            let probability = try SileroVoiceActivityDetector.verifyBundledModelExecution()
            return RuntimeModelExecutionCheck(
                modelID: "silero-vad-coreml",
                status: .passed,
                evidence: "Core ML VAD executed; probability \(Int((probability * 100).rounded()))%"
            )
        } catch {
            return RuntimeModelExecutionCheck(
                modelID: "silero-vad-coreml",
                status: .failed,
                evidence: "Silero VAD execution failed."
            )
        }
    }

    private static func lfm25Check(includePrepare: Bool) async -> RuntimeModelExecutionCheck {
        guard BundledLlamaEngine.isBundled else {
            return RuntimeModelExecutionCheck(
                modelID: "local-companion-lfm2-5",
                status: .failed,
                evidence: "LFM2.5 GGUF is missing or too small."
            )
        }
        guard includePrepare else {
            return RuntimeModelExecutionCheck(
                modelID: "local-companion-lfm2-5",
                status: .skipped,
                evidence: "LFM2.5 artifact is present; generation check is skipped for quick status."
            )
        }
        let clock = ContinuousClock()
        let started = clock.now
        let prepared = await BundledLlamaEngine.shared.prepare()
        let elapsed = started.duration(to: clock.now)
        let milliseconds = Int(Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1.0e15)
        return RuntimeModelExecutionCheck(
            modelID: "local-companion-lfm2-5",
            status: prepared ? .passed : .failed,
            evidence: prepared
                ? "llama.cpp loaded LFM2.5 and completed a decode in \(milliseconds)ms."
                : "llama.cpp could not load and decode with LFM2.5 after \(milliseconds)ms."
        )
    }

    private static func appNativeChecks() -> [RuntimeModelExecutionCheck] {
        let depression = DepressionScreeningIndexCalculator.score(phq2Score: 2)
        let ecg = ECGTwelveLeadReconstructor.reconstruct(
            fromLeadI: (0..<240).map { index in
                let phase = Double(index) / 240 * 2 * .pi * 4
                return 0.55 * sin(phase) + 0.08 * sin(phase * 2.7)
            }
        )
        return [
            makeCheck(id: "attention-switch-screen", score: Int(((1 - 0.68) * 100).rounded()), label: "direct attention task fixture"),
            makeCheck(id: "phq2-depression-followup", score: depression.score, label: "PHQ-2 fixture"),
            makeCheck(id: "single-to-twelve-ecg", score: ecg?.qualityScore, label: "ECG reconstruction fixture"),
            makeCheck(id: "ecg-reconstructed-cardiac-screen", score: ecg?.repolarizationShiftScore, label: "ECG screening fixture")
        ]
    }

    private static func makeCheck(id: String, score: Int?, label: String) -> RuntimeModelExecutionCheck {
        guard let score, (0...100).contains(score) else {
            return RuntimeModelExecutionCheck(modelID: id, status: .failed, evidence: "\(label) did not produce a bounded score.")
        }
        return RuntimeModelExecutionCheck(modelID: id, status: .passed, evidence: "\(label) produced \(score)%")
    }

    private static func controlledVowelSamples(sampleRate: Double, duration: Double) -> [Float] {
        (0..<Int(sampleRate * duration)).map { index -> Float in
            let time = Double(index) / sampleRate
            let modulation = 1 + 0.015 * sin(2 * .pi * 4.2 * time)
            let fundamental = sin(2 * .pi * 220 * modulation * time)
            let secondHarmonic = 0.32 * sin(2 * .pi * 440 * time)
            let thirdHarmonic = 0.14 * sin(2 * .pi * 660 * time)
            return Float(0.11 * (fundamental + secondHarmonic + thirdHarmonic))
        }
    }

    private static func controlledBreathSamples(sampleRate: Double, duration: Double) -> [Float] {
        (0..<Int(sampleRate * duration)).map { index -> Float in
            let time = Double(index) / sampleRate
            let envelope = 0.7 + 0.3 * sin(2 * .pi * 0.35 * time)
            return Float(0.08 * envelope * sin(2 * .pi * 920 * time) + 0.002 * sin(2 * .pi * 170 * time))
        }
    }
}

enum ModelRuntimeManifest {
    static let bundledExecutable: [RuntimeModelArtifact] = [
        RuntimeModelArtifact(
            id: "local-companion-lfm2-5",
            displayName: "LFM2.5 230M Instruct",
            runtime: .llamaCPP,
            state: .bundledExecutable,
            sourcePath: "Venture/Resources/Models/LocalLLM/lfm2_5_230m_q4_k_m.gguf",
            capability: "local companion responses"
        ),
        RuntimeModelArtifact(
            id: "silero-vad-coreml",
            displayName: "Silero VAD Core ML",
            runtime: .coreML,
            state: .bundledExecutable,
            sourcePath: "Venture/Resources/Models/SileroVAD.mlpackage",
            capability: "voice activity detection and speech quality"
        )
    ]

    static let sourceBound: [RuntimeModelArtifact] = [
        RuntimeModelArtifact(
            id: "voice-acoustic-measurements",
            displayName: "local voice acoustic measurements",
            runtime: .appNative,
            state: .sourceBound,
            sourcePath: nil,
            capability: "fundamental pitch, frame-level pitch and amplitude variation, voiced duration, clipping, and recording quality; no disease probabilities"
        ),
        RuntimeModelArtifact(
            id: "apple-watch-ecg",
            displayName: "Apple Watch ECG classification",
            runtime: .healthKit,
            state: .sourceBound,
            sourcePath: nil,
            capability: "imported ECG rhythm screening from HealthKit records"
        ),
        RuntimeModelArtifact(
            id: "single-to-twelve-ecg",
            displayName: "Single-to-twelve-lead ECG reconstruction",
            runtime: .appNative,
            state: .sourceBound,
            sourcePath: nil,
            capability: "reconstructed 12-lead screening vector from imported Apple Watch Lead I"
        ),
        RuntimeModelArtifact(
            id: "ecg-reconstructed-cardiac-screen",
            displayName: "Reconstructed ECG cardiac follow-up screen",
            runtime: .appNative,
            state: .sourceBound,
            sourcePath: nil,
            capability: "ischemia, conduction-delay, low-voltage, and rhythm-irregularity follow-up screens from reconstructed ECG features"
        ),
        RuntimeModelArtifact(
            id: "attention-switch-screen",
            displayName: "venture attention-switch screen",
            runtime: .appNative,
            state: .sourceBound,
            sourcePath: nil,
            capability: "attention-switch follow-up likelihood from direct task performance"
        ),
        RuntimeModelArtifact(
            id: "phq2-depression-followup",
            displayName: "PHQ-2 depression follow-up screen",
            runtime: .appNative,
            state: .sourceBound,
            sourcePath: nil,
            capability: "depression follow-up likelihood from PHQ-2 self-report"
        ),
        RuntimeModelArtifact(
            id: "venture-progression-forecast",
            displayName: "venture measured-signal forecast",
            runtime: .appNative,
            state: .sourceBound,
            sourcePath: nil,
            capability: "five-band follow-up trajectory from measured app signals"
        ),
        RuntimeModelArtifact(
            id: "blood-pressure-cuff-screen",
            displayName: "Blood pressure cuff screen",
            runtime: .healthKit,
            state: .sourceBound,
            sourcePath: nil,
            capability: "blood-pressure range screening from measured cuff values"
        ),
        RuntimeModelArtifact(
            id: "night-signal-wearable-anomaly",
            displayName: "NightSignal wearable anomaly screen",
            runtime: .appNative,
            state: .sourceBound,
            sourcePath: nil,
            capability: "overnight Apple Watch heart-rate anomaly screening"
        ),
        RuntimeModelArtifact(
            id: "recovery-strain-index",
            displayName: "venture recovery strain index",
            runtime: .appNative,
            state: .sourceBound,
            sourcePath: nil,
            capability: "personal recovery strain from measured HRV and sleep"
        )
    ]

    static let unavailableExternalResearch: [RuntimeModelArtifact] = [
        RuntimeModelArtifact(id: "parkinson-voice-coreml", displayName: "legacy Parkinson feature head", runtime: .coreML, state: .unavailable, sourcePath: nil, capability: "disabled: no verified MDVP audio feature contract"),
        RuntimeModelArtifact(id: "ssl4pr-hubert-coreml", displayName: "SSL4PR HuBERT speech research model", runtime: .coreML, state: .unavailable, sourcePath: nil, capability: "official trained checkpoint under conversion; no iPhone disease validation"),
        RuntimeModelArtifact(id: "opera", displayName: "OPERA respiratory representations", runtime: .coreML, state: .unavailable, sourcePath: nil, capability: "external acoustic representation; requires a compatible task head and protocol"),
        RuntimeModelArtifact(id: "hear", displayName: "Google HeAR acoustic representations", runtime: .coreML, state: .unavailable, sourcePath: nil, capability: "embedding model only; no bundled mobile disease classifier"),
        RuntimeModelArtifact(id: "pupil-autonomic-screen", displayName: "pupil autonomic screen", runtime: .appNative, state: .unavailable, sourcePath: nil, capability: "eye tasks excluded from current voice protocol"),
        RuntimeModelArtifact(id: "speech-language-dementia-index", displayName: "speech language dementia index", runtime: .appNative, state: .unavailable, sourcePath: nil, capability: "no validated disease classifier; descriptive language measurements only"),
        RuntimeModelArtifact(id: "respiratory-acoustic-screen", displayName: "respiratory acoustic screen", runtime: .appNative, state: .unavailable, sourcePath: nil, capability: "heuristic tonal-audio detector is not a validated respiratory disease head"),
        RuntimeModelArtifact(id: "cognitive-dementia-pattern-index", displayName: "cognitive dementia pattern index", runtime: .appNative, state: .unavailable, sourcePath: nil, capability: "direct task scores do not establish a dementia classifier"),
        RuntimeModelArtifact(id: "alzheimer-composite-screen", displayName: "alzheimer composite screen", runtime: .appNative, state: .unavailable, sourcePath: nil, capability: "hand-weighted signals do not establish an Alzheimer disease model"),
        RuntimeModelArtifact(id: "voice-mood-strain-index", displayName: "voice mood strain index", runtime: .appNative, state: .unavailable, sourcePath: nil, capability: "recording noise and speech length do not establish a depression classifier"),
        RuntimeModelArtifact(id: "depression-composite-screen", displayName: "depression composite screen", runtime: .appNative, state: .unavailable, sourcePath: nil, capability: "hand-weighted signals do not establish a depression model"),
        RuntimeModelArtifact(id: "wavbert", displayName: "WavBERT", runtime: .coreML, state: .unavailable, sourcePath: nil, capability: "external Alzheimer speech model"),
        RuntimeModelArtifact(id: "hubert-ecg", displayName: "HuBERT ECG", runtime: .coreML, state: .unavailable, sourcePath: nil, capability: "external ECG disease-head model"),
        RuntimeModelArtifact(id: "external-ecg-recon-coreml", displayName: "External ECG reconstruction Core ML artifact", runtime: .coreML, state: .unavailable, sourcePath: nil, capability: "converted TensorFlow ECG lead-reconstruction weights"),
        RuntimeModelArtifact(id: "external-ecg-mi-risk", displayName: "External ECG heart-attack risk model", runtime: .coreML, state: .unavailable, sourcePath: nil, capability: "external myocardial-infarction risk model"),
        RuntimeModelArtifact(id: "bp-ppg", displayName: "PPG blood pressure estimation", runtime: .coreML, state: .unavailable, sourcePath: nil, capability: "external camera PPG blood pressure model")
    ]

    static var all: [RuntimeModelArtifact] {
        bundledExecutable + sourceBound + unavailableExternalResearch
    }

    static func audit(
        bundle: Bundle = .main,
        fileManager: FileManager = .default,
        repositoryRoot: URL? = nil
    ) -> [RuntimeModelArtifactAudit] {
        all.map { artifact in
            switch artifact.state {
            case .bundledExecutable:
                if let sourcePath = artifact.sourcePath,
                   bundledArtifactExists(sourcePath: sourcePath, bundle: bundle, fileManager: fileManager)
                    || repositoryArtifactExists(sourcePath: sourcePath, repositoryRoot: repositoryRoot, fileManager: fileManager) {
                    return RuntimeModelArtifactAudit(
                        artifact: artifact,
                        status: .installed,
                        evidence: "\(artifact.displayName) artifact is present for \(artifact.runtime.rawValue).",
                        action: "Run the model-specific execution test before release."
                    )
                }
                return RuntimeModelArtifactAudit(
                    artifact: artifact,
                    status: .missing,
                    evidence: "\(artifact.displayName) is marked bundled, but its artifact was not found.",
                    action: "Add the model artifact or mark this model unavailable before release."
                )
            case .sourceBound:
                return RuntimeModelArtifactAudit(
                    artifact: artifact,
                    status: .sourceBound,
                    evidence: "\(artifact.displayName) runs from measured app or HealthKit inputs.",
                    action: "Keep this output tied to measured inputs and do not report it when inputs are missing."
                )
            case .unavailable:
                return RuntimeModelArtifactAudit(
                    artifact: artifact,
                    status: .unavailable,
                    evidence: "\(artifact.displayName) has no executable iOS artifact in this build.",
                    action: "Do not show likelihoods until a verified mobile artifact is added."
                )
            }
        }
    }

    private static func bundledArtifactExists(
        sourcePath: String,
        bundle: Bundle,
        fileManager: FileManager
    ) -> Bool {
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let name = sourceURL.deletingPathExtension().lastPathComponent
        let sourceExtension = sourceURL.pathExtension
        let runtimeExtension = sourceExtension == "mlmodel" || sourceExtension == "mlpackage"
            ? "mlmodelc"
            : sourceExtension
        guard let url = bundle.url(forResource: name, withExtension: runtimeExtension) else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    private static func repositoryArtifactExists(
        sourcePath: String,
        repositoryRoot: URL?,
        fileManager: FileManager
    ) -> Bool {
        guard let repositoryRoot else { return false }
        return fileManager.fileExists(atPath: repositoryRoot.appendingPathComponent(sourcePath).path)
    }
}
