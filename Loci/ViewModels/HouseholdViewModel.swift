import Foundation
import Supabase
import SwiftData

@Observable
final class HouseholdViewModel {
    // MARK: - Published State

    private(set) var currentHousehold: Household?
    private(set) var members: [HouseholdMember] = []
    private(set) var inviteCode: String?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let supabase = SupabaseClientProvider.shared

    // MARK: - Create Household

    /// Creates a new household with the current user as owner.
    func createHousehold(name: String, modelContext: ModelContext) async throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HouseholdError.invalidName
        }

        guard let userId = await currentUserId() else {
            throw HouseholdError.notAuthenticated
        }

        await setLoading(true)
        defer { Task { await self.setLoading(false) } }

        do {
            struct CreatePayload: Encodable {
                let name: String
                let owner_id: String
            }

            struct HouseholdRow: Decodable {
                let id: String
                let name: String
                let owner_id: String
                let invite_code: String?
                let invite_expires_at: String?
            }

            let rows: [HouseholdRow] = try await supabase
                .from("households")
                .insert(CreatePayload(name: name.trimmingCharacters(in: .whitespacesAndNewlines), owner_id: userId))
                .select()
                .execute()
                .value

            guard let row = rows.first, let householdId = UUID(uuidString: row.id) else {
                throw HouseholdError.createFailed
            }

            // Add owner as first member
            struct MemberPayload: Encodable {
                let household_id: String
                let user_id: String
                let display_name: String
                let role: String
            }

            let displayName = await currentDisplayName(modelContext: modelContext) ?? String(localized: "Owner")

            try await supabase
                .from("household_members")
                .insert(MemberPayload(
                    household_id: row.id,
                    user_id: userId,
                    display_name: displayName,
                    role: MemberRole.owner.rawValue
                ))
                .execute()

            // Save to SwiftData
            let household = Household(
                id: householdId,
                name: row.name,
                ownerId: UUID(uuidString: row.owner_id) ?? UUID(),
                inviteCode: row.invite_code ?? "",
                inviteExpiresAt: row.invite_expires_at.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date.distantPast
            )

            let member = HouseholdMember(
                householdId: householdId,
                userId: UUID(uuidString: userId) ?? UUID(),
                displayName: displayName,
                role: .owner
            )

            await MainActor.run {
                modelContext.insert(household)
                modelContext.insert(member)
                try? modelContext.save()
                self.currentHousehold = household
                self.members = [member]
                self.errorMessage = nil
            }
        } catch let error as HouseholdError {
            await setError(error.localizedDescription)
            throw error
        } catch {
            await setError(String(localized: "Failed to create household. Please try again."))
            throw HouseholdError.createFailed
        }
    }

    // MARK: - Join Household

    /// Joins a household via invite code using the edge function.
    func joinHousehold(code: String, modelContext: ModelContext) async throws {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmedCode.isEmpty else {
            throw HouseholdError.invalidCode
        }

        guard let userId = await currentUserId() else {
            throw HouseholdError.notAuthenticated
        }

        await setLoading(true)
        defer { Task { await self.setLoading(false) } }

        do {
            // Validate the code first
            struct ValidateRequest: Encodable {
                let code: String
            }

            struct ValidateResponse: Decodable {
                let valid: Bool
                let householdId: String
                let householdName: String
                let memberCount: Int
            }

            let validateResult: ValidateResponse = try await supabase.functions
                .invoke(
                    "household-invite/validate",
                    options: .init(body: ValidateRequest(code: trimmedCode))
                )

            // Accept the invite
            struct AcceptRequest: Encodable {
                let code: String
            }

            struct AcceptResponse: Decodable {
                let householdId: String
                let householdName: String
                let role: String
            }

            let acceptResult: AcceptResponse = try await supabase.functions
                .invoke(
                    "household-invite/accept",
                    options: .init(body: AcceptRequest(code: trimmedCode))
                )

            guard let householdId = UUID(uuidString: acceptResult.householdId) else {
                throw HouseholdError.joinFailed
            }

            let displayName = await currentDisplayName(modelContext: modelContext) ?? String(localized: "Member")

            // Save to SwiftData
            let household = Household(
                id: householdId,
                name: acceptResult.householdName,
                ownerId: UUID(), // Will be populated on refresh
                inviteCode: "",
                inviteExpiresAt: Date.distantPast
            )

            let member = HouseholdMember(
                householdId: householdId,
                userId: UUID(uuidString: userId) ?? UUID(),
                displayName: displayName,
                role: MemberRole(rawValue: acceptResult.role) ?? .member
            )

            await MainActor.run {
                modelContext.insert(household)
                modelContext.insert(member)
                try? modelContext.save()
                self.currentHousehold = household
                self.members.append(member)
                self.errorMessage = nil
            }

            // Refresh to get full member list
            await refreshMembers(modelContext: modelContext)
        } catch let error as HouseholdError {
            await setError(error.localizedDescription)
            throw error
        } catch {
            let message = error.localizedDescription.lowercased()
            if message.contains("expired") {
                await setError(String(localized: "This invite code has expired."))
                throw HouseholdError.codeExpired
            } else if message.contains("full") {
                await setError(String(localized: "This household is full (maximum 6 members)."))
                throw HouseholdError.householdFull
            } else if message.contains("already") {
                await setError(String(localized: "You are already a member of this household."))
                throw HouseholdError.alreadyMember
            }
            await setError(String(localized: "Failed to join household. Please check the code and try again."))
            throw HouseholdError.joinFailed
        }
    }

    // MARK: - Leave Household

    /// Removes the current user from the household. Owners cannot leave; they must delete.
    func leaveHousehold(modelContext: ModelContext) async throws {
        guard let household = currentHousehold else {
            throw HouseholdError.noHousehold
        }

        guard let userId = await currentUserId() else {
            throw HouseholdError.notAuthenticated
        }

        // Owners must delete, not leave
        let userUUID = UUID(uuidString: userId)
        if household.ownerId == userUUID {
            throw HouseholdError.ownerCannotLeave
        }

        await setLoading(true)
        defer { Task { await self.setLoading(false) } }

        do {
            // Remove from Supabase
            try await supabase
                .from("household_members")
                .delete()
                .eq("household_id", value: household.id.uuidString)
                .eq("user_id", value: userId)
                .execute()

            // Remove local data
            let householdIdString = household.id.uuidString
            let memberDescriptor = FetchDescriptor<HouseholdMember>(
                predicate: #Predicate { $0.householdId.uuidString == householdIdString && $0.userId.uuidString == userId }
            )

            await MainActor.run {
                if let localMember = try? modelContext.fetch(memberDescriptor).first {
                    modelContext.delete(localMember)
                }
                modelContext.delete(household)
                try? modelContext.save()
                self.currentHousehold = nil
                self.members = []
                self.inviteCode = nil
                self.errorMessage = nil
            }
        } catch let error as HouseholdError {
            await setError(error.localizedDescription)
            throw error
        } catch {
            await setError(String(localized: "Failed to leave household. Please try again."))
            throw HouseholdError.leaveFailed
        }
    }

    // MARK: - Delete Household

    /// Deletes the household. Only the owner can delete.
    func deleteHousehold(modelContext: ModelContext) async throws {
        guard let household = currentHousehold else {
            throw HouseholdError.noHousehold
        }

        guard let userId = await currentUserId() else {
            throw HouseholdError.notAuthenticated
        }

        guard household.ownerId == UUID(uuidString: userId) else {
            throw HouseholdError.notOwner
        }

        await setLoading(true)
        defer { Task { await self.setLoading(false) } }

        do {
            // Delete from Supabase (cascade removes members)
            try await supabase
                .from("households")
                .delete()
                .eq("id", value: household.id.uuidString)
                .execute()

            // Delete local data
            let householdIdString = household.id.uuidString
            let memberDescriptor = FetchDescriptor<HouseholdMember>(
                predicate: #Predicate { $0.householdId.uuidString == householdIdString }
            )

            await MainActor.run {
                if let localMembers = try? modelContext.fetch(memberDescriptor) {
                    for member in localMembers {
                        modelContext.delete(member)
                    }
                }
                modelContext.delete(household)
                try? modelContext.save()
                self.currentHousehold = nil
                self.members = []
                self.inviteCode = nil
                self.errorMessage = nil
            }
        } catch let error as HouseholdError {
            await setError(error.localizedDescription)
            throw error
        } catch {
            await setError(String(localized: "Failed to delete household. Please try again."))
            throw HouseholdError.deleteFailed
        }
    }

    // MARK: - Refresh Members

    /// Fetches the current member list from Supabase.
    func refreshMembers(modelContext: ModelContext) async {
        guard let household = currentHousehold else { return }

        do {
            struct MemberRow: Decodable {
                let id: String
                let household_id: String
                let user_id: String
                let display_name: String
                let role: String
            }

            let rows: [MemberRow] = try await supabase
                .from("household_members")
                .select()
                .eq("household_id", value: household.id.uuidString)
                .execute()
                .value

            let refreshedMembers = rows.compactMap { row -> HouseholdMember? in
                guard let id = UUID(uuidString: row.id),
                      let householdId = UUID(uuidString: row.household_id),
                      let userId = UUID(uuidString: row.user_id) else { return nil }
                return HouseholdMember(
                    id: id,
                    householdId: householdId,
                    userId: userId,
                    displayName: row.display_name,
                    role: MemberRole(rawValue: row.role) ?? .member
                )
            }

            // Update local SwiftData
            let householdIdString = household.id.uuidString
            let existingDescriptor = FetchDescriptor<HouseholdMember>(
                predicate: #Predicate { $0.householdId.uuidString == householdIdString }
            )

            await MainActor.run {
                // Remove stale local members
                if let existing = try? modelContext.fetch(existingDescriptor) {
                    for member in existing {
                        modelContext.delete(member)
                    }
                }
                // Insert fresh data
                for member in refreshedMembers {
                    modelContext.insert(member)
                }
                try? modelContext.save()
                self.members = refreshedMembers
            }
        } catch {
            // Network failure — keep existing local data
        }
    }

    // MARK: - Load Local Household

    /// Loads the user's household from local SwiftData on app launch.
    func loadLocalHousehold(modelContext: ModelContext) async {
        guard let userId = await currentUserId() else { return }

        let userIdString = userId
        let memberDescriptor = FetchDescriptor<HouseholdMember>(
            predicate: #Predicate { $0.userId.uuidString == userIdString }
        )

        await MainActor.run {
            guard let membership = try? modelContext.fetch(memberDescriptor).first else { return }

            let householdIdString = membership.householdId.uuidString
            let householdDescriptor = FetchDescriptor<Household>(
                predicate: #Predicate { $0.id.uuidString == householdIdString }
            )

            if let household = try? modelContext.fetch(householdDescriptor).first {
                self.currentHousehold = household
                self.inviteCode = household.isInviteExpired ? nil : household.inviteCode

                let allMembersDescriptor = FetchDescriptor<HouseholdMember>(
                    predicate: #Predicate { $0.householdId.uuidString == householdIdString }
                )
                self.members = (try? modelContext.fetch(allMembersDescriptor)) ?? []
            }
        }
    }

    // MARK: - Generate Invite Code

    /// Generates a new invite code for the household (owner only).
    func generateInviteCode(modelContext: ModelContext) async throws {
        guard let household = currentHousehold else {
            throw HouseholdError.noHousehold
        }

        await setLoading(true)
        defer { Task { await self.setLoading(false) } }

        do {
            struct GenerateRequest: Encodable {
                let householdId: String
            }

            struct GenerateResponse: Decodable {
                let code: String
                let expiresAt: String
            }

            let result: GenerateResponse = try await supabase.functions
                .invoke(
                    "household-invite/generate",
                    options: .init(body: GenerateRequest(householdId: household.id.uuidString))
                )

            let expiresAt = ISO8601DateFormatter().date(from: result.expiresAt) ?? Date()

            await MainActor.run {
                household.inviteCode = result.code
                household.inviteExpiresAt = expiresAt
                try? modelContext.save()
                self.inviteCode = result.code
                self.errorMessage = nil
            }
        } catch {
            await setError(String(localized: "Failed to generate invite code. Please try again."))
            throw HouseholdError.generateCodeFailed
        }
    }

    // MARK: - Computed Properties

    var isOwner: Bool {
        guard let household = currentHousehold,
              let userId = try? supabase.auth.session.user.id else { return false }
        // Compare owner_id with the internal user ID (not auth ID)
        // For local check, we compare against members with owner role
        return members.contains { $0.role == .owner && $0.householdId == household.id }
    }

    var hasHousehold: Bool {
        currentHousehold != nil
    }

    var memberCount: Int {
        members.count
    }

    // MARK: - Helpers

    private func currentUserId() async -> String? {
        guard let session = try? await supabase.auth.session else { return nil }
        let authId = session.user.id.uuidString
        struct UserRow: Decodable { let id: String }
        let result: [UserRow]? = try? await supabase
            .from("users")
            .select("id")
            .eq("auth_id", value: authId)
            .execute()
            .value
        return result?.first?.id
    }

    private func currentDisplayName(modelContext: ModelContext) async -> String? {
        guard let session = try? await supabase.auth.session else { return nil }
        let authIdString = session.user.id.uuidString
        let descriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate { $0.authId?.uuidString == authIdString }
        )
        return try? await MainActor.run {
            try modelContext.fetch(descriptor).first?.displayName
        }
    }

    @MainActor
    private func setLoading(_ loading: Bool) {
        isLoading = loading
    }

    @MainActor
    private func setError(_ message: String) {
        errorMessage = message
    }
}

