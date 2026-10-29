import Foundation

// The three table games' (Liar's Dice, Pass the Plate, Fireworks) pieces that
// are not the server's: how this phone's player has done, kept on the phone;
// the turn clock's figures; and where a celebration's sparks fly. Pure
// values, so each is a unit test — the screens only draw them.
//
// The server judges every move and keeps every score. A record here is a
// keepsake ("your best show", "three wins in a row"), never a ruling.

// MARK: - Records

/// One game's record on this phone — or one variant of it: Fireworks keeps
/// its five- and six-colour shows apart, because they score out of 25 and 30.
struct TableGameRecord: Codable, Equatable {
    var played = 0
    var wins = 0
    /// Wins in a row, to now.
    var streak = 0
    var bestStreak = 0
    /// The highest score kept; nil until a scored game is recorded.
    var best: Int?
    /// The game that set `best`, so its finish keeps saying so when reopened.
    var bestKey: String?
    /// The best that game beat; nil when it was the first score kept.
    var bestBefore: Int?
    /// Games already counted, newest last, so a finish seen twice (the page
    /// reopened, the app back from the background) counts once.
    var counted: [String] = []

    /// How many finished games are remembered for that.
    static let remembered = 30

    /// A finished game. False, and nothing changes, when `key` was counted
    /// already (or is empty).
    @discardableResult
    mutating func record(key: String, won: Bool, score: Int?) -> Bool {
        guard !key.isEmpty, !counted.contains(key) else { return false }
        counted.append(key)
        if counted.count > Self.remembered { counted.removeFirst(counted.count - Self.remembered) }
        played += 1
        if won {
            wins += 1
            streak += 1
            bestStreak = max(bestStreak, streak)
        } else {
            streak = 0
        }
        if let score {
            if let best {
                if score > best {
                    bestBefore = best
                    self.best = score
                    bestKey = key
                }
            } else {
                bestBefore = nil
                best = score
                bestKey = key
            }
        }
        return true
    }

    /// This game set the best score kept (a tie with an older best does not).
    func isBest(_ key: String) -> Bool { !key.isEmpty && bestKey == key }

    /// This game beat an earlier best — a "new best", not merely the first.
    func beatBest(_ key: String) -> Bool { isBest(key) && bestBefore != nil }
}

/// Every variant's record for one game.
struct TableGameBook: Codable, Equatable {
    var records: [String: TableGameRecord] = [:]

    func record(_ variant: String) -> TableGameRecord { records[variant] ?? TableGameRecord() }

    /// Count a finished game under `variant`, and hand back that record.
    @discardableResult
    mutating func note(variant: String, key: String, won: Bool, score: Int?) -> TableGameRecord {
        var next = record(variant)
        next.record(key: key, won: won, score: score)
        records[variant] = next
        return next
    }
}

/// Where one game's book lives: UserDefaults, under the game's own id.
struct TableGameBestStore {
    /// The game's wire id: "liars-dice", "pass-the-plate", "fireworks".
    let gameId: String
    var defaults: UserDefaults = .standard
    /// Off for the demo: a showcase game is never anybody's record.
    var persists = true

    var key: String { "\(gameId).bests.v1" }

    func load() -> TableGameBook {
        guard let data = defaults.data(forKey: key),
              let book = try? JSONDecoder().decode(TableGameBook.self, from: data) else { return TableGameBook() }
        return book
    }

    func save(_ book: TableGameBook) {
        guard persists, let data = try? JSONEncoder().encode(book) else { return }
        defaults.set(data, forKey: key)
    }

    /// Count a finished game (once) and hand back its variant's record.
    @discardableResult
    func note(variant: String, key: String, won: Bool, score: Int?) -> TableGameRecord {
        var book = load()
        let record = book.note(variant: variant, key: key, won: won, score: score)
        save(book)
        return record
    }
}

/// One finished game's name in a record: the room and when play began, since
/// Play again keeps the room and restarts its clock.
enum TableGameKey {
    static func finished(roomId: String, startedAt: Double?) -> String {
        guard !roomId.isEmpty else { return "" }
        let started = Int64((startedAt ?? 0).rounded())
        return "\(roomId)|\(started)"
    }
}

// MARK: - The turn clock

enum TableClock {
    /// How pressing the clock is.
    enum Urgency: Equatable { case calm, hurry, last }

