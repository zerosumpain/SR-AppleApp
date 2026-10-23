import Foundation

/// Whack-a-Mole: one shared field of nine holes, two to five phones.
///
/// The host pops moles out of random holes on a schedule, and every phone
/// shows each one at the same host-clock instant. A mole stays up for about
/// nine-tenths of a second at first and less as the round goes on, and they
/// come quicker too. Tap a mole on your own phone and it times you from the
/// frame that showed it to the touch, and reports the figure; when two
/// people go for the same mole the host gives it to the lower time, so
/// Bluetooth latency never decides who got there first.
///
/// An ordinary mole is worth 1, a golden one 3. A bomb costs 2 to everyone
/// who hits it. Forty-five seconds; the most points wins.
///
/// The schedule is drawn from the host's generator a moment ahead of time
/// (`lookahead`), so each mole reaches every phone before it is due — just as
/// Quick Draw sends `drawAt` before DRAW.
enum WhackAMoleRules: OfflineGameRules {
    /// The holes: a 3 × 3 field.
    static let columns = 3
    static let holes = 9
    /// The 3-2-1 before the first mole.
    static let leadIn: Double = 3
    /// How long the moles keep coming.
    static let duration: Double = 45
    /// How far ahead the host draws the schedule, seconds. Long enough for a
    /// view to cross Bluetooth before its mole is due.
    static let lookahead: Double = 1.5
    /// How long a mole is up at the start and at the very end, seconds.
    static let upAtStart: Double = 0.9
    static let upAtEnd: Double = 0.6
    /// The gap between one mole popping and the next, start and end.
    static let gapAtStart: Double = 1.0
    static let gapAtEnd: Double = 0.5
    /// After the first whack of a mole, how long the host waits for a
    /// quicker time that is still on its way.
    static let claimWindow: Double = 0.25
    /// After a mole drops, how long the host still takes whacks for it (the
    /// tap was in time; the message was not).
    static let lateSlack: Double = 0.4
    /// A whack that reaches the host this long BEFORE its mole was due
    /// cannot have been a reaction, whatever the phone says.
    static let earlySlack: Double = 0.5
    /// A resolved mole stays in the view this long, so each phone can show
    /// who got it.
    static let keepResolved: Double = 1.2
    /// How long "Time's up" shows before the match ends.
    static let resultPause: Double = 3
    /// Chances of a special mole once the first few seconds are past.
    static let goldenChance = 0.08
    static let bombChance = 0.12
    /// No bombs (or golden moles) until this far in: let people warm up.
    static let specialsAfter: Double = 5

    static let info = OfflineGameInfo(
        id: "whack-a-mole",
        title: "Whack-a-Mole",
        blurb: "Moles pop up on everyone's screen at once — whack them first.",
        category: .reaction,
        minPlayers: 2,
        maxPlayers: 5,
        symbol: "hammer.fill",
        howToPlay: [
            "Everyone shares one field of nine holes.",
            "When a mole pops up, tap it — the quickest tap takes it for 1 point.",
            "A golden mole is worth 3.",
            "Hit a bomb and you lose 2, so look before you tap.",
            "Moles come faster as time runs down.",
            "After \(Int(duration)) seconds the most points wins."
        ]
    )

    // MARK: - State

    enum Phase: String, Codable, Equatable {
        /// The lead-in and the 45 seconds of moles (the view tells which by the clock).
        case playing
        /// "Time's up" is on screen until `resultUntil`.
        case timeUp
        /// The match is decided.
        case over
    }

    enum Kind: String, Codable, Equatable {
        case mole
        case golden
        case bomb

        /// Points to whoever takes it — or, for a bomb, to everyone who hits it.
        var points: Int {
            switch self {
            case .mole: return 1
            case .golden: return 3
            case .bomb: return -2
            }
        }
    }

    /// One player's whack of one mole.
    struct Whack: Codable, Equatable {
        let playerId: String
        /// Milliseconds from the mole shown to the touch, on their phone.
        let ms: Int
    }

    struct Mole: Codable, Equatable {
        /// Counts up from 1 through the match; whacks name it.
        let id: Int
        let hole: Int
        let kind: Kind
        /// Host clock: pops up, drops down.
        let upAt: Double
        let downAt: Double
        /// After this the host takes no more whacks and settles the mole.
        var closesAt: Double
        /// Whacks in, in arrival order. Hidden until it settles.
        var whacks: [Whack] = []
        var resolved = false
        /// Who took it (not for a bomb).
        var takenBy: String?
        /// Who hit it, when it is a bomb.
        var bombed: [String] = []
    }

