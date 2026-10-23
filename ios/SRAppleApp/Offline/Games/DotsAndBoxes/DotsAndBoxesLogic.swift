import Foundation

/// Dots and Boxes for two to five phones.
///
/// A grid of dots; players take turns drawing one line between two
/// neighbouring dots. Whoever draws the fourth side of a box claims it and
/// must draw again, so one good line can start a long run of boxes. When
/// every box is claimed the most boxes wins.
///
/// The board grows with the table so each player still gets a fair share of
/// boxes: 4 × 4 for two, 5 × 5 for three, and six rows of five for four or
/// five. A turn lasts thirty seconds; a player who lets it run out has a
/// random free line drawn for them (which may hand a box to the next player —
/// that is the price of dawdling).
///
/// Nothing is hidden in this game, so every player and every spectator sees
/// the same view. The host still checks every line: whose turn it is, that
/// the line is on the board and not yet drawn, and that the move was meant
/// for this turn and not one that has already gone.
enum DotsAndBoxesRules: OfflineGameRules {
    /// Seconds each turn lasts before a line is drawn for the player.
    static let turnSeconds: Double = 30
    /// How long the finished board stays up before the standings.
    static let resultPause: Double = 4

    static let info = OfflineGameInfo(
        id: "dots-and-boxes",
        title: "Dots and Boxes",
        blurb: "Draw lines between dots; close a box to claim it and go again.",
        category: .skill,
        minPlayers: 2,
        maxPlayers: 5,
        symbol: "square.grid.3x3",
        howToPlay: [
            "On your turn, tap near a gap between two dots to pick a line, then draw it.",
            "Draw the fourth side of a box to claim it — then you go again.",
            "Try not to draw a box's third side: the next player will take it.",
            "You have \(Int(turnSeconds)) seconds a turn, or a random line is drawn for you.",
            "When every box is claimed, the most boxes wins."
        ]
    )

    /// Rows and columns of BOXES for a table of `count` players.
    static func boardSize(players count: Int) -> (rows: Int, cols: Int) {
        switch count {
        case ...2: return (4, 4)
        case 3: return (5, 5)
        default: return (6, 5)
        }
    }

    // MARK: - State

    enum Phase: String, Codable, Equatable {
        /// Lines are being drawn.
        case playing
        /// Every box is claimed; the final board shows until `resultUntil`.
        case done
        /// The match is decided and the room shows the standings.
        case over
    }

    /// One line between two neighbouring dots.
    ///
    /// A horizontal line at (`row`, `col`) runs along the top of box
    /// (`row`, `col`) — `row` goes from 0 to `rows`, `col` from 0 to `cols − 1`.
    /// A vertical line at (`row`, `col`) runs down the left of box
    /// (`row`, `col`) — `row` from 0 to `rows − 1`, `col` from 0 to `cols`.
    struct Line: Codable, Equatable, Hashable {
        var horizontal: Bool
        var row: Int
        var col: Int
    }

    /// Who drew the last line, and what it won.
    struct Move: Codable, Equatable {
        let playerId: String
        let line: Line
        /// Boxes that line closed.
        let claimed: Int
        /// The clock drew it because the turn ran out.
        let timedOut: Bool
    }

    struct State: Codable, Equatable {
        var players: [OfflinePlayer]
        /// Players whose phones have left; their turns are skipped (until
        /// they come back with `.back`) and their boxes stay theirs.
        var away: [String] = []
        var rows: Int
        var cols: Int
        /// Horizontal lines, row by row: index `row * cols + col`.
        var hLines: [Bool]
        /// Vertical lines, row by row: index `row * (cols + 1) + col`.
        var vLines: [Bool]
        /// Each box's owner as a seat index (into `players`), or −1 while open.
        /// Index `row * cols + col`.
        var boxes: [Int]
        var phase: Phase = .playing
        /// Seat whose turn it is.
        var turn = 0
        /// Goes up with every line drawn (and every skipped turn), so a late
        /// tap meant for an earlier turn is refused rather than misapplied.
        var turnNumber = 1
        /// Host clock: when the current turn runs out.
        var turnEndsAt: Double
        var resultUntil: Double = 0
        var lastMove: Move?
        /// Turns each player let run out.
        var timeouts: [String: Int] = [:]
    }

    enum Action: Codable, Equatable {
        /// Draw `line`, on turn `turn` (the view's `turnNumber`).
        case draw(turn: Int, line: Line)
        /// A player marked away whose phone has come back takes their seat
        /// again. The view sends it by itself when it sees itself marked away
        /// (a view only reaches a phone that is connected).
        case back
    }

    // MARK: - What a player sees

