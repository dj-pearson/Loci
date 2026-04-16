package com.pearsonmedia.lociate.service

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.Location
import android.os.Looper
import androidx.core.content.ContextCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.Priority
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import timber.log.Timber
import java.util.Locale
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class LocationService(
    private val context: Context,
    private val fusedLocationClient: FusedLocationProviderClient
) {
    private val _currentLocation = MutableStateFlow<Location?>(null)
    val currentLocation: StateFlow<Location?> = _currentLocation.asStateFlow()

    val hasLocationPermission: Boolean
        get() = ContextCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

    val hasBackgroundLocationPermission: Boolean
        get() = ContextCompat.checkSelfPermission(
            context, Manifest.permission.ACCESS_BACKGROUND_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

    suspend fun getLastLocation(): Location? {
        if (!hasLocationPermission) return null

        return suspendCancellableCoroutine { continuation ->
            try {
                fusedLocationClient.lastLocation
                    .addOnSuccessListener { location ->
                        _currentLocation.value = location
                        continuation.resume(location)
                    }
                    .addOnFailureListener { exception ->
                        Timber.e(exception, "Failed to get last location")
                        continuation.resume(null)
                    }
            } catch (e: SecurityException) {
                Timber.e(e, "Security exception getting location")
                continuation.resume(null)
            }
        }
    }

    fun observeLocationUpdates(intervalMs: Long = 10_000L): Flow<Location> = callbackFlow {
        if (!hasLocationPermission) {
            close()
            return@callbackFlow
        }

        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, intervalMs)
            .setMinUpdateIntervalMillis(intervalMs / 2)
            .build()

        val callback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                result.lastLocation?.let { location ->
                    _currentLocation.value = location
                    trySend(location)
                }
            }
        }

        try {
            fusedLocationClient.requestLocationUpdates(request, callback, Looper.getMainLooper())
        } catch (e: SecurityException) {
            Timber.e(e, "Security exception requesting location updates")
            close(e)
        }

        awaitClose {
            fusedLocationClient.removeLocationUpdates(callback)
        }
    }

    suspend fun reverseGeocode(latitude: Double, longitude: Double): String? {
        return try {
            val geocoder = Geocoder(context, Locale.getDefault())
            @Suppress("DEPRECATION")
            val addresses = geocoder.getFromLocation(latitude, longitude, 1)
            addresses?.firstOrNull()?.let { address ->
                buildString {
                    address.thoroughfare?.let { append(it) }
                    address.locality?.let {
                        if (isNotEmpty()) append(", ")
                        append(it)
                    }
                }
            }
        } catch (e: Exception) {
            Timber.e(e, "Reverse geocoding failed")
            null
        }
    }
}
