import SwiftData
import SwiftUI

struct CreateHouseholdView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var viewModel: HouseholdViewModel

    @State private var familyName = ""
    @State private var hasCreated = false

    var body: some View {
        NavigationStack {
            Group {
                if hasCreated {
                    inviteCodeView
                } else {
                    createFormView
                }
            }
            .navigationTitle(hasCreated
                ? String(localized: "Invite Family")
                : String(localized: "Create Family"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !hasCreated {
                        Button(String(localized: "Cancel")) {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if hasCreated {
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

    // MARK: - Create Form

    private var createFormView: some View {
        Form {
            Section {
                TextField(String(localized: "Family Name"), text: $familyName)
                    .textContentType(.organizationName)
                    .submitLabel(.done)
                    .onSubmit(createHousehold)
            } header: {
                Text(String(localized: "Give your family group a name"))
            } footer: {
                Text(String(localized: "You can invite up to 5 other family members to share voice notes at your favorite places."))
            }

            Section {
                Button {
                    createHousehold()
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Text(String(localized: "Create Family"))
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
            }
        }
    }

    // MARK: - Invite Code View

    private var inviteCodeView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.success)

            Text(String(localized: "Family Created!"))
                .font(Theme.Typography.title)
                .fontWeight(.bold)

            Text(String(localized: "Share this code with your family members so they can join."))
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.lg)

            inviteCodeCard

            Text(String(localized: "Code expires in 48 hours"))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.warning)

            shareButton

            regenerateButton

            Spacer()
        }
        .padding(Theme.Spacing.md)
    }

    private var inviteCodeCard: some View {
        Text(displayInviteCode)
            .font(.system(size: 36, weight: .bold, design: .monospaced))
            .tracking(8)
            .padding(.vertical, Theme.Spacing.md)
            .padding(.horizontal, Theme.Spacing.xl)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                    .strokeBorder(Theme.primary.opacity(0.3), lineWidth: 1)
            )
    }

    private var shareButton: some View {
        ShareLink(
            item: shareText,
            subject: Text(String(localized: "Join my family on Loci")),
            message: Text(shareText)
        ) {
            Label(String(localized: "Share Invite Code"), systemImage: "square.and.arrow.up")
                .font(Theme.Typography.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.sm)
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private var regenerateButton: some View {
        Button {
            regenerateCode()
        } label: {
            Label(String(localized: "Regenerate Code"), systemImage: "arrow.clockwise")
                .font(Theme.Typography.body)
        }
        .disabled(viewModel.isLoading)
        .padding(.top, Theme.Spacing.sm)
    }

    // MARK: - Actions

    private func createHousehold() {
        let trimmed = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        Task {
            do {
                try await viewModel.createHousehold(name: trimmed, modelContext: modelContext)
                // Generate invite code after creation
                try await viewModel.generateInviteCode(modelContext: modelContext)
                await MainActor.run {
                    hasCreated = true
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
            } catch {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)
            }
        }
    }

    private func regenerateCode() {
        Task {
            do {
                try await viewModel.generateInviteCode(modelContext: modelContext)
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            } catch {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)
            }
        }
    }

    // MARK: - Computed Properties

    private var displayInviteCode: String {
        viewModel.inviteCode ?? "------"
    }

    private var shareText: String {
        let code = viewModel.inviteCode ?? ""
        return String(localized: "Join my family on Loci! Use invite code: \(code)")
    }
}
