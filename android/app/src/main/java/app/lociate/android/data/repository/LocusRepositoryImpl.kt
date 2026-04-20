package app.lociate.android.data.repository

import app.lociate.android.data.local.converter.toDomain
import app.lociate.android.data.local.converter.toEntity
import app.lociate.android.data.local.dao.LocusDao
import app.lociate.android.domain.model.Locus
import app.lociate.android.domain.model.LocusCategory
import app.lociate.android.domain.repository.LocusRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class LocusRepositoryImpl @Inject constructor(
    private val locusDao: LocusDao
) : LocusRepository {

    override fun observeAllActive(): Flow<List<Locus>> =
        locusDao.observeAllActive().map { entities -> entities.map { it.toDomain() } }

    override fun observeByCategory(category: LocusCategory): Flow<List<Locus>> =
        locusDao.observeByCategory(category.name).map { entities -> entities.map { it.toDomain() } }

    override fun observeById(id: String): Flow<Locus?> =
        locusDao.observeById(id).map { it?.toDomain() }

    override suspend fun getById(id: String): Locus? =
        locusDao.getById(id)?.toDomain()

    override fun search(query: String): Flow<List<Locus>> =
        locusDao.search(query).map { entities -> entities.map { it.toDomain() } }

    override suspend fun getNearby(lat: Double, lng: Double, limit: Int): List<Locus> =
        locusDao.getNearby(lat, lng, limit).map { it.toDomain() }

    override suspend fun getUnsynced(): List<Locus> =
        locusDao.getUnsynced().map { it.toDomain() }

    override fun observeActiveCount(): Flow<Int> =
        locusDao.observeActiveCount()

    override suspend fun save(locus: Locus) {
        locusDao.insert(locus.toEntity())
    }

    override suspend fun update(locus: Locus) {
        locusDao.update(locus.toEntity())
    }

    override suspend fun archive(id: String) {
        locusDao.archive(id)
    }

    override suspend fun unarchive(id: String) {
        locusDao.unarchive(id)
    }

    override suspend fun delete(id: String) {
        locusDao.deleteById(id)
    }

    override suspend fun updateSyncStatus(id: String, status: String) {
        locusDao.updateSyncStatus(id, status)
    }
}
