package app.lociate.android.widget

import app.lociate.android.data.local.dao.HouseholdDao
import app.lociate.android.data.local.dao.LocusDao
import app.lociate.android.domain.model.SubscriptionTier
import app.lociate.android.util.HaversineDistance
import app.lociate.android.util.SecurePreferences
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.roundToInt

/** One row in the widget. Flattened so the Glance layer touches no domain types. */
data class WidgetLocus(
    val id: String,
    val title: String,
    val transcription: String,
    val distanceMeters: Double,
) {
    /** Mirrors the iOS `NearbyLocusData.formattedDistance`. */
    val formattedDistance: String
        get() = if (distanceMeters < 1000) {
            "${distanceMeters.roundToInt()}m"
        } else {
            String.format("%.1fkm", distanceMeters / 1000)
        }
}

data class WidgetSnapshot(
    val isPremium: Boolean,
    val loci: List<WidgetLocus>,
)

/**
 * Loads widget content from Room only (US-213).
 *
 * A widget update that hit the network would drain battery and could stall the
 * host launcher, so this reads the last known coordinate from preferences and the
 * loci from the local database — exactly what the iOS timeline provider does.
 */
@Singleton
class WidgetDataSource @Inject constructor(
    private val locusDao: LocusDao,
    private val householdDao: HouseholdDao,
    private val securePreferences: SecurePreferences,
) {
    suspend fun load(limit: Int = MAX_ROWS): WidgetSnapshot {
        val tier = runCatching {
            SubscriptionTier.valueOf(
                householdDao.getUserProfile()?.subscriptionTier ?: SubscriptionTier.FREE.name
            )
        }.getOrDefault(SubscriptionTier.FREE)

        // Gate before reading any loci: a free-tier widget shows an upgrade prompt,
        // so loading content would be wasted work and a needless data exposure.
        if (tier == SubscriptionTier.FREE) {
            return WidgetSnapshot(isPremium = false, loci = emptyList())
        }

        val latitude = securePreferences.getString(KEY_LAST_LATITUDE)?.toDoubleOrNull()
        val longitude = securePreferences.getString(KEY_LAST_LONGITUDE)?.toDoubleOrNull()
        if (latitude == null || longitude == null) {
            return WidgetSnapshot(isPremium = true, loci = emptyList())
        }

        // getNearby orders by squared-degree distance, which is a good enough
        // prefilter; the exact Haversine ordering is applied to the shortlist so the
        // displayed distances and the ordering agree.
        val candidates = locusDao.getNearby(latitude, longitude, limit = limit * 5)

        return WidgetSnapshot(
            isPremium = true,
            loci = candidates
                .map { entity ->
                    val distance = HaversineDistance.calculate(
                        latitude, longitude, entity.latitude, entity.longitude
                    )
                    WidgetLocus(
                        id = entity.id,
                        title = entity.locationName?.takeIf { it.isNotBlank() }
                            ?: entity.category,
                        transcription = entity.transcription,
                        distanceMeters = distance,
                    )
                }
                .sortedBy { it.distanceMeters }
                .take(limit)
        )
    }

    companion object {
        /** Matches the iOS widget's three rows. */
        const val MAX_ROWS = 3

        /**
         * Written by the location service. Shared with the widget through
         * SecurePreferences rather than a plain SharedPreferences file, because a
         * coordinate is location data.
         */
        const val KEY_LAST_LATITUDE = "widget_last_latitude"
        const val KEY_LAST_LONGITUDE = "widget_last_longitude"
    }
}

/**
 * Glance workers run outside any injected component, so the data source is
 * resolved through a Hilt entry point rather than constructor injection.
 */
@EntryPoint
@InstallIn(SingletonComponent::class)
interface WidgetEntryPoint {
    fun widgetDataSource(): WidgetDataSource
}