// MARK: - Household Errors

enum HouseholdError: LocalizedError {
    case notAuthenticated
    case invalidName
    case invalidCode
    case codeExpired
    case householdFull
    case alreadyMember
    case noHousehold
    case notOwner
    case ownerCannotLeave
    case createFailed
    case joinFailed
    case leaveFailed
    case deleteFailed
    case generateCodeFailed

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            String(localized: "You must be signed in to manage households.")
        case .invalidName:
            String(localized: "Please enter a valid household name.")
        case .invalidCode:
            String(localized: "Please enter a valid invite code.")
        case .codeExpired:
            String(localized: "This invite code has expired.")
        case .householdFull:
            String(localized: "This household is full (maximum 6 members).")
        case .alreadyMember:
            String(localized: "You are already a member of this household.")
        case .noHousehold:
            String(localized: "No household found.")
        case .notOwner:
            String(localized: "Only the household owner can perform this action.")
        case .ownerCannotLeave:
            String(localized: "The household owner cannot leave. Delete the household instead.")
        case .createFailed:
            String(localized: "Failed to create household. Please try again.")
        case .joinFailed:
            String(localized: "Failed to join household. Please check the code and try again.")
        case .leaveFailed:
            String(localized: "Failed to leave household. Please try again.")
        case .deleteFailed:
            String(localized: "Failed to delete household. Please try again.")
        case .generateCodeFailed:
            String(localized: "Failed to generate invite code. Please try again.")
        }
    }
}
