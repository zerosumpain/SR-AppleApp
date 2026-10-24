import Foundation

/// Reflex Grid: a race across a four-by-four grid for one to five phones.
///
/// Everyone gets the SAME seeded run of twenty lit tiles. After a shared
/// countdown every phone lights its first tile at the same host-clock
/// instant, and each player races through the run on their own phone: tap
/// the lit tile and the next one lights at once; tap a dark tile and half a
/// second goes on your time. Nothing waits for the network between tiles —
/// the phone has the whole run and measures its own owner from the frame that
/// showed GO, reporting each tile as it is cleared so everyone sees a live
/// progress bar of the others. Lowest total (time plus penalties) wins.
///
/// The run itself is not a secret: everybody plays the same one, so it is in
/// every view. What stays private is a racer's running time until they cross
/// the line — the others see only how many tiles they have cleared.
enum ReflexGridRules: OfflineGameRules {
    /// Tiles across and down.
    static let columns = 4
    /// Tiles on the grid.
    static let cellCount = columns * columns
    /// Lit tiles in one run.
    static let runLength = 20
    /// What a tap on a dark tile adds to your time, milliseconds.
    static let penaltyMs = 500
    /// The countdown before GO, seconds.
    static let leadIn: Double = 3
    /// How long after GO a racer has to finish, seconds; after that they did not finish.
    static let raceLimit: Double = 60
    /// How long the result stays up before the final table, seconds.
    static let resultPause: Double = 5
    /// No honest tile is cleared quicker than this after the one before, ms.
    static let minTileMs = OfflineReaction.anticipationMs
    /// A report that claims more time than the host has seen since GO by more
    /// than this cannot be honest (the phone started early). Generous, so a
    /// rough clock estimate over Bluetooth is never caught by it. Seconds.
    static let clockSlack: Double = 1
    /// Most dark-tile taps a phone may report.
    static let maxMisses = 999

    static let info = OfflineGameInfo(
        id: "reflex-grid",
        title: "Reflex Grid",
        blurb: "Race through the same twenty lit tiles; fastest total time wins.",
        category: .reaction,
        minPlayers: 1,
        maxPlayers: 5,
        symbol: "square.grid.4x3.fill",
        howToPlay: [
            "Everyone races the same run of \(runLength) lit tiles, on their own phone, at the same moment.",
            "When the countdown says GO, tap the lit tile — the next one lights straight away.",
            "A tap on a dark tile adds half a second to your time.",
            "Watch the bars to see how far the others have got.",
            "Lowest total time wins. Not done after \(Int(raceLimit)) seconds and you did not finish."
        ]
    )

    // MARK: - State

    enum Phase: String, Codable, Equatable {
        /// The countdown, then the race; GO is at `startsAt`.
        case racing
        /// Everyone has finished (or run out of time); the times are up until `resultUntil`.
        case result
        /// The match is decided.
        case over
    }

    /// One racer's run so far.
    struct Run: Codable, Equatable {
        /// Tiles cleared, 0…`runLength`.
        var cleared = 0
        /// Milliseconds from GO to the last cleared tile, as the phone measured it.
        var ms = 0
        /// Taps on dark tiles.
        var misses = 0

        var finished: Bool { cleared >= ReflexGridRules.runLength }
        /// Time plus penalties.
        var totalMs: Int { ms + misses * ReflexGridRules.penaltyMs }
    }

    struct State: Codable, Equatable {
        var players: [OfflinePlayer]
        /// Players whose phones have left; they are not waited for.
        var away: [String] = []
        var phase: Phase = .racing
        /// The lit tiles in order, each 0..<cellCount, never the same twice running.
        var sequence: [Int] = []
        /// GO, host clock.
        var startsAt: Double = 0
        /// The race closes here, host clock.
        var endsAt: Double = 0
        /// When the result gives way to the final table, host clock.
        var resultUntil: Double = 0
        var runs: [String: Run] = [:]
    }

    enum Action: Codable, Equatable {
        /// I have cleared tile number `step` (1-based) `ms` milliseconds after
        /// GO showed on my phone, with `misses` dark-tile taps so far.
        case tile(step: Int, ms: Int, misses: Int)
    }

    // MARK: - What a player sees

