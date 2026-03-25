import SwiftUI

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let subtitle: String
    var buttonTitle: String?
    var onButtonTap: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 56))
                .foregroundStyle(Theme.textSecondary.opacity(0.5))

            Text(title)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)

            if let buttonTitle, let onButtonTap {
                Button(action: onButtonTap) {
                    Text(buttonTitle)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Theme.primary, in: Capsule())
                        .foregroundStyle(.white)
                }
                .padding(.top, Theme.Spacing.sm)
            }
        }
        .padding(Theme.Spacing.xl)
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
