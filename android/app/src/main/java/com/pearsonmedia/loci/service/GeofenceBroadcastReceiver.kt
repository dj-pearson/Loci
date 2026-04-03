package com.pearsonmedia.loci.service

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent
import com.pearsonmedia.loci.LociApplication
import com.pearsonmedia.loci.R
import com.pearsonmedia.loci.ui.MainActivity
import timber.log.Timber

class GeofenceBroadcastReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val geofencingEvent = GeofencingEvent.fromIntent(intent) ?: return

        if (geofencingEvent.hasError()) {
            Timber.e("Geofence error: ${geofencingEvent.errorCode}")
            return
        }

        if (geofencingEvent.geofenceTransition == Geofence.GEOFENCE_TRANSITION_ENTER) {
            val triggeringGeofences = geofencingEvent.triggeringGeofences ?: return

            for (geofence in triggeringGeofences) {
                val locusId = geofence.requestId
                sendNotification(context, locusId)
            }
        }
    }

    private fun sendNotification(context: Context, locusId: String) {
        val deepLinkIntent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            putExtra("locus_id", locusId)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            locusId.hashCode(),
            deepLinkIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, LociApplication.CHANNEL_GEOFENCE)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("You're near a saved locus")
            .setContentText("Tap to listen to your voice note")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setVibrate(longArrayOf(0, 250, 100, 250))
            .build()

        val manager = context.getSystemService(NotificationManager::class.java)
        manager.notify(locusId.hashCode(), notification)
    }
}
