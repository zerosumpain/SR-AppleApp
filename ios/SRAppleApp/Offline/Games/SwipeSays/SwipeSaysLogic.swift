import Foundation

/// Swipe Says: twenty-five prompts, the same for every phone, at the same
/// host-clock instants.
///
/// A prompt is one of three things. A plain arrow: swipe that way. A RED
/// arrow: swipe the OPPOSITE way. A circle: do nothing at all — any swipe is
/// wrong, and holding still earns a steady `holdPoints`. Each prompt stays
/// open for `windowFor(_:)` seconds, starting at 1.5 s and shrinking to 0.9 s
/// by the last one.
///
/// Like Quick Draw, speed is measured on the swiping phone — from the frame
/// that showed the prompt to the moment the swipe was recognised — and only
/// the milliseconds travel. A right swipe scores `100 − ms/15`, never less
/// than 10; a wrong one, a missed one or one too soon scores nothing. The
/// highest total after the last prompt wins.
///
/// What is secret: the prompts still to come. Each view carries only the
/// prompt that is up next (its phone needs it a moment early to show it on
/// the right frame) and the one just closed; the rest of the sequence stays
/// on the host. Other players' answers to the open prompt show only as
/// "answered" until it closes.
enum SwipeSaysRules: OfflineGameRules {
    /// Prompts in a match.
    static let promptCount = 25
    /// How long before the first prompt, seconds: "Get ready".
    static let leadIn: Double = 3
    /// The first prompt's window, seconds.
    static let firstWindow: Double = 1.5
    /// The last prompt's window, seconds.
    static let lastWindow: Double = 0.9
    /// The pause between one prompt closing and the next showing, seconds —
    /// long enough to read the last result.
    static let gapRange: ClosedRange<Double> = 0.8...1.4
    /// How long the host keeps a prompt open past its window, for a swipe
    /// still crossing a Bluetooth link. The swipe's own time still has to be
    /// inside the window to score.
    static let lateGrace: Double = 0.4
    /// A swipe reaching the host this long BEFORE the prompt was due (host
    /// clock) cannot have been a reaction, whatever the phone says.
    static let earlySlack: Double = 0.5
    /// How long the final scores stay up before the match ends, seconds.
    static let finalPause: Double = 4
    /// Points for correctly ignoring a circle.
    static let holdPoints = 50
    /// Chance a prompt (after the first) is a circle.
    static let circleChance = 0.16
    /// Chance an arrow (after the first) is red.
    static let redChance = 0.32

    static let info = OfflineGameInfo(
        id: "swipe-says",
        title: "Swipe Says",
        blurb: "Swipe the way the arrow says — unless it's red, or a circle.",
        category: .reaction,
        minPlayers: 2,
        maxPlayers: 5,
        symbol: "hand.draw.fill",
        howToPlay: [
            "Everyone gets the same \(promptCount) prompts at the same moment.",
            "An arrow: swipe that way. A red arrow: swipe the opposite way.",
            "A circle: don't swipe at all — holding still scores \(holdPoints).",
            "Faster right swipes score more (up to 100); wrong or missed scores 0.",
            "Prompts get quicker as you go. The arrow buttons work instead of swiping.",
            "Highest total after \(promptCount) prompts wins."
        ]
    )

    // MARK: - Prompts

    enum Direction: String, Codable, Equatable, CaseIterable {
        case up, down, left, right

        var opposite: Direction {
            switch self {
            case .up: return .down
            case .down: return .up
            case .left: return .right
            case .right: return .left
            }
        }

        /// "up", "left" — for sentences and VoiceOver.
        var word: String { rawValue }
    }

    /// One prompt. `direction == nil` is a circle.
    struct Prompt: Codable, Equatable {
        var direction: Direction?
        var red: Bool

        static let circle = Prompt(direction: nil, red: false)

        var isCircle: Bool { direction == nil }

        /// The swipe that scores, or nil when the right answer is no swipe.
        var expected: Direction? {
            guard let direction else { return nil }
            return red ? direction.opposite : direction
        }