    /// One player's row: name, seat (for the colour) and boxes so far.
    struct Seat: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        let seat: Int
        let boxes: Int
        let away: Bool
    }

    struct PlayerView: Codable, Equatable {
        let phase: Phase
        let rows: Int
        let cols: Int
        let hLines: [Bool]
        let vLines: [Bool]
        /// Owner seat per box, −1 while open.
        let boxes: [Int]
        let seats: [Seat]
        /// Whose turn it is while playing.
        let turnPlayer: String?
        let turnNumber: Int
        let turnEndsAt: Double
        let resultUntil: Double
        let lastMove: Move?
        /// The players with the most boxes, once every box is claimed.
        let champions: [String]
    }

    // MARK: - Rules

    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State {
        let size = boardSize(players: players.count)
        var state = State(
            players: players,
            rows: size.rows,
            cols: size.cols,
            hLines: Array(repeating: false, count: (size.rows + 1) * size.cols),
            vLines: Array(repeating: false, count: size.rows * (size.cols + 1)),
            boxes: Array(repeating: -1, count: size.rows * size.cols),
            turnEndsAt: now + turnSeconds
        )
        for player in players { state.timeouts[player.id] = 0 }
        return state
    }

    static func apply(_ action: Action, by playerId: String, to state: inout State, now: Double, rng: inout OfflineRNG) throws {
        guard let seat = state.players.firstIndex(where: { $0.id == playerId }) else {
            throw OfflineRefusal("You are not in this game.")
        }
        if case .back = action {
            guard state.phase == .playing else { throw OfflineRefusal("The game is over.") }
            guard let index = state.away.firstIndex(of: playerId) else {
                throw OfflineRefusal("You are already in this game.")
            }
            // Back in the turn order from the next turn on; their boxes were
            // always theirs.
            state.away.remove(at: index)
            return
        }
        guard !state.away.contains(playerId) else { throw OfflineRefusal("You have left this game.") }
        guard state.phase == .playing else { throw OfflineRefusal("The game is over.") }
        switch action {
        case .back:
            return
        case .draw(let turn, let line):
            guard turn == state.turnNumber else { throw OfflineRefusal("That move was for an earlier turn.") }
            guard seat == state.turn else {
                throw OfflineRefusal("It's \(state.players[state.turn].name)'s turn.")
            }
            guard let drawn = isDrawn(line, in: state) else { throw OfflineRefusal("That line is not on the board.") }
            guard !drawn else { throw OfflineRefusal("That line is already drawn.") }
            draw(line, seat: seat, in: &state, now: now, timedOut: false)
        }
    }

    static func tick(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        switch state.phase {
        case .playing:
            guard now >= state.turnEndsAt else { return }
            let player = state.players[state.turn]
            if state.away.contains(player.id) {
                // Should not happen (playerLeft moves the turn on), but never stall.
                passTurn(&state, now: now)
                return
            }
            let free = openLines(state)
            guard let line = rng.pick(free) else { return }
            state.timeouts[player.id, default: 0] += 1
            draw(line, seat: state.turn, in: &state, now: now, timedOut: true)
        case .done:
            if now >= state.resultUntil { state.phase = .over }
        case .over:
            break
        }
    }

    static func playerLeft(_ playerId: String, state: inout State, now: Double, rng: inout OfflineRNG) {
        guard let seat = state.players.firstIndex(where: { $0.id == playerId }),
              !state.away.contains(playerId) else { return }
        state.away.append(playerId)
        if state.phase == .playing, state.turn == seat { passTurn(&state, now: now) }
    }

    static func view(of state: State, for playerId: String?) -> PlayerView {
        // Dots and Boxes has no secrets: every phone sees the same board.
        let seats = state.players.enumerated().map { index, player in
            Seat(id: player.id, name: player.name, seat: index,
                 boxes: boxCount(state, seat: index), away: state.away.contains(player.id))
        }
        return PlayerView(
            phase: state.phase,
            rows: state.rows,
            cols: state.cols,
            hLines: state.hLines,
            vLines: state.vLines,
            boxes: state.boxes,
            seats: seats,
            turnPlayer: state.phase == .playing ? state.players[state.turn].id : nil,
            turnNumber: state.turnNumber,
            turnEndsAt: state.turnEndsAt,
            resultUntil: state.resultUntil,
            lastMove: state.lastMove,
            champions: state.phase == .playing ? [] : champions(state)
        )
    }

    static func isOver(_ state: State) -> Bool { state.phase == .over }

    static func standings(_ state: State) -> [OfflineStanding] {
        let seats = Dictionary(uniqueKeysWithValues: state.players.enumerated().map { ($0.element.id, $0.offset) })
        return OfflineStanding.ranked(state.players, score: { boxCount(state, seat: seats[$0.id] ?? -1) }, detail: { player in
            var parts: [String] = []
            let boxes = boxCount(state, seat: seats[player.id] ?? -1)
            parts.append(boxes == 1 ? "1 box" : "\(boxes) boxes")
            let timeouts = state.timeouts[player.id] ?? 0
            if timeouts > 0 { parts.append(timeouts == 1 ? "1 turn timed out" : "\(timeouts) turns timed out") }
            if state.away.contains(player.id) { parts.append("left") }
            return parts.joined(separator: " · ")
        })
    }

    // MARK: - The board

    /// Whether `line` is drawn, or nil when it is not on the board.
    static func isDrawn(_ line: Line, in state: State) -> Bool? {
        isDrawn(line, rows: state.rows, cols: state.cols, hLines: state.hLines, vLines: state.vLines)
    }

    /// The same question asked of the board's arrays — the view uses this too.
    static func isDrawn(_ line: Line, rows: Int, cols: Int, hLines: [Bool], vLines: [Bool]) -> Bool? {
        if line.horizontal {
            guard (0...rows).contains(line.row), (0..<cols).contains(line.col) else { return nil }
            let index = line.row * cols + line.col
            return hLines.indices.contains(index) ? hLines[index] : nil
        } else {
            guard (0..<rows).contains(line.row), (0...cols).contains(line.col) else { return nil }
            let index = line.row * (cols + 1) + line.col
            return vLines.indices.contains(index) ? vLines[index] : nil
        }
    }

    /// The four sides of box (`row`, `col`): top, bottom, left, right.
    static func sides(row: Int, col: Int) -> [Line] {
        [Line(horizontal: true, row: row, col: col),
         Line(horizontal: true, row: row + 1, col: col),
         Line(horizontal: false, row: row, col: col),
         Line(horizontal: false, row: row, col: col + 1)]
    }

    /// Every undrawn line, horizontals first, in a fixed order (so a random
    /// pick from the seeded generator is reproducible).
    static func openLines(_ state: State) -> [Line] {
        var out: [Line] = []
        for row in 0...state.rows {
            for col in 0..<state.cols where !state.hLines[row * state.cols + col] {
                out.append(Line(horizontal: true, row: row, col: col))
            }
        }
        for row in 0..<state.rows {
            for col in 0...state.cols where !state.vLines[row * (state.cols + 1) + col] {
                out.append(Line(horizontal: false, row: row, col: col))
            }
        }
        return out
    }

    /// Boxes held by `seat`.
    static func boxCount(_ state: State, seat: Int) -> Int {
        guard seat >= 0 else { return 0 }
        return state.boxes.filter { $0 == seat }.count
    }

    /// The most boxes (several on a tie).
    static func champions(_ state: State) -> [String] {
        let counts = state.players.indices.map { boxCount(state, seat: $0) }
        let top = counts.max() ?? 0
        guard top > 0 else { return [] }
        return state.players.indices.filter { counts[$0] == top }.map { state.players[$0].id }
    }

    // MARK: - Helpers

    /// Draw a checked line for `seat`: claim any box it closes (and go again),
    /// or hand the turn on.
    private static func draw(_ line: Line, seat: Int, in state: inout State, now: Double, timedOut: Bool) {
        if line.horizontal {
            state.hLines[line.row * state.cols + line.col] = true
        } else {
            state.vLines[line.row * (state.cols + 1) + line.col] = true
        }
        // The boxes either side of the line.
        var touching: [(Int, Int)] = []
        if line.horizontal {
            if line.row > 0 { touching.append((line.row - 1, line.col)) }
            if line.row < state.rows { touching.append((line.row, line.col)) }
        } else {
            if line.col > 0 { touching.append((line.row, line.col - 1)) }
            if line.col < state.cols { touching.append((line.row, line.col)) }
        }
        var claimed = 0
        for (row, col) in touching {
            let index = row * state.cols + col
            guard state.boxes[index] < 0 else { continue }
            let closed = sides(row: row, col: col).allSatisfy { isDrawn($0, in: state) == true }
            if closed {
                state.boxes[index] = seat
                claimed += 1
            }
        }
        state.lastMove = Move(playerId: state.players[seat].id, line: line, claimed: claimed, timedOut: timedOut)
        state.turnNumber += 1

        if !state.boxes.contains(-1) {
            state.phase = .done
            state.resultUntil = now + resultPause
            return
        }
        if claimed > 0 {
            state.turnEndsAt = now + turnSeconds
        } else {
            state.turn = nextSeat(after: state.turn, in: state)
            state.turnEndsAt = now + turnSeconds
        }
    }

    /// Hand the turn to the next player still here, without drawing.
    private static func passTurn(_ state: inout State, now: Double) {
        state.turn = nextSeat(after: state.turn, in: state)
        state.turnNumber += 1
        state.turnEndsAt = now + turnSeconds
    }

    /// The next seat clockwise whose player is still here (or `seat` itself
    /// when nobody else is).
    private static func nextSeat(after seat: Int, in state: State) -> Int {
        let count = state.players.count
        guard count > 0 else { return 0 }
        for step in 1...count {
            let next = (seat + step) % count
            if !state.away.contains(state.players[next].id) { return next }
        }
        return seat
    }
}
