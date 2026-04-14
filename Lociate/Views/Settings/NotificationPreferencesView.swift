import SwiftUI

struct NotificationPreferencesView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { viewModel.notificationsEnabled },
                    set: { viewModel.notificationsEnabled = $0 }
                )) {
                    Label(String(localized: "Proximity Notifications"), systemImage: "bell.badge")
                }
            } footer: {
                Text(String(localized: "When enabled, Loci notifies you when you return to a place where you left a voice note."))
            }

            if viewModel.notificationsEnabled {
                Section(String(localized: "Quiet Hours")) {
                    DatePicker(
                        String(localized: "Start"),
                        selection: Binding(
                            get: { viewModel.quietHoursStart },
                            set: { viewModel.quietHoursStart = $0 }
                        ),
                        displayedComponents: .hourAndMinute
                    )

                    DatePicker(
                        String(localized: "End"),
                        selection: Binding(
                            get: { viewModel.quietHoursEnd },
                            set: { viewModel.quietHoursEnd = $0 }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                } footer: {
                    Text(String(localized: "Proximity notifications will be suppressed during quiet hours."))
                }

                Section(String(localized: "Preview")) {
                    sampleNotification
                }
            }
        }
        .navigationTitle(String(localized: "Notifications"))
    }

    // MARK: - Sample Notification Preview

    private var sampleNotification: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(Theme.primary)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Loci")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(String(localized: "now"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(String(localized: "You left a note here"))
                    .font(.subheadline.weight(.semibold))

                Text(String(localized: "\"Great coffee spot, try the oat milk latte\""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
