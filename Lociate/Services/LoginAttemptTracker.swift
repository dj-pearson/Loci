import Foundation
import Security

/// Tracks failed login attempts per email and enforces exponential backoff lockouts
/// to mitigate brute force attacks on the client side. (US-143)
@Observable
final class LoginAttemptTracker {
    // MARK: - Configuration

    /// Thresholds and corresponding cooldown durations in seconds.
    private static let lockoutPolicy: [(threshold: Int, cooldownSeconds: TimeInterval)] = [
        (3, 30),        // After 3 failures: 30s cooldown
        (5, 120),       // After 5 failures: 2 minutes
        (8, 900),       // After 8 failures: 15 minutes
        (10, 3600),     // After 10 failures: 1 hour
    ]

    private static let keychainPrefix = "app.lociate.ios.loginAttempts."

    // MARK: - Observable State

    private(set) var remainingLockoutSeconds: TimeInterval = 0
    private(set) var isLockedOut = false
    private(set) var failedAttemptCount: Int = 0
    private(set) var shouldSuggestPasswordReset = false

    private var lockoutTimer: Timer?
    private var currentEmail: String?

    // MARK: - Public API

    /// Check if a login attempt is allowed for the given email.
    /// Returns nil if allowed, or a user-facing message if locked out.
    func checkAllowed(email: String) -> String? {
        let record = loadRecord(for: email)
        currentEmail = email
        failedAttemptCount = record.count

        guard let lockoutEnd = record.lockoutEnd, lockoutEnd > Date() else {
            isLockedOut = false
            remainingLockoutSeconds = 0
            shouldSuggestPasswordReset = false
            return nil
        }

        let remaining = lockoutEnd.timeIntervalSinceNow
        isLockedOut = true
        remainingLockoutSeconds = remaining
        shouldSuggestPasswordReset = record.count >= 10
        startLockoutTimer(until: lockoutEnd)

        if record.count >= 10 {
            return String(localized: "Account temporarily locked. Try again in \(formattedTime(remaining)) or reset your password.")
        } else if record.count >= 8 {
            return String(localized: "Too many failed attempts. Try again in \(formattedTime(remaining)).")
        } else if record.count >= 5 {
            return String(localized: "Multiple failed attempts. Please wait \(formattedTime(remaining)).")
        } else {
            return String(localized: "Please wait \(formattedTime(remaining)) before trying again.")
        }
    }

    /// Record a failed login attempt for the given email.
    func recordFailure(email: String) {
        var record = loadRecord(for: email)
        record.count += 1
        record.lastAttempt = Date()

        // Determine cooldown based on current failure count
        let cooldown = Self.lockoutPolicy
            .last(where: { record.count >= $0.threshold })?
            .cooldownSeconds ?? 0

        if cooldown > 0 {
            record.lockoutEnd = Date().addingTimeInterval(cooldown)
        } else {
            record.lockoutEnd = nil
        }

        saveRecord(record, for: email)

        // Update observable state
        failedAttemptCount = record.count
        if let lockoutEnd = record.lockoutEnd {
            isLockedOut = true
            remainingLockoutSeconds = lockoutEnd.timeIntervalSinceNow
            shouldSuggestPasswordReset = record.count >= 10
            startLockoutTimer(until: lockoutEnd)
        }
    }

    /// Record a successful login — resets all attempt tracking for the email.
    func recordSuccess(email: String) {
        deleteRecord(for: email)
        isLockedOut = false
        remainingLockoutSeconds = 0
        failedAttemptCount = 0
        shouldSuggestPasswordReset = false
        lockoutTimer?.invalidate()
        lockoutTimer = nil
    }

    // MARK: - Lockout Timer

    private func startLockoutTimer(until end: Date) {
        lockoutTimer?.invalidate()
        lockoutTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            let remaining = end.timeIntervalSinceNow
            Task { @MainActor in
                if remaining <= 0 {
                    self.isLockedOut = false
                    self.remainingLockoutSeconds = 0
                    timer.invalidate()
                    self.lockoutTimer = nil
                } else {
                    self.remainingLockoutSeconds = remaining
                }
            }
        }
    }

    // MARK: - Time Formatting

    func formattedTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(max(0, seconds))
        if totalSeconds >= 3600 {
            let hours = totalSeconds / 3600
            let mins = (totalSeconds % 3600) / 60
            return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
        } else if totalSeconds >= 60 {
            let mins = totalSeconds / 60
            let secs = totalSeconds % 60
            return secs > 0 ? "\(mins)m \(secs)s" : "\(mins)m"
        } else {
            return "\(totalSeconds)s"
        }
    }

    // MARK: - Keychain Persistence

    private struct AttemptRecord: Codable {
        var count: Int
        var lastAttempt: Date?
        var lockoutEnd: Date?
    }

    private func keychainKey(for email: String) -> String {
        // `Data(_:)` over a String's UTF-8 view is non-failing, unlike
        // `data(using: .utf8)`, which is Optional for encodings that can fail.
        Self.keychainPrefix + Data(email.lowercased().utf8)
            .map { String(format: "%02x", $0) }.joined().suffix(32)
    }

    private func loadRecord(for email: String) -> AttemptRecord {
        let key = keychainKey(for: email)
        guard let data = try? KeychainService.load(key: key),
              let record = try? JSONDecoder().decode(AttemptRecord.self, from: data) else {
            return AttemptRecord(count: 0)
        }

        // Auto-expire records older than 24 hours with no active lockout
        if let lastAttempt = record.lastAttempt,
           Date().timeIntervalSince(lastAttempt) > 86400,
           (record.lockoutEnd ?? .distantPast) < Date() {
            deleteRecord(for: email)
            return AttemptRecord(count: 0)
        }

        return record
    }

    private func saveRecord(_ record: AttemptRecord, for email: String) {
        let key = keychainKey(for: email)
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? KeychainService.save(key: key, data: data)
    }

    private func deleteRecord(for email: String) {
        let key = keychainKey(for: email)
        try? KeychainService.delete(key: key)
    }
}
