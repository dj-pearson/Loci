package app.lociate.android.data.local

import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

/**
 * Room migrations (US-216).
 *
 * `fallbackToDestructiveMigration` is deliberately never used: an offline-first app
 * holds voice notes that may not have synced yet, and dropping the database would
 * destroy them irrecoverably.
 */
object LociateDatabaseMigrations {

    /** Adds the security audit log table. */
    val MIGRATION_1_2 = object : Migration(1, 2) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL(
                """
                CREATE TABLE IF NOT EXISTS `audit_log` (
                    `id` TEXT NOT NULL,
                    `eventType` TEXT NOT NULL,
                    `emailHash` TEXT NOT NULL,
                    `deviceInfo` TEXT NOT NULL,
                    `appVersion` TEXT NOT NULL,
                    `timestamp` INTEGER NOT NULL,
                    PRIMARY KEY(`id`)
                )
                """.trimIndent()
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS `index_audit_log_timestamp` ON `audit_log` (`timestamp`)"
            )
        }
    }

    val ALL: Array<Migration> = arrayOf(MIGRATION_1_2)
}
