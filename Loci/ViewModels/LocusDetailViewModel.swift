import Foundation
import SwiftData

@Observable
final class LocusDetailViewModel {
    // MARK: - State

    let locus: Locus
    private(set) var errorMessage: String?

    // MARK: - Dependencies

    let playerService: AudioPlayerService
    private let geofenceManager: GeofenceManager

    // MARK: - SwiftData

    var modelContext: ModelContext?

    // MARK: - Computed

    var audioURL: URL? {
        let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first
        return documentsDirectory?.appendingPathComponent(locus.audioFileURL)
    }

    // MARK: - Initialization

    init(
        locus: Locus,
        playerService: AudioPlayerService = AudioPlayerService(),
        geofenceManager: GeofenceManager = .shared
    ) {
        self.locus = locus
        self.playerService = playerService
        self.geofenceManager = geofenceManager
    }

    // MARK: - Archive

    func archiveLocus() {
        locus.isArchived = true
        locus.updatedAt = Date()
        saveContext()
        NotificationCenter.default.post(name: .locusDidCreate, object: nil)
    }

    func unarchiveLocus() {
        locus.isArchived = false
        locus.updatedAt = Date()
        saveContext()
        NotificationCenter.default.post(name: .locusDidCreate, object: nil)
    }

    // MARK: - Delete

    func deleteLocus() {
        // Stop playback if playing this locus
        playerService.stop()

        // Delete audio file
        if let url = audioURL {
            try? FileManager.default.removeItem(at: url)
        }

        // Remove from SwiftData
        modelContext?.delete(locus)
        saveContext()
        NotificationCenter.default.post(name: .locusDidCreate, object: nil)
    }

    // MARK: - Edit

    func updateCategory(_ category: LocusCategory) {
        locus.category = category
        locus.updatedAt = Date()
        saveContext()
    }

    func updateTranscription(_ text: String) {
        locus.transcription = text
        locus.updatedAt = Date()
        saveContext()
    }

    // MARK: - Playback

    func togglePlayback() {
        guard let url = audioURL else { return }
        if playerService.isPlaying {
            playerService.pause()
        } else {
            playerService.play(url: url)
        }
    }

    func stopPlayback() {
        playerService.stop()
    }

    // MARK: - Private

    private func saveContext() {
        do {
            try modelContext?.save()
        } catch {
            errorMessage = String(localized: "Failed to save changes. Please try again.")
        }
    }

    func clearError() {
        errorMessage = nil
    }
}
