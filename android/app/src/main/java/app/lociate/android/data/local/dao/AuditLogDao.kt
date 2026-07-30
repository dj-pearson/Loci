package app.lociate.android.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import app.lociate.android.data.local.entity.AuditLogEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface AuditLogDao {

    @Query("SELECT * FROM audit_log ORDER BY timestamp DESC LIMIT :limit")
    fun observeRecent(limit: Int = 200): Flow<List<AuditLogEntity>>

    @Query("SELECT COUNT(*) FROM audit_log")
    suspend fun count(): Int

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entry: AuditLogEntity)

    /**
     * FIFO trim. The log is a diagnostic aid, not an archive — unbounded growth on
     * a device with no retention policy is a storage leak.
     */
    @Query(
        """
        DELETE FROM audit_log
        WHERE id IN (
            SELECT id FROM audit_log ORDER BY timestamp DESC LIMIT -1 OFFSET :keep
        )
        """
    )
    suspend fun trimTo(keep: Int)

    @Query("DELETE FROM audit_log")
    suspend fun clear()
}
