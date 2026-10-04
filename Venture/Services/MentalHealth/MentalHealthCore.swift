import Foundation

struct ScreeningModelReference: Identifiable, Sendable, Equatable {
    enum State: String, Sendable {
        case active = "running on device"
        case available = "available on device"
        case informsTest = "informs test design"
        case unavailable = "not executable in this build"
    }

    let id: String
    let domain: String
    let name: String
    let state: State
    let detail: String
    let url: URL
}

enum ScreeningModelCatalog {
    private static let catalog: [ScreeningModelReference] = [
        .init(id: "bacld", domain: "eyes", name: "Brightness-Aware CL Detector", state: .informsTest, detail: "The pupil scan uses separate baseline and bright-light samples. The repository's personalized random-forest pipeline is Python-only and ships no trained mobile artifact.", url: URL(string: "https://github.com/arcadelab/Brightness-Aware-CL-Detector")!),
        .init(id: "venture-pupil-response-screen", domain: "eyes", name: "venture pupil response screen", state: .unavailable, detail: "Eye screening is disabled in the current voice-only experience; historical camera measurements are not included in results.", url: URL(string: "https://github.com/openPupil/Open-PupilEXT")!),
        .init(id: "venture-cognitive-dementia-screen", domain: "cognition", name: "venture cognitive dementia-pattern screen", state: .informsTest, detail: "Direct memory and attention task measurements remain available when completed. No validated dementia classifier is executed.", url: URL(string: "https://github.com/sonalsk/RememberME")!),
        .init(id: "venture-alzheimer-composite", domain: "cognition", name: "venture Alzheimer composite screen", state: .unavailable, detail: "The previous hand-weighted composite is not a validated Alzheimer classifier and is excluded from screening results.", url: URL(string: "https://github.com/NiliRahmani/Alzheimer-s-Dementia-Recognition-through-Spontaneous-Speech")!),
        .init(id: "venture-speech-language-screen", domain: "voice", name: "venture speech-language dementia screen", state: .informsTest, detail: "Word count and lexical diversity are measured from actual on-device transcription. These measurements do not identify dementia or execute WavBERT.", url: URL(string: "https://github.com/billzyx/WavBERT")!),
        .init(id: "venture-voice-mood-strain", domain: "voice", name: "venture voice mood-strain screen", state: .unavailable, detail: "No validated mood classifier is executed from acoustic timing or recording noise.", url: URL(string: "https://github.com/querodormir/HuBERT_Depression_Detection")!),
        .init(id: "venture-depression-composite", domain: "mood", name: "venture depression composite screen", state: .unavailable, detail: "No validated composite disease model is bundled; optional PHQ-2 responses retain their separate follow-up guidance.", url: URL(string: "https://github.com/AmirHoseein99/Depression-Engine")!),
        .init(id: "venture-stress-anxiety-strain", domain: "recovery", name: "venture stress and anxiety strain screen", state: .active, detail: "Runs in-app from measured HRV, sleep, voice activity, speech timing, and PHQ-2 when available. It reports follow-up strain context, not an anxiety diagnosis.", url: URL(string: "https://github.com/hariharitha21/Detection-of-Anxiety-and-Depression")!),
        .init(id: "venture-respiratory-acoustic", domain: "voice", name: "venture respiratory acoustic screen", state: .active, detail: "Runs in-app from measured breathing audio and reports wheeze-like acoustic likelihood, recording quality, and airflow irregularity. It is not a respiratory disease diagnosis.", url: URL(string: "https://github.com/sharnilpandya84/COPDDetectionUsingAcoustics")!),
        .init(id: "phq2", domain: "mood", name: "PHQ-2 depression follow-up screen", state: .active, detail: "Runs in-app from the two PHQ-2 responses and reports follow-up likelihood with safety guidance. It is a validated screen, not a diagnosis.", url: URL(string: "https://www.hiv.uw.edu/page/mental-health-screening/phq-2")!),
        .init(id: "apple-watch-ecg", domain: "recovery", name: "Apple Watch ECG classification screen", state: .active, detail: "Runs from HealthKit ECG classification, symptoms metadata, and imported Lead I sample count. It surfaces Apple rhythm-screen results and quality, not ECG foundation-model diagnoses.", url: URL(string: "https://developer.apple.com/documentation/healthkit/hkelectrocardiogram")!),
        .init(id: "mediapipe", domain: "eyes", name: "MediaPipe", state: .unavailable, detail: "MediaPipe offers iOS face landmarks, but it is not linked into this Swift package build. Apple Vision is the active on-device landmark backend, so venture does not claim MediaPipe execution.", url: URL(string: "https://github.com/google-ai-edge/mediapipe")!),
        .init(id: "gazeml", domain: "eyes", name: "GazeML", state: .unavailable, detail: "The project targets desktop TensorFlow and requires its trained gaze-estimation assets. It does not provide a supported Core ML package for this iOS target.", url: URL(string: "https://github.com/swook/GazeML")!),
        .init(id: "pupil-labs", domain: "eyes", name: "Pupil Labs", state: .informsTest, detail: "Pupil Labs is an eye-tracking hardware and software ecosystem. Its algorithms assume dedicated eye-camera geometry that the iPhone front camera does not provide.", url: URL(string: "https://github.com/pupil-labs/pupil")!),
        .init(id: "pure-open", domain: "eyes", name: "PuRe-open", state: .unavailable, detail: "PuRe is designed for infrared eye-camera imagery and ships C++ research code rather than a calibrated iPhone front-camera model.", url: URL(string: "https://github.com/pupil-labs/PuRe-open")!),
        .init(id: "pupilsense", domain: "eyes", name: "PupilSense", state: .unavailable, detail: "PupilSense requires its research capture and preprocessing pipeline and does not publish a drop-in Core ML artifact for venture's camera frames.", url: URL(string: "https://github.com/stevenshci/PupilSense")!),
        .init(id: "open-pupilext", domain: "eyes", name: "Open-PupilEXT", state: .unavailable, detail: "The project is a research pupil-measurement stack, not a calibrated front-camera iOS model. venture keeps using measured Apple Vision eye landmarks until a verified mobile artifact is bundled.", url: URL(string: "https://github.com/openPupil/Open-PupilEXT")!),
        .init(id: "pupil-dlc", domain: "eyes", name: "Pupil-DLC", state: .unavailable, detail: "The DeepLabCut-based workflow requires its Python analysis environment and trained pose-estimation assets. It cannot run inside this Swift target without conversion and validation.", url: URL(string: "https://github.com/Valyriverse/Pupil-DLC")!),
        .init(id: "eyeloop", domain: "eyes", name: "EyeLoop", state: .informsTest, detail: "EyeLoop's modular target-following experiments inform venture's gaze task, but the archived Python tracker is not embedded in this native iOS build.", url: URL(string: "https://github.com/simonarvin/eyeloop")!),
        .init(id: "david-gaze", domain: "eyes", name: "Deep gaze estimation", state: .unavailable, detail: "The PyTorch model was trained on synthetic UnityEyes imagery and reports desktop benchmark error. It does not ship a calibrated Core ML artifact for this front-camera protocol.", url: URL(string: "https://github.com/david-wb/gaze-estimation")!),
        .init(id: "pupeyes", domain: "eyes", name: "PupEyes", state: .informsTest, detail: "PupEyes informs preprocessing and quality-control practices for exported pupil data. It is a Python analysis package, not an on-device capture or disease model.", url: URL(string: "https://pupeyes.readthedocs.io")!),
        .init(id: "adem-test", domain: "cognition", name: "ADEM_TEST", state: .informsTest, detail: "The dataset's pro-saccade, anti-saccade, attention, and visual-search tasks inform gaze-task coverage. Its dedicated binocular 3D recordings cannot train a valid classifier for iPhone front-camera estimates without a new calibration study.", url: URL(string: "https://zenodo.org/records/18796183")!),
        .init(id: "whisper", domain: "voice", name: "Whisper", state: .unavailable, detail: "The upstream repository is a PyTorch transcription implementation. This build uses Apple's on-device Speech framework and does not bundle Whisper weights or a mobile runtime.", url: URL(string: "https://github.com/openai/whisper")!),
        .init(id: "fairseq", domain: "voice", name: "wav2vec 2.0 and HuBERT", state: .unavailable, detail: "The fairseq research stack and checkpoints are not an iOS runtime. No compatible task-specific Core ML classifier from this repository is installed.", url: URL(string: "https://github.com/facebookresearch/fairseq")!),
        .init(id: "sensevoice", domain: "voice", name: "SenseVoice", state: .unavailable, detail: "SenseVoice requires its model weights and supported inference runtime. Neither is bundled in this native Swift target.", url: URL(string: "https://github.com/FunAudioLLM/SenseVoice")!),
        .init(id: "silero-vad", domain: "voice", name: "Silero VAD Core ML", state: .available, detail: "The bundled MIT-licensed Core ML package measures voice-active frames on supported physical devices at 16 kHz. Simulator capture uses a labeled signal fallback. It does not classify disease.", url: URL(string: "https://huggingface.co/FluidInference/silero-vad-coreml")!),
        .init(id: "deepfilter", domain: "voice", name: "DeepFilterNet3 Core ML", state: .unavailable, detail: "The neural files require the project's STFT, ERB, normalization, and deep-filter reconstruction pipeline. venture uses Apple's voice-processing audio mode rather than running an incomplete enhancer.", url: URL(string: "https://huggingface.co/aufklarer/DeepFilterNet3-CoreML")!),
        .init(id: "wavbert", domain: "voice", name: "WavBERT", state: .unavailable, detail: "The recorded voice is processed by on-device speech recognition and Silero VAD. WavBERT requires ADReSSo data, downloaded wav2vec weights, and a Linux PyTorch/fairseq stack that is not included in the repository.", url: URL(string: "https://github.com/billzyx/WavBERT")!),
        .init(id: "dementia-voice-analyzer", domain: "voice", name: "DementiaVoiceAnalyzer", state: .unavailable, detail: "The repository does not provide a licensed, calibrated Core ML artifact that accepts venture's recording protocol.", url: URL(string: "https://github.com/Butovens/DementiaVoiceAnalyzer")!),
        .init(id: "ad-spontaneous", domain: "voice", name: "Alzheimer spontaneous speech", state: .unavailable, detail: "This research classifier depends on its original speech corpus and Python preprocessing. No deployable iOS checkpoint is published.", url: URL(string: "https://github.com/NiliRahmani/Alzheimer-s-Dementia-Recognition-through-Spontaneous-Speech")!),
        .init(id: "ad-detection-open", domain: "voice", name: "AD detection open", state: .unavailable, detail: "The training pipeline does not ship a mobile artifact with a reproducible phone-audio input contract.", url: URL(string: "https://github.com/hellolzc/AD_detection_open")!),
        .init(id: "alzheimers-dementia", domain: "voice", name: "Alzheimer dementia and MMSE", state: .unavailable, detail: "The repository's training code and dataset assumptions cannot be replaced by one iPhone recording; no compatible bundled checkpoint is available.", url: URL(string: "https://github.com/wazeerzulfikar/alzheimers-dementia")!),
        .init(id: "adress", domain: "voice", name: "ADReSS Challenge 2020", state: .informsTest, detail: "ADReSS defines a controlled spontaneous-speech research task. Access to its dataset and a trained, licensed mobile classifier is not included in venture.", url: URL(string: "https://github.com/KarolChlasta/ADReSS-Challenge2020")!),
        .init(id: "multiconad", domain: "voice", name: "MultiConAD", state: .unavailable, detail: "The multimodal research code requires its original trained assets and data modalities; it is not a drop-in iOS speech classifier.", url: URL(string: "https://github.com/ArezoShakeri/MultiConAD")!),
        .init(id: "parkinson-xgboost", domain: "voice", name: "Parkinson voice XGBoost", state: .unavailable, detail: "The bundled research head expects 22 MDVP and nonlinear features. The phone extractor does not reproduce that preprocessing, so predictions are disabled.", url: URL(string: "https://github.com/Mohit6304/Parkinsons-Disease-Detection")!),
        .init(id: "vocalpredict", domain: "voice", name: "VocalPredict", state: .unavailable, detail: "The repository reports a 94% result from notebook experiments, but publishes training notebooks rather than a licensed Core ML artifact and mobile audio preprocessing contract. It is not executed by this build.", url: URL(string: "https://github.com/aryan-kesarwani/VocalPredict-Early-Detection-of-Parkinson-s-Disease-through-Voice-Analysis")!),
        .init(id: "parkinson-abderrezzak", domain: "voice", name: "Parkinson Disease Voice Detector", state: .unavailable, detail: "This classical research project is not bundled because it does not supply a licensed Core ML artifact and distinct calibration contract.", url: URL(string: "https://github.com/AbderrezzakMrch/Parkinson-s-Disease-Voice-Detector")!),
        .init(id: "parkinson-lvwarren", domain: "voice", name: "Parkinsons voice features", state: .unavailable, detail: "The repository provides research code around voice-derived Parkinson screening, but this build has no matching Core ML classifier, scaler, and phone-audio feature contract.", url: URL(string: "https://github.com/lvwarren/Parkinsons")!),
        .init(id: "parkinson-imadtoubal", domain: "voice", name: "Parkinson speech classification", state: .unavailable, detail: "The project is a Python speech-data classifier and does not ship a licensed iOS model artifact that can accept venture's sustained-vowel capture.", url: URL(string: "https://github.com/imadtoubal/Parkinson-s-Disease-Classification-from-Speech-Data")!),
        .init(id: "parkinson-reps-learning", domain: "voice", name: "PD representation learning", state: .unavailable, detail: "The representation-learning code requires its research datasets and Python runtime. No converted, verified Core ML package is bundled.", url: URL(string: "https://github.com/idiap/pddetection-reps-learning")!),
        .init(id: "parkinson-mahesh", domain: "voice", name: "Parkinson disease classifier", state: .unavailable, detail: "The repository is retained as a reference, but it cannot be reported as running without a bundled mobile model and identical preprocessing pipeline.", url: URL(string: "https://github.com/mahesh989/Parkinson_Disease")!),
        .init(id: "ssl4pr", domain: "voice", name: "SSL4PR", state: .unavailable, detail: "The repository and HuBERT checkpoint require Python/PyTorch preprocessing and have no converted, verified Core ML task package in this app.", url: URL(string: "https://github.com/K-STMLab/SSL4PR")!),
        .init(id: "ssl4pr-hf", domain: "voice", name: "SSL4PR HuBERT base", state: .unavailable, detail: "The Hugging Face checkpoint is not a Core ML package and its training-domain calibration has not been reproduced for iPhone sustained-vowel audio.", url: URL(string: "https://huggingface.co/morenolq/SSL4PR-hubert-base")!),
        .init(id: "parkinson-shlok", domain: "voice", name: "Parkinson voice KNN", state: .unavailable, detail: "The repository trains from the UCI feature table rather than accepting raw iPhone audio, and it does not ship a mobile model artifact.", url: URL(string: "https://github.com/shlokKh/Parkinsons-Voice-Detection")!),
        .init(id: "parkinson-svm", domain: "voice", name: "Parkinson voice SVM", state: .unavailable, detail: "The repository does not include a verified Core ML model and scaler matching venture's acoustic extractor.", url: URL(string: "https://github.com/aryam643/Parkinsons-Detection-Using-SVM")!),
        .init(id: "parkinson-canbul", domain: "voice", name: "Parkinson ML benchmark", state: .unavailable, detail: "This is a training and benchmarking project without a deployable iOS inference artifact.", url: URL(string: "https://github.com/CanBul/Parkinson-Disease-Detection")!),
        .init(id: "parkinson-attention", domain: "voice", name: "Parkinson CNN attention", state: .unavailable, detail: "The deep model requires its original preprocessing and checkpoint; no compatible mobile package is bundled.", url: URL(string: "https://github.com/vitomarcorubino/Parkinsons-detection")!),
        .init(id: "parkinson-lstm", domain: "voice", name: "Parkinson voice ML and LSTM", state: .unavailable, detail: "Training code alone cannot execute in the app, and the repository does not provide a converted checkpoint and feature contract.", url: URL(string: "https://github.com/vivraj17/Detection-Of-Parkinson-s-Disesase-Using-Voice-Impairments-With-ML-and-LSTM")!),
        .init(id: "parkinson-biomarker", domain: "voice", name: "Parkinson vocal biomarkers", state: .unavailable, detail: "The research feature pipeline does not ship a Core ML classifier verified against venture's recordings.", url: URL(string: "https://github.com/JuanPuentes25/Parkinson-s-disease-detection-from-vocal-biomarker")!),
        .init(id: "mentalcare", domain: "voice", name: "MentalCare multimodal Parkinson", state: .informsTest, detail: "MentalCare combines speech, handwriting, and motion tasks. venture cannot label its voice-only recording as that full multimodal pipeline.", url: URL(string: "https://github.com/AravCodes/MentalCare")!),
        .init(id: "depression-engine", domain: "voice", name: "Depression Engine", state: .unavailable, detail: "The repository does not supply a validated iOS audio classifier and cannot be used to diagnose depression from one recording.", url: URL(string: "https://github.com/AmirHoseein99/Depression-Engine")!),
        .init(id: "speechbrain-emotion", domain: "voice", name: "SpeechBrain emotion recognition", state: .unavailable, detail: "The IEMOCAP emotion model is a Python SpeechBrain checkpoint, not a depression classifier or bundled Core ML model.", url: URL(string: "https://huggingface.co/speechbrain/emotion-recognition-wav2vec2-IEMOCAP")!),
        .init(id: "depression-icassp", domain: "voice", name: "ICASSP 2022 depression", state: .unavailable, detail: "The research code depends on its datasets, preprocessing, and Python runtime and publishes no calibrated iPhone artifact.", url: URL(string: "https://github.com/speechandlanguageprocessing/ICASSP2022-Depression")!),
        .init(id: "depression-fyp", domain: "voice", name: "Speech depression FYP", state: .unavailable, detail: "No deployable Core ML checkpoint with a compatible recording protocol is bundled.", url: URL(string: "https://github.com/chanjunweimy/FYP_Submission")!),
        .init(id: "depression-speech", domain: "voice", name: "Depression detection in speech", state: .unavailable, detail: "The repository's research pipeline cannot be represented as running without its trained model, preprocessing, and calibration assets.", url: URL(string: "https://github.com/skj-7/Depression-detection-in-speech")!),
        .init(id: "depression-sukesh", domain: "voice", name: "Speech depression biomarkers", state: .unavailable, detail: "The project does not provide a verified Core ML checkpoint and input-normalization contract for venture's phone recordings.", url: URL(string: "https://github.com/sukesh167/Depression-Detection-in-speech")!),
        .init(id: "depression-hein", domain: "voice", name: "Depression analysis model", state: .unavailable, detail: "The Python model is cataloged for future review, but no compatible iOS runtime artifact is bundled in this app target.", url: URL(string: "https://github.com/Hein-HtetSan/depression-analysis-model")!),
        .init(id: "depression-ser", domain: "voice", name: "SER depression detection", state: .unavailable, detail: "Speech-emotion research cannot be silently treated as depression diagnosis; this build has no licensed mobile classifier from the repository.", url: URL(string: "https://github.com/HLasse/SERDepressionDetection")!),
        .init(id: "anxiety-depression-hariharitha", domain: "voice", name: "Anxiety and depression speech screen", state: .unavailable, detail: "The repository is not executed because it does not ship a calibrated iOS artifact for venture's measured voice protocol.", url: URL(string: "https://github.com/hariharitha21/Detection-of-Anxiety-and-Depression")!),
        .init(id: "hubert-depression", domain: "voice", name: "HuBERT depression study", state: .unavailable, detail: "The pipeline extracts HuBERT embeddings with a GPU-oriented Python stack and trains logistic regression on controlled-access interview datasets. It does not publish a calibrated Core ML package for venture recordings.", url: URL(string: "https://github.com/querodormir/HuBERT_Depression_Detection")!),
        .init(id: "multimodal-depression", domain: "voice", name: "Multimodal depression detection", state: .unavailable, detail: "The model expects multiple research modalities unavailable in venture and has no drop-in iOS package.", url: URL(string: "https://github.com/56kd/MulitmodalDepressionDetection")!),
        .init(id: "alzheimers-42bismuth", domain: "voice", name: "Alzheimer Detection", state: .unavailable, detail: "The repository is not bundled as an executable mobile model. venture's active Alzheimer-related signal remains its measured speech-language and cognition screen.", url: URL(string: "https://github.com/42bismuth/Alzheimer-Detection")!),
        .init(id: "fhs-dementia-biomarkers", domain: "cognition", name: "FHS dementia AD biomarkers", state: .informsTest, detail: "This biomarkers project informs risk-factor thinking, but it does not provide an iPhone sensor model that can classify a user's scan.", url: URL(string: "https://github.com/hannahburkhardt/FHS_dementia_AD_biomarkers")!),
        .init(id: "opensmile", domain: "voice", name: "openSMILE", state: .informsTest, detail: "openSMILE is a proven audio feature-extraction toolkit, not a standalone disease classifier. venture can use its feature taxonomy when adding future converted models.", url: URL(string: "https://github.com/audeering/opensmile")!),
        .init(id: "resp-neural", domain: "voice", name: "Sound AI Neural Minds", state: .unavailable, detail: "This respiratory-sound project does not ship a licensed mobile model artifact. Lung-sound classification also requires a chest-quality recording, not ordinary speech captured near an iPhone microphone.", url: URL(string: "https://github.com/Mohamad-Atif1/Sound_ai_neural_minds")!),
        .init(id: "pulmonary-audio", domain: "voice", name: "Pulmonary Disease Audio", state: .unavailable, detail: "The repository does not include a deployable iOS checkpoint. Its training domain is clinical respiratory audio rather than a normal phone voice sample.", url: URL(string: "https://github.com/allenmanoj17/Detection-of-Pulmonary-Diseases-using-Respiratory-Sounds")!),
        .init(id: "copd-acoustics", domain: "voice", name: "COPD acoustic screen", state: .unavailable, detail: "The project studies COPD from respiratory acoustics, but no deployable Core ML artifact and phone/chest recording protocol is included in this app.", url: URL(string: "https://github.com/sharnilpandya84/COPDDetectionUsingAcoustics")!),
        .init(id: "respiratory-dnn", domain: "voice", name: "Respiratory disease DNN", state: .unavailable, detail: "The deep-learning respiratory classifier requires its training audio pipeline and does not provide a verified iOS package for venture.", url: URL(string: "https://github.com/victor369basu/Respiratory-diseases-recognition-through-respiratory-sound-with-the-help-of-deep-neural-network")!),
        .init(id: "respirenet", domain: "voice", name: "RespireNet", state: .unavailable, detail: "The web-application model is not bundled as a native iOS runtime and cannot be used until its input contract and weights are converted and audited.", url: URL(string: "https://github.com/K-GOKULAPPADURAI/RespireNet-Respiratory-Disease-Prediction-Web-Application-Using-Deep-Learning")!),
        .init(id: "copd-severity-lung-sounds", domain: "voice", name: "COPD severity lung sounds", state: .unavailable, detail: "The lung-sound severity model expects controlled respiratory recordings and ships no verified Core ML artifact for this iPhone app.", url: URL(string: "https://github.com/rsarka34/Automated-Severity-Detection-Of-Chronic-Obstructive-Pulmonary-Disease-Using-Lung-Sounds")!),
        .init(id: "cough-check", domain: "voice", name: "CoughCheck", state: .unavailable, detail: "The application repository does not provide a reusable trained Core ML classifier for venture. A cough recording cannot be silently substituted for its original pipeline.", url: URL(string: "https://github.com/OpenCOVID19CoughCheck/CoughCheckApp")!),
        .init(id: "voice-pathology", domain: "voice", name: "Voice Pathology Detection", state: .unavailable, detail: "No deployable mobile model artifact or compatible license file was present in the audited repository, so venture cannot execute it as a pathology test.", url: URL(string: "https://github.com/sahilbrid/voice-pathology-detection")!),
        .init(id: "voice-fhir", domain: "voice", name: "Voice Biomarker FHIR", state: .informsTest, detail: "This is an interoperability schema rather than a disease classifier. venture keeps its extracted voice fields structured but does not claim the schema performs inference.", url: URL(string: "https://github.com/kind-lab/voice-biomarker-fhir")!),
        .init(id: "covid-sounds-ios", domain: "voice", name: "COVID-19 Sounds iOS", state: .informsTest, detail: "This iPhone project demonstrates respiratory-sound collection. It does not bundle a general-purpose disease classifier that can be reused as an venture test.", url: URL(string: "https://github.com/cam-mobsys/covid19-sounds-ios-app")!),
        .init(id: "rememberme", domain: "cognition", name: "RememberME", state: .informsTest, detail: "venture uses randomized memory, attention, and decision tasks. RememberME is a Flutter application with score-based activities, not a trained inference model.", url: URL(string: "https://github.com/sonalsk/RememberME")!),
        .init(id: "dementia-examiner", domain: "cognition", name: "Dementia Examiner", state: .informsTest, detail: "Its task categories inform cognitive coverage. The repository is a Java desktop MMSE and clock-drawing application, not an iOS model artifact.", url: URL(string: "https://github.com/COBsquare/Dementia-Examiner-for-Individuals")!),
        .init(id: "wearable-stress", domain: "recovery", name: "Stress Detection From Wearables", state: .unavailable, detail: "The notebooks expect WESAD chest and wrist sensor channels. Apple Health does not provide the complete synchronized feature set or a bundled trained checkpoint.", url: URL(string: "https://github.com/peasypi/Stress-Detection-From-Wearables")!),
        .init(id: "wearable-infection", domain: "recovery", name: "NightSignal wearable anomaly", state: .active, detail: "venture ports the repository's Apache-2.0 deterministic Apple Watch pipeline: inactive overnight heart rate is compared with the running personal median, and an alert requires two consecutive elevated nights. It is an anomaly signal, not an infection diagnosis.", url: URL(string: "https://github.com/StanfordBioinformatics/wearable-infection")!),
        .init(id: "open-seizure", domain: "recovery", name: "Open Seizure Detector", state: .unavailable, detail: "The ecosystem relies on dedicated wearable motion or physiology hardware and alert services. venture cannot infer seizures from ordinary HealthKit summaries.", url: URL(string: "https://github.com/orgs/OpenSeizureDetector/repositories")!),
        .init(id: "seizure-exploration", domain: "recovery", name: "Aura Seizure Exploration", state: .unavailable, detail: "The audited repository does not contain a deployable iOS model and requires wearable sensor streams that venture does not currently receive.", url: URL(string: "https://github.com/Aura-healthcare/seizure_detector_exploration")!),
        .init(id: "pd-watch", domain: "recovery", name: "PADS Watch Parkinson Screen", state: .unavailable, detail: "This pipeline is trained on raw PADS smartwatch motion data. HealthKit summaries do not expose the matching raw sensor protocol or a bundled mobile checkpoint.", url: URL(string: "https://github.com/Fatimat01/PD-Detection")!),
        .init(id: "pdkit", domain: "recovery", name: "PDkit", state: .informsTest, detail: "PDkit describes multimodal Parkinson monitoring tasks. It informs future motion testing but is not a model artifact that can be embedded directly.", url: URL(string: "https://ubicomp-mental-health.github.io/papers/2019/pdkit-saez-pons.pdf")!),
        .init(id: "mhealthx", domain: "recovery", name: "mhealthx", state: .informsTest, detail: "mhealthx is a research feature-extraction toolkit, not a disease classifier. Its task protocols can inform future sensor capture.", url: URL(string: "https://sage-bionetworks.github.io/mhealthx/")!),
        .init(id: "pulse-anomaly", domain: "recovery", name: "AI on the Pulse", state: .unavailable, detail: "The repository contains anomaly-detection research code but no compatible Core ML artifact or validated HealthKit input contract.", url: URL(string: "https://github.com/davegabe/ai-on-the-pulse")!),
        .init(id: "symdetector", domain: "voice", name: "SymDetector", state: .informsTest, detail: "The project demonstrates detection of cough, sneeze, sniffle, and throat-clearing events. It is not a downloadable disease-diagnosis model for venture.", url: URL(string: "https://z0ngqing.github.io/project/health/")!),
        .init(id: "h-watch", domain: "recovery", name: "H-Watch", state: .informsTest, detail: "H-Watch is an open hardware and firmware platform. It does not provide an Apple Watch disease classifier for direct use in this app.", url: URL(string: "https://github.com/ETH-PBL/H-Watch")!),
        .init(id: "stress-wesad", domain: "recovery", name: "Wearable Stress Detection", state: .unavailable, detail: "This WESAD-style system expects synchronized multimodal physiological channels and does not ship a Core ML checkpoint compatible with HealthKit summaries.", url: URL(string: "https://github.com/kjspring/stress-detection-wearable-devices")!),
        .init(id: "asleep", domain: "recovery", name: "asleep", state: .unavailable, detail: "The sleep classifier expects raw wrist accelerometry at its training cadence. HealthKit sleep summaries are not the same model input and no iOS artifact is bundled.", url: URL(string: "https://github.com/OxWearables/asleep")!),
        .init(id: "wearable-hrv", domain: "recovery", name: "Wearable HRV Validation", state: .informsTest, detail: "This repository validates wearable HR and HRV quality. venture uses source attribution and personal baselines, but the project is not a disease classifier.", url: URL(string: "https://github.com/Aminsinichi/wearable-hrv")!),
        .init(id: "eeg-neuro", domain: "cognition", name: "Lightweight EEG Neurology Models", state: .unavailable, detail: "These models require EEG electrodes and EEG waveforms. An iPhone and Apple Watch do not measure EEG, so the input cannot be produced by venture.", url: URL(string: "https://github.com/cepdnaclk/e20-4yp-Lightweight-Deep-Learning-Models-for-Detection-of-Neurological-Disorders-Using-EEG-Signals")!),
        .init(id: "hrv-stress", domain: "recovery", name: "Stress Prediction Using HRV", state: .unavailable, detail: "The repository trains from 34 SWELL HRV features and contains notebooks rather than deployable weights. A single HealthKit SDNN value cannot satisfy that input contract.", url: URL(string: "https://github.com/realmichaelye/Stress-Prediction-Using-HRV")!),
        .init(id: "vitallens", domain: "recovery", name: "VitalLens", state: .unavailable, detail: "The Python package estimates pulse signals from face video, but its inference service and model stack are not Core ML artifacts and are not bundled in venture.", url: URL(string: "https://github.com/Rouast-Labs/vitallens-python")!),
        .init(id: "ecg-founder", domain: "recovery", name: "ECGFounder", state: .informsTest, detail: "ECGFounder informs the representation-style feature layer. The app-native ECG screen runs from imported Apple Watch Lead I and does not claim the external checkpoint executed.", url: URL(string: "https://github.com/PKUDigitalHealth/ECGFounder")!),
        .init(id: "hubert-ecg", domain: "recovery", name: "HuBERT ECG", state: .informsTest, detail: "HuBERT ECG informs the broad ECG screening framing. venture runs a lightweight Swift feature screen from measured Lead I rather than reporting HuBERT disease-head output.", url: URL(string: "https://github.com/Edoar-do/HuBERT-ECG")!),
        .init(id: "ecg-diagnosis", domain: "recovery", name: "ECG diagnosis", state: .informsTest, detail: "The 12-lead diagnosis repository informs the multi-label follow-up categories. venture's deployable iOS layer uses reconstructed Lead-I-derived features and keeps results as early-warning screens.", url: URL(string: "https://github.com/onlyzdd/ecg-diagnosis")!),
        .init(id: "id-shd", domain: "recovery", name: "ID-SHD wearable ECG study", state: .informsTest, detail: "This prospective study evaluates structural-heart screening from Apple Watch and portable single-lead ECGs against echocardiography. Its clinical AI model is not publicly distributed for embedding in venture.", url: URL(string: "https://www.cards-lab.org/id-shd")!),
        .init(id: "clef-ecg", domain: "recovery", name: "CLEF ECG foundation model", state: .unavailable, detail: "The research repository provides a clinical ECG representation-learning pipeline, not a verified Core ML classifier calibrated for Apple Watch lead-I exports.", url: URL(string: "https://github.com/Nokia-Bell-Labs/ecg-foundation-model")!),
        .init(id: "ecg-lv-dysfunction", domain: "recovery", name: "ECG LV dysfunction", state: .unavailable, detail: "The model targets left-ventricular dysfunction from its clinical ECG input protocol. No compatible on-device artifact or Apple Watch lead-I calibration is bundled.", url: URL(string: "https://github.com/obi-ml-public/ECG-LV-Dysfunction")!),
        .init(id: "ecg-reconstruction", domain: "recovery", name: "Single-to-twelve-lead ECG reconstruction", state: .active, detail: "Runs in Swift from imported Apple Watch Lead I. It creates a bounded reconstructed 12-lead screening vector for follow-up features; generated leads are not presented as measured clinical leads.", url: URL(string: "https://github.com/knu-plml/ecg-recon")!),
        .init(id: "ecg-mi-risk", domain: "recovery", name: "ECG ischemia follow-up screen", state: .active, detail: "Runs in Swift from reconstructed ECG screening features and reports ischemia follow-up context, not a heart-attack diagnosis or emergency rule-out.", url: URL(string: "https://github.com/onlyzdd/ecg-diagnosis")!),
        .init(id: "bp-ppg", domain: "recovery", name: "BP Estimation PPG", state: .unavailable, detail: "The repository contains training code but no trained checkpoint. It expects calibrated PPG windows and ABP labels; venture therefore uses real cuff readings imported from Apple Health.", url: URL(string: "https://github.com/Nikitha-ramasetti/BP_Estimation_PPG")!),
        .init(id: "rppg", domain: "recovery", name: "Remote biosensing rPPG", state: .unavailable, detail: "The PyTorch research framework is not a calibrated blood-pressure model and does not ship a Core ML package for the iPhone camera.", url: URL(string: "https://github.com/remotebiosensing/rppg")!),
        .init(id: "bp-webcam", domain: "recovery", name: "Webcam blood pressure estimation", state: .unavailable, detail: "The repository does not provide a validated iOS artifact or per-device calibration needed for camera blood-pressure inference.", url: URL(string: "https://github.com/enesbasbug/Blood_Pressure_Estimation_with_Webcam_using_Deep_Learning")!),
        .init(id: "bp-akrlowicz", domain: "recovery", name: "PPG blood pressure estimation", state: .unavailable, detail: "Its PPG and arterial-pressure training inputs are not equivalent to uncalibrated iPhone video and no mobile checkpoint is bundled.", url: URL(string: "https://github.com/akrlowicz/ppg-blood-pressure-estimation")!),
        .init(id: "bp-fabian", domain: "recovery", name: "Non-invasive BP deep learning", state: .unavailable, detail: "The training pipeline lacks a verified iPhone capture contract and deployable Core ML artifact.", url: URL(string: "https://github.com/Fabian-Sc85/non-invasive-bp-estimation-using-deep-learning")!),
        .init(id: "sleep-tracking", domain: "recovery", name: "Apple Watch sleep tracking RNN", state: .unavailable, detail: "The model expects raw watch acceleration and heart-rate sequences not exposed by this HealthKit-only iPhone target.", url: URL(string: "https://github.com/hegdepashupati/sleep-tracking")!),
        .init(id: "sleep-classifiers", domain: "recovery", name: "Apple Watch sleep classifiers", state: .unavailable, detail: "The research classifiers need raw synchronized watch motion and heart-rate features and do not provide a bundled mobile artifact.", url: URL(string: "https://github.com/ojwalch/sleep_classifiers")!),
        .init(id: "gemma-pytorch", domain: "assistant", name: "Gemma PyTorch", state: .unavailable, detail: "The official repository is a Python/PyTorch implementation. It is not an iOS inference runtime and no compatible quantized model is bundled.", url: URL(string: "https://github.com/google/gemma_pytorch")!),
        .init(id: "gemma-4-e2b", domain: "assistant", name: "Gemma 4 E2B", state: .available, detail: "Gemma 4 E2B Q4 is available as an optional local GGUF download. When installed, venture selects it for llama.cpp companion inference.", url: URL(string: "https://huggingface.co/ggml-org/gemma-4-E2B-it-GGUF")!),
        .init(id: "local-companion-lfm2-5", domain: "assistant", name: "LFM2.5 230M Instruct", state: .available, detail: "The bundled Q4_K_M GGUF is available to the llama.cpp Apple runtime. venture marks it running only after a real decode succeeds.", url: URL(string: "https://huggingface.co/LiquidAI/LFM2.5-230M-GGUF")!),
        .init(id: "qwen3", domain: "assistant", name: "Qwen3", state: .unavailable, detail: "The upstream repository provides research and serving runtimes, not a bundled native Swift inference package and mobile-quantized weight file.", url: URL(string: "https://github.com/QwenLM/Qwen3")!),
        .init(id: "qwen25", domain: "assistant", name: "Qwen 2.5 0.5B Instruct", state: .unavailable, detail: "Qwen is cataloged as an alternative GGUF, but its weights are not the bundled local assistant artifact in this build.", url: URL(string: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF")!),
        .init(id: "pocketpal", domain: "assistant", name: "PocketPal AI", state: .informsTest, detail: "PocketPal demonstrates GGUF download and llama.rn lifecycle in React Native. It cannot be copied as a model into this native SwiftUI target.", url: URL(string: "https://github.com/a-ghorbani/pocketpal-ai")!),
        .init(id: "ollama", domain: "assistant", name: "Ollama", state: .unavailable, detail: "Ollama is a desktop and server runtime and does not run inside an iOS App Store sandbox.", url: URL(string: "https://ollama.com")!),
        .init(id: "tinyllama", domain: "assistant", name: "TinyLlama", state: .unavailable, detail: "The GitHub repository provides training code. It does not bundle a quantized chat model or an iOS llama.cpp runtime; the current assistant uses the bundled LFM2.5 model and grounded app context.", url: URL(string: "https://github.com/jzhang38/TinyLlama")!)
    ]

    static var all: [ScreeningModelReference] {
        catalog.map { reference in
            guard BundledLlamaEngine.isReady else { return reference }
            if reference.id == "gemma-4-e2b", LocalCompanionModel.active == .gemma4E2B {
                return ScreeningModelReference(
                    id: reference.id,
                    domain: reference.domain,
                    name: reference.name,
                    state: .active,
                    detail: "Gemma 4 E2B Q4 has loaded and completed a local decode through llama.cpp. venture grounds prompts in measured app data and rejects unsafe or malformed output.",
                    url: reference.url
                )
            }
            if reference.id == "local-companion-lfm2-5", LocalCompanionModel.active == .lfm25 {
                return ScreeningModelReference(
                    id: reference.id,
                    domain: reference.domain,
                    name: reference.name,
                    state: .active,
                    detail: "The LFM2.5 GGUF has loaded and completed a local decode through llama.cpp. venture grounds prompts in measured app data and rejects unsafe or malformed output.",
                    url: reference.url
                )
            }
            return reference
        }
    }

    static func references(for domain: String) -> [ScreeningModelReference] {
        all.filter { $0.domain == domain }
    }
}

struct NightSignalDailyInput: Sendable, Equatable {
    let date: Date
    let overnightRestingHeartRateBPM: Double
}

struct NightSignalAssessment: Sendable, Equatable {
    enum Level: Int, Codable, Sendable {
        case nearBaseline = 0
        case elevated = 1
        case high = 2

        var title: String {
            switch self {
            case .nearBaseline: "Near personal baseline"
            case .elevated: "Elevated wearable anomaly"
            case .high: "High wearable anomaly"
            }
        }
    }

    let date: Date
    let level: Level
    let overnightRestingHeartRateBPM: Double
    let runningMedianBPM: Double
    let measuredNights: Int
}

/// Swift port of Stanford NightSignal's median-of-nightly-averages and
/// two-consecutive-night alert rules. This reports an anomaly, not a disease.
enum NightSignalCalculator {
    static func evaluate(
        _ inputs: [NightSignalDailyInput],
        calendar: Calendar = .current,
        minimumBaselineNights: Int = 7
    ) -> NightSignalAssessment? {
        let sorted = inputs
            .filter { $0.overnightRestingHeartRateBPM.isFinite && $0.overnightRestingHeartRateBPM > 0 }
            .sorted { $0.date < $1.date }
        guard sorted.count >= minimumBaselineNights, let latest = sorted.last else { return nil }

        var redCandidates = Set<Date>()
        var yellowCandidates = Set<Date>()
        var latestMedian = 0.0

        for index in sorted.indices {
            let history = sorted[...index].map(\.overnightRestingHeartRateBPM).sorted()
            let median = median(history)
            let day = calendar.startOfDay(for: sorted[index].date)
            if sorted[index].overnightRestingHeartRateBPM >= median + 4 {
                redCandidates.insert(day)
            }
            if sorted[index].overnightRestingHeartRateBPM >= median + 3 {
                yellowCandidates.insert(day)
            }
            if index == sorted.indices.last { latestMedian = median }
        }

        let latestDay = calendar.startOfDay(for: latest.date)
        let previousDay = calendar.date(byAdding: .day, value: -1, to: latestDay)
        let consecutiveRed = previousDay.map { redCandidates.contains($0) } == true && redCandidates.contains(latestDay)
        let consecutiveYellow = previousDay.map { yellowCandidates.contains($0) } == true && yellowCandidates.contains(latestDay)
        let level: NightSignalAssessment.Level = consecutiveRed ? .high : (consecutiveYellow ? .elevated : .nearBaseline)

        return NightSignalAssessment(
            date: latest.date,
            level: level,
            overnightRestingHeartRateBPM: latest.overnightRestingHeartRateBPM,
            runningMedianBPM: latestMedian,
            measuredNights: sorted.count
        )
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middle - 1] + values[middle]) / 2
        }
        return values[middle]
    }
}

