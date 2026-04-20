package app.lociate.android.data.remote.dto

import app.lociate.android.data.local.entity.LocusEntity
import app.lociate.android.domain.model.Locus
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * DTO for Supabase PostgREST loci table.
 * Maps between the PostgreSQL schema and the local domain model.
 */
@Serializable
data class LocusDto(
    val id: String,
    val latitude: Double,
    val longitude: Double,

    @SerialName("location_name")
    val locationName: String? = null,

    @SerialName("audio_file_url")
    val audioFileUrl: String = "",

    val transcription: String = "",
    val category: String = "GENERAL",

    @SerialName("is_shared")
    val isShared: Boolean = false,

    @SerialName("created_by_name")
    val createdByName: String? = null,

    @SerialName("household_id")
    val householdId: String? = null,

    @SerialName("created_at")
    val createdAt: Long = System.currentTimeMillis(),

    @SerialName("updated_at")
    val updatedAt: Long = System.currentTimeMillis(),

    @SerialName("is_archived")
    val isArchived: Boolean = false,

    @SerialName("user_id")
    val userId: String? = null
) {
    fun toEntity(): LocusEntity = LocusEntity(
        id = id,
        latitude = latitude,
        longitude = longitude,
        locationName = locationName,
        audioFilePath = audioFileUrl,
        transcription = transcription,
        category = category,
        isShared = isShared,
        createdByName = createdByName,
        householdId = householdId,
        createdAt = createdAt,
        updatedAt = updatedAt,
        isArchived = isArchived,
        syncStatus = "SYNCED"
    )

    companion object {
        fun fromDomain(locus: Locus): LocusDto = LocusDto(
            id = locus.id.toString(),
            latitude = locus.latitude,
            longitude = locus.longitude,
            locationName = locus.locationName,
            audioFileUrl = locus.audioFilePath,
            transcription = locus.transcription,
            category = locus.category.name,
            isShared = locus.isShared,
            createdByName = locus.createdByName,
            householdId = locus.householdId?.toString(),
            createdAt = locus.createdAt.toEpochMilli(),
            updatedAt = locus.updatedAt.toEpochMilli(),
            isArchived = locus.isArchived
        )
    }
}
