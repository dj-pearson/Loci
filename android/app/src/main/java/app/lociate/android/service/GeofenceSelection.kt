package app.lociate.android.service

import app.lociate.android.domain.model.Locus
import app.lociate.android.util.AppConstants
import app.lociate.android.util.HaversineDistance

/**
 * Chooses which loci to monitor (US-208).
 *
 * `GeofenceService.registerGeofences` previously did `loci.filter { !isArchived }
 * .take(MAX_GEOFENCES)` on an **unsorted** list. For a user with more than 100
 * loci that monitors an arbitrary 100 — so proximity notifications fire for loci
 * across town while the one the user is standing next to is not registered at all.
 * iOS has always sorted by distance first (its cap is 20, so the bug would have
 * been obvious there much sooner).
 *
 * Extracted as a pure function so the selection is unit-testable without Play
 * Services or a Context.
 */
object GeofenceSelection {

    /**
     * @param loci every candidate locus
     * @param fromLatitude current position, or null if unknown
     * @param fromLongitude current position, or null if unknown
     * @param limit platform cap; Android allows 100 against iOS's 20
     */
    fun select(
        loci: List<Locus>,
        fromLatitude: Double?,
        fromLongitude: Double?,
        limit: Int = AppConstants.MAX_GEOFENCES
    ): List<Locus> {
        val active = loci.filter { !it.isArchived }

        // No fix yet: registering an arbitrary subset is still better than
        // registering nothing, and the next location update re-registers properly.
        if (fromLatitude == null || fromLongitude == null) {
            return active.take(limit)
        }

        return active
            .sortedBy {
                HaversineDistance.calculate(fromLatitude, fromLongitude, it.latitude, it.longitude)
            }
            .take(limit)
    }
}