struct MentalHealthSummary: Sendable, Equatable {
    let signalLoadScore: Int?
    let assessments: [MentalSignalAssessment]
    let forecasts: [MentalSignalForecast]
    let measuredSignalCount: Int

    static let empty = MentalHealthSummary(signalLoadScore: nil, assessments: [], forecasts: [], measuredSignalCount: 0)

    var headline: String {
        guard let signalLoadScore else { return "Learning your personal reference" }
        switch signalLoadScore {
        case 0..<25: return "Signals are close to your reference"
        case 25..<50: return "Some signals changed today"
        default: return "Several signals need attention"
        }
    }

    var priorityAssessment: MentalSignalAssessment? {
        assessments
            .filter { $0.level != .unavailable }
            .sorted {
                if $0.level.priority != $1.level.priority {
                    return $0.level.priority > $1.level.priority
                }
                return $0.domain.priority > $1.domain.priority
            }
            .first
    }
}

struct MentalSignalForecast: Identifiable, Sendable, Equatable {
    enum Domain: String, Sendable {
        case parkinsonVoice = "Parkinson voice"
        case pupilResponse = "Pupil response"
        case dementiaPattern = "Dementia pattern"
        case depressionFollowUp = "Depression follow-up"
        case stressAnxiety = "Stress and anxiety"
        case respiratory = "Respiratory acoustics"
        case cardiac = "Heart rhythm"
        case recovery = "Recovery strain"
    }

