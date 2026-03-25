import Foundation
import SwiftData

enum ModelContainerConfiguration {
    static let schema = Schema([
        Locus.self,
        Household.self,
        HouseholdMember.self,
        UserProfile.self,
    ])

    static func production() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "Loci",
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .identifier("group.com.pearsonmedia.loci")
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func preview() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "LociPreview",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
