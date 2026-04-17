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
        let reason = String(localized: "Unlock Lociate to access your notes")

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
    /// Since we now lock immediately on `.background` (see recordBackgroundTransition),
    /// the grace period only survives brief `.inactive` transitions (e.g. notification
    /// center pull-down) — never a true background send.
    func lockIfNeeded() {
        guard isBiometricLockEnabled else {
            isLocked = false
            return
        }

        if let lastAuth = lastAuthenticatedDate,
           Date().timeIntervalSince(lastAuth) < Self.gracePeriod {
            return
        }

        isLocked = true
    }

    /// Called on scenePhase==.background. Locks immediately so an attacker who
    /// pockets a briefly-unlocked device cannot reopen the app without biometric
    /// re-auth. This closes the 5-minute grace-period bypass identified in the
    /// 2026-04 security audit (US-175).
    func recordBackgroundTransition() {
        guard isBiometricLockEnabled else { return }
        lastAuthenticatedDate = nil
        isLocked = true
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
