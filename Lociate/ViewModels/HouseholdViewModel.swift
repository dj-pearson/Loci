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

    /// The signed-in user's internal `users.id`, cached by `currentUserId()`.
    ///
    /// `isOwner` needs it and cannot await `supabase.auth.session`, which is an async
    /// property. Nil until the first async call resolves, which makes `isOwner` fail
    /// closed — owner-only controls stay hidden rather than appearing to everyone.
    private(set) var signedInUserId: UUID?

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
            let sanitizedName = InputSanitizer.sanitizeHouseholdName(name)
            guard !sanitizedName.isEmpty else {
                throw HouseholdError.createFailed
            }

            let rows: [HouseholdRow] = try await supabase
                .from("households")
                .insert(CreatePayload(name: sanitizedName, ownerId: userId))
                .select()
                .execute()
                .value

            guard let row = rows.first, let householdId = UUID(uuidString: row.id) else {
                throw HouseholdError.createFailed
            }

            // Add owner as first member
            let displayName = InputSanitizer.sanitizeDisplayName(
                await currentDisplayName(modelContext: modelContext) ?? String(localized: "Owner")
            )

            try await supabase
                .from("household_members")
                .insert(MemberPayload(
                    householdId: row.id,
                    userId: userId,
                    displayName: displayName,
                    role: MemberRole.owner.rawValue
                ))
                .execute()

            // Save to SwiftData
            let household = Household(
                id: householdId,
                name: row.name,
                ownerId: UUID(uuidString: row.ownerId) ?? UUID(),
                inviteCode: row.inviteCode ?? "",
                inviteExpiresAt: row.inviteExpiresAt.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date.distantPast
            )

            let member = HouseholdMember(
                householdId: householdId,
                userId: UUID(uuidString: userId) ?? UUID(),
                displayName: displayName,
                role: .owner
            )

            await persistNewMembership(
                household: household,
                member: member,
                replacingMembers: true,
                in: modelContext
            )
        } catch let error as HouseholdError {
            await setError(error.localizedDescription)
            throw error
        } catch {
            await setError(String(localized: "Failed to create household. Please try again."))
            throw HouseholdError.createFailed
        }
    }

    /// Saves a newly created or joined household and its first member, then publishes
    /// them. `replacingMembers` distinguishes creating (this member is the only one we
    /// know about) from joining (the full list arrives from `refreshMembers`).
    private func persistNewMembership(
        household: Household,
        member: HouseholdMember,
        replacingMembers: Bool,
        in modelContext: ModelContext
    ) async {
        await MainActor.run {
            modelContext.insert(household)
            modelContext.insert(member)
            try? modelContext.save()
            self.currentHousehold = household
            self.members = replacingMembers ? [member] : self.members + [member]
            self.errorMessage = nil
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
            let validateResult: ValidateResponse = try await supabase.functions
                .invoke(
                    "household-invite/validate",
                    options: .init(body: ValidateRequest(code: trimmedCode))
                )

            // Accept the invite
            let acceptResult: AcceptResponse = try await supabase.functions
                .invoke(
                    "household-invite/accept",
                    options: .init(body: AcceptRequest(code: trimmedCode))
                )

            guard let householdId = UUID(uuidString: acceptResult.householdId) else {
                throw HouseholdError.joinFailed
            }

            let displayName = InputSanitizer.sanitizeDisplayName(
                await currentDisplayName(modelContext: modelContext) ?? String(localized: "Member")
            )

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

            await persistNewMembership(
                household: household,
                member: member,
                replacingMembers: false,
                in: modelContext
            )

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
            let rows: [MemberRow] = try await supabase
                .from("household_members")
                .select()
                .eq("household_id", value: household.id.uuidString)
                .execute()
                .value

            let refreshedMembers = rows.compactMap { row -> HouseholdMember? in
                guard let id = UUID(uuidString: row.id),
                      let householdId = UUID(uuidString: row.householdId),
                      let userId = UUID(uuidString: row.userId) else { return nil }
                return HouseholdMember(
                    id: id,
                    householdId: householdId,
                    userId: userId,
                    displayName: row.displayName,
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

    // MARK: - Remove Member

    /// Removes a member from the household. Owner only.
    func removeMember(_ member: HouseholdMember, modelContext: ModelContext) async throws {
        guard let household = currentHousehold else {
            throw HouseholdError.noHousehold
        }

        guard member.role != .owner else {
            throw HouseholdError.ownerCannotLeave
        }

        await setLoading(true)
        defer { Task { await self.setLoading(false) } }

        do {
            try await supabase
                .from("household_members")
                .delete()
                .eq("id", value: member.id.uuidString)
                .eq("household_id", value: household.id.uuidString)
                .execute()

            await MainActor.run {
                modelContext.delete(member)
                try? modelContext.save()
                self.members.removeAll { $0.id == member.id }
                self.errorMessage = nil
            }
        } catch {
            await setError(String(localized: "Failed to remove member. Please try again."))
            throw HouseholdError.removeFailed
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

    /// Whether the *signed-in user* owns the current household.
    ///
    /// This gates the owner-only controls in HouseholdMembersView: removing members,
    /// generating an invite code, deleting the household.
    ///
    /// It previously bound `try? supabase.auth.session.user.id` — which does not
    /// compile, because `session` is an async property — and then never used the
    /// binding, testing only whether *any* member held the owner role. That is true
    /// for every valid household, so every member saw the owner's controls. The
    /// server's RLS policies would still have rejected the mutations, but the UI was
    /// wrong. Now it looks for the signed-in user's own membership row.
    var isOwner: Bool {
        guard let household = currentHousehold, let signedInUserId else { return false }
        return members.contains {
            $0.householdId == household.id
                && $0.userId == signedInUserId
                && $0.role == .owner
        }
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
        let id = result?.first?.id
        // Cache it so `isOwner` — which is synchronous and cannot await a session —
        // has something to compare against.
        if let uuid = id.flatMap(UUID.init(uuidString:)) {
            await MainActor.run { self.signedInUserId = uuid }
        }
        return id
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

    @MainActor
    func clearError() {
        errorMessage = nil
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
    case removeFailed

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
        case .removeFailed:
            String(localized: "Failed to remove member. Please try again.")
        }
    }
}

// MARK: - Supabase Payloads

// PostgREST speaks the table's snake_case column names; the Swift side stays
// camelCase and CodingKeys does the translation. (The edge-function payloads —
// Validate*/Accept*/Generate* — are already camelCase over the wire and need none.)
//
// Declared at file scope rather than inside the functions that use them: with
// explicit CodingKeys each one runs to ~14 lines, and nesting them pushed
// createHousehold and joinHousehold past the body-length limit.

private struct CreatePayload: Encodable {
    let name: String
    let ownerId: String

    enum CodingKeys: String, CodingKey {
        case name
        case ownerId = "owner_id"
    }
}

private struct HouseholdRow: Decodable {
    let id: String
    let name: String
    let ownerId: String
    let inviteCode: String?
    let inviteExpiresAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case ownerId = "owner_id"
        case inviteCode = "invite_code"
        case inviteExpiresAt = "invite_expires_at"
    }
}

private struct MemberPayload: Encodable {
    let householdId: String
    let userId: String
    let displayName: String
    let role: String

    enum CodingKeys: String, CodingKey {
        case householdId = "household_id"
        case userId = "user_id"
        case displayName = "display_name"
        case role
    }
}

private struct ValidateRequest: Encodable {
    let code: String
}

private struct ValidateResponse: Decodable {
    let valid: Bool
    let householdId: String
    let householdName: String
    let memberCount: Int
}

private struct AcceptRequest: Encodable {
    let code: String
}

private struct AcceptResponse: Decodable {
    let householdId: String
    let householdName: String
    let role: String
}

private struct MemberRow: Decodable {
    let id: String
    let householdId: String
    let userId: String
    let displayName: String
    let role: String

    enum CodingKeys: String, CodingKey {
        case id
        case householdId = "household_id"
        case userId = "user_id"
        case displayName = "display_name"
        case role
    }
}

private struct GenerateRequest: Encodable {
    let householdId: String
}

private struct GenerateResponse: Decodable {
    let code: String
    let expiresAt: String
}
