import SwiftUI

/// Premium onboarding page (US-172).
///
/// Hero SF Symbol sitting inside a gradient pill on a primary halo backdrop
/// with a gentle parallax float. Button uses the primary gradient and
/// elevation to feel tactile.
struct OnboardingPageView: View {
    let systemImage: String
    let headline: String
    let bodyText: String
    let ctaTitle: String
    let onCTA: () -> Void

    @State private var heroPulse = false
    @State private var heroFloat = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: DesignSystem.Space.lg) {
            Spacer()

            // Hero with gradient halo + floating icon tile.
            ZStack {
                Circle()
                    .fill(DesignSystem.Gradients.primaryHalo)
                    .frame(width: 320, height: 320)
                    .scaleEffect(reduceMotion ? 1.0 : (heroPulse ? 1.08 : 0.92))
                    .opacity(reduceMotion ? 0.6 : (heroPulse ? 0.4 : 0.8))
                    .animation(
                        reduceMotion
                            ? nil
                            : DesignSystem.Motion.gentle.repeatForever(autoreverses: true),
                        value: heroPulse
                    )

                ZStack {
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.xl, style: .continuous)
                        .fill(DesignSystem.Gradients.primary)
                        .frame(width: 140, height: 140)
                        .elevation(.level4)

                    Image(systemName: systemImage)
                        .font(.system(size: 64, weight: .medium))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                }
                .offset(y: reduceMotion ? 0 : (heroFloat ? -6 : 6))
                .animation(
                    reduceMotion
                        ? nil
                        : DesignSystem.Motion.gentle.repeatForever(autoreverses: true),
                    value: heroFloat
                )
            }
            .padding(.bottom, DesignSystem.Space.sm)
            .onAppear {
                heroPulse = true
                heroFloat = true
            }

            Text(headline)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textPrimary)

            Text(bodyText)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, DesignSystem.Space.xl)

            Spacer()

            Button(action: {
                HapticManager.tabSelection()
                onCTA()
            }, label: {
                Text(ctaTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        DesignSystem.Gradients.primary,
                        in: RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                    )
                    .foregroundStyle(.white)
                    .elevation(.level3)
            })
            .buttonStyle(.plain)
            .padding(.horizontal, DesignSystem.Space.xl)
            .padding(.bottom, DesignSystem.Space.xl)
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