    var id: String { domain.rawValue }
    let domain: Domain
    let title: String
    let band: Int
    let score: Int
    let timeframe: String
    let evidence: [String]
    let action: String
    let limitation: String

    var bandText: String { "band \(band)/5" }
}

struct MentalSignalAssessment: Identifiable, Sendable, Equatable {
    enum Domain: String, Sendable {
        case cognition = "Memory and attention"
        case voice = "Voice change"
        case autonomic = "Recovery"
        case stress = "Stress and anxiety"
        case mood = "Mood screen"
        case cardiac = "Heart and circulation"

        fileprivate var priority: Int {
            switch self {
            case .cardiac: 5
            case .mood, .stress: 4
            case .cognition: 3
            case .voice: 2
            case .autonomic: 1
            }
        }
    }

    enum Level: String, Sendable {
        case unavailable = "Not enough data"
        case recorded = "Recorded"
        case nearReference = "Near reference"
        case changed = "Changed"
        case clinicianReview = "Clinician review"

        fileprivate var priority: Int {
            switch self {
            case .unavailable: 0
            case .recorded, .nearReference: 1
            case .changed: 2
            case .clinicianReview: 3
            }
        }
    }

    var id: String { domain.rawValue }
    let domain: Domain
    let level: Level
    let evidence: String
    let action: String
}

