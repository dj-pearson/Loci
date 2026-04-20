import SwiftData
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var householdMembers: [HouseholdMember]

    @Bindable var viewModel: SettingsViewModel
    var householdViewModel: HouseholdViewModel
    var biometricService: BiometricLockService?

    @State private var showSignOutConfirmation = false
    @State private var showCreateHousehold = false
    @State private var showJoinHousehold = false
    @State private var showDeleteAccountConfirmation = false
    @State private var isExportingData = false
    @State private var exportURL: URL?
    @State private var showExportShare = false
    @State private var isDeletingAccount = false

    var body: some View {
        Form {
            accountHeaderCard
            accountSection
            privacySection
            notificationsSection
            dataSection
            familySection
            aboutSection
        }
        .navigationTitle(String(localized: "Settings"))
    }

    // MARK: - Account Header Card (US-173)

    /// Premium account header shown at the top of Settings. Gradient
    /// avatar tile, display name, tier badge, and an upgrade CTA for
    /// free-tier users.
    ///
    /// US-179: The entire card is now a NavigationLink into AccountView so
    /// tapping it feels natural and opens the full account hub.
    private var accountHeaderCard: some View {
        Section {
            NavigationLink {
                AccountView(viewModel: viewModel)
            } label: {
                HStack(spacing: DesignSystem.Space.md) {
                    // Gradient avatar tile with initial.
                    ZStack {
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                            .fill(DesignSystem.Gradients.primary)
                            .frame(width: 56, height: 56)
                            .elevation(.level2)
                        Text(accountInitial)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(accountDisplayName)
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)

                        // Tier badge with gradient background.
                        HStack(spacing: 4) {
                            Image(systemName: tierBadgeIcon)
                                .font(.caption2.weight(.bold))
                            Text(viewModel.subscriptionTier.displayName)
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(tierBadgeGradient, in: Capsule())
                    }

                    Spacer()
                }
                .padding(.vertical, DesignSystem.Space.xxs)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "\(accountDisplayName), \(viewModel.subscriptionTier.displayName) tier"))
                .accessibilityHint(String(localized: "Opens account settings"))
            }
            .disabled(!viewModel.isSignedIn)
        }
    }

    private var accountDisplayName: String {
        viewModel.currentUser?.displayName
            ?? String(localized: "Guest")
    }

    private var accountInitial: String {
        let name = accountDisplayName
        return String(name.prefix(1)).uppercased()
    }

    private var tierBadgeIcon: String {
        switch viewModel.subscriptionTier {
        case .free: "sparkles"
        case .premium: "crown.fill"
        case .family: "person.3.fill"
        }
    }

    private var tierBadgeGradient: LinearGradient {
        switch viewModel.subscriptionTier {
        case .free: DesignSystem.Gradients.primary
        case .premium: DesignSystem.Gradients.premium
        case .family: DesignSystem.Gradients.family
        }
    }

    // MARK: - Privacy Section

    private var privacySection: some View {
        Section(String(localized: "Privacy")) {
            if let biometricService, biometricService.canUseBiometrics() {
                Toggle(isOn: Binding(
                    get: { biometricService.isBiometricLockEnabled },
                    set: { newValue in
                        // US-184: Refuse to enable biometric lock on a
                        // compromised device — the OS-level biometric API
                        // cannot be trusted under jailbreak.
                        if IntegrityCheckService.shared.shouldBlockSensitiveOperations {
                            return
                        }
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
                .disabled(IntegrityCheckService.shared.shouldBlockSensitiveOperations)
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

            // US-149: Security audit log for transparency
            NavigationLink {
                SecurityAuditLogView()
            } label: {
                Label(
                    String(localized: "Security Log"),
                    systemImage: "shield.checkered"
                )
            }

            // Data export — US-184: refuse on compromised devices.
            Button {
                Task { await exportData() }
            } label: {
                if isExportingData {
                    HStack {
                        Label(String(localized: "Exporting Data..."), systemImage: "square.and.arrow.up")
                        Spacer()
                        ProgressView()
                    }
                } else {
                    Label(String(localized: "Export My Data"), systemImage: "square.and.arrow.up")
                }
            }
            .disabled(isExportingData || IntegrityCheckService.shared.shouldBlockSensitiveOperations)
            .sheet(isPresented: $showExportShare) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }

            // Account deletion — US-184: refuse on compromised devices.
            if viewModel.isSignedIn {
                Button(role: .destructive) {
                    showDeleteAccountConfirmation = true
                } label: {
                    if isDeletingAccount {
                        HStack {
                            Label(String(localized: "Deleting Account..."), systemImage: "trash")
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        Label(String(localized: "Delete Account"), systemImage: "trash")
                    }
                }
                .disabled(isDeletingAccount || IntegrityCheckService.shared.shouldBlockSensitiveOperations)
                .alert(
                    String(localized: "Delete Account"),
                    isPresented: $showDeleteAccountConfirmation
                ) {
                    Button(String(localized: "Delete Everything"), role: .destructive) {
                        Task { await deleteAccount() }
                    }
                    Button(String(localized: "Cancel"), role: .cancel) {}
                } message: {
                    Text(String(localized: "This will permanently delete your account, all voice notes, audio recordings, and household memberships. This action cannot be undone."))
                }
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

                // US-176: Real Manage Subscription destination (was a Text placeholder).
                NavigationLink {
                    ManageSubscriptionView()
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
                // US-176: Real Sign In destination (was a Text placeholder).
                NavigationLink {
                    SignInView()
                } label: {
                    Label(String(localized: "Sign In"), systemImage: "person.badge.plus")
                }
            }
        }
    }

    // MARK: - Notifications Section

    @Environment(NotificationService.self) private var notificationService

    private var notificationsSection: some View {
        Section(String(localized: "Notifications")) {
            if notificationService.authorizationStatus == .denied {
                notificationDeniedBanner
            }

            Toggle(isOn: Binding(
                get: { viewModel.notificationsEnabled },
                set: { viewModel.notificationsEnabled = $0 }
            )) {
                Label(String(localized: "Proximity Alerts"), systemImage: "bell")
            }
            .disabled(notificationService.authorizationStatus == .denied)

            if viewModel.notificationsEnabled && notificationService.authorizationStatus != .denied {
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

                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: notificationService.isQuietHoursActive ? "moon.fill" : "moon")
                        .foregroundStyle(notificationService.isQuietHoursActive ? Theme.warning : Theme.textSecondary)
                        .font(.caption)
                    Text(notificationService.isQuietHoursActive
                         ? String(localized: "Quiet hours are active")
                         : String(localized: "Quiet hours are inactive"))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private var notificationDeniedBanner: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label {
                Text(String(localized: "Notifications Disabled"))
                    .font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: "bell.slash.fill")
                    .foregroundStyle(Theme.warning)
            }

            Text(String(localized: "Lociate uses notifications to alert you when you return to a saved location. Enable notifications to receive proximity alerts."))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text(String(localized: "Open Settings"))
                    .font(.caption.weight(.medium))
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    // MARK: - Data Section

    @State private var showDeleteArchivedConfirmation = false
    @State private var deletedArchivedCount = 0
    @State private var showDeletedArchivedAlert = false

    private var dataSection: some View {
        Section(String(localized: "Data")) {
            if viewModel.isStorageLow {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.warning)
                    Text(String(localized: "Device storage is running low. Consider deleting archived audio to free space."))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.vertical, Theme.Spacing.xs)
            }

            if let lastSync = viewModel.lastSyncTimestamp {
                HStack {
                    Label(String(localized: "Last Sync"), systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    Text(lastSync, style: .relative)
                        .foregroundStyle(.secondary)
                }
            }

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

            Button(role: .destructive) {
                showDeleteArchivedConfirmation = true
            } label: {
                Label(String(localized: "Delete Archived Audio"), systemImage: "archivebox.fill")
            }
            .confirmationDialog(
                String(localized: "Delete Archived Audio"),
                isPresented: $showDeleteArchivedConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Delete All Archived Audio"), role: .destructive) {
                    deletedArchivedCount = viewModel.deleteArchivedAudio(modelContext: modelContext)
                    showDeletedArchivedAlert = true
                }
            } message: {
                Text(String(localized: "This will permanently delete audio files for all archived loci. The text transcriptions will be preserved."))
            }
            .alert(
                String(localized: "Archived Audio Deleted"),
                isPresented: $showDeletedArchivedAlert
            ) {
                Button(String(localized: "OK")) {}
            } message: {
                Text(String(localized: "\(deletedArchivedCount) audio file(s) deleted."))
            }
            // US-176: Removed duplicate "Export Data" NavigationLink stub — the
            // working "Export My Data" button already lives in the Privacy section.
        }
    }

    // MARK: - Family Section

    private var familySection: some View {
        Section(String(localized: "Family")) {
            if IntegrityCheckService.shared.shouldBlockSensitiveOperations {
                // US-184: Household creation/join is disabled on compromised
                // devices — invite codes and member lists are sensitive.
                Label(
                    String(localized: "Family sharing disabled on this device."),
                    systemImage: "exclamationmark.shield"
                )
                .font(.caption)
                .foregroundStyle(Theme.warning)
            } else if householdMembers.isEmpty {
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

            Link(destination: URL(string: "https://lociate.app/privacy")!) {
                Label(String(localized: "Privacy Policy"), systemImage: "hand.raised")
            }

            Link(destination: URL(string: "https://lociate.app/terms")!) {
                Label(String(localized: "Terms of Service"), systemImage: "doc.text")
            }

            Link(destination: URL(string: "https://lociate.app/support")!) {
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

    // MARK: - Data Export

    private func exportData() async {
        isExportingData = true
        defer { isExportingData = false }

        let descriptor = FetchDescriptor<Locus>()
        guard let loci = try? modelContext.fetch(descriptor) else { return }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("loci-export-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Export loci as JSON
        let lociData = loci.map { locus -> [String: Any] in
            [
                "id": locus.id.uuidString,
                "latitude": locus.latitude,
                "longitude": locus.longitude,
                "locationName": locus.locationName ?? "",
                "transcription": locus.transcription,
                "category": locus.categoryRawValue,
                "isShared": locus.isShared,
                "isArchived": locus.isArchived,
                "createdAt": locus.createdAt.ISO8601Format(),
                "updatedAt": locus.updatedAt.ISO8601Format(),
            ]
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: lociData, options: .prettyPrinted) {
            try? jsonData.write(to: tempDir.appendingPathComponent("loci.json"))
        }

        // Copy audio files
        let audioDir = tempDir.appendingPathComponent("audio")
        try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

        for locus in loci {
            let sourceURL = documentsURL.appendingPathComponent(locus.audioFileURL)
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                try? FileManager.default.copyItem(
                    at: sourceURL,
                    to: audioDir.appendingPathComponent(locus.audioFileURL)
                )
            }
        }

        // Export user profile
        let profileDescriptor = FetchDescriptor<UserProfile>()
        if let profile = try? modelContext.fetch(profileDescriptor).first {
            let profileData: [String: Any] = [
                "displayName": profile.displayName,
                "subscriptionTier": profile.subscriptionTier.rawValue,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: profileData, options: .prettyPrinted) {
                try? data.write(to: tempDir.appendingPathComponent("profile.json"))
            }
        }

        // Create ZIP (using a simple directory share since ZIPFoundation isn't available)
        exportURL = tempDir
        showExportShare = true
    }

    // MARK: - Account Deletion

    private func deleteAccount() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }

        // Call server-side cascade deletion
        do {
            let supabase = SupabaseClientProvider.shared
            try await supabase.functions.invoke("account/delete", options: .init(method: "POST"))
        } catch {
            // Continue with local cleanup even if server fails
        }

        // Clear local SwiftData
        let lociDescriptor = FetchDescriptor<Locus>()
        if let loci = try? modelContext.fetch(lociDescriptor) {
            for locus in loci {
                modelContext.delete(locus)
            }
        }

        let profileDescriptor = FetchDescriptor<UserProfile>()
        if let profiles = try? modelContext.fetch(profileDescriptor) {
            for profile in profiles {
                modelContext.delete(profile)
            }
        }

        let householdDescriptor = FetchDescriptor<Household>()
        if let households = try? modelContext.fetch(householdDescriptor) {
            for household in households {
                modelContext.delete(household)
            }
        }

        let memberDescriptor = FetchDescriptor<HouseholdMember>()
        if let members = try? modelContext.fetch(memberDescriptor) {
            for member in members {
                modelContext.delete(member)
            }
        }

        try? modelContext.save()

        // Clear local audio files
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        if let contents = try? FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil) {
            for file in contents where file.pathExtension == AppConstants.Audio.fileExtension {
                try? FileManager.default.removeItem(at: file)
            }
        }

        // Sign out
        viewModel.signOut()
    }
}

// MARK: - ShareSheet

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
