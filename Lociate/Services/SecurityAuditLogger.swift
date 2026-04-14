import CryptoKit
import Foundation
import os.log
import SwiftData

// MARK: - Audit Event Types

enum SecurityAuditEvent: String, Codable, CaseIterable {
    case signInSuccess = "sign_in_success"
    case signInFailure = "sign_in_failure"
    case signUp = "sign_up"
    case signOut = "sign_out"
    case passwordResetRequest = "password_reset_request"
    case sessionExpired = "session_expired"
    case accountDeleted = "account_deleted"
    case biometricUnlock = "biometric_unlock"
    case biometricFailure = "biometric_failure"
}

// MARK: - Audit Log Entry (SwiftData)

@Model
final class AuditLogEntry {
    var id: UUID
    var eventType: String
    var emailHash: String
    var deviceInfo: String
    var appVersion: String
    var timestamp: Date

    init(
        eventType: SecurityAuditEvent,
        emailHash: String,
        deviceInfo: String = AuditLogEntry.currentDeviceInfo,
        appVersion: String = AuditLogEntry.currentAppVersion
    ) {
        self.id = UUID()
        self.eventType = eventType.rawValue
        self.emailHash = emailHash
        self.deviceInfo = deviceInfo
        self.appVersion = appVersion
        self.timestamp = Date()
    }

    static var currentDeviceInfo: String {
        let device = UIDevice.current
        return "\(device.model) (\(device.systemName) \(device.systemVersion))"
    }

    static var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
}

// MARK: - Security Audit Logger (US-149)

@Observable
final class SecurityAuditLogger {
    static let shared = SecurityAuditLogger()

    private let logger = Logger(subsystem: "com.pearsonmedia.loci", category: "SecurityAudit")
    private let maxEntries = 1000

    // MARK: - Public API

    /// Log a security audit event with the user's email (hashed for privacy).
    func log(
        event: SecurityAuditEvent,
        email: String? = nil,
        modelContext: ModelContext? = nil
    ) {
        let hashedEmail = email.map { hashEmail($0) } ?? "anonymous"

        // 1. Log to local SwiftData store
        if let context = modelContext {
            let entry = AuditLogEntry(eventType: event, emailHash: hashedEmail)
            context.insert(entry)

            // FIFO cleanup: cap at maxEntries
            cleanupOldEntries(context: context)

            try? context.save()
        }

        // 2. Log to TelemetryDeck for server-side analytics
        AnalyticsService.shared.track(
            AnalyticsEvent(rawValue: "security_\(event.rawValue)") ?? .appLaunch,
            properties: [
                "event_type": event.rawValue,
                "email_hash": hashedEmail,
                "device_info": AuditLogEntry.currentDeviceInfo,
                "app_version": AuditLogEntry.currentAppVersion,
            ]
        )

        // 3. Local os.log for development
        logger.info("Security event: \(event.rawValue) | email: \(hashedEmail)")
    }

    // MARK: - Query

    /// Fetch the most recent audit log entries for display in Settings > Security.
    func recentEntries(modelContext: ModelContext, limit: Int = 50) -> [AuditLogEntry] {
        var descriptor = FetchDescriptor<AuditLogEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Helpers

    /// SHA-256 hash of email for privacy — never store plaintext emails in logs.
    private func hashEmail(_ email: String) -> String {
        let data = Data(email.lowercased().utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined().prefix(16) + "..."
    }

    /// Remove oldest entries to keep the log capped at maxEntries (FIFO).
    private func cleanupOldEntries(context: ModelContext) {
        let countDescriptor = FetchDescriptor<AuditLogEntry>()
        guard let totalCount = try? context.fetchCount(countDescriptor),
              totalCount > maxEntries else { return }

        let deleteCount = totalCount - maxEntries
        var oldestDescriptor = FetchDescriptor<AuditLogEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        oldestDescriptor.fetchLimit = deleteCount

        if let oldEntries = try? context.fetch(oldestDescriptor) {
            for entry in oldEntries {
                context.delete(entry)
            }
        }
    }
}
