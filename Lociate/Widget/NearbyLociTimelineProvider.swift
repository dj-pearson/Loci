import CoreLocation
import SwiftData
import WidgetKit

struct NearbyLociEntry: TimelineEntry {
    let date: Date
    let loci: [NearbyLocusData]
    let isLocked: Bool

    init(date: Date, loci: [NearbyLocusData], isLocked: Bool = false) {
        self.date = date
        self.loci = loci
        self.isLocked = isLocked
    }
}

struct NearbyLocusData: Identifiable {
    let id: UUID
    let transcription: String
    let locationName: String?
    let categoryRawValue: String
    let distanceMeters: Double

    var category: LocusCategory {
        LocusCategory(rawValue: categoryRawValue) ?? .general
    }

    var formattedDistance: String {
        if distanceMeters < 1000 {
            "\(Int(distanceMeters))m"
        } else {
            String(format: "%.1fkm", distanceMeters / 1000)
        }
    }
}

struct NearbyLociTimelineProvider: TimelineProvider {
    private static let appGroupID = "group.app.lociate.ios"
    private static let lastLatKey = "widget_last_latitude"
    private static let lastLonKey = "widget_last_longitude"
    static let isPremiumKey = "widget_is_premium"

    func placeholder(in context: Context) -> NearbyLociEntry {
        NearbyLociEntry(date: .now, loci: Self.sampleData)
    }

    func getSnapshot(in context: Context, completion: @escaping (NearbyLociEntry) -> Void) {
        if context.isPreview {
            completion(NearbyLociEntry(date: .now, loci: Self.sampleData))
        } else {
            let loci = fetchNearbyLoci()
            completion(NearbyLociEntry(date: .now, loci: loci))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NearbyLociEntry>) -> Void) {
        let isLocked = !isPremiumUser()
        let loci = isLocked ? [] : fetchNearbyLoci()
        let entry = NearbyLociEntry(date: .now, loci: loci, isLocked: isLocked)
        // US-178: Refresh every hour rather than every 15 minutes. The main app
        // pushes an immediate reload via WidgetCenter.shared.reloadAllTimelines()
        // whenever a locus is created, so we don't need aggressive polling.
        let refreshDate = Date().addingTimeInterval(3600)
        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
        completion(timeline)
    }

    // MARK: - Data Fetching

    /// US-178: Spatial pre-filter constant. Approximate 2 km radius converts to
    /// ~0.02 degrees latitude and a longitude-corrected delta computed per-call.
    /// At the equator 0.02° ≈ 2.2 km; near the poles longitude needs correction.
    private static let searchRadiusKm: Double = 2.0
    private static let kmPerLatDegree: Double = 111.0

    private func fetchNearbyLoci() -> [NearbyLocusData] {
        guard let coordinate = lastKnownLocation() else {
            return []
        }

        guard let container = try? Self.createModelContainer() else {
            return []
        }

        let context = ModelContext(container)

        // US-178: Predicate-based bounding box so SwiftData doesn't page the whole
        // Locus table into memory just to return the 3 closest notes. This cuts
        // widget CPU and memory dramatically on large datasets.
        let latDelta = Self.searchRadiusKm / Self.kmPerLatDegree
        let lonDelta = latDelta / max(0.0001, cos(coordinate.latitude * .pi / 180))
        let minLat = coordinate.latitude - latDelta
        let maxLat = coordinate.latitude + latDelta
        let minLon = coordinate.longitude - lonDelta
        let maxLon = coordinate.longitude + lonDelta

        var descriptor = FetchDescriptor<Locus>(
            predicate: #Predicate<Locus> { locus in
                locus.isArchived == false
                    && locus.latitude >= minLat
                    && locus.latitude <= maxLat
                    && locus.longitude >= minLon
                    && locus.longitude <= maxLon
            }
        )
        descriptor.fetchLimit = 50

        guard let nearby = try? context.fetch(descriptor) else {
            return []
        }

        let sorted = nearby.sortedByDistance(from: coordinate)
        return Array(sorted.prefix(3)).map { locus in
            NearbyLocusData(
                id: locus.id,
                transcription: locus.transcription,
                locationName: locus.locationName,
                categoryRawValue: locus.categoryRawValue,
                distanceMeters: locus.coordinate.distance(to: coordinate)
            )
        }
    }

    private func isPremiumUser() -> Bool {
        let defaults = UserDefaults(suiteName: Self.appGroupID)
        return defaults?.bool(forKey: Self.isPremiumKey) ?? false
    }

    private func lastKnownLocation() -> CLLocationCoordinate2D? {
        let defaults = UserDefaults(suiteName: Self.appGroupID)
        let lat = defaults?.double(forKey: Self.lastLatKey) ?? 0
        let lon = defaults?.double(forKey: Self.lastLonKey) ?? 0
        guard lat != 0 || lon != 0 else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private static func createModelContainer() throws -> ModelContainer {
        let schema = ModelContainerConfiguration.schema
        let configuration = ModelConfiguration(
            "Lociate",
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .identifier(appGroupID)
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    // MARK: - Sample Data

    static let sampleData: [NearbyLocusData] = [
        NearbyLocusData(
            id: UUID(),
            transcription: "Great coffee shop on the corner, try the cold brew",
            locationName: "Main Street",
            categoryRawValue: LocusCategory.food.rawValue,
            distanceMeters: 120
        ),
        NearbyLocusData(
            id: UUID(),
            transcription: "Free parking behind the library after 6pm",
            locationName: "Library Lot",
            categoryRawValue: LocusCategory.parking.rawValue,
            distanceMeters: 340
        ),
        NearbyLocusData(
            id: UUID(),
            transcription: "Trail head is past the second gate on the left",
            locationName: "Oak Ridge Park",
            categoryRawValue: LocusCategory.outdoor.rawValue,
            distanceMeters: 890
        ),
    ]
}
