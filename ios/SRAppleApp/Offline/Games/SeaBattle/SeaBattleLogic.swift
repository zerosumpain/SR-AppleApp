import Foundation

/// Sea Battle: battleships for two to five phones, everyone against everyone.
///
/// Each player hides a fleet of four ships — lengths 4, 3, 2 and 2 — on their
/// own 8 × 8 grid. The host deals everyone a random layout at the start, so
/// there is always a legal fleet; players may move and turn ships, ask for a
/// fresh shuffle, and say Ready. When everyone is ready, or the minute for
/// placing runs out, the shooting starts.
///
/// On your turn you fire at any square of any opponent who is still afloat.
/// A hit earns another shot, up to three in one turn; a miss passes the turn
/// on. Sinking a ship announces it and shows its squares to everyone. A fleet
/// with every ship sunk is out, and the last fleet afloat wins.
///
/// What stays secret: where a player's ships are, except the squares that
/// have been hit and the ships that have sunk. Every phone sees every shot
/// on every grid, but only your own phone ever holds your layout.
///
/// A turn lasts 30 seconds; if it runs out, the host fires one shot at random
/// for that player and passes the turn on, so an idle phone cannot stall the
/// game. A player who leaves scuttles their fleet: they are out, and their
/// ships are never revealed. If their phone comes back while the battle is
/// still on, the fleet sails again where it was.
enum SeaBattleRules: OfflineGameRules {
    /// The grid is `size` × `size`; square `index` is row `index / size`, column `index % size`.
    static let size = 8
    /// The fleet, longest first. Every player has the same one.
    static let fleetLengths = [4, 3, 2, 2]
    /// The ships' names, in the same order as `fleetLengths`.
    static let fleetNames = ["Battleship", "Cruiser", "Destroyer", "Patrol boat"]
    /// Shots in one turn: a hit earns another, up to this many.
    static let maxShots = 3
    /// Seconds to place the fleet before the shooting starts anyway.
    static let placeSeconds: Double = 60
    /// Seconds for each shot before the host fires one at random.
    static let turnSeconds: Double = 30
    /// Seconds the final grids stay up before the standings.
    static let donePause: Double = 5

    static let info = OfflineGameInfo(
        id: "sea-battle",
        title: "Sea Battle",
        blurb: "Hide your fleet, then hunt everyone else's — last fleet afloat wins.",
        category: .skill,
        minPlayers: 2,
        maxPlayers: 5,
        symbol: "ferry.fill",
        howToPlay: [
            "Place your four ships on your own grid — tap a ship, then a square; Rotate turns it.",
            "Shuffle gives you a random layout. Say Ready when you are happy.",
            "On your turn, pick an opponent's grid and fire at one square.",
            "A hit earns another shot, up to \(maxShots) in a turn. A miss passes the turn on.",
            "Sink every ship in a fleet to knock that player out. Last fleet afloat wins."
        ]
    )

    // MARK: - State

    enum Phase: String, Codable, Equatable {
        /// Everyone is placing their fleet until `placeEndsAt`.
        case placing
        /// Turns of shooting.
        case firing
        /// One fleet is left; the final grids show until `doneUntil`.
        case done
        /// The match is over; the room shows the standings.
        case over
    }

    /// Where one ship lies: its bow square, and whether it runs across
    /// (to the right) or down. The ship's length comes from its place in
    /// the fleet.
    struct Placement: Codable, Equatable {
        var bow: Int
        var across: Bool
    }

    /// One shot that landed on a grid.
    struct Shot: Codable, Equatable {
        let cell: Int
        let hit: Bool
    }

    /// A ship that has gone down: shown to everyone.
    struct Sunk: Codable, Equatable {
        let name: String
        let cells: [Int]
    }

    /// The most recent shot, for the "Ben hit Ann's cruiser" line.
    struct LastShot: Codable, Equatable {
        let shooter: String
        let target: String
        let cell: Int
        let hit: Bool
        /// The ship this shot sank, if it sank one.
        let sunk: String?
        /// The shot sank the target's last ship.
        let knockedOut: Bool
        /// The shooter's time ran out, so the host fired for them.
        let timedOut: Bool
    }

