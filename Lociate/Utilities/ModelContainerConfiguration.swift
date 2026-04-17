import Foundation
import SwiftData

enum ModelContainerConfiguration {
    static let schema = Schema([
        Locus.self,
        Household.self,
        HouseholdMember.self,
        UserProfile.self,
        AuditLogEntry.self,
    ])

    static func production() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "Lociate",
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .identifier("group.com.pearsonmedia.lociate")
        )
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

        if let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            directories.append(documents)
        }
        if let group = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.pearsonmedia.lociate"
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
