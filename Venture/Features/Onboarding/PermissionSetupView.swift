import SwiftUI

struct PermissionSetupView: View {
    let store: VentureStore
    let onContinue: () -> Void

    @State private var camera: PermissionState = .waiting
    @State private var voice: PermissionState = .waiting
    @State private var health: PermissionState = .waiting
    @State private var screenTime: PermissionState = .waiting
    @State private var requesting = false

    private let sensors = SensorAuthorizationService()

    var body: some View {
        ZStack {
            VentureAtmosphereView().ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22) {
                Spacer()
                Text("choose what venture can measure")
                    .font(.system(.largeTitle, design: .serif, weight: .regular))
                Text("each permission enables a specific measurement or protection action. you can skip any of them; venture leaves unavailable signals blank.")
                    .font(.subheadline)
                    .foregroundStyle(VentureTheme.secondary)
                    .lineSpacing(3)

                VStack(spacing: 0) {
                    PermissionLine(title: "camera", detail: "live eye landmarks; frames are discarded", state: camera)
                    Divider()
                    PermissionLine(title: "voice", detail: "prompt timing and local speech recognition", state: voice)
                    Divider()
                    PermissionLine(title: "Apple Health", detail: "sleep, HRV, activity, and Apple Watch samples", state: health)
                    Divider()
                    PermissionLine(
                        title: "Screen Time",
                        detail: store.supportService.capabilityAvailable
                            ? "shield only apps and categories you select"
                            : "requires Apple-approved Family Controls access",
                        state: screenTime
                    )
                }
                .padding(.horizontal, 20)
                .background(VentureTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(VentureTheme.line, lineWidth: 0.8)
                }

                Button(requesting ? "requesting access…" : "review permissions", action: requestPermissions)
                    .buttonStyle(VenturePrimaryButtonStyle())
                    .disabled(requesting)

                Button("not now", action: onContinue)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .buttonStyle(HapticPlainButtonStyle())

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .foregroundStyle(VentureTheme.ink)
    }

    private func requestPermissions() {
        guard !requesting else { return }
        requesting = true
        Task {
            camera = await sensors.requestCameraAccess() ? .granted : .skipped
            let microphone = await sensors.requestMicrophoneAccess()
            let speech = await sensors.requestSpeechRecognitionAccess()
            voice = microphone && speech ? .granted : .skipped
            await store.healthService.requestAccess()
            health = store.healthService.state == .connected ? .granted : .skipped
            await store.refreshHealth()
            if store.supportService.capabilityAvailable {
                await store.supportService.requestScreenTimeAuthorization()
                screenTime = store.supportService.isAuthorized ? .granted : .skipped
            } else {
                screenTime = .unavailable
            }
            requesting = false
            try? await Task.sleep(for: .milliseconds(350))
            onContinue()
        }
    }
}

private struct PermissionLine: View {
    let title: String
    let detail: String
    let state: PermissionState

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(VentureTheme.secondary).lineSpacing(2)
            }
            Spacer()
            Text(state.label)
                .font(.caption2)
                .foregroundStyle(state == .granted ? VentureTheme.ink : VentureTheme.secondary)
        }
        .padding(.vertical, 17)
    }
}

private enum PermissionState: Equatable {
    case waiting, granted, skipped, unavailable
    var label: String {
        switch self {
        case .waiting: "optional"
        case .granted: "allowed"
        case .skipped: "not allowed"
        case .unavailable: "approved build required"
        }
    }
}
