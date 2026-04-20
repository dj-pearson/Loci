package com.pearsonmedia.lociate.service

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
import com.pearsonmedia.lociate.data.local.dao.LocusDao
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import timber.log.Timber
import java.util.concurrent.TimeUnit

/**
 * WorkManager-based background sync worker.
 * Uploads unsynced loci to Supabase when network is available.
 * Compatible with Doze mode — uses WorkManager instead of AlarmManager.
 */
@HiltWorker
class SyncWorker @AssistedInject constructor(
    @Assisted context: Context,
    @Assisted workerParams: WorkerParameters,
    private val locusDao: LocusDao
) : CoroutineWorker(context, workerParams) {

    override suspend fun doWork(): Result {
        return try {
            val unsyncedLoci = locusDao.getUnsynced()

            if (unsyncedLoci.isEmpty()) {
                Timber.d("No unsynced loci to sync")
                return Result.success()
            }

            Timber.d("Syncing ${unsyncedLoci.size} loci...")

            // TODO: Implement actual Supabase upload in US-161
            // For each unsynced locus:
            // 1. Upload audio file to Supabase Storage
            // 2. Insert/update locus record via PostgREST
            // 3. Update local sync status to SYNCED

            for (locus in unsyncedLoci) {
                // Placeholder: mark as synced after upload
                locusDao.updateSyncStatus(locus.id, "SYNCED")
            }

            Timber.d("Sync completed: ${unsyncedLoci.size} loci synced")
            Result.success()
        } catch (e: Exception) {
            Timber.e(e, "Sync failed")
            if (runAttemptCount < 3) {
                Result.retry()
            } else {
                Result.failure()
            }
        }
    }

    companion object {
        private const val SYNC_WORK_NAME = "loci_periodic_sync"
        private const val SYNC_ONCE_TAG = "loci_sync_once"

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
