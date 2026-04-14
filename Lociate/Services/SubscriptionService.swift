import Foundation
import RevenueCat
import WidgetKit

@Observable
final class SubscriptionService: NSObject, PurchasesDelegate {
    // MARK: - Published State

    private(set) var currentTier: SubscriptionTier = .free
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    // MARK: - Initialization

    override init() {
        super.init()
        Purchases.shared.delegate = self
        Task {
            await checkEntitlements()
        }
    }

    // MARK: - Offerings

    /// Fetches available subscription packages from RevenueCat.
    func fetchOfferings() async throws -> [Package] {
        isLoading = true
        defer { isLoading = false }

        let offerings = try await Purchases.shared.offerings()
        guard let current = offerings.current else {
            return []
        }
        return current.availablePackages
    }

    // MARK: - Purchase

    /// Completes a purchase for the given package.
    /// Returns `true` if the purchase succeeded and entitlements were updated.
    @discardableResult
    func purchase(_ package: Package) async throws -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let result = try await Purchases.shared.purchase(package: package)

        if result.userCancelled {
            return false
        }

        updateTier(from: result.customerInfo)
        return true
    }

    // MARK: - Restore

    /// Restores previous purchases and updates the subscription tier.
    func restorePurchases() async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let customerInfo = try await Purchases.shared.restorePurchases()
        updateTier(from: customerInfo)
    }

    // MARK: - Entitlements

    /// Checks current entitlements and updates the subscription tier.
    func checkEntitlements() async {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            updateTier(from: customerInfo)
        } catch {
            // Silently fail — tier stays at current value (offline-first)
        }
    }

    // MARK: - Feature Gating

    /// Returns `true` if the given feature requires a subscription upgrade.
    func isPremiumFeature(_ feature: PremiumFeature) -> Bool {
        switch feature {
        case .unlimitedLoci:
            return currentTier == .free
        case .aiCategorization:
            return !currentTier.limits.hasAICategorization
        case .cloudSync:
            return !currentTier.limits.hasCloudSync
        case .widget:
            return !currentTier.limits.hasWidget
        case .search:
            return !currentTier.limits.hasSearch
        case .familySharing:
            return !currentTier.limits.hasFamilySharing
        }
    }

    // MARK: - PurchasesDelegate

    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        updateTier(from: customerInfo)
    }

    // MARK: - Private

    private func updateTier(from customerInfo: CustomerInfo) {
        if customerInfo.entitlements[RevenueCatConfiguration.EntitlementID.family]?.isActive == true {
            currentTier = .family
        } else if customerInfo.entitlements[RevenueCatConfiguration.EntitlementID.premium]?.isActive == true {
            currentTier = .premium
        } else {
            currentTier = .free
        }

        // Persist premium status to App Group for widget access
        let defaults = UserDefaults(suiteName: "group.com.pearsonmedia.loci")
        defaults?.set(currentTier != .free, forKey: "widget_is_premium")
        WidgetCenter.shared.reloadAllTimelines()
    }

    func clearError() {
        errorMessage = nil
    }
}

// MARK: - Premium Features

enum PremiumFeature: String, CaseIterable {
    case unlimitedLoci
    case aiCategorization
    case cloudSync
    case widget
    case search
    case familySharing
}
