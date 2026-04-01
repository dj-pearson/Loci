import Foundation
import MapKit
import SwiftData

@Observable
final class SettingsViewModel {
    // MARK: - User Preferences (AppStorage-backed)

    var notificationsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "loci_notifications_enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "loci_notifications_enabled") }
    }

    var quietHoursStart: Date {
        get {
            UserDefaults.standard.object(forKey: "loci_quiet_hours_start") as? Date
                ?? Calendar.current.date(from: DateComponents(hour: 22, minute: 0))!
        }
        set { UserDefaults.standard.set(newValue, forKey: "loci_quiet_hours_start") }
    }

    var quietHoursEnd: Date {
        get {
            UserDefaults.standard.object(forKey: "loci_quiet_hours_end") as? Date
                ?? Calendar.current.date(from: DateComponents(hour: 7, minute: 0))!
        }
        set { UserDefaults.standard.set(newValue, forKey: "loci_quiet_hours_end") }
    }

    var defaultRadius: Double {
        get {
            let value = UserDefaults.standard.double(forKey: "loci_default_radius")
            return value > 0 ? value : AppConstants.geofenceRadius
        }
        set { UserDefaults.standard.set(newValue, forKey: "loci_default_radius") }
    }

    var mapType: MKMapType {
        get {
            let raw = UserDefaults.standard.integer(forKey: "loci_map_type")
            return MKMapType(rawValue: UInt(raw)) ?? .standard
        }
        set { UserDefaults.standard.set(Int(newValue.rawValue), forKey: "loci_map_type") }
    }

    var lastSyncTimestamp: Date? {
        get { UserDefaults.standard.object(forKey: "loci_last_sync_timestamp") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "loci_last_sync_timestamp") }
    }

    // MARK: - Account State

    var isSignedIn = false
    var currentUser: UserProfile?
    var subscriptionTier: SubscriptionTier {
        currentUser?.subscriptionTier ?? .free
    }

    // MARK: - Storage

    var storageUsed: Int64 {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(
            at: documentsURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == AppConstants.Audio.fileExtension else { continue }
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
        }
        return totalSize
    }

    /// Returns the device's available free space in bytes, or nil if unavailable.
    var deviceFreeSpace: Int64? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let capacity = values.volumeAvailableCapacityForImportantUsage else {
            return nil
        }
        return capacity
    }

    /// Whether device storage is critically low (< 100 MB).
    var isStorageLow: Bool {
        guard let free = deviceFreeSpace else { return false }
        return free < AppConstants.lowStorageThresholdBytes
    }

    // MARK: - Actions

    /// Deletes audio files for all archived loci.
    func deleteArchivedAudio(modelContext: ModelContext) -> Int {
        let archivedPredicate = #Predicate<Locus> { $0.isArchived }
        let descriptor = FetchDescriptor<Locus>(predicate: archivedPredicate)
        guard let archivedLoci = try? modelContext.fetch(descriptor) else { return 0 }

        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        var deletedCount = 0

        for locus in archivedLoci {
            let fileURL = documentsURL.appendingPathComponent(locus.audioFileURL)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: fileURL)
                deletedCount += 1
            }
        }

        return deletedCount
    }

    func clearCache(modelContext: ModelContext) {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileManager = FileManager.default

        // Fetch all known audio file names from SwiftData
        let descriptor = FetchDescriptor<Locus>()
        let knownFiles = Set((try? modelContext.fetch(descriptor))?.map(\.audioFileURL) ?? [])

        guard let contents = try? fileManager.contentsOfDirectory(
            at: documentsURL,
            includingPropertiesForKeys: nil
        ) else { return }

        for fileURL in contents {
            guard fileURL.pathExtension == AppConstants.Audio.fileExtension else { continue }
            let fileName = fileURL.lastPathComponent
            if !knownFiles.contains(fileName) {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }

    func signOut() {
        isSignedIn = false
        currentUser = nil
    }
}
