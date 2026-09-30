import Foundation
import CoreLocation

// Following a route with no signal: how far along it you are, how far off it,
// and how long is left.
//
// A PORT of SR-Health's `src/lib/trails/field/nav.ts` and `tracker.ts`, number
// for number — `RouteNavTests` repeats `field.test.ts`'s cases, so the phone
// and /health/record agree on what "off route" means. One addition the web
// does not have, `RouteFollower`, is explained on it.

/// `[lng, lat]` order is the web's; here a route is plain coordinates.
enum RouteNav {
    static let earthRadiusM = 6_371_008.8
    static let offRouteM = 50.0

    static func haversineM(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let φ1 = a.latitude * .pi / 180
        let φ2 = b.latitude * .pi / 180
        let Δφ = (b.latitude - a.latitude) * .pi / 180
        let Δλ = (b.longitude - a.longitude) * .pi / 180
        let h = sin(Δφ / 2) * sin(Δφ / 2) + cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)
        return 2 * earthRadiusM * asin(min(1, h.squareRoot()))
    }

    struct Nearest: Equatable {
        let distanceM: Double
        let point: CLLocationCoordinate2D
        /// Index of the segment start the nearest point falls on.
        let segmentIndex: Int
        /// Distance along the route to that point.
        let alongM: Double

        static func == (l: Nearest, r: Nearest) -> Bool {
            l.distanceM == r.distanceM && l.segmentIndex == r.segmentIndex && l.alongM == r.alongM
        }
    }

    /// Closest point on a segment, in local planar coordinates — longitude is
    /// scaled by cos(latitude) first, or the "nearest" point is visibly wrong
    /// on an east-west lane.
    static func project(_ p: CLLocationCoordinate2D, _ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D)
        -> (point: CLLocationCoordinate2D, t: Double) {
        var scale = cos((a.latitude + b.latitude) / 2 * .pi / 180)
        if scale == 0 { scale = 1e-6 }
        let ax = a.longitude * scale, ay = a.latitude
        let bx = b.longitude * scale, by = b.latitude
        let px = p.longitude * scale, py = p.latitude
        let dx = bx - ax, dy = by - ay
        let lenSq = dx * dx + dy * dy
        if lenSq == 0 { return (a, 0) }
        let t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / lenSq))
        return (CLLocationCoordinate2D(latitude: ay + dy * t, longitude: (ax + dx * t) / scale), t)
    }

    /// Cumulative distance to each vertex — `cumulative[i]` is metres to `route[i]`.
    static func cumulative(_ route: [CLLocationCoordinate2D]) -> [Double] {
        var out = [0.0]
        out.reserveCapacity(route.count)
        for i in route.indices.dropFirst() { out.append(out[i - 1] + haversineM(route[i - 1], route[i])) }
        return out
    }

    /// The web's `nearestPointOnRoute`, optionally limited to segments `range`.
    static func nearest(
        _ position: CLLocationCoordinate2D,
        on route: [CLLocationCoordinate2D],
        cumulative: [Double]? = nil,
        segments range: Range<Int>? = nil
    ) -> Nearest? {
        guard route.count >= 2 else { return nil }
        let along = cumulative ?? Self.cumulative(route)
        let all = 0..<(route.count - 1)
        let span = range.map { $0.clamped(to: all) } ?? all
        var best: Nearest?
        for i in span {
            let a = route[i], b = route[i + 1]
            let (point, t) = project(position, a, b)
            let d = haversineM(position, point)
            if best == nil || d < best!.distanceM {
                best = Nearest(distanceM: d, point: point, segmentIndex: i, alongM: along[i] + (along[i + 1] - along[i]) * t)
            }
        }
        return best
    }

    static func isOffRoute(_ distanceM: Double, threshold: Double = offRouteM) -> Bool { distanceM > threshold }

    struct Progress: Equatable {
        let alongM: Double
        let totalM: Double
        let fraction: Double
        let remainingM: Double
        let offRouteM: Double
        let offRoute: Bool
    }

    static func progress(_ position: CLLocationCoordinate2D, on route: [CLLocationCoordinate2D], threshold: Double = offRouteM) -> Progress? {
        let along = cumulative(route)
        guard let n = nearest(position, on: route, cumulative: along) else { return nil }
        return progress(n, totalM: along.last ?? 0, threshold: threshold)
    }

    static func progress(_ n: Nearest, totalM: Double, threshold: Double = offRouteM) -> Progress {
        Progress(
            alongM: n.alongM,
            totalM: totalM,
            fraction: totalM > 0 ? min(1, n.alongM / totalM) : 0,
            remainingM: max(0, totalM - n.alongM),
            offRouteM: n.distanceM,
            offRoute: isOffRoute(n.distanceM, threshold: threshold)
        )
    }

    // MARK: Naismith, per sport

    static let baseSpeedKmh: [String: Double] = ["walk": 5, "hike": 4.5, "run": 10, "trail_run": 8.5, "ride": 22, "mtb": 14]
    static let ascentPenaltySPerM: [String: Double] = ["walk": 3.6, "hike": 6, "run": 4.5, "trail_run": 6, "ride": 2.4, "mtb": 3.6]

    static func estimateTimeS(distanceM: Double, ascentM: Double, sport: String) -> Double {
        guard distanceM > 0 else { return 0 }
        let speed = baseSpeedKmh[sport] ?? baseSpeedKmh["walk"]!
        let penalty = ascentPenaltySPerM[sport] ?? ascentPenaltySPerM["walk"]!
        return distanceM / 1000 / speed * 3600 + max(0, ascentM) * penalty
    }

    /// Metres of climb still ahead, from the route's own heights.
    static func ascentAhead(_ route: [RoutePoint], from alongM: Double, cumulative along: [Double]) -> Double {
        var up = 0.0
        for i in route.indices.dropFirst() where along[i] > alongM {
            if let a = route[i - 1].ele, let b = route[i].ele, b > a { up += b - a }
        }
        return up
    }
}

