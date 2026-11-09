import Foundation

// "Your walking": each person's own movement figures, handed back to them
// (review 2026-11-09, O3). Two sources that know different things:
//
// - The SITE's trail (`GET /api/native/family/movement`): journeys between
//   named places — which trips you repeat, how long they take, how fast you
//   walk them, how you get about. Figures only; never a coordinate.
// - This phone's HEALTH data (`FamilyWalkingHealth`, the screen's file): how
//   you walk — the speed and step length the iPhone measures while you carry
//   it, and walking steadiness.
//
// This file is the wire shape and the words: PURE and Foundation-only
// (`FamilyWalkingTests`, run on Linux).

/// One person's movement, as the site counts it.
struct FamilyMovement: Decodable, Equatable {
    let subject: String
    let name: String
    let days: Int
    let stats: Stats

    struct Stats: Decodable, Equatable {
        let byMode: [String: ModeTotals]
        let walkingPace: Pace?
        let commonTrips: [Trip]
        let roundTrips: RoundTrips?
        let timeOut: [Day]

        private enum CodingKeys: String, CodingKey { case byMode, walkingPace, commonTrips, roundTrips, timeOut }

        init(byMode: [String: ModeTotals], walkingPace: Pace?, commonTrips: [Trip], roundTrips: RoundTrips?, timeOut: [Day]) {
            self.byMode = byMode; self.walkingPace = walkingPace; self.commonTrips = commonTrips
            self.roundTrips = roundTrips; self.timeOut = timeOut
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            byMode = (try? c.decodeIfPresent([String: ModeTotals].self, forKey: .byMode)) ?? [:]
            walkingPace = try? c.decodeIfPresent(Pace.self, forKey: .walkingPace)
            commonTrips = (try? c.decodeIfPresent([Trip].self, forKey: .commonTrips)) ?? []
            roundTrips = try? c.decodeIfPresent(RoundTrips.self, forKey: .roundTrips)
            timeOut = (try? c.decodeIfPresent([Day].self, forKey: .timeOut)) ?? []
        }
    }

    struct ModeTotals: Decodable, Equatable {
        let count: Int
        let metres: Double
        let seconds: Double
    }

    struct Pace: Decodable, Equatable {
        let medianMps: Double
        let p75Mps: Double
        let n: Int
        let weekly: [Week]

        struct Week: Decodable, Equatable {
            let weekStart: String
            let medianMps: Double
            let n: Int
        }
    }

    struct Trip: Decodable, Equatable, Identifiable {
        let fromLabel: String
        let toLabel: String
        let count: Int
        let usualDeparture: String
        let medianSeconds: Double
        let totalSeconds: Double
        /// "foot", "car", "rail", "other".
        let mode: String
        /// From a site older than these, absent.
        var medianMetres: Double? = nil
        var fastestSeconds: Double? = nil
        var medianPaceSecPerKm: Double? = nil
        var lastAt: String? = nil

        var id: String { "\(fromLabel)→\(toLabel)" }
    }

    struct RoundTrips: Decodable, Equatable {
        let count: Int
        let medianSeconds: Double
        let totalSeconds: Double
    }

    struct Day: Decodable, Equatable, Identifiable {
        let date: String
        let minutesOut: Double
        let firstOut: String?
        let lastIn: String?
        var id: String { date }
    }
}

enum WalkingWords {
    /// The NHS's "brisk": about 3 mph, 4.8 km/h.
    static let briskMps = 4.8 / 3.6

    /// "12:05 /km" from metres per second.
    static func pace(mps: Double) -> String {
        guard mps > 0 else { return "—" }
        return pace(secPerKm: 1000 / mps)
    }

    /// "12:05 /km".
    static func pace(secPerKm: Double) -> String {
        let s = Int(secPerKm.rounded())
        return String(format: "%d:%02d /km", s / 60, s % 60)
    }

    /// "5.1 km/h".
    static func speed(mps: Double) -> String {
        String(format: "%.1f km/h", mps * 3.6)
    }

