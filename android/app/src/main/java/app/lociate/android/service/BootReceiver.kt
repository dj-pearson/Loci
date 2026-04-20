package com.pearsonmedia.lociate.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import timber.log.Timber

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            Timber.d("Boot completed — geofences will be re-registered on next app launch")
            // Geofences are re-registered when the app opens and loads loci.
            // For persistent background geofencing, use WorkManager to schedule re-registration.
        }
    }
}
