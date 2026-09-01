import Foundation
import SwiftData

@Observable
final class AudioCacheManager {
    static let defaultMaxCacheSize: Int64 = 500 * 1024 * 1024 // 500MB

    var maxCacheSize: Int64

    private let fileManager = FileManager.default

    init(maxCacheSize: Int64 = AudioCacheManager.defaultMaxCacheSize) {
        self.maxCacheSize = maxCacheSize
    }

    // MARK: - Cache Size

    /// Calculates total size of all audio files in the documents/audio directory and root documents directory.
    func currentCacheSize() -> Int64 {
        var totalSize: Int64 = 0

        // Audio files in documents/audio/
        let audioDir = audioDirectory()
        totalSize += directorySize(at: audioDir)

        // Audio files in documents root (locus_*.m4a from recordings)
        let documentsDir = URL.documentsDirectory
        if let contents = try? fileManager.contentsOfDirectory(
            at: documentsDir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        ) {
            for file in contents where file.pathExtension == AppConstants.Audio.fileExtension {
                if let attrs = try? file.resourceValues(forKeys: [.fileSizeKey]),
                   let size = attrs.fileSize {
                    totalSize += Int64(size)
                }
            }
        }

        return totalSize
    }

    // MARK: - Cache Check

    /// Checks if an audio file exists locally.
    func isFileCached(_ url: String) -> Bool {
        fileManager.fileExists(atPath: url)
    }

    // MARK: - Cleanup

    /// Removes oldest archived loci audio files when cache exceeds the limit.
    /// Excludes non-synced audio files from cleanup to prevent data loss.
    func cleanupIfNeeded(modelContext: ModelContext) {
        let cacheSize = currentCacheSize()
        guard cacheSize > maxCacheSize else { return }

        // Fetch archived loci that are synced (safe to delete local audio)
        let archivedValue = true
        let syncedStatus = SyncStatus.synced.rawValue
        var descriptor = FetchDescriptor<Locus>(
            predicate: #Predicate {
                $0.isArchived == archivedValue && $0.syncStatusRawValue == syncedStatus
            },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)] // oldest first
        )
        descriptor.fetchLimit = 500

        guard let archivedLoci = try? modelContext.fetch(descriptor) else { return }

        var freedBytes: Int64 = 0
        let targetReduction = cacheSize - maxCacheSize

        for locus in archivedLoci {
            guard freedBytes < targetReduction else { break }

            let filePath = locus.audioFileURL
            guard fileManager.fileExists(atPath: filePath) else { continue }

            if let attrs = try? fileManager.attributesOfItem(atPath: filePath),
               let fileSize = attrs[.size] as? Int64 {
                do {
                    try fileManager.removeItem(atPath: filePath)
                    freedBytes += fileSize
                } catch {
                    continue
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func audioDirectory() -> URL {
        let documentsDir = URL.documentsDirectory
        return documentsDir.appendingPathComponent("audio", isDirectory: true)
    }

    private func directorySize(at url: URL) -> Int64 {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return 0 }

        var size: Int64 = 0
        for file in contents {
            if let attrs = try? file.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = attrs.fileSize {
                size += Int64(fileSize)
            }
        }
        return size
    }
}