    /// "Brisk", "Steady", "Easy" — the NHS's 3 mph is brisk.
    static func band(mps: Double) -> String {
        if mps >= briskMps { return "Brisk" }
        if mps >= 4.0 / 3.6 { return "Steady" }
        return "Easy"
    }

    /// "18 min", "1h 05m".
    static func duration(_ seconds: Double) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }

    /// "850 m", "2.4 km", "38 km".
    static func distance(_ metres: Double) -> String {
        if metres < 1000 { return "\(Int((metres / 10).rounded() * 10)) m" }
        return metres < 10_000 ? String(format: "%.1f km", metres / 1000) : String(format: "%.0f km", metres / 1000)
    }

    /// Whether the newest weeks are quicker or slower than the earlier ones:
    /// the median of the last two weeks with walks against the median of the
    /// weeks before. Nil with under four weeks, or a change under 15 s/km —
    /// GPS can't tell that apart from the route. PURE.
    static func trend(_ weekly: [FamilyMovement.Pace.Week]) -> (text: String, quicker: Bool)? {
        let weeks = weekly.filter { $0.n > 0 && $0.medianMps > 0 }.sorted { $0.weekStart < $1.weekStart }
        guard weeks.count >= 4 else { return nil }
        func median(_ xs: [Double]) -> Double {
            let s = xs.sorted(); let m = s.count / 2
            return s.count % 2 == 0 ? (s[m - 1] + s[m]) / 2 : s[m]
        }
        let recent = median(weeks.suffix(2).map { 1000 / $0.medianMps })
        let earlier = median(weeks.dropLast(2).map { 1000 / $0.medianMps })
        let delta = earlier - recent
        guard abs(delta) >= 15 else { return nil }
        let quicker = delta > 0
        let s = Int(abs(delta).rounded())
        let by = s >= 60 ? String(format: "%d:%02d", s / 60, s % 60) : "\(s) s"
        return ("\(quicker ? "Quicker" : "Slower") lately — \(by) per km \(quicker ? "faster" : "slower") than the weeks before", quicker)
    }

    /// The trips you walk, most-made first; then everything else. PURE.
    static func ordered(_ trips: [FamilyMovement.Trip]) -> (walked: [FamilyMovement.Trip], other: [FamilyMovement.Trip]) {
        let walked = trips.filter { $0.mode == "foot" }.sorted { $0.count > $1.count }
        let other = trips.filter { $0.mode != "foot" }.sorted { $0.count > $1.count }
        return (walked, other)
    }

    /// "Usually 17 min · best 14 min · 1.3 km · 13:05 /km". PURE.
    static func tripLine(_ trip: FamilyMovement.Trip) -> String {
        var parts = ["Usually \(duration(trip.medianSeconds))"]
        if let best = trip.fastestSeconds, trip.medianSeconds - best >= 60 { parts.append("best \(duration(best))") }
        if let metres = trip.medianMetres, metres > 0 { parts.append(distance(metres)) }
        if let pace = trip.medianPaceSecPerKm { parts.append(self.pace(secPerKm: pace)) }
        return parts.joined(separator: " · ")
    }

    /// "8 times · leaves about 08:24". PURE.
    static func tripWhen(_ trip: FamilyMovement.Trip) -> String {
        "\(trip.count) time\(trip.count == 1 ? "" : "s") · leaves about \(trip.usualDeparture)"
    }

    /// Walking a week, from the window's totals: "11.2 km a week". PURE.
    static func perWeek(metres: Double, days: Int) -> String {
        guard days > 0 else { return "—" }
        return "\(distance(metres / (Double(days) / 7))) a week"
    }

    /// The modes in the order a page lists them, with their words. PURE.
    static let modes: [(key: String, title: String, symbol: String)] = [
        ("foot", "On foot", "figure.walk"),
        ("car", "By car", "car.fill"),
        ("rail", "By train", "tram.fill"),
        ("other", "Cycling, running or other", "bicycle"),
    ]
}
