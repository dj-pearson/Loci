package app.lociate.android.service

import android.content.Context
import androidx.hilt.work.HiltWorker
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import app.lociate.android.data.remote.api.SyncRepository
import app.lociate.android.data.remote.api.SyncUploadResult
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import timber.log.Timber
import java.util.concurrent.TimeUnit

/**
 * WorkManager-based background sync worker.
 * Uploads unsynced loci to Supabase when network is available.
 * Compatible with Doze mode — uses WorkManager instead of AlarmManager.
 *
 * US-194: this used to fetch the unsynced rows and mark every one of them
 * SYNCED without uploading anything, so a paying user's notes never left the
 * device while the app reported them backed up. The upload now goes through
 * [SyncRepository], which only advances the sync status once both the audio
 * object and the row have landed.
 */
@HiltWorker
class SyncWorker @AssistedInject constructor(
    @Assisted context: Context,
    @Assisted workerParams: WorkerParameters,
    private val syncRepository: SyncRepository
) : CoroutineWorker(context, workerParams) {

    override suspend fun doWork(): Result {
        val outcome: SyncUploadResult? = try {
            val result = syncRepository.uploadUnsynced()
            result.exceptionOrNull()?.let { Timber.e(it, "Sync upload returned a failure") }
            result.getOrNull()
        } catch (e: Exception) {
            Timber.e(e, "Sync failed")
            null
        }

        return when (SyncDecision.from(outcome, runAttemptCount)) {
            SyncDecision.SUCCESS -> {
                Timber.d("Sync completed")
                Result.success()
            }
            SyncDecision.RETRY -> {
                Timber.w("Sync incomplete — scheduling a retry (attempt $runAttemptCount)")
                Result.retry()
            }
            SyncDecision.FAILURE -> {
                Timber.e("Sync failed after $runAttemptCount attempts — giving up")
                Result.failure()
            }
        }
    }

    companion object {
        private const val SYNC_WORK_NAME = "loci_periodic_sync"
        private const val SYNC_ONCE_TAG = "loci_sync_once"
        const val MAX_ATTEMPTS = 3

        private val networkConstraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()

        /**
         * Schedule periodic sync every 15 minutes when network is available.
         */
        fun schedulePeriodicSync(context: Context) {
            val request = PeriodicWorkRequestBuilder<SyncWorker>(
                15, TimeUnit.MINUTES
            )
                .setConstraints(networkConstraints)
                .setBackoffCriteria(
                    BackoffPolicy.EXPONENTIAL,
                    30, TimeUnit.SECONDS
                )
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                SYNC_WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request
            )
            Timber.d("Periodic sync scheduled")
        }

        /**
         * Trigger a one-time sync immediately (e.g., on pull-to-refresh).
         */
        fun syncNow(context: Context) {
            val request = OneTimeWorkRequestBuilder<SyncWorker>()
                .setConstraints(networkConstraints)
                .addTag(SYNC_ONCE_TAG)
                .build()

            WorkManager.getInstance(context).enqueue(request)
            Timber.d("One-time sync triggered")
        }

        /**
         * Cancel all sync work.
         */
        fun cancelSync(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(SYNC_WORK_NAME)
            Timber.d("Sync work cancelled")
        }
    }
}
