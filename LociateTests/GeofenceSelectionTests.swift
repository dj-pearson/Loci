import CoreLocation
import XCTest

@testable import Lociate

/// US-205: iOS hard-caps an app at 20 monitored regions. Exceeding it does not
/// error — the extra regions are silently dropped, so proximity notifications
/// stop firing for whichever loci lost the race. The nearest-rotation selection
/// that avoids this had no coverage.
final class GeofenceSelectionTests: XCTestCase {

    private let origin = CLLocationCoordinate2D(latitude: 40.7608, longitude: -111.8910)

    /// Builds a locus roughly `metres` north of `origin`. 1 degree of latitude is
    /// ~111 km, which is close enough for ordering assertions.
    private func locus(metresNorth metres: Double, name: String) -> Locus {
        Locus(
            latitude: origin.latitude + metres / 111_000,
            longitude: origin.longitude,
            locationName: name,
            audioFileURL: "/tmp/\(name).m4a",
            transcription: name
        )
    }

    // MARK: - The 20-region cap

    func testNeverSelectsMoreThanTheSystemCap() {
        let loci = (1...60).map { locus(metresNorth: Double($0) * 100, name: "l\($0)") }

        let selected = loci.nearest(AppConstants.maxGeofences, to: origin)

        XCTAssertEqual(selected.count, AppConstants.maxGeofences)
        XCTAssertEqual(AppConstants.maxGeofences, 20, "iOS allows at most 20 regions per app")
    }

    func testReturnsEverythingWhenUnderTheCap() {
        let loci = (1...5).map { locus(metresNorth: Double($0) * 100, name: "l\($0)") }

        XCTAssertEqual(loci.nearest(AppConstants.maxGeofences, to: origin).count, 5)
    }

    func testEmptyInputSelectsNothing() {
        XCTAssertTrue([Locus]().nearest(AppConstants.maxGeofences, to: origin).isEmpty)
    }

    // MARK: - Nearest wins

    func testSelectsTheNearestLociNotAnArbitrarySubset() {
        // Insertion order is deliberately reversed relative to distance, so a
        // selection that just truncated the input would pick the farthest.
        let loci = (1...40).reversed().map { locus(metresNorth: Double($0) * 100, name: "l\($0)") }

        let selected = loci.nearest(AppConstants.maxGeofences, to: origin)
        let names = selected.compactMap(\.locationName)

        XCTAssertEqual(names.first, "l1", "closest locus must be selected first")
        for index in 1...AppConstants.maxGeofences {
            XCTAssertTrue(names.contains("l\(index)"), "l\(index) is within the nearest 20")
        }
        XCTAssertFalse(names.contains("l21"), "the 21st-nearest must be excluded")
    }

    func testSelectionIsOrderedByAscendingDistance() {
        let loci = [
            locus(metresNorth: 5000, name: "far"),
            locus(metresNorth: 100, name: "near"),
            locus(metresNorth: 1000, name: "mid"),
        ]

        XCTAssertEqual(
            loci.nearest(3, to: origin).compactMap(\.locationName),
            ["near", "mid", "far"]
        )
    }

    func testRotationFollowsTheUserRatherThanStickingToTheFirstSet() {
        // The whole point of nearest-rotation: after the user moves, the monitored
        // set must change, or a locus at the new location never triggers.
        let loci = (1...40).map { locus(metresNorth: Double($0) * 500, name: "l\($0)") }

        let atOrigin = Set(loci.nearest(AppConstants.maxGeofences, to: origin).map(\.id))
        let movedNorth = CLLocationCoordinate2D(
            latitude: origin.latitude + 20_000 / 111_000,
            longitude: origin.longitude
        )
        let afterMoving = Set(loci.nearest(AppConstants.maxGeofences, to: movedNorth).map(\.id))

        XCTAssertNotEqual(atOrigin, afterMoving, "the monitored set must follow the user")
        XCTAssertEqual(afterMoving.count, AppConstants.maxGeofences)
    }

    // MARK: - Distance helper

    func testHaversineDistanceIsAccurateOverAKnownSpan() {
        // Salt Lake City to San Francisco is ~965 km. 1% tolerance covers the
        // spherical-earth approximation.
        let slc = CLLocationCoordinate2D(latitude: 40.7608, longitude: -111.8910)
        let sfo = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)

        let metres = slc.distance(to: sfo)

        XCTAssertEqual(metres, 965_000, accuracy: 10_000)
    }

    func testDistanceToSelfIsZero() {
        XCTAssertEqual(origin.distance(to: origin), 0, accuracy: 0.001)
    }

    func testDistanceIsSymmetric() {
        let other = CLLocationCoordinate2D(latitude: 41.0, longitude: -112.0)
        XCTAssertEqual(origin.distance(to: other), other.distance(to: origin), accuracy: 0.001)
    }
}
