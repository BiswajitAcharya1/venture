# Venture Architecture

Venture is an iOS 17+ SwiftUI application organized around encrypted personal signal processing.

## Layers

- `App` and `Root`: lifecycle, tabs, presentation, and launch motion.
- `Features`: SwiftUI screens and scan interactions.
- `Domain`: immutable cognitive snapshots and scan results.
- `Services/Sensors`: camera, microphone, speech, and Core ML voice-activity processing.
- `Services/MentalHealth`: transparent personal-reference signal scoring and action selection.
- `Services/Companion`: Apple Foundation Models on eligible iOS 26 devices with a grounded local fallback.
- `Services/Storage`: AES-256-GCM encrypted metrics with a Keychain-held device key.
- `Services/Security`: password strength, email verification, remote auth sessions, and the development-only local credential fallback.
- `Services/System`: Health-aware Screen Time shielding, reminders, jobs, brightness, and haptics.

## Evidence Boundaries

Venture measures pupil response, relative gaze-target tracking, voice timing, task performance, PHQ-2 self-report, sleep, HRV, activity, and Apple Watch ECG data. The mental health core compares repeated sensor and task measurements with the user's own history. PHQ-2 is interpreted with its published follow-up threshold, while pupil data remains separately labeled context. The app does not diagnose or rule out Alzheimer's disease, Parkinson's disease, depression, or cardiac conditions.

The Watch ECG surface reports Apple's HealthKit classification and imported lead-I samples. The HuBERT-ECG base checkpoint is not shipped or presented as a condition classifier because it requires preprocessing and task-specific downstream fine-tuning.

## Account And Email Verification

Production account mode uses Supabase Auth. Configure `VENTURE_SUPABASE_URL` and `VENTURE_SUPABASE_ANON_KEY` for sign-up, confirmation OTP, resend, password recovery, sign-in, and refresh-token rotation. The app sends credentials to Supabase over TLS, stores only returned session tokens in Keychain, and does not persist the account password locally. Cross-device sign-in uses the same Supabase identity. Repeated failed sign-in attempts are also locally throttled with an exponential lockout so the app does not rapidly retry credentials while server-side Supabase rate limits remain the authoritative abuse control.

When a remote account backend is configured, protected screens require a stored session that can be refreshed. If no session is present, Venture returns to authentication instead of trusting the local onboarding flag. Release builds with no configured account backend hide account creation and provide an on-device profile instead of exposing an unverifiable email flow. Account deletion calls the authenticated Supabase `delete-account` Edge Function before local encrypted data and keys are destroyed. Sign out removes the Keychain session token.

The checked-in privacy manifest declares linked name and email collection for the Supabase account path. App Store privacy answers must match this declaration before submission, even if a particular user chooses the on-device profile.

Email deliverability checks are configured with `VentureEmailVerifierBaseURL` and `VentureEmailVerifierProvider` set to `reacher` or `aftership`. Reacher-compatible servers use `POST /v1/check_email`; AfterShip-compatible servers use `GET /v1/{email}/verification` when wrapped by your backend. SMTP checks, provider API keys, email sending, phone OTP, refresh-token rotation, rate limiting, CSRF protection, and audit logs belong on the server side, not in the iOS bundle. Development builds without a backend use a local verification-code fallback so onboarding can be tested, but that fallback is not cross-device account sync.

## Efficiency And Security

- Writes are debounced through `VentureJobPipeline`.
- At most 365 daily snapshots are retained.
- Metrics are encrypted with AES-256-GCM before file storage.
- The encryption key is stored in Keychain with device-only accessibility.
- Production auth sessions are stored as Keychain tokens with `WhenUnlockedThisDeviceOnly` accessibility; production account passwords are not stored in the app.
- Raw camera frames and microphone buffers are processed transiently and not persisted.
- Screen Time shielding requires an Apple-approved Family Controls entitlement, explicit authorization, and user selection. The Personal Team development target disables shielding so the app can be signed and run; sleep-aware local reminders remain available.
- When Family Controls is available, the focus recommendation adapts between 25, 45, and 60 minutes using measured sleep and signal load. The active app expires the shield at the end of the window and schedules a local end reminder; exact background enforcement still requires Apple's Screen Time extension lifecycle.
- The on-device assistant receives structured metrics only.

## Local Build Reliability

The checkout can live under an iCloud-managed `Documents` folder. On this machine, direct `xcodebuild` calls from that location may block inside `NSFileCoordinator` while recursively reading `Venture.xcodeproj`. Use `tools/build_simulator_clean.sh` for simulator verification: it mirrors the repo to a temporary local directory, excludes Xcode user state and git metadata, and builds with DerivedData outside iCloud.
