package app.lociate.android.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "households"
)
data class HouseholdEntity(
    @PrimaryKey
    val id: String,

    val name: String,

    @ColumnInfo(name = "owner_id")
    val ownerId: String,

    @ColumnInfo(name = "invite_code")
    val inviteCode: String,

    @ColumnInfo(name = "invite_expires_at")
    val inviteExpiresAt: Long,

    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis()
)

@Entity(
    tableName = "household_members",
    indices = [
        Index(value = ["household_id"]),
        Index(value = ["user_id"])
    ]
)
data class HouseholdMemberEntity(
    @PrimaryKey
    val id: String,

    @ColumnInfo(name = "household_id")
    val householdId: String,

    @ColumnInfo(name = "user_id")
    val userId: String,

    @ColumnInfo(name = "display_name")
    val displayName: String,

    val role: String = "MEMBER"
)

@Entity(tableName = "user_profile")
data class UserProfileEntity(
    @PrimaryKey
    val id: String,

    @ColumnInfo(name = "auth_id")
    val authId: String? = null,

    @ColumnInfo(name = "display_name")
    val displayName: String,

    @ColumnInfo(name = "subscription_tier")
    val subscriptionTier: String = "FREE",

    @ColumnInfo(name = "fcm_token")
    val fcmToken: String? = null
)
