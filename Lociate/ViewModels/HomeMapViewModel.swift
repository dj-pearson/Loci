import CoreLocation
import Foundation
import MapKit
import SwiftData

@Observable
final class HomeMapViewModel {
    // MARK: - Constants

    /// Padding factor around visible region for smooth scrolling pre-fetch.
    private static let viewportPaddingFactor: Double = 0.10
    /// Maximum annotations rendered before forcing additional clustering.
    private static let maxAnnotations: Int = 100
    /// Debounce interval for map region changes in seconds.
    private static let regionDebounceInterval: TimeInterval = 0.2

    // MARK: - State

    var mapRegion: MKCoordinateRegion
    var selectedCategories: Set<LocusCategory> = Set(LocusCategory.allCases)
    var showFamilyLoci: Bool = true

    /// The debounced map region used for computing visible loci.
    /// Updated 200ms after the last `mapRegion` change via `scheduleRegionUpdate()`.
    var debouncedMapRegion: MKCoordinateRegion

    // MARK: - Dependencies

    private let locationService: LocationService

    // MARK: - SwiftData

    var modelContext: ModelContext?

    // MARK: - Debounce

    private var regionDebounceTask: Task<Void, Never>?

    // MARK: - US-183: Clustering Cache

    /// Fingerprint that uniquely identifies a clustering input so we can
    /// return the same result when SwiftUI re-renders without the loci or
    /// viewport actually changing.
    private struct ClusterCacheKey: Equatable {
        let locusCount: Int
        let maxUpdatedAt: Double
        let selectedCategoriesHash: Int
        let showFamilyLoci: Bool
        let centerLat: Double
        let centerLon: Double
        let spanLat: Double
        let spanLon: Double
        let screenWidth: Double
    }

    private var cachedClusterKey: ClusterCacheKey?
    private var cachedClusterResult: (singles: [Locus], clusters: [LocusCluster])?

    // MARK: - Initialization

    init(locationService: LocationService) {
        self.locationService = locationService

        // Default to a wide view; will re-center when location arrives
        if let location = locationService.currentLocation {
            let region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
            mapRegion = region
            debouncedMapRegion = region
        } else {
            let region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
            mapRegion = region
            debouncedMapRegion = region
        }
    }

    // MARK: - Region Debouncing

    /// Call this whenever the map camera changes. Debounces updates to `debouncedMapRegion`
    /// so that expensive visible-loci calculations only run after 200ms of inactivity.
    func scheduleRegionUpdate() {
        regionDebounceTask?.cancel()
        regionDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard let self, !Task.isCancelled else { return }
            self.debouncedMapRegion = self.mapRegion
        }
    }

    // MARK: - Filtered Loci

    /// Returns all non-archived loci matching the selected category and family filters.
    func filteredLoci(from allLoci: [Locus]) -> [Locus] {
        allLoci.filter { locus in
            !locus.isArchived
                && selectedCategories.contains(locus.category)
                && (showFamilyLoci || !locus.isShared || locus.createdByName == nil)
        }
    }

    /// The latitude/longitude box used for viewport filtering.
    struct ViewportBounds {
        let minLat: Double
        let maxLat: Double
        let minLon: Double
        let maxLon: Double

        func contains(latitude: Double, longitude: Double) -> Bool {
            latitude >= minLat && latitude <= maxLat
                && longitude >= minLon && longitude <= maxLon
        }
    }

    /// Returns the padded region used for viewport filtering.
    /// Adds a 10% margin around the debounced region for smooth scrolling.
    private func paddedRegion() -> ViewportBounds {
        let center = debouncedMapRegion.center
        let span = debouncedMapRegion.span
        let latPad = span.latitudeDelta * Self.viewportPaddingFactor
        let lonPad = span.longitudeDelta * Self.viewportPaddingFactor

        return ViewportBounds(
            minLat: center.latitude - span.latitudeDelta / 2 - latPad,
            maxLat: center.latitude + span.latitudeDelta / 2 + latPad,
            minLon: center.longitude - span.longitudeDelta / 2 - lonPad,
            maxLon: center.longitude + span.longitudeDelta / 2 + lonPad
        )
    }

    /// Returns loci within the current map viewport bounds with a 10% padding margin.
    func visibleLoci(from allLoci: [Locus]) -> [Locus] {
        let filtered = filteredLoci(from: allLoci)
        let bounds = paddedRegion()

        return filtered.filter { locus in
            bounds.contains(latitude: locus.latitude, longitude: locus.longitude)
        }
    }

    /// Clusters visible loci for the current viewport, enforcing the max annotation limit.
    /// When visible annotations exceed `maxAnnotations`, clustering threshold is increased
    /// until the total count (singles + clusters) fits within the budget.
    ///
    /// US-183: Result is memoised on a fingerprint of (loci identity,
    /// category filter, family toggle, viewport, screen width). Unrelated
    /// SwiftUI body re-renders hit the cache instead of re-running
    /// filtering + clustering (previously O(n) on every @Query update).
    func viewportAnnotations(
        from allLoci: [Locus],
        screenWidth: CGFloat
    ) -> (singles: [Locus], clusters: [LocusCluster]) {
        let maxUpdatedAt = allLoci.reduce(0.0) { partial, locus in
            max(partial, locus.updatedAt.timeIntervalSinceReferenceDate)
        }

        let key = ClusterCacheKey(
            locusCount: allLoci.count,
            maxUpdatedAt: maxUpdatedAt,
            selectedCategoriesHash: selectedCategories.hashValue,
            showFamilyLoci: showFamilyLoci,
            centerLat: debouncedMapRegion.center.latitude,
            centerLon: debouncedMapRegion.center.longitude,
            spanLat: debouncedMapRegion.span.latitudeDelta,
            spanLon: debouncedMapRegion.span.longitudeDelta,
            screenWidth: Double(screenWidth)
        )

        if key == cachedClusterKey, let cached = cachedClusterResult {
            return cached
        }

        let visible = visibleLoci(from: allLoci)
        var threshold: CGFloat = 60
        var result = LocusClusterEngine.cluster(
            loci: visible,
            region: debouncedMapRegion,
            screenWidth: screenWidth,
            thresholdPoints: threshold
        )

        // Progressively tighten clustering until within annotation budget
        var totalAnnotations = result.singles.count + result.clusters.count
        while totalAnnotations > Self.maxAnnotations && threshold < 300 {
            threshold += 30
            result = LocusClusterEngine.cluster(
                loci: visible,
                region: debouncedMapRegion,
                screenWidth: screenWidth,
                thresholdPoints: threshold
            )
            totalAnnotations = result.singles.count + result.clusters.count
        }

        cachedClusterKey = key
        cachedClusterResult = result
        return result
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
        let region = MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
        mapRegion = region
        debouncedMapRegion = region
    }
}
