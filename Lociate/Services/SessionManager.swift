import Foundation
import SwiftUI

/// Manages secure session lifecycle including inactivity timeout, token refresh
/// failure handling, and re-authentication for sensitive operations. (US-145)
@Observable
final class SessionManager {
    // MARK: - State

    private(set) var isSessionExpired = false
    private(set) var sessionExpiryReason: ExpiryReason?
    private(set) var requiresReAuth = false
    var reAuthCompletion: ((Bool) -> Void)?

    enum ExpiryReason {
        case inactivity
        case tokenRefreshFailed
        case manualSignOut

        var message: String {
            switch self {
            case .inactivity:
                String(localized: "Your session expired due to inactivity. Please sign in again.")
            case .tokenRefreshFailed:
                String(localized: "Your session could not be refreshed. Please sign in again.")
            case .manualSignOut:
                String(localized: "You have been signed out.")
            }
        }
    }

    // MARK: - Keychain Keys

    private enum Keys {
        static let lastActivity = "app.lociate.ios.session.lastActivity"
        static let tokenRefreshFailCount = "app.lociate.ios.session.refreshFailCount"
    }

    // MARK: - Activity Tracking

    private var lastActivityUpdateTime: Date?

    /// Record meaningful user activity (creating/editing loci, navigating, etc.).
    /// Throttled to avoid excessive writes.
    func recordActivity() {
        let now = Date()

        // Throttle updates to once per interval
        if let lastUpdate = lastActivityUpdateTime,
           now.timeIntervalSince(lastUpdate) < AppConstants.sessionActivityUpdateIntervalSeconds {
            return
        }

        lastActivityUpdateTime = now
        saveTimestamp(now, forKey: Keys.lastActivity)
    }

    /// Check if the session has expired due to inactivity.
    /// Returns true if the user should be signed out.
    func checkSessionValidity() -> Bool {
        guard let lastActivity = loadTimestamp(forKey: Keys.lastActivity) else {
            // No activity recorded — new session, record now
            recordActivity()
            return true
        }

        let daysSinceActivity = Calendar.current.dateComponents(
            [.day], from: lastActivity, to: Date()
        ).day ?? 0

        if daysSinceActivity >= AppConstants.sessionInactivityTimeoutDays {
            isSessionExpired = true
            sessionExpiryReason = .inactivity
            return false
        }

        return true
    }

    // MARK: - Token Refresh Failure Tracking

    /// Record a token refresh failure. Returns true if max retries exceeded.
    func recordTokenRefreshFailure() -> Bool {
        var failCount = loadInt(forKey: Keys.tokenRefreshFailCount)
        failCount += 1
        saveInt(failCount, forKey: Keys.tokenRefreshFailCount)

        if failCount >= AppConstants.tokenRefreshMaxRetries {
            isSessionExpired = true
            sessionExpiryReason = .tokenRefreshFailed
            return true
        }
        return false
    }

    /// Reset token refresh failure counter (called on successful refresh).
    func resetTokenRefreshFailures() {
        saveInt(0, forKey: Keys.tokenRefreshFailCount)
    }

    // MARK: - Re-Authentication for Sensitive Operations

    /// Sensitive operations that require re-authentication.
    enum SensitiveOperation: String {
        case deleteAccount = "delete your account"
        case changePassword = "change your password"
        case manageHousehold = "manage household settings"
        case exportData = "export your data"
    }

    /// Request re-authentication before a sensitive operation.
    /// Caller should present a biometric/password prompt.
    func requestReAuth(for operation: SensitiveOperation, completion: @escaping (Bool) -> Void) {
        requiresReAuth = true
        reAuthCompletion = { [weak self] success in
            self?.requiresReAuth = false
            self?.reAuthCompletion = nil
            if success {
                self?.recordActivity()
            }
            completion(success)
        }
    }

    /// Complete the re-authentication flow.
    func completeReAuth(success: Bool) {
        reAuthCompletion?(success)
    }

    // MARK: - Session Cleanup

    /// Clear all session data on sign out.
    func clearSession() {
        try? KeychainService.delete(key: Keys.lastActivity)
        try? KeychainService.delete(key: Keys.tokenRefreshFailCount)
        isSessionExpired = false
        sessionExpiryReason = nil
        requiresReAuth = false
        reAuthCompletion = nil
        lastActivityUpdateTime = nil
    }

    // MARK: - Keychain Helpers

    private func saveTimestamp(_ date: Date, forKey key: String) {
        let data = withUnsafeBytes(of: date.timeIntervalSince1970) { Data($0) }
        try? KeychainService.save(key: key, data: data)
    }

    private func loadTimestamp(forKey key: String) -> Date? {
        guard let data = try? KeychainService.load(key: key),
              data.count == MemoryLayout<TimeInterval>.size else { return nil }
        let interval = data.withUnsafeBytes { $0.load(as: TimeInterval.self) }
        return Date(timeIntervalSince1970: interval)
    }

    private func saveInt(_ value: Int, forKey key: String) {
        let data = withUnsafeBytes(of: value) { Data($0) }
        try? KeychainService.save(key: key, data: data)
    }

    private func loadInt(forKey key: String) -> Int {
        guard let data = try? KeychainService.load(key: key),
              data.count == MemoryLayout<Int>.size else { return 0 }
        return data.withUnsafeBytes { $0.load(as: Int.self) }
    }
}
