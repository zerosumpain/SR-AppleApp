import Foundation

// Results of games played with no internet, kept on the phone until it can
// tell the site — the "sync later" half of offline play.
//
// Each phone records ONE row per finished match: its own place, score and
// whether it won. That is the only row a phone can vouch for (the site knows
// who is asking, and nobody else), and it is all the family leaderboard
// needs: every phone in a nearby match files its own row under the same
// match key, so the site sees one match with everyone in it, once each,
// however many times a flaky connection makes a phone retry.
//
// The site's half is `POST api/native/games/offline-results` (see
// `OfflineResultUpload`). Until a site answers it, results simply wait.

/// One finished match, as this phone played it.
struct OfflineResult: Codable, Equatable, Identifiable {
    enum Mode: String, Codable, Equatable {
        /// This phone alone, perhaps against computer players.
        case solo
        /// Phones in the same room, one of them hosting.
        case nearby
    }

    /// The match's key — the room's key and the match number — shared by
    /// every phone in it, so the site files each person once per match.
    let id: String
    /// The offline game's id (`OfflineGameInfo.id`).
    let game: String
    let title: String
    let mode: Mode
    /// Epoch milliseconds, as the site's clocks count.
    let finishedAt: Double
    /// Seats in the match, computer players included.
    let players: Int
    /// How many of those seats were computer players.
    let bots: Int
    /// 1 is first; ties share a rank.
    let rank: Int
    /// The figure the game's table is ranked by.
    let score: Int
    /// First, with somebody to beat. A game played alone wins nothing, as on
    /// the site's own board.
    let won: Bool
    /// The game's own one-line detail: "best 212 ms · 1 false start".
    let detail: String?
    /// The others at the table, by name.
    let opponents: [String]

    /// A result from a finished lobby, for player `me`; nil when the lobby is
    /// not finished or `me` was not in the match (a spectator files nothing).
    static func from(lobby: OfflineLobby, me: String, title: String, mode: Mode, finishedAt: Double) -> OfflineResult? {
        guard lobby.phase == .finished, let table = lobby.standings,
              let mine = table.first(where: { $0.playerId == me }) else { return nil }
        let bots = Set(lobby.players.filter(\.isBot).map(\.id))
        return OfflineResult(
            id: "\(lobby.roomKey ?? lobby.hostId)-\(lobby.match)",
            game: lobby.gameId ?? "unknown",
            title: title,
            mode: mode,
            finishedAt: finishedAt,
            players: table.count,
            bots: table.filter { bots.contains($0.playerId) }.count,
            rank: mine.rank,
            score: mine.score,
            won: table.count > 1 && mine.rank == 1,
            detail: mine.detail,
            opponents: table.filter { $0.playerId != me }.map(\.name)
        )
    }
}

/// How often this phone has played each game offline: played, won, best.
struct OfflineTally: Codable, Equatable {
    var played = 0
    var won = 0
    var best: Int?
    /// Epoch ms of the last game, so "most played lately" can weigh it.
    var lastPlayed: Double = 0
}

/// The results waiting to go, and what this phone has played. One value,
/// saved whole, so a crash between "add" and "save" loses nothing it then
/// pretends to have.
struct OfflineResultQueue: Codable, Equatable {
    /// More than a fortnight of games at the kitchen table. Beyond it the
    /// oldest go first: a phone that never reconnects must not grow forever.
    static let limit = 200
    /// Match keys already synced, remembered so a finished screen shown again
    /// (a rejoin, a relaunch) cannot queue the same match twice.
    static let rememberSynced = 400

    private(set) var pending: [OfflineResult] = []
    private(set) var synced: [String] = []
    private(set) var tallies: [String: OfflineTally] = [:]
    /// Sync attempts that failed since the last one that worked.
    private(set) var failures = 0

    /// Queue `result` and count it. False (and nothing changes) when this
    /// match is already queued or synced.
    @discardableResult
    mutating func add(_ result: OfflineResult) -> Bool {
        guard !pending.contains(where: { $0.id == result.id }), !synced.contains(result.id) else { return false }
        pending.append(result)
        if pending.count > Self.limit { pending.removeFirst(pending.count - Self.limit) }
        var tally = tallies[result.game] ?? OfflineTally()
        tally.played += 1
        if result.won { tally.won += 1 }
        tally.best = max(tally.best ?? result.score, result.score)
        tally.lastPlayed = max(tally.lastPlayed, result.finishedAt)
        tallies[result.game] = tally
        return true
    }