struct MentalHealthCore: Sendable {
    func evaluate(snapshots: [CognitiveSnapshot], health: HealthMetrics) -> MentalHealthSummary {
        let snapshots = snapshots.map(\.screeningContext)
        let latest = snapshots.max(by: { $0.capturedAt < $1.capturedAt })
        let prior = latest.map { latest in
            snapshots.filter { $0.capturedAt < latest.capturedAt }.suffix(14)
        } ?? []
        let priorSnapshots = Array(prior)
        var severities: [Double] = []
        var measuredCount = 0

        let cognition = latest.map {
            cognitionAssessment(latest: $0, prior: priorSnapshots, severities: &severities, measuredCount: &measuredCount)
        } ?? unavailableCognition
        let voice = latest.map {
            voiceAssessment(latest: $0, prior: priorSnapshots, severities: &severities, measuredCount: &measuredCount)
        } ?? unavailableVoice
        let autonomic = autonomicAssessment(
            latest: latest,
            health: health,
            prior: priorSnapshots,
            severities: &severities,
            measuredCount: &measuredCount
        )
        let mood = latest.map {
            moodAssessment(latest: $0, health: health, prior: priorSnapshots, measuredCount: &measuredCount)
        } ?? unavailableMood
        let stress = stressAnxietyAssessment(
            latest: latest,
            health: health,
            prior: priorSnapshots,
            measuredCount: &measuredCount
        )
        let cardiac = cardiacAssessment(health, measuredCount: &measuredCount)

        let score: Int?
        if latest != nil, prior.count >= 3, !severities.isEmpty {
            score = Int((min(1, severities.reduce(0, +) / Double(severities.count)) * 100).rounded())
        } else {
            score = nil
        }
        return MentalHealthSummary(
            signalLoadScore: score,
            assessments: [cognition, voice, autonomic, stress, mood, cardiac],
            forecasts: MentalSignalForecastCalculator.make(
                snapshots: snapshots,
                health: health,
                signalLoadScore: score
            ),
            measuredSignalCount: measuredCount
        )
    }

