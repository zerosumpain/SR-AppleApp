import Foundation

/// The trip story's matching (v7, proposal D): which of the phone's photos
/// belong to which stop — taken during the stop's time (with half an hour
/// either side) and within 400 m of it. A photo with no location is matched
/// by time alone only when exactly one stop was running then.
///
/// Foundation only: the Linux harness compiles and tests it.
enum TripStoryMatch {
    struct Photo: Equatable {
        var id: String
        /// Local minutes after midnight on the day (the trip's zone).
        var minute: Double
        var at: TripLatLng?
    }

    static let slackMin = 30.0
    static let nearM = 400.0

    /// Stop id → the photos taken there, in time order. Each photo goes to
    /// one stop at most: the nearest of those it fits.
    static func assign(_ photos: [Photo], to day: PlannedDay) -> [String: [String]] {
        let stops = day.stops.filter { $0.kind == .wish || $0.kind == .meal || TripMapScene.isVisit($0) }
        var out: [String: [String]] = [:]
        for photo in photos.sorted(by: { $0.minute < $1.minute }) {
            let running = stops.filter { photo.minute >= $0.arriveMin - slackMin && photo.minute <= $0.departMin + slackMin }
            var best: (id: String, metres: Double)?
            if let at = photo.at {
                for stop in running {
                    guard let loc = stop.location else { continue }
                    let m = metres(at, loc)
                    if m <= nearM, best == nil || m < best!.metres { best = (stop.id, m) }
                }
            } else if running.count == 1 {
                best = (running[0].id, 0)
            }
            if let best { out[best.id, default: []].append(photo.id) }
        }
        return out
    }

    static func metres(_ a: TripLatLng, _ b: TripLatLng) -> Double {
        let r = 6_371_000.0
        let dLat = (b.lat - a.lat) * .pi / 180
        let dLng = (b.lng - a.lng) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(a.lat * .pi / 180) * cos(b.lat * .pi / 180) * sin(dLng / 2) * sin(dLng / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }
}
