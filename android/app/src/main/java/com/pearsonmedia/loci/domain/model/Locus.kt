package com.pearsonmedia.loci.domain.model

import java.time.Instant
import java.util.UUID

data class Locus(
    val id: UUID = UUID.randomUUID(),
    val latitude: Double,
    val longitude: Double,
    val locationName: String? = null,
    val audioFilePath: String,
    val transcription: String = "",
    val category: LocusCategory = LocusCategory.GENERAL,
    val isShared: Boolean = false,
    val createdByName: String? = null,
    val householdId: UUID? = null,
    val createdAt: Instant = Instant.now(),
    val updatedAt: Instant = Instant.now(),
    val isArchived: Boolean = false,
    val syncStatus: SyncStatus = SyncStatus.PENDING
)

enum class SyncStatus {
    PENDING,
    SYNCED,
    MODIFIED,
    CONFLICTED
}

enum class SubscriptionTier {
    FREE,
    PREMIUM,
    FAMILY;

    val maxLoci: Int
        get() = when (this) {
            FREE -> 10
            PREMIUM, FAMILY -> Int.MAX_VALUE
        }

    val hasCloudSync: Boolean
        get() = this != FREE

    val hasAiCategorization: Boolean
        get() = this != FREE

    val hasWidget: Boolean
        get() = this != FREE

    val hasSearch: Boolean
        get() = this != FREE

    val hasFamilySharing: Boolean
        get() = this == FAMILY

    val maxHouseholdMembers: Int
        get() = if (this == FAMILY) 6 else 0
}