        /// "Swipe left", "Red up: swipe down", "Circle: hold still".
        var instruction: String {
            guard let direction else { return "Circle: hold still" }
            return red ? "Red \(direction.word): swipe \(direction.opposite.word)" : "Swipe \(direction.word)"
        }
    }

    /// How one player's answer to one prompt was judged.
    enum Verdict: String, Codable, Equatable {
        /// The right swipe, in time.
        case right
        /// A swipe the wrong way — or any swipe at a circle.
        case wrong
        /// Swiped before the prompt showed, or quicker than a reaction can be.
        case tooSoon
        /// The right way, but after the window had closed.
        case tooSlow
        /// No swipe at an arrow.
        case missed
        /// No swipe at a circle: correct.
        case held
    }

    /// One player's answer to the open prompt (or the one just closed).
    struct Answer: Codable, Equatable {
        var direction: Direction?
        var ms: Int?
        var verdict: Verdict
        var points: Int
    }

    // MARK: - State

    enum Phase: String, Codable, Equatable {
        /// Prompts are running: the current one shows at `showAt`.
        case playing
        /// The last prompt has closed; the final scores show until `endsAt`.
        case finished
        /// The match is decided.
        case over
    }

    struct State: Codable, Equatable {
        var players: [OfflinePlayer]
        /// Players whose phones have left; they are not waited for.
        var away: [String] = []
        /// The whole sequence. Secret beyond `index`.
        var prompts: [Prompt]
        var phase: Phase = .playing
        /// The open prompt, 0-based.
        var index = 0
        /// When the open prompt shows, host clock.
        var showAt: Double = 0
        /// When its window ends, host clock (the host waits `lateGrace` more).
        var closesAt: Double = 0
        /// Answers to the open prompt, by player.
        var answers: [String: Answer] = [:]
        /// The prompt just closed and how everyone did — public.
        var lastIndex: Int?
        var lastAnswers: [String: Answer] = [:]
        var scores: [String: Int] = [:]
        /// Right answers (swipes and holds) per player.
        var rights: [String: Int] = [:]
        /// Each player's quickest right swipe, ms.
        var best: [String: Int] = [:]
        /// When the final scores give way to the standings, host clock.
        var endsAt: Double = 0
    }

    enum Action: Codable, Equatable {
        /// A swipe `ms` milliseconds after prompt `prompt` (1-based) showed
        /// on the swiping phone.
        case swipe(prompt: Int, direction: Direction, ms: Int)
        /// A swipe before prompt `prompt` showed.
        case early(prompt: Int, direction: Direction)
    }

    // MARK: - What a player sees

