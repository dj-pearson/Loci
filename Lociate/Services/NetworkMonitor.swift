import Foundation
import Network

/// Monitors network connectivity using NWPathMonitor.
/// Observable for SwiftUI integration via @Environment.
@Observable
final class NetworkMonitor {
    private(set) var isConnected = true
    private(set) var connectionType: ConnectionType = .unknown

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.pearsonmedia.loci.network-monitor")

    enum ConnectionType {
        case wifi
        case cellular
        case wiredEthernet
        case unknown
    }

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
                self?.connectionType = self?.resolveConnectionType(path) ?? .unknown
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
