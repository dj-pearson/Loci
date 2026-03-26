import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var householdMembers: [HouseholdMember]

    @Bindable var viewModel: SettingsViewModel
    var householdViewModel: HouseholdViewModel
    var biometricService: BiometricLockService?

    @State private var showSignOutConfirmation = false
    @State private var showCreateHousehold = false
    @State private var showJoinHousehold = false

    var body: some View {
        Form {
            accountSection
            privacySection
            notificationsSection
            dataSection
            familySection
            aboutSection
        }
        .navigationTitle(String(localized: "Settings"))
    }

    // MARK: - Privacy Section

    private var privacySection: some View {
        Section(String(localized: "Privacy")) {
            if let biometricService, biometricService.canUseBiometrics() {
                Toggle(isOn: Binding(
                    get: { biometricService.isBiometricLockEnabled },
                    set: { newValue in
                        if newValue {
                            Task {
                                do {
                                    let authenticated = try await biometricService.authenticate()
                                    if authenticated {
                                        biometricService.isBiometricLockEnabled = true
                                    }
                                } catch {
                                    // Authentication failed — don't enable
                                }
                            }
                        } else {
                            biometricService.isBiometricLockEnabled = false
                        }
                    }
                )) {
                    Label(
                        String(localized: "Require \(biometricService.biometricType.displayName)"),
                        systemImage: biometricService.biometricType.systemImageName
                    )
                }
            } else {
                Label(
                    String(localized: "Biometric Lock"),
                    systemImage: "lock"
                )
                .foregroundStyle(.secondary)

                Text(String(localized: "Biometric authentication is not available on this device."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        Section(String(localized: "Account")) {
            if viewModel.isSignedIn {
                if let user = viewModel.currentUser {
                    HStack {
                        Label(user.displayName, systemImage: "person.circle")
                        Spacer()
                        Text(viewModel.subscriptionTier.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                NavigationLink {
                    Text(String(localized: "Manage Subscription"))
                } label: {
                    Label(String(localized: "Manage Subscription"), systemImage: "creditcard")
                }

                Button(role: .destructive) {
                    showSignOutConfirmation = true
                } label: {
                    Label(String(localized: "Sign Out"), systemImage: "rectangle.portrait.and.arrow.right")
                }
                .confirmationDialog(
                    String(localized: "Sign Out"),
                    isPresented: $showSignOutConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(String(localized: "Sign Out"), role: .destructive) {
                        viewModel.signOut()
                    }
                } message: {
                    Text(String(localized: "Your local data will be kept, but cloud sync will stop."))
                }
            } else {
                NavigationLink {
                    Text(String(localized: "Sign In"))
                } label: {
                    Label(String(localized: "Sign In"), systemImage: "person.badge.plus")
                }
            }
        }
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        Section(String(localized: "Notifications")) {
            Toggle(isOn: Binding(
                get: { viewModel.notificationsEnabled },
                set: { viewModel.notificationsEnabled = $0 }
            )) {
                Label(String(localized: "Proximity Alerts"), systemImage: "bell")
            }

            if viewModel.notificationsEnabled {
                DatePicker(
                    String(localized: "Quiet Hours Start"),
                    selection: Binding(
                        get: { viewModel.quietHoursStart },
                        set: { viewModel.quietHoursStart = $0 }
                    ),
                    displayedComponents: .hourAndMinute
                )

                DatePicker(
                    String(localized: "Quiet Hours End"),
                    selection: Binding(
                        get: { viewModel.quietHoursEnd },
                        set: { viewModel.quietHoursEnd = $0 }
                    ),
                    displayedComponents: .hourAndMinute
                )
            }
        }
    }

    // MARK: - Data Section

    private var dataSection: some View {
        Section(String(localized: "Data")) {
            HStack {
                Label(String(localized: "Storage Used"), systemImage: "internaldrive")
                Spacer()
                Text(formattedStorageSize(viewModel.storageUsed))
                    .foregroundStyle(.secondary)
            }

            Button {
                viewModel.clearCache(modelContext: modelContext)
            } label: {
                Label(String(localized: "Clear Cache"), systemImage: "trash")
            }

            NavigationLink {
                Text(String(localized: "Export Data"))
            } label: {
                Label(String(localized: "Export Data"), systemImage: "square.and.arrow.up")
            }
        }
    }

    // MARK: - Family Section

    private var familySection: some View {
        Section(String(localized: "Family")) {
            if householdMembers.isEmpty {
                Button {
                    showCreateHousehold = true
                } label: {
                    Label(String(localized: "Create Family"), systemImage: "person.2.badge.plus")
                }
                .sheet(isPresented: $showCreateHousehold) {
                    CreateHouseholdView(viewModel: householdViewModel)
                }

                Button {
                    showJoinHousehold = true
                } label: {
                    Label(String(localized: "Join Family"), systemImage: "person.badge.key")
                }
                .sheet(isPresented: $showJoinHousehold) {
                    JoinHouseholdView(viewModel: householdViewModel)
                }
            } else {
                HStack {
                    Label(String(localized: "Household"), systemImage: "house")
                    Spacer()
                    Text("\(householdMembers.count) members")
                        .foregroundStyle(.secondary)
                }

                NavigationLink {
                    HouseholdMembersView(viewModel: householdViewModel)
                } label: {
                    Label(String(localized: "Manage Members"), systemImage: "person.2")
                }
            }
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section(String(localized: "About")) {
            HStack {
                Label(String(localized: "Version"), systemImage: "info.circle")
                Spacer()
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }

            Link(destination: URL(string: "https://useloci.com/privacy")!) {
                Label(String(localized: "Privacy Policy"), systemImage: "hand.raised")
            }

            Link(destination: URL(string: "https://useloci.com/terms")!) {
                Label(String(localized: "Terms of Service"), systemImage: "doc.text")
            }

            Link(destination: URL(string: "https://useloci.com/support")!) {
                Label(String(localized: "Support & Feedback"), systemImage: "envelope")
            }

            HStack {
                Spacer()
                Text(String(localized: "Made by Pearson Media LLC"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func formattedStorageSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - SubscriptionTier Display Name

private extension SubscriptionTier {
    var displayName: String {
        switch self {
        case .free: String(localized: "Free")
        case .premium: String(localized: "Premium")
        case .family: String(localized: "Family")
        }
    }
}