    struct Row: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        /// Their total. Another player's points on the open prompt join it
        /// only once the prompt closes; my own join at once.
        let score: Int
        let away: Bool
        /// Has swiped at the open prompt (not what, nor how fast).
        let answered: Bool
        /// How they did on the prompt just closed.
        let last: Verdict?
        let lastPoints: Int
    }

    struct PlayerView: Codable, Equatable {
        let phase: Phase
        /// The open prompt, 1-based, of `total`.
        let number: Int
        let total: Int
        /// The open prompt — sent before it shows, so every phone can put it
        /// up on the same instant. Nil once the prompts are done.
        let prompt: Prompt?
        /// Host clock.
        let showAt: Double
        let closesAt: Double
        /// The open prompt's window, ms: a swipe slower than this misses.
        let windowMs: Int
        /// My own answer to the open prompt, if any.
        let myAnswer: Answer?
        /// The prompt just closed (1-based) and what it was.
        let lastNumber: Int?
        let lastPrompt: Prompt?
        /// My result on it.
        let myLast: Answer?
        let rows: [Row]
        /// The leaders once the prompts are done (several on a tie).
        let champions: [String]
        let endsAt: Double
    }

    // MARK: - Rules

    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State {
        var prompts: [Prompt] = []
        for number in 0..<promptCount {
            // The first is always a plain arrow: a fair way in.
            if number > 0, rng.chance(circleChance) {
                prompts.append(.circle)
            } else {
                let direction = rng.pick(Direction.allCases) ?? .up
                let red = number > 0 && rng.chance(redChance)
                prompts.append(Prompt(direction: direction, red: red))
            }
        }
        var state = State(players: players, prompts: prompts)
        for player in players { state.scores[player.id] = 0 }
        open(&state, index: 0, at: now + leadIn)
        return state
    }

    static func apply(_ action: Action, by playerId: String, to state: inout State, now: Double, rng: inout OfflineRNG) throws {
        guard state.players.contains(where: { $0.id == playerId }) else {
            throw OfflineRefusal("You are not in this game.")
        }
        guard !state.away.contains(playerId) else { throw OfflineRefusal("You have left this game.") }
        guard state.phase == .playing else { throw OfflineRefusal("The prompts are over.") }
        let number: Int
        switch action {
        case .swipe(let n, _, _), .early(let n, _): number = n
        }
        guard number >= 1, number <= state.prompts.count else { throw OfflineRefusal("There is no such prompt.") }
        guard number <= state.index + 1 else { throw OfflineRefusal("That prompt hasn't come up yet.") }
        guard number == state.index + 1 else { throw OfflineRefusal("That prompt has closed.") }
        guard state.answers[playerId] == nil else { throw OfflineRefusal("You have already answered this one.") }

        let prompt = state.prompts[state.index]
        switch action {
        case .early(_, let direction):
            state.answers[playerId] = Answer(direction: direction, ms: nil, verdict: .tooSoon, points: 0)
        case .swipe(_, let direction, let ms):
            guard ms >= 0, ms <= 60_000 else { throw OfflineRefusal("That time cannot be right.") }
            state.answers[playerId] = judge(prompt, direction: direction, ms: ms,
                                            windowMs: windowMs(state.index),
                                            arrivedEarly: now < state.showAt - earlySlack)
        }
        if let answer = state.answers[playerId] {
            state.scores[playerId, default: 0] += answer.points
            if answer.verdict == .right {
                state.rights[playerId, default: 0] += 1
                if let ms = answer.ms { state.best[playerId] = min(state.best[playerId] ?? ms, ms) }
            }
        }
        if everyoneHasAnswered(state) { close(&state, now: now, rng: &rng) }
    }

    static func tick(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        switch state.phase {
        case .playing:
            if now >= state.closesAt + lateGrace || everyoneHasAnswered(state) { close(&state, now: now, rng: &rng) }
        case .finished:
            if now >= state.endsAt { state.phase = .over }
        case .over:
            break
        }
    }

    static func playerLeft(_ playerId: String, state: inout State, now: Double, rng: inout OfflineRNG) {
        guard state.players.contains(where: { $0.id == playerId }), !state.away.contains(playerId) else { return }
        state.away.append(playerId)
        if state.phase == .playing, everyoneHasAnswered(state) { close(&state, now: now, rng: &rng) }
    }

    static func view(of state: State, for playerId: String?) -> PlayerView {
        let open = state.phase == .playing
        let rows = state.players.map { player -> Row in
            let last = state.lastAnswers[player.id]
            // Someone else's points on the open prompt would give away whether
            // they were right and, through the formula, roughly how fast: their
            // row shows the total banked before it until the prompt closes.
            // My own row moves at once.
            let pending = open && player.id != playerId ? (state.answers[player.id]?.points ?? 0) : 0
            return Row(id: player.id, name: player.name, score: (state.scores[player.id] ?? 0) - pending,
                       away: state.away.contains(player.id),
                       answered: open && state.answers[player.id] != nil,
                       last: last?.verdict, lastPoints: last?.points ?? 0)
        }
        return PlayerView(
            phase: state.phase,
            number: state.index + 1,
            total: state.prompts.count,
            prompt: open ? state.prompts[state.index] : nil,
            showAt: state.showAt,
            closesAt: state.closesAt,
            windowMs: windowMs(state.index),
            myAnswer: open ? playerId.flatMap { state.answers[$0] } : nil,
            lastNumber: state.lastIndex.map { $0 + 1 },
            lastPrompt: state.lastIndex.map { state.prompts[$0] },
            myLast: playerId.flatMap { state.lastAnswers[$0] },
            rows: rows,
            champions: state.phase == .playing ? [] : champions(state),
            endsAt: state.endsAt
        )
    }

    static func isOver(_ state: State) -> Bool { state.phase == .over }

    static func standings(_ state: State) -> [OfflineStanding] {
        OfflineStanding.ranked(state.players, score: { state.scores[$0.id] ?? 0 }, detail: { player in
            var parts: [String] = []
            let rights = state.rights[player.id] ?? 0
            parts.append("\(rights) of \(state.prompts.count) right")
            if let best = state.best[player.id] { parts.append("best \(best) ms") }
            if state.away.contains(player.id) { parts.append("left") }
            return parts.joined(separator: " · ")
        })
    }

    // MARK: - Scoring

    /// Points for a right swipe after `ms`: 100 at once, a point less every
    /// 15 ms, never under 10.
    static func points(forMs ms: Int) -> Int {
        max(10, 100 - ms / 15)
    }

    /// The window of the prompt at `index` (0-based), seconds: shrinking in
    /// even steps from `firstWindow` to `lastWindow`.
    static func windowFor(_ index: Int) -> Double {
        let steps = Double(max(1, promptCount - 1))
        let fraction = min(1, max(0, Double(index) / steps))
        return firstWindow - (firstWindow - lastWindow) * fraction
    }

    static func windowMs(_ index: Int) -> Int { Int((windowFor(index) * 1000).rounded()) }

    /// Judge one reported swipe.
    static func judge(_ prompt: Prompt, direction: Direction, ms: Int, windowMs: Int, arrivedEarly: Bool) -> Answer {
        if arrivedEarly || !OfflineReaction.counts(ms) {
            return Answer(direction: direction, ms: nil, verdict: .tooSoon, points: 0)
        }
        guard let expected = prompt.expected, expected == direction else {
            return Answer(direction: direction, ms: ms, verdict: .wrong, points: 0)
        }
        guard ms <= windowMs else {
            return Answer(direction: direction, ms: ms, verdict: .tooSlow, points: 0)
        }
        return Answer(direction: direction, ms: ms, verdict: .right, points: points(forMs: ms))
    }

    // MARK: - Helpers

    /// Put prompt `index` up at host time `showAt`.
    private static func open(_ state: inout State, index: Int, at showAt: Double) {
        state.index = index
        state.answers = [:]
        state.showAt = showAt
        state.closesAt = showAt + windowFor(index)
    }

    /// Everyone still here has swiped at the open prompt. Nobody left at all
    /// counts too, so a room that empties never stalls.
    private static func everyoneHasAnswered(_ state: State) -> Bool {
        state.players.allSatisfy { state.away.contains($0.id) || state.answers[$0.id] != nil }
    }

    /// Close the open prompt: whoever did not swipe either held still (a
    /// circle, which scores) or missed it; then the next prompt, or the end.
    private static func close(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        let prompt = state.prompts[state.index]
        var results = state.answers
        for player in state.players where results[player.id] == nil && !state.away.contains(player.id) {
            if prompt.isCircle {
                results[player.id] = Answer(direction: nil, ms: nil, verdict: .held, points: holdPoints)
                state.scores[player.id, default: 0] += holdPoints
                state.rights[player.id, default: 0] += 1
            } else {
                results[player.id] = Answer(direction: nil, ms: nil, verdict: .missed, points: 0)
            }
        }
        state.lastIndex = state.index
        state.lastAnswers = results
        state.answers = [:]
        if state.index + 1 < state.prompts.count {
            open(&state, index: state.index + 1, at: now + rng.double(in: gapRange))
        } else {
            state.phase = .finished
            state.endsAt = now + finalPause
        }
    }

    /// The highest totals (several on a tie); nobody if nobody scored.
    static func champions(_ state: State) -> [String] {
        let top = state.players.map { state.scores[$0.id] ?? 0 }.max() ?? 0
        guard top > 0 else { return [] }
        return state.players.map(\.id).filter { (state.scores[$0] ?? 0) == top }
    }
}
