import Foundation
import SwiftData

@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var authId: UUID?
    var displayName: String
    var subscriptionTierRawValue: String
    var apnsToken: String?

    var subscriptionTier: SubscriptionTier {
        get { SubscriptionTier(rawValue: subscriptionTierRawValue) ?? .free }
        set { subscriptionTierRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        authId: UUID? = nil,
        displayName: String,
        subscriptionTier: SubscriptionTier = .free,
        apnsToken: String? = nil
    ) {
        self.id = id
        self.authId = authId
        self.displayName = displayName
        self.subscriptionTierRawValue = subscriptionTier.rawValue
        self.apnsToken = apnsToken
    }
}

enum SubscriptionTier: String, Codable {
    case free
    case premium
    case family

    var limits: TierLimits {
        switch self {
        case .free:
            TierLimits(
                maxLoci: AppConstants.maxFreeLocis,
                hasCloudSync: false,
                hasAICategorization: false,
                hasWidget: false,
                hasSearch: false,
                hasFamilySharing: false
            )
        case .premium:
            TierLimits(
                maxLoci: .max,
                hasCloudSync: true,
                hasAICategorization: true,
                hasWidget: true,
                hasSearch: true,
                hasFamilySharing: false
            )
        case .family:
            TierLimits(
                maxLoci: .max,
                hasCloudSync: true,
                hasAICategorization: true,
                hasWidget: true,
                hasSearch: true,
                hasFamilySharing: true
            )
        }
    }
}

struct TierLimits {
    let maxLoci: Int
    let hasCloudSync: Bool
    let hasAICategorization: Bool
    let hasWidget: Bool
    let hasSearch: Bool
    let hasFamilySharing: Bool
}
