import Foundation

// Home's family block: the board that replaced the Orbit (review 2026-11-09, O1).
//
// The Orbit answered "how far and which way", which nobody asks of their
// family at a glance. A glance asks four things: who is where, since when, who
// is on the way, and when they will get there. The board says all four in
// words, one row per person, and adds the one thing no tracker shows — the
// SHAPE of each person's day so far, as a strip: home, out, travelling.
//
// PURE and Foundation-only (`FamilyBoardTests`, run on Linux). The view in
// `Home/HomeFamilyBoard.swift` adapts a `HouseholdView` and the forecast into
// `FamilyBoardInput` and draws `FamilyBoardRow`s.

/// One person, as the board needs them: plain values, no CoreLocation.
struct FamilyBoardInput: Equatable {
    struct Person: Equatable {
        var subject: String
        var name: String
        var isSelf: Bool
        /// "home", "out", "unknown", "off".
        var status: String
        /// "Home", "School", a street — or nil.
        var place: String?
        /// The phone's name for where a mover is now ("Station Road"), if known.
        var near: String? = nil
        /// "walking", "active", "vehicle" — moving now, or nil.
        var movingMode: String? = nil
        var movingSince: Double? = nil
        var speedKmh: Double? = nil
        var battery: Int? = nil
        var lastSeen: Double? = nil
        var lat: Double? = nil
        var lon: Double? = nil
        /// Today's `[lat, lon, epoch]`, where their day is the viewer's to see.
        var trail: [[Double]]? = nil
        /// The forecast's live journey for them (`kind: arriving`).
        var journey: Journey? = nil
    }

    struct Journey: Equatable {
        let to: String
        let leftAt: Double?
        let arriveFrom: Double
        let arriveTo: Double
    }

    let people: [Person]
    /// Home, where known: what "home" in the strip means.
    var home: (lat: Double, lon: Double)? = nil
    /// The strip's left edge (06:00 local, or earlier if the day began earlier).
    let dayStart: Double
    let now: Double

    static func == (a: FamilyBoardInput, b: FamilyBoardInput) -> Bool {
        a.people == b.people && a.home?.lat == b.home?.lat && a.home?.lon == b.home?.lon && a.dayStart == b.dayStart && a.now == b.now
    }
}

/// What one slice of a day was.
enum FamilyBand: String, Equatable {
    /// No fix to go by.
    case none
    case home
    case away
    case moving
}

/// One row of the board.
struct FamilyBoardRow: Equatable, Identifiable {
    let subject: String
    let name: String
    let isSelf: Bool
    /// "At School", "Home", "Walking near Station Road", "Not sharing".
    let headline: String
    /// "since 08:41", "for 12 min", "seen 3h ago" — or nil.
    let since: String?
    /// For a mover the forecast has a destination for.
    let journey: JourneyLine?
    /// The day so far, left to right; empty where the day is not the viewer's.
    let strip: [FamilyBand]
    let lowBattery: Bool
    let battery: Int?
    let stale: Bool
    let moving: Bool
    let sharing: Bool

    var id: String { subject }

    struct JourneyLine: Equatable {
        let to: String
        /// "08:47", or "08:45–08:50".
        let eta: String
        /// How far through the journey, 0…1, when it is known when they left.
        let progress: Double?
    }

    /// One sentence for VoiceOver: "Rory, at School since 08:41, battery 54%."
    var spoken: String {
        var parts = ["\(isSelf ? "You" : name), \(headline.prefix(1).lowercased() + headline.dropFirst())"]
        if let since { parts[0] += " \(since)" }
        if let journey { parts.append("heading to \(journey.to), arriving \(journey.eta)") }
        if let battery { parts.append("battery \(battery)%\(lowBattery ? ", low" : "")") }
        if stale { parts.append("not seen lately") }
        return parts.joined(separator: ", ") + "."
    }
}

enum FamilyBoard {
    /// Slices across the day strip.
    static let bins = 36
    /// Within this of home is home.
    static let homeMetres = 200.0
    /// Within this of where they are now is "still there".
    static let stayMetres = 150.0
    /// Faster than this between two fixes is travelling.
    static let movingMps = 1.0
    /// A gap longer than this in the trail is "no fix", not more of the same.
    static let gapSeconds = 20.0 * 60
    /// Stale: not heard from in this long.
    static let staleSeconds = 2.0 * 3600

    /// The rows, in order: whoever is moving first (it is what changes), then
    /// you, then everyone else as the site sent them. Not sharing comes last.
    static func rows(_ input: FamilyBoardInput, clock: (Double) -> String) -> [FamilyBoardRow] {
        let rows = input.people.map { row($0, input: input, clock: clock) }
        let indexed = Array(rows.enumerated())
        return indexed.sorted { a, b in
            func rank(_ r: FamilyBoardRow) -> Int { !r.sharing ? 3 : r.moving ? 0 : r.isSelf ? 1 : 2 }
            let (x, y) = (rank(a.element), rank(b.element))
            return x != y ? x < y : a.offset < b.offset
        }.map(\.element)
    }

