import CoreLocation
import Testing
@testable import Loci

struct HaversineDistanceTests {

    // MARK: - Known Coordinate Pairs

    @Test func newYorkToLosAngeles() {
        // NYC (40.7128, -74.0060) to LA (34.0522, -118.2437)
        // Expected: ~3,944 km
        let meters = HaversineDistance.distance(
            lat1: 40.7128, lon1: -74.0060,
            lat2: 34.0522, lon2: -118.2437
        )
        let km = meters / 1000
        #expect(km > 3930 && km < 3960)
    }

    @Test func londonToTokyo() {
        // London (51.5074, -0.1278) to Tokyo (35.6762, 139.6503)
        // Expected: ~9,560 km
        let meters = HaversineDistance.distance(
            lat1: 51.5074, lon1: -0.1278,
            lat2: 35.6762, lon2: 139.6503
        )
        let km = meters / 1000
        #expect(km > 9550 && km < 9580)
    }

    @Test func samePoint() {
        let meters = HaversineDistance.distance(
            lat1: 40.7128, lon1: -74.0060,
            lat2: 40.7128, lon2: -74.0060
        )
        #expect(meters == 0)
    }

    @Test func shortDistance() {
        // Statue of Liberty (40.6892, -74.0445) to Ellis Island (40.6995, -74.0396)
        // Expected: ~1.16 km
        let meters = HaversineDistance.distance(
            lat1: 40.6892, lon1: -74.0445,
            lat2: 40.6995, lon2: -74.0396
        )
        #expect(meters > 1100 && meters < 1250)
    }

    @Test func antipodal() {
        // North Pole to South Pole: ~20,015 km (half circumference)
        let meters = HaversineDistance.distance(
            lat1: 90, lon1: 0,
            lat2: -90, lon2: 0
        )
        let km = meters / 1000
        #expect(km > 20000 && km < 20030)
    }

    // MARK: - CLLocationCoordinate2D Extension

    @Test func coordinateExtension() {
        let nyc = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
        let la = CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)

        let distance = nyc.distance(to: la)
        let km = distance / 1000
        #expect(km > 3930 && km < 3960)
    }

    @Test func coordinateDistanceToSelf() {
        let point = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
        #expect(point.distance(to: point) == 0)
    }
}