    private func cognitionAssessment(
        latest: CognitiveSnapshot,
        prior: [CognitiveSnapshot],
        severities: inout [Double],
        measuredCount: inout Int
    ) -> MentalSignalAssessment {
        var evidence: [String] = []
        if let memory = latest.memoryScore {
            measuredCount += 1
            evidence.append("memory task \(Int(memory * 100))%")
            appendDrop(memory, baseline: prior.compactMap(\.memoryScore).mean, scale: 0.5, to: &severities)
        }
        if let attention = latest.attentionScore {
            measuredCount += 1
            evidence.append("attention task \(Int(attention * 100))%")
            appendDrop(attention, baseline: prior.compactMap(\.attentionScore).mean, scale: 0.35, to: &severities)
        }
        if let executive = latest.executiveFunctionScore {
            measuredCount += 1
            evidence.append("interference control \(Int(executive * 100))%")
            appendDrop(executive, baseline: prior.compactMap(\.executiveFunctionScore).mean, scale: 0.35, to: &severities)
        }
        guard !evidence.isEmpty else {
            return .init(domain: .cognition, level: .unavailable, evidence: "No completed cognitive task.", action: "Complete the memory and attention task.")
        }
        let severity = domainSeverity(
            latest: [latest.memoryScore, latest.attentionScore, latest.executiveFunctionScore],
            baselines: [prior.compactMap(\.memoryScore).mean, prior.compactMap(\.attentionScore).mean, prior.compactMap(\.executiveFunctionScore).mean],
            scales: [0.5, 0.35, 0.35]
        )
        return .init(
            domain: .cognition,
            level: severity >= 0.5 ? .changed : .nearReference,
            evidence: evidence.joined(separator: " · "),
            action: severity >= 0.5
                ? "Repeat when rested. If memory, language, or daily-function changes persist, contact a clinician."
                : "Continue measuring under similar conditions."
        )
    }

    private func voiceAssessment(
        latest: CognitiveSnapshot,
        prior: [CognitiveSnapshot],
        severities: inout [Double],
        measuredCount: inout Int
    ) -> MentalSignalAssessment {
        var evidence: [String] = []
        var severity = 0.0
        if let acoustic = latest.voiceAcousticSummary {
            evidence.append("recording quality \(Int(acoustic.recordingQuality * 100))%")
            guard acoustic.isUsable else {
                return .init(domain: .voice, level: .unavailable, evidence: evidence.joined(separator: " · "), action: "Repeat in a quiet place with the phone steady. This recording cannot support interpretation.")
            }
            measuredCount += 1
            if let pitch = acoustic.pitchHz { evidence.append("average pitch \(Int(pitch.rounded())) Hz") }
            evidence.append("voiced sample \(acoustic.voicedSeconds.formatted(.number.precision(.fractionLength(1)))) sec")
        }
        if let speech = latest.speechStability {
            measuredCount += 1
            let baseline = prior.compactMap(\.speechStability).mean
            appendDrop(speech, baseline: baseline, scale: 0.3, to: &severities)
            severity = dropSeverity(speech, baseline: baseline, scale: 0.3)
            evidence.append("speech timing \(Int(speech * 100))%" + baseline.map { " · reference \(Int($0 * 100))%" }.orEmpty)
        }
        if let words = latest.spontaneousWordCount { evidence.append("open speech \(words) words") }
        if let diversity = latest.spontaneousLexicalDiversity { evidence.append("lexical diversity \(Int(diversity * 100))%") }
        guard !evidence.isEmpty else { return unavailableVoice }
        return .init(
            domain: .voice, level: severity >= 0.5 ? .changed : (prior.compactMap(\.speechStability).count >= 3 ? .nearReference : .recorded),
            evidence: evidence.joined(separator: " · "),
            action: severity >= 0.5
                ? "Repeat in a quiet room. Persistent speech, movement, or memory changes need clinician review."
                : "Keep a record under similar conditions. Voice measurements cannot identify or rule out a disease."
        )
    }

    private func autonomicAssessment(
        latest: CognitiveSnapshot?,
        health: HealthMetrics,
        prior: [CognitiveSnapshot],
        severities: inout [Double],
        measuredCount: inout Int
    ) -> MentalSignalAssessment {
        var evidence: [String] = []
        var domainSeverities: [Double] = []
        if let sleep = health.sleepHours ?? latest?.sleepHours {
            measuredCount += 1
            evidence.append("sleep \(sleep.formatted(.number.precision(.fractionLength(1)))) hr")
            appendDrop(sleep, baseline: prior.compactMap(\.sleepHours).mean, scale: 2, to: &domainSeverities)
        }
        if let hrv = health.heartRateVariabilityMilliseconds ?? latest?.heartRateVariability {
            measuredCount += 1
            evidence.append("HRV \(Int(hrv.rounded())) ms")
            let baseline = prior.compactMap(\.heartRateVariability).mean
            if let baseline { domainSeverities.append(min(1, max(0, (baseline - hrv) / max(baseline * 0.4, 1)))) }
        }
        guard !evidence.isEmpty else {
            return .init(domain: .autonomic, level: .unavailable, evidence: "No recovery measurements.", action: "Connect Apple Health if you want to add recovery measurements.")
        }
        severities.append(contentsOf: domainSeverities)
        let severity = domainSeverities.isEmpty ? 0 : domainSeverities.reduce(0, +) / Double(domainSeverities.count)
        return .init(
            domain: .autonomic,
            level: severity >= 0.5 ? .changed : .nearReference,
            evidence: evidence.joined(separator: " · "),
            action: severity >= 0.5 ? "Reduce optional interruptions and protect sleep tonight." : "Recovery signals are not showing a large personal deviation."
        )
    }

