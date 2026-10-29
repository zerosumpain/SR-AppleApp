import Foundation

// Manhunt's phone-side extras for the play screen: where the last ping is
// from me (distance and a compass word), how much of a clock is left as a
// share, the one line that says what to do now, and a record of how this
// phone's player has done, kept on this phone. Pure values on raw degrees and
// milliseconds, so each is a unit test. Nothing here travels to the site or
// decides anything the server owns: the server still judges every catch.

enum ManhuntPlayKit {
    /// Metres between two points (haversine), on raw degrees.
    static func metres(fromLat: Double, fromLng: Double, toLat: Double, toLng: Double) -> Double {
        let values = [fromLat, fromLng, toLat, toLng]
        guard values.allSatisfy({ $0.isFinite }) else { return .nan }
        let r = 6_371_000.0
        let dLat = (toLat - fromLat) * .pi / 180
        let dLng = (toLng - fromLng) * .pi / 180
        let a = fromLat * .pi / 180, b = toLat * .pi / 180
        let h = pow(sin(dLat / 2), 2) + cos(a) * cos(b) * pow(sin(dLng / 2), 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }

    /// The initial bearing from one point to another, 0 ..< 360 (0 is north).
    static func bearing(fromLat: Double, fromLng: Double, toLat: Double, toLng: Double) -> Double {
        let a = fromLat * .pi / 180, b = toLat * .pi / 180
        let dLng = (toLng - fromLng) * .pi / 180
        let y = sin(dLng) * cos(b)
        let x = cos(a) * sin(b) - sin(a) * cos(b) * cos(dLng)
        guard x.isFinite, y.isFinite, x != 0 || y != 0 else { return 0 }
        let degrees = atan2(y, x) * 180 / .pi
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    static let compassWords = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]

    /// "north", "south-west": the nearest of the eight points.
    static func compass(_ degrees: Double) -> String {
        guard degrees.isFinite else { return "" }
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        let index = Int((d / 45).rounded()) % 8
        return compassWords[index]
    }

    /// "80 m", "140 m", "1.2 km" — tens of metres under a kilometre, since a
    /// phone's fix is no sharper than that and a jumpy last digit is noise.
    static func distance(_ m: Double) -> String {
        guard m.isFinite, m >= 0 else { return "–" }
        if m >= 995 {
            let km = (m / 100).rounded() / 10
            return km == km.rounded() ? "\(Int(km)) km" : String(format: "%.1f km", km)
        }
        if m < 10 { return "\(Int(m.rounded())) m" }
        return "\(Int((m / 10).rounded()) * 10) m"
    }

    /// A catch reach, to the metre: "25 m". Not rounded to tens like a
    /// whereabouts, since "within 30 m" for a 25 m reach would send a hunter
    /// at 28 m to tap Catch and miss.
    static func reach(_ m: Double) -> String {
        guard m.isFinite, m >= 0 else { return "–" }
        if m >= 1_000 { return distance(m) }
        return "\(Int(m.rounded())) m"
    }

    /// Close enough to say "right by you" rather than a distance and a direction.
    static let besideM: Double = 15

    /// "140 m north-east", or "right by you".
    static func whereabouts(metres m: Double, bearing: Double) -> String {
        guard m.isFinite else { return "" }
        if m < besideM { return "right by you" }
        return "\(distance(m)) \(compass(bearing))"
    }

    /// How much of a span is left, 0 ... 1. A missing or empty span reads as none.
    static func fraction(left: Double?, total: Double?) -> Double {
        guard let left, let total, left.isFinite, total.isFinite, total > 0 else { return 0 }
        return min(1, max(0, left / total))
    }

    /// The last ten seconds before a ping: the clock warns and the phone taps.
    static let pingWarnMs: Double = 10_000

    static func pingSoon(_ left: Double?) -> Bool {
        guard let left, left.isFinite else { return false }
        return left > 0 && left <= pingWarnMs
    }

    /// Whole seconds left, rounded up: "Catch again in 4 s".
    static func secondsUp(_ ms: Double?) -> Int {
        guard let ms, ms.isFinite, ms > 0 else { return 0 }
        return Int((ms / 1000).rounded(.up))
    }

    /// Who is doing what, for the line under the headline.
    enum Seat: Equatable { case runner, hunter, watching }

    /// The one line that says what to do now.
    static func nowLine(headstart: Bool, seat: Seat, live: Bool, claimByMe: Bool, claimOnMe: Bool,
                        runnerName: String, lead: String?, catchM: Double) -> String {
        let within = reach(catchM)
        if headstart {
            switch seat {
            case .runner: return "Go! Get well away and find somewhere to hide inside the circle."
            case .hunter: return "Stay where you are and give \(runnerName) a fair start. No peeking."
            case .watching: return "\(runnerName.prefix(1).uppercased())\(runnerName.dropFirst()) is getting away."
            }
        }
        if claimOnMe { return "A hunter says they caught you. If they did, own up." }
        if claimByMe { return "Waiting for \(runnerName) to own up. If they don't answer, your catch stands." }
        switch seat {
        case .runner:
            return live
                ? "You're outside the circle, so the hunters can see you. Get back in!"
                : "Keep moving and stay inside the circle. Every ping shows the hunters where you are."
        case .hunter:
            if live { return "\(runnerName) is showing on the map right now. Go, go, go!" }
            if let lead, !lead.isEmpty { return "\(runnerName) was last seen \(lead). Get within \(within), then tap Catch." }
            return "Wait for the first ping, then head for it. Get within \(within) to catch."
        case .watching:
            return "You're watching this one."
        }
    }
}

// MARK: - The record on this phone

/// What one finished game did to the record, for the results page.
struct ManhuntRecordNote: Equatable {
    let record: ManhuntRecord
    /// "Your first escape!", "New best: 3 wins in a row" — or nil.
    let headline: String?
}

/// How this phone's player has done at Manhunt: games, escapes as the runner,
/// catches and team wins as a hunter, and the longest run of wins. Each game
/// is counted once however often its results page is shown.
struct ManhuntRecord: Codable, Equatable {
    var games = 0
    var runs = 0
    var escapes = 0
    var hunts = 0
    var teamWins = 0
    var catches = 0
    var streak = 0
    var bestStreak = 0
    /// The last few games counted, so a page shown twice counts once.
    var seen: [String] = []
    /// The last game counted and what it said, to say it again.
    var lastToken: String?
    var lastHeadline: String?

