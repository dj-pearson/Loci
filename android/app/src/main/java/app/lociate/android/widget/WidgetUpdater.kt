package app.lociate.android.widget

import android.content.Context
import androidx.glance.appwidget.updateAll
import app.lociate.android.util.SecurePreferences
import dagger.hilt.android.qualifiers.ApplicationContext
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Feeds the widget (US-213).
 *
 * Two responsibilities, kept together because they always happen as a pair: store
 * the coordinate the widget reads, and ask Glance to recompose. The iOS widget gets
 * the equivalent through the App Group plus
 * `WidgetCenter.shared.reloadAllTimelines()`.
 */
@Singleton
class WidgetUpdater @Inject constructor(
    @ApplicationContext private val context: Context,
    private val securePreferences: SecurePreferences,
) {
    /**
     * Records the device's latest coordinate.
     *
     * Stored as a string because [SecurePreferences] has no double accessor, and
     * kept in encrypted preferences rather than a plain file — a coordinate is
     * location data, and any app that could read it would learn where the user is.
     */
    fun recordLocation(latitude: Double, longitude: Double) {
        securePreferences.putString(WidgetDataSource.KEY_LAST_LATITUDE, latitude.toString())
        securePreferences.putString(WidgetDataSource.KEY_LAST_LONGITUDE, longitude.toString())
    }

    /**
     * Asks every placed widget to recompose.
     *
     * Suspending and failure-tolerant: a widget refresh must never take down the
     * caller, which is usually a save flow the user is waiting on.
     */
    suspend fun requestUpdate() {
        try {
            NearbyLociWidget().updateAll(context)
        } catch (e: Exception) {
            Timber.w(e, "Widget update failed")
        }
    }

    /** Convenience for the common case: new coordinate, then refresh. */
    suspend fun onLocationChanged(latitude: Double, longitude: Double) {
        recordLocation(latitude, longitude)
        requestUpdate()
    }
}
