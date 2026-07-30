package app.lociate.android

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import app.lociate.android.service.GeofenceRegistrationWorker
import app.lociate.android.service.PushRegistrationService
import app.lociate.android.service.SyncWorker
import app.lociate.android.util.CrashReporting
import dagger.hilt.android.HiltAndroidApp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject

@HiltAndroidApp
class LociateApplication : Application() {

    @Inject
    lateinit var pushRegistrationService: PushRegistrationService

    private val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onCreate() {
        super.onCreate()

        if (BuildConfig.DEBUG) {
            Timber.plant(Timber.DebugTree())
        }

        // US-199: first, so a crash anywhere in the rest of startup is reported.
        CrashReporting.initialize(this)

        createNotificationChannels()

        // US-197: request the FCM token and flush anything queued from a previous
        // session that could not reach the server. Off the main thread — this does
        // network I/O and must not delay first frame.
        if (BuildConfig.FCM_ENABLED) {
            applicationScope.launch {
                pushRegistrationService.registerForPush()
                pushRegistrationService.syncPendingToken()
            }
        } else {
            Timber.i("FCM disabled in this build — no google-services.json")
        }

        // US-219: proximity notifications are the whole point of the app, and
        // nothing registered geofences anywhere. Registering on every cold start
        // re-asserts them after a reboot, a force-stop, or a permission change.
        GeofenceRegistrationWorker.enqueue(this)

        // US-194: the sync worker was never scheduled either, so even a working
        // upload would only have run on an explicit pull-to-refresh.
        SyncWorker.schedulePeriodicSync(this)
    }

    private fun createNotificationChannels() {
        val manager = getSystemService(NotificationManager::class.java)

        val geofenceChannel = NotificationChannel(
            CHANNEL_GEOFENCE,
            "Nearby Loci",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Notifications when you return to a saved location"
            enableVibration(true)
        }

        val syncChannel = NotificationChannel(
            CHANNEL_SYNC,
            "Sync Status",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Background sync progress"
        }

        val recordingChannel = NotificationChannel(
            CHANNEL_RECORDING,
            "Recording",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Active voice recording indicator"
        }

        manager.createNotificationChannels(
            listOf(geofenceChannel, syncChannel, recordingChannel)
        )
    }

    companion object {
        const val CHANNEL_GEOFENCE = "geofence_notifications"
        const val CHANNEL_SYNC = "sync_notifications"
        const val CHANNEL_RECORDING = "recording_notifications"
    }
}
