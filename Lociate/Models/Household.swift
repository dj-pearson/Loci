import Foundation
import SwiftData

@Model
final class Household {
    @Attribute(.unique) var id: UUID
    var name: String
    var ownerId: UUID
    var inviteCode: String
    var inviteExpiresAt: Date

    var isInviteExpired: Bool {
        Date() > inviteExpiresAt
    }

    init(
        id: UUID = UUID(),
        name: String,
        ownerId: UUID,
        inviteCode: String,
        inviteExpiresAt: Date
    ) {
        self.id = id
        self.name = name
        self.ownerId = ownerId
        self.inviteCode = inviteCode
        self.inviteExpiresAt = inviteExpiresAt
    }
}
