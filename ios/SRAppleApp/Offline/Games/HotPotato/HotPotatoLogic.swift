import Foundation

/// Hot Potato: pass it on before it bursts, for three to five phones.
///
/// One player holds the potato. Somewhere inside it a fuse is burning — eight
/// to twenty seconds, chosen by the host and never shown to anyone. To get rid
/// of it the holder must first do a tiny task that only their own screen
/// shows (four shapes, one of them different: tap the odd one out), and then
/// pick who to throw it to. A wrong tap fumbles: the holder loses a moment and
/// gets a fresh task. When the fuse runs out, whoever is holding it loses a
/// life. Three lives each; lose the last and you are out, and the next potato
/// starts with a random survivor. The last one standing wins.
///
/// Everyone sees who holds the potato. Nobody — not even the host's own
/// screen — sees the fuse: it lives only in `State` and never in a view.
enum HotPotatoRules: OfflineGameRules {
    /// Lives each player starts with.
    static let startingLives = 3
    /// How long a fuse burns, seconds. Host-only.
    static let fuseRange: ClosedRange<Double> = 8...20
    /// How long a wrong tap freezes the holder, seconds.
    static let fumblePenalty: Double = 1.5
    /// How long the "it burst" moment stays up before the next potato.
    static let burstPause: Double = 3
    /// How many different shapes a task draws from (`Glyph` raw values 0..<this).
    static let shapeKinds = 8
    /// How many shapes a task shows.
    static let taskSize = 4

    static let info = OfflineGameInfo(
        id: "hot-potato",
        title: "Hot Potato",
        blurb: "Pass the potato before its hidden fuse bursts in your hands.",
        category: .reaction,
        minPlayers: 3,
        maxPlayers: 5,
        symbol: "flame.fill",
        howToPlay: [
            "Somebody holds the potato; a hidden fuse is burning inside it.",
            "Holding it? Tap the one shape that differs from the other three.",
            "Then throw it to anyone still in. A wrong tap costs you time.",
            "If it bursts in your hands you lose a life — you have \(startingLives).",
            "Lose them all and you're out. Last one standing wins."
        ]
    )

    // MARK: - State

    enum Phase: String, Codable, Equatable {
        /// The potato is going round; the fuse is burning.
        case passing
        /// It just burst; the moment stays up until `burstUntil`.
        case burst
        /// One player (or nobody) is left.
        case over
    }

    /// The shapes a task is drawn from. The view draws each as an SF Symbol.
    enum Glyph: Int, Codable, Equatable, CaseIterable {
        case circle, square, triangle, diamond, star, heart, hexagon, shield
    }

    /// The holder's current task: four shapes, three alike.
    struct Puzzle: Codable, Equatable {
        /// Counts up for every new task, so a late tap on an old one is refused.
        var number: Int
        var shapes: [Glyph]
        /// Where the odd one sits.
        var odd: Int
    }

    struct State: Codable, Equatable {
        var players: [OfflinePlayer]
        /// Players whose phones have left; they forfeit and are never thrown to.
        var away: [String] = []
        var lives: [String: Int] = [:]
        /// Players out of the match (no lives left, or left), first out first.
        var outOrder: [String] = []
        var phase: Phase = .passing
        /// Which potato this is (1, 2, …) — a new one after every burst.
        var round = 0
        /// Counts every change of holder, so a late throw is refused.
        var pass = 0
        var holder: String?
        /// Who threw it to the holder, if anybody.
        var thrower: String?
        /// When the fuse bursts, host clock. SECRET: never in a view.
        var fuseEndsAt: Double = 0
        var task = Puzzle(number: 0, shapes: [], odd: 0)
        /// The holder has done the task and may throw.
        var solved = false
        /// A fumbled holder cannot tap again until this host time.
        var lockedUntil: Double = 0
        /// Who the last potato burst on.
        var burstOn: String?
        /// When the burst moment gives way, host clock.
        var burstUntil: Double = 0
        var tosses: [String: Int] = [:]
        var fumbles: [String: Int] = [:]
    }

    enum Action: Codable, Equatable {
        /// Tap shape `choice` (0..<4) of task `task`.
        case tap(task: Int, choice: Int)
        /// Throw the potato to `target` (on pass `pass`).
        case throwTo(pass: Int, target: String)
    }

    // MARK: - What a player sees

