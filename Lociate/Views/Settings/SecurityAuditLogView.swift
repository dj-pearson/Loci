import SwiftData
import SwiftUI

/// US-149: Settings > Security audit log view for transparency.
/// Shows recent authentication events so users can detect unauthorized access.
struct SecurityAuditLogView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var entries: [AuditLogEntry] = []

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Security Events",
                    systemImage: "shield.checkered",
                    description: Text(String(localized: "Authentication events will appear here."))
                )
            } else {
                ForEach(entries, id: \.id) { entry in
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: iconName(for: entry.eventType))
                            .foregroundStyle(iconColor(for: entry.eventType))
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayName(for: entry.eventType))
                                .font(Theme.Typography.body)

                            Text(entry.timestamp, style: .relative)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.textSecondary)

                            Text(entry.deviceInfo)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(String(localized: "Security Log"))
        .onAppear {
            entries = SecurityAuditLogger.shared.recentEntries(modelContext: modelContext)
        }
    }

    // MARK: - Display Helpers

    private func displayName(for eventType: String) -> String {
        switch eventType {
        case "sign_in_success": return "Signed in"
        case "sign_in_failure": return "Failed sign-in attempt"
        case "sign_up": return "Account created"
        case "sign_out": return "Signed out"
        case "password_reset_request": return "Password reset requested"
        case "session_expired": return "Session expired"
        case "account_deleted": return "Account deleted"
        case "biometric_unlock": return "Biometric unlock"
        case "biometric_failure": return "Biometric unlock failed"
        default: return eventType
        }
    }

    private func iconName(for eventType: String) -> String {
        switch eventType {
        case "sign_in_success": return "person.badge.shield.checkmark"
        case "sign_in_failure": return "exclamationmark.shield"
        case "sign_up": return "person.badge.plus"
        case "sign_out": return "rectangle.portrait.and.arrow.right"
        case "password_reset_request": return "key.horizontal"
        case "session_expired": return "clock.badge.exclamationmark"
        case "account_deleted": return "person.badge.minus"
        case "biometric_unlock": return "faceid"
        case "biometric_failure": return "faceid"
        default: return "shield"
        }
    }

    private func iconColor(for eventType: String) -> Color {
        switch eventType {
        case "sign_in_success", "biometric_unlock": return Theme.success
        case "sign_in_failure", "biometric_failure": return Theme.error
        case "sign_out", "session_expired": return Theme.warning
        case "account_deleted": return Theme.error
        default: return Theme.primary
        }
    }
}
