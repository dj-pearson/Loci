import Foundation
import SwiftData

enum PreviewData {
    // MARK: - User Profiles

    static let currentUser = UserProfile(
        displayName: "Alex Johnson",
        subscriptionTier: .premium
    )

    static let familyUser = UserProfile(
        displayName: "Sam Johnson",
        subscriptionTier: .family
    )

    static let freeUser = UserProfile(
        displayName: "Jordan Lee",
        subscriptionTier: .free
    )

    // MARK: - Household

    static let householdId = UUID()
    static let ownerId = UUID()

    static let sampleHousehold = Household(
        id: householdId,
        name: "The Johnsons",
        ownerId: ownerId,
        inviteCode: "ABC123",
        inviteExpiresAt: Date().addingTimeInterval(48 * 3600)
    )

    static let expiredHousehold = Household(
        name: "Old Group",
        ownerId: UUID(),
        inviteCode: "XYZ789",
        inviteExpiresAt: Date().addingTimeInterval(-3600)
    )

    // MARK: - Household Members

    static let ownerMember = HouseholdMember(
        householdId: householdId,
        userId: ownerId,
        displayName: "Alex Johnson",
        role: .owner
    )

    static let regularMember = HouseholdMember(
        householdId: householdId,
        userId: UUID(),
        displayName: "Sam Johnson",
        role: .member
    )

    // MARK: - Loci

    static let coffeShopNote = Locus(
        latitude: 41.8827,
        longitude: -87.6233,
        locationName: "Intelligentsia Coffee, Millennium Park",
        audioFileURL: "audio/coffee-shop.m4a",
        transcription: "This place has the best pour-over in the city. Ask for the Ethiopian single origin.",
        category: .food
    )

    static let parkingReminder = Locus(
        latitude: 41.8796,
        longitude: -87.6237,
        locationName: "Millennium Park Garage",
        audioFileURL: "audio/parking.m4a",
        transcription: "Parked on level 3, section B, near the elevator. Rate is $15 for the first 3 hours.",
        category: .parking
    )

    static let hikingTrail = Locus(
        latitude: 41.9484,
        longitude: -87.6553,
        locationName: "North Pond Nature Sanctuary",
        audioFileURL: "audio/hiking.m4a",
        transcription: "Great trail loop, about 45 minutes. Watch for the blue heron near the north end.",
        category: .outdoor
    )

    static let doctorOffice = Locus(
        latitude: 41.8953,
        longitude: -87.6189,
        locationName: "Northwestern Medical, Suite 420",
        audioFileURL: "audio/doctor.m4a",
        transcription: "Dr. Rivera is on the 4th floor. Bring insurance card and the referral from Dr. Chen.",
        category: .health
    )

    static let shoppingTip = Locus(
        latitude: 41.8882,
        longitude: -87.6243,
        locationName: "Trader Joe's, State Street",
        audioFileURL: "audio/shopping.m4a",
        transcription: "They restock the frozen section on Tuesday mornings. Get the cauliflower gnocchi before it sells out.",
        category: .shopping
    )

    static let homeNote = Locus(
        latitude: 41.9100,
        longitude: -87.6345,
        locationName: "Home",
        audioFileURL: "audio/home.m4a",
        transcription: "Remember to check the basement sump pump before the next big rain.",
        category: .home,
        isShared: true,
        createdByName: "Sam Johnson",
        householdId: householdId
    )

    static let travelNote = Locus(
        latitude: 41.9742,
        longitude: -87.9073,
        locationName: "O'Hare Terminal 3",
        audioFileURL: "audio/travel.m4a",
        transcription: "TSA PreCheck line is faster from the north entrance. Grab food before security, options are limited inside.",
        category: .travel
    )

    static let warningNote = Locus(
        latitude: 41.8670,
        longitude: -87.6168,
        locationName: "Cermak Rd & Michigan Ave",
        audioFileURL: "audio/warning.m4a",
        transcription: "Huge pothole on the right lane heading south. Avoid until the city fixes it.",
        category: .warning
    )

    static let generalNote = Locus(
        latitude: 41.8819,
        longitude: -87.6278,
        locationName: "Art Institute of Chicago",
        audioFileURL: "audio/general.m4a",
        transcription: "Free admission on Thursday evenings after 5pm for Illinois residents.",
        category: .general
    )

    static let tipNote = Locus(
        latitude: 41.8826,
        longitude: -87.6226,
        locationName: "Cloud Gate",
        audioFileURL: "audio/tip.m4a",
        transcription: "Best photos at sunrise before the crowds arrive. Weekdays are much less packed.",
        category: .tip
    )

    static let archivedNote = Locus(
        latitude: 41.8500,
        longitude: -87.6500,
        locationName: "Old Spot",
        audioFileURL: "audio/archived.m4a",
        transcription: "This place closed down last month.",
        category: .general,
        isArchived: true
    )

    static let syncedNote = Locus(
        latitude: 41.8900,
        longitude: -87.6300,
        locationName: "Synced Location",
        audioFileURL: "audio/synced.m4a",
        transcription: "This note has been synced to the cloud.",
        category: .general,
        syncStatus: .synced
    )

    /// All sample loci for populating previews
    static let allLoci: [Locus] = [
        coffeShopNote, parkingReminder, hikingTrail, doctorOffice,
        shoppingTip, homeNote, travelNote, warningNote,
        generalNote, tipNote, archivedNote, syncedNote,
    ]

    // MARK: - Preview Container

    @MainActor
    static var previewContainer: ModelContainer {
        do {
            let container = try ModelContainerConfiguration.preview()
            let context = container.mainContext

            // Insert user profiles
            context.insert(currentUser)
            context.insert(familyUser)
            context.insert(freeUser)

            // Insert household and members
            context.insert(sampleHousehold)
            context.insert(expiredHousehold)
            context.insert(ownerMember)
            context.insert(regularMember)

            // Insert all loci
            for locus in allLoci {
                context.insert(locus)
            }

            return container
        } catch {
            fatalError("Failed to create preview container: \(error.localizedDescription)")
        }
    }
}
