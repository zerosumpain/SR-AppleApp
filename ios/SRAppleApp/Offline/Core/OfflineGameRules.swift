import Foundation

// The offline games' contract: what one game's rules must say, in pure values.
//
// ## Why the rules are pure
//
// "Play nearby" has no server. The HOST PHONE is the server: it holds the one
// true state, runs the rules, and sends each player only what that player may
// see. Guests send actions and draw what comes back. So every rule that
// decides who won lives in a type with no UI, no clock of its own and no
// randomness of its own — the host hands it the time and a seeded generator —
// and the whole of a game is a unit test on Linux rather than something only
// five phones side by side can show.
//
// ## Times
//
// Every `now` here is HOST-CLOCK SECONDS: the host phone's monotonic uptime
// (`ProcessInfo.systemUptime`), as a `Double`. Guests convert with the
// `OfflineHostClock` they are handed (see `OfflineClock.swift`). A rule never
// reads a clock itself.
//
// The authoritative description, with a worked example, is
// docs/OFFLINE_GAMES.md.

/// One game's rules. A caseless `enum` conforms — `enum QuickDrawRules: OfflineGameRules`.
///
/// The host calls `start` once, then `apply` for every action anyone sends,
/// `tick` about ten times a second, and `view` for every player after each of
/// those; `isOver` ends the match and `standings` is the table shown after it.
protocol OfflineGameRules {
    /// Everything the host knows, secrets included. Never sent anywhere whole.
    associatedtype State: Codable & Equatable
    /// What a player may ask for. An enum with associated values encodes fine.
    associatedtype Action: Codable & Equatable
    /// What ONE player sees (`playerId`), or a spectator (`nil`) — other
    /// players' hands and hidden answers left out. Sent over the air on every
    /// change, so keep it small: no history the screen does not draw.
    associatedtype PlayerView: Codable & Equatable

    /// The catalogue card and the lobby's limits.
    static var info: OfflineGameInfo { get }

    /// A new match for `players` (in seat order, host first), at host time
    /// `now`. Every shuffle and every random wait comes from `rng`.
    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State

    /// One player's action. Throw `OfflineRefusal("a sentence")` for anything
    /// illegal — out of turn, a card they do not hold, a phase that is over.
    /// A throw leaves the state exactly as it was (the host applies to a copy),
    /// so validate in any order you like.
    static func apply(_ action: Action, by playerId: String, to state: inout State, now: Double, rng: inout OfflineRNG) throws

    /// Called by the host about ten times a second while the match runs: timers
    /// running out, a scheduled stimulus, a dealer's turn, the next round.
    /// Must be idempotent for a repeated `now` — it may be called twice at one time.
    static func tick(_ state: inout State, now: Double, rng: inout OfflineRNG)

    /// What `playerId` (or a spectator, `nil`) may see now.
    static func view(of state: State, for playerId: String?) -> PlayerView

    /// The match is finished; the host stops ticking and shows standings.
    static func isOver(_ state: State) -> Bool

    /// The table after (or during) the match, best first, one row per player
    /// who started it. `OfflineStanding.ranked` does the ranking.
    static func standings(_ state: State) -> [OfflineStanding]

    /// `playerId` has gone — their phone left or dropped out of range. Skip
    /// their turns, fold their hand, or end the match. Default: nothing (the
    /// room itself ends a match that falls below `info.minPlayers`).
    static func playerLeft(_ playerId: String, state: inout State, now: Double, rng: inout OfflineRNG)
}

extension OfflineGameRules {
    static func tick(_ state: inout State, now: Double, rng: inout OfflineRNG) {}
    static func playerLeft(_ playerId: String, state: inout State, now: Double, rng: inout OfflineRNG) {}
}

/// Which shelf a game sits on in the catalogue.
enum OfflineGameCategory: String, Codable, CaseIterable, Identifiable {
    case card, reaction, skill

    var id: String { rawValue }

    /// The section heading on the Play nearby page.
    var title: String {
        switch self {
        case .card: return "Card games"
        case .reaction: return "Reaction games"
        case .skill: return "Skill games"
        }
    }
}

