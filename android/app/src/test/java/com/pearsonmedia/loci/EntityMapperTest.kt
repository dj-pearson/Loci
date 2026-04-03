package com.pearsonmedia.loci

import com.google.common.truth.Truth.assertThat
import com.pearsonmedia.loci.data.local.converter.toDomain
import com.pearsonmedia.loci.data.local.converter.toEntity
import com.pearsonmedia.loci.domain.model.Locus
import com.pearsonmedia.loci.domain.model.LocusCategory
import com.pearsonmedia.loci.domain.model.SyncStatus
import org.junit.Test
import java.time.Instant
import java.util.UUID

class EntityMapperTest {

    @Test
    fun `locus domain to entity and back preserves data`() {
        val original = Locus(
            id = UUID.randomUUID(),
            latitude = 37.7749,
            longitude = -122.4194,
            locationName = "San Francisco",
            audioFilePath = "/audio/test.m4a",
            transcription = "Test transcription",
            category = LocusCategory.FOOD,
            isShared = true,
            createdByName = "John",
            householdId = UUID.randomUUID(),
            createdAt = Instant.now(),
            updatedAt = Instant.now(),
            isArchived = false,
            syncStatus = SyncStatus.PENDING
        )

        val entity = original.toEntity()
        val restored = entity.toDomain()

        assertThat(restored.id).isEqualTo(original.id)
        assertThat(restored.latitude).isEqualTo(original.latitude)
        assertThat(restored.longitude).isEqualTo(original.longitude)
        assertThat(restored.locationName).isEqualTo(original.locationName)
        assertThat(restored.audioFilePath).isEqualTo(original.audioFilePath)
        assertThat(restored.transcription).isEqualTo(original.transcription)
        assertThat(restored.category).isEqualTo(original.category)
        assertThat(restored.isShared).isEqualTo(original.isShared)
        assertThat(restored.createdByName).isEqualTo(original.createdByName)
        assertThat(restored.householdId).isEqualTo(original.householdId)
        assertThat(restored.isArchived).isEqualTo(original.isArchived)
        assertThat(restored.syncStatus).isEqualTo(original.syncStatus)
    }

    @Test
    fun `entity category maps correctly`() {
        val entity = com.pearsonmedia.loci.data.local.entity.LocusEntity(
            id = UUID.randomUUID().toString(),
            latitude = 0.0,
            longitude = 0.0,
            audioFilePath = "/test.m4a",
            category = "SHOPPING"
        )

        val domain = entity.toDomain()
        assertThat(domain.category).isEqualTo(LocusCategory.SHOPPING)
    }
}
