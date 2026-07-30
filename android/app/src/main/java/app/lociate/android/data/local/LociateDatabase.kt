package app.lociate.android.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import app.lociate.android.data.local.dao.AuditLogDao
import app.lociate.android.data.local.dao.HouseholdDao
import app.lociate.android.data.local.dao.LocusDao
import app.lociate.android.data.local.entity.AuditLogEntity
import app.lociate.android.data.local.entity.HouseholdEntity
import app.lociate.android.data.local.entity.HouseholdMemberEntity
import app.lociate.android.data.local.entity.LocusEntity
import app.lociate.android.data.local.entity.UserProfileEntity

@Database(
    entities = [
        LocusEntity::class,
        HouseholdEntity::class,
        HouseholdMemberEntity::class,
        UserProfileEntity::class,
        // US-216: security audit log, matching the iOS AuditLogEntry model.
        AuditLogEntity::class
    ],
    // Bumped from 1 for the audit_log table. A destructive fallback is not an
    // option — it would wipe a user's unsynced voice notes — so the migration in
    // LociateDatabaseMigrations is required.
    version = 2,
    exportSchema = true
)
abstract class LociateDatabase : RoomDatabase() {
    abstract fun locusDao(): LocusDao
    abstract fun householdDao(): HouseholdDao
    abstract fun auditLogDao(): AuditLogDao
}
