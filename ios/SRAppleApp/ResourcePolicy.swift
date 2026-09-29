import Foundation
import Network
import Combine

/// Automatic savings are opt-in and never change the user's location preset
/// or close-tracking preference. Only bulk history traffic is deferred.
@MainActor final class ResourcePolicy: ObservableObject {
    static let shared = ResourcePolicy()
    @Published private(set) var wifi = false
    @Published private(set) var connected = false
    @Published private(set) var constrained = false
    private let monitor = NWPathMonitor()
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.wifi = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
                self?.connected = path.status == .satisfied
                self?.constrained = path.isConstrained
            }
        }
        monitor.start(queue: DispatchQueue(label: "SR.connection-policy", qos: .utility))
    }
    func bulkDeferral(sync: HealthSyncState) -> String? {
        if !connected { return "Waiting for a connection. Collected data is saved on this iPhone." }
        if sync.wifiOnly && !wifi { return "Health history is waiting for Wi-Fi. Location sharing continues." }
        guard sync.automaticEfficiency else { return nil }
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return "Health history is paused by Low Power Mode." }
        if constrained { return "Health history is paused by Low Data Mode." }
        if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical { return "Health history will resume when this iPhone cools down." }
        return nil
    }
}
