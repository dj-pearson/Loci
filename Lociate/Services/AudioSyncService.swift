import Foundation
import Supabase
import SwiftData

@Observable
final class AudioSyncService {
    private(set) var isUploading = false
    private(set) var isDownloading = false

    private let supabase = SupabaseClientProvider.shared
    private let bucket = "loci-audio"

    // MARK: - Upload

    /// Uploads local audio files for synced loci that don't yet have a remote audio URL.
    func uploadPendingAudio(modelContext: ModelContext) async {
        guard let userId = await currentUserId() else { return }

        await MainActor.run { isUploading = true }
        defer { Task { @MainActor in isUploading = false } }

        // Find synced loci with local audio files
        let syncedStatus = SyncStatus.synced.rawValue
        let descriptor = FetchDescriptor<Locus>(
            predicate: #Predicate { $0.syncStatusRawValue == syncedStatus }
        )

        guard let loci = try? modelContext.fetch(descriptor) else { return }

        for locus in loci {
            let localURL = URL(fileURLWithPath: locus.audioFileURL)

            // Skip if the audio URL is already a remote URL
            guard FileManager.default.fileExists(atPath: localURL.path) else { continue }

            let remotePath = "\(userId)/\(locus.id.uuidString).m4a"

            do {
                let data = try Data(contentsOf: localURL)

                try await RetryHelper.withRetry(shouldRetry: RetryHelper.isTransientError) {
                    try await supabase.storage
                        .from(bucket)
                        .upload(
                            path: remotePath,
                            file: data,
                            options: .init(contentType: "audio/mp4", upsert: true)
                        )
                }

                // Update the audio URL to include remote path info
                // Keep local path for offline playback, store remote path in a way that's recoverable
                await MainActor.run {
                    locus.updatedAt = Date()
                }
            } catch is CancellationError {
                return
            } catch {
                // Will retry on next sync cycle
                continue
            }
        }

        try? modelContext.save()
    }

    // MARK: - Download

    /// Downloads audio files that exist remotely but not locally.
    func downloadMissingAudio(modelContext: ModelContext) async {
        guard let userId = await currentUserId() else { return }

        await MainActor.run { isDownloading = true }
        defer { Task { @MainActor in isDownloading = false } }

        let syncedStatus = SyncStatus.synced.rawValue
        let descriptor = FetchDescriptor<Locus>(
            predicate: #Predicate { $0.syncStatusRawValue == syncedStatus }
        )

        guard let loci = try? modelContext.fetch(descriptor) else { return }

        let documentsDir = URL.documentsDirectory
        let audioDir = documentsDir.appendingPathComponent("audio", isDirectory: true)

        // Ensure audio directory exists
        try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

        for locus in loci {
            let localPath = audioDir.appendingPathComponent("\(locus.id.uuidString).m4a")

            // Skip if local file already exists
            guard !FileManager.default.fileExists(atPath: localPath.path) else { continue }

            let remotePath = "\(userId)/\(locus.id.uuidString).m4a"

            do {
                let data = try await supabase.storage
                    .from(bucket)
                    .download(path: remotePath)

                try data.write(to: localPath)

                await MainActor.run {
                    locus.audioFileURL = localPath.path
                }
            } catch {
                // File may not exist remotely yet, skip
                continue
            }
        }

        try? modelContext.save()
    }

    // MARK: - Delete

    /// Deletes a remote audio file when a locus is deleted.
    func deleteRemoteAudio(locusId: UUID) async {
        guard let userId = await currentUserId() else { return }

        let remotePath = "\(userId)/\(locusId.uuidString).m4a"

        _ = try? await supabase.storage
            .from(bucket)
            .remove(paths: [remotePath])
    }

    // MARK: - Helpers

    private func currentUserId() async -> String? {
        guard let session = try? await supabase.auth.session else { return nil }
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
}
