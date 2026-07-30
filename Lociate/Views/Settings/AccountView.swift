import SwiftData
import SwiftUI
import UIKit

/// US-179: Dedicated account management hub. Accessible from the Settings
/// account header card. Lets the signed-in user edit their display name,
/// review their email + subscription, and jump to destructive flows like
/// sign out or account deletion without hunting through Settings sections.
struct AccountView: View {
    @Environment(AuthService.self) private var authService
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var viewModel: SettingsViewModel

    @State private var isEditingName = false
    @State private var draftDisplayName: String = ""
    @State private var currentEmail: String?
    @State private var showSignOutConfirmation = false
    @State private var showDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    @State private var errorMessage: String?

    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        Form {
            profileSection
            subscriptionSection
            securitySection
            dangerSection
        }
        .navigationTitle(String(localized: "Account"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadEmail() }
        .alert(
            String(localized: "Account"),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Profile Section

    private var profileSection: some View {
        Section(String(localized: "Profile")) {
            HStack(spacing: DesignSystem.Space.md) {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                    .fill(DesignSystem.Gradients.primary)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Text(initial)
                            .font(.title.weight(.bold))
                            .foregroundStyle(.white)
                    )
                    .elevation(.level2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.currentUser?.displayName ?? String(localized: "Guest"))
                        .font(.headline)
                    if let currentEmail {
                        Text(currentEmail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Spacer()
            }
            .padding(.vertical, DesignSystem.Space.xxs)

            if isEditingName {
                HStack(spacing: Theme.Spacing.sm) {
                    TextField(String(localized: "Display name"), text: $draftDisplayName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($nameFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { commitDisplayName() }

                    Button(String(localized: "Save")) { commitDisplayName() }
                        .buttonStyle(.borderedProminent)
                        .disabled(draftDisplayName.trimmingCharacters(in: .whitespaces).isEmpty)

                    Button(String(localized: "Cancel"), role: .cancel) {
                        isEditingName = false
                        nameFieldFocused = false
                    }
                }
            } else {
                Button {
                    beginEditingName()
                } label: {
                    Label(String(localized: "Edit Display Name"), systemImage: "pencil")
                }
                .disabled(viewModel.currentUser == nil)
            }
        }
    }

    // MARK: - Subscription Section

    private var subscriptionSection: some View {
        Section(String(localized: "Subscription")) {
            HStack {
                Label(String(localized: "Current Tier"), systemImage: tierIcon)
                Spacer()
                Text(tierDisplayName)
                    .foregroundStyle(.secondary)
            }

            NavigationLink {
                ManageSubscriptionView()
            } label: {
                Label(String(localized: "Manage Subscription"), systemImage: "creditcard")
            }
        }
    }

    // MARK: - Security Section

    private var securitySection: some View {
        Section(String(localized: "Security")) {
            Button {
                Task { await requestPasswordReset() }
            } label: {
                Label(String(localized: "Send Password Reset Email"), systemImage: "key")
            }
            .disabled(currentEmail == nil)
        }
    }

    // MARK: - Danger Section

    private var dangerSection: some View {
        Section {
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
                    Task { await signOut() }
                }
            } message: {
                Text(String(localized: "Your local data will be kept, but cloud sync will stop."))
            }

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
            .confirmationDialog(
                String(localized: "Delete Account"),
                isPresented: $showDeleteAccountConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Delete Everything"), role: .destructive) {
                    Task { await deleteAccount() }
                }
            } message: {
                Text(String(localized: "This permanently deletes your account, voice notes, and audio. This cannot be undone."))
            }
        }
    }

    // MARK: - Helpers

    private var initial: String {
        let name = viewModel.currentUser?.displayName ?? "G"
        return String(name.prefix(1)).uppercased()
    }

    private var tierDisplayName: String {
        switch subscriptionService.currentTier {
        case .free: String(localized: "Free")
        case .premium: String(localized: "Premium")
        case .family: String(localized: "Family")
        }
    }

    private var tierIcon: String {
        switch subscriptionService.currentTier {
        case .free: "sparkles"
        case .premium: "crown.fill"
        case .family: "person.3.fill"
        }
    }

    private func beginEditingName() {
        draftDisplayName = viewModel.currentUser?.displayName ?? ""
        isEditingName = true
        nameFieldFocused = true
    }

    private func commitDisplayName() {
        let sanitized = InputSanitizer.sanitizeDisplayName(draftDisplayName)
        guard !sanitized.isEmpty, let user = viewModel.currentUser else {
            isEditingName = false
            return
        }
        user.displayName = sanitized
        do {
            try modelContext.save()
            isEditingName = false
            nameFieldFocused = false
            HapticManager.saveSuccess()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadEmail() async {
        currentEmail = authService.supabaseEmail
    }

    private func requestPasswordReset() async {
        guard let email = currentEmail else { return }
        try? await authService.resetPassword(email: email)
        HapticManager.saveSuccess()
        errorMessage = String(localized: "If this email is registered, a password reset link has been sent.")
    }

    private func signOut() async {
        try? await authService.signOut()
        viewModel.signOut()
        dismiss()
    }

    private func deleteAccount() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            try await authService.deleteAccount(modelContext: modelContext)
            viewModel.signOut()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
