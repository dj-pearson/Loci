package com.pearsonmedia.lociate.data.local.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "loci",
    indices = [
        Index(value = ["latitude", "longitude"]),
        Index(value = ["category"]),
        Index(value = ["is_archived"]),
        Index(value = ["sync_status"]),
        Index(value = ["household_id"]),
        Index(value = ["created_at"])
    ]
)
data class LocusEntity(
    @PrimaryKey
    val id: String,

    val latitude: Double,
    val longitude: Double,

    @ColumnInfo(name = "location_name")
    val locationName: String? = null,

    @ColumnInfo(name = "audio_file_path")
    val audioFilePath: String,

    val transcription: String = "",
    val category: String = "GENERAL",

    @ColumnInfo(name = "is_shared")
    val isShared: Boolean = false,

    @ColumnInfo(name = "created_by_name")
    val createdByName: String? = null,

    @ColumnInfo(name = "household_id")
    val householdId: String? = null,

    @ColumnInfo(name = "created_at")
    val createdAt: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "updated_at")
    val updatedAt: Long = System.currentTimeMillis(),

    @ColumnInfo(name = "is_archived")
    val isArchived: Boolean = false,

    @ColumnInfo(name = "sync_status")
    val syncStatus: String = "PENDING"
)
