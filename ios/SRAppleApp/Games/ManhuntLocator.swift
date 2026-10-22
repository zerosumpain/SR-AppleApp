import Foundation
import CoreLocation

/// Where this phone is, for Manhunt only — and only while a hunt is live.
///
/// A session of its own, apart from `LocationCollector`: its fixes go to the
/// game room and nowhere else — never the journey outbox, never history. It is
/// the one exception to "GPS sleeps when still", and it is narrow: the store
/// starts it when the room reaches the head start and stops it at the finish,
/// on Leave, when the room closes or goes away, and when the game screen goes.
/// It keeps running with the phone in a pocket (the hunt is outdoors), so iOS
/// shows its location indicator throughout — a visible reminder belongs here.
///
/// In `-SRDemo` it never starts: the demo has no GPS and the fixtures place
/// everyone.
@MainActor
final class ManhuntLocator: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    /// Every fix while running.
    var onFix: @MainActor (CLLocation) -> Void = { _ in }
    /// Location is off for the app: the screen says so.
    var onDenied: @MainActor () -> Void = {}
    private(set) var running = false
    private var waiter: CheckedContinuation<CLLocation?, Never>?
    private var waitTimeout: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
    }

    /// Start sending fixes. Idempotent.
    func start() {
        guard !running, !SRDemo.isOn else { return }
        running = true
        askIfNeeded()
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    /// Stop at once. Idempotent; safe to call from anywhere the game ends.
    func stop() {
        guard running else { return }
        running = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    /// One fix, for the lobby's "centre the circle here". Nil after 15 s, or
    /// when location is off.
    func oneFix() async -> CLLocation? {
        if SRDemo.isOn { return nil }
        if let pending = waiter {
            waiter = nil
            pending.resume(returning: nil)
        }
        askIfNeeded()
        return await withCheckedContinuation { continuation in
            waiter = continuation
            manager.requestLocation()
            waitTimeout?.cancel()
            waitTimeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled else { return }
                self?.settleWaiter(nil)
            }
        }
    }

    private func askIfNeeded() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    private func settleWaiter(_ location: CLLocation?) {
        guard let pending = waiter else { return }
        waiter = nil
        waitTimeout?.cancel()
        pending.resume(returning: location)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        settleWaiter(latest)
        if running { onFix(latest) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .denied {
            settleWaiter(nil)
            onDenied()
        }
        // Anything else (no fix yet) is transient: the next update answers.
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            settleWaiter(nil)
            onDenied()
        default:
            break
        }
    }
}
