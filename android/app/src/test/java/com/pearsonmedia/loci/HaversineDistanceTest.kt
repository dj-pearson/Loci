package com.pearsonmedia.loci

import com.google.common.truth.Truth.assertThat
import com.pearsonmedia.loci.util.HaversineDistance
import org.junit.Test

class HaversineDistanceTest {

    @Test
    fun `same point returns zero distance`() {
        val distance = HaversineDistance.calculate(37.7749, -122.4194, 37.7749, -122.4194)
        assertThat(distance).isWithin(0.01).of(0.0)
    }

    @Test
    fun `known distance SF to LA is approximately correct`() {
        // San Francisco to Los Angeles ~559 km
        val distance = HaversineDistance.calculate(
            37.7749, -122.4194,
            34.0522, -118.2437
        )
        val distanceKm = distance / 1000.0
        assertThat(distanceKm).isWithin(10.0).of(559.0)
    }

    @Test
    fun `nearby points return small distance`() {
        // Two points ~100m apart
        val distance = HaversineDistance.calculate(
            37.7749, -122.4194,
            37.7758, -122.4194
        )
        assertThat(distance).isWithin(10.0).of(100.0)
    }

    @Test
    fun `sortByDistance returns nearest items first`() {
        data class TestItem(val lat: Double, val lng: Double)

        val items = listOf(
            TestItem(34.0522, -118.2437),  // LA (far)
            TestItem(37.7850, -122.4094),  // Near SF
            TestItem(40.7128, -74.0060),   // NYC (very far)
            TestItem(37.7749, -122.4194)   // Exact point
        )

        val sorted = HaversineDistance.sortByDistance(
            items = items,
            fromLat = 37.7749,
            fromLon = -122.4194,
            limit = 2,
            latSelector = { it.lat },
            lonSelector = { it.lng }
        )

        assertThat(sorted).hasSize(2)
        assertThat(sorted[0].lat).isEqualTo(37.7749) // Exact match first
        assertThat(sorted[1].lat).isEqualTo(37.7850) // Nearest second
    }
}