    struct State: Codable, Equatable {
        var players: [OfflinePlayer]
        /// Players whose phones have left; their fleets are scuttled.
        var away: [String] = []
        var phase: Phase = .placing
        /// When placing ends, host clock.
        var placeEndsAt: Double = 0
        /// Each player's fleet, in `fleetLengths` order. The secret.
        var fleets: [String: [Placement]] = [:]
        /// Players who have said Ready, in the order they did.
        var ready: [String] = []
        /// Shots fired AT each player's grid, in the order they landed.
        var shots: [String: [Shot]] = [:]
        /// Whose turn it is while firing.
        var turnPlayer: String?
        /// Counts up with every turn, so a late shot from an old turn is refused.
        var turnNumber = 0
        /// Shots already fired this turn.
        var shotsThisTurn = 0
        /// When the current shot's time runs out, host clock.
        var turnEndsAt: Double = 0
        /// Players whose fleets are gone (sunk or scuttled), first out first.
        var out: [String] = []
        var lastShot: LastShot?
        var winner: String?
        var doneUntil: Double = 0
        /// Shots each player has fired, and how many hit.
        var fired: [String: Int] = [:]
        var hits: [String: Int] = [:]
        /// Ships each player has sunk.
        var sank: [String: Int] = [:]
    }

    enum Action: Codable, Equatable {
        /// Replace my fleet's layout while placing.
        case place(ships: [Placement])
        /// Ask the host for a random layout while placing.
        case shuffle
        /// Lock my layout in.
        case ready
        /// Fire at `cell` on `target`'s grid, on turn `turn`.
        case fire(turn: Int, target: String, cell: Int)
        /// A player marked away whose phone has come back takes their seat
        /// again, fleet and all — it was never revealed, only set aside. The
        /// view sends it by itself when it sees itself marked away (a view
        /// only reaches a phone that is connected).
        case back
    }

    // MARK: - What a player sees

