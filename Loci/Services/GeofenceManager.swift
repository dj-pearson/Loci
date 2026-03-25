import CoreLocation
import Foundation

@Observable
final class GeofenceManager {
    // MARK: - Singleton

    static let shared = GeofenceManager()

    // MARK: - Properties

    private(set) var monitoredRegionIds: Set<String> = []

    private var monitor: CLMonitor?
    private var initTask: Task<Void, Never>?

    // MARK: - Initialization

    private init() {
        initTask = Task {
            await self.setupMonitor()
        }
    }

    deinit {
        initTask?.cancel()
    }

    // MARK: - Monitor Setup

    private func setupMonitor() async {
        let monitor = await CLMonitor("LociGeofences")
        self.monitor = monitor

        // Restore tracked identifiers from existing monitor state
        for identifier in monitor.identifiers {
            monitoredRegionIds.insert(identifier)
        }
    }

    private func ensureMonitor() async -> CLMonitor? {
        if let monitor { return monitor }
        await initTask?.value
        return monitor
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
