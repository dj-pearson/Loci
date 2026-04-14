package com.pearsonmedia.loci.data.remote.api

import com.pearsonmedia.loci.data.local.converter.toDomain
import com.pearsonmedia.loci.data.local.converter.toEntity
import com.pearsonmedia.loci.data.local.dao.LocusDao
import com.pearsonmedia.loci.data.remote.SupabaseClientProvider
import com.pearsonmedia.loci.data.remote.dto.LocusDto
import com.pearsonmedia.loci.domain.model.SyncStatus
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.storage.storage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import timber.log.Timber
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SyncRepository @Inject constructor(
    private val supabaseProvider: SupabaseClientProvider,
    private val locusDao: LocusDao
) {
    private val postgrest get() = supabaseProvider.client.postgrest
    private val storage get() = supabaseProvider.client.storage

    /**
     * Upload all unsynced loci to the Supabase backend.
     */
    suspend fun uploadUnsynced(): Result<Int> = withContext(Dispatchers.IO) {
        try {
            val unsynced = locusDao.getUnsynced()
            if (unsynced.isEmpty()) return@withContext Result.success(0)

            var successCount = 0
            for (entity in unsynced) {
                try {
                    val locus = entity.toDomain()

                    // 1. Upload audio file to Supabase Storage
                    val audioFile = File(locus.audioFilePath)
                    if (audioFile.exists()) {
                        val bucket = storage.from("audio")
                        val storagePath = "loci/${locus.id}/${audioFile.name}"
                        bucket.upload(storagePath, audioFile.readBytes())
                    }

                    // 2. Upsert locus record via PostgREST
                    val dto = LocusDto.fromDomain(locus)
                    postgrest.from("loci").upsert(dto)

                    // 3. Mark as synced locally
                    locusDao.updateSyncStatus(entity.id, SyncStatus.SYNCED.name)
                    successCount++
                } catch (e: Exception) {
                    Timber.e(e, "Failed to sync locus: ${entity.id}")
                    locusDao.updateSyncStatus(entity.id, SyncStatus.CONFLICTED.name)
                }
            }

            Timber.d("Sync completed: $successCount/${unsynced.size} loci uploaded")
            Result.success(successCount)
        } catch (e: Exception) {
            Timber.e(e, "Sync upload failed")
            Result.failure(e)
        }
    }

    /**
     * Download remote loci and merge with local database.
     */
    suspend fun downloadAndMerge(): Result<Int> = withContext(Dispatchers.IO) {
        try {
            val remoteLoci = postgrest.from("loci")
                .select()
                .decodeList<LocusDto>()

            var mergedCount = 0
            for (dto in remoteLoci) {
                val localEntity = locusDao.getById(dto.id)
                if (localEntity == null) {
                    // New remote locus — insert locally
                    locusDao.insert(dto.toEntity())
                    mergedCount++
                } else if (dto.updatedAt > localEntity.updatedAt &&
                    localEntity.syncStatus != "MODIFIED"
                ) {
                    // Remote is newer and local hasn't been modified — update
                    locusDao.update(dto.toEntity())
                    mergedCount++
                }
                // If local is modified, keep local version (upload will handle it)
            }

            Timber.d("Download merge completed: $mergedCount new/updated loci")
            Result.success(mergedCount)
        } catch (e: Exception) {
            Timber.e(e, "Download merge failed")
            Result.failure(e)
        }
    }
}
