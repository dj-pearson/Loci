package app.lociate.android.domain.model

import java.time.Instant
import java.util.UUID

data class Household(
    val id: UUID = UUID.randomUUID(),
    val name: String,
    val ownerId: UUID,
    val inviteCode: String,
    val inviteExpiresAt: Instant,
    val createdAt: Instant = Instant.now()
) {
    val isInviteExpired: Boolean
        get() = Instant.now().isAfter(inviteExpiresAt)
}

data class HouseholdMember(
    val id: UUID = UUID.randomUUID(),
    val householdId: UUID,
    val userId: UUID,
    val displayName: String,
    val role: MemberRole = MemberRole.MEMBER
)

enum class MemberRole {
    OWNER,
    MEMBER
}

data class UserProfile(
    val id: UUID = UUID.randomUUID(),
    val authId: String? = null,
    val displayName: String,
    val subscriptionTier: SubscriptionTier = SubscriptionTier.FREE,
    val fcmToken: String? = null
)
