import Foundation
import os.log
import SwiftData

enum ModelContainerConfiguration {
    static let appGroupIdentifier = "group.app.lociate.ios"

    private static let logger = Logger(subsystem: "app.lociate.ios", category: "ModelContainer")

    static let schema = Schema([
        Locus.self,
        Household.self,
        HouseholdMember.self,
        UserProfile.self,
        AuditLogEntry.self,
    ])

    static func production() throws -> ModelContainer {
        // SwiftData *traps* rather than throwing when the App Group entitlement is
        // missing — "Unable to find App Group Container in Entitlements" — so the
        // `throws` on this function cannot catch it and the enclosing do/catch in
        // LociateApp is no help. Availability has to be probed first.
        //
        // The entitlement is absent from any build that is not signed with it, which
        // is exactly what CODE_SIGNING_ALLOWED=NO produces in CI; that aborted the
        // unit tests before a single one ran.
        let groupIsAvailable = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) != nil

        let configuration: ModelConfiguration
        if groupIsAvailable {
            configuration = ModelConfiguration(
                "Lociate",
                schema: schema,
                isStoredInMemoryOnly: false,
                groupContainer: .identifier(appGroupIdentifier)
            )
        } else {
            // The widget reads this store through the App Group, so falling back to a
            // local one means the widget cannot see the user's loci. That must never
            // happen in a signed build — log it loudly rather than refusing to launch.
            logger.error(
                "App Group \(appGroupIdentifier, privacy: .public) is unavailable; using a local store. The widget will not see this data."
            )
            configuration = ModelConfiguration(
                "Lociate",
                schema: schema,
                isStoredInMemoryOnly: false
            )
        }

        let container = try ModelContainer(for: schema, configurations: [configuration])
        // US-184: Exclude sensitive local data from iCloud/iTunes backups.
        // Voice notes, transcripts, and household invite codes should not
        // leave the device unless the user explicitly opts in via sync.
        applyBackupExclusionToStorageDirectories()
        return container
    }

    /// US-184: Flags the app's Documents directory (audio files) and App
    /// Group container (SwiftData store) as excluded from device backups.
    /// Idempotent — safe to call on every cold start.
    static func applyBackupExclusionToStorageDirectories() {
        let fileManager = FileManager.default
        var directories: [URL] = []

        directories.append(URL.documentsDirectory)
        if let group = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            directories.append(group)
        }

        for directory in directories {
            var url = directory
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? url.setResourceValues(resourceValues)
        }
    }

    static func preview() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "LociatePreview",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
