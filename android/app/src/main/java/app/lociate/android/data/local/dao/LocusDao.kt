package app.lociate.android.data.local.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import app.lociate.android.data.local.entity.LocusEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface LocusDao {

    @Query("SELECT * FROM loci WHERE is_archived = 0 ORDER BY created_at DESC")
    fun observeAllActive(): Flow<List<LocusEntity>>

    @Query("SELECT * FROM loci WHERE is_archived = 0 AND category = :category ORDER BY created_at DESC")
    fun observeByCategory(category: String): Flow<List<LocusEntity>>

    @Query("SELECT * FROM loci WHERE id = :id")
    suspend fun getById(id: String): LocusEntity?

    @Query("SELECT * FROM loci WHERE id = :id")
    fun observeById(id: String): Flow<LocusEntity?>

    @Query(
        """
        SELECT * FROM loci
        WHERE is_archived = 0
        AND (transcription LIKE '%' || :query || '%'
             OR location_name LIKE '%' || :query || '%')
        ORDER BY created_at DESC
        """
    )
    fun search(query: String): Flow<List<LocusEntity>>

    @Query(
        """
        SELECT * FROM loci
        WHERE is_archived = 0
        ORDER BY (
            (latitude - :lat) * (latitude - :lat) +
            (longitude - :lng) * (longitude - :lng)
        ) ASC
        LIMIT :limit
        """
    )
    suspend fun getNearby(lat: Double, lng: Double, limit: Int = 20): List<LocusEntity>

    @Query("SELECT * FROM loci WHERE sync_status != 'SYNCED'")
    suspend fun getUnsynced(): List<LocusEntity>

    /**
     * One-shot active loci. US-219: the geofence worker needs a snapshot, not a
     * Flow — a worker that collected a Flow would never complete.
     */
    @Query("SELECT * FROM loci WHERE is_archived = 0")
    suspend fun observeAllActiveOnce(): List<LocusEntity>

    @Query("SELECT COUNT(*) FROM loci WHERE is_archived = 0")
    fun observeActiveCount(): Flow<Int>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(locus: LocusEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(loci: List<LocusEntity>)

    @Update
    suspend fun update(locus: LocusEntity)

    @Query("UPDATE loci SET is_archived = 1, updated_at = :now, sync_status = 'MODIFIED' WHERE id = :id")
    suspend fun archive(id: String, now: Long = System.currentTimeMillis())

    @Query("UPDATE loci SET is_archived = 0, updated_at = :now, sync_status = 'MODIFIED' WHERE id = :id")
    suspend fun unarchive(id: String, now: Long = System.currentTimeMillis())

    @Delete
    suspend fun delete(locus: LocusEntity)

    @Query("DELETE FROM loci WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("UPDATE loci SET sync_status = :status WHERE id = :id")
    suspend fun updateSyncStatus(id: String, status: String)
}