    /// One player's grid as anybody may see it: the shots on it, and the
    /// ships that have sunk. Never the ships still afloat.
    struct Board: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        let seat: Int
        let away: Bool
        /// The whole fleet is gone (sunk or scuttled).
        let out: Bool
        /// Has said Ready (placing only).
        let ready: Bool
        let shots: [Shot]
        let sunk: [Sunk]
        let shipsLeft: Int
    }

    struct PlayerView: Codable, Equatable {
        let phase: Phase
        let size: Int
        let fleetLengths: [Int]
        let fleetNames: [String]
        let maxShots: Int
        let placeEndsAt: Double
        let turnPlayer: String?
        let turnNumber: Int
        let shotsThisTurn: Int
        let turnEndsAt: Double
        let boards: [Board]
        /// My own layout — nil for a spectator.
        let myFleet: [Placement]?
        let lastShot: LastShot?
        let winner: String?
        let doneUntil: Double
    }

    // MARK: - Rules

    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State {
        var state = State(players: players)
        state.placeEndsAt = now + placeSeconds
        for player in players {
            state.fleets[player.id] = randomFleet(&rng)
            state.shots[player.id] = []
        }
        return state
    }

    static func apply(_ action: Action, by playerId: String, to state: inout State, now: Double, rng: inout OfflineRNG) throws {
        guard state.players.contains(where: { $0.id == playerId }) else {
            throw OfflineRefusal("You are not in this game.")
        }
        if case .back = action {
            try comeBack(playerId, in: &state)
            return
        }
        guard !state.away.contains(playerId) else { throw OfflineRefusal("You have left this game.") }

        switch action {
        case .back:
            return

        case .place(let ships):
            try checkPlacing(state, playerId)
            guard isValidFleet(ships) else {
                throw OfflineRefusal("Ships must stay on the grid and must not overlap.")
            }
            state.fleets[playerId] = ships

        case .shuffle:
            try checkPlacing(state, playerId)
            state.fleets[playerId] = randomFleet(&rng)

        case .ready:
            try checkPlacing(state, playerId)
            state.ready.append(playerId)
            if everyoneReady(state) { beginFiring(&state, now: now, rng: &rng) }

        case .fire(let turn, let target, let cell):
            guard state.phase == .firing else {
                throw OfflineRefusal(state.phase == .placing ? "The shooting hasn't started yet." : "The battle is over.")
            }
            guard !state.out.contains(playerId) else { throw OfflineRefusal("Your fleet has been sunk.") }
            guard state.turnPlayer == playerId else {
                throw OfflineRefusal("It's \(name(of: state.turnPlayer, in: state))'s turn.")
            }
            guard turn == state.turnNumber else { throw OfflineRefusal("That shot was for an earlier turn.") }
            guard target != playerId else { throw OfflineRefusal("You can't fire at your own fleet.") }
            guard state.players.contains(where: { $0.id == target }) else {
                throw OfflineRefusal("There is no such fleet.")
            }
            guard !state.out.contains(target) else {
                throw OfflineRefusal("\(name(of: target, in: state))'s fleet is already gone.")
            }
            guard cell >= 0, cell < size * size else { throw OfflineRefusal("That square is off the grid.") }
            guard !(state.shots[target] ?? []).contains(where: { $0.cell == cell }) else {
                throw OfflineRefusal("\(coordinate(cell)) on \(name(of: target, in: state))'s grid has already been fired at.")
            }
            fire(&state, shooter: playerId, target: target, cell: cell, timedOut: false, now: now, rng: &rng)
        }
    }

    static func tick(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        switch state.phase {
        case .placing:
            if now >= state.placeEndsAt { beginFiring(&state, now: now, rng: &rng) }
        case .firing:
            guard now >= state.turnEndsAt, let shooter = state.turnPlayer else { return }
            // Time is up: one shot at random, and the turn passes on even if it hits.
            let targets = state.players.map(\.id).filter { $0 != shooter && !state.out.contains($0) }
            guard let target = rng.pick(targets) else { return }
            let taken = Set((state.shots[target] ?? []).map(\.cell))
            let open = (0..<(size * size)).filter { !taken.contains($0) }
            guard let cell = rng.pick(open) else { return }
            fire(&state, shooter: shooter, target: target, cell: cell, timedOut: true, now: now, rng: &rng)
        case .done:
            if now >= state.doneUntil { state.phase = .over }
        case .over:
            break
        }
    }

    static func playerLeft(_ playerId: String, state: inout State, now: Double, rng: inout OfflineRNG) {
        guard state.players.contains(where: { $0.id == playerId }), !state.away.contains(playerId) else { return }
        state.away.append(playerId)
        switch state.phase {
        case .placing:
            if !state.out.contains(playerId) { state.out.append(playerId) }
            if survivors(state).count <= 1 {
                finish(&state, now: now)
            } else if everyoneReady(state) {
                beginFiring(&state, now: now, rng: &rng)
            }
        case .firing:
            guard !state.out.contains(playerId) else { return }
            state.out.append(playerId)
            if survivors(state).count <= 1 {
                finish(&state, now: now)
            } else if state.turnPlayer == playerId {
                nextTurn(&state, now: now)
            }
        case .done, .over:
            break
        }
    }

    static func view(of state: State, for playerId: String?) -> PlayerView {
        let boards = state.players.enumerated().map { seat, player -> Board in
            let shots = state.shots[player.id] ?? []
            let sunk = sunkShips(of: player.id, in: state)
            let isOut = state.out.contains(player.id)
            return Board(
                id: player.id, name: player.name, seat: seat,
                away: state.away.contains(player.id), out: isOut,
                ready: state.ready.contains(player.id),
                shots: shots, sunk: sunk,
                shipsLeft: isOut ? 0 : fleetLengths.count - sunk.count
            )
        }
        let mine = playerId.flatMap { id in state.players.contains { $0.id == id } ? state.fleets[id] : nil }
        return PlayerView(
            phase: state.phase, size: size, fleetLengths: fleetLengths, fleetNames: fleetNames,
            maxShots: maxShots, placeEndsAt: state.placeEndsAt,
            turnPlayer: state.phase == .firing ? state.turnPlayer : nil,
            turnNumber: state.turnNumber, shotsThisTurn: state.shotsThisTurn, turnEndsAt: state.turnEndsAt,
            boards: boards, myFleet: mine, lastShot: state.lastShot,
            winner: state.winner, doneUntil: state.doneUntil
        )
    }

    static func isOver(_ state: State) -> Bool { state.phase == .over }

    /// The winner first, then everyone else by how long their fleet lasted.
    /// The score is how many fleets went down before yours.
    static func standings(_ state: State) -> [OfflineStanding] {
        OfflineStanding.ranked(state.players, score: { player in
            state.out.firstIndex(of: player.id) ?? state.out.count
        }, detail: { player in
            var parts: [String] = []
            let fired = state.fired[player.id] ?? 0
            let hits = state.hits[player.id] ?? 0
            parts.append(fired == 1 ? "\(hits) of 1 shot hit" : "\(hits) of \(fired) shots hit")
            let sank = state.sank[player.id] ?? 0
            if sank > 0 { parts.append(sank == 1 ? "sank 1 ship" : "sank \(sank) ships") }
            if state.away.contains(player.id) { parts.append("left") }
            return parts.joined(separator: " · ")
        })
    }

    // MARK: - Geometry (shared with the view)

    /// The squares a ship of `length` covers from `bow`, or nil if any of it
    /// would leave the grid.
    static func cells(bow: Int, across: Bool, length: Int) -> [Int]? {
        guard bow >= 0, bow < size * size, length > 0 else { return nil }
        let row = bow / size
        let col = bow % size
        if across {
            guard col + length <= size else { return nil }
        } else {
            guard row + length <= size else { return nil }
        }
        return (0..<length).map { across ? bow + $0 : bow + $0 * size }
    }

    /// The squares of ship `index` in a layout, or nil if it is off the grid.
    static func cells(of placement: Placement, ship index: Int) -> [Int]? {
        guard fleetLengths.indices.contains(index) else { return nil }
        return cells(bow: placement.bow, across: placement.across, length: fleetLengths[index])
    }

    /// A whole layout: one placement per ship, all on the grid, none overlapping.
    static func isValidFleet(_ ships: [Placement]) -> Bool {
        guard ships.count == fleetLengths.count else { return false }
        var used = Set<Int>()
        for (index, ship) in ships.enumerated() {
            guard let squares = cells(of: ship, ship: index) else { return false }
            for square in squares {
                guard used.insert(square).inserted else { return false }
            }
        }
        return true
    }

    /// "A1" for the top-left square, "H8" for the bottom-right.
    static func coordinate(_ cell: Int) -> String {
        let letters = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L"]
        let row = cell / size
        let col = cell % size
        let letter = letters.indices.contains(row) ? letters[row] : "?"
        return "\(letter)\(col + 1)"
    }

    /// A random legal layout, longest ship first.
    static func randomFleet(_ rng: inout OfflineRNG) -> [Placement] {
        // Retry the whole layout if a ship has nowhere to go; with 11 squares
        // of ship on a 64-square grid that essentially never happens.
        while true {
            var ships: [Placement] = []
            var used = Set<Int>()
            var stuck = false
            for length in fleetLengths {
                var options: [Placement] = []
                for bow in 0..<(size * size) {
                    for across in [true, false] {
                        if let squares = cells(bow: bow, across: across, length: length),
                           squares.allSatisfy({ !used.contains($0) }) {
                            options.append(Placement(bow: bow, across: across))
                        }
                    }
                }
                guard let choice = rng.pick(options) else { stuck = true; break }
                ships.append(choice)
                for square in cells(bow: choice.bow, across: choice.across, length: length) ?? [] {
                    used.insert(square)
                }
            }
            if !stuck { return ships }
        }
    }

    // MARK: - Helpers

    /// A player who left is back. Their fleet sails again (as it was, Ready
    /// or not) unless every ship in it had already been sunk.
    private static func comeBack(_ playerId: String, in state: inout State) throws {
        guard state.phase == .placing || state.phase == .firing else {
            throw OfflineRefusal("The battle is over.")
        }
        guard let index = state.away.firstIndex(of: playerId) else {
            throw OfflineRefusal("You are already in this battle.")
        }
        state.away.remove(at: index)
        if sunkShips(of: playerId, in: state).count < fleetLengths.count {
            state.out.removeAll { $0 == playerId }
        }
    }

    private static func checkPlacing(_ state: State, _ playerId: String) throws {
        guard state.phase == .placing else { throw OfflineRefusal("The fleets are already at sea.") }
        guard !state.ready.contains(playerId) else { throw OfflineRefusal("You have already said Ready.") }
    }

    private static func name(of id: String?, in state: State) -> String {
        guard let id else { return "someone else" }
        return state.players.first { $0.id == id }?.name ?? "someone else"
    }

    /// Players whose fleets are still afloat, in seat order.
    private static func survivors(_ state: State) -> [String] {
        state.players.map(\.id).filter { !state.out.contains($0) }
    }

    private static func everyoneReady(_ state: State) -> Bool {
        state.players.allSatisfy { state.away.contains($0.id) || state.ready.contains($0.id) }
    }

    /// The ships `playerId` has lost, in fleet order.
    static func sunkShips(of playerId: String, in state: State) -> [Sunk] {
        guard let fleet = state.fleets[playerId] else { return [] }
        let hitCells = Set((state.shots[playerId] ?? []).filter(\.hit).map(\.cell))
        var out: [Sunk] = []
        for (index, ship) in fleet.enumerated() {
            guard let squares = cells(of: ship, ship: index), squares.allSatisfy({ hitCells.contains($0) }) else { continue }
            out.append(Sunk(name: fleetNames[index], cells: squares))
        }
        return out
    }

    /// Placing is over: the first shooter is drawn at random from those still afloat.
    private static func beginFiring(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        guard state.phase == .placing else { return }
        let afloat = survivors(state)
        if afloat.count <= 1 {
            finish(&state, now: now)
            return
        }
        state.phase = .firing
        state.turnPlayer = rng.pick(afloat)
        state.turnNumber = 1
        state.shotsThisTurn = 0
        state.turnEndsAt = now + turnSeconds
    }

    /// One shot lands. A hit (with shots to spare) keeps the turn; anything
    /// else passes it on. The last fleet afloat ends the battle.
    private static func fire(_ state: inout State, shooter: String, target: String, cell: Int,
                             timedOut: Bool, now: Double, rng: inout OfflineRNG) {
        let fleet = state.fleets[target] ?? []
        var hitShip: Int?
        for (index, ship) in fleet.enumerated() where (cells(of: ship, ship: index) ?? []).contains(cell) {
            hitShip = index
        }
        let hit = hitShip != nil
        let sunkBefore = sunkShips(of: target, in: state).count
        state.shots[target, default: []].append(Shot(cell: cell, hit: hit))
        state.fired[shooter, default: 0] += 1
        if hit { state.hits[shooter, default: 0] += 1 }

        var sunkName: String?
        var knockedOut = false
        let sunkNow = sunkShips(of: target, in: state)
        if sunkNow.count > sunkBefore, let index = hitShip {
            sunkName = fleetNames[index]
            state.sank[shooter, default: 0] += 1
            if sunkNow.count == fleetLengths.count {
                knockedOut = true
                if !state.out.contains(target) { state.out.append(target) }
            }
        }
        state.lastShot = LastShot(shooter: shooter, target: target, cell: cell, hit: hit,
                                  sunk: sunkName, knockedOut: knockedOut, timedOut: timedOut)
        state.shotsThisTurn += 1

        if survivors(state).count <= 1 {
            finish(&state, now: now)
        } else if hit && !timedOut && state.shotsThisTurn < maxShots {
            state.turnEndsAt = now + turnSeconds
        } else {
            nextTurn(&state, now: now)
        }
    }

    /// The next fleet afloat after the current shooter, in seat order.
    private static func nextTurn(_ state: inout State, now: Double) {
        let ids = state.players.map(\.id)
        let start = state.turnPlayer.flatMap { ids.firstIndex(of: $0) } ?? -1
        var next: String?
        for step in 1...ids.count {
            let candidate = ids[(start + step + ids.count) % ids.count]
            if !state.out.contains(candidate) {
                next = candidate
                break
            }
        }
        state.turnPlayer = next
        state.turnNumber += 1
        state.shotsThisTurn = 0
        state.turnEndsAt = now + turnSeconds
    }

    private static func finish(_ state: inout State, now: Double) {
        state.winner = survivors(state).count == 1 ? survivors(state).first : nil
        state.turnPlayer = nil
        state.phase = .done
        state.doneUntil = now + donePause
    }
}
