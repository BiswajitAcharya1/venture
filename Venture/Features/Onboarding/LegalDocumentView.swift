import SwiftUI

enum LegalDocument: String, Identifiable {
    case terms = "Terms of Service"
    case privacy = "Privacy Policy"

    var id: String { rawValue }

    var introduction: String {
        switch self {
        case .terms:
            "These Terms of Service govern your use of venture. By accessing or using the app, you agree to these terms. If you do not agree, do not use venture."
        case .privacy:
            "This Privacy Policy explains how venture processes information when you use its scans, Apple Health connection, cognitive tasks, local account, and on-device companion. venture is designed to minimize data collection and keep measured history on your device."
        }
    }

    fileprivate var sections: [LegalSection] {
        switch self {
        case .terms:
            termsSections
        case .privacy:
            privacySections
        }
    }

    private var termsSections: [LegalSection] {
        [
            LegalSection(
                title: "1. purpose of venture",
                body: "venture is a personal measurement and trend-awareness tool. It combines optional camera-guided pupil measurements, voice timing measurements, cognitive task performance, and information you choose to read from Apple Health. The app compares available measurements with your own recorded history and may present summaries, estimates, or suggested wellbeing actions."
            ),
            LegalSection(
                title: "2. not medical care",
                body: "venture is not a medical device, physician, therapist, diagnostic service, treatment service, or emergency service. It does not diagnose, confirm, rule out, predict, or treat Alzheimer’s disease, Parkinson’s disease, depression, heart disease, an eye condition, or any other medical or mental-health condition. Measurements, model outputs, and personal-change estimates are screening information only. They cannot be 100% accurate, can be incomplete or wrong, and can be affected by lighting, noise, device position, sensor quality, permissions, sleep, stress, medication, illness, and other factors. Do not delay professional care or make medication, treatment, safety, or emergency decisions based on venture."
            ),
            LegalSection(
                title: "3. emergencies and urgent concerns",
                body: "Do not use venture for emergencies. If you believe you or another person may be in immediate danger, call local emergency services. In the United States, call or text 988 for the Suicide & Crisis Lifeline when appropriate. New or worsening chest pain, trouble breathing, fainting, one-sided weakness, sudden confusion, severe distress, or other urgent symptoms require qualified medical attention."
            ),
            LegalSection(
                title: "4. eligibility",
                body: "You must be legally able to agree to these terms. venture is not directed to children under 13. If local law requires parental or guardian consent for your use of the app or processing of health-related information, you may use venture only after obtaining that consent."
            ),
            LegalSection(
                title: "5. accounts and device access",
                body: "Production email accounts require a verified email address and a HTTPS account backend so you can sign in on another device without storing your password in the app. Access tokens are stored in Keychain on each device. Release builds without a configured backend do not expose account creation and instead allow an on-device profile. Development builds may use a clearly labeled local fallback that cannot sync accounts across devices. You are responsible for protecting your device and credentials and preventing unauthorized access. Development identity-provider placeholders are not included in release builds."
            ),
            LegalSection(
                title: "6. permissions",
                body: "Some features require camera, microphone, speech recognition, Face ID, notifications, Screen Time, or Apple Health permission. You may decline or later revoke a permission in iOS settings, but the related feature may become unavailable. venture must not represent missing measurements as completed measurements."
            ),
            LegalSection(
                title: "7. Apple Health and Apple Watch",
                body: "With your permission, venture reads selected HealthKit data such as sleep, heart-rate variability, resting heart rate, oxygen saturation, activity, cuff-recorded blood pressure, and Apple Watch ECG information. venture does not write health records to Apple Health. It cannot start an Apple Watch ECG recording and does not independently classify ECG diseases. Any rhythm classification displayed from an imported ECG is Apple’s recorded classification, not an venture diagnosis."
            ),
            LegalSection(
                title: "8. estimates and personal reference",
                body: "Scores and summaries depend on available measurements, measurement quality, device sensors, permissions, and the amount of personal history recorded. They are personal-reference estimates rather than population diagnoses or guarantees. A high screening value does not prove that a condition is present. A low screening value does not prove that a condition is absent. A change in a score does not establish its cause, and an unchanged score does not establish that you are healthy."
            ),
            LegalSection(
                title: "9. wellbeing and device controls",
                body: "venture may suggest actions such as reducing interruptions, scheduling a reminder, or enabling Screen Time protection for items you select. These actions require your permission and may depend on Apple-approved entitlements that are not available in every build. You remain responsible for reviewing and changing any device-control selection."
            ),
            LegalSection(
                title: "10. acceptable use",
                body: "You may not misuse venture, attempt to bypass its security, interfere with its operation, reverse engineer protected portions except where law permits, use it to harm another person, or present its estimates as a professional diagnosis. You may not use the app in a way that violates applicable law or another person’s rights."
            ),
            LegalSection(
                title: "11. ownership",
                body: "venture’s software, design, branding, text, and original content are protected by applicable intellectual-property laws. These terms give you a limited, personal, revocable, non-exclusive, non-transferable right to use the app on supported Apple devices. They do not transfer ownership of venture or third-party technology used by the app."
            ),
            LegalSection(
                title: "12. third-party and system services",
                body: "venture relies on Apple technologies including iOS, HealthKit, Speech, Face ID, Keychain, notifications, and related frameworks. Those services are controlled by Apple and may be governed by Apple’s terms and privacy policies. Availability can change with device model, region, operating-system version, permissions, or Apple policy."
            ),
            LegalSection(
                title: "13. availability and changes",
                body: "Features may be added, changed, limited, suspended, or removed to improve safety, accuracy, performance, legal compliance, or compatibility. Prototype and personal-development builds may not include production authentication, cloud sync, Family Controls, or every capability described in product plans. The app may stop supporting older operating systems or devices."
            ),
            LegalSection(
                title: "14. research models and third-party materials",
                body: "Some measurements use or are informed by third-party research code, datasets, models, and Apple frameworks. Published research performance does not establish performance for every person, device, language, recording environment, or venture capture. Availability of source code does not make a model clinically validated, and venture will identify a model as active only when its required artifact is installed and executable in the app."
            ),
            LegalSection(
                title: "15. disclaimer of warranties",
                body: "To the fullest extent permitted by law, venture is provided as available and without warranties of uninterrupted operation, error-free measurements, fitness for a particular purpose, non-infringement, or medical accuracy. Some jurisdictions do not allow certain warranty exclusions, so part of this section may not apply to you."
            ),
            LegalSection(
                title: "16. limitation of liability",
                body: "To the fullest extent permitted by law, venture’s operator and contributors are not liable for indirect, incidental, special, consequential, exemplary, or punitive damages, loss of data, loss of opportunity, or decisions made in reliance on app estimates. Nothing in these terms excludes liability that cannot legally be excluded."
            ),
            LegalSection(
                title: "17. indemnity",
                body: "To the extent permitted by applicable law, you agree to be responsible for claims, losses, or expenses resulting from your unlawful misuse of venture, violation of these terms, or presentation of venture output as a professional diagnosis. This section does not require you to indemnify a party for conduct that cannot legally be shifted to you."
            ),
            LegalSection(
                title: "18. termination",
                body: "You may stop using venture at any time. Access may be limited or terminated if use creates security, legal, or safety risk or materially violates these terms. Provisions that by their nature should survive termination, including ownership, disclaimers, and liability limitations, will continue to apply."
            ),
            LegalSection(
                title: "19. changes to these terms",
                body: "These terms may be updated as venture changes. The effective date will be revised when an update is published. Continued use after an update takes effect means you accept the revised terms where permitted by law. Material changes should be presented in the app or through the distribution channel used for venture."
            ),
            LegalSection(
                title: "20. questions",
                body: "Questions about these terms should be sent through the support contact listed on venture’s App Store product page or the distribution channel from which you received the app."
            ),
            LegalSection(
                title: "21. App Store distribution",
                body: "When venture is obtained through Apple’s App Store, your use is also subject to Apple’s applicable Usage Rules and licensed-application terms. Apple is not responsible for venture’s measurements, support, maintenance, warranties, or claims except where Apple’s terms or applicable law expressly provide otherwise. Nothing in these terms limits rights that cannot legally be waived."
            )
        ]
    }

