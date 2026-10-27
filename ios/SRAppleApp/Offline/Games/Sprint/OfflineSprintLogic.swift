import Foundation

/// Maths Sprint with no internet: sixty seconds of mental arithmetic, alone or
/// against up to four phones in the room.
///
/// The site's Quick Maths Sprint marks answers on the server; this one marks
/// them on the host phone, so it plays on a plane. Every player gets the SAME
/// problems in the same order — dealt once from the seeded generator — so a
/// race is fair and a solo run can be compared with yesterday's. Problems
/// start with sums to twenty and climb through times tables to two-digit
/// sums and division as a player gets further in.
///
/// A right answer scores 10, and every fifth right answer in a row adds a
/// bonus of 5. A wrong answer scores nothing and breaks the streak, and the
/// next problem comes up either way, so nobody is stuck on one sum.
///
/// The answers never leave the host: a player's view carries only the text
/// of their current problem, and everyone's running score.
enum OfflineSprintRules: OfflineGameRules {
    /// Seconds of play.
    static let seconds: Double = 60
    /// Seconds of "3, 2, 1" before the first problem.
    static let countdown: Double = 3
    /// How long the final scores stay up before the standings.
    static let resultPause: Double = 4
    /// Problems dealt; far more than anyone answers in a minute.
    static let dealt = 150
    static let pointsRight = 10
    /// A bonus on every `streakEvery`-th right answer in a row.
    static let streakEvery = 5
    static let streakBonus = 5

    static let info = OfflineGameInfo(
        id: "maths-sprint",
        title: "Maths Sprint",
        blurb: "Sixty seconds of mental arithmetic. Same sums for everyone.",
        category: .skill,
        minPlayers: 1,
        maxPlayers: 5,
        symbol: "plus.forwardslash.minus",
        howToPlay: [
            "Answer each sum on the keypad and tap Enter.",
            "Right answers score \(pointsRight); every \(streakEvery) in a row adds \(streakBonus) more.",
            "A wrong answer scores nothing and moves you on.",
            "The sums get harder the further you get.",
            "Highest score after \(Int(seconds)) seconds wins. Play alone to beat your best."
        ]
    )

    // MARK: - State

    enum Phase: String, Codable, Equatable {
        /// "3, 2, 1" until `startsAt`.
        case countdown
        case playing
        /// Time is up; scores show until `resultUntil`.
        case done
        case over
    }

    struct Problem: Codable, Equatable {
        let text: String
        let answer: Int
    }

    struct Racer: Codable, Equatable {
        var index = 0
        var score = 0
        var right = 0
        var wrong = 0
        var streak = 0
        var bestStreak = 0
    }

    struct State: Codable, Equatable {
        var players: [OfflinePlayer]
        var away: [String] = []
        var problems: [Problem]
        var racers: [String: Racer]
        var phase: Phase = .countdown
        var startsAt: Double
        var endsAt: Double
        var resultUntil: Double = 0
    }

    enum Action: Codable, Equatable {
        /// My answer to problem `index` (the view's `index`).
        case answer(index: Int, value: Int)
    }

    // MARK: - What a player sees

