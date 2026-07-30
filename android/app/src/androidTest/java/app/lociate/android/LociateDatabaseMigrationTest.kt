package app.lociate.android

import androidx.room.testing.MigrationTestHelper
import androidx.sqlite.db.framework.FrameworkSQLiteOpenHelperFactory
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.lociate.android.data.local.LociateDatabase
import app.lociate.android.data.local.LociateDatabaseMigrations
import com.google.common.truth.Truth.assertThat
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.IOException

/**
 * US-208/US-216: the database was configured with `fallbackToDestructiveMigration()`,
 * which drops and recreates every table on any schema change. In an offline-first
 * app that silently destroys voice notes that had not synced yet.
 *
 * This proves the 1 -> 2 migration preserves existing rows. It needs a device or
 * emulator because Room's schema validation runs against real SQLite.
 */
@RunWith(AndroidJUnit4::class)
class LociateDatabaseMigrationTest {

    private val databaseName = "migration-test.db"

    @get:Rule
    val helper = MigrationTestHelper(
        InstrumentationRegistry.getInstrumentation(),
        LociateDatabase::class.java,
        emptyList(),
        FrameworkSQLiteOpenHelperFactory()
    )

    @Test
    @Throws(IOException::class)
    fun migrate1To2_preservesExistingLoci() {
        // A version-1 database holding one unsynced recording — exactly the row a
        // destructive migration would have thrown away.
        helper.createDatabase(databaseName, 1).use { db ->
            db.execSQL(
                """
                INSERT INTO loci (
                    id, latitude, longitude, location_name, audio_file_path,
                    transcription, category, is_shared, created_by_name, household_id,
                    created_at, updated_at, is_archived, sync_status
                ) VALUES (
                    'locus-1', 40.7608, -111.8910, 'Home', '/data/audio/locus-1.m4a',
                    'spare key under the mat', 'HOME', 0, NULL, NULL,
                    1700000000000, 1700000000000, 0, 'PENDING'
                )
                """.trimIndent()
            )
        }

        val migrated = helper.runMigrationsAndValidate(
            databaseName,
            2,
            true,
            *LociateDatabaseMigrations.ALL
        )

        migrated.query("SELECT transcription, sync_status FROM loci WHERE id = 'locus-1'")
            .use { cursor ->
                assertThat(cursor.moveToFirst()).isTrue()
                assertThat(cursor.getString(0)).isEqualTo("spare key under the mat")
                // Still unsynced: the migration must not have altered sync state.
                assertThat(cursor.getString(1)).isEqualTo("PENDING")
            }
    }

    @Test
    @Throws(IOException::class)
    fun migrate1To2_createsTheAuditLogTable() {
        helper.createDatabase(databaseName, 1).close()

        val migrated = helper.runMigrationsAndValidate(
            databaseName,
            2,
            true,
            *LociateDatabaseMigrations.ALL
        )

        migrated.query(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'audit_log'"
        ).use { cursor ->
            assertThat(cursor.moveToFirst()).isTrue()
        }
    }
}
