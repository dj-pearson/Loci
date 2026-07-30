import SwiftData
import SwiftUI

struct HouseholdMembersView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var viewModel: HouseholdViewModel

    @State private var memberToRemove: HouseholdMember?
    @State private var showRemoveConfirmation = false
    @State private var showLeaveConfirmation = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        List {
            memberCountSection
            membersSection
            inviteCodeSection
            dangerSection
        }
        .navigationTitle(viewModel.currentHousehold?.name ?? String(localized: "Family"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.refreshMembers(modelContext: modelContext)
        }
        .alert(
            String(localized: "Remove Member"),
            isPresented: $showRemoveConfirmation,
            presenting: memberToRemove
        ) { member in
            Button(String(localized: "Remove"), role: .destructive) {
                removeMember(member)
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: { member in
            Text(String(localized: "Are you sure you want to remove \(member.displayName) from the family?"))
        }
        .alert(
            String(localized: "Leave Family"),
            isPresented: $showLeaveConfirmation
        ) {
            Button(String(localized: "Leave"), role: .destructive) {
                leaveHousehold()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "You will no longer see shared notes from this family."))
        }
        .alert(
            String(localized: "Delete Family"),
            isPresented: $showDeleteConfirmation
        ) {
            Button(String(localized: "Delete"), role: .destructive) {
                deleteHousehold()
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "This will permanently remove the family group and all members. This cannot be undone."))
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

    // MARK: - Member Count

    private var memberCountSection: some View {
        Section {
            HStack {
                Label(
                    String(localized: "\(viewModel.memberCount) of \(AppConstants.maxHouseholdMembers) members"),
                    systemImage: "person.2"
                )
                .font(Theme.Typography.headline)

                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                }
            }
        }
    }

    // MARK: - Members List

    private var membersSection: some View {
        Section(String(localized: "Members")) {
            ForEach(sortedMembers, id: \.id) { member in
                memberRow(member)
            }
            .onDelete { offsets in
                guard viewModel.isOwner else { return }
                if let index = offsets.first {
                    let member = sortedMembers[index]
                    guard member.role != .owner else { return }
                    memberToRemove = member
                    showRemoveConfirmation = true
                }
            }
            .deleteDisabled(!viewModel.isOwner)
        }
    }

    private func memberRow(_ member: HouseholdMember) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: member.role == .owner ? "crown.fill" : "person.fill")
                .foregroundStyle(member.role == .owner ? Theme.warning : Theme.textSecondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayName)
                    .font(Theme.Typography.body)

                Text(member.role == .owner
                    ? String(localized: "Owner")
                    : String(localized: "Member"))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    // MARK: - Invite Code Section

    @ViewBuilder
    private var inviteCodeSection: some View {
        if viewModel.isOwner {
            Section(String(localized: "Invite Code")) {
                if let code = viewModel.inviteCode {
                    HStack {
                        Text(code)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .tracking(4)

                        Spacer()

                        ShareLink(
                            item: String(localized: "Join my family on Lociate! Use invite code: \(code)"),
                            subject: Text(String(localized: "Join my family on Lociate"))
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }

                    Button {
                        regenerateCode()
                    } label: {
                        Label(String(localized: "Regenerate Code"), systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                } else {
                    Button {
                        regenerateCode()
                    } label: {
                        Label(String(localized: "Generate Invite Code"), systemImage: "plus.circle")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
    }

    // MARK: - Danger Section

    private var dangerSection: some View {
        Section {
            if viewModel.isOwner {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label(String(localized: "Delete Family"), systemImage: "trash")
                }
            } else {
                Button(role: .destructive) {
                    showLeaveConfirmation = true
                } label: {
                    Label(String(localized: "Leave Family"), systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
    }

    // MARK: - Sorted Members

    private var sortedMembers: [HouseholdMember] {
        viewModel.members.sorted { lhs, rhs in
            if lhs.role == .owner && rhs.role != .owner { return true }
            if lhs.role != .owner && rhs.role == .owner { return false }
            return lhs.displayName < rhs.displayName
        }
    }

    // MARK: - Actions

    private func removeMember(_ member: HouseholdMember) {
        Task {
            do {
                try await viewModel.removeMember(member, modelContext: modelContext)
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            } catch {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)
            }
        }
    }

    private func leaveHousehold() {
        Task {
            do {
                try await viewModel.leaveHousehold(modelContext: modelContext)
                await MainActor.run { dismiss() }
            } catch {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)
            }
        }
    }

    private func deleteHousehold() {
        Task {
            do {
                try await viewModel.deleteHousehold(modelContext: modelContext)
                await MainActor.run { dismiss() }
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
}
