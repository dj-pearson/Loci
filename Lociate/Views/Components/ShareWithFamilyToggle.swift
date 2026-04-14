import SwiftUI

struct ShareWithFamilyToggle: View {
    @Binding var isShared: Bool
    let householdName: String

    var body: some View {
        Toggle(isOn: $isShared) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(Theme.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Share with Family"))
                        .font(Theme.Typography.body)
                    Text(householdName)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        .accessibilityLabel(String(localized: "Share this voice note with \(householdName)"))
    }
}
