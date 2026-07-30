package app.lociate.android.data.local.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * A security-relevant event, stored locally (US-216).
 *
 * Mirrors the iOS `AuditLogEntry`. The email is stored only as a SHA-256 hash —
 * this table is on-device and unencrypted at the Room layer, so holding a raw
 * address would make it a liability rather than a safeguard.
 */
@Entity(
    tableName = "audit_log",
    indices = [Index(value = ["timestamp"])]
)
data class AuditLogEntity(
    @PrimaryKey
    val id: String,
    val eventType: String,
    val emailHash: String,
    val deviceInfo: String,
    val appVersion: String,
    val timestamp: Long,
)