    struct Row: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        let cleared: Int
        let misses: Int
        let away: Bool
        let finished: Bool
        /// Their total — only once they have crossed the line.
        let totalMs: Int?
    }

    struct PlayerView: Codable, Equatable {
        let phase: Phase
        let startsAt: Double
        let endsAt: Double
        let resultUntil: Double
        /// The run everybody plays.
        let sequence: [Int]
        /// Seat order.
        let rows: [Row]
        /// My own run, with my running time.
        let mine: Run?
        /// The quickest finishers, once the race is closed (several on a tie).
        let winners: [String]
        let runLength: Int
        let columns: Int
        let penaltyMs: Int
    }

    // MARK: - Rules

    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State {
        var state = State(players: players)
        state.sequence = makeSequence(&rng)
        state.startsAt = now + leadIn
        state.endsAt = state.startsAt + raceLimit
        for player in players { state.runs[player.id] = Run() }
        return state
    }

    static func apply(_ action: Action, by playerId: String, to state: inout State, now: Double, rng: inout OfflineRNG) throws {
        guard state.players.contains(where: { $0.id == playerId }) else {
            throw OfflineRefusal("You are not in this race.")
        }
        guard !state.away.contains(playerId) else { throw OfflineRefusal("You have left this race.") }
        guard state.phase == .racing else { throw OfflineRefusal("The race is over.") }
        guard now >= state.startsAt - clockSlack else { throw OfflineRefusal("Wait for GO.") }
        let run = state.runs[playerId] ?? Run()
        guard !run.finished else { throw OfflineRefusal("You have already finished.") }

        switch action {
        case .tile(let step, let ms, let misses):
            guard step >= 1, step <= runLength else { throw OfflineRefusal("There is no such tile.") }
            guard step > run.cleared else { throw OfflineRefusal("You have already cleared that tile.") }
            guard misses >= run.misses, misses <= maxMisses else { throw OfflineRefusal("That miss count cannot be right.") }
            guard ms >= run.ms, ms >= step * minTileMs, ms <= Int(raceLimit * 1000) else {
                throw OfflineRefusal("That time cannot be right.")
            }
            // More time on the phone's stopwatch than the host has seen since GO.
            guard Double(ms) / 1000 <= now - state.startsAt + clockSlack else {
                throw OfflineRefusal("That time cannot be right.")
            }
            state.runs[playerId] = Run(cleared: step, ms: ms, misses: misses)
        }
        if everyoneIsDone(state) { close(&state, now: now) }
    }

    static func tick(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        switch state.phase {
        case .racing:
            if now >= state.endsAt + clockSlack || everyoneIsDone(state) { close(&state, now: now) }
        case .result:
            if now >= state.resultUntil { state.phase = .over }
        case .over:
            break
        }
    }

    static func playerLeft(_ playerId: String, state: inout State, now: Double, rng: inout OfflineRNG) {
        guard state.players.contains(where: { $0.id == playerId }), !state.away.contains(playerId) else { return }
        state.away.append(playerId)
        if state.phase == .racing, everyoneIsDone(state) { close(&state, now: now) }
    }

    static func view(of state: State, for playerId: String?) -> PlayerView {
        let rows = state.players.map { player -> Row in
            let run = state.runs[player.id] ?? Run()
            return Row(id: player.id, name: player.name, cleared: run.cleared, misses: run.misses,
                       away: state.away.contains(player.id), finished: run.finished,
                       totalMs: run.finished ? run.totalMs : nil)
        }
        let mine = playerId.flatMap { id in state.players.contains { $0.id == id } ? (state.runs[id] ?? Run()) : nil }
        return PlayerView(
            phase: state.phase, startsAt: state.startsAt, endsAt: state.endsAt, resultUntil: state.resultUntil,
            sequence: state.sequence, rows: rows, mine: mine,
            winners: state.phase == .racing ? [] : winners(state),
            runLength: runLength, columns: columns, penaltyMs: penaltyMs
        )
    }

    static func isOver(_ state: State) -> Bool { state.phase == .over }

    static func standings(_ state: State) -> [OfflineStanding] {
        OfflineStanding.ranked(state.players, score: { score(state.runs[$0.id] ?? Run()) }, detail: { player in
            let run = state.runs[player.id] ?? Run()
            var parts: [String] = []
            if run.finished {
                parts.append(seconds(run.totalMs))
                if run.misses > 0 { parts.append(run.misses == 1 ? "1 miss" : "\(run.misses) misses") }
            } else {
                parts.append("did not finish · \(run.cleared) of \(runLength)")
            }
            if state.away.contains(player.id) { parts.append("left") }
            return parts.joined(separator: " · ")
        }, lowerIsBetter: true)
    }

    // MARK: - Helpers

    /// The table's figure, lower is better: a finisher's total in ms; a
    /// non-finisher is behind every finisher, and ahead of anyone who cleared fewer tiles.
    static func score(_ run: Run) -> Int {
        if run.finished { return run.totalMs }
        return slowestFinish + 1_000 + (runLength - run.cleared) * 1_000
    }

    /// The worst total a finisher can post: the whole time limit plus the most
    /// misses a phone may report. Every non-finisher scores above it, so
    /// penalties never lift someone who did not finish over someone who did.
    static let slowestFinish = Int(raceLimit * 1000) + maxMisses * penaltyMs

    /// "8.42 s".
    static func seconds(_ ms: Int) -> String {
        String(format: "%.2f s", Double(ms) / 1000)
    }

    /// Twenty tiles, each different from the one before, so every tap moves.
    static func makeSequence(_ rng: inout OfflineRNG) -> [Int] {
        var tiles: [Int] = []
        for _ in 0..<runLength {
            if let last = tiles.last {
                let pick = rng.int(below: cellCount - 1)
                tiles.append(pick >= last ? pick + 1 : pick)
            } else {
                tiles.append(rng.int(below: cellCount))
            }
        }
        return tiles
    }

    /// Everyone still here has crossed the line.
    private static func everyoneIsDone(_ state: State) -> Bool {
        state.players.allSatisfy { state.away.contains($0.id) || (state.runs[$0.id]?.finished ?? false) }
    }

    /// Close the race and put the times up.
    private static func close(_ state: inout State, now: Double) {
        state.phase = .result
        state.resultUntil = now + resultPause
    }

    /// The lowest finishing total (several on a tie); nobody if nobody finished.
    static func winners(_ state: State) -> [String] {
        let finished = state.players.compactMap { player -> (String, Int)? in
            guard let run = state.runs[player.id], run.finished else { return nil }
            return (player.id, run.totalMs)
        }
        guard let best = finished.map(\.1).min() else { return [] }
        return finished.filter { $0.1 == best }.map(\.0)
    }
}