    private func cardiacAssessment(
        _ health: HealthMetrics,
        measuredCount: inout Int
    ) -> MentalSignalAssessment {
        var evidence: [String] = []
        var level: MentalSignalAssessment.Level = .nearReference
        var actions: [String] = []

        if
            let systolic = health.bloodPressureSystolicMMHg,
            let diastolic = health.bloodPressureDiastolicMMHg
        {
            measuredCount += 1
            let band = BloodPressureBand.classify(systolic: systolic, diastolic: diastolic)
            evidence.append("cuff blood pressure \(Int(systolic.rounded()))/\(Int(diastolic.rounded())) mmHg · \(band.rawValue)")
            switch band {
            case .severe:
                level = .clinicianReview
                actions.append(band.guidance)
            case .low, .stageOne, .stageTwo:
                level = .changed
                actions.append(band.guidance)
            case .normal, .elevated:
                actions.append(band.guidance)
            }
        }

        if let classification = health.electrocardiogramClassification {
            measuredCount += 1
            evidence.append("Apple classification: \(classification)")
            let guidance = AppleECGGuidance.make(classification: classification)
            if let profile = ECGScreeningProfile.make(from: health) {
                evidence.append(
                    profile.findings
                        .map { "\($0.name) \($0.likelihood)%" }
                        .joined(separator: " · ")
                )
                evidence.append(profile.qualityNote)
            }
            switch guidance.level {
            case .clinicianReview:
                level = .clinicianReview
            case .changed where level != .clinicianReview:
                level = .changed
            case .recorded, .nearReference, .changed:
                break
            }
            actions.append(guidance.action)
        }

        guard !evidence.isEmpty else {
            return .init(
                domain: .cardiac,
                level: .unavailable,
                evidence: "No cuff blood pressure or Watch ECG available.",
                action: "Add a validated cuff reading or record an ECG on Apple Watch, then import it."
            )
        }

        return .init(
            domain: .cardiac,
            level: level,
            evidence: evidence.joined(separator: " · "),
            action: actions.joined(separator: " ")
        )
    }

    private func moodAssessment(
        latest: CognitiveSnapshot,
        health: HealthMetrics,
        prior: [CognitiveSnapshot],
        measuredCount: inout Int
    ) -> MentalSignalAssessment {
        guard let score = latest.phq2Score, (0...6).contains(score) else { return unavailableMood }
        measuredCount += 1
        let guidance = PHQ2Screen.guidance(score: score)
        return .init(
            domain: .mood, level: guidance.needsFollowUp ? .clinicianReview : .nearReference,
            evidence: "PHQ-2 \(score)/6 · \(guidance.status)",
            action: [guidance.action, guidance.safety].compactMap { $0 }.joined(separator: " ")
        )
    }

    private func stressAnxietyAssessment(
        latest: CognitiveSnapshot?,
        health: HealthMetrics,
        prior: [CognitiveSnapshot],
        measuredCount: inout Int
    ) -> MentalSignalAssessment {
        guard let strain = StressAnxietyStrainIndexCalculator.score(latest: latest, health: health, prior: prior) else {
            return .init(
                domain: .stress,
                level: .unavailable,
                evidence: "Not enough recovery, voice, or mood data.",
                action: "Connect Apple Health or complete the voice and mood screens."
            )
        }
        measuredCount += 1
        return .init(
            domain: .stress,
            level: strain.score >= 70 ? .changed : .nearReference,
            evidence: "stress/anxiety strain \(strain.score)% · " + strain.evidence.joined(separator: " · "),
            action: strain.score >= 70
                ? "Reduce optional interruptions today, prioritize sleep, and repeat the screen. If anxiety feels persistent, intense, or unsafe, contact a qualified professional."
                : "No large combined strain signal was measured from the available data."
        )
    }

    private var unavailableCognition: MentalSignalAssessment {
        .init(
            domain: .cognition,
            level: .unavailable,
            evidence: "No completed cognitive task.",
            action: "Complete the memory and attention task."
        )
    }

    private var unavailableVoice: MentalSignalAssessment {
        .init(
            domain: .voice,
            level: .unavailable,
            evidence: "No completed voice sample.",
            action: "Complete the voice task in a quiet room."
        )
    }

    private var unavailableMood: MentalSignalAssessment {
        .init(
            domain: .mood,
            level: .unavailable,
            evidence: "No completed PHQ-2 screen.",
            action: "Complete the two mood questions when you are comfortable."
        )
    }

    private func appendDrop(_ value: Double, baseline: Double?, scale: Double, to values: inout [Double]) {
        guard let baseline else { return }
        values.append(dropSeverity(value, baseline: baseline, scale: scale))
    }

    private func appendAbsoluteChange(_ value: Double, baseline: Double?, scale: Double, to values: inout [Double]) {
        guard let baseline else { return }
        values.append(min(1, abs(value - baseline) / scale))
    }

    private func dropSeverity(_ value: Double, baseline: Double?, scale: Double) -> Double {
        guard let baseline else { return 0 }
        return min(1, max(0, (baseline - value) / scale))
    }

    private func domainSeverity(latest: [Double?], baselines: [Double?], scales: [Double]) -> Double {
        let values = zip(zip(latest, baselines), scales).compactMap { pair, scale -> Double? in
            guard let value = pair.0, let baseline = pair.1 else { return nil }
            return dropSeverity(value, baseline: baseline, scale: scale)
        }
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
}

enum MentalSignalForecastCalculator {
    static func make(
        snapshots: [CognitiveSnapshot],
        health: HealthMetrics,
        signalLoadScore: Int?
    ) -> [MentalSignalForecast] {
        let snapshots = snapshots.map(\.screeningContext)
        guard let latest = snapshots.max(by: { $0.capturedAt < $1.capturedAt }) else {
            return cardiacForecast(health: health).map { [$0] } ?? []
        }

        var forecasts: [MentalSignalForecast] = []
        if let phq2 = latest.phq2Score {
            let guidance = PHQ2Screen.guidance(score: phq2)
            forecasts.append(.init(domain: .depressionFollowUp, title: "mood follow-up", band: guidance.needsFollowUp ? 3 : 1, score: phq2 * 100 / 6, timeframe: "based on your responses", evidence: ["PHQ-2 \(phq2)/6"], action: guidance.action, limitation: "This self-report screen is not a depression diagnosis or a voice disease prediction."))
        }
        if let stressAnxiety = stressAnxietyForecast(latest: latest, snapshots: snapshots, health: health) {
            forecasts.append(stressAnxiety)
        }
        if let respiratory = respiratoryForecast(latest: latest) {
            forecasts.append(respiratory)
        }
        if let cardiac = cardiacForecast(health: health) {
            forecasts.append(cardiac)
        }
        if let recovery = recoveryForecast(snapshots: snapshots, health: health, signalLoadScore: signalLoadScore) {
            forecasts.append(recovery)
        }
        return forecasts.sorted {
            if $0.band != $1.band { return $0.band > $1.band }
            return $0.score > $1.score
        }
    }

    private static func dementiaPatternForecast(latest: CognitiveSnapshot) -> MentalSignalForecast? {
        let cognitive = DementiaPatternScreeningIndexCalculator.score(snapshot: latest)
        let speech = SpeechLanguageDementiaScreeningIndexCalculator.score(snapshot: latest)
        let alzheimer = AlzheimerCompositeScreeningIndexCalculator.score(snapshot: latest)
        let values = [alzheimer?.score, cognitive?.score, speech?.score].compactMap { $0 }
        guard !values.isEmpty else { return nil }
        let score = alzheimer?.score ?? Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
        return MentalSignalForecast(
            domain: .dementiaPattern,
            title: "memory-language follow-up",
            band: band(for: score),
            score: score,
            timeframe: timeframe(for: score),
            evidence: [
                alzheimer.map { "Alzheimer composite screen \($0.score)%" },
                cognitive.map { "cognitive dementia-pattern screen \($0.score)%" },
                speech.map { "speech-language screen \($0.score)%" }
            ].compactMap { $0 },
            action: score >= 60
                ? "repeat after rest with a longer open-speech sample. if memory, language, or daily-function changes persist, seek clinical assessment."
                : "build a repeated trend from cognitive tasks and open speech before drawing conclusions.",
            limitation: "This is a measured screening trend. It is not an Alzheimer disease or dementia diagnosis."
        )
    }

    private static func pupilResponseForecast(latest: CognitiveSnapshot) -> MentalSignalForecast? {
        guard let pupil = PupilAutonomicScreeningIndexCalculator.score(snapshot: latest) else { return nil }
        return MentalSignalForecast(
            domain: .pupilResponse,
            title: "pupil follow-up",
            band: band(for: pupil.score),
            score: pupil.score,
            timeframe: timeframe(for: pupil.score),
            evidence: pupil.evidence,
            action: pupil.score >= 60
                ? "repeat once with even light and a steady phone. new visible pupil inequality, eye pain, severe headache, weakness, confusion, or vision loss needs urgent care."
                : "compare repeated scans under similar lighting before interpreting a trend.",
            limitation: "This uses front-camera measurements. It is not a retinal, eye, Alzheimer, Parkinson, or neurological diagnosis."
        )
    }

    private static func depressionForecast(
        latest: CognitiveSnapshot,
        snapshots: [CognitiveSnapshot],
        health: HealthMetrics
    ) -> MentalSignalForecast? {
        let prior = snapshots
            .filter { $0.capturedAt < latest.capturedAt }
            .suffix(14)
        guard let screen = DepressionCompositeScreeningIndexCalculator.score(
            snapshot: latest,
            health: health,
            prior: Array(prior)
        ) else { return nil }
        return MentalSignalForecast(
            domain: .depressionFollowUp,
            title: "mood follow-up",
            band: band(for: screen.score),
            score: screen.score,
            timeframe: timeframe(for: screen.score),
            evidence: screen.evidence,
            action: screen.score >= 50
                ? "complete a fuller mood screen and reduce optional interruptions today. if symptoms persist or feel urgent, contact a qualified professional or crisis support."
                : "use this as context with sleep and recovery; repeat only when it feels useful.",
            limitation: "This combines PHQ-2 when available with measured voice, pupil, sleep, and HRV context. It is an early-warning screen, not a depression diagnosis."
        )
    }

