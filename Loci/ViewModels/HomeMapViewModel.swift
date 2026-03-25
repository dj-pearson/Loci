import CoreLocation
import Foundation
import MapKit
import SwiftData

@Observable
final class HomeMapViewModel {
    // MARK: - State

    var mapRegion: MKCoordinateRegion
    var selectedCategories: Set<LocusCategory> = Set(LocusCategory.allCases)

    // MARK: - Dependencies

    private let locationService: LocationService

    // MARK: - SwiftData

    var modelContext: ModelContext?

    // MARK: - Initialization

    init(locationService: LocationService) {
        self.locationService = locationService

        // Default to a wide view; will re-center when location arrives
        if let location = locationService.currentLocation {
            mapRegion = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        } else {
            mapRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }
    }

    // MARK: - Filtered Loci

    /// Returns all non-archived loci matching the selected category filters.
    func filteredLoci(from allLoci: [Locus]) -> [Locus] {
        allLoci.filter { locus in
            !locus.isArchived && selectedCategories.contains(locus.category)
        }
    }

    /// Returns loci within the current map viewport bounds.
    func visibleLoci(from allLoci: [Locus]) -> [Locus] {
        let filtered = filteredLoci(from: allLoci)
        let center = mapRegion.center
        let span = mapRegion.span

        let minLat = center.latitude - span.latitudeDelta / 2
        let maxLat = center.latitude + span.latitudeDelta / 2
        let minLon = center.longitude - span.longitudeDelta / 2
        let maxLon = center.longitude + span.longitudeDelta / 2

        return filtered.filter { locus in
            locus.latitude >= minLat && locus.latitude <= maxLat
                && locus.longitude >= minLon && locus.longitude <= maxLon
        }
    }

    // MARK: - Category Filtering

    func toggleCategory(_ category: LocusCategory) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
    }

    func selectAllCategories() {
        selectedCategories = Set(LocusCategory.allCases)
    }

    func clearAllCategories() {
        selectedCategories.removeAll()
    }

    // MARK: - Map Actions

    func centerOnUserLocation() {
        guard let location = locationService.currentLocation else { return }
        mapRegion = MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
    }
}