/// A game's card in the catalogue, and the limits the lobby enforces.
struct OfflineGameInfo: Equatable {
    /// kebab-case and unique: `quick-draw`. Travels on the wire.
    let id: String
    let title: String
    /// One sentence for the catalogue card.
    let blurb: String
    let category: OfflineGameCategory
    /// 1 for a game that can be played alone; most are 2.
    let minPlayers: Int
    /// At most `OfflineRoom.capacity` (5).
    let maxPlayers: Int
    /// An SF Symbol name available on iOS 17.
    let symbol: String
    /// Short sentences, one rule each, shown before the game starts.
    let howToPlay: [String]
    /// Computer players a game played alone seats, for a game with a bot that
    /// plays best round a bigger table (Liar's Dice); nil for the fewest it
    /// needs. `OfflinePlayModes.soloBots` keeps it within the table's limits.
    var soloOpponents: Int? = nil

    /// "2–5 players", "1–4 players", "2 players".
    var playersLabel: String {
        if minPlayers == maxPlayers { return maxPlayers == 1 ? "1 player" : "\(maxPlayers) players" }
        return "\(minPlayers)–\(maxPlayers) players"
    }

    /// Whether `count` players may start it.
    func allows(_ count: Int) -> Bool { count >= minPlayers && count <= maxPlayers }
}

/// One person in a room. The id is a UUID string the phone keeps in
/// UserDefaults, so a guest who drops and rejoins is the same player.
struct OfflinePlayer: Codable, Equatable, Hashable, Identifiable {
    let id: String
    var name: String
}

/// One row of the table after a match.
struct OfflineStanding: Codable, Equatable, Identifiable {
    let playerId: String
    let name: String
    /// 1 is the winner; ties share a rank (1, 1, 3).
    let rank: Int
    /// The figure the table is ranked by: rounds, points, chips.
    let score: Int
    /// One short line: "best 212 ms · 1 false start".
    let detail: String?

    var id: String { playerId }

    /// Rank `players` by `score`, highest first (or lowest, for golf-style
    /// games), with ties sharing a rank. Seat order breaks display ties only.
    static func ranked(_ players: [OfflinePlayer],
                       score: (OfflinePlayer) -> Int,
                       detail: (OfflinePlayer) -> String? = { _ in nil },
                       lowerIsBetter: Bool = false) -> [OfflineStanding] {
        let scored = players.enumerated().map { (seat: $0.offset, player: $0.element, score: score($0.element)) }
        let sorted = scored.sorted { a, b in
            if a.score != b.score { return lowerIsBetter ? a.score < b.score : a.score > b.score }
            return a.seat < b.seat
        }
        var out: [OfflineStanding] = []
        for (index, row) in sorted.enumerated() {
            let rank = index > 0 && sorted[index - 1].score == row.score ? out[index - 1].rank : index + 1
            out.append(OfflineStanding(playerId: row.player.id, name: row.player.name, rank: rank,
                                       score: row.score, detail: detail(row.player)))
        }
        return out
    }
}

/// An illegal action, with the sentence the player's screen shows.
struct OfflineRefusal: Error, Equatable, Codable {
    let reason: String
    init(_ reason: String) { self.reason = reason }
}

/// What a game's view is handed: its decoded `PlayerView`, who I am, a way
/// to act, and the host's clock. The view never changes state itself — it
/// sends an action and waits for the next `view` to come back.
struct OfflineGameContext<Rules: OfflineGameRules> {
    /// What I may see now.
    let view: Rules.PlayerView
    /// My player id. Compare with ids inside the view to find "me".
    let me: String
    /// Everyone in the room, seat order, host first.
    let players: [OfflinePlayer]
    /// Whether this phone is the host.
    let isHost: Bool
    /// Host-clock time, for countdowns and scheduled stimuli.
    let clock: OfflineHostClock
    /// The host's last refusal of one of MY actions, or nil. Cleared on the
    /// next view that arrives after it.
    let refusal: String?
    /// Send an action to the host. Cheap; call it from a button.
    let send: (Rules.Action) -> Void

    /// A player's name by id ("You" is the view's business).
    func name(of id: String) -> String {
        players.first { $0.id == id }?.name ?? "Someone"
    }
}
