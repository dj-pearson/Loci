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
    private static let appGroupID = "group.com.pearsonmedia.loci"
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
        let refreshDate = Date().addingTimeInterval(900) // 15 minutes
        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
        completion(timeline)
    }

    // MARK: - Data Fetching

    private func fetchNearbyLoci() -> [NearbyLocusData] {
        guard let coordinate = lastKnownLocation() else {
            return []
        }

        guard let container = try? Self.createModelContainer() else {
            return []
        }

        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Locus>(
            predicate: #Predicate<Locus> { locus in
                locus.isArchived == false
            }
        )

        guard let allLoci = try? context.fetch(descriptor) else {
            return []
        }

        let sorted = allLoci.sortedByDistance(from: coordinate)
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