    private var privacySections: [LegalSection] {
        [
            LegalSection(
                title: "1. privacy design",
                body: "venture uses data minimization, on-device processing where available, permission-based access, and encrypted local storage. The current build does not include advertising, cross-app tracking, third-party analytics, or production cloud sync."
            ),
            LegalSection(
                title: "2. information you provide",
                body: "If Supabase Auth is configured and you create an email account, venture sends the name, email address, password, verification or recovery code, legal-consent versions, and authentication request information to Supabase over HTTPS so Supabase can create and secure the account, deliver account emails, prevent abuse, and issue sessions. venture stores returned session tokens in Keychain and does not persist the production account password. Supabase processes this information under its own infrastructure and privacy terms. Release builds without Supabase use an on-device profile and do not collect account credentials. Development builds may use a device-only local account; signed-device builds store salted password-derived material and account details in Keychain, while unsigned debug simulator builds may use an iOS-protected local file when Keychain is unavailable. Text you type into the companion is processed locally and is not added to scan history by the current build."
            ),
            LegalSection(
                title: "3. pupil and camera processing",
                body: "When you begin a pupil scan and grant camera access, the front camera supplies live frames used to locate facial and eye landmarks and estimate relative pupil response, symmetry, variability, and fixation stability. Camera frames are processed during the session and are not saved as videos or photographs. venture stores only extracted measurements when a scan produces a usable result. Camera-derived measurements are sensitive to lighting, glare, position, camera quality, and movement and are not retinal examinations or disease tests."
            ),
            LegalSection(
                title: "4. voice and speech processing",
                body: "When you begin a voice scan and grant microphone access, venture processes a six-second sustained sound in memory to measure audio level, voice activity, and background noise. The in-memory sample is discarded after processing. Extracted signal measurements may be saved; raw recordings and transcripts are not retained in measured history. The voice task does not produce a Parkinson’s score or diagnosis."
            ),
            LegalSection(
                title: "5. cognitive task information",
                body: "venture records results produced by tasks you choose to complete, such as working-memory accuracy and attention-switch performance. It stores task outcomes and timing-derived measurements rather than a screen recording of your activity. These results reflect performance in that session and are not clinical cognitive-test results."
            ),
            LegalSection(
                title: "6. Apple Health information",
                body: "After you grant HealthKit permission, venture may read selected sleep, heart-rate variability, resting heart rate, oxygen saturation, steps, active energy, cuff-recorded blood pressure, and ECG data. ECG data may include Apple’s classification, symptoms recorded with the ECG, source, duration, average heart rate, and available lead-I voltage samples. venture requests read access only and does not alter or delete the source records in Apple Health. Removing cached health history inside venture does not remove information from the Health app. You can revoke Health access in iOS settings."
            ),
            LegalSection(
                title: "7. derived information",
                body: "venture may derive a personal signal-load score, measurement summaries, change levels, and suggested actions from available scan and health information. These outputs are estimates tied to your recorded history. No model or measurement can be 100% accurate. Outputs are not medical diagnoses, clinical risk scores, or proof that a condition is present or absent."
            ),
            LegalSection(
                title: "8. companion and optional calling tests",
                body: "The companion uses the bundled on-device language model or the local measurement explainer. Optional care-page calling tests send the text you submit to the calling service you configure and, for Claude or Amazon Nova tests, to the configured model provider. Measured summaries are included only when you opt in and are shown before submission. On-device call-test dictation does not upload audio. If you separately opt in to an automated clinic call, the service sends the clinic destination number and generated speech to Twilio; Twilio carries call audio and transcribes the clinic’s replies. The service uses those reply transcripts and your selected summary to continue the conversation with the selected provider. It does not request call recording or persist transcripts. Cloud providers process submitted information under their own account settings and terms. The clinic must confirm any appointment."
            ),
            LegalSection(
                title: "9. storage and security",
                body: "Saved scan history, cached HealthKit measurements, and derived summaries are encoded and encrypted with AES-256-GCM using a device-specific key stored in the iOS data-protection Keychain with unlocked-device-only accessibility. The encrypted file uses iOS complete file protection and is marked to be excluded from device backup. Supabase account sessions use ephemeral HTTPS networking without cookies or response caching, reject redirects to another host or a non-HTTPS destination, rotate refresh tokens, and store session tokens in Keychain. The iOS binary contains only Supabase’s publishable anon key; the privileged service-role key remains server-side. Development fallback credentials are salted and derived with PBKDF2-HMAC-SHA256 before storage. Face ID may be used for re-authentication when enabled and supported. No security system can guarantee absolute protection."
            ),
            LegalSection(
                title: "10. retention",
                body: "venture retains encrypted extracted measurements on the device until you delete the relevant history, clear all scans, or remove the app’s data. The app limits persisted scan history to the most recent 365 snapshots. Temporary voice recordings use complete file protection, are excluded from backup, and are removed after capture ends; stale venture voice files are also removed before a new recording begins. Camera frames are not written to persistent storage. iOS may manage Keychain items separately from the app’s ordinary data container."
            ),
            LegalSection(
                title: "11. deletion and controls",
                body: "The privacy vault lets you delete eye measurements, voice measurements, cached health measurements, or all scan history stored by venture. These controls do not change source records in Apple Health. When a production account exists, the account-wipe control requests deletion from the configured account service before destroying local encrypted data. You can also revoke camera, microphone, speech, notification, Face ID, Screen Time, or Health permissions through iOS settings. Sign out ends the current app session and removes the stored session token, but it does not itself erase encrypted measurement history."
            ),
            LegalSection(
                title: "12. sharing and disclosure",
                body: "venture does not sell personal information, share health information for advertising, or use health information for cross-app tracking. venture does not include third-party advertising or analytics SDKs. If you choose an email account, Supabase processes account identity, authentication, email-delivery, security, and operational-log information as venture’s backend provider; scan history, raw media, HealthKit records, and companion context are not uploaded to Supabase by the current app. Information may also be processed by Apple when you use Apple-controlled services such as HealthKit, on-device Speech, iCloud device backup where applicable, or App Store distribution. venture may disclose information when required by valid law or necessary to protect rights and safety."
            ),
            LegalSection(
                title: "13. backups and device transfer",
                body: "venture marks its encrypted metrics file and temporary voice files to be excluded from device backup. The encryption key and local authentication secrets use device-only Keychain accessibility and are not designed to migrate to another device. Apple controls the final behavior of operating-system backup and transfer services. venture does not currently provide its own cloud backup or multi-device measurement sync service."
            ),
            LegalSection(
                title: "14. notifications and Screen Time",
                body: "If you grant notification permission, venture may schedule local recovery or wind-down reminders. If a distribution build has Apple’s required Family Controls entitlement and you grant Screen Time access, venture can apply shields only to apps, categories, or websites you select. These settings are controlled through Apple frameworks and can be changed or revoked by you."
            ),
            LegalSection(
                title: "15. children",
                body: "venture is not directed to children under 13 and does not knowingly seek their personal information. A parent or guardian should not permit a child to use the app when consent is required but has not been provided."
            ),
            LegalSection(
                title: "16. your choices and rights",
                body: "Depending on where you live, privacy law may provide rights to know, access, correct, delete, restrict, or obtain a copy of certain personal information. Because the current build keeps measurements locally, many choices are exercised directly through the privacy vault, iOS permission settings, or deletion of app data. Questions or requests should be sent through the support contact on venture’s App Store product page or distribution channel."
            ),
            LegalSection(
                title: "17. policy changes",
                body: "This policy may change when venture adds services, changes data practices, or responds to legal and safety requirements. The effective date will be updated, and material changes should be presented in the app or through the distribution channel before or when they take effect."
            ),
            LegalSection(
                title: "18. consumer health data and consent",
                body: "Eye, voice, cognitive, recovery, blood-pressure, ECG, sleep, stress-related, and derived signal information may qualify as consumer health data or sensitive personal information under some laws. venture processes a category only after you choose the related scan, enter the information, or grant the required iOS permission. The current build does not sell consumer health data or use it for targeted advertising. Where applicable law grants additional rights, you may request access, correction, deletion, withdrawal of consent, or information about disclosures through the support contact on the App Store product page. Withdrawing permission stops future access but may not delete information already stored until you use the privacy vault or request deletion."
            ),
            LegalSection(
                title: "19. security incidents",
                body: "venture uses technical safeguards but no system can eliminate all risk. If the operator becomes aware of a security incident involving information it possesses, it will investigate and provide notices required by applicable law. Device-only information that never leaves your device ordinarily cannot be inspected or recovered by the operator. You should keep iOS updated, use a device passcode, protect account credentials, and report suspected unauthorized access through the App Store support contact."
            )
        ]
    }
}