    struct Row: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        let lives: Int
        let out: Bool
        let away: Bool
        let holding: Bool
    }

    /// The holder's own task. Nobody else's view carries one.
    struct PuzzleView: Codable, Equatable {
        let number: Int
        let shapes: [Glyph]
        let solved: Bool
        /// Host clock; taps before this are refused (a fumble's penalty).
        let lockedUntil: Double
    }

    struct PlayerView: Codable, Equatable {
        let phase: Phase
        let round: Int
        let pass: Int
        let holder: String?
        let thrower: String?
        let rows: [Row]
        /// Mine, only while I am holding the potato.
        let myTask: PuzzleView?
        let burstOn: String?
        let burstUntil: Double
        /// The last one standing, once it is over.
        let winner: String?
        let startingLives: Int
    }

    // MARK: - Rules

    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State {
        var state = State(players: players)
        for player in players { state.lives[player.id] = startingLives }
        newPotato(&state, now: now, rng: &rng)
        return state
    }

    static func apply(_ action: Action, by playerId: String, to state: inout State, now: Double, rng: inout OfflineRNG) throws {
        guard state.players.contains(where: { $0.id == playerId }), !state.away.contains(playerId) else {
            throw OfflineRefusal("You are not in this game.")
        }
        guard !state.outOrder.contains(playerId) else { throw OfflineRefusal("You are out — watch the others.") }
        guard state.phase == .passing else {
            throw OfflineRefusal(state.phase == .over ? "The game is over." : "Wait for the next potato.")
        }
        guard state.holder == playerId else {
            let holder = state.holder.flatMap { id in state.players.first { $0.id == id }?.name } ?? "Someone"
            throw OfflineRefusal("\(holder) has the potato, not you.")
        }
        // The fuse may have run out a moment before the next tick: it burst.
        guard now < state.fuseEndsAt else { throw OfflineRefusal("Too late — it burst!") }

        switch action {
        case .tap(let task, let choice):
            guard task == state.task.number else { throw OfflineRefusal("That was for an old task.") }
            guard !state.solved else { throw OfflineRefusal("Done — now throw it!") }
            guard choice >= 0, choice < state.task.shapes.count else { throw OfflineRefusal("There's no shape there.") }
            guard now >= state.lockedUntil else { throw OfflineRefusal("You fumbled — wait a moment.") }
            if choice == state.task.odd {
                state.solved = true
            } else {
                state.fumbles[playerId, default: 0] += 1
                state.lockedUntil = now + fumblePenalty
                state.task = newPuzzle(number: state.task.number + 1, rng: &rng)
            }
        case .throwTo(let pass, let target):
            guard pass == state.pass else { throw OfflineRefusal("You've already passed that one on.") }
            guard state.solved else { throw OfflineRefusal("Tap the odd shape out first.") }
            guard target != playerId else { throw OfflineRefusal("You can't throw it to yourself.") }
            guard state.players.contains(where: { $0.id == target }) else { throw OfflineRefusal("That player isn't here.") }
            guard isIn(target, state) else { throw OfflineRefusal("They're out — pick someone still in.") }
            state.tosses[playerId, default: 0] += 1
            hand(&state, to: target, from: playerId, rng: &rng)
        }
    }

    static func tick(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        switch state.phase {
        case .passing:
            guard now >= state.fuseEndsAt else { return }
            if let holder = state.holder {
                burst(on: holder, state: &state, now: now)
            } else if survivors(state).count <= 1 {
                // Nobody holds it (it cannot normally happen): never stall.
                finish(&state)
            } else {
                newPotato(&state, now: now, rng: &rng)
            }
        case .burst:
            guard now >= state.burstUntil else { return }
            if survivors(state).count <= 1 {
                finish(&state)
            } else {
                newPotato(&state, now: now, rng: &rng)
            }
        case .over:
            break
        }
    }

    static func playerLeft(_ playerId: String, state: inout State, now: Double, rng: inout OfflineRNG) {
        guard state.players.contains(where: { $0.id == playerId }), !state.away.contains(playerId) else { return }
        state.away.append(playerId)
        // Leaving while still in is a forfeit: out, in the order it happened.
        if !state.outOrder.contains(playerId) { state.outOrder.append(playerId) }
        guard state.phase != .over else { return }
        if survivors(state).count <= 1 {
            finish(&state)
            return
        }
        // The potato was in their hands: it jumps to a random survivor, same fuse.
        if state.phase == .passing, state.holder == playerId,
           let next = rng.pick(survivors(state)) {
            hand(&state, to: next, from: nil, rng: &rng)
        }
    }

    static func view(of state: State, for playerId: String?) -> PlayerView {
        let rows = state.players.map { player in
            Row(id: player.id, name: player.name, lives: state.lives[player.id] ?? 0,
                out: state.outOrder.contains(player.id), away: state.away.contains(player.id),
                holding: state.phase == .passing && state.holder == player.id)
        }
        var myTask: PuzzleView?
        if state.phase == .passing, let playerId, state.holder == playerId {
            myTask = PuzzleView(number: state.task.number, shapes: state.task.shapes,
                              solved: state.solved, lockedUntil: state.lockedUntil)
        }
        return PlayerView(
            phase: state.phase, round: state.round, pass: state.pass,
            holder: state.phase == .passing ? state.holder : nil,
            thrower: state.phase == .passing ? state.thrower : nil,
            rows: rows, myTask: myTask, burstOn: state.burstOn, burstUntil: state.burstUntil,
            winner: state.phase == .over ? winner(state) : nil,
            startingLives: startingLives
        )
    }

    static func isOver(_ state: State) -> Bool { state.phase == .over }

    /// Ranked by how many players each outlasted: the winner outlasted
    /// everyone, the first out nobody. Players still in share a rank.
    static func standings(_ state: State) -> [OfflineStanding] {
        OfflineStanding.ranked(state.players, score: { outlasted($0.id, state) }, detail: { player in
            var parts: [String] = []
            if state.away.contains(player.id) {
                parts.append("left")
            } else if state.outOrder.contains(player.id) {
                parts.append("out")
            } else {
                let lives = state.lives[player.id] ?? 0
                parts.append(lives == 1 ? "1 life left" : "\(lives) lives left")
            }
            let tosses = state.tosses[player.id] ?? 0
            if tosses > 0 { parts.append(tosses == 1 ? "1 throw" : "\(tosses) throws") }
            let fumbles = state.fumbles[player.id] ?? 0
            if fumbles > 0 { parts.append(fumbles == 1 ? "1 fumble" : "\(fumbles) fumbles") }
            return parts.joined(separator: " · ")
        })
    }

    // MARK: - Helpers

    /// Still in the match: lives left and still here.
    static func isIn(_ id: String, _ state: State) -> Bool {
        !state.outOrder.contains(id) && !state.away.contains(id) && (state.lives[id] ?? 0) > 0
    }

    /// Everyone still in, in seat order.
    static func survivors(_ state: State) -> [String] {
        state.players.map(\.id).filter { isIn($0, state) }
    }

    /// How many players `id` has outlasted.
    private static func outlasted(_ id: String, _ state: State) -> Int {
        if let index = state.outOrder.firstIndex(of: id) { return index }
        return state.outOrder.count
    }

    /// The last one standing, if there is exactly one.
    static func winner(_ state: State) -> String? {
        let left = survivors(state)
        return left.count == 1 ? left[0] : nil
    }

    /// A fresh potato with a fresh fuse, starting with a random survivor.
    private static func newPotato(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        state.round += 1
        state.phase = .passing
        state.burstOn = nil
        state.fuseEndsAt = now + rng.double(in: fuseRange)
        let holder = rng.pick(survivors(state))
        if let holder {
            hand(&state, to: holder, from: nil, rng: &rng)
        } else {
            state.holder = nil
            finish(&state)
        }
    }

    /// The potato lands with `id`, who gets a new task.
    private static func hand(_ state: inout State, to id: String, from thrower: String?, rng: inout OfflineRNG) {
        state.holder = id
        state.thrower = thrower
        state.pass += 1
        state.solved = false
        state.lockedUntil = 0
        state.task = newPuzzle(number: state.task.number + 1, rng: &rng)
    }

    /// It burst on `id`: a life gone, and out with the last one.
    private static func burst(on id: String, state: inout State, now: Double) {
        let lives = max(0, (state.lives[id] ?? 0) - 1)
        state.lives[id] = lives
        if lives == 0, !state.outOrder.contains(id) { state.outOrder.append(id) }
        state.burstOn = id
        state.holder = nil
        state.thrower = nil
        state.solved = false
        state.phase = .burst
        state.burstUntil = now + burstPause
    }

    private static func finish(_ state: inout State) {
        state.phase = .over
        state.holder = nil
        state.thrower = nil
        state.solved = false
    }

    /// Four shapes, three alike, the odd one somewhere random.
    static func newPuzzle(number: Int, rng: inout OfflineRNG) -> Puzzle {
        let common = rng.int(below: shapeKinds)
        var other = rng.int(below: shapeKinds - 1)
        if other >= common { other += 1 }
        let odd = rng.int(below: taskSize)
        let commonShape = Glyph(rawValue: common) ?? .circle
        let oddShape = Glyph(rawValue: other) ?? .square
        var shapes = Array(repeating: commonShape, count: taskSize)
        shapes[odd] = oddShape
        return Puzzle(number: number, shapes: shapes, odd: odd)
    }
}
