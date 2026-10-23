import Foundation

// One game's rules, type-erased so the room can hold "whichever game is on"
// and the wire can carry it as bytes.
//
// The room never sees a `State`, an `Action` or a `PlayerView`: it hands an
// action over as JSON `Data`, asks for a player's view back as JSON `Data`,
// and compares those bytes to decide whether a player needs a fresh view.
// That is why the encoder sorts its keys — the same view must always encode
// to the same bytes, or every tick would resend every view.

/// The JSON coding every offline payload uses.
enum OfflineCoding {
    /// Sorted keys: equal values encode to equal bytes.
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}

/// A running match of some game, as the room holds it.
protocol OfflineMatch {
    var info: OfflineGameInfo { get }
    /// The players the match was started with, seat order.
    var players: [OfflinePlayer] { get }
    /// Apply one player's action (JSON of the game's `Action`). Throws
    /// `OfflineRefusal`; on a throw nothing changes.
    mutating func apply(_ action: Data, by playerId: String, now: Double) throws
    mutating func tick(now: Double)
    mutating func playerLeft(_ playerId: String, now: Double)
    /// JSON of the game's `PlayerView` for `playerId`, or a spectator.
    func viewData(for playerId: String?) -> Data
    var isOver: Bool { get }
    var standings: [OfflineStanding] { get }
}

/// `OfflineMatch` for one rules type: its state and its generator.
struct OfflineMatchOf<Rules: OfflineGameRules>: OfflineMatch {
    private(set) var state: Rules.State
    private(set) var rng: OfflineRNG
    let players: [OfflinePlayer]

    init(players: [OfflinePlayer], seed: UInt64, now: Double) {
        var rng = OfflineRNG(seed: seed)
        self.state = Rules.start(players: players, now: now, rng: &rng)
        self.rng = rng
        self.players = players
    }

    var info: OfflineGameInfo { Rules.info }

    mutating func apply(_ action: Data, by playerId: String, now: Double) throws {
        let decoded: Rules.Action
        do {
            decoded = try OfflineCoding.decode(Rules.Action.self, from: action)
        } catch {
            throw OfflineRefusal("The host could not read that move — is everyone on the same version of the app?")
        }
        // On a copy, so a rule that throws halfway leaves nothing behind.
        var next = state
        var nextRng = rng
        try Rules.apply(decoded, by: playerId, to: &next, now: now, rng: &nextRng)
        state = next
        rng = nextRng
    }

    mutating func tick(now: Double) {
        Rules.tick(&state, now: now, rng: &rng)
    }

    mutating func playerLeft(_ playerId: String, now: Double) {
        Rules.playerLeft(playerId, state: &state, now: now, rng: &rng)
    }

    func viewData(for playerId: String?) -> Data {
        // A Codable struct of plain values does not fail to encode; if one
        // ever did, an empty object is a view the screen can survive.
        (try? OfflineCoding.encode(Rules.view(of: state, for: playerId))) ?? Data("{}".utf8)
    }

    var isOver: Bool { Rules.isOver(state) }

    var standings: [OfflineStanding] { Rules.standings(state) }
}

/// A game the room can start: its card, and how to begin a match of it.
/// Built from a rules type — `OfflineGameEntry(QuickDrawRules.self)` — and
/// paired with the game's view in `OfflineCatalogue`.
struct OfflineGameEntry {
    let info: OfflineGameInfo
    let begin: (_ players: [OfflinePlayer], _ seed: UInt64, _ now: Double) -> any OfflineMatch

    init<Rules: OfflineGameRules>(_ rules: Rules.Type) {
        info = Rules.info
        begin = { players, seed, now in OfflineMatchOf<Rules>(players: players, seed: seed, now: now) }
    }
}
