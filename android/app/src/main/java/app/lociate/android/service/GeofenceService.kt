package app.lociate.android.service

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingClient
import com.google.android.gms.location.GeofencingRequest
import app.lociate.android.domain.model.Locus
import app.lociate.android.util.AppConstants
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
            action = "app.lociate.android.GEOFENCE_EVENT"
        }
        PendingIntent.getBroadcast(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )
    }

    /**
     * @param fromLatitude / [fromLongitude] the device's current position. Required
     *   for nearest-first selection — see [GeofenceSelection].
     */
    fun registerGeofences(
        loci: List<Locus>,
        fromLatitude: Double? = null,
        fromLongitude: Double? = null
    ) {
        if (ContextCompat.checkSelfPermission(
                context, Manifest.permission.ACCESS_FINE_LOCATION
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            Timber.w("Missing location permission for geofences")
            return
        }

        // US-208: nearest-first. This used to `.take(MAX_GEOFENCES)` from an
        // unsorted list, so a user with more than 100 loci had an arbitrary subset
        // monitored — notifications for loci across town, silence for the one they
        // were standing next to.
        val nearest = GeofenceSelection.select(
            loci = loci,
            fromLatitude = fromLatitude,
            fromLongitude = fromLongitude
        )

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
