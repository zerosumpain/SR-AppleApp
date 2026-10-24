import Foundation

/// Steady Hand: tilt your phone to keep a rolling ball inside a ring that
/// drifts and shrinks. One to five phones.
///
/// Every phone runs its own little table: the ball rolls by the phone's tilt
/// (or follows a finger when there is no motion sensor), and the ring moves
/// along a path every phone works out from the same numbers, so everyone
/// chases exactly the same ring at exactly the same host-clock instant. Each
/// phone measures, second by second, how much of that second its ball spent
/// inside the ring, and reports it in tenths; the host adds the tenths up,
/// times the round's multiplier, and keeps the table. Three rounds of twenty
/// seconds — the ring is smaller and quicker each time, and worth more.
///
/// The host is the referee of time, not of the ball: it runs the rounds, says
/// when a second may be reported, refuses a second twice, a second that has
/// not happened yet, or a figure that cannot be right. The physics and the
/// ring's path live here too, as pure functions, so the view and the tests
/// use the very same maths.
enum SteadyHandRules: OfflineGameRules {
    /// Rounds in a match.
    static let rounds = 3
    /// Seconds of play in a round.
    static let roundSeconds = 20
    /// The "get ready" pause before each round, seconds.
    static let readyPause: Double = 3
    /// How long after a round's last second the host still takes reports —
    /// the final second's report is sent as it ends and needs time to arrive.
    static let reportGrace: Double = 1.5
    /// How long a round's result stays up, seconds.
    static let resultPause: Double = 5
    /// A second may be reported this long before the host's clock says it
    /// has ended — a guest's estimate of the host clock is a few ms out over
    /// Wi-Fi and tens of ms over Bluetooth, so an honest phone is never caught.
    static let earlySlack: Double = 0.5
    /// The ball's radius, in table units (the table runs from -1 to 1 each way).
    static let ballRadius: Double = 0.07

    static let info = OfflineGameInfo(
        id: "steady-hand",
        title: "Steady Hand",
        blurb: "Tilt your phone to keep the ball inside a drifting, shrinking ring.",
        category: .skill,
        minPlayers: 1,
        maxPlayers: 5,
        symbol: "scope",
        howToPlay: [
            "Hold your phone flat; tilt it to roll the ball.",
            "Keep the ball inside the ring as it drifts and shrinks.",
            "Every tenth of a second inside scores, times the round's multiplier.",
            "Three rounds of \(roundSeconds) seconds: ×1, ×2, then ×3.",
            "No motion sensor? Drag your finger to steer instead.",
            "Most points after round \(rounds) wins."
        ]
    )

    /// What a round is worth per tenth of a second inside: ×1, ×2, ×3.
    static func multiplier(round: Int) -> Int { max(1, min(round, rounds)) }

    // MARK: - The ring's path

    /// Where the ring is, and how big, through one round — the same numbers on
    /// every phone, so the ring is a pure function of the time into the round.
    /// The centre traces a Lissajous curve; the radius shrinks steadily.
    struct RingPath: Codable, Equatable {
        var ampX: Double
        var ampY: Double
        /// Radians a second.
        var freqX: Double
        var freqY: Double
        var phaseX: Double
        var phaseY: Double
        var startRadius: Double
        var endRadius: Double

        /// The ring's centre `t` seconds into the round, in table units.
        func center(at t: Double) -> (x: Double, y: Double) {
            let s = clamped(t)
            return (ampX * sin(freqX * s + phaseX), ampY * sin(freqY * s + phaseY))
        }

        /// The ring's radius `t` seconds into the round, in table units.
        func radius(at t: Double) -> Double {
            let fraction = clamped(t) / Double(SteadyHandRules.roundSeconds)
            return startRadius + (endRadius - startRadius) * fraction
        }

        /// Whether a ball centred at (`x`, `y`) is inside the ring at `t`.
        func contains(x: Double, y: Double, at t: Double) -> Bool {
            let c = center(at: t)
            let dx = x - c.x, dy = y - c.y
            return (dx * dx + dy * dy).squareRoot() <= radius(at: t)
        }

        private func clamped(_ t: Double) -> Double {
            min(max(t, 0), Double(SteadyHandRules.roundSeconds))
        }
    }

    /// The ring for `round`: smaller and quicker each round, drawn from `rng`.
    /// The amplitude leaves room for the ring, so it never leaves the table.
    static func makePath(round: Int, rng: inout OfflineRNG) -> RingPath {
        let tier: (start: Double, end: Double, speed: ClosedRange<Double>)
        switch multiplier(round: round) {
        case 1: tier = (0.42, 0.30, 0.30...0.45)
        case 2: tier = (0.34, 0.22, 0.45...0.65)
        default: tier = (0.27, 0.15, 0.65...0.90)
        }
        let reach = 0.92 - tier.start
        return RingPath(
            ampX: rng.double(in: 0.35...reach),
            ampY: rng.double(in: 0.35...reach),
            freqX: rng.double(in: tier.speed),
            freqY: rng.double(in: tier.speed),
            phaseX: rng.double(in: 0...(2 * Double.pi)),
            phaseY: rng.double(in: 0...(2 * Double.pi)),
            startRadius: tier.start,
            endRadius: tier.end
        )
    }

