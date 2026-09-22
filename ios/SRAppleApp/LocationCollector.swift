import Foundation
import Combine
import CoreLocation
import UIKit

/// Where the phone is, and — since the motion gate — when it is worth asking.
///
/// ## The six steps
///
/// The app used to hold a continuous background location session all day. That
/// is what kept the process alive, and it is also what drained the battery: it
/// ran GPS in order to find out whether GPS was needed. The gate inverts it.
///
///   1. Still long enough → drop a geofence at the current spot, keep
///      significant-change and visit monitoring as backstops, stop GPS. Let iOS
///      suspend the app. Near-zero cost.
///   2. Wake on geofence exit, significant change, or a visit departure. These
///      are the only three things that wake a SUSPENDED app; motion does not.
///   3. On waking, read the motion history for the stretch we slept through.
///      The coprocessor recorded it in hardware whether or not we existed, so
///      this costs nothing but the asking.
///   4. Decide. Sustained walking or travel → GPS back on. A blip → one coarse
///      point, re-anchor, back to sleep.
///   5. Moving → GPS on, the app stays alive, and the old speed-and-distance
///      policy takes over as before.
///   6. Still again → back to step 1.
///
/// ## The failure this is most exposed to
///
/// Switching GPS off with no working way back. The app would look fine and
/// record nothing, for hours, silently. So `arm()` refuses to sleep unless every
/// wake route is actually available — Always authorisation, significant-change,
/// geofencing and a readable motion log — and logs a `blocked` event saying which
/// one was missing rather than sleeping and hoping. Everything ambiguous fails
/// OPEN, towards paying for GPS.
@MainActor final class LocationCollector: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let outbox: Outbox
    private let motion = MotionGate()
    private var policy: MovementPolicy
    private var reference: CLLocation?
    private var heartbeat: Timer?
    var onUpdate: (() -> Void)?
    @Published var status = "Location sharing is off"
    /// Published so the settings and history screens can say which state the app
    /// is actually in rather than which one it was configured for.
    @Published private(set) var gate: GateState = .tracking

    /// The anchor's region identifier. One region, always replaced — iOS allows
    /// twenty per app and leaking them would quietly stop new ones registering.
    private static let anchorID = "sr.location.anchor"
    /// Ignore SIGNIFICANT-CHANGE wakes for this long after arming.
    /// `startMonitoringSignificantLocationChanges` delivers a fix almost
    /// immediately, and without this the gate would wake itself the instant it
    /// went to sleep.
    ///
    /// It deliberately does NOT apply to a geofence exit or a visit. A relaunch
    /// caused by an exit re-arms and then receives that exit milliseconds later:
    /// settling it would swallow the very event that woke the app, leaving it
    /// asleep at an anchor it has already left — which is the silent-failure
    /// mode this whole design has to avoid.
    private static let settle: TimeInterval = 30
    /// How long to wait for the one coarse fix that re-anchors after a blip.
    private static let anchorFixTimeout: TimeInterval = 20

    /// When the phone was first seen to be still. Not persisted: a relaunch has
    /// no idea how long you have been sitting down, and assuming would arm the
    /// gate the moment the app came back.
    private var stillSince: Date?
    private var armedAt: Date?
    private var assessing = false
    private var awaitingAnchor: String?
    private var anchorTimeoutTask: Task<Void, Never>?
    /// Whether anything is actually running, so `stop()` only writes a line to
    /// the log when there was something to stop.
    private var running = false

    /// The live settings. Read on every apply rather than cached, so a change
    /// on the settings screen takes effect on the next fix instead of at the
    /// next launch.
    private var settings: LocationSettings { outbox.state.location }

    init(outbox: Outbox) {
        self.outbox = outbox
        self.policy = MovementPolicy(settings: outbox.state.location)
        self.gate = outbox.state.gateState
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
        // Turning the gate off while it has GPS asleep must wake it here, or the
        // switch appears to do nothing until something happens to move the phone.
        if !s.motion.enabled, gate == .armed {
            if outbox.state.sharing {
                resumeTracking(reason: "Motion gating turned off", kind: .resumed)
                return
            }
            // Not sharing, so there is nothing to resume — just clear the state
            // that would otherwise have the app come back asleep.
            gate = .tracking
            try? outbox.change { $0.gateState = .tracking; $0.anchor = nil }
        }
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
        // A heartbeat while the gate is asleep would defeat the whole thing: it
        // forces a fix, which is the cost we stopped paying.
        guard gate == .tracking else { return }
        let interval = settings.heartbeatInterval
        guard interval > 0, outbox.state.sharing else { return }
        heartbeat = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.outbox.state.sharing, self.gate == .tracking else { return }
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
            // Come back asleep if that is how we went away. Without this every
            // launch — including the background relaunch a geofence exit itself
            // causes — would start continuous GPS again, which is the entire
            // cost the gate exists to avoid.
            if settings.motion.enabled, outbox.state.gateState == .armed, let anchor = outbox.state.anchor {
                rearm(anchor: anchor, reason: "Relaunched asleep", kind: .armed, verify: true)
            } else {
                resumeTracking(reason: "Sharing on", kind: .started)
            }
        case .notDetermined: status = "Location permission needed"
        default: status = "Location permission is off in Settings"
        }
    }

    func stop() {
        heartbeat?.invalidate(); heartbeat = nil
        anchorTimeoutTask?.cancel(); anchorTimeoutTask = nil
        awaitingAnchor = nil
        stopWakeRoutes()
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        policy = MovementPolicy(settings: outbox.state.location)
        reference = nil
        stillSince = nil
        armedAt = nil
        gate = .tracking
        try? outbox.change { $0.gateState = .tracking; $0.anchor = nil }
        if running { note(.stopped, reason: "Sharing off") }
        running = false
        status = "Location sharing is off"
    }

    // MARK: - Step 1 and 6: going to sleep

    /// Switch GPS off and leave something behind that can wake us.
    ///
    /// Every guard below is a way the app could go silent. They log instead of
    /// sleeping, because "still recording, expensively" beats "not recording,
    /// and nobody can tell".
    private func arm(at location: CLLocation) {
        let s = settings.motion
        guard s.enabled, gate == .tracking else { return }

        guard manager.authorizationStatus == .authorizedAlways else {
            block("GPS cannot sleep without Always access — nothing could wake it")
            return
        }
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else {
            block("Significant-change monitoring unavailable on this iPhone")
            return
        }
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            block("Geofencing unavailable on this iPhone")
            return
        }
        guard motion.usable else {
            block(motion.refusalReason ?? "Motion history unreadable")
            return
        }

        let anchor = GateAnchor(latitude: location.coordinate.latitude,
                                longitude: location.coordinate.longitude,
                                radius: anchorRadius(for: location),
                                at: Date())
        rearm(anchor: anchor, reason: "Still for \(short(s.sleepAfter))", kind: .armed)
    }

    /// Radius derived from the fix, not from a constant.
    ///
    /// An anchor smaller than the error in the fix that placed it exits itself
    /// the moment the next fix lands a few metres the other way — which is the
    /// wake storm, and it costs more than never sleeping at all. The widening
    /// on top is the automatic half of `maxWakesPerHour`; the history screen
    /// shows the wake count that triggered it.
    private func anchorRadius(for location: CLLocation) -> Double {
        let s = settings.motion
        var radius = max(s.anchorRadius, max(0, location.horizontalAccuracy) * 2)
        let recent = GateMaths.wakes(outbox.state.gateEvents, since: Date().addingTimeInterval(-3600))
        if recent > s.maxWakesPerHour {
            radius *= pow(2, Double(min(3, recent - s.maxWakesPerHour)))
        }
        return min(s.maxAnchorRadius, radius)
    }

    private func rearm(anchor: GateAnchor, reason: String, kind: GateEvent.Kind, verify: Bool = false) {
        stopWakeRoutes()
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: anchor.latitude, longitude: anchor.longitude),
            radius: anchor.radius,
            identifier: Self.anchorID)
        region.notifyOnEntry = false
        region.notifyOnExit = true
        manager.startMonitoring(for: region)
        // Region events fire on a boundary CROSSING. Coming back from a relaunch
        // we may already be outside the anchor we stored — and an anchor you are
        // outside of will never be exited again, so the app would sleep for
        // good. Asking for the state is the only thing that catches that.
        if verify { manager.requestState(for: region) }
        manager.startMonitoringSignificantLocationChanges()
        if settings.motion.visitMonitoring { manager.startMonitoringVisits() }
        manager.stopUpdatingLocation()
        heartbeat?.invalidate(); heartbeat = nil

        gate = .armed
        armedAt = Date()
        stillSince = nil
        running = true
        try? outbox.change { $0.gateState = .armed; $0.anchor = anchor }
        note(kind, reason: reason, detail: "Anchor \(Int(anchor.radius))m")
        status = "Asleep · GPS off within \(Int(anchor.radius))m"
    }

    /// Wanted to sleep, could not. Keeps GPS running and says why.
    private func block(_ reason: String) {
        // Once per hour at most: this is evaluated on every fix while stationary
        // and the log is for reading, not for filling.
        let hourAgo = Date().addingTimeInterval(-3600)
        let alreadySaid = outbox.state.gateEvents.contains {
            $0.kind == .blocked && $0.reason == reason && $0.at > hourAgo
        }
        stillSince = nil
        guard !alreadySaid else { return }
        note(.blocked, reason: reason)
    }

    private func stopWakeRoutes() {
        for region in manager.monitoredRegions where region.identifier == Self.anchorID {
            manager.stopMonitoring(for: region)
        }
        manager.stopMonitoringVisits()
        // Included so `stop()` genuinely stops everything. `rearm()` and
        // `resumeTracking()` both start it again straight afterwards if they
        // want it, which costs one redundant call and removes a way for pausing
        // sharing to leave a listener behind.
        manager.stopMonitoringSignificantLocationChanges()
    }

    // MARK: - Steps 2, 3 and 4: waking, reading the history, deciding

    private func wake(reason: String, settles: Bool = false) {
        guard gate == .armed, !assessing else { return }
        if settles, let armedAt, Date().timeIntervalSince(armedAt) < Self.settle { return }
        assessing = true
        note(.woke, reason: reason, state: .armed)
        status = "Woken · checking what moved"

        var taskID: UIBackgroundTaskIdentifier = .invalid
        // A background wake gives seconds of runtime and a cold GPS fix can take
        // half a minute, so buy the time explicitly. Same move `flush()` makes.
        taskID = UIApplication.shared.beginBackgroundTask(withName: "Assess movement") {
            UIApplication.shared.endBackgroundTask(taskID); taskID = .invalid
        }
        Task { @MainActor [weak self] in
            defer {
                if taskID != .invalid { UIApplication.shared.endBackgroundTask(taskID) }
            }
            guard let self else { return }
            let verdict = await self.assess()
            self.assessing = false
            self.act(on: verdict)
        }
    }

    /// Step 3. Read back the stretch we slept through.
    private func assess() async -> MotionVerdict {
        let s = settings.motion
        let now = Date()
        // From when we went to sleep, but never further back than the window —
        // hours of history would accumulate enough walking to answer "yes"
        // every single time, which is not a gate.
        let slept = armedAt ?? outbox.state.anchor?.at ?? now
        let from = max(slept, now.addingTimeInterval(-s.historyWindow))
        let evidence = await motion.evidence(from: from, to: now, burstWindow: s.stepBurstWindow)
        return MotionAssessment.verdict(evidence, settings: s)
    }

    /// Step 4.
    private func act(on verdict: MotionVerdict) {
        guard gate == .armed else { return }
        if verdict.wakesGPS {
            resumeTracking(reason: verdict.reason, kind: .resumed)
            return
        }
        // A blip. One coarse fix: it re-anchors us — re-arming the anchor we
        // just exited would exit again immediately — and it is recorded too,
        // because it has already been paid for and a long sleep should not be a
        // hole in the record.
        awaitingAnchor = verdict.reason
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.requestLocation()
        anchorTimeoutTask?.cancel()
        anchorTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.anchorFixTimeout))
            guard !Task.isCancelled, let self, self.awaitingAnchor != nil, self.gate == .armed else { return }
            let reason = self.awaitingAnchor ?? "Blip"
            self.awaitingAnchor = nil
            // No fix in time. Re-arm on the old anchor, widened, rather than
            // staying awake — but widened, or we exit it again straight away.
            if var anchor = self.outbox.state.anchor {
                anchor.radius = min(self.settings.motion.maxAnchorRadius, anchor.radius * 2)
                anchor.at = Date()
                self.rearm(anchor: anchor, reason: reason, kind: .slept)
            } else {
                self.resumeTracking(reason: "No fix to re-anchor on", kind: .resumed)
            }
        }
    }

    // MARK: - Step 5: tracking

    private func resumeTracking(reason: String, kind: GateEvent.Kind) {
        anchorTimeoutTask?.cancel(); anchorTimeoutTask = nil
        awaitingAnchor = nil
        stopWakeRoutes()
        gate = .tracking
        armedAt = nil
        stillSince = nil
        running = true
        try? outbox.change { $0.gateState = .tracking; $0.anchor = nil }
        applySettings()
        manager.startUpdatingLocation()
        if settings.significantChangeMonitoring, CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
        } else {
            manager.stopMonitoringSignificantLocationChanges()
        }
        note(kind, reason: reason)
        status = manager.authorizationStatus == .authorizedAlways
            ? "Sharing · background access enabled"
            : "Sharing · enable Always for background recovery"
    }

    // MARK: - The log

    private func note(_ kind: GateEvent.Kind, reason: String, detail: String? = nil, state: GateState? = nil) {
        let event = GateEvent(at: Date(), kind: kind, reason: reason, detail: detail,
                              battery: outbox.state.battery.last?.level,
                              stateAfter: state ?? gate)
        try? outbox.change {
            // `start()` runs on launch AND again on the authorisation callback,
            // so without this every launch writes the same line twice.
            if let last = $0.gateEvents.last, last.kind == kind, last.reason == reason,
               event.at.timeIntervalSince(last.at) < 60 { return }
            $0.gateEvents.append(event)
            if $0.gateEvents.count > GateEvent.maxStored {
                $0.gateEvents.removeFirst($0.gateEvents.count - GateEvent.maxStored)
            }
        }
    }

    private func short(_ seconds: TimeInterval) -> String {
        seconds < 90 ? "\(Int(seconds))s" : "\(Int((seconds / 60).rounded())) min"
    }

    // MARK: - Core Location

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { start() }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard outbox.state.sharing else { return }

        // The one coarse fix requested to re-anchor after a blip.
        if let reason = awaitingAnchor, let location = locations.last {
            awaitingAnchor = nil
            anchorTimeoutTask?.cancel(); anchorTimeoutTask = nil
            if settings.motion.coarseOnBlip { record(location, moving: false) }
            let anchor = GateAnchor(latitude: location.coordinate.latitude,
                                    longitude: location.coordinate.longitude,
                                    radius: anchorRadius(for: location),
                                    at: Date())
            rearm(anchor: anchor, reason: reason, kind: .slept)
            return
        }

        // A fix arriving while asleep IS a significant change — Core Location
        // delivers those down this same path.
        if gate == .armed {
            wake(reason: "Significant change", settles: true)
            return
        }

        for location in locations {
            guard abs(location.timestamp.timeIntervalSinceNow) < 120,
                  location.horizontalAccuracy >= 0,
                  location.horizontalAccuracy <= settings.accuracyCeiling else { continue }
            let distance = reference.map { location.distance(from: $0) } ?? 0
            let worthKeeping = policy.shouldRecord(at: location.timestamp, speed: max(0, location.speed), distance: distance, accuracy: location.horizontalAccuracy)
            if reference == nil || distance > max(30, location.horizontalAccuracy * 2) { reference = location }
            // Re-apply: the moving/stationary split is the whole saving, so it
            // has to follow the state change rather than wait for a restart.
            manager.desiredAccuracy = (policy.moving ? settings.movingAccuracy : settings.stationaryAccuracy).coreLocationValue
            manager.distanceFilter = policy.moving ? settings.movingDistanceFilter : settings.stationaryDistanceFilter

            if worthKeeping { record(location, moving: policy.moving) }

            // Step 6 → step 1. Evaluated on every accepted fix rather than only
            // on a recorded one, or a stationary phone recording every ten
            // minutes would take ten minutes longer to fall asleep than asked.
            if settings.motion.enabled {
                if policy.moving {
                    stillSince = nil
                } else {
                    if stillSince == nil { stillSince = location.timestamp }
                    if let since = stillSince,
                       location.timestamp.timeIntervalSince(since) >= settings.motion.sleepAfter {
                        arm(at: location)
                        return
                    }
                }
            }
        }
    }

    private func record(_ location: CLLocation, moving: Bool) {
        let point = LocationRecord(recorded: timestamp(location.timestamp),
                                   latitude: location.coordinate.latitude,
                                   longitude: location.coordinate.longitude,
                                   accuracy: location.horizontalAccuracy,
                                   speed: max(0, location.speed),
                                   moving: moving)
        do {
            try outbox.change {
                $0.batches.append(UploadBatch(locations: [point]))
                // What the drain bought. Counted here rather than derived from
                // the queue, because the queue empties on upload.
                $0.pointsRecorded += 1
                $0.accuracySum += location.horizontalAccuracy
                if $0.countingSince == nil { $0.countingSince = Date() }
            }
            if gate == .tracking {
                status = moving
                    ? "Moving · target \(Int(settings.movingInterval))s"
                    : "Stationary · target \(Int(settings.stationaryInterval / 60)) min"
            }
            onUpdate?()
        } catch { status = "Could not save location. Open the app and retry." }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == Self.anchorID else { return }
        wake(reason: "Left the anchor")
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        // Only ever asked for after a relaunch. Being outside the stored anchor
        // means the exit happened while we were not running to hear it.
        guard region.identifier == Self.anchorID, state == .outside else { return }
        wake(reason: "Anchor is already behind us")
    }

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        // An arrival is not interesting — we are asleep because we arrived. A
        // departure is the cheapest signal iOS has that you have gone.
        guard visit.departureDate != Date.distantFuture else { return }
        wake(reason: "Left a visited place")
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        guard gate == .armed else { return }
        // The anchor did not take. Staying asleep now would mean staying asleep
        // for good, so come back up and say why.
        resumeTracking(reason: "Anchor failed · \(error.localizedDescription)", kind: .resumed)
    }

    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        status = "Location paused by iOS · waiting for movement"
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if awaitingAnchor != nil { return }
        status = "Location unavailable · \(error.localizedDescription)"
    }
}
