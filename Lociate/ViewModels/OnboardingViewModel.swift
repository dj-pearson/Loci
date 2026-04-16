import Foundation

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case locationPermission
    case notificationPermission
    case microphonePermission
    case firstLocus
    case complete
}

@Observable
final class OnboardingViewModel {
    var currentStep: OnboardingStep = .welcome

    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: Self.onboardingCompletedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.onboardingCompletedKey) }
    }

    private static let onboardingCompletedKey = "loci_has_completed_onboarding"

    private var allSteps: [OnboardingStep] {
        OnboardingStep.allCases
    }

    func advance() {
        guard let currentIndex = allSteps.firstIndex(of: currentStep),
              currentIndex + 1 < allSteps.count else {
            completeOnboarding()
            return
        }
        currentStep = allSteps[currentIndex + 1]
    }

    func skip() {
        guard currentStep != .welcome && currentStep != .firstLocus else {
            advance()
            return
        }
        advance()
    }

    func completeOnboarding() {
        currentStep = .complete
        hasCompletedOnboarding = true
    }
}
