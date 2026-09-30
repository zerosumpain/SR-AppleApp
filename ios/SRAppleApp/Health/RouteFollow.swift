import Foundation
import CoreLocation
import Combine
import UIKit

// Walking a saved route: the GPS session, the recording it makes, and the two
// things kept on disk so neither needs a signal — the route itself, and a
// finished recording waiting to go up.

// MARK: - Routes kept on the phone

/// Every saved route that has been opened, as the site sent it. Following
/// reads from here, so a route opened at home can be walked on a hill with no
/// signal. Keyed by route id; a delete on the list removes the copy.
enum RouteCache {
    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("routes", isDirectory: true)
    }

    private static func file(_ id: String) -> URL {
        directory.appendingPathComponent("\(TrailPath.escape(id)).json")
    }

    static func store(_ data: Data, id: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func load(_ id: String) -> PlannedRouteDetail? {
        guard let data = try? Data(contentsOf: file(id)) else { return nil }
        return try? JSONDecoder().decode(PlannedRouteDetail.self, from: data)
    }

    static func remove(_ id: String) {
        try? FileManager.default.removeItem(at: file(id))
    }
}

// MARK: - The recording

/// What `/api/trails/recordings` takes, and what is kept on disk until it has.
struct RouteRecording: Codable, Equatable {
    let clientId: String
    var name: String
    let sport: String
    let routeId: String?
    /// Epoch seconds.
    let startedAt: Double
    var finishedAt: Double
    /// `[lng, lat, ele | null, secondsFromStart]` — Health's `TrackPoint`.
    var track: [[Double?]]
    var movingS: Double

    var pointCount: Int { track.count }
}

/// Finished recordings not yet accepted by the site, oldest first. A save is
/// idempotent on `clientId` (Health upserts `recorded:<clientId>`), so a retry
/// after a lost reply cannot make a second activity.
@MainActor
final class RecordingQueue: ObservableObject {
    static let shared = RecordingQueue()

    @Published private(set) var pending: [RouteRecording] = []
    @Published private(set) var lastError: String?

    private let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("route-recordings.json")
    private var sending = false

    init() {
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([RouteRecording].self, from: data) {
            pending = saved
        }
    }

    func add(_ recording: RouteRecording) {
        pending.removeAll { $0.clientId == recording.clientId }
        pending.append(recording)
        persist()
    }

    /// Send whatever is waiting. Stops at the first failure: the network is
    /// the likely cause and the rest would fail the same way.
    func flush() async {
        guard !sending, !pending.isEmpty, AccessStore.ownerSite else { return }
        sending = true
        defer { sending = false }
        while let next = pending.first {
            do {
                try await SiteClient.shared.post("api/native/health/recordings", body: try JSONEncoder().encode(next))
                pending.removeFirst()
                persist()
                lastError = nil
            } catch let error as SiteError where error.status == 400 {
                // Health refused it (too few points, say). Retrying will not
                // change its mind, and a stuck head would block the rest.
                pending.removeFirst()
                persist()
                lastError = error.localizedDescription
            } catch {
                lastError = error.localizedDescription
                return
            }
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

// MARK: - The session

/// One walk along one route: GPS, the filter, progress, and the recording.
///
/// Its own `CLLocationManager`, separate from the background movement
/// collector: that one is tuned to sleep, this one to be exact for an hour.
/// Started in the foreground, it keeps running with the screen off under the
/// blue location indicator — When In Use is enough for that.
@MainActor
final class FollowSession: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Phase: Equatable { case ready, following, paused, finished }

    let detail: PlannedRouteDetail
    @Published private(set) var phase: Phase = .ready
    @Published private(set) var progress: RouteNav.Progress?
    @Published private(set) var here: CLLocation?
    @Published private(set) var walked: [CLLocationCoordinate2D] = []
    @Published private(set) var distanceM: Double = 0
    @Published private(set) var elapsedS: Double = 0
    @Published private(set) var weakSignal = false
    @Published private(set) var denied = false

    /// Called once per fix accepted — the live share hangs off this.
    var onFix: ((CLLocation, RouteNav.Progress?) -> Void)?

    private var follower: RouteFollower
    private let manager = CLLocationManager()
    private var recording: RouteRecording
    private var lastRecorded: CLLocation?
    private var wasOffRoute = false
    private var ticker: Timer?
    private var pausedAt: Date?
    private var pausedTotal: TimeInterval = 0
    private var lastPersist = Date.distantPast

    private static let activeURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("route-follow-active.json")

    init(detail: PlannedRouteDetail) {
        self.detail = detail
        follower = RouteFollower(route: detail.route)
        recording = RouteRecording(
            clientId: UUID().uuidString.lowercased(),
            name: detail.name,
            sport: detail.sport,
            routeId: detail.id,
            startedAt: Date().timeIntervalSince1970,
            finishedAt: Date().timeIntervalSince1970,
            track: [],
            movingS: 0
        )
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
    }

    var coordinates: [CLLocationCoordinate2D] { follower.coordinates }

    /// Time left: Naismith on what is left of the route, the web's estimate.
    var timeLeftS: Double? {
        guard let p = progress else { return nil }
        let up = RouteNav.ascentAhead(detail.route, from: p.alongM, cumulative: follower.cumulative)
        return RouteNav.estimateTimeS(distanceM: p.remainingM, ascentM: up, sport: detail.sport)
    }

    func start() {
        guard phase == .ready || phase == .paused else { return }
        if phase == .paused, let pausedAt { pausedTotal += Date().timeIntervalSince(pausedAt) }
        pausedAt = nil
        if phase == .ready {
            recording = RouteRecording(
                clientId: recording.clientId, name: recording.name, sport: recording.sport, routeId: recording.routeId,
                startedAt: Date().timeIntervalSince1970, finishedAt: Date().timeIntervalSince1970, track: [], movingS: 0
            )
        }
        phase = .following
        if SRDemo.isOn {
            playDemo()
            return
        }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: denied = true; return
        default: break
        }
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        UIApplication.shared.isIdleTimerDisabled = true
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func pause() {
        guard phase == .following else { return }
        phase = .paused
        pausedAt = Date()
        manager.stopUpdatingLocation()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// Stop, queue the recording for upload, and send it if there is signal.
    /// A walk with under two points is not a recording and is dropped.
    @discardableResult
    func finish() -> RouteRecording? {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        ticker?.invalidate()
        UIApplication.shared.isIdleTimerDisabled = false
        phase = .finished
        try? FileManager.default.removeItem(at: Self.activeURL)
        guard recording.track.count >= 2 else { return nil }
        recording.finishedAt = Date().timeIntervalSince1970
        let done = recording
        RecordingQueue.shared.add(done)
        Task { await RecordingQueue.shared.flush() }
        return done
    }

    /// A walk the app was killed during becomes a recording ending at its
    /// last fix, rather than vanishing. Run once at launch.
    static func recoverInterrupted() {
        guard let data = try? Data(contentsOf: activeURL),
              var orphan = try? JSONDecoder().decode(RouteRecording.self, from: data) else { return }
        try? FileManager.default.removeItem(at: activeURL)
        guard orphan.track.count >= 2 else { return }
        if let lastSec = orphan.track.last?[3] ?? nil { orphan.finishedAt = orphan.startedAt + lastSec }
        Task { @MainActor in RecordingQueue.shared.add(orphan) }
    }

    // MARK: Fixes

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in locations.forEach(self.accept) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .denied, .restricted: self.denied = true
            case .authorizedAlways, .authorizedWhenInUse:
                self.denied = false
                if self.phase == .following {
                    manager.allowsBackgroundLocationUpdates = true
                    manager.startUpdatingLocation()
                }
            default: break
            }
        }
    }

