import CoreLocation
import Foundation

// MARK: - Haversine Distance

enum HaversineDistance {
    private static let earthRadiusMeters: Double = 6_371_000

    /// Calculates the great-circle distance between two GPS coordinates using the Haversine formula.
    /// - Returns: Distance in meters.
    static func distance(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double
    ) -> Double {
        let dLat = (lat2 - lat1).degreesToRadians
        let dLon = (lon2 - lon1).degreesToRadians

        let lat1Rad = lat1.degreesToRadians
        let lat2Rad = lat2.degreesToRadians

        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1Rad) * cos(lat2Rad) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))

        return earthRadiusMeters * c
    }
}

// MARK: - Double Extension

private extension Double {
    var degreesToRadians: Double { self * .pi / 180 }
}

// MARK: - CLLocationCoordinate2D Extension

extension CLLocationCoordinate2D {
    /// Returns the Haversine distance in meters to another coordinate.
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        HaversineDistance.distance(
            lat1: latitude, lon1: longitude,
            lat2: other.latitude, lon2: other.longitude
        )
    }
}

// MARK: - Array<Locus> Extensions

extension Array where Element: Locus {
    /// Returns the array sorted by ascending distance from the given coordinate.
    func sortedByDistance(from coordinate: CLLocationCoordinate2D) -> [Locus] {
        sorted { lhs, rhs in
            lhs.coordinate.distance(to: coordinate) < rhs.coordinate.distance(to: coordinate)
        }
    }

    /// Returns the nearest `count` loci to the given coordinate, sorted by distance.
    func nearest(_ count: Int, to coordinate: CLLocationCoordinate2D) -> [Locus] {
        Array<Locus>(sortedByDistance(from: coordinate).prefix(count))
    }
}
