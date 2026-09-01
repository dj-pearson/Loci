import CoreLocation
import Foundation
import os.log
import UIKit

extension Notification.Name {
    static let locusDidCreate = Notification.Name("LocusDidCreate")
}

@Observable
final class GeofenceManager {
    // MARK: - Singleton

    static let shared = GeofenceManager()

    // MARK: - Properties

    private(set) var monitoredRegionIds: Set<String> = []

    private let logger = Logger(subsystem: "app.lociate.ios", category: "Geofence")

    private var monitor: CLMonitor?
    private var initTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var notificationObservers: [Any] = []

    /// The last location used for a geofence refresh, to avoid redundant recalculations.
    private var lastRefreshLocation: CLLocation?

    /// Loci supplier closure — set by the app to provide current loci for rotation.
    /// This avoids GeofenceManager needing direct SwiftData access.
    var lociProvider: (() -> [Locus])?

    /// Called when a geofence entry event is detected for a locus.
    /// Set by the app to trigger notification delivery via NotificationService.
    var onGeofenceEntry: ((Locus) -> Void)?

    private var eventTask: Task<Void, Never>?

    // MARK: - Initialization

    private init() {
        initTask = Task {
            await self.setupMonitor()
        }
        observeNotifications()
    }

    deinit {
        initTask?.cancel()
        refreshTask?.cancel()
        eventTask?.cancel()
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Monitor Setup

    private func setupMonitor() async {
        let monitor = await CLMonitor("LociGeofences")
        self.monitor = monitor

        // Restore tracked identifiers from existing monitor state
        for identifier in await monitor.identifiers {
            monitoredRegionIds.insert(identifier)
        }

        // Start listening for geofence events
        startEventMonitoring(monitor)
    }

    /// Observes the CLMonitor event stream for geofence entry (`.satisfied`) events.
    /// When entry is detected, looks up the locus by ID and calls `onGeofenceEntry`.
    private func startEventMonitoring(_ monitor: CLMonitor) {
        eventTask?.cancel()
        eventTask = Task {
            // `events` is an async property AND its iteration throws, so this needs
            // both `await` on the access and `try` on the loop. The do/catch is what
            // keeps the closure non-throwing, which `eventTask: Task<Void, Never>?`
            // requires — and it means a stream failure gets logged instead of being
            // swallowed by an unobserved Task.
            do {
                for try await event in await monitor.events {
                    guard !Task.isCancelled else { break }

                    // Only act on entry events (state becomes satisfied)
                    guard case .satisfied = event.state else { continue }

                    let identifier = event.identifier
                    guard let loci = lociProvider?(),
                          let locus = loci.first(where: { $0.id.uuidString == identifier })
                    else { continue }

                    AnalyticsService.shared.trackGeofenceTriggered()
                    onGeofenceEntry?(locus)
                }
            } catch {
                // A thrown error ends the stream, which means geofence entries stop
                // arriving — worth a log rather than silence.
                logger.error("Geofence event stream failed: \(error.localizedDescription)")
            }
        }
    }

    private func ensureMonitor() async -> CLMonitor? {
        if let monitor { return monitor }
        await initTask?.value
        return monitor
    }

    // MARK: - Notification Observers

    private func observeNotifications() {
        let locationObserver = NotificationCenter.default.addObserver(
            forName: .locationDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let location = notification.userInfo?["location"] as? CLLocation else { return }
            self.scheduleRefresh(from: location.coordinate)
        }
        let locusObserver = NotificationCenter.default.addObserver(
            forName: .locusDidCreate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, let location = self.lastRefreshLocation else { return }
            self.scheduleRefresh(from: location.coordinate)
        }
        let foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, let location = self.lastRefreshLocation else { return }
            self.scheduleRefresh(from: location.coordinate)
        }
        notificationObservers = [locationObserver, locusObserver, foregroundObserver]
    }

    // MARK: - Geofence Rotation

    /// Schedules an async geofence refresh, cancelling any in-flight refresh.
    private func scheduleRefresh(from coordinate: CLLocationCoordinate2D) {
        refreshTask?.cancel()
        refreshTask = Task {
            guard let loci = lociProvider?() else { return }
            await refreshGeofences(from: coordinate, loci: loci)
        }
    }

    /// Recalculates which loci should be monitored based on proximity to the given location.
    /// Registers the nearest 20 (or fewer) non-archived loci and removes any that fell out of range.
    func refreshGeofences(from location: CLLocationCoordinate2D, loci: [Locus]) async {
        guard await ensureMonitor() != nil else { return }

        lastRefreshLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)

        // Filter to non-archived loci only (personal + shared)
        let activeLoci = loci.filter { !$0.isArchived }

        // Get nearest N loci sorted by Haversine distance
        let nearest = activeLoci.nearest(AppConstants.maxGeofences, to: location)
        let newIds = Set(nearest.map { $0.id.uuidString })

        // Determine which regions to add and remove
        let toRemove = monitoredRegionIds.subtracting(newIds)
        let toAdd = nearest.filter { !monitoredRegionIds.contains($0.id.uuidString) }

        // Remove regions no longer in the nearest set
        for identifier in toRemove {
            guard let monitor else { break }
            await monitor.remove(identifier)
            monitoredRegionIds.remove(identifier)
        }

        // Register new nearest regions
        for locus in toAdd {
            await registerRegion(for: locus)
        }
    }

    // MARK: - Region Management

    func registerRegion(for locus: Locus) async {
        guard let monitor = await ensureMonitor() else { return }
        let condition = CLMonitor.CircularGeographicCondition(
            center: locus.coordinate,
            radius: AppConstants.geofenceRadius
        )
        await monitor.add(condition, identifier: locus.id.uuidString)
        monitoredRegionIds.insert(locus.id.uuidString)
    }

    func removeRegion(for locus: Locus) async {
        guard let monitor = await ensureMonitor() else { return }
        await monitor.remove(locus.id.uuidString)
        monitoredRegionIds.remove(locus.id.uuidString)
    }

    func removeAllRegions() async {
        guard let monitor = await ensureMonitor() else { return }
        let ids = monitoredRegionIds
        for identifier in ids {
            await monitor.remove(identifier)
        }
        monitoredRegionIds.removeAll()
    }
}
