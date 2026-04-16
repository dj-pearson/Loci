package com.pearsonmedia.lociate.service

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingClient
import com.google.android.gms.location.GeofencingRequest
import com.pearsonmedia.lociate.domain.model.Locus
import com.pearsonmedia.lociate.util.AppConstants
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class GeofenceService @Inject constructor(
    private val context: Context,
    private val geofencingClient: GeofencingClient
) {
    private val geofencePendingIntent: PendingIntent by lazy {
        val intent = Intent(context, GeofenceBroadcastReceiver::class.java).apply {
            action = "com.pearsonmedia.lociate.GEOFENCE_EVENT"
        }
        PendingIntent.getBroadcast(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )
    }

    fun registerGeofences(loci: List<Locus>) {
        if (ContextCompat.checkSelfPermission(
                context, Manifest.permission.ACCESS_FINE_LOCATION
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            Timber.w("Missing location permission for geofences")
            return
        }

        // Android supports up to 100 geofences (vs iOS 20)
        val nearest = loci
            .filter { !it.isArchived }
            .take(AppConstants.MAX_GEOFENCES)

        if (nearest.isEmpty()) return

        val geofences = nearest.map { locus ->
            Geofence.Builder()
                .setRequestId(locus.id.toString())
                .setCircularRegion(
                    locus.latitude,
                    locus.longitude,
                    AppConstants.GEOFENCE_RADIUS_METERS
                )
                .setExpirationDuration(Geofence.NEVER_EXPIRE)
                .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER)
                .build()
        }

        val request = GeofencingRequest.Builder()
            .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
            .addGeofences(geofences)
            .build()

        try {
            geofencingClient.addGeofences(request, geofencePendingIntent)
                .addOnSuccessListener {
                    Timber.d("Registered ${geofences.size} geofences")
                }
                .addOnFailureListener { e ->
                    Timber.e(e, "Failed to register geofences")
                }
        } catch (e: SecurityException) {
            Timber.e(e, "Security exception registering geofences")
        }
    }

    fun removeAllGeofences() {
        geofencingClient.removeGeofences(geofencePendingIntent)
            .addOnSuccessListener { Timber.d("All geofences removed") }
            .addOnFailureListener { e -> Timber.e(e, "Failed to remove geofences") }
    }

    fun removeGeofence(locusId: String) {
        geofencingClient.removeGeofences(listOf(locusId))
            .addOnSuccessListener { Timber.d("Geofence removed: $locusId") }
            .addOnFailureListener { e -> Timber.e(e, "Failed to remove geofence: $locusId") }
    }
}
