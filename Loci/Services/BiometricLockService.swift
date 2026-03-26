import Foundation
import LocalAuthentication

@Observable
final class BiometricLockService {
    // MARK: - State

    var isLocked = false

    // MARK: - Settings (UserDefaults-backed)

    var isBiometricLockEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "loci_biometric_lock_enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "loci_biometric_lock_enabled") }
    }

    // MARK: - Grace Period

    private static let gracePeriod: TimeInterval = 5 * 60 // 5 minutes
    private var lastAuthenticatedDate: Date?

    // MARK: - Biometric Availability

    var biometricType: BiometricType {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        @unknown default: return .none
        }
    }

    func canUseBiometrics() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    // MARK: - Authentication

    /// Triggers biometric prompt with device passcode fallback.
    /// Returns `true` if authentication succeeded.
    func authenticate() async throws -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = String(localized: "Use Passcode")

        // Use deviceOwnerAuthentication to allow passcode fallback
        let reason = String(localized: "Unlock Loci to access your notes")

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            if success {
                lastAuthenticatedDate = Date()
                isLocked = false
            }
            return success
        } catch {
            throw BiometricError.authenticationFailed(error)
        }
    }

    // MARK: - Lock Management

    /// Called when app enters foreground to determine if lock should engage.
    func lockIfNeeded() {
        guard isBiometricLockEnabled else {
            isLocked = false
            return
        }

        if let lastAuth = lastAuthenticatedDate,
           Date().timeIntervalSince(lastAuth) < Self.gracePeriod {
            // Within grace period — stay unlocked
            return
        }

        isLocked = true
    }

    /// Records a successful background transition timestamp.
    func recordBackgroundTransition() {
        // lastAuthenticatedDate is already set on successful auth;
        // no additional action needed on background entry.
    }
}

// MARK: - Types

enum BiometricType {
    case faceID
    case touchID
    case opticID
    case none

    var displayName: String {
        switch self {
        case .faceID: String(localized: "Face ID")
        case .touchID: String(localized: "Touch ID")
        case .opticID: String(localized: "Optic ID")
        case .none: String(localized: "Biometrics")
        }
    }

    var systemImageName: String {
        switch self {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        case .none: "lock"
        }
    }
}

enum BiometricError: Error, LocalizedError {
    case authenticationFailed(Error)
    case biometricsUnavailable

    var errorDescription: String? {
        switch self {
        case .authenticationFailed(let underlying):
            String(localized: "Authentication failed: \(underlying.localizedDescription)")
        case .biometricsUnavailable:
            String(localized: "Biometric authentication is not available on this device.")
        }
    }
}