    // MARK: - The ball

    /// The ball on one phone's table: where it is and how fast it rolls.
    /// Kept by the view, never sent; the maths is here so it can be tested.
    struct Ball: Equatable {
        var x: Double = 0
        var y: Double = 0
        var vx: Double = 0
        var vy: Double = 0

        /// Table units a second², per g of tilt.
        static let pull: Double = 2.4
        /// Fraction of speed lost each second to rolling friction (as a rate).
        static let friction: Double = 1.4
        /// Speed kept off a wall.
        static let bounce: Double = 0.35

        /// Roll for `dt` seconds under a tilt. `tiltX` is gravity along the
        /// phone's width (right positive), `tiltY` along its height (towards
        /// the top positive), each in g — `CMDeviceMotion.gravity.x` and `.y`.
        /// Screen y grows downwards, so a phone tipped top-down rolls the
        /// ball up the screen.
        mutating func roll(tiltX: Double, tiltY: Double, dt: Double) {
            let step = min(max(dt, 0), 0.1)
            vx += tiltX * Self.pull * step
            vy -= tiltY * Self.pull * step
            let keep = exp(-Self.friction * step)
            vx *= keep
            vy *= keep
            x += vx * step
            y += vy * step
            keepOnTable()
        }

        /// Follow a finger at (`toX`, `toY`) for `dt` seconds — the drag
        /// fallback. It lags a little behind the finger, so a steady hand
        /// still matters.
        mutating func follow(toX: Double, toY: Double, dt: Double) {
            let step = min(max(dt, 0), 0.1)
            guard step > 0 else { return }
            let share = 1 - exp(-step / 0.25)
            let nx = x + (toX - x) * share
            let ny = y + (toY - y) * share
            vx = (nx - x) / step
            vy = (ny - y) / step
            x = nx
            y = ny
            keepOnTable()
        }

        /// Stop at the table's edge, bouncing back a little.
        private mutating func keepOnTable() {
            let edge = 1 - SteadyHandRules.ballRadius
            if x > edge { x = edge; vx = -abs(vx) * Self.bounce }
            if x < -edge { x = -edge; vx = abs(vx) * Self.bounce }
            if y > edge { y = edge; vy = -abs(vy) * Self.bounce }
            if y < -edge { y = -edge; vy = abs(vy) * Self.bounce }
        }
    }

    // MARK: - State

    enum Phase: String, Codable, Equatable {
        /// "Get ready": the ring sits at its start; play begins at `startsAt`.
        case ready
        /// The round runs from `startsAt` to `endsAt`; reports are taken until `closesAt`.
        case playing
        /// The round's points are up until `resultUntil`.
        case result
        /// The match is decided.
        case over
    }

    struct State: Codable, Equatable {
        var players: [OfflinePlayer]
        /// Players whose phones have left; they score nothing until they report again.
        var away: [String] = []
        var round = 0
        var phase: Phase = .ready
        /// Host clock: the round's first second begins.
        var startsAt: Double = 0
        /// Host clock: the round's last second ends.
        var endsAt: Double = 0
        /// Host clock: the last report for this round is taken.
        var closesAt: Double = 0
        var resultUntil: Double = 0
        var path: RingPath
        /// Seconds (0-based) each player has reported this round, ascending.
        var reported: [String: [Int]] = [:]
        /// Points this round.
        var roundPoints: [String: Int] = [:]
        /// Points this match.
        var totals: [String: Int] = [:]
        /// Tenths of a second inside the ring, all match.
        var tenths: [String: Int] = [:]
    }

    enum Action: Codable, Equatable {
        /// For `second` (0-based) of `round`, the ball was inside the ring
        /// for `tenths` tenths of that second.
        case report(round: Int, second: Int, tenths: Int)
    }

    // MARK: - What a player sees

