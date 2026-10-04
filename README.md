# Venture

Venture is a native SwiftUI iOS voice check and care-support app for people who
need an accessible starting point, including rural communities. It turns measured
recording evidence into:

`problem -> measured evidence -> next action`

Short definition: **every mind holds a world**.

## What Works

- Voice-only capture: repeated comfortable vowels and optional open speech.
- Local waveform analysis for pitch, voiced duration, frame-level pitch and
  loudness variation, clipping, and recording quality; limited recordings request
  another attempt before interpretation.
- On-device Apple Speech transcription and word/lexical measurements when
  supported. Silero VAD Core ML runs on physical devices; simulator capture uses
  an explicitly labeled signal fallback.
- Curved SwiftUI results with a bottom get-help action, everyday voice and memory
  support, visit preparation, telehealth guidance, and community-clinic search.
- Historical eye measurements remain readable for deletion, but eye-test results
  are excluded from screening, sharing, backend metrics, and assistant context.
- Randomized working-memory, attention-switching, interference-control, delayed
  recall, and PHQ-2 tasks scored from actual user responses.
- Apple Health imports for sleep, HRV, resting heart rate, oxygen saturation,
  activity, cuff blood pressure, and Apple Watch ECG waveform/classification.
- Adaptive app shielding through FamilyControls and ManagedSettings when the
  signed build has Apple-approved Family Controls access.
- Supabase email signup, OTP verification, password recovery, refresh-token
  rotation, and cross-device sign-in.
- AES-256-GCM encrypted local metrics, device-only Keychain keys, LZFSE payload
  compression, duplicate-write suppression, and deletion of temporary media.

## Local Assistant

The app bundles an LFM2.5 230M Instruct Q4_K_M GGUF and runs it locally through
an arm64 llama.cpp XCFramework. It streams generated tokens,
uses the model's embedded chat template, supports cancellation, carries a short
conversation window into follow-up questions, answers ordinary stable knowledge questions, and uses a
separate measured-signal engine for questions about the user's Venture data.

Settings also offers an optional 2.8 GB Gemma 4 E2B download. It is fetched
only after the user requests it and stored in Application Support; it is not
bundled in the app or this repository.

Fast deterministic paths handle simple arithmetic, crisis language, current-data
limitations, and unsafe requests for personal disease probabilities. Rejected or
malformed general-model output is retried through the model rather than being
misrouted to an empty scan response.

The model is memory-mapped, loaded after onboarding on physical devices, and
released on iOS memory warnings. It has no live web access and may be wrong about
facts outside its training data.

## Model Integrity

Only artifacts that are actually bundled and executable are represented as
available. The language model is marked running only after a real decode succeeds:

- LFM2.5 230M Instruct Q4_K_M through llama.cpp
- Silero VAD Core ML
- NightSignal's deterministic wearable anomaly pipeline

The legacy Parkinson XGBoost head is disabled because the phone extractor does
not reproduce its expected MDVP feature contract. Hand-weighted Alzheimer,
dementia, and voice-mood percentages are excluded from public results.

Other repositories listed in `docs/model-sources.md` are explicitly marked as
research references or unavailable when they do not provide compatible weights,
preprocessing, licensing, or an iOS runtime. Source code or reported accuracy is
not treated as a working mobile model.

## Calling Experiments

The care page exposes separate AI Clinic Receptionist, Nova Dear Care, and Rural
Health AI test buttons. Conversations are isolated. Opted-in personalized demos
use the user's actual extracted measurements and appointment goal. Optional
Twilio calls generate the opening before dialing, continue through signed speech
webhooks, and expose status/end controls. Claude and Nova need server-side model
credentials; Rural is clearly labeled as an independently authored English rules
adaptation without upstream TFLite inference. See
[`calling-service/README.md`](calling-service/README.md) for setup and provenance.

Venture provides screening context, not diagnosis. It does not claim to determine
whether a person has Alzheimer's disease, Parkinson's disease, depression,
anxiety, cancer, or a cardiac condition. Apple Watch ECG findings use Apple's
HealthKit classification only.

## Build

Requirements:

- Xcode 26.5 (verified toolchain)
- iOS 17 deployment target
- About 700 MB of free build space for the model and llama runtime

```sh
xcodebuild \
  -project Venture.xcodeproj \
  -scheme Venture \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Unsigned arm64 device verification:

```sh
xcodebuild \
  -project Venture.xcodeproj \
  -scheme Venture \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

For normal Personal Team development, use
`Venture/Resources/Venture.entitlements`; Screen Time shielding remains disabled so
the app can provision. After Apple approves Family Controls for the distribution
identifier, use `Venture/Resources/VentureFamilyControls.entitlements` and set
`VENTURE_FAMILY_CONTROLS_ENABLED=YES`.

Configure production authentication using
[`docs/supabase-setup.md`](docs/supabase-setup.md). Use `-resetOnboarding` in a
Debug scheme to replay onboarding.

## Verification

```sh
swiftc -parse $(rg --files Venture VentureTests -g '*.swift')
./tools/build_simulator_clean.sh
xcodebuild \
  -project Venture.xcodeproj \
  -scheme Venture \
  -destination 'platform=iOS Simulator,name=Venture Runtime Check' \
  test
```

See [`docs/architecture.md`](docs/architecture.md) and
[`docs/model-sources.md`](docs/model-sources.md) for the data flow, privacy
boundaries, model provenance, and unsupported research pipelines.
