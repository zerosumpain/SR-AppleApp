import Foundation
import CoreLocation

/// Notices arriving at and leaving a trip day's stops, by geofence.
///
/// iOS gives an app TWENTY monitored regions, shared by every location
/// manager in it. `LocationCollector` already holds the motion gate's anchor
/// and up to fifteen watched family places (`regionsReserved`); a region
/// registered past the limit fails, and one this registered could crowd out
/// a family place the collector adds later. So this takes only what is left,
/// at most fifteen, and ROLLS: the next few upcoming stops of today, re-chosen
/// every time a stop is reached, skipped or re-planned.
///
/// What it records are ordinary `arrived` / `left` events, marked as
/// detected; the Day screen lets the person correct either.
@MainActor
final class TripArrivals: NSObject, CLLocationManagerDelegate {
    static let shared = TripArrivals()

    static let regionPrefix = "sr.trip."
    static let maximum = 15
    static let appLimit = 20
    /// Around a stop. iOS is unreliable under ~100 m.
    static let radiusM = 100.0
    /// An arrival this long before the plan's time is passing by, not arriving.
    static let earlyLimitMin = 90.0
    /// Out again this quickly is walking past, not a visit.
    static let passingBySec: TimeInterval = 180

    private let manager = CLLocationManager()
    private var reserved: @MainActor () -> Int = { 1 + WatchedPlace.maximum }
    private var started = false

    private override init() {
        super.init()
    }

    /// At launch, before any scene: a geofence crossing relaunches the app in
    /// the background, and this must be the delegate it finds.
    func start(reserved: @escaping @MainActor () -> Int) {
        self.reserved = reserved
        guard !started else { return }
        started = true
        manager.delegate = self
        refresh()
    }

    /// Re-choose the monitored stops for the running day.
    func refresh(now: Date = Date()) {
        guard started, !SRDemo.isOn, CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        let ours = manager.monitoredRegions.filter { $0.identifier.hasPrefix(Self.regionPrefix) }
        let foreign = manager.monitoredRegions.count - ours.count
        let budget = Self.budget(reserved: reserved(), foreignNow: foreign)
        let wanted = Self.wanted(store: TripStore.shared, now: now, budget: budget)
        let wantedIds = Set(wanted.map(\.identifier))
        for region in ours where !wantedIds.contains(region.identifier) {
            manager.stopMonitoring(for: region)
        }
        let have = Set(ours.map(\.identifier))
        for region in wanted where !have.contains(region.identifier) {
            manager.startMonitoring(for: region)
        }
    }

    /// What is left of the twenty: never more than fifteen, never into what
    /// the collector holds or may yet register.
    nonisolated static func budget(reserved: Int, foreignNow: Int) -> Int {
        max(0, min(maximum, appLimit - max(reserved, foreignNow)))
    }

    /// Today's stops still to come, in plan order, as regions. The morning's
    /// stay is watched for its exit only.
    private static func wanted(store: TripStore, now: Date, budget: Int) -> [CLCircularRegion] {
        guard budget > 0, let running = store.running(now: now) else { return [] }
        let tripId = running.bundle.trip.id
        guard let day = store.day(tripId, running.date) else { return [] }
        let marks = store.marks(tripId)
        var regions: [CLCircularRegion] = []
        for (i, stop) in day.stops.enumerated() where regions.count < budget {
            guard let at = stop.location, marks[stop.id]?.done != true else { continue }
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: at.lat, longitude: at.lng),
                radius: radiusM,
                identifier: identifier(trip: tripId, date: day.date, stop: stop.id)
            )
            // The morning's stay is watched for LEAVING only: you start
            // there, and its exit is what says the day has begun.
            region.notifyOnEntry = !(i == 0 && stop.kind == .stay)
            region.notifyOnExit = true
            regions.append(region)
        }
        return regions
    }

    nonisolated static func identifier(trip: String, date: String, stop: String) -> String {
        "\(regionPrefix)\(trip)|\(date)|\(stop)"
    }

    nonisolated static func parse(_ identifier: String) -> (trip: String, date: String, stop: String)? {
        guard identifier.hasPrefix(regionPrefix) else { return nil }
        let parts = identifier.dropFirst(regionPrefix.count).split(separator: "|", maxSplits: 2).map(String.init)
        return parts.count == 3 ? (parts[0], parts[1], parts[2]) : nil
    }

    // MARK: Crossings

    private func entered(_ identifier: String, at now: Date) {
        guard let key = Self.parse(identifier),
              let day = TripStore.shared.day(key.trip, key.date),
              let stop = day.stops.first(where: { $0.id == key.stop }),
              let clock = TripStore.shared.clock(key.trip),
              clock.localDate(now) == key.date else { return }
        let mark = TripStore.shared.marks(key.trip)[stop.id]
        guard mark?.arrivedAt == nil, mark?.done != true else { return }
        // Walking past the Pantheon at ten on the way to the Forum is not
        // visiting it — its turn is this afternoon.
        guard clock.minutes(now) >= stop.arriveMin - Self.earlyLimitMin else { return }
        // Back at the stay mid-afternoon is a stop at the stay, not the end
        // of the day, unless nothing else is left.
        if stop.kind == .stay, let progress = TripStore.shared.progress(key.trip, key.date, now: now),
           progress.currentIndex != day.index(of: stop.id), clock.minutes(now) < stop.arriveMin - 60 { return }
        TripStore.shared.record(.arrived, tripId: key.trip, stop: stop, at: now, detail: ["detected": .bool(true)])
        refresh(now: now)
    }

    private func exited(_ identifier: String, at now: Date) {
        guard let key = Self.parse(identifier),
              let day = TripStore.shared.day(key.trip, key.date),
              let stop = day.stops.first(where: { $0.id == key.stop }) else { return }
        let mark = TripStore.shared.marks(key.trip)[stop.id]
        // Leaving the morning's stay starts the day: nothing records arriving there.
        if stop.kind == .stay, day.index(of: stop.id) == 0 {
            if mark?.leftAt == nil {
                TripStore.shared.record(.left, tripId: key.trip, stop: stop, at: now, detail: ["detected": .bool(true)])
                refresh(now: now)
            }
            return
        }
        guard let mark, let arrived = mark.arrivedAt, mark.leftAt == nil, !mark.skipped else { return }
        if now.timeIntervalSince(arrived) < Self.passingBySec && !mark.corrected {
            TripStore.shared.clear(stop.id, tripId: key.trip)
            return
        }
        TripStore.shared.record(.left, tripId: key.trip, stop: stop, at: now, detail: ["detected": .bool(true)])
        refresh(now: now)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let id = region.identifier
        guard id.hasPrefix(Self.regionPrefix) else { return }
        let now = Date()
        Task { @MainActor in self.entered(id, at: now) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        let id = region.identifier
        guard id.hasPrefix(Self.regionPrefix) else { return }
        let now = Date()
        Task { @MainActor in self.exited(id, at: now) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        // Most likely the twenty are full after all: say nothing, try again
        // with a smaller set on the next refresh.
    }
}
