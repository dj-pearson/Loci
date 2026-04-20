package app.lociate.android.domain.repository

import app.lociate.android.domain.model.Locus
import app.lociate.android.domain.model.LocusCategory
import kotlinx.coroutines.flow.Flow

interface LocusRepository {
    fun observeAllActive(): Flow<List<Locus>>
    fun observeByCategory(category: LocusCategory): Flow<List<Locus>>
    fun observeById(id: String): Flow<Locus?>
    suspend fun getById(id: String): Locus?
    fun search(query: String): Flow<List<Locus>>
    suspend fun getNearby(lat: Double, lng: Double, limit: Int = 20): List<Locus>
    suspend fun getUnsynced(): List<Locus>
    fun observeActiveCount(): Flow<Int>
    suspend fun save(locus: Locus)
    suspend fun update(locus: Locus)
    suspend fun archive(id: String)
    suspend fun unarchive(id: String)
    suspend fun delete(id: String)
    suspend fun updateSyncStatus(id: String, status: String)
}
