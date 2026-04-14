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
        return try ModelContainer(for: schema, configurations: [configuration])
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