    /// The next results to send, oldest first.
    func batch(max: Int = 25) -> [OfflineResult] { Array(pending.prefix(max)) }

    /// The site has answered for `ids` — recorded, or refused for good — so
    /// they are done with. A success resets the backoff.
    mutating func settle(_ ids: [String]) {
        let done = Set(ids)
        guard !done.isEmpty else { return }
        pending.removeAll { done.contains($0.id) }
        synced.append(contentsOf: ids.filter { !synced.contains($0) })
        if synced.count > Self.rememberSynced { synced.removeFirst(synced.count - Self.rememberSynced) }
        failures = 0
    }

    /// A sync attempt failed (no network, the site down or not ready).
    mutating func failed() { failures += 1 }

    /// Seconds to wait before the next attempt after `failures` in a row:
    /// at once, then a quarter of a minute, a minute, five, fifteen.
    static func backoff(failures: Int) -> Double {
        let steps: [Double] = [0, 15, 60, 300, 900]
        return steps[min(max(0, failures), steps.count - 1)]
    }

    /// Games by how much they are played here, most first — the order a
    /// "your games" shelf would show them in. Recent play counts double.
    func mostPlayed(now: Double, limit: Int = 6) -> [String] {
        let fortnightMs: Double = 14 * 24 * 3_600_000
        var weights: [(game: String, weight: Double)] = []
        for (game, tally) in tallies {
            let played = Double(tally.played)
            let recent: Double = now - tally.lastPlayed < fortnightMs ? played : 0
            weights.append((game, played + recent))
        }
        weights.sort { $0.weight == $1.weight ? $0.game < $1.game : $0.weight > $1.weight }
        return weights.prefix(limit).map(\.game)
    }

    /// "3 games waiting to sync", or nil when nothing is.
    var waitingLine: String? {
        switch pending.count {
        case 0: return nil
        case 1: return "1 game waiting to sync"
        default: return "\(pending.count) games waiting to sync"
        }
    }
}

/// `POST api/native/games/offline-results`: `{ results: [...] }`, each row an
/// `OfflineResult` with its game namespaced (`game: "offline:<id>"`, plus
/// `source: "offline"`). The site files a row as a `game_results` row for the
/// caller — room id `offline-<id>`, round 1 — so a retry, or the same match
/// from another phone, lands once per person.
///
/// The namespace matters because an offline game can share an id with an
/// online one and score differently: the offline Maths Sprint has no
/// difficulty and scores ten a sum plus a streak bonus, so its rows must
/// never land on the online `maths-sprint` board. The site decides whether
/// to show offline boards beside the online ones; the phone keeps the plain
/// id for its own tallies.
struct OfflineResultUpload: Encodable {
    static let gamePrefix = "offline:"
    static let source = "offline"

    let results: [OfflineResult]

    /// The game id as the site files it.
    static func wireGame(_ id: String) -> String { gamePrefix + id }

    private enum CodingKeys: String, CodingKey { case results }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(results.map(Row.init), forKey: .results)
    }

    /// One row on the wire: every field of the result, the game namespaced.
    private struct Row: Encodable {
        let id: String
        let game: String
        let source: String
        let title: String
        let mode: OfflineResult.Mode
        let finishedAt: Double
        let players: Int
        let bots: Int
        let rank: Int
        let score: Int
        let won: Bool
        let detail: String?
        let opponents: [String]

        init(_ result: OfflineResult) {
            id = result.id
            game = OfflineResultUpload.wireGame(result.game)
            source = OfflineResultUpload.source
            title = result.title
            mode = result.mode
            finishedAt = result.finishedAt
            players = result.players
            bots = result.bots
            rank = result.rank
            score = result.score
            won = result.won
            detail = result.detail
            opponents = result.opponents
        }
    }
}

/// The site's answer: the ids it recorded, and the ids it will never take
/// (a game it does not know, a malformed row). Both are settled; anything
/// in neither list is tried again later.
struct OfflineResultReceipt: Decodable, Equatable {
    let recorded: [String]
    let rejected: [String]

    init(recorded: [String], rejected: [String] = []) {
        self.recorded = recorded
        self.rejected = rejected
    }

    private enum CodingKeys: String, CodingKey { case recorded, rejected }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recorded = (try? c.decodeIfPresent([String].self, forKey: .recorded)) ?? []
        rejected = (try? c.decodeIfPresent([String].self, forKey: .rejected)) ?? []
    }

    var settled: [String] { recorded + rejected }
}