    struct State: Codable, Equatable {
        var players: [OfflinePlayer]
        /// Players whose phones have left; they are not waited for.
        var away: [String] = []
        var phase: Phase = .playing
        /// Host clock: the first mole may come; the last must be down by.
        var startsAt: Double
        var endsAt: Double
        var resultUntil: Double = 0
        /// Moles drawn and not yet long gone, in schedule order.
        var moles: [Mole] = []
        /// When the next mole to be drawn pops up.
        var nextUpAt: Double
        /// The last mole has been drawn.
        var scheduleDone = false
        var nextId = 1
        var scores: [String: Int] = [:]
        /// Moles taken (any kind but bombs), golden ones, bombs hit.
        var taken: [String: Int] = [:]
        var golden: [String: Int] = [:]
        var bombs: [String: Int] = [:]
        /// Each player's best winning time, ms.
        var best: [String: Int] = [:]
    }

    enum Action: Codable, Equatable {
        /// A tap on mole `mole`, `ms` milliseconds after it showed on the tapping phone.
        case whack(mole: Int, ms: Int)
    }

    // MARK: - What a player sees

    struct MoleView: Codable, Equatable, Identifiable {
        let id: Int
        let hole: Int
        let kind: Kind
        let upAt: Double
        let downAt: Double
        let resolved: Bool
        let takenBy: String?
        let bombed: [String]
        /// I have already whacked this one.
        let mine: Bool
    }