    struct Row: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        let score: Int
        let right: Int
        let away: Bool
    }

    struct Mine: Codable, Equatable {
        /// Nil before the start and once time is up.
        let problem: String?
        let index: Int
        let score: Int
        let right: Int
        let wrong: Int
        let streak: Int
        /// Whether my last answer was right — nil before the first.
        let lastRight: Bool?
    }

    struct PlayerView: Codable, Equatable {
        let phase: Phase
        let startsAt: Double
        let endsAt: Double
        /// Nil for a spectator.
        let me: Mine?
        /// Everyone, best score first.
        let board: [Row]
    }

    // MARK: - Rules

    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State {
        var racers: [String: Racer] = [:]
        for player in players { racers[player.id] = Racer() }
        let problems = (0..<dealt).map { problem(level: level(for: $0), rng: &rng) }
        return State(players: players, problems: problems, racers: racers,
                     startsAt: now + countdown, endsAt: now + countdown + seconds)
    }

    static func apply(_ action: Action, by playerId: String, to state: inout State, now: Double, rng: inout OfflineRNG) throws {
        guard var racer = state.racers[playerId] else { throw OfflineRefusal("You are not in this race.") }
        guard state.phase == .playing, now < state.endsAt else {
            throw OfflineRefusal(state.phase == .countdown ? "Wait for the start." : "Time is up.")
        }
        switch action {
        case .answer(let index, let value):
            guard index == racer.index else { throw OfflineRefusal("That answer was for an earlier sum.") }
            guard state.problems.indices.contains(index) else { throw OfflineRefusal("You have answered every sum!") }
            if value == state.problems[index].answer {
                racer.right += 1
                racer.streak += 1
                racer.bestStreak = max(racer.bestStreak, racer.streak)
                racer.score += pointsRight + (racer.streak % streakEvery == 0 ? streakBonus : 0)
            } else {
                racer.wrong += 1
                racer.streak = 0
            }
            racer.index += 1
            state.racers[playerId] = racer
        }
    }

    static func tick(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        switch state.phase {
        case .countdown:
            if now >= state.startsAt { state.phase = .playing }
        case .playing:
            if now >= state.endsAt {
                state.phase = .done
                state.resultUntil = now + resultPause
            }
        case .done:
            if now >= state.resultUntil { state.phase = .over }
        case .over:
            break
        }
    }

    static func playerLeft(_ playerId: String, state: inout State, now: Double, rng: inout OfflineRNG) {
        if !state.away.contains(playerId) { state.away.append(playerId) }
    }

    static func view(of state: State, for playerId: String?) -> PlayerView {
        let board = state.players
            .map { player -> Row in
                let racer = state.racers[player.id] ?? Racer()
                return Row(id: player.id, name: player.name, score: racer.score, right: racer.right,
                           away: state.away.contains(player.id))
            }
            .enumerated()
            .sorted { $0.element.score == $1.element.score ? $0.offset < $1.offset : $0.element.score > $1.element.score }
            .map(\.element)
        var mine: Mine?
        if let playerId, let racer = state.racers[playerId] {
            let showing = state.phase == .playing && state.problems.indices.contains(racer.index)
            let answered = racer.right + racer.wrong
            mine = Mine(
                problem: showing ? state.problems[racer.index].text : nil,
                index: racer.index, score: racer.score, right: racer.right, wrong: racer.wrong,
                streak: racer.streak,
                lastRight: answered == 0 ? nil : racer.streak > 0
            )
        }
        return PlayerView(phase: state.phase, startsAt: state.startsAt, endsAt: state.endsAt, me: mine, board: board)
    }

    static func isOver(_ state: State) -> Bool { state.phase == .over }

    static func standings(_ state: State) -> [OfflineStanding] {
        OfflineStanding.ranked(state.players, score: { state.racers[$0.id]?.score ?? 0 }, detail: { player in
            let racer = state.racers[player.id] ?? Racer()
            var parts = ["\(racer.right) right", "\(racer.wrong) wrong"]
            if racer.bestStreak >= 2 { parts.append("best streak \(racer.bestStreak)") }
            if state.away.contains(player.id) { parts.append("left") }
            return parts.joined(separator: " · ")
        })
    }

    // MARK: - Problems

    /// How hard problem `index` is: 0 for the first ten, then 1, 2 and 3.
    static func level(for index: Int) -> Int {
        switch index {
        case ..<10: return 0
        case ..<25: return 1
        case ..<45: return 2
        default: return 3
        }
    }

    /// One problem at `level`. Every answer is a whole number of 0 or more.
    static func problem(level: Int, rng: inout OfflineRNG) -> Problem {
        switch level {
        case 0:
            let a = rng.int(in: 1...10), b = rng.int(in: 1...10)
            if rng.chance(0.5) { return Problem(text: "\(a) + \(b)", answer: a + b) }
            let big = max(a, b) + rng.int(in: 0...9)
            return Problem(text: "\(big) − \(min(a, b))", answer: big - min(a, b))
        case 1:
            if rng.chance(0.5) {
                let a = rng.int(in: 2...10), b = rng.int(in: 2...10)
                return Problem(text: "\(a) × \(b)", answer: a * b)
            }
            let a = rng.int(in: 11...60), b = rng.int(in: 5...39)
            return rng.chance(0.5)
                ? Problem(text: "\(a) + \(b)", answer: a + b)
                : Problem(text: "\(a + b) − \(b)", answer: a)
        case 2:
            let b = rng.int(in: 2...12), q = rng.int(in: 2...12)
            switch rng.int(below: 3) {
            case 0: return Problem(text: "\(b * q) ÷ \(b)", answer: q)
            case 1: return Problem(text: "\(b) × \(q)", answer: b * q)
            default:
                let a = rng.int(in: 25...99), c = rng.int(in: 12...89)
                return Problem(text: "\(a) + \(c)", answer: a + c)
            }
        default:
            switch rng.int(below: 3) {
            case 0:
                let a = rng.int(in: 11...19), b = rng.int(in: 3...9)
                return Problem(text: "\(a) × \(b)", answer: a * b)
            case 1:
                let b = rng.int(in: 3...12), q = rng.int(in: 6...15)
                return Problem(text: "\(b * q) ÷ \(b)", answer: q)
            default:
                let a = rng.int(in: 101...499), c = rng.int(in: 21...99)
                return Problem(text: "\(a) − \(c)", answer: a - c)
            }
        }
    }
}
