import Foundation

/// Quick Draw: a western stand-off for two to five phones.
///
/// Each round the host picks a random wait of two to six seconds and then
/// every screen shouts DRAW! at the same host-clock instant. Each phone times
/// its own owner from the frame that showed DRAW to the touch, and reports
/// the figure; the lowest wins the round. Touch the screen before DRAW — or
/// so soon after it that nobody could have seen it — and you have jumped the
/// gun: you sit the rest of that round out. First to five rounds wins, or the
/// most rounds after nine.
///
/// The reference game for docs/OFFLINE_GAMES.md: every other game follows
/// the same shape — a caseless enum of rules, a `State` with the secrets, a
/// `PlayerView` with only what one player may see, and nothing that reads a
/// clock or a random number of its own.
enum QuickDrawRules: OfflineGameRules {
    /// Round wins that take the match.
    static let winsNeeded = 5
    /// Rounds before the most wins takes it.
    static let maxRounds = 9
    /// How long the stand-off lasts before DRAW, seconds.
    static let waitRange: ClosedRange<Double> = 2...6
    /// How long after DRAW the round waits for slow (or absent) players.
    static let drawWindow: Double = 3
    /// How long a round's result stays up before the next stand-off.
    static let resultPause: Double = 3
    /// A tap that reaches the host this long BEFORE DRAW (host clock) cannot
    /// have been a reaction, whatever the phone says. Generous, so an honest
    /// phone with a rough clock estimate is never caught by it.
    static let earlySlack: Double = 0.5

    static let info = OfflineGameInfo(
        id: "quick-draw",
        title: "Quick Draw",
        blurb: "Wait for DRAW!, then tap faster than everyone else.",
        category: .reaction,
        minPlayers: 2,
        maxPlayers: 5,
        symbol: "bolt.fill",
        howToPlay: [
            "Hold still while the screen says Steady.",
            "When it shouts DRAW!, tap anywhere — fastest tap wins the round.",
            "Tap before DRAW and you sit the round out.",
            "First to \(winsNeeded) rounds wins, or the most after \(maxRounds)."
        ]
    )

    // MARK: - State

    enum Phase: String, Codable, Equatable {
        /// The stand-off; DRAW shows at `drawAt`.
        case waiting
        /// The round's times are up on screen until `resultUntil`.
        case result
        /// The match is decided.
        case over
    }

    /// One player's tap this round.
    struct Tap: Codable, Equatable {
        /// Jumped the gun — or claimed a time under `OfflineReaction.anticipationMs`.
        var early: Bool
        /// Milliseconds from DRAW shown to touch, when not early.
        var ms: Int?
    }

    struct State: Codable, Equatable {
        var players: [OfflinePlayer]
        /// Players whose phones have left; they are skipped.
        var away: [String] = []
        var round = 0
        var phase: Phase = .waiting
        /// When DRAW shows, host clock.
        var drawAt: Double = 0
        /// When the result gives way to the next round, host clock.
        var resultUntil: Double = 0
        var taps: [String: Tap] = [:]
        var roundWinner: String?
        var wins: [String: Int] = [:]
        /// Each player's best valid time, ms.
        var best: [String: Int] = [:]
        var falseStarts: [String: Int] = [:]
    }

    enum Action: Codable, Equatable {
        /// A tap `ms` milliseconds after DRAW showed on the tapping phone.
        case draw(round: Int, ms: Int)
        /// A tap before DRAW showed.
        case early(round: Int)
    }

    // MARK: - What a player sees

