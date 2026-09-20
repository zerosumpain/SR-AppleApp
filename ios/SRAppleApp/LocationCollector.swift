import Foundation
import CoreLocation

@MainActor final class LocationCollector: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let outbox: Outbox
    private var policy = MovementPolicy()
    private var reference: CLLocation?
    var onUpdate: (() -> Void)?
    @Published var status = "Location sharing is off"
    init(outbox: Outbox) {
        self.outbox = outbox
        super.init()
        manager.delegate = self
        manager.activityType = .other
        manager.pausesLocationUpdatesAutomatically = true
        manager.showsBackgroundLocationIndicator = true
    }
    func requestPermission() { manager.requestWhenInUseAuthorization() }
    func requestAlways() { manager.requestAlwaysAuthorization() }
    func start() {
        guard outbox.state.sharing else { stop(); return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.allowsBackgroundLocationUpdates = true
            manager.desiredAccuracy = policy.moving ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters
            manager.distanceFilter = policy.moving ? 10 : 30
            manager.startUpdatingLocation()
            if CLLocationManager.significantLocationChangeMonitoringAvailable() { manager.startMonitoringSignificantLocationChanges() }
            status = manager.authorizationStatus == .authorizedAlways ? "Sharing · background access enabled" : "Sharing · enable Always for background recovery"
        case .notDetermined: status = "Location permission needed"
        default: status = "Location permission is off in Settings"
        }
    }
    func stop() {
        manager.stopUpdatingLocation(); manager.stopMonitoringSignificantLocationChanges()
        manager.allowsBackgroundLocationUpdates = false
        policy = MovementPolicy(); reference = nil; status = "Location sharing is off"
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { start() }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard outbox.state.sharing else { return }
        for location in locations {
            guard abs(location.timestamp.timeIntervalSinceNow) < 120, location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 100 else { continue }
            let distance = reference.map { location.distance(from: $0) } ?? 0
            let record = policy.shouldRecord(at: location.timestamp, speed: max(0, location.speed), distance: distance, accuracy: location.horizontalAccuracy)
            if reference == nil || distance > max(30, location.horizontalAccuracy * 2) { reference = location }
            manager.desiredAccuracy = policy.moving ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters
            manager.distanceFilter = policy.moving ? 10 : 30
            guard record else { continue }
            let point = LocationRecord(recorded: timestamp(location.timestamp), latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, accuracy: location.horizontalAccuracy, speed: max(0, location.speed), moving: policy.moving)
            do {
                try outbox.change { $0.batches.append(UploadBatch(locations: [point])) }
                status = policy.moving ? "Moving · target 30 seconds" : "Stationary · target 10 minutes"
                onUpdate?()
            } catch { status = "Could not save location. Open the app and retry." }
        }
    }
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) { status = "Location paused by iOS · waiting for movement" }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { status = "Location unavailable · \(error.localizedDescription)" }
}
