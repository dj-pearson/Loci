import SwiftUI

struct NotificationPermissionView: View {
    let notificationService: NotificationService
    let onComplete: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 80))
                .foregroundStyle(Theme.primary)

            Text(String(localized: "Stay in the Loop"))
                .font(Theme.Typography.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            // Long-form user copy. A localization key has to be a single literal, so wrapping this would break key extraction.
            // swiftlint:disable:next line_length
            Text(String(localized: "Lociate sends a notification when you return to a place where you left a voice note — so your memories find you."))
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)

            Spacer()

            VStack(spacing: Theme.Spacing.sm) {
                Button {
                    Task {
                        await notificationService.requestPermission()
                        onComplete()
                    }
                } label: {
                    Text(String(localized: "Enable Notifications"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.primary, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                        .foregroundStyle(.white)
                }

                Button(action: onSkip) {
                    Text(String(localized: "Maybe Later"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xl)
        }
    }
}
