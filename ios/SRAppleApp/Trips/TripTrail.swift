import Foundation
import CoreLocation

/// Where the phone has been on the running trip day, so the map can take
/// what is behind you off it (`TripMapScene.Walked`).
///
/// It asks for no location of its own. It keeps what already arrives: the
/// family location's GPS while you are moving (`LocationCollector`), the
/// off-plan watch's wake-ups (`TripOffPlan`), and the blue dot while a trip
/// map is open. Kept on the phone only, for today, a point every
/// `spacingM`; it never leaves the device.
@MainActor
final class TripTrail: ObservableObject {
    static let shared = TripTrail()

    /// A point is kept once it is this far from the last one kept.
    static let spacingM = 12.0
    /// Fixes worse than this would walk streets you never set foot in.
    static let worstAccuracyM = 50.0
    static let maximum = 4000
    private static let key = "trips.trail"

    private struct Stored: Codable {
        var tripId: String
        var date: String
        var points: [TripLatLng]
    }

    /// Today's, for the running trip.
    @Published private(set) var points: [TripLatLng] = []
    private var tripId: String?
    private var date: String?
    /// Written at most this often: a walk adds a point every few seconds.
    private static let saveEverySec: TimeInterval = 30
    private var savedAt = Date.distantPast

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            tripId = stored.tripId
            date = stored.date
            points = stored.points
        }
    }

    /// The trail for a trip's day: empty unless it is the one being kept.
    func points(_ tripId: String, _ date: String) -> [TripLatLng] {
        tripId == self.tripId && date == self.date ? points : []
    }

    /// What the map takes off for a trip's day: nil when there is nothing
    /// to go on.
    func walked(_ tripId: String, _ date: String) -> TripMapScene.Walked? {
        let trail = points(tripId, date)
        return trail.isEmpty ? nil : TripMapScene.Walked(trail: trail)
    }

    func add(_ locations: [CLLocation]) {
        guard !SRDemo.isOn else { return }
        let good = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= Self.worstAccuracyM }
        guard let newest = good.last, let running = TripStore.shared.running(now: newest.timestamp) else { return }
        let trip = running.bundle.trip.id
        let clock = TripClock(running.bundle.trip.timeZone)
        // A new day (or trip) starts a new trail: yesterday is off the map anyway.
        if trip != tripId || running.date != date {
            tripId = trip
            date = running.date
            points = []
        }
        var next = points
        for fix in good where clock.localDate(fix.timestamp) == running.date {
            let p = TripLatLng(lat: fix.coordinate.latitude, lng: fix.coordinate.longitude)
            if let last = next.last, TripMapScene.distanceM(last, p) < Self.spacingM { continue }
            next.append(p)
        }
        guard next.count != points.count else { return }
        points = Array(next.suffix(Self.maximum))
        if Date().timeIntervalSince(savedAt) >= Self.saveEverySec { save() }
    }

    private func save() {
        savedAt = Date()
        guard let tripId, let date,
              let data = try? JSONEncoder().encode(Stored(tripId: tripId, date: date, points: points)) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
