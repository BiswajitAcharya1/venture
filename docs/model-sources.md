# Model Sources and Boundaries

## Calling experiments

- [AI-clinic-receptionist](https://github.com/mohamedabdelaty74/AI-clinic-receptionist) supplies a FastAPI/Claude receptionist architecture. Venture's independent server adapter preserves bounded tool continuation with a read-only measured-context tool and personalized appointment requests. It needs server-side Anthropic credentials; it is not a bundled model.
- [Nova_Dear-Care](https://github.com/DevDaring/Nova_Dear-Care) supplies an edge-device Bedrock/Nova assistant architecture. The adapter uses the native model request, short conversation history, and opted-in screening context for the user's appointment goal. It needs AWS model access and credentials; it is not local inference.
- [rural-health-ai](https://github.com/MridulHarsh/rural-health-ai) supplies a Flutter triage workflow and TFLite classifiers, with no conversational inference API or published license. Venture executes an independently authored English care/appointment rules adaptation, clearly labeled as having no upstream TFLite inference. Its tested output is a coordination workflow, not clinical model output.

Pinned commits, source-file provenance, configuration and adaptation boundaries live under `calling-service/upstream`. The calling service uses only submitted text and explicitly opted-in summaries. Real calls additionally need Twilio configuration and a separate opt-in; signatures, retry IDs, and limited in-memory sessions are implemented in `calling-service/phone.py`.

## Bundled

- Silero VAD v6 Core ML conversion from FluidInference is bundled for local voice-activity measurement. The model is MIT licensed and runs on 16 kHz mono audio in 256 ms chunks.
- Apple Speech performs optional, locale-specific transcription only when the selected recognizer supports on-device recognition. Unavailable transcription leaves language measurements absent. Biomarker recording uses the built-in microphone in measurement mode with voice processing disabled; recordings and transcripts are discarded after extracted metrics are captured.
- The legacy converted `Mohit6304/Parkinsons-Disease-Detection` 22-feature classifier remains in the repository for attribution, but execution is disabled. Its mobile extractor did not reproduce the MDVP/nonlinear feature contract and cannot justify a Parkinson result. The sustained vowel now produces fundamental pitch, frame-level pitch/amplitude variation, voiced seconds, clipping fraction, and a recording-quality rule. These are descriptive measurements; they are not MDVP jitter/shimmer or disease probabilities.
- Eye tests and eye-derived results are excluded from the current voice screening flow. Legacy camera code is retained, but it supplies no current screening result.
- Raw memory and attention task performance may remain available as descriptive measurements. Hand-weighted Alzheimer/dementia composites are not validated disease classifiers and do not produce public disease output.
- PHQ-2 supplies an optional self-report follow-up screen. A score of 3 or higher recommends fuller assessment. Hand-weighted voice mood/depression composites are not presented as disease model output.
- Stanford NightSignal is ported from its Apache-2.0 Python implementation to Swift. Venture reads raw Apple Watch heart-rate samples and step intervals from HealthKit, calculates inactive overnight heart-rate averages, compares them with the running personal median, and applies the original two-consecutive-night +3/+4 bpm alert rules. The output is a wearable anomaly, not an infection diagnosis.
- LFM2.5 230M Instruct Q4_K_M is bundled under the LFM 1.0 license and runs through the bundled llama.cpp Apple XCFramework. The runtime applies the model's embedded chat template, carries a bounded recent-conversation window, and marks the model running only after a real decode succeeds. Health prompts contain only measured app context, and malformed or unsafe output falls back to Venture's deterministic local metric explainer.
- Apple's Foundation Models framework remains an optional fallback on eligible iOS 26 devices; no prompt is sent to a hosted model.

## Optional download

- Gemma 4 E2B Instruct Q4_0 is an optional 2.8 GB Companion model. The user starts its download from Settings; it is stored in Application Support and is not included in the app bundle or repository. The [upstream GGUF model card](https://huggingface.co/ggml-org/gemma-4-E2B-it-GGUF) identifies it as Apache-2.0 licensed.

## Evaluated but not represented as running

- MediaPipe Face Landmarker is distributed for iOS through MediaPipe Tasks/CocoaPods rather than the current Swift package build. Venture does not display a MediaPipe label while Apple Vision is the active landmark backend.
- DeepFilterNet3-CoreML requires its accompanying STFT, ERB, normalization, and deep-filter post-processing pipeline. Bundling only the neural network would not produce valid enhanced audio, so this build uses Apple's supported voice-processing path instead.
- Qwen3's upstream repository remains a separate PyTorch research/runtime project. The bundled mobile model is LFM2.5 230M Instruct Q4_K_M, not Qwen3.
- PocketPal AI is a React Native application built around `llama.rn`, not a Swift package that can be copied into a native SwiftUI target. Its model-download and GGUF lifecycle are useful architectural references, but this build does not claim to run PocketPal or a bundled GGUF model.
- `remotebiosensing/rppg` is a PyTorch research and benchmarking repository. It does not ship a validated iOS blood-pressure estimator or a Core ML model with the required calibration contract. Venture therefore imports cuff measurements from Apple Health and does not infer blood pressure from the phone camera.
- `Edoardo-BS/hubert-ecg-base` is a self-supervised base representation checkpoint. Its model card demonstrates loading an `AutoModel`; it does not publish a ready-to-use label head for the condition list requested for this app. Venture uses it as a representation reference for an app-native reconstructed ECG follow-up screen, not as an executed HuBERT disease-head checkpoint.
- `billzyx/WavBERT` publishes an Alzheimer speech-research training and evaluation pipeline for ADReSSo. The repository does not include a released Core ML, ONNX, GGUF, or task checkpoint that the iOS target can execute. Its Python, fairseq, PyTorch, dataset, and CUDA pipeline is therefore documented but not represented as running on device.
- The original `bdsp-core/ECGFounder` URL is no longer an available repository. The current official `PKUDigitalHealth/ECGFounder` project publishes a pretrained ECG representation and Python research code. It still requires a defined downstream dataset, task head, preprocessing, and calibration before it can produce condition labels. Venture therefore imports the real Apple Watch lead-I waveform, displays Apple's classification, and runs a bounded Swift reconstruction/follow-up screen without claiming ECGFounder percentages.
- `peasypi/Stress-Detection-From-Wearables` contains WESAD training notebooks for CNN and LDA experiments. It does not publish a deployable model artifact or an Apple Health feature contract. Venture uses measured sleep, HRV, resting heart rate, activity, and pupil change against the user's own reference instead of labeling stress, anxiety, or depression from that repository.
- `sonalsk/RememberME` is a Flutter application organized around thinking, concentration, memory, and decision-making games. It has no released clinical model artifact. Venture uses those task categories only as design references for directly scored memory, attention-switching, interference-control, and delayed-recall tasks.
- `COBsquare/Dementia-Examiner-for-Individuals` is a Java desktop application based on MMSE-style prompts and clock drawing. It publishes no validated iOS model or reusable scoring checkpoint. Venture does not copy its disease conclusion; formal MMSE administration and interpretation remain clinician-led.
- `realmichaelye/Stress-Prediction-Using-HRV` trains classifiers on 34 SWELL HRV features in notebooks and publishes no deployable checkpoint. A single Apple Health SDNN value does not satisfy that input contract, so the app compares measured HRV and sleep with personal history instead of claiming that model ran.
- `Nikitha-ramasetti/BP_Estimation_PPG` contains PyTorch CNN/LSTM training code using preprocessed MIMIC-III PPG and arterial-pressure labels. It includes no released Core ML checkpoint or phone-camera calibration contract. Venture therefore displays cuff measurements imported from Apple Health rather than estimating blood pressure from camera pixels.
- `Rouast-Labs/vitallens-python` is a Python client; its high-fidelity HR, respiratory-rate, and HRV path calls the VitalLens API. The separate Swift SDK also requires the service contract and API credentials. It is not represented as local inference in this build.
- `jzhang38/TinyLlama` is an archived training repository. Its documented 4-bit model is about 637 MB. Venture uses the smaller bundled LFM2.5 GGUF for local general chat, Apple's on-device Foundation Model when available, and its measured-signal engine for health-grounded answers.
- `pupil-labs/pupil`, EyeLoop, PupEyes, and `david-wb/gaze-estimation` are desktop or Python research systems. They inform capture, target-following, preprocessing, and quality-control choices, but none supplies a calibrated Core ML artifact for Venture's iPhone protocol.
- PupilSense publishes a Detectron2-based pupil-to-iris segmentation workflow and research dataset structure. Its depression study used repeated naturalistic measurements and PHQ labels; copying the segmenter alone would not reproduce the depression model.
- ADEM_TEST is a CC BY 4.0 test dataset containing dedicated binocular 3D eye-movement sequences and heatmaps for pro-saccade, anti-saccade, visual-attention, and visual-search tasks. Venture borrows task coverage only. Front-camera relative pupil centers are not compatible inputs for a classifier trained on that hardware.

## Not represented as executable inference

SSL4PR, WavBERT, Depression-Engine, HuBERT-ECG, and similar research checkpoints are not exposed as if their external weights executed in this build. Their published checkpoints are not sufficient by themselves to establish clinical validity across phone microphones, languages, devices, environments, or Apple Watch ECG data. Venture exposes measured voice changes, direct cognitive-task scores, optional PHQ-2 follow-up, and Apple's own Watch ECG classification. It does not diagnose or rule out a neurological, psychiatric, respiratory, or cardiac disorder. A numerical output from a converted research checkpoint is evidence of execution, not evidence of clinical validity for iPhone recordings.

The in-app `ScreeningModelCatalog` is the canonical inventory of every supplied repository reviewed for this build. A source is marked running only when its required artifact and preprocessing path execute in the app. Protocol-only projects are marked as informing test design, and missing or incompatible artifacts remain visibly unavailable.

## Source Links

- https://huggingface.co/FluidInference/silero-vad-coreml
- https://github.com/Mohit6304/Parkinsons-Disease-Detection
- https://huggingface.co/aufklarer/DeepFilterNet3-CoreML
- https://github.com/google-ai-edge/mediapipe
- https://github.com/pupil-labs/pupil
- https://github.com/simonarvin/eyeloop
- https://github.com/david-wb/gaze-estimation
- https://github.com/RichardoMrMu/awesome-gaze-estimation-new
- https://pupeyes.readthedocs.io
- https://github.com/stevenshci/PupilSense
- https://zenodo.org/records/18796183
- https://pubmed.ncbi.nlm.nih.gov/14583691/
- https://github.com/QwenLM/Qwen3
- https://huggingface.co/LiquidAI/LFM2.5-230M-GGUF
- https://github.com/a-ghorbani/pocketpal-ai
- https://github.com/remotebiosensing/rppg
- https://github.com/K-STMLab/SSL4PR
- https://github.com/billzyx/WavBERT
- https://github.com/Edoar-do/HuBERT-ECG
- https://huggingface.co/Edoardo-BS/hubert-ecg-base
- https://github.com/PKUDigitalHealth/ECGFounder
- https://huggingface.co/PKUDigitalHealth/ECGFounder
- https://github.com/peasypi/Stress-Detection-From-Wearables
- https://github.com/sonalsk/RememberME
- https://github.com/COBsquare/Dementia-Examiner-for-Individuals
- https://github.com/realmichaelye/Stress-Prediction-Using-HRV
- https://github.com/Nikitha-ramasetti/BP_Estimation_PPG
- https://github.com/Rouast-Labs/vitallens-python
- https://github.com/Rouast-Labs/vitallens-ios
- https://github.com/jzhang38/TinyLlama
- https://github.com/StanfordBioinformatics/wearable-infection
- https://github.com/google/gemma.cpp
- https://developer.apple.com/documentation/foundationmodels

## Current voice research audit

See [voice model audit](voice-model-audit.md) for the pinned SSL4PR conversion attempt, exact task/language/preprocessing contract, license references, and its distinction from WavBERT, OPERA, and HeAR. No dementia subtype is inferred from descriptive voice metrics.
