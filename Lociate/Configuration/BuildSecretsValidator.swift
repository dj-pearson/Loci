import Foundation
import os.log

/// Validates that BuildSecrets are properly configured at runtime.
/// Called on app startup to catch misconfiguration early.
enum BuildSecretsValidator {
    private static let logger = Logger(subsystem: "app.lociate.ios", category: "BuildSecrets")

    /// Validate that required secrets are populated.
    ///
    /// - In DEBUG builds: logs warnings for empty or placeholder values.
    /// - In RELEASE builds: triggers a fatal error if critical secrets
    ///   (supabaseURL, supabaseAnonKey) are missing, since the app cannot
    ///   function without them.
    static func validate() {
        let checks: [(name: String, value: String, critical: Bool)] = [
            ("supabaseURL", BuildSecrets.supabaseURL, true),
            ("supabaseAnonKey", BuildSecrets.supabaseAnonKey, true),
            ("revenueCatAPIKey", BuildSecrets.revenueCatAPIKey, false),
            ("telemetryDeckAppID", BuildSecrets.telemetryDeckAppID, false),
            ("certificatePinHash", BuildSecrets.certificatePinHash, false),
        ]

        let placeholders: Set<String> = [
            "your-local-anon-key",
            "appl_REPLACE_WITH_KEY",
            "REPLACE_ME",
            "TODO",
        ]

        for check in checks {
            let isEmpty = check.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let isPlaceholder = placeholders.contains(check.value)

            guard isEmpty || isPlaceholder else { continue }

            let reason = isEmpty ? "empty" : "placeholder (\(check.value))"

            #if DEBUG
            logger.warning("BuildSecrets.\(check.name) is \(reason). Feature may not work.")
            #else
            if check.critical {
                fatalError(
                    "BuildSecrets.\(check.name) is \(reason). "
                    + "Production builds require valid API credentials. "
                    + "Ensure CI secrets are configured correctly."
                )
            } else {
                logger.error(
                    "BuildSecrets.\(check.name) is \(reason). Associated feature will be disabled."
                )
            }
            #endif
        }
    }
}
