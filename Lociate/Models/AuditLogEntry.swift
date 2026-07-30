import Foundation
import SwiftData
import UIKit

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

/// US-187: lives in Models/ rather than alongside `SecurityAuditLogger` because
/// `ModelContainerConfiguration.schema` includes it, and the widget extension has
/// to build that same schema. Keeping the @Model here lets the widget share the
/// five model files without dragging the logger and analytics stack into the
/// extension's memory budget.
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
