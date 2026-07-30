import Foundation
import Network

/// Monitors network connectivity using NWPathMonitor.
/// Observable for SwiftUI integration via @Environment.
@Observable
final class NetworkMonitor {
    private(set) var isConnected = true
    private(set) var connectionType: ConnectionType = .unknown

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.lociate.ios.network-monitor")

    enum ConnectionType {
        case wifi
        case cellular
        case wiredEthernet
        case unknown
    }

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let wasConnected = self.isConnected
                let isNowConnected = path.status == .satisfied
                self.isConnected = isNowConnected
                self.connectionType = self.resolveConnectionType(path)

                // US-195: an APNs token that arrived while offline is queued
                // locally; flush it on the connectivity edge so it is not lost
                // until the next foreground.
                if !wasConnected, isNowConnected {
                    Task { await PushRegistrationService.shared.syncPendingToken() }
                }
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    private func resolveConnectionType(_ path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.cellular) { return .cellular }
        if path.usesInterfaceType(.wiredEthernet) { return .wiredEthernet }
        return .unknown
    }
}
