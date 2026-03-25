import Foundation
import SwiftData

@Model
final class HouseholdMember {
    @Attribute(.unique) var id: UUID
    var householdId: UUID
    var userId: UUID
    var displayName: String
    var roleRawValue: String

    var role: MemberRole {
        get { MemberRole(rawValue: roleRawValue) ?? .member }
        set { roleRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        householdId: UUID,
        userId: UUID,
        displayName: String,
        role: MemberRole = .member
    ) {
        self.id = id
        self.householdId = householdId
        self.userId = userId
        self.displayName = displayName
        self.roleRawValue = role.rawValue
    }
}

enum MemberRole: String, Codable {
    case owner
    case member
}
