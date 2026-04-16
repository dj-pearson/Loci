package com.pearsonmedia.lociate.data.local.converter

import com.pearsonmedia.lociate.data.local.entity.HouseholdEntity
import com.pearsonmedia.lociate.data.local.entity.HouseholdMemberEntity
import com.pearsonmedia.lociate.data.local.entity.LocusEntity
import com.pearsonmedia.lociate.data.local.entity.UserProfileEntity
import com.pearsonmedia.lociate.domain.model.Household
import com.pearsonmedia.lociate.domain.model.HouseholdMember
import com.pearsonmedia.lociate.domain.model.Locus
import com.pearsonmedia.lociate.domain.model.LocusCategory
import com.pearsonmedia.lociate.domain.model.MemberRole
import com.pearsonmedia.lociate.domain.model.SubscriptionTier
import com.pearsonmedia.lociate.domain.model.SyncStatus
import com.pearsonmedia.lociate.domain.model.UserProfile
import java.time.Instant
import java.util.UUID

fun LocusEntity.toDomain(): Locus = Locus(
    id = UUID.fromString(id),
    latitude = latitude,
    longitude = longitude,
    locationName = locationName,
    audioFilePath = audioFilePath,
    transcription = transcription,
    category = LocusCategory.fromString(category),
    isShared = isShared,
    createdByName = createdByName,
    householdId = householdId?.let { UUID.fromString(it) },
    createdAt = Instant.ofEpochMilli(createdAt),
    updatedAt = Instant.ofEpochMilli(updatedAt),
    isArchived = isArchived,
    syncStatus = SyncStatus.valueOf(syncStatus)
)

fun Locus.toEntity(): LocusEntity = LocusEntity(
    id = id.toString(),
    latitude = latitude,
    longitude = longitude,
    locationName = locationName,
    audioFilePath = audioFilePath,
    transcription = transcription,
    category = category.name,
    isShared = isShared,
    createdByName = createdByName,
    householdId = householdId?.toString(),
    createdAt = createdAt.toEpochMilli(),
    updatedAt = updatedAt.toEpochMilli(),
    isArchived = isArchived,
    syncStatus = syncStatus.name
)

fun HouseholdEntity.toDomain(): Household = Household(
    id = UUID.fromString(id),
    name = name,
    ownerId = UUID.fromString(ownerId),
    inviteCode = inviteCode,
    inviteExpiresAt = Instant.ofEpochMilli(inviteExpiresAt),
    createdAt = Instant.ofEpochMilli(createdAt)
)

fun HouseholdMemberEntity.toDomain(): HouseholdMember = HouseholdMember(
    id = UUID.fromString(id),
    householdId = UUID.fromString(householdId),
    userId = UUID.fromString(userId),
    displayName = displayName,
    role = MemberRole.valueOf(role)
)

fun UserProfileEntity.toDomain(): UserProfile = UserProfile(
    id = UUID.fromString(id),
    authId = authId,
    displayName = displayName,
    subscriptionTier = SubscriptionTier.valueOf(subscriptionTier),
    fcmToken = fcmToken
)

fun UserProfile.toEntity(): UserProfileEntity = UserProfileEntity(
    id = id.toString(),
    authId = authId,
    displayName = displayName,
    subscriptionTier = subscriptionTier.name,
    fcmToken = fcmToken
)
