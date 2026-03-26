import SwiftData
import SwiftUI

struct JoinHouseholdView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var viewModel: HouseholdViewModel

    @State private var inviteCode = ""
    @State private var hasJoined = false

    var body: some View {
        NavigationStack {
            Group {
                if hasJoined {
                    successView
                } else {
                    codeEntryView
                }
            }
            .navigationTitle(hasJoined
                ? String(localized: "Welcome!")
                : String(localized: "Join Family"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !hasJoined {
                        Button(String(localized: "Cancel")) {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if hasJoined {
                        Button(String(localized: "Done")) {
                            dismiss()
                        }
                    }
                }
            }
            .alert(
                String(localized: "Error"),
                isPresented: .init(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.clearError() } }
                ),
                presenting: viewModel.errorMessage
            ) { _ in
                Button(String(localized: "OK")) {}
            } message: { message in
                Text(message)
            }
        }
    }

    // MARK: - Code Entry

    private var codeEntryView: some View {
        Form {
            Section {
                TextField(String(localized: "Invite Code"), text: $inviteCode)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onChange(of: inviteCode) { _, newValue in
                        // Filter to alphanumeric only and limit to 6 characters
                        let filtered = String(newValue.unicodeScalars.filter {
                            CharacterSet.alphanumerics.contains($0)
                        }).uppercased()
                        if filtered.count <= AppConstants.inviteCodeLength {
                            inviteCode = filtered
                        } else {
                            inviteCode = String(filtered.prefix(AppConstants.inviteCodeLength))
                        }
                    }
                    .submitLabel(.join)
                    .onSubmit(joinHousehold)
            } header: {
                Text(String(localized: "Enter the 6-character code from your family member"))
            } footer: {
                Text(String(localized: "Invite codes are case-insensitive and expire after 48 hours."))
            }

            Section {
                Button {
                    joinHousehold()
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Text(String(localized: "Join Family"))
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(inviteCode.count != AppConstants.inviteCodeLength || viewModel.isLoading)
            }
        }
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            Image(systemName: "person.2.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.success)

            Text(String(localized: "You're In!"))
                .font(Theme.Typography.title)
                .fontWeight(.bold)

            if let household = viewModel.currentHousehold {
                Text(household.name)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.primary)
            }

            Text(String(localized: "\(viewModel.memberCount) member(s) in this family"))
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.textSecondary)

            Spacer()
        }
        .padding(Theme.Spacing.md)
    }

    // MARK: - Actions

    private func joinHousehold() {
        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count == AppConstants.inviteCodeLength else { return }

        Task {
            do {
                try await viewModel.joinHousehold(code: code, modelContext: modelContext)
                await MainActor.run {
                    hasJoined = true
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
            } catch {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)
            }
        }
    }
}
