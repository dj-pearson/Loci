import Foundation
import RevenueCat

enum RevenueCatConfiguration {
    // MARK: - API Keys

    static var apiKey: String {
        BuildSecrets.revenueCatAPIKey
    }

    // MARK: - Offering IDs

    enum OfferingID {
        static let premiumMonthly = "premium_monthly"
        static let premiumYearly = "premium_yearly"
        static let familyMonthly = "family_monthly"
        static let familyYearly = "family_yearly"
        static let lifetimeIndividual = "lifetime_individual"
        static let lifetimeFamily = "lifetime_family"
    }

    // MARK: - Entitlement IDs

    enum EntitlementID {
        static let premium = "premium"
        static let family = "family"
    }

    // MARK: - Configure

    /// Call this once during app startup (e.g., in LociateApp.init).
    static func configure() {
        Purchases.logLevel = {
            #if DEBUG
            return .debug
            #else
            return .warn
            #endif
        }()

        Purchases.configure(withAPIKey: apiKey)
    }

    /// Sets the RevenueCat app user ID after authentication.
    static func identify(userId: String) async throws {
        _ = try await Purchases.shared.logIn(userId)
    }

    /// Clears the RevenueCat user on sign-out.
    static func resetUser() async throws {
        _ = try await Purchases.shared.logOut()
    }
}
