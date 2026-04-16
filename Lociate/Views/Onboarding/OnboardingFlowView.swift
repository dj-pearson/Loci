import SwiftUI

/// Full-screen onboarding flow that gates the main app on first launch.
/// Steps through welcome pages, permission requests, and first-locus prompt.
struct OnboardingFlowView: View {
    @Bindable var viewModel: OnboardingViewModel
    let locationService: LocationService
    let notificationService: NotificationService

    @State private var audioService = AudioService()

    var body: some View {
        ZStack {
            switch viewModel.currentStep {
            case .welcome:
                WelcomeOnboardingView(
                    onFinish: { viewModel.advance() },
                    onSkip: { viewModel.advance() }
                )
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))

            case .locationPermission:
                LocationPermissionView(
                    locationService: locationService,
                    onComplete: { viewModel.advance() },
                    onSkip: { viewModel.skip() }
                )
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))

            case .notificationPermission:
                NotificationPermissionView(
                    notificationService: notificationService,
                    onComplete: { viewModel.advance() },
                    onSkip: { viewModel.skip() }
                )
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))

            case .microphonePermission:
                MicrophonePermissionView(
                    audioService: audioService,
                    onComplete: { viewModel.advance() },
                    onSkip: { viewModel.skip() }
                )
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))

            case .firstLocus:
                OnboardingPageView(
                    systemImage: "waveform.circle.fill",
                    headline: String(localized: "Drop Your First Locus"),
                    bodyText: String(localized: "Tap the microphone button on the map to record your first voice note. It will be pinned right where you are."),
                    ctaTitle: String(localized: "Let's Go!")
                ) {
                    viewModel.completeOnboarding()
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))

            case .complete:
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.35), value: viewModel.currentStep)
        .overlay(alignment: .top) {
            if viewModel.currentStep != .welcome && viewModel.currentStep != .complete {
                progressIndicator
                    .padding(.top, Theme.Spacing.md)
            }
        }
    }

    // MARK: - Progress Indicator

    private var progressIndicator: some View {
        let totalSteps = OnboardingStep.allCases.count - 1 // exclude .complete
        let currentIndex = OnboardingStep.allCases.firstIndex(of: viewModel.currentStep) ?? 0

        return HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index <= currentIndex ? Theme.primary : Theme.primary.opacity(0.2))
                    .frame(width: index == currentIndex ? 20 : 8, height: 4)
                    .animation(.easeInOut(duration: 0.2), value: currentIndex)
            }
        }
    }
}