    private func accept(_ fix: CLLocation) {
        guard phase == .following else { return }
        let verdict = FixFilter.classify(
            accuracy: fix.horizontalAccuracy, lat: fix.coordinate.latitude, lng: fix.coordinate.longitude
        )
        weakSignal = verdict != .accept
        guard verdict != .reject else { return }
        here = fix
        progress = follower.update(fix.coordinate)
        if let p = progress {
            if p.offRoute && !wasOffRoute { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
            if !p.offRoute && wasOffRoute { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            wasOffRoute = p.offRoute
        }
        guard FixFilter.shouldRecord(fix.timestamp, after: lastRecorded?.timestamp) else { return }
        if let last = lastRecorded {
            guard FixFilter.isPlausibleStep(from: last, to: fix, sport: detail.sport) else { return }
            let step = RouteNav.haversineM(last.coordinate, fix.coordinate)
            let dt = fix.timestamp.timeIntervalSince(last.timestamp)
            distanceM += step
            // Moving time: a gap under a minute at walking pace or better.
            if dt < 60, step / dt > 0.5 { recording.movingS += dt }
        }
        lastRecorded = fix
        walked.append(fix.coordinate)
        let sec = max(0, fix.timestamp.timeIntervalSince1970 - recording.startedAt)
        recording.track.append([
            fix.coordinate.longitude, fix.coordinate.latitude,
            fix.verticalAccuracy >= 0 ? fix.altitude : nil, sec.rounded(),
        ])
        onFix?(fix, progress)
        persistActive()
    }

    private func tick() {
        guard phase == .following else { return }
        elapsedS = Date().timeIntervalSince1970 - recording.startedAt - pausedTotal
    }

    /// Every 30 s, so a killed app loses at most that.
    private func persistActive() {
        guard Date().timeIntervalSince(lastPersist) > 30 else { return }
        lastPersist = Date()
        var snapshot = recording
        snapshot.finishedAt = Date().timeIntervalSince1970
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: Self.activeURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    // MARK: Demo

    /// `-SRDemo`: walk a third of the way round, then step off the route, so
    /// a screenshot shows progress and the off-route banner without a GPS.
    private func playDemo() {
        let pts = follower.coordinates
        guard pts.count > 10 else { return }
        let stop = pts.count / 3
        let base = Date().addingTimeInterval(-Double(stop) * 20)
        for i in stride(from: 0, through: stop, by: 2) {
            let c = pts[i]
            accept(CLLocation(
                coordinate: c, altitude: 30, horizontalAccuracy: 6, verticalAccuracy: 4,
                timestamp: base.addingTimeInterval(Double(i) * 20)
            ))
        }
        elapsedS = Double(stop) * 20
        if SRDemo.isOffRouteShot {
            let c = pts[stop]
            accept(CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: c.latitude + 0.0009, longitude: c.longitude + 0.0009),
                altitude: 30, horizontalAccuracy: 6, verticalAccuracy: 4, timestamp: Date()
            ))
        }
    }
}