    struct Row: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        let wins: Int
        let away: Bool
        /// Has tapped this round (a valid tap or a false start).
        let tapped: Bool
        let early: Bool
        /// Their time this round — only once the round is over.
        let ms: Int?
    }

    struct PlayerView: Codable, Equatable {
        let round: Int
        let phase: Phase
        /// Host clock. The view turns DRAW at this instant.
        let drawAt: Double
        let resultUntil: Double
        let rows: [Row]
        /// My own tap this round, if any (with my time, even mid-round).
        let myTap: Tap?
        let roundWinner: String?
        /// The match winners, once it is over (several on a tie).
        let champions: [String]
        let winsNeeded: Int
        let maxRounds: Int
    }

    // MARK: - Rules

    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State {
        var state = State(players: players)
        for player in players { state.wins[player.id] = 0 }
        beginRound(&state, now: now, rng: &rng)
        return state
    }

    static func apply(_ action: Action, by playerId: String, to state: inout State, now: Double, rng: inout OfflineRNG) throws {
        guard state.players.contains(where: { $0.id == playerId }), !state.away.contains(playerId) else {
            throw OfflineRefusal("You are not in this stand-off.")
        }
        guard state.phase == .waiting else { throw OfflineRefusal("This round is over.") }
        let round: Int
        switch action {
        case .draw(let r, _), .early(let r): round = r
        }
        guard round == state.round else { throw OfflineRefusal("That tap was for another round.") }
        guard state.taps[playerId] == nil else { throw OfflineRefusal("You have already drawn this round.") }

        switch action {
        case .early:
            state.taps[playerId] = Tap(early: true, ms: nil)
        case .draw(_, let ms):
            guard ms >= 0, ms <= 60_000 else { throw OfflineRefusal("That time cannot be right.") }
            // Too quick to be a reaction, or arrived well before DRAW was due:
            // either way, the gun was jumped.
            if !OfflineReaction.counts(ms) || now < state.drawAt - earlySlack {
                state.taps[playerId] = Tap(early: true, ms: nil)
            } else {
                state.taps[playerId] = Tap(early: false, ms: ms)
            }
        }
        if state.taps[playerId]?.early == true { state.falseStarts[playerId, default: 0] += 1 }
        if everyoneHasDrawn(state) { resolve(&state, now: now) }
    }

    static func tick(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        switch state.phase {
        case .waiting:
            if now >= state.drawAt + drawWindow || everyoneHasDrawn(state) { resolve(&state, now: now) }
        case .result:
            guard now >= state.resultUntil else { return }
            if decided(state) {
                state.phase = .over
            } else {
                beginRound(&state, now: now, rng: &rng)
            }
        case .over:
            break
        }
    }

    static func playerLeft(_ playerId: String, state: inout State, now: Double, rng: inout OfflineRNG) {
        guard !state.away.contains(playerId) else { return }
        state.away.append(playerId)
        if state.phase == .waiting, everyoneHasDrawn(state) { resolve(&state, now: now) }
    }

    static func view(of state: State, for playerId: String?) -> PlayerView {
        let reveal = state.phase != .waiting
        let rows = state.players.map { player -> Row in
            let tap = state.taps[player.id]
            return Row(id: player.id, name: player.name, wins: state.wins[player.id] ?? 0,
                       away: state.away.contains(player.id), tapped: tap != nil,
                       early: tap?.early ?? false, ms: reveal ? tap?.ms : nil)
        }
        return PlayerView(
            round: state.round, phase: state.phase, drawAt: state.drawAt, resultUntil: state.resultUntil,
            rows: rows, myTap: playerId.flatMap { state.taps[$0] }, roundWinner: state.roundWinner,
            champions: state.phase == .over ? champions(state) : [],
            winsNeeded: winsNeeded, maxRounds: maxRounds
        )
    }

    static func isOver(_ state: State) -> Bool { state.phase == .over }

    static func standings(_ state: State) -> [OfflineStanding] {
        OfflineStanding.ranked(state.players, score: { state.wins[$0.id] ?? 0 }, detail: { player in
            var parts: [String] = []
            if let best = state.best[player.id] { parts.append("best \(best) ms") }
            let falseStarts = state.falseStarts[player.id] ?? 0
            if falseStarts > 0 { parts.append(falseStarts == 1 ? "1 false start" : "\(falseStarts) false starts") }
            if state.away.contains(player.id) { parts.append("left") }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        })
    }

    // MARK: - Helpers

    private static func beginRound(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        state.round += 1
        state.phase = .waiting
        state.taps = [:]
        state.roundWinner = nil
        state.drawAt = now + rng.double(in: waitRange)
    }

    /// Everyone still here has tapped (a false start counts as having tapped).
    private static func everyoneHasDrawn(_ state: State) -> Bool {
        state.players.allSatisfy { state.away.contains($0.id) || state.taps[$0.id] != nil }
    }

    /// Close the round: the lowest valid time wins it (seat order breaks an
    /// exact tie), and the result goes up.
    private static func resolve(_ state: inout State, now: Double) {
        var winner: (id: String, ms: Int)?
        for player in state.players {
            guard let tap = state.taps[player.id], !tap.early, let ms = tap.ms else { continue }
            if let best = state.best[player.id] { state.best[player.id] = min(best, ms) } else { state.best[player.id] = ms }
            if winner == nil || ms < winner!.ms { winner = (player.id, ms) }
        }
        if let winner { state.wins[winner.id, default: 0] += 1 }
        state.roundWinner = winner?.id
        state.phase = .result
        state.resultUntil = now + resultPause
    }

    /// Somebody has the wins, or the rounds have run out.
    static func decided(_ state: State) -> Bool {
        state.wins.values.contains { $0 >= winsNeeded } || state.round >= maxRounds
    }

    /// The most round wins (several on a tie); nobody if nobody won a round.
    static func champions(_ state: State) -> [String] {
        let top = state.wins.values.max() ?? 0
        guard top > 0 else { return [] }
        return state.players.map(\.id).filter { state.wins[$0] == top }
    }
}