    static let remembered = 24

    var wins: Int { escapes + teamWins }

    /// Counts a finished game. `runner` is the seat I played; `won` is my
    /// side winning; `madeCatch` is the catch being mine.
    mutating func record(token: String, runner: Bool, won: Bool, madeCatch: Bool) -> ManhuntRecordNote {
        if seen.contains(token) {
            return ManhuntRecordNote(record: self, headline: lastToken == token ? lastHeadline : nil)
        }
        seen.append(token)
        if seen.count > Self.remembered { seen.removeFirst(seen.count - Self.remembered) }
        games += 1
        var headline: String?
        if runner {
            runs += 1
            if won {
                escapes += 1
                if escapes == 1 { headline = "Your first escape!" }
            }
        } else {
            hunts += 1
            if won { teamWins += 1 }
            if madeCatch {
                catches += 1
                if catches == 1 { headline = "Your first catch!" }
            }
        }
        if won {
            streak += 1
            if streak > bestStreak {
                bestStreak = streak
                if streak >= 2, headline == nil { headline = "New best: \(streak) wins in a row" }
            }
        } else {
            streak = 0
        }
        lastToken = token
        lastHeadline = headline
        return ManhuntRecordNote(record: self, headline: headline)
    }
}

/// Where the record lives: one small JSON value in UserDefaults, under a key
/// that starts with the game's id.
struct ManhuntRecordStore {
    var key = "manhunt.record.v1"
    var defaults: UserDefaults = .standard

    func load() -> ManhuntRecord {
        guard let data = defaults.data(forKey: key),
              let record = try? JSONDecoder().decode(ManhuntRecord.self, from: data) else { return ManhuntRecord() }
        return record
    }

    func save(_ record: ManhuntRecord) {
        if let data = try? JSONEncoder().encode(record) { defaults.set(data, forKey: key) }
    }

    /// Counts a finished game once and keeps it.
    @discardableResult
    func record(token: String, runner: Bool, won: Bool, madeCatch: Bool) -> ManhuntRecordNote {
        var record = load()
        let note = record.record(token: token, runner: runner, won: won, madeCatch: madeCatch)
        save(record)
        return note
    }
}
