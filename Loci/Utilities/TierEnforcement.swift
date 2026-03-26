import Foundation
import SwiftData

enum TierEnforcement {

    /// Checks if the user can create a new locus given their subscription tier.
    /// Free users are limited to `AppConstants.maxFreeLocis` non-archived, personal loci.
    static func canCreateLocus(tier: SubscriptionTier, modelContext: ModelContext) -> Bool {
        guard tier == .free else { return true }
        return personalLociCount(in: modelContext) < AppConstants.maxFreeLocis
    }

    /// Checks if AI categorization is available for the given tier.
    static func canUseAI(tier: SubscriptionTier) -> Bool {
        tier.limits.hasAICategorization
    }

    /// Checks if cloud sync is available for the given tier.
    static func canSync(tier: SubscriptionTier) -> Bool {
        tier.limits.hasCloudSync
    }

    /// Checks if the home screen widget is available for the given tier.
    static func canUseWidget(tier: SubscriptionTier) -> Bool {
        tier.limits.hasWidget
    }

    /// Checks if full-text search is available for the given tier.
    static func canSearch(tier: SubscriptionTier) -> Bool {
        tier.limits.hasSearch
    }

    /// Checks if family sharing is available for the given tier.
    static func canShareWithFamily(tier: SubscriptionTier) -> Bool {
        tier.limits.hasFamilySharing
    }

    /// Returns the `BlockedFeature` if a given premium feature is not available,
    /// or `nil` if the feature is accessible.
    static func blockedFeature(for feature: PremiumFeature, tier: SubscriptionTier, modelContext: ModelContext? = nil) -> BlockedFeature? {
        switch feature {
        case .unlimitedLoci:
            if let modelContext, !canCreateLocus(tier: tier, modelContext: modelContext) {
                return .lociLimit
            }
            return nil
        case .aiCategorization:
            return canUseAI(tier: tier) ? nil : .aiCategorization
        case .cloudSync:
            return canSync(tier: tier) ? nil : .cloudSync
        case .widget:
            return canUseWidget(tier: tier) ? nil : .widget
        case .search:
            return canSearch(tier: tier) ? nil : .search
        case .familySharing:
            return canShareWithFamily(tier: tier) ? nil : .familySharing
        }
    }

    /// Counts non-archived, personal (not shared) loci in SwiftData.
    static func personalLociCount(in modelContext: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Locus>(
            predicate: #Predicate<Locus> { locus in
                locus.isArchived == false && locus.isShared == false
            }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }
}

// MARK: - Blocked Feature

/// Describes which feature was blocked, used by upgrade prompts to show context-aware messaging.
enum BlockedFeature: String, Sendable {
    case lociLimit
    case aiCategorization
    case cloudSync
    case widget
    case search
    case familySharing

    var title: String {
        switch self {
        case .lociLimit:
            String(localized: "Loci Limit Reached")
        case .aiCategorization:
            String(localized: "AI Categorization")
        case .cloudSync:
            String(localized: "Cloud Sync")
        case .widget:
            String(localized: "Home Screen Widget")
        case .search:
            String(localized: "Full-Text Search")
        case .familySharing:
            String(localized: "Family Sharing")
        }
    }

    var message: String {
        switch self {
        case .lociLimit:
            String(localized: "You've reached the free limit of \(AppConstants.maxFreeLocis) loci. Upgrade to Premium for unlimited voice notes.")
        case .aiCategorization:
            String(localized: "AI categorization is a Premium feature. Upgrade to automatically organize your loci.")
        case .cloudSync:
            String(localized: "Cloud sync requires a Premium subscription. Upgrade to back up and sync across devices.")
        case .widget:
            String(localized: "The home screen widget is a Premium feature. Upgrade to see nearby loci at a glance.")
        case .search:
            String(localized: "Full-text search requires a Premium subscription. Upgrade to search all your voice notes.")
        case .familySharing:
            String(localized: "Family sharing requires a Family plan. Upgrade to share loci with up to 6 family members.")
        }
    }

    var requiredTier: SubscriptionTier {
        switch self {
        case .familySharing:
            .family
        default:
            .premium
        }
    }
}
