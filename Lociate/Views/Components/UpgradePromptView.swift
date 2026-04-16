import SwiftUI

struct UpgradePromptView: View {
    let blockedFeature: BlockedFeature
    let onUpgrade: () -> Void
    let onDismiss: () -> Void

    @State private var shouldShow = true

    var body: some View {
        if shouldShow && !isCoolingDown {
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: iconName)
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.primary)

                Text(blockedFeature.title)
                    .font(Theme.Typography.headline)
                    .fontWeight(.bold)

                Text(blockedFeature.message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                Button {
                    onUpgrade()
                } label: {
                    Text(ctaText)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.primary, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
                }

                Button {
                    startCooldown()
                    shouldShow = false
                    onDismiss()
                } label: {
                    Text(String(localized: "Not Now"))
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(Theme.Spacing.lg)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
            .padding(.horizontal, Theme.Spacing.md)
        }
    }

    private var iconName: String {
        switch blockedFeature {
        case .lociLimit: "mappin.slash"
        case .aiCategorization: "brain"
        case .cloudSync: "icloud.slash"
        case .widget: "rectangle.on.rectangle.angled"
        case .search: "magnifyingglass"
        case .familySharing: "person.3"
        }
    }

    private var ctaText: String {
        switch blockedFeature.requiredTier {
        case .family:
            String(localized: "Upgrade to Family")
        default:
            String(localized: "Upgrade to Premium")
        }
    }

    // MARK: - 24-Hour Cooldown

    private var cooldownKey: String {
        "upgrade_prompt_cooldown_\(blockedFeature.rawValue)"
    }

    private var isCoolingDown: Bool {
        guard let lastShown = UserDefaults.standard.object(forKey: cooldownKey) as? Date else {
            return false
        }
        return Date().timeIntervalSince(lastShown) < 24 * 60 * 60
    }

    private func startCooldown() {
        UserDefaults.standard.set(Date(), forKey: cooldownKey)
    }
}