struct LegalDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let document: LegalDocument
    @State private var closing = false

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(document.rawValue)
                                .font(.system(.largeTitle, design: .serif, weight: .regular))
                            Text("Effective June 20, 2026")
                                .font(.caption)
                                .foregroundStyle(VentureTheme.secondary)
                            Text(document.introduction)
                                .font(.body)
                                .lineSpacing(5)
                        }

                        Divider().opacity(0.45)

                        ForEach(document.sections) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(section.title)
                                    .font(.system(.headline, design: .rounded, weight: .semibold))
                                Text(section.body)
                                    .font(.subheadline)
                                    .foregroundStyle(VentureTheme.secondary)
                                    .lineSpacing(5)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                    .padding(.bottom, 20)
                }
                .opacity(closing ? 0 : 1)
                .blur(radius: closing && !reduceMotion ? 3 : 0)
                .offset(y: closing && !reduceMotion ? 8 : 0)
                }
            .background(VentureTheme.background)
            .foregroundStyle(VentureTheme.ink)
            .textSelection(.enabled)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("close") { closeDocument() }
                        .buttonStyle(HapticPlainButtonStyle())
                }
            }
        }
    }

    private func closeDocument() {
        guard !closing else { return }
        Haptics.soft()
        withAnimation(.easeInOut(duration: 0.28)) {
            closing = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            dismiss()
        }
    }
}

private struct LegalSection: Identifiable {
    let title: String
    let body: String

    var id: String { title }
}
