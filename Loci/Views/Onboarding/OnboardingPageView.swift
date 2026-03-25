import SwiftUI

struct OnboardingPageView: View {
    let systemImage: String
    let headline: String
    let bodyText: String
    let ctaTitle: String
    let onCTA: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            Image(systemName: systemImage)
                .font(.system(size: 80))
                .foregroundStyle(Theme.primary)
                .padding(.bottom, Theme.Spacing.md)

            Text(headline)
                .font(Theme.Typography.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textPrimary)

            Text(bodyText)
                .font(Theme.Typography.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Theme.Spacing.xl)

            Spacer()

            Button(action: onCTA) {
                Text(ctaTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.primary, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xl)
        }
    }
}

#Preview {
    OnboardingPageView(
        systemImage: "mappin.and.ellipse",
        headline: "Your Spatial Memory",
        bodyText: "Pin voice notes to locations. Your memories live where they happened.",
        ctaTitle: "Next"
    ) { }
}
