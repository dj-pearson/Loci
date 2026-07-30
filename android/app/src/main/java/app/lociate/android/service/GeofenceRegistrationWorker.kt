package app.lociate.android.service

import android.content.Context
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import app.lociate.android.data.local.converter.toDomain
import app.lociate.android.data.local.dao.LocusDao
import app.lociate.android.widget.WidgetDataSource
import app.lociate.android.util.SecurePreferences
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import timber.log.Timber

/**
 * Registers proximity geofences (US-219).
 *
 * `GeofenceService.registerGeofences` existed but had **no callers anywhere** — so
 * proximity-triggered notifications, the app's core feature, never worked on
 * Android. `BootReceiver` logged "geofences will be re-registered on next app
 * launch", but nothing on launch registered them either.
 *
 * A worker rather than an inline call, because registration has to survive a reboot
 * and a process death: geofences are a system-level registration the app has to
 * re-assert, and doing it only while a ViewModel happens to be alive is how it went
 * missing in the first place.
 */
@HiltWorker
class GeofenceRegistrationWorker @AssistedInject constructor(
    @Assisted context: Context,
    @Assisted workerParams: WorkerParameters,
    private val locusDao: LocusDao,
    private val geofenceService: GeofenceService,
    private val securePreferences: SecurePreferences,
) : CoroutineWorker(context, workerParams) {

    override suspend fun doWork(): Result {
        return try {
            val loci = locusDao.observeAllActiveOnce().map { it.toDomain() }
            if (loci.isEmpty()) {
                Timber.d("No active loci — nothing to register")
                return Result.success()
            }

            // Reuses the coordinate the widget already persists, so nearest-first
            // selection works even before a fresh location fix arrives.
            val latitude = securePreferences
                .getString(WidgetDataSource.KEY_LAST_LATITUDE)?.toDoubleOrNull()
            val longitude = securePreferences
                .getString(WidgetDataSource.KEY_LAST_LONGITUDE)?.toDoubleOrNull()

            geofenceService.registerGeofences(
                loci = loci,
                fromLatitude = latitude,
                fromLongitude = longitude
            )

            Timber.d("Registered geofences for ${loci.size} loci")
            Result.success()
        } catch (e: Exception) {
            Timber.e(e, "Geofence registration failed")
            if (runAttemptCount < MAX_ATTEMPTS) Result.retry() else Result.failure()
        }
    }

    companion object {
        private const val WORK_NAME = "loci_geofence_registration"
        private const val MAX_ATTEMPTS = 3

        /**
         * Re-registers geofences. Safe to call often — REPLACE coalesces bursts, so
         * saving several loci in a row does not queue redundant work.
         */
        fun enqueue(context: Context) {
            WorkManager.getInstance(context).enqueueUniqueWork(
                WORK_NAME,
                ExistingWorkPolicy.REPLACE,
                OneTimeWorkRequestBuilder<GeofenceRegistrationWorker>().build()
            )
        }
    }
}