    private static func stressAnxietyForecast(
        latest: CognitiveSnapshot,
        snapshots: [CognitiveSnapshot],
        health: HealthMetrics
    ) -> MentalSignalForecast? {
        let prior = snapshots
            .filter { $0.capturedAt < latest.capturedAt }
            .suffix(14)
        guard let strain = StressAnxietyStrainIndexCalculator.score(latest: latest, health: health, prior: Array(prior)) else {
            return nil
        }
        return MentalSignalForecast(
            domain: .stressAnxiety,
            title: "stress/anxiety follow-up",
            band: band(for: strain.score),
            score: strain.score,
            timeframe: timeframe(for: strain.score),
            evidence: strain.evidence,
            action: strain.score >= 70
                ? "lower optional notifications, protect recovery time, and repeat after sleep. persistent anxiety or unsafe feelings need qualified support."
                : "use this as a combined strain check; repeat only when the context is similar.",
            limitation: "This combines measured strain signals. It is not an anxiety disorder diagnosis and cannot replace clinical screening."
        )
    }

    private static func respiratoryForecast(latest: CognitiveSnapshot) -> MentalSignalForecast? {
        guard let wheeze = latest.respiratoryWheezeLikelihood else { return nil }
        let quality = latest.respiratoryRecordingQuality ?? 0.5
        let irregularity = latest.respiratoryAirflowIrregularity ?? 0
        let score = boundedPercent((wheeze * 0.78 + irregularity * 0.12 + (1 - min(quality, 1)) * 0.1) * 100)
        return MentalSignalForecast(
            domain: .respiratory,
            title: "breathing follow-up",
            band: band(for: score),
            score: score,
            timeframe: timeframe(for: score),
            evidence: [
                "wheeze-like acoustic signal \(boundedPercent(wheeze * 100))%",
                "sample quality \(boundedPercent(quality * 100))%",
                "airflow irregularity \(boundedPercent(irregularity * 100))%"
            ],
            action: score >= 65
                ? "repeat in a quiet room. persistent wheeze, shortness of breath, chest pain, blue lips, or breathing distress needs medical care."
                : "compare only with similar breathing samples; no elevated wheeze-like acoustic pattern was measured here.",
            limitation: "This is an acoustic screening signal from phone audio. It is not a COPD, asthma, infection, or pulmonary disease diagnosis."
        )
    }

    private static func cardiacForecast(health: HealthMetrics) -> MentalSignalForecast? {
        var scores: [Int] = []
        var evidence: [String] = []
        if let profile = ECGScreeningProfile.make(from: health) {
            let highest = profile.findings.max(by: { $0.likelihood < $1.likelihood })
            if let highest {
                scores.append(highest.name == "sinus rhythm screen" ? 8 : highest.likelihood)
                evidence.append("\(highest.name) \(highest.likelihood)%")
            }
            evidence.append(profile.qualityNote)
        }
        if
            let systolic = health.bloodPressureSystolicMMHg,
            let diastolic = health.bloodPressureDiastolicMMHg
        {
            let band = BloodPressureBand.classify(systolic: systolic, diastolic: diastolic)
            scores.append(bloodPressureScore(for: band))
            evidence.append("blood pressure \(Int(systolic.rounded()))/\(Int(diastolic.rounded())) · \(band.rawValue)")
        }
        guard !scores.isEmpty else { return nil }
        let score = scores.max() ?? 0
        return MentalSignalForecast(
            domain: .cardiac,
            title: "heart follow-up",
            band: band(for: score),
            score: score,
            timeframe: timeframe(for: score),
            evidence: evidence,
            action: score >= 75
                ? "follow Apple ECG or cuff guidance and seek urgent care for chest pain, fainting, severe shortness of breath, weakness, or other concerning symptoms."
                : "repeat ECG or cuff readings only as directed by device guidance or a clinician.",
            limitation: "This uses Apple Watch ECG classification, measured cuff values, and reconstructed Lead-I-derived ECG screening features. Reconstructed leads are early-warning context, not measured clinical 12-lead ECGs or diagnosis."
        )
    }

    private static func recoveryForecast(
        snapshots: [CognitiveSnapshot],
        health: HealthMetrics,
        signalLoadScore: Int?
    ) -> MentalSignalForecast? {
        var scores: [Int] = []
        var evidence: [String] = []
        if let strain = RecoveryStrainCalculator.score(snapshots: snapshots) {
            scores.append(strain.score)
            evidence.append(contentsOf: strain.evidence)
        }
        if
            let levelRaw = health.nightSignalLevel,
            let level = NightSignalAssessment.Level(rawValue: levelRaw),
            let overnight = health.nightSignalOvernightHeartRateBPM,
            let baseline = health.nightSignalBaselineBPM
        {
            scores.append(level == .high ? 82 : (level == .elevated ? 60 : 15))
            evidence.append("overnight inactive heart rate \(Int(overnight.rounded())) vs \(Int(baseline.rounded())) bpm median")
        }
        if let signalLoadScore {
            scores.append(signalLoadScore)
            evidence.append("overall signal load \(signalLoadScore)/100")
        }
        guard !scores.isEmpty else { return nil }
        let score = Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
        return MentalSignalForecast(
            domain: .recovery,
            title: "recovery follow-up",
            band: band(for: score),
            score: score,
            timeframe: timeframe(for: score),
            evidence: evidence,
            action: score >= 50
                ? "protect sleep, lower optional interruptions, and compare tomorrow's recovery signals."
                : "recovery signals are not pushing the forecast upward right now.",
            limitation: "This is a recovery trajectory estimate, not a stress, anxiety, infection, or sleep-disorder diagnosis."
        )
    }

    private static func band(for score: Int) -> Int {
        switch score {
        case 0..<20: 1
        case 20..<40: 2
        case 40..<60: 3
        case 60..<80: 4
        default: 5
        }
    }

    private static func timeframe(for score: Int) -> String {
        switch score {
        case 0..<40: "watch over the next few scans"
        case 40..<60: "repeat within a few days"
        case 60..<80: "repeat soon and compare"
        default: "repeat now and consider follow-up"
        }
    }

    private static func bloodPressureScore(for band: BloodPressureBand) -> Int {
        switch band {
        case .low: 54
        case .normal: 8
        case .elevated: 28
        case .stageOne: 58
        case .stageTwo: 76
        case .severe: 94
        }
    }

