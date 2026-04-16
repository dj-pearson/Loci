package com.pearsonmedia.lociate.util

import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

object HaversineDistance {

    private const val EARTH_RADIUS_METERS = 6_371_000.0

    /**
     * Calculate distance in meters between two GPS coordinates using Haversine formula.
     */
    fun calculate(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)

        val a = sin(dLat / 2).pow(2) +
                cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) *
                sin(dLon / 2).pow(2)

        val c = 2 * atan2(sqrt(a), sqrt(1 - a))

        return EARTH_RADIUS_METERS * c
    }

    /**
     * Sort loci by distance from a given coordinate, return the nearest [limit].
     */
    fun <T> sortByDistance(
        items: List<T>,
        fromLat: Double,
        fromLon: Double,
        limit: Int = 20,
        latSelector: (T) -> Double,
        lonSelector: (T) -> Double
    ): List<T> {
        return items
            .sortedBy { calculate(fromLat, fromLon, latSelector(it), lonSelector(it)) }
            .take(limit)
    }
}