// MARK: - The fix filter (`tracker.ts`)

enum FixFilter {
    enum Verdict { case accept, flag, reject }

    /// Beyond this the fix is a guess from cell towers, not GPS.
    static let rejectAccuracyM = 100.0
    /// Usable, but shown as uncertain.
    static let flagAccuracyM = 30.0
    /// A point every 3 s is plenty.
    static let minInterval: TimeInterval = 3
    /// No one runs at 45 km/h; a jump that fast is a fix error.
    static let maxPlausibleSpeed = 12.5
    /// A bike is allowed faster — the web's 12.5 m/s would drop a descent.
    static let maxPlausibleRideSpeed = 25.0

    static func classify(accuracy: Double, lat: Double, lng: Double) -> Verdict {
        guard lat.isFinite, lng.isFinite, accuracy >= 0 else { return .reject }
        if accuracy > rejectAccuracyM { return .reject }
        if accuracy > flagAccuracyM { return .flag }
        return .accept
    }

    static func shouldRecord(_ now: Date, after last: Date?) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= minInterval
    }

    static func isPlausibleStep(from a: CLLocation, to b: CLLocation, sport: String = "walk") -> Bool {
        let dt = b.timestamp.timeIntervalSince(a.timestamp)
        guard dt > 0 else { return false }
        let limit = sport == "ride" || sport == "mtb" ? maxPlausibleRideSpeed : maxPlausibleSpeed
        return RouteNav.haversineM(a.coordinate, b.coordinate) / dt <= limit
    }
}

// MARK: - Following, not just measuring

/// Where you are on a route, remembered from fix to fix.
///
/// The web asks "which point of the WHOLE route is nearest?" every fix. On a
/// loop the start and the finish are the same place, so a walker setting off
/// reads 100% done; on a figure-of-eight or an out-and-back they jump between
/// the two passes. A person following a route moves forward along it, so this
/// searches a window from where they last were — a little behind (GPS
/// wobble, a step back to a gate) to well ahead — and only falls back to the
/// whole route when nothing in the window is close, which is what rejoining
/// after a detour looks like.
struct RouteFollower {
    let route: [RoutePoint]
    let coordinates: [CLLocationCoordinate2D]
    let cumulative: [Double]
    var totalM: Double { cumulative.last ?? 0 }

    /// Metres along the route last matched.
    private(set) var alongM: Double = 0

    static let behindM = 150.0
    static let aheadM = 1500.0

    init(route: [RoutePoint]) {
        self.route = route
        coordinates = route.map(\.coordinate)
        cumulative = RouteNav.cumulative(coordinates)
    }

    mutating func update(_ position: CLLocationCoordinate2D) -> RouteNav.Progress? {
        guard coordinates.count >= 2 else { return nil }
        let low = segment(atOrBefore: alongM - Self.behindM)
        let high = segment(atOrBefore: alongM + Self.aheadM) + 1
        var match = RouteNav.nearest(position, on: coordinates, cumulative: cumulative, segments: low..<high)
        if match.map({ RouteNav.isOffRoute($0.distanceM) }) ?? true,
           let anywhere = RouteNav.nearest(position, on: coordinates, cumulative: cumulative),
           !RouteNav.isOffRoute(anywhere.distanceM) {
            match = anywhere
        }
        guard let n = match else { return nil }
        // Off the route, the last place ON it stays the reference: a detour
        // does not move you along.
        if !RouteNav.isOffRoute(n.distanceM) { alongM = n.alongM }
        return RouteNav.progress(n, totalM: totalM)
    }

    /// The last segment whose start is at or before `metres`.
    private func segment(atOrBefore metres: Double) -> Int {
        guard metres > 0 else { return 0 }
        var lo = 0, hi = cumulative.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if cumulative[mid] <= metres { lo = mid } else { hi = mid - 1 }
        }
        return min(lo, coordinates.count - 2)
    }
}