    struct Row: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        let total: Int
        let roundPoints: Int
        /// Seconds reported this round — a progress mark, not a secret.
        let seconds: Int
        let away: Bool
    }

    struct PlayerView: Codable, Equatable {
        let round: Int
        let rounds: Int
        let phase: Phase
        let startsAt: Double
        let endsAt: Double
        let resultUntil: Double
        let path: RingPath
        let multiplier: Int
        let roundSeconds: Int
        let rows: [Row]
        /// The seconds of mine the host has this round (empty for a spectator).
        let myReported: [Int]
        /// This round's best scorers, once the round is over.
        let roundLeaders: [String]
        /// The match winners, once it is over (several on a tie).
        let champions: [String]
    }

    // MARK: - Rules

    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State {
        var state = State(players: players, path: makePath(round: 1, rng: &rng))
        for player in players {
            state.totals[player.id] = 0
            state.tenths[player.id] = 0
        }
        beginRound(&state, now: now, rng: &rng)
        return state
    }

    static func apply(_ action: Action, by playerId: String, to state: inout State, now: Double, rng: inout OfflineRNG) throws {
        guard state.players.contains(where: { $0.id == playerId }) else {
            throw OfflineRefusal("You are not in this match.")
        }
        switch action {
        case .report(let round, let second, let tenths):
            switch state.phase {
            case .playing: break
            case .ready: throw OfflineRefusal("The round has not started yet.")
            case .result, .over: throw OfflineRefusal("This round is over.")
            }
            guard round == state.round else { throw OfflineRefusal("That score was for another round.") }
            guard second >= 0, second < roundSeconds else { throw OfflineRefusal("A round has only \(roundSeconds) seconds.") }
            guard tenths >= 0, tenths <= 10 else { throw OfflineRefusal("That score cannot be right.") }
            guard now >= state.startsAt + Double(second + 1) - earlySlack else {
                throw OfflineRefusal("That second has not finished yet.")
            }
            let mine = state.reported[playerId] ?? []
            guard !mine.contains(second) else { throw OfflineRefusal("You have already scored that second.") }

            // A phone that dropped and came back plays on from here.
            state.away.removeAll { $0 == playerId }
            state.reported[playerId] = (mine + [second]).sorted()
            let points = tenths * multiplier(round: state.round)
            state.roundPoints[playerId, default: 0] += points
            state.totals[playerId, default: 0] += points
            state.tenths[playerId, default: 0] += tenths
            if everyoneHasReported(state) { closeRound(&state, now: now) }
        }
    }

    static func tick(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        switch state.phase {
        case .ready:
            if now >= state.startsAt { state.phase = .playing }
        case .playing:
            if now >= state.closesAt { closeRound(&state, now: now) }
        case .result:
            guard now >= state.resultUntil else { return }
            if state.round >= rounds {
                state.phase = .over
            } else {
                state.path = makePath(round: state.round + 1, rng: &rng)
                beginRound(&state, now: now, rng: &rng)
            }
        case .over:
            break
        }
    }

    static func playerLeft(_ playerId: String, state: inout State, now: Double, rng: inout OfflineRNG) {
        guard state.players.contains(where: { $0.id == playerId }), !state.away.contains(playerId) else { return }
        state.away.append(playerId)
        // Nobody left to wait for: once the clock has run, close at once.
        if state.phase == .playing, now >= state.endsAt, everyoneHasReported(state) { closeRound(&state, now: now) }
    }

    static func view(of state: State, for playerId: String?) -> PlayerView {
        let rows = state.players.map { player in
            Row(id: player.id, name: player.name, total: state.totals[player.id] ?? 0,
                roundPoints: state.roundPoints[player.id] ?? 0,
                seconds: state.reported[player.id]?.count ?? 0,
                away: state.away.contains(player.id))
        }
        let closed = state.phase == .result || state.phase == .over
        return PlayerView(
            round: state.round, rounds: rounds, phase: state.phase,
            startsAt: state.startsAt, endsAt: state.endsAt, resultUntil: state.resultUntil,
            path: state.path, multiplier: multiplier(round: state.round), roundSeconds: roundSeconds,
            rows: rows,
            myReported: playerId.flatMap { state.reported[$0] } ?? [],
            roundLeaders: closed ? roundLeaders(state) : [],
            champions: state.phase == .over ? champions(state) : []
        )
    }

    static func isOver(_ state: State) -> Bool { state.phase == .over }

    static func standings(_ state: State) -> [OfflineStanding] {
        OfflineStanding.ranked(state.players, score: { state.totals[$0.id] ?? 0 }, detail: { player in
            let tenths = state.tenths[player.id] ?? 0
            var parts = ["\(tenths / 10).\(tenths % 10) s in the ring"]
            if state.away.contains(player.id) { parts.append("left") }
            return parts.joined(separator: " · ")
        })
    }

    // MARK: - Helpers

    private static func beginRound(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        state.round += 1
        state.phase = .ready
        state.startsAt = now + readyPause
        state.endsAt = state.startsAt + Double(roundSeconds)
        state.closesAt = state.endsAt + reportGrace
        state.reported = [:]
        state.roundPoints = [:]
        for player in state.players { state.roundPoints[player.id] = 0 }
    }

    /// Everyone still here has reported every second of the round.
    private static func everyoneHasReported(_ state: State) -> Bool {
        let present = state.players.filter { !state.away.contains($0.id) }
        guard !present.isEmpty else { return true }
        return present.allSatisfy { (state.reported[$0.id]?.count ?? 0) >= roundSeconds }
    }

    private static func closeRound(_ state: inout State, now: Double) {
        state.phase = .result
        state.resultUntil = now + resultPause
    }

    /// The best scorers of the round just played (several on a tie; nobody
    /// if nobody scored).
    static func roundLeaders(_ state: State) -> [String] {
        let top = state.players.map { state.roundPoints[$0.id] ?? 0 }.max() ?? 0
        guard top > 0 else { return [] }
        return state.players.map(\.id).filter { state.roundPoints[$0] == top }
    }

    /// The most points (several on a tie); nobody if nobody scored.
    static func champions(_ state: State) -> [String] {
        let top = state.players.map { state.totals[$0.id] ?? 0 }.max() ?? 0
        guard top > 0 else { return [] }
        return state.players.map(\.id).filter { state.totals[$0] == top }
    }
}