    struct Row: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        let score: Int
        let away: Bool
    }

    struct PlayerView: Codable, Equatable {
        let phase: Phase
        let startsAt: Double
        let endsAt: Double
        let resultUntil: Double
        let moles: [MoleView]
        let rows: [Row]
        /// The winners, once it is over (several on a tie).
        let champions: [String]
    }

    // MARK: - Rules

    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State {
        let startsAt = now + leadIn
        var state = State(players: players, startsAt: startsAt, endsAt: startsAt + duration,
                          nextUpAt: startsAt + 0.4)
        for player in players { state.scores[player.id] = 0 }
        schedule(&state, now: now, rng: &rng)
        return state
    }

    static func apply(_ action: Action, by playerId: String, to state: inout State, now: Double, rng: inout OfflineRNG) throws {
        guard state.players.contains(where: { $0.id == playerId }), !state.away.contains(playerId) else {
            throw OfflineRefusal("You are not in this game.")
        }
        guard state.phase == .playing else { throw OfflineRefusal("Time's up.") }
        switch action {
        case .whack(let moleId, let ms):
            guard let index = state.moles.firstIndex(where: { $0.id == moleId }) else {
                throw OfflineRefusal("That mole has gone.")
            }
            var mole = state.moles[index]
            guard ms >= 0, ms <= 10_000 else { throw OfflineRefusal("That time cannot be right.") }
            guard !mole.whacks.contains(where: { $0.playerId == playerId }) else {
                throw OfflineRefusal("You have already whacked that one.")
            }
            guard !mole.resolved, now < mole.closesAt else {
                throw OfflineRefusal(mole.kind == .bomb ? "That bomb has gone." : "Too late — that mole has gone.")
            }
            guard now >= mole.upAt - earlySlack else { throw OfflineRefusal("That mole isn't up yet.") }
            guard OfflineReaction.counts(ms) else { throw OfflineRefusal("Too quick to be a real whack.") }
            // The phone hides a mole once it drops; a time past that (plus a
            // frame or two) was not a hit on a mole that was showing.
            guard Double(ms) <= (mole.downAt - mole.upAt) * 1000 + 50 else {
                throw OfflineRefusal("Too late — that mole had dropped.")
            }

            mole.whacks.append(Whack(playerId: playerId, ms: ms))
            if mole.kind == .bomb {
                // A bomb punishes every hit at once; nobody races for it.
                mole.bombed.append(playerId)
                state.scores[playerId, default: 0] += Kind.bomb.points
                state.bombs[playerId, default: 0] += 1
            } else {
                // The first whack in starts a short wait for a quicker one.
                mole.closesAt = min(mole.closesAt, now + claimWindow)
            }
            state.moles[index] = mole
            if everyoneHasWhacked(mole, in: state) { settle(&state, index: index) }
        }
    }

    static func tick(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        switch state.phase {
        case .playing:
            for index in state.moles.indices where !state.moles[index].resolved && now >= state.moles[index].closesAt {
                settle(&state, index: index)
            }
            state.moles.removeAll { $0.resolved && now >= max($0.downAt, $0.closesAt) + keepResolved }
            schedule(&state, now: now, rng: &rng)
            let pending = state.moles.contains { !$0.resolved }
            if now >= state.endsAt + lateSlack, !pending {
                state.phase = .timeUp
                state.resultUntil = now + resultPause
            }
        case .timeUp:
            if now >= state.resultUntil { state.phase = .over }
        case .over:
            break
        }
    }

    static func playerLeft(_ playerId: String, state: inout State, now: Double, rng: inout OfflineRNG) {
        guard state.players.contains(where: { $0.id == playerId }), !state.away.contains(playerId) else { return }
        state.away.append(playerId)
        // A mole only waiting for them need not wait any more.
        for index in state.moles.indices where !state.moles[index].resolved && everyoneHasWhacked(state.moles[index], in: state) {
            settle(&state, index: index)
        }
    }

    static func view(of state: State, for playerId: String?) -> PlayerView {
        let moles = state.moles.map { mole in
            MoleView(id: mole.id, hole: mole.hole, kind: mole.kind, upAt: mole.upAt, downAt: mole.downAt,
                     resolved: mole.resolved, takenBy: mole.resolved ? mole.takenBy : nil,
                     bombed: mole.bombed,
                     mine: playerId.map { id in mole.whacks.contains { $0.playerId == id } } ?? false)
        }
        let rows = state.players.map { player in
            Row(id: player.id, name: player.name, score: state.scores[player.id] ?? 0,
                away: state.away.contains(player.id))
        }
        return PlayerView(phase: state.phase, startsAt: state.startsAt, endsAt: state.endsAt,
                          resultUntil: state.resultUntil, moles: moles, rows: rows,
                          champions: state.phase == .playing ? [] : champions(state))
    }

    static func isOver(_ state: State) -> Bool { state.phase == .over }

    static func standings(_ state: State) -> [OfflineStanding] {
        OfflineStanding.ranked(state.players, score: { state.scores[$0.id] ?? 0 }, detail: { player in
            var parts: [String] = []
            let taken = state.taken[player.id] ?? 0
            parts.append(taken == 1 ? "1 mole" : "\(taken) moles")
            let golden = state.golden[player.id] ?? 0
            if golden > 0 { parts.append("\(golden) golden") }
            let bombs = state.bombs[player.id] ?? 0
            if bombs > 0 { parts.append(bombs == 1 ? "1 bomb" : "\(bombs) bombs") }
            if let best = state.best[player.id] { parts.append("best \(best) ms") }
            if state.away.contains(player.id) { parts.append("left") }
            return parts.joined(separator: " · ")
        })
    }

    // MARK: - Helpers

    /// How far through the 45 seconds a host instant is, 0…1.
    static func progress(_ state: State, at time: Double) -> Double {
        min(1, max(0, (time - state.startsAt) / duration))
    }

    /// Draw every mole due to pop up before `now + lookahead`, in order. The
    /// draws depend only on the schedule, never on when the host ticks, so a
    /// seed always gives the same moles.
    private static func schedule(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        while !state.scheduleDone, state.nextUpAt <= now + lookahead {
            let upAt = state.nextUpAt
            let p = progress(state, at: upAt)
            let up = upAtStart + (upAtEnd - upAtStart) * p
            let downAt = upAt + up
            guard downAt <= state.endsAt else {
                // It would still be up at the whistle: that was the last one.
                state.scheduleDone = true
                return
            }
            // A hole that is still busy (up, or showing who took it) is skipped.
            let busy = state.moles.filter { $0.downAt + 0.15 > upAt }.map(\.hole)
            let free = (0..<holes).filter { !busy.contains($0) }
            let hole = rng.pick(free) ?? rng.int(below: holes)
            var kind = Kind.mole
            let roll = rng.unit()
            if upAt - state.startsAt >= specialsAfter {
                if roll < bombChance { kind = .bomb } else if roll < bombChance + goldenChance { kind = .golden }
            }
            state.moles.append(Mole(id: state.nextId, hole: hole, kind: kind, upAt: upAt, downAt: downAt,
                                    closesAt: downAt + lateSlack))
            state.nextId += 1
            let gap = gapAtStart + (gapAtEnd - gapAtStart) * p
            state.nextUpAt = upAt + gap * rng.double(in: 0.8...1.2)
        }
    }

    /// Everyone still here has had a go at this mole.
    private static func everyoneHasWhacked(_ mole: Mole, in state: State) -> Bool {
        state.players.allSatisfy { player in
            state.away.contains(player.id) || mole.whacks.contains { $0.playerId == player.id }
        }
    }

    /// Close a mole: the lowest reported time takes it (seat order breaks an
    /// exact tie). Bombs were scored as they were hit.
    private static func settle(_ state: inout State, index: Int) {
        var mole = state.moles[index]
        guard !mole.resolved else { return }
        mole.resolved = true
        if mole.kind != .bomb {
            var winner: Whack?
            for player in state.players {
                guard let whack = mole.whacks.first(where: { $0.playerId == player.id }) else { continue }
                if winner == nil || whack.ms < winner!.ms { winner = whack }
            }
            if let winner {
                mole.takenBy = winner.playerId
                state.scores[winner.playerId, default: 0] += mole.kind.points
                state.taken[winner.playerId, default: 0] += 1
                if mole.kind == .golden { state.golden[winner.playerId, default: 0] += 1 }
                if let best = state.best[winner.playerId] {
                    state.best[winner.playerId] = min(best, winner.ms)
                } else {
                    state.best[winner.playerId] = winner.ms
                }
            }
        }
        state.moles[index] = mole
    }

    /// The highest score (several on a tie); nobody if nobody scored above zero.
    static func champions(_ state: State) -> [String] {
        let live = state.players.map(\.id)
        guard let top = live.compactMap({ state.scores[$0] }).max(), top > 0 else { return [] }
        return live.filter { state.scores[$0] == top }
    }
}
