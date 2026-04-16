package com.pearsonmedia.lociate

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import dagger.hilt.android.HiltAndroidApp
import timber.log.Timber

@HiltAndroidApp
class LociateApplication : Application() {

    override fun onCreate() {
        super.onCreate()

        if (BuildConfig.DEBUG) {
            Timber.plant(Timber.DebugTree())
        }

        createNotificationChannels()
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
