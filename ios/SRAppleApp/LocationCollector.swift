import Foundation
import Combine
import CoreLocation

@MainActor final class LocationCollector: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let outbox: Outbox
    private var policy: MovementPolicy
    private var reference: CLLocation?
    private var heartbeat: Timer?
    var onUpdate: (() -> Void)?
    @Published var status = "Location sharing is off"
    /// The live settings. Read on every apply rather than cached, so a change
    /// on the settings screen takes effect on the next fix instead of at the
    /// next launch.
    private var settings: LocationSettings { outbox.state.location }

    init(outbox: Outbox) {
        self.outbox = outbox
        self.policy = MovementPolicy(settings: outbox.state.location)
        super.init()
        manager.delegate = self
        manager.showsBackgroundLocationIndicator = true
        applySettings()
    }

    /// Push the current settings at Core Location and the policy.
    ///
    /// Called on start, after every fix, and when the settings screen saves.
    /// `desiredAccuracy` and `distanceFilter` are the two the radio actually
    /// responds to, and they differ by whether the phone is moving — standing
    /// still is the case that does not need a GPS fix and was paying for one.
    func applySettings() {
        let s = settings
        policy.settings = s
        manager.activityType = s.activity.coreLocationValue
        manager.pausesLocationUpdatesAutomatically = s.pausesAutomatically
        manager.desiredAccuracy = (policy.moving ? s.movingAccuracy : s.stationaryAccuracy).coreLocationValue
        manager.distanceFilter = policy.moving ? s.movingDistanceFilter : s.stationaryDistanceFilter
        restartHeartbeat()
    }

    /// The timer that asks for a fix while the process is alive.
    ///
    /// The biggest lever in the settings and the least obvious one: at sixty
    /// seconds it forced a fresh fix every minute even while stationary and
    /// only recording every ten. Zero turns it off and leaves Core Location to
    /// report when it has something worth reporting.
    private func restartHeartbeat() {
        heartbeat?.invalidate()
        heartbeat = nil
        let interval = settings.heartbeatInterval
        guard interval > 0, outbox.state.sharing else { return }
        heartbeat = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.outbox.state.sharing else { return }
                self.manager.requestLocation()
            }
        }
    }
    func requestPermission() { manager.requestWhenInUseAuthorization() }
    func requestAlways() { manager.requestAlwaysAuthorization() }
    func start() {
        guard outbox.state.sharing else { stop(); return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.allowsBackgroundLocationUpdates = true
            applySettings()
            manager.startUpdatingLocation()
            if settings.significantChangeMonitoring, CLLocationManager.significantLocationChangeMonitoringAvailable() {
                manager.startMonitoringSignificantLocationChanges()
            } else {
                manager.stopMonitoringSignificantLocationChanges()
            }
            status = manager.authorizationStatus == .authorizedAlways ? "Sharing · background access enabled" : "Sharing · enable Always for background recovery"
        case .notDetermined: status = "Location permission needed"
        default: status = "Location permission is off in Settings"
        }
    }
    func stop() {
        heartbeat?.invalidate(); heartbeat = nil
        manager.stopUpdatingLocation(); manager.stopMonitoringSignificantLocationChanges()
        manager.allowsBackgroundLocationUpdates = false
        policy = MovementPolicy(settings: outbox.state.location); reference = nil; status = "Location sharing is off"
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { start() }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard outbox.state.sharing else { return }
        for location in locations {
            guard abs(location.timestamp.timeIntervalSinceNow) < 120,
                  location.horizontalAccuracy >= 0,
                  location.horizontalAccuracy <= settings.accuracyCeiling else { continue }
            let distance = reference.map { location.distance(from: $0) } ?? 0
            let record = policy.shouldRecord(at: location.timestamp, speed: max(0, location.speed), distance: distance, accuracy: location.horizontalAccuracy)
            if reference == nil || distance > max(30, location.horizontalAccuracy * 2) { reference = location }
            // Re-apply: the moving/stationary split is the whole saving, so it
            // has to follow the state change rather than wait for a restart.
            manager.desiredAccuracy = (policy.moving ? settings.movingAccuracy : settings.stationaryAccuracy).coreLocationValue
            manager.distanceFilter = policy.moving ? settings.movingDistanceFilter : settings.stationaryDistanceFilter
            guard record else { continue }
            let point = LocationRecord(recorded: timestamp(location.timestamp), latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, accuracy: location.horizontalAccuracy, speed: max(0, location.speed), moving: policy.moving)
            do {
                try outbox.change {
                    $0.batches.append(UploadBatch(locations: [point]))
                    // What the drain bought. Counted here rather than derived
                    // from the queue, because the queue empties on upload.
                    $0.pointsRecorded += 1
                    $0.accuracySum += location.horizontalAccuracy
                    if $0.countingSince == nil { $0.countingSince = Date() }
                }
                status = policy.moving
                    ? "Moving · target \(Int(settings.movingInterval))s"
                    : "Stationary · target \(Int(settings.stationaryInterval / 60)) min"
                onUpdate?()
            } catch { status = "Could not save location. Open the app and retry." }
        }
    }
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) { status = "Location paused by iOS · waiting for movement" }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { status = "Location unavailable · \(error.localizedDescription)" }
}
