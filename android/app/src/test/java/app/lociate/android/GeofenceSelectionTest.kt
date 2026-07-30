package app.lociate.android

import app.lociate.android.domain.model.Locus
import app.lociate.android.service.GeofenceSelection
import app.lociate.android.util.AppConstants
import com.google.common.truth.Truth.assertThat
import org.junit.Test
import java.util.UUID

/**
 * US-208/US-219: geofence selection had two independent defects — it took an
 * arbitrary 100 loci from an unsorted list, and nothing ever called the registration
 * code at all. These pin the selection contract.
 */
class GeofenceSelectionTest {

    private val originLat = 40.7608
    private val originLon = -111.8910

    /** Roughly `metres` north of the origin; 1 degree of latitude is ~111 km. */
    private fun locus(metresNorth: Double, name: String, archived: Boolean = false) = Locus(
        id = UUID.randomUUID(),
        latitude = originLat + metresNorth / 111_000,
        longitude = originLon,
        locationName = name,
        audioFilePath = "/tmp/$name.m4a",
        transcription = name,
        isArchived = archived
    )

    @Test
    fun `never selects more than the Android cap`() {
        val loci = (1..250).map { locus(it * 100.0, "l$it") }

        val selected = GeofenceSelection.select(loci, originLat, originLon)

        assertThat(selected).hasSize(AppConstants.MAX_GEOFENCES)
        assertThat(AppConstants.MAX_GEOFENCES).isEqualTo(100)
    }

    @Test
    fun `selects the nearest loci, not an arbitrary subset`() {
        // Insertion order is reversed relative to distance, so the previous
        // implementation — a plain .take() on an unsorted list — would have picked
        // the farthest 100 and left the closest unmonitored.
        val loci = (1..150).reversed().map { locus(it * 100.0, "l$it") }

        val names = GeofenceSelection.select(loci, originLat, originLon)
            .mapNotNull { it.locationName }

        assertThat(names.first()).isEqualTo("l1")
        assertThat(names).contains("l100")
        assertThat(names).doesNotContain("l101")
    }

    @Test
    fun `orders by ascending distance`() {
        val loci = listOf(
            locus(5_000.0, "far"),
            locus(100.0, "near"),
            locus(1_000.0, "mid"),
        )

        assertThat(GeofenceSelection.select(loci, originLat, originLon).mapNotNull { it.locationName })
            .containsExactly("near", "mid", "far")
            .inOrder()
    }

    @Test
    fun `excludes archived loci`() {
        val loci = listOf(
            locus(100.0, "active"),
            locus(200.0, "archived", archived = true),
        )

        assertThat(GeofenceSelection.select(loci, originLat, originLon).mapNotNull { it.locationName })
            .containsExactly("active")
    }

    @Test
    fun `falls back to an arbitrary subset when no location is known`() {
        // Registering something beats registering nothing; the next location update
        // re-registers with proper ordering.
        val loci = (1..150).map { locus(it * 100.0, "l$it") }

        val selected = GeofenceSelection.select(loci, fromLatitude = null, fromLongitude = null)

        assertThat(selected).hasSize(AppConstants.MAX_GEOFENCES)
    }

    @Test
    fun `handles an empty input`() {
        assertThat(GeofenceSelection.select(emptyList(), originLat, originLon)).isEmpty()
    }

    @Test
    fun `returns everything when under the cap`() {
        val loci = (1..5).map { locus(it * 100.0, "l$it") }

        assertThat(GeofenceSelection.select(loci, originLat, originLon)).hasSize(5)
    }

    @Test
    fun `the monitored set follows the user`() {
        // The point of nearest-first: after the user moves, a different set is
        // monitored, or a locus at the new location never triggers.
        val loci = (1..150).map { locus(it * 500.0, "l$it") }

        val atOrigin = GeofenceSelection.select(loci, originLat, originLon).map { it.id }.toSet()
        val movedNorth = GeofenceSelection.select(
            loci,
            fromLatitude = originLat + 40_000 / 111_000.0,
            fromLongitude = originLon
        ).map { it.id }.toSet()

        assertThat(atOrigin).isNotEqualTo(movedNorth)
    }

    @Test
    fun `Android cap is larger than the iOS cap`() {
        // Documents the intentional platform difference: iOS allows 20 regions,
        // Android 100. A copy-paste of the iOS constant would silently under-monitor.
        assertThat(AppConstants.MAX_GEOFENCES).isGreaterThan(20)
    }
}