    /// Whole seconds left, rounded up (so "1" until the very end); nil when the
    /// clock is unknown. Times are the server's milliseconds.
    static func secondsLeft(endsAt: Double?, now: Double?) -> Int? {
        guard let endsAt, let now else { return nil }
        let left = (endsAt - now) / 1000
        guard left > 0 else { return 0 }
        return Int(left.rounded(.up))
    }

    /// The share of the turn left, 0…1 (1 when the clock is unknown).
    static func fraction(endsAt: Double?, turnMs: Double, now: Double?) -> Double {
        guard let endsAt, let now, turnMs > 0 else { return 1 }
        return min(1, max(0, (endsAt - now) / turnMs))
    }

    /// Calm, then hurry for the last third (or ten seconds), then the last
    /// sixth (or five seconds).
    static func urgency(fraction: Double, seconds: Int?) -> Urgency {
        if let seconds, seconds <= 5 { return .last }
        if fraction < 0.17 { return .last }
        if let seconds, seconds <= 10 { return .hurry }
        if fraction < 0.34 { return .hurry }
        return .calm
    }

    /// The marks a player is nudged at as their clock runs down.
    static let nudges = [10, 5]

    /// Whether the clock just crossed a nudge mark going from `previous` to
    /// `now` seconds — once per mark, never on the way back up (a new turn).
    static func nudge(from previous: Int?, to now: Int?) -> Bool {
        guard let previous, let now, now < previous else { return false }
        return nudges.contains { now <= $0 && previous > $0 }
    }
}

// MARK: - Sparks

/// Where a celebration's sparks are, frame by frame: a handful of bursts
/// spread over the show, each a ring of sparks flying out, slowing, falling
/// a little and fading. Deterministic, so a frame is a function of the time
/// and nothing is kept between frames.
enum TableSparks {
    /// One burst: its centre in a unit square (0…1 across, 0…1 down), when it
    /// goes off (seconds into the show), which colour, and how far it reaches
    /// (a share of the view's shorter side).
    struct Burst: Equatable {
        let x: Double
        let y: Double
        let start: Double
        let hue: Int
        let reach: Double
    }

    /// One spark: its offset from the burst's centre in shares of the view's
    /// shorter side, and how bright it still is (0…1).
    struct Spark: Equatable {
        let dx: Double
        let dy: Double
        let alpha: Double
    }

    /// How long one burst lasts, in seconds.
    static let life = 1.4

    /// A steady 0..<1 from two integers.
    static func unit(_ a: Int, _ b: Int) -> Double {
        var h = UInt64(bitPattern: Int64(a)) &* 0x9E37_79B9_7F4A_7C15
        h ^= UInt64(bitPattern: Int64(b)) &* 0xBF58_476D_1CE4_E5B9
        h ^= h >> 31
        h = h &* 0x94D0_49BB_1331_11EB
        h ^= h >> 29
        return Double(h >> 11) / 9_007_199_254_740_992.0
    }

    /// `count` bursts over `duration` seconds, the last one finishing as the
    /// show does, across the top two-thirds of the view.
    static func show(count: Int, duration: Double, seed: Int) -> [Burst] {
        guard count > 0 else { return [] }
        let span = max(0, duration - life)
        return (0..<count).map { i in
            Burst(x: 0.14 + 0.72 * unit(seed, i * 3),
                  y: 0.16 + 0.42 * unit(seed, i * 3 + 1),
                  start: count == 1 ? 0 : span * Double(i) / Double(count - 1),
                  hue: i,
                  reach: 0.2 + 0.14 * unit(seed, i * 3 + 2))
        }
    }

    /// Spark `i` of `n` in `burst`, `t` seconds into the show; nil before the
    /// burst goes off and once it has faded.
    static func spark(_ i: Int, of n: Int, burst: Burst, at t: Double) -> Spark? {
        guard n > 0 else { return nil }
        let local = (t - burst.start) / life
        guard local >= 0, local < 1 else { return nil }
        let angle = 2 * Double.pi * (Double(i) + 0.35 * unit(i, burst.hue)) / Double(n)
        let ease = 1 - (1 - local) * (1 - local)
        let reach = burst.reach * (0.72 + 0.28 * unit(burst.hue, i)) * ease
        let fall = 0.1 * local * local
        return Spark(dx: cos(angle) * reach, dy: sin(angle) * reach + fall, alpha: 1 - local)
    }
}
