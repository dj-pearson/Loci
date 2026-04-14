import SwiftUI

/// Premium empty state (US-171).
///
/// Hero SF Symbol on a gradient halo background, headline, supporting copy,
/// and a gradient CTA button. Respects Reduce Motion — the halo animation
/// collapses into a static glow.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let subtitle: String
    var buttonTitle: String?
    var onButtonTap: (() -> Void)?

    @State private var haloPulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: DesignSystem.Space.md) {
            // Hero icon on a gradient halo.
            ZStack {
                Circle()
                    .fill(DesignSystem.Gradients.primaryHalo)
                    .frame(width: 220, height: 220)
                    .scaleEffect(reduceMotion ? 1.0 : (haloPulse ? 1.06 : 0.94))
                    .opacity(reduceMotion ? 0.6 : (haloPulse ? 0.4 : 0.8))
                    .animation(
                        reduceMotion
                            ? nil
                            : DesignSystem.Motion.gentle.repeatForever(autoreverses: true),
                        value: haloPulse
                    )
                    .allowsHitTesting(false)

                ZStack {
                    Circle()
                        .fill(DesignSystem.Gradients.primary)
                        .frame(width: 96, height: 96)
                        .elevation(.level3)

                    Image(systemName: systemImage)
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .onAppear { haloPulse = true }

            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignSystem.Space.xl)

            if let buttonTitle, let onButtonTap {
                Button(action: onButtonTap) {
                    Text(buttonTitle)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(DesignSystem.Gradients.primary, in: Capsule())
                        .foregroundStyle(.white)
                        .elevation(.level2)
                }
                .buttonStyle(.plain)
                .padding(.top, DesignSystem.Space.xs)
            }
        }
        .padding(DesignSystem.Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preset Factories

extension EmptyStateView {
    static func map(onRecord: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            systemImage: "mappin.and.ellipse",
            title: String(localized: "Drop Your First Locus"),
            subtitle: String(localized: "Record a voice note to pin it to your current location."),
            buttonTitle: String(localized: "Record Now"),
            onButtonTap: onRecord
        )
    }

    static func list(onRecord: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            systemImage: "list.bullet.rectangle",
            title: String(localized: "No Loci Yet"),
            subtitle: String(localized: "Your voice notes will appear here once you start recording."),
            buttonTitle: String(localized: "Record a Voice Note"),
            onButtonTap: onRecord
        )
    }

    static func search() -> EmptyStateView {
        EmptyStateView(
            systemImage: "magnifyingglass",
            title: String(localized: "No Results Found"),
            subtitle: String(localized: "Try broadening your search or using different keywords.")
        )
    }
}

#Preview("Map Empty State") {
    EmptyStateView.map { }
}

#Preview("List Empty State") {
    EmptyStateView.list { }
}

#Preview("Search Empty State") {
    EmptyStateView.search()
}
