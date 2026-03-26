import BackgroundTasks
import Foundation
import SwiftData

@Observable
final class BackgroundSyncManager {
    static let taskIdentifier = "com.pearsonmedia.loci.sync"

    private let syncService: SyncService
    private let audioSyncService: AudioSyncService
    private let authService: AuthService
    private let audioCacheManager: AudioCacheManager

    private var lastSyncTime: Date?
    private let minimumSyncInterval: TimeInterval = 15 * 60 // 15 minutes

    init(syncService: SyncService, audioSyncService: AudioSyncService, authService: AuthService, audioCacheManager: AudioCacheManager = AudioCacheManager()) {
        self.syncService = syncService
        self.audioSyncService = audioSyncService
        self.authService = authService
        self.audioCacheManager = audioCacheManager
    }

    // MARK: - Background Task Registration

    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let bgTask = task as? BGAppRefreshTask else { return }
            self?.handleBackgroundRefresh(bgTask)
        }
    }

    func scheduleBackgroundSync() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minimumSyncInterval)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Background task scheduling may fail in certain conditions
        }
    }

    // MARK: - Sync Triggers

    /// Called when app enters foreground via scenePhase change.
    func syncOnForeground(modelContext: ModelContext) {
        guard shouldSync() else { return }
        Task {
            await performFullSync(modelContext: modelContext)
        }
    }

    /// Called after a new locus is created.
    func syncAfterCreation(modelContext: ModelContext) {
        guard authService.isAuthenticated else { return }
        Task {
            await syncService.uploadPendingLoci(modelContext: modelContext)
            await audioSyncService.uploadPendingAudio(modelContext: modelContext)
        }
    }

    // MARK: - Full Sync

    func performFullSync(modelContext: ModelContext) async {
        guard authService.isAuthenticated else { return }

        // Upload first, then download
        await syncService.uploadPendingLoci(modelContext: modelContext)
        await syncService.downloadRemoteLoci(modelContext: modelContext)

        // Audio sync after loci are in sync
        await audioSyncService.uploadPendingAudio(modelContext: modelContext)
        await audioSyncService.downloadMissingAudio(modelContext: modelContext)

        // Clean up audio cache if over limit
        audioCacheManager.cleanupIfNeeded(modelContext: modelContext)

        lastSyncTime = Date()
    }

    // MARK: - Private

    private func shouldSync() -> Bool {
        guard authService.isAuthenticated else { return false }

        if let lastSync = lastSyncTime {
            return Date().timeIntervalSince(lastSync) >= minimumSyncInterval
        }

        return true
    }

    private func handleBackgroundRefresh(_ task: BGAppRefreshTask) {
        scheduleBackgroundSync() // Schedule next refresh

        let syncTask = Task {
            guard let container = try? ModelContainer(for: Locus.self, UserProfile.self) else {
                task.setTaskCompleted(success: false)
                return
            }

            let context = ModelContext(container)
            await performFullSync(modelContext: context)
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            syncTask.cancel()
        }
    }
}
