import SwiftUI

struct OnboardingFlowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let store: VentureStore
    let onComplete: () -> Void

    @State private var stage: Stage = .launch

    init(store: VentureStore, onComplete: @escaping () -> Void) {
        self.store = store
        self.onComplete = onComplete
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-voicePreview") || arguments.contains("-eyePreview") {
            _stage = State(initialValue: .scan)
        } else if arguments.contains("-authPreview") {
            _stage = State(initialValue: .authentication)
        }
#endif
    }

    var body: some View {
        ZStack {
            switch stage {
            case .launch:
                LaunchView { transition(to: .authentication) }
            case .authentication:
                AuthenticationView { transition(to: .permissions) }
                    .transition(
                        .asymmetric(
                            insertion: .opacity,
                            removal: .opacity
                        )
                    )
            case .permissions:
                PermissionSetupView(store: store) { transition(to: .baseline) }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .baseline:
                BaselineIntroView {
                    transition(to: .scan)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            case .scan:
                ScanFlowView(store: store, completionAction: onComplete)
                    .transition(.scale(scale: 1.04).combined(with: .opacity))
            }
        }
    }

    private func transition(to newStage: Stage) {
        withAnimation(.easeInOut(duration: reduceMotion ? 0.18 : 0.42)) {
            stage = newStage
        }
    }
}

private extension OnboardingFlowView {
    enum Stage {
        case launch
        case authentication
        case permissions
        case baseline
        case scan
    }
}
