# Venture experience rebuild

The active app entry is `VentureExperienceView`. Legacy screens remain in source for migration but are no longer the main navigation.

## Flow

A single tap on the entrance orb expands it to fill the screen, then reveals account authentication or a session-only guest option. The account screen's globe opens the 27 manually authored language tables. This is followed by explicit microphone/camera permissions → three five-second sustained vowels → eight-second camera pupil-response measurement → four pages (home, insights, assistant, care).

The shared palette uses warm cream, beige, lavender, and purple with dark plum text. Entrance and control animations respect Reduce Motion. The pupil measurement keeps its dark baseline and controlled light pulse.

Language preference persists; all redesigned navigation, control and test labels update immediately. Arabic/Urdu use right-to-left layout. Account data uses encrypted, account-scoped files. Guest sessions do not load or write account history. Existing legacy history is left untouched, not silently assigned to a new user.

## Models and evidence

- Kokoro: actual Jud/KokoroCoreML Swift package, pinned source plus bundled frontend/backend Core ML models and voice embeddings. Synthesis is off the main thread. Simulator uses CPU-only. This upstream text pipeline is English; the scripted care sample explicitly states that limitation. Separate calling experiments use installed iOS voices for in-app replies and optionally Twilio for opted-in real clinic calls.
- Gemma 4 E2B Q4: actual GGUF artifact through the existing llama.cpp runtime. Only successful runtime preparation marks the chat ready. Prompts include the selected language; no generated result is presented when loading fails. General-purpose model output is not a clinical diagnosis.
- MediaPipe: Google Face Landmarker provides face and iris landmarks. Iris diameter is NOT pupil diameter. The camera service still requires actual dark-pupil segmentation, baseline and bright-phase samples; insufficient samples produce unavailable data.
- Voice: three samples must each contain at least 4.5 seconds of captured audio and measurable voice activity. No microphone-independent/fabricated recording. Only derived voice/noise measurements are persisted, never audio. The example button plays a real licensed VOICED human vowel recording with a padded five-second duration; attribution is bundled and linked in settings.

## Dementia research boundary

Three sustained vowels have not been validated here for Alzheimer's disease, frontotemporal dementia, Lewy-body dementia or vascular dementia subtype probabilities in 27 languages. No eligible clinical classifier has been bundled; this is intentional, not a claim of model accuracy. No individual disease percentages are exposed. Capping a percentage at 84 does not calibrate it.

Primary sources reviewed:

- https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0304272 — Spanish connected speech AD/bvFTD study; linguistic features and small validation sample, not sustained vowels.
- https://pmc.ncbi.nlm.nih.gov/articles/PMC13216759/ — PREPARE foundation-model study, spontaneous speech and dataset-specific classifier evaluation.
- https://alz-journals.onlinelibrary.wiley.com/doi/10.1002/alz.13748 — pathology-grounded AD/FTLD speech research; a research AUC is not an individual's disease probability.
- https://github.com/Jud/kokoro-coreml — requested speech runtime, English G2P and iOS 18+ requirements.
- https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker/ios — official landmark runtime.
- https://ai.google.dev/gemma/docs/core — actual Gemma 4 family and memory requirements.

Before adding subtype output: acquire a licensed patient dataset and deployable classifier, establish task/language/device compatibility, evaluate participant-independent and external cohorts, calibrate probabilities, and obtain appropriate clinical/regulatory review. No model was trained on invented patient data.
