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
    /// Let computer player `playerId` move, if it has a move now. True when
    /// one was applied. Always false for a game with no bot.
    mutating func botAct(_ playerId: String, now: Double) -> Bool
}

/// `OfflineMatch` for one rules type: its state and its generator.
struct OfflineMatchOf<Rules: OfflineGameRules>: OfflineMatch {
    /// A computer player's candidate moves, best first (`OfflineBotRules`).
    typealias Bot = (Rules.State, String, inout OfflineRNG) -> [Rules.Action]

    private(set) var state: Rules.State
    private(set) var rng: OfflineRNG
    let players: [OfflinePlayer]
    private let bot: Bot?

    init(players: [OfflinePlayer], seed: UInt64, now: Double, bot: Bot? = nil) {
        var rng = OfflineRNG(seed: seed)
        self.state = Rules.start(players: players, now: now, rng: &rng)
        self.rng = rng
        self.players = players
        self.bot = bot
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

    /// Each candidate in turn, through exactly the rules a person's move goes
    /// through, until one is accepted — so a bot can never make an illegal
    /// move, and a bot that suggests one only wastes its own turn's thought.
    mutating func botAct(_ playerId: String, now: Double) -> Bool {
        guard let bot else { return false }
        let candidates = bot(state, playerId, &rng)
        for action in candidates {
            var next = state
            var nextRng = rng
            do {
                try Rules.apply(action, by: playerId, to: &next, now: now, rng: &nextRng)
            } catch {
                continue
            }
            state = next
            rng = nextRng
            return true
        }
        return false
    }
}

/// A game the room can start: its card, and how to begin a match of it.
/// Built from a rules type — `OfflineGameEntry(QuickDrawRules.self)` — and
/// paired with the game's view in `OfflineCatalogue`.
struct OfflineGameEntry {
    let info: OfflineGameInfo
    /// The phone can fill seats with computer players (`OfflineBotRules`).
    let hasBot: Bool
    let begin: (_ players: [OfflinePlayer], _ seed: UInt64, _ now: Double) -> any OfflineMatch

    // Never specialised or inlined: the catalogue builds twenty of these in
    // one initializer, and a whole-module Release build that specialised
    // every game's match and coding into it ran past CI's 30-minute limit
    // (a per-file build of the same code took 15 minutes). Unspecialised
    // generic code is plenty fast for one move at a time.
    @inline(never)
    @_semantics("optimize.sil.specialize.generic.never")
    init<Rules: OfflineGameRules>(_ rules: Rules.Type) {
        info = Rules.info
        hasBot = false
        begin = { players, seed, now in OfflineMatchOf<Rules>(players: players, seed: seed, now: now) }
    }

    /// A game with a computer player (`OfflineBotRules`).
    @inline(never)
    @_semantics("optimize.sil.specialize.generic.never")
    init<Rules: OfflineBotRules>(withBot rules: Rules.Type) {
        info = Rules.info
        hasBot = true
        begin = { players, seed, now in
            OfflineMatchOf<Rules>(players: players, seed: seed, now: now, bot: { state, playerId, rng in
                Rules.botActions(state, for: playerId, rng: &rng)
            })
        }
    }
}

/// A game the phone can play against. A bot is deliberately simple — it
/// takes what is on offer, blocks what is obvious and otherwise plays
/// something sensible — so a child can beat it and an adult can practise.
protocol OfflineBotRules: OfflineGameRules {
    /// What computer player `playerId` would do now, best first; empty when
    /// it has nothing to do (not its turn). The match tries each through
    /// `apply` until one is accepted, so a candidate may be wrong.
    static func botActions(_ state: State, for playerId: String, rng: inout OfflineRNG) -> [Action]
}
