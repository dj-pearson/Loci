import CoreLocation
import Foundation
import SwiftData

@Model
final class Locus {
    @Attribute(.unique) var id: UUID
    var latitude: Double
    var longitude: Double
    var locationName: String?
    var audioFileURL: String
    var transcription: String
    var categoryRawValue: String
    var isShared: Bool
    var createdByName: String?
    var householdId: UUID?
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool
    var syncStatusRawValue: String

    var category: LocusCategory {
        get { LocusCategory(rawValue: categoryRawValue) ?? .general }
        set { categoryRawValue = newValue.rawValue }
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRawValue) ?? .pending }
        set { syncStatusRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        locationName: String? = nil,
        audioFileURL: String,
        transcription: String = "",
        category: LocusCategory = .general,
        isShared: Bool = false,
        createdByName: String? = nil,
        householdId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isArchived: Bool = false,
        syncStatus: SyncStatus = .pending
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.locationName = locationName
        self.audioFileURL = audioFileURL
        self.transcription = transcription
        self.categoryRawValue = category.rawValue
        self.isShared = isShared
        self.createdByName = createdByName
        self.householdId = householdId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.syncStatusRawValue = syncStatus.rawValue
    }
}

enum SyncStatus: String, Codable {
    case pending
    case synced
    case modified
    case conflicted
}
