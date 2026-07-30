package app.lociate.android.data.remote.api

import app.lociate.android.data.local.converter.toDomain
import app.lociate.android.data.local.converter.toEntity
import app.lociate.android.data.local.dao.LocusDao
import app.lociate.android.data.remote.SupabaseClientProvider
import app.lociate.android.data.remote.dto.LocusDto
import app.lociate.android.domain.model.SyncStatus
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.storage.storage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import timber.log.Timber
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Outcome of an upload pass, so [app.lociate.android.service.SyncWorker] can
 * choose between success, retry, and failure instead of guessing.
 */
data class SyncUploadResult(
    val uploaded: Int,
    val failed: Int,
    /** True when at least one locus failed and is worth retrying. */
    val retryable: Boolean
) {
    val attempted: Int get() = uploaded + failed
}

@Singleton
class SyncRepository @Inject constructor(
    private val supabaseProvider: SupabaseClientProvider,
    private val locusDao: LocusDao
) {
    private val postgrest get() = supabaseProvider.client.postgrest
    private val storage get() = supabaseProvider.client.storage
    private val auth get() = supabaseProvider.client.auth

    /**
     * Upload all unsynced loci to the Supabase backend.
     *
     * A locus is only marked [SyncStatus.SYNCED] once both the audio object and
     * the row have landed. A failure leaves the row unsynced so the next pass
     * retries it — marking it [SyncStatus.CONFLICTED] on a network blip (as this
     * used to) is wrong: a conflict is a merge problem, not a transport problem,
     * and `getUnsynced()` would keep returning it with no way to tell the two
     * apart.
     */
    suspend fun uploadUnsynced(): Result<SyncUploadResult> = withContext(Dispatchers.IO) {
        try {
            val unsynced = locusDao.getUnsynced()
            if (unsynced.isEmpty()) {
                return@withContext Result.success(SyncUploadResult(0, 0, retryable = false))
            }

            val userId = auth.currentSessionOrNull()?.user?.id
            if (userId == null) {
                // Not signed in. Sync is additive, so this is not an error —
                // leave everything pending for after the next sign-in.
                Timber.d("Skipping sync upload — no authenticated session")
                return@withContext Result.success(SyncUploadResult(0, 0, retryable = false))
            }

            var uploaded = 0
            var failed = 0
            var retryable = false

            for (entity in unsynced) {
                try {
                    val locus = entity.toDomain()

                    // 1. Audio object. Bucket and path must match what iOS writes
                    //    and what the storage RLS policy in 005_storage_bucket.sql
                    //    enforces — the first path segment has to be the user id,
                    //    or INSERT is denied outright.
                    val audioFile = File(locus.audioFilePath)
                    if (audioFile.exists()) {
                        storage.from(AUDIO_BUCKET).upload(
                            path = remoteAudioPath(userId, locus.id.toString()),
                            data = audioFile.readBytes()
                        ) {
                            // Idempotent: a retry after a partial pass overwrites
                            // instead of failing with "object already exists".
                            upsert = true
                        }
                    } else {
                        Timber.w("Audio file missing for locus ${entity.id}; uploading row only")
                    }

                    // 2. Row — only after the audio is durable, so a household
                    //    member never sees a locus whose audio 404s.
                    postgrest.from("loci").upsert(LocusDto.fromDomain(locus))

                    // 3. Local status, only now that both steps succeeded.
                    locusDao.updateSyncStatus(entity.id, SyncStatus.SYNCED.name)
                    uploaded++
                } catch (e: Exception) {
                    // A per-locus failure must not abort the batch: one unreadable
                    // file should not block every other pending note.
                    Timber.e(e, "Failed to sync locus ${entity.id}")
                    failed++
                    retryable = true
                }
            }

            Timber.d("Sync upload: $uploaded ok, $failed failed of ${unsynced.size}")
            Result.success(SyncUploadResult(uploaded, failed, retryable))
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

    companion object {
        /**
         * Created by backend/migrations/005_storage_bucket.sql. The previous
         * value ("audio") named a bucket that does not exist, so every Android
         * audio upload failed even once the worker started calling this at all.
         */
        const val AUDIO_BUCKET = "loci-audio"

        /**
         * Matches the iOS `AudioSyncService` layout exactly — a household member
         * on the other platform has to resolve the same object.
         */
        fun remoteAudioPath(userId: String, locusId: String): String = "$userId/$locusId.m4a"
    }
}
