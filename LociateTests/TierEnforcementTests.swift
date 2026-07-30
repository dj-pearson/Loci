import SwiftData
import XCTest

@testable import Lociate

/// US-205: tier enforcement is the revenue boundary — a mistake here either gives
/// away paid features or blocks a paying customer. It had no coverage at all.
final class TierEnforcementTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: ModelContainerConfiguration.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    private func insertLoci(count: Int, isArchived: Bool = false, isShared: Bool = false) {
        for index in 0..<count {
            context.insert(
                Locus(
                    latitude: 40.0 + Double(index) / 1000,
                    longitude: -111.0 + Double(index) / 1000,
                    audioFileURL: "/tmp/test-\(UUID().uuidString).m4a",
                    transcription: "note \(index)",
                    isShared: isShared,
                    isArchived: isArchived
                )
            )
        }
        try? context.save()
    }

    // MARK: - Free tier locus cap

    func testFreeTierAllowsUpToTheCap() {
        insertLoci(count: AppConstants.maxFreeLocis - 1)
        XCTAssertTrue(TierEnforcement.canCreateLocus(tier: .free, modelContext: context))
    }

    func testFreeTierBlocksAtTheCap() {
        insertLoci(count: AppConstants.maxFreeLocis)
        XCTAssertFalse(TierEnforcement.canCreateLocus(tier: .free, modelContext: context))
    }

    func testPaidTiersAreNeverCapped() {
        insertLoci(count: AppConstants.maxFreeLocis + 50)
        XCTAssertTrue(TierEnforcement.canCreateLocus(tier: .premium, modelContext: context))
        XCTAssertTrue(TierEnforcement.canCreateLocus(tier: .family, modelContext: context))
    }

    func testArchivedLociDoNotCountAgainstTheCap() {
        // Matches the server-side trigger in 008_tier_enforcement.sql. If the two
        // disagree, a user is blocked locally but allowed remotely, or vice versa.
        insertLoci(count: AppConstants.maxFreeLocis, isArchived: true)
        XCTAssertTrue(TierEnforcement.canCreateLocus(tier: .free, modelContext: context))
    }

    func testSharedLociDoNotCountAgainstTheCap() {
        // The cap is on *personal* loci; notes shared into the household by other
        // members must not consume the owner's allowance.
        insertLoci(count: AppConstants.maxFreeLocis, isShared: true)
        XCTAssertTrue(TierEnforcement.canCreateLocus(tier: .free, modelContext: context))
    }

    func testPersonalLociCountIgnoresArchivedAndShared() {
        insertLoci(count: 3)
        insertLoci(count: 4, isArchived: true)
        insertLoci(count: 5, isShared: true)
        XCTAssertEqual(TierEnforcement.personalLociCount(in: context), 3)
    }

    // MARK: - Feature gates, tier by tier

    func testFreeTierGatesEveryPremiumFeature() {
        XCTAssertFalse(TierEnforcement.canUseAI(tier: .free))
        XCTAssertFalse(TierEnforcement.canSync(tier: .free))
        XCTAssertFalse(TierEnforcement.canUseWidget(tier: .free))
        XCTAssertFalse(TierEnforcement.canSearch(tier: .free))
        XCTAssertFalse(TierEnforcement.canShareWithFamily(tier: .free))
    }

    func testPremiumUnlocksEverythingExceptFamilySharing() {
        XCTAssertTrue(TierEnforcement.canUseAI(tier: .premium))
        XCTAssertTrue(TierEnforcement.canSync(tier: .premium))
        XCTAssertTrue(TierEnforcement.canUseWidget(tier: .premium))
        XCTAssertTrue(TierEnforcement.canSearch(tier: .premium))
        // The Family tier's only differentiator — if this ever returns true,
        // the Family plan has nothing left to sell.
        XCTAssertFalse(TierEnforcement.canShareWithFamily(tier: .premium))
    }

    func testFamilyUnlocksEverything() {
        XCTAssertTrue(TierEnforcement.canUseAI(tier: .family))
        XCTAssertTrue(TierEnforcement.canSync(tier: .family))
        XCTAssertTrue(TierEnforcement.canUseWidget(tier: .family))
        XCTAssertTrue(TierEnforcement.canSearch(tier: .family))
        XCTAssertTrue(TierEnforcement.canShareWithFamily(tier: .family))
    }

    func testTierLimitsMatchThePublishedPricingTable() {
        // CLAUDE.md documents the tier table; these numbers are what the paywall
        // copy promises.
        XCTAssertEqual(SubscriptionTier.free.limits.maxLoci, 10)
        XCTAssertEqual(SubscriptionTier.premium.limits.maxLoci, .max)
        XCTAssertEqual(SubscriptionTier.family.limits.maxLoci, .max)
    }

    // MARK: - blockedFeature mapping

    func testBlockedFeatureReportsTheRightReasonForFreeUsers() {
        XCTAssertEqual(
            TierEnforcement.blockedFeature(for: .aiCategorization, tier: .free),
            .aiCategorization
        )
        XCTAssertEqual(TierEnforcement.blockedFeature(for: .cloudSync, tier: .free), .cloudSync)
        XCTAssertEqual(TierEnforcement.blockedFeature(for: .widget, tier: .free), .widget)
        XCTAssertEqual(TierEnforcement.blockedFeature(for: .search, tier: .free), .search)
        XCTAssertEqual(
            TierEnforcement.blockedFeature(for: .familySharing, tier: .free),
            .familySharing
        )
    }

    func testBlockedFeatureReturnsNilWhenTheTierAllowsIt() {
        XCTAssertNil(TierEnforcement.blockedFeature(for: .aiCategorization, tier: .premium))
        XCTAssertNil(TierEnforcement.blockedFeature(for: .familySharing, tier: .family))
    }

    func testUnlimitedLociIsOnlyBlockedOnceTheCapIsReached() {
        insertLoci(count: AppConstants.maxFreeLocis - 1)
        XCTAssertNil(
            TierEnforcement.blockedFeature(
                for: .unlimitedLoci, tier: .free, modelContext: context
            )
        )

        insertLoci(count: 1)
        XCTAssertEqual(
            TierEnforcement.blockedFeature(
                for: .unlimitedLoci, tier: .free, modelContext: context
            ),
            .lociLimit
        )
    }

    func testUnlimitedLociWithoutAContextCannotBlock() {
        // The overload takes an optional context; passing none must not
        // accidentally report a limit the caller cannot have checked.
        XCTAssertNil(TierEnforcement.blockedFeature(for: .unlimitedLoci, tier: .free))
    }
}
