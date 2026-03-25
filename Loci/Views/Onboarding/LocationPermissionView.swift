import SwiftUI

struct LocationPermissionView: View {
    let locationService: LocationService
    let onComplete: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            Image(systemName: "location.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(Theme.primary)

            Text(String(localized: "Enable Location"))
                .font(Theme.Typography.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(String(localized: "Loci needs Always Allow location to notify you when you return to a saved location."))
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                bulletPoint(
                    icon: "moon.stars",
                    text: String(localized: "Works in the background — even when the app is closed")
                )
                bulletPoint(
                    icon: "battery.75percent",
                    text: String(localized: "Low battery impact — less than 2% daily usage")
                )
                bulletPoint(
                    icon: "lock.shield",
                    text: String(localized: "Private and on-device — your location never leaves your phone")
                )
            }
            .padding(.horizontal, Theme.Spacing.xl)

            Spacer()

            VStack(spacing: Theme.Spacing.sm) {
                Button(action: requestPermission) {
                    Text(String(localized: "Enable Location"))
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
        .onChange(of: locationService.authorizationStatus) { _, newStatus in
            if newStatus == .authorizedAlways || newStatus == .authorizedWhenInUse {
                onComplete()
            }
        }
    }

    private func requestPermission() {
        locationService.requestAlwaysPermission()
    }

    private func bulletPoint(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Theme.primary)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

#Preview {
    LocationPermissionView(
        locationService: LocationService(),
        onComplete: { },
        onSkip: { }
    )
}