    static func row(_ p: FamilyBoardInput.Person, input: FamilyBoardInput, clock: (Double) -> String) -> FamilyBoardRow {
        let now = input.now
        let sharing = p.status != "off"
        let stale = sharing && (p.lastSeen.map { now - $0 >= staleSeconds } ?? false)
        let low = sharing && (p.battery.map { $0 <= 20 } ?? false)
        let headline = headlineFor(p)
        var since: String?
        if !sharing {
            since = nil
        } else if p.movingMode != nil, let started = p.movingSince {
            since = "for \(duration(now - started))"
        } else if stale, let seen = p.lastSeen {
            since = "seen \(duration(now - seen)) ago"
        } else if let lat = p.lat, let lon = p.lon, let trail = p.trail,
                  let arrived = arrivedAt(trail: trail, lat: lat, lon: lon) {
            since = arrived.wholeTrail ? "all day" : "since \(clock(arrived.t))"
        }
        let journey = p.movingMode == nil ? nil : p.journey.map { j -> FamilyBoardRow.JourneyLine in
            let a = clock(j.arriveFrom), b = clock(j.arriveTo)
            let mid = (j.arriveFrom + j.arriveTo) / 2
            let progress = j.leftAt.flatMap { left -> Double? in
                guard mid > left else { return nil }
                return min(0.95, max(0.05, (now - left) / (mid - left)))
            }
            return .init(to: j.to, eta: a == b ? a : "\(a)–\(b)", progress: progress)
        }
        let strip: [FamilyBand] = sharing ? (p.trail.map { bands(trail: $0, home: input.home, from: input.dayStart, to: now) } ?? []) : []
        return FamilyBoardRow(subject: p.subject, name: p.name, isSelf: p.isSelf, headline: headline, since: since,
                              journey: journey, strip: strip, lowBattery: low, battery: sharing ? p.battery : nil,
                              stale: stale, moving: p.movingMode != nil, sharing: sharing)
    }

    /// "At School", "Home", "Walking near Station Road", "Driving".
    static func headlineFor(_ p: FamilyBoardInput.Person) -> String {
        if p.status == "off" { return "Not sharing" }
        if let mode = p.movingMode {
            let verb: String
            switch mode {
            case "walking": verb = "Walking"
            case "vehicle": verb = "Travelling"
            default: verb = "On the move"
            }
            if let near = p.near, !near.isEmpty { return "\(verb) near \(near)" }
            return verb
        }
        if p.status == "home" || p.place == "Home" { return "Home" }
        if let place = p.place, !place.isEmpty { return p.status == "unknown" ? "Last at \(place)" : "At \(place)" }
        return p.status == "unknown" ? "Not seen lately" : "Out"
    }

    /// When they got to where they are now: walking back through today's
    /// trail from the newest fix while it stays within `stayMetres` of here.
    /// `wholeTrail` when every fix today is here. Nil with no trail, or when
    /// the newest fix is not here (the trail is behind the pin). PURE.
    static func arrivedAt(trail: [[Double]], lat: Double, lon: Double) -> (t: Double, wholeTrail: Bool)? {
        let points = trail.filter { $0.count >= 3 }.sorted { $0[2] < $1[2] }
        guard let newest = points.last, metres(newest[0], newest[1], lat, lon) <= stayMetres else { return nil }
        var earliest = newest[2]
        for p in points.reversed() {
            guard metres(p[0], p[1], lat, lon) <= stayMetres else { return (earliest, false) }
            earliest = p[2]
        }
        return (earliest, true)
    }

    /// The day so far in `bins` slices from `from` to `to`: travelling where
    /// two fixes in the slice are further apart than walking pace allows for
    /// standing, home near home, away elsewhere, none where the trail has
    /// nothing within `gapSeconds`. PURE.
    static func bands(trail: [[Double]], home: (lat: Double, lon: Double)?, from: Double, to: Double, bins: Int = bins) -> [FamilyBand] {
        guard to > from, bins > 0 else { return [] }
        let points = trail.filter { $0.count >= 3 && $0[2] >= from - gapSeconds && $0[2] <= to }.sorted { $0[2] < $1[2] }
        let width = (to - from) / Double(bins)
        var out: [FamilyBand] = []
        var cursor = 0
        for i in 0..<bins {
            let a = from + Double(i) * width, b = a + width
            while cursor < points.count && points[cursor][2] < a { cursor += 1 }
            var inside: [[Double]] = []
            var j = cursor
            while j < points.count && points[j][2] < b { inside.append(points[j]); j += 1 }
            // The fix just before the slice says where it began.
            let before = cursor > 0 ? points[cursor - 1] : nil
            let span = ([before].compactMap { $0 } + inside)
            if span.isEmpty || (inside.isEmpty && (before.map { a - $0[2] > gapSeconds } ?? true)) {
                out.append(.none)
                continue
            }
            var moved = false
            for k in span.indices.dropFirst() {
                let p = span[k - 1], q = span[k]
                let dt = q[2] - p[2]
                guard dt > 0, dt <= gapSeconds else { continue }
                let d = metres(p[0], p[1], q[0], q[1])
                if d > 40 && d / dt >= movingMps { moved = true; break }
            }
            if moved { out.append(.moving); continue }
            let here = inside.last ?? before!
            if let home, metres(here[0], here[1], home.lat, home.lon) <= homeMetres {
                out.append(.home)
            } else {
                out.append(.away)
            }
        }
        return out
    }

    /// "12 min", "2h 05m".
    static func duration(_ seconds: Double) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }

    static func metres(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let x = (lon2 - lon1) * cos((lat1 + lat2) / 2 * .pi / 180) * 111_320
        let y = (lat2 - lat1) * 111_320
        return (x * x + y * y).squareRoot()
    }
}