    private static func boundedPercent(_ value: Double) -> Int {
        Int(min(100, max(0, value)).rounded())
    }
}

struct RecoveryStrainScore: Sendable, Equatable {
    let score: Int
    let evidence: [String]
}

struct ScreeningIndexScore: Sendable, Equatable {
    let score: Int
    let evidence: [String]
}

enum CognitiveScreeningIndexCalculator {
    static func score(snapshot: CognitiveSnapshot) -> ScreeningIndexScore? {
        let measured: [(label: String, value: Double)] = [
            snapshot.memoryScore.map { ("memory", $0) },
            snapshot.attentionScore.map { ("attention", $0) },
            snapshot.executiveFunctionScore.map { ("interference", $0) }
        ].compactMap { $0 }
        guard !measured.isEmpty else { return nil }

        let averagePerformance = measured.map(\.value).reduce(0, +) / Double(measured.count)
        let concern = Int((max(0, min(1, 1 - averagePerformance)) * 100).rounded())
        let evidence = measured.map { "\($0.label) \(Int(($0.value * 100).rounded()))%" }
        return ScreeningIndexScore(score: concern, evidence: evidence)
    }
}

enum DementiaPatternScreeningIndexCalculator {
    static func score(snapshot: CognitiveSnapshot) -> ScreeningIndexScore? {
        guard let cognitive = CognitiveScreeningIndexCalculator.score(snapshot: snapshot) else { return nil }
        let lowSpeechFluency = snapshot.spontaneousLexicalDiversity.map { max(0, min(1, (0.42 - $0) / 0.22)) } ?? 0
        let shortSpeech = snapshot.spontaneousWordCount.map { max(0, min(1, Double(80 - $0) / 60)) } ?? 0
        let languageConcern = (lowSpeechFluency + shortSpeech) / (snapshot.spontaneousLexicalDiversity == nil && snapshot.spontaneousWordCount == nil ? 1 : 2)
        let combined = min(100, max(0, Int((Double(cognitive.score) * 0.75 + languageConcern * 100 * 0.25).rounded())))
        var evidence = cognitive.evidence
        if let words = snapshot.spontaneousWordCount { evidence.append("spoken words \(words)") }
        if let diversity = snapshot.spontaneousLexicalDiversity { evidence.append("lexical diversity \(Int((diversity * 100).rounded()))%") }
        return ScreeningIndexScore(score: combined, evidence: evidence)
    }
}

enum SpeechLanguageDementiaScreeningIndexCalculator {
    static func score(snapshot: CognitiveSnapshot) -> ScreeningIndexScore? {
        let measured: [(label: String, concern: Double, evidence: String)] = [
            snapshot.speechStability.map {
                ("speech timing", max(0, min(1, (0.72 - $0) / 0.32)), "speech timing \(Int(($0 * 100).rounded()))%")
            },
            snapshot.spontaneousWordCount.map {
                ("word count", max(0, min(1, Double(90 - $0) / 70)), "spoken words \($0)")
            },
            snapshot.spontaneousLexicalDiversity.map {
                ("lexical diversity", max(0, min(1, (0.46 - $0) / 0.26)), "lexical diversity \(Int(($0 * 100).rounded()))%")
            }
        ].compactMap { $0 }

        guard measured.count >= 2 else { return nil }
        let weighted = measured.reduce(0.0) { result, item in
            let weight = item.label == "speech timing" ? 0.35 : 0.325
            return result + item.concern * weight
        }
        let weightTotal = measured.reduce(0.0) { result, item in
            result + (item.label == "speech timing" ? 0.35 : 0.325)
        }
        let score = Int((min(1, max(0, weighted / max(weightTotal, 0.001))) * 100).rounded())
        return ScreeningIndexScore(score: score, evidence: measured.map(\.evidence))
    }
}

enum AlzheimerCompositeScreeningIndexCalculator {
    static func score(snapshot: CognitiveSnapshot) -> ScreeningIndexScore? {
        var measured: [(concern: Double, weight: Double, evidence: String)] = []

        if let cognitive = CognitiveScreeningIndexCalculator.score(snapshot: snapshot) {
            measured.append((Double(cognitive.score) / 100, 0.52, "cognitive screen \(cognitive.score)%"))
        }

        if let speech = SpeechLanguageDementiaScreeningIndexCalculator.score(snapshot: snapshot) {
            measured.append((Double(speech.score) / 100, 0.28, "speech-language screen \(speech.score)%"))
        }

        if let gaze = snapshot.gazeTrackingScore {
            measured.append((
                max(0, min(1, (0.58 - gaze) / 0.36)),
                0.10,
                "gaze tracking \(Int((gaze * 100).rounded()))%"
            ))
        }

        if let fixation = snapshot.fixationStability {
            measured.append((
                max(0, min(1, (0.58 - fixation) / 0.35)),
                0.10,
                "fixation stability \(Int((fixation * 100).rounded()))%"
            ))
        }

        guard measured.contains(where: { $0.evidence.contains("cognitive screen") }) || measured.count >= 2 else {
            return nil
        }
        let weight = measured.reduce(0) { $0 + $1.weight }
        guard weight > 0 else { return nil }
        let score = measured.reduce(0) { $0 + $1.concern * $1.weight } / weight
        return ScreeningIndexScore(
            score: Int((min(1, max(0, score)) * 100).rounded()),
            evidence: measured.map(\.evidence)
        )
    }
}

enum VoiceMoodStrainScreeningIndexCalculator {
    static func score(snapshot: CognitiveSnapshot) -> ScreeningIndexScore? {
        let measured: [(concern: Double, evidence: String)] = [
            snapshot.voiceActivityRatio.map {
                (max(0, min(1, (0.48 - $0) / 0.3)), "voice activity \(Int(($0 * 100).rounded()))%")
            },
            snapshot.speechStability.map {
                (max(0, min(1, (0.68 - $0) / 0.3)), "speech timing \(Int(($0 * 100).rounded()))%")
            },
            snapshot.spontaneousWordCount.map {
                (max(0, min(1, Double(75 - $0) / 60)), "spoken words \($0)")
            },
            snapshot.noiseLevel.map {
                (max(0, min(1, ($0 - 0.32) / 0.45)), "noise \(Int(($0 * 100).rounded()))%")
            }
        ].compactMap { $0 }

        guard measured.count >= 2 else { return nil }
        let average = measured.map(\.concern).reduce(0, +) / Double(measured.count)
        return ScreeningIndexScore(
            score: Int((min(1, max(0, average)) * 100).rounded()),
            evidence: measured.map(\.evidence)
        )
    }
}

enum StressAnxietyStrainIndexCalculator {
    static func score(
        latest: CognitiveSnapshot?,
        health: HealthMetrics,
        prior: [CognitiveSnapshot]
    ) -> ScreeningIndexScore? {
        var measured: [(concern: Double, evidence: String)] = []

        if let hrv = health.heartRateVariabilityMilliseconds ?? latest?.heartRateVariability,
           let reference = prior.compactMap(\.heartRateVariability).mean,
           reference > 0 {
            let concern = min(1, max(0, (reference - hrv) / max(reference * 0.35, 1)))
            measured.append((concern, "HRV \(Int(hrv.rounded())) ms vs \(Int(reference.rounded())) ms reference"))
        }

        if let sleep = health.sleepHours ?? latest?.sleepHours,
           let reference = prior.compactMap(\.sleepHours).mean,
           reference > 0 {
            let concern = min(1, max(0, (reference - sleep) / 2))
            measured.append((concern, "sleep \(sleep.formatted(.number.precision(.fractionLength(1)))) hr vs \(reference.formatted(.number.precision(.fractionLength(1)))) hr reference"))
        }

        if let voiceActivity = latest?.voiceActivityRatio {
            measured.append((max(0, min(1, (0.46 - voiceActivity) / 0.3)), "voice activity \(Int((voiceActivity * 100).rounded()))%"))
        }

        if let speech = latest?.speechStability {
            measured.append((max(0, min(1, (0.68 - speech) / 0.3)), "speech timing \(Int((speech * 100).rounded()))%"))
        }

        if let phq2 = latest?.phq2Score {
            measured.append((min(1, max(0, Double(phq2) / 6)), "PHQ-2 \(phq2)/6"))
        }

        guard measured.count >= 2 else { return nil }
        let score = Int((measured.map(\.concern).reduce(0, +) / Double(measured.count) * 100).rounded())
        return ScreeningIndexScore(score: min(100, max(0, score)), evidence: measured.map(\.evidence))
    }
}

enum PupilAutonomicScreeningIndexCalculator {
    static func score(snapshot: CognitiveSnapshot) -> ScreeningIndexScore? {
        let measured: [(concern: Double, evidence: String)] = [
            snapshot.pupilResponse.map {
                (max(0, min(1, (0.34 - $0) / 0.34)), "pupil light response \(Int(($0 * 100).rounded()))%")
            },
            snapshot.pupilSymmetry.map {
                (max(0, min(1, (0.86 - $0) / 0.28)), "pupil symmetry \(Int(($0 * 100).rounded()))%")
            },
            snapshot.pupilVariability.map {
                (max(0, min(1, $0 / 0.28)), "pupil estimate variability \(Int(($0 * 100).rounded()))%")
            },
            snapshot.fixationStability.map {
                (max(0, min(1, (0.58 - $0) / 0.35)), "fixation stability \(Int(($0 * 100).rounded()))%")
            },
            snapshot.gazeTrackingScore.map {
                (max(0, min(1, (0.55 - $0) / 0.35)), "gaze tracking \(Int(($0 * 100).rounded()))%")
            }
        ].compactMap { $0 }

        guard measured.count >= 2 else { return nil }
        let average = measured.map(\.concern).reduce(0, +) / Double(measured.count)
        return ScreeningIndexScore(
            score: Int((min(1, max(0, average)) * 100).rounded()),
            evidence: measured.map(\.evidence)
        )
    }
}

enum DepressionScreeningIndexCalculator {
    static func score(phq2Score: Int) -> ScreeningIndexScore {
        let bounded = min(6, max(0, phq2Score))
        let percent = Int((Double(bounded) / 6 * 100).rounded())
        return ScreeningIndexScore(score: percent, evidence: ["PHQ-2 \(bounded)/6"])
    }
}

enum DepressionCompositeScreeningIndexCalculator {
    static func score(
        snapshot: CognitiveSnapshot,
        health: HealthMetrics,
        prior: [CognitiveSnapshot]
    ) -> ScreeningIndexScore? {
        var measured: [(concern: Double, weight: Double, evidence: String)] = []

        if let phq2Score = snapshot.phq2Score {
            let phq = DepressionScreeningIndexCalculator.score(phq2Score: phq2Score)
            measured.append((Double(phq.score) / 100, 0.48, phq.evidence[0]))
        }

        if let voice = VoiceMoodStrainScreeningIndexCalculator.score(snapshot: snapshot) {
            measured.append((Double(voice.score) / 100, 0.20, "voice mood-strain screen \(voice.score)%"))
        }

        if let pupil = PupilAutonomicScreeningIndexCalculator.score(snapshot: snapshot) {
            measured.append((Double(pupil.score) / 100, 0.12, "pupil-autonomic screen \(pupil.score)%"))
        }

        if let sleep = health.sleepHours ?? snapshot.sleepHours {
            let reference = prior.compactMap(\.sleepHours).mean
            let concern = reference.map {
                max(0, min(1, ($0 - sleep) / 2))
            } ?? max(0, min(1, (7 - sleep) / 3))
            measured.append((
                concern,
                0.10,
                "sleep \(sleep.formatted(.number.precision(.fractionLength(1)))) hr" + reference.map { " vs \($0.formatted(.number.precision(.fractionLength(1)))) hr reference" }.orEmpty
            ))
        }

        if let hrv = health.heartRateVariabilityMilliseconds ?? snapshot.heartRateVariability {
            let reference = prior.compactMap(\.heartRateVariability).mean
            if let reference, reference > 0 {
                measured.append((
                    max(0, min(1, (reference - hrv) / max(reference * 0.35, 1))),
                    0.06,
                    "HRV \(Int(hrv.rounded())) ms vs \(Int(reference.rounded())) ms reference"
                ))
            }
        }

        if let steps = health.stepCount {
            measured.append((
                max(0, min(1, (2_000 - steps) / 2_000)),
                0.04,
                "steps \(Int(steps.rounded()))"
            ))
        }

        let hasPHQ = snapshot.phq2Score != nil
        guard hasPHQ || measured.count >= 2 else { return nil }
        let weight = measured.reduce(0) { $0 + $1.weight }
        guard weight > 0 else { return nil }
        let score = measured.reduce(0) { $0 + $1.concern * $1.weight } / weight
        return ScreeningIndexScore(
            score: Int((min(1, max(0, score)) * 100).rounded()),
            evidence: measured.map(\.evidence)
        )
    }
}

enum RecoveryStrainCalculator {
    static func score(snapshots: [CognitiveSnapshot]) -> RecoveryStrainScore? {
        guard let latest = snapshots.max(by: { $0.capturedAt < $1.capturedAt }) else { return nil }
        let prior = snapshots
            .filter { $0.capturedAt < latest.capturedAt }
            .suffix(14)

        var deviations: [Double] = []
        var evidence: [String] = []

        if let hrv = latest.heartRateVariability,
           let reference = prior.compactMap(\.heartRateVariability).mean,
           reference > 0 {
            let deviation = min(1, max(0, (reference - hrv) / max(reference * 0.4, 1)))
            deviations.append(deviation)
            evidence.append("HRV \(Int(hrv.rounded())) ms vs \(Int(reference.rounded())) ms reference")
        }

        if let sleep = latest.sleepHours,
           let reference = prior.compactMap(\.sleepHours).mean,
           reference > 0 {
            let deviation = min(1, max(0, (reference - sleep) / 2))
            deviations.append(deviation)
            evidence.append("sleep \(sleep.formatted(.number.precision(.fractionLength(1)))) hr vs \(reference.formatted(.number.precision(.fractionLength(1)))) hr reference")
        }

        guard !deviations.isEmpty else { return nil }
        let score = Int((deviations.reduce(0, +) / Double(deviations.count) * 100).rounded())
        return RecoveryStrainScore(score: min(100, max(0, score)), evidence: evidence)
    }
}

private extension Array where Element == Double {
    var mean: Double? { isEmpty ? nil : reduce(0, +) / Double(count) }
}

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}
