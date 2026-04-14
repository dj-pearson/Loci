import Foundation
import Supabase
import SwiftData

@Observable
final class SyncService {
    // MARK: - Published State

    private(set) var isSyncing = false
    private(set) var lastSyncDate: Date?
    private(set) var pendingCount = 0

    private let supabase = SupabaseClientProvider.shared

    // MARK: - Upload (US-074)

    /// Uploads loci with .pending or .modified sync status to Supabase.
    func uploadPendingLoci(modelContext: ModelContext) async {
        guard let userId = await currentUserId() else { return }

        await MainActor.run { isSyncing = true }
        defer { Task { @MainActor in isSyncing = false } }

        let pendingPredicate = #Predicate<Locus> {
            $0.syncStatusRawValue == "pending" || $0.syncStatusRawValue == "modified"
        }
        let descriptor = FetchDescriptor<Locus>(predicate: pendingPredicate)

        guard let loci = try? modelContext.fetch(descriptor) else { return }

        await MainActor.run { pendingCount = loci.count }

        for locus in loci {
            do {
                let payload = LocusUploadPayload(
                    id: locus.id.uuidString,
                    user_id: userId,
                    household_id: locus.householdId?.uuidString,
                    location: "SRID=4326;POINT(\(locus.longitude) \(locus.latitude))",
                    location_name: locus.locationName,
                    audio_url: locus.audioFileURL,
                    transcription: locus.transcription,
                    category: locus.categoryRawValue,
                    is_shared: locus.isShared,
                    created_by_name: locus.createdByName,
                    is_archived: locus.isArchived,
                    created_at: locus.createdAt.ISO8601Format(),
                    updated_at: locus.updatedAt.ISO8601Format()
                )

                try await RetryHelper.withRetry(shouldRetry: RetryHelper.isTransientError) {
                    try await supabase
                        .from("loci")
                        .upsert(payload, onConflict: "id")
                        .execute()
                }

                await MainActor.run {
                    locus.syncStatus = .synced
                    pendingCount = max(0, pendingCount - 1)
                }
            } catch is CancellationError {
                return
            } catch {
                // Leave as pending for retry on next sync cycle
                continue
            }
        }

        try? modelContext.save()
    }

    // MARK: - Download & Merge (US-075)

    /// Downloads remote loci updated after lastSyncDate, merging with local data.
    func downloadRemoteLoci(modelContext: ModelContext) async {
        guard let userId = await currentUserId() else { return }

        await MainActor.run { isSyncing = true }
        defer { Task { @MainActor in isSyncing = false } }

        do {
            var query = supabase
                .from("loci")
                .select()

            if let lastSync = lastSyncDate {
                query = query.gte("updated_at", value: lastSync.ISO8601Format())
            }

            let response: [LocusRemotePayload] = try await RetryHelper.withRetry(
                shouldRetry: RetryHelper.isTransientError
            ) {
                try await query.execute().value
            }

            for remote in response {
                await mergeLocus(remote: remote, modelContext: modelContext)
            }

            try? modelContext.save()

            await MainActor.run {
                lastSyncDate = Date()
            }

            // Trigger geofence refresh after download
            NotificationCenter.default.post(name: .locusDidCreate, object: nil)
        } catch is CancellationError {
            return
        } catch {
            // Network failure — will retry on next sync cycle
        }
    }

    // MARK: - Merge Logic

    private func mergeLocus(remote: LocusRemotePayload, modelContext: ModelContext) async {
        guard let remoteId = UUID(uuidString: remote.id) else { return }

        let idString = remoteId.uuidString
        let descriptor = FetchDescriptor<Locus>(
            predicate: #Predicate { $0.id.uuidString == idString }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            // Last-write-wins: update only if remote is newer
            let remoteDate = ISO8601DateFormatter().date(from: remote.updated_at) ?? Date.distantPast
            if remoteDate > existing.updatedAt {
                existing.locationName = remote.location_name
                existing.transcription = remote.transcription
                existing.categoryRawValue = remote.category
                existing.isShared = remote.is_shared
                existing.createdByName = remote.created_by_name
                existing.isArchived = remote.is_archived
                existing.updatedAt = remoteDate
                existing.syncStatus = .synced
            }
        } else {
            // New remote locus — create locally
            let coords = parsePoint(remote.location)
            let locus = Locus(
                id: remoteId,
                latitude: coords.latitude,
                longitude: coords.longitude,
                locationName: remote.location_name,
                audioFileURL: remote.audio_url ?? "",
                transcription: remote.transcription,
                category: LocusCategory(rawValue: remote.category) ?? .general,
                isShared: remote.is_shared,
                createdByName: remote.created_by_name,
                householdId: remote.household_id.flatMap(UUID.init(uuidString:)),
                createdAt: ISO8601DateFormatter().date(from: remote.created_at) ?? Date(),
                updatedAt: ISO8601DateFormatter().date(from: remote.updated_at) ?? Date(),
                isArchived: remote.is_archived,
                syncStatus: .synced
            )
            modelContext.insert(locus)
        }
    }

    // MARK: - Helpers

    private func currentUserId() async -> String? {
        guard let session = try? await supabase.auth.session else { return nil }
        // Look up internal user ID
        let authId = session.user.id.uuidString
        struct UserRow: Decodable { let id: String }
        let result: [UserRow]? = try? await supabase
            .from("users")
            .select("id")
            .eq("auth_id", value: authId)
            .execute()
            .value
        return result?.first?.id
    }

    /// Parses PostGIS geography text representation to lat/lon.
    private func parsePoint(_ geography: String) -> (latitude: Double, longitude: Double) {
        // Format: POINT(lon lat) or SRID=4326;POINT(lon lat)
        let pointRegex = /POINT\((-?[\d.]+)\s+(-?[\d.]+)\)/
        if let match = geography.firstMatch(of: pointRegex),
           let lon = Double(match.1),
           let lat = Double(match.2) {
            return (lat, lon)
        }
        return (0, 0)
    }
}

// MARK: - Upload Payload

private struct LocusUploadPayload: Encodable {
    let id: String
    let user_id: String
    let household_id: String?
    let location: String
    let location_name: String?
    let audio_url: String
    let transcription: String
    let category: String
    let is_shared: Bool
    let created_by_name: String?
    let is_archived: Bool
    let created_at: String
    let updated_at: String
}

// MARK: - Remote Payload

struct LocusRemotePayload: Decodable {
    let id: String
    let user_id: String
    let household_id: String?
    let location: String
    let location_name: String?
    let audio_url: String?
    let transcription: String
    let category: String
    let is_shared: Bool
    let created_by_name: String?
    let is_archived: Bool
    let created_at: String
    let updated_at: String
}
