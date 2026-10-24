import Foundation

/// Four in a Row for two to four phones.
///
/// Players take turns dropping a disc into a column; it falls to the lowest
/// free space. The first to line up four of their own discs — across, up and
/// down, or on a diagonal — wins. A full board with no line is a draw.
///
/// The board grows with the table: the classic 7 columns by 6 rows for two,
/// and 9 by 7 for three or four, so a crowded table still has room to build a
/// line. Who goes first is drawn from the seeded generator, so Play again
/// does not always hand the host the opening move.
///
/// A turn lasts thirty seconds; a player who lets it run out has a disc
/// dropped for them in a random column that still has room. A player who
/// leaves keeps their discs on the board, and their turns are skipped until
/// their phone comes back; if only one player is left, they win by default.
///
/// Nothing is hidden in this game, so every player and every spectator sees
/// the same view. The host still checks every drop: whose turn it is, that
/// the column is on the board and has room, and that the move was meant for
/// this turn and not one that has already gone.
enum FourInARowRules: OfflineGameRules {
    /// Seconds each turn lasts before a disc is dropped for the player.
    static let turnSeconds: Double = 30
    /// How long the finished board stays up before the standings.
    static let resultPause: Double = 4
    /// Discs in a line that win.
    static let lineLength = 4

    static let info = OfflineGameInfo(
        id: "four-in-a-row",
        title: "Four in a Row",
        blurb: "Drop discs into the columns; the first to line up four wins.",
        category: .skill,
        minPlayers: 2,
        maxPlayers: 4,
        symbol: "circle.grid.3x3.fill",
        howToPlay: [
            "On your turn, tap a column to pick it, then tap Drop (or the same column again).",
            "Your disc falls to the lowest free space in that column.",
            "Line up four of your discs across, up and down, or diagonally to win.",
            "Two players use a 7 × 6 board; three or four use a bigger 9 × 7 one.",
            "You have \(Int(turnSeconds)) seconds a turn, or a disc is dropped for you at random.",
            "If the board fills up with no line of four, it's a draw."
        ]
    )

    /// Columns and rows of the board for a table of `count` players.
    static func boardSize(players count: Int) -> (cols: Int, rows: Int) {
        count <= 2 ? (7, 6) : (9, 7)
    }

    // MARK: - State

    enum Phase: String, Codable, Equatable {
        /// Discs are being dropped.
        case playing
        /// Somebody has four in a row, or the board is full; the final board
        /// shows until `resultUntil`.
        case done
        /// The match is decided and the room shows the standings.
        case over
    }

    /// How a finished match ended.
    enum Ending: String, Codable, Equatable {
        /// `winner` lined up four.
        case line
        /// The board filled with no line.
        case draw
        /// Everybody else left, so `winner` won by default.
        case forfeit
    }

    /// The last disc dropped, so every screen can mark it.
    struct Move: Codable, Equatable {
        let playerId: String
        let column: Int
        /// The row it landed in (0 is the top row).
        let row: Int
        /// The clock dropped it because the turn ran out.
        let timedOut: Bool
    }

    struct State: Codable, Equatable {
        var players: [OfflinePlayer]
        /// Players whose phones have left; their turns are skipped (until
        /// they come back with `.back`) and their discs stay on the board.
        var away: [String] = []
        var cols: Int
        var rows: Int
        /// Each space's owner as a seat index (into `players`), or −1 while
        /// empty. Row by row from the top: index `row * cols + col`, so the
        /// bottom row is `rows − 1`.
        var grid: [Int]
        var phase: Phase = .playing
        /// Seat whose turn it is.
        var turn: Int
        /// Goes up with every disc dropped (and every skipped turn), so a late
        /// tap meant for an earlier turn is refused rather than misapplied.
        var turnNumber = 1
        /// Host clock: when the current turn runs out.
        var turnEndsAt: Double
        var resultUntil: Double = 0
        var lastMove: Move?
        var ending: Ending?
        /// The winner's id, for a line or a forfeit.
        var winner: String?
        /// Grid indexes of the winning line (every disc in it, which can be
        /// more than four), for the screen to ring.
        var winningCells: [Int] = []
        /// Turns each player let run out.
        var timeouts: [String: Int] = [:]
    }

    enum Action: Codable, Equatable {
        /// Drop a disc in `column` (0 is the left), on turn `turn` (the
        /// view's `turnNumber`).
        case drop(turn: Int, column: Int)
        /// A player marked away whose phone has come back takes their seat
        /// again. The view sends it by itself when it sees itself marked away
        /// (a view only reaches a phone that is connected).
        case back
    }

    // MARK: - What a player sees

    /// One player's row: name, seat (for the colour and the marker) and
    /// whether they have left.
    struct Seat: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        let seat: Int
        let away: Bool
    }

    struct PlayerView: Codable, Equatable {
        let phase: Phase
        let cols: Int
        let rows: Int
        /// Owner seat per space, −1 while empty; `row * cols + col`, top row first.
        let grid: [Int]
        let seats: [Seat]
        /// Whose turn it is while playing.
        let turnPlayer: String?
        let turnNumber: Int
        let turnEndsAt: Double
        let lastMove: Move?
        let ending: Ending?
        let winner: String?
        let winningCells: [Int]
    }

    // MARK: - Rules

    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State {
        let size = boardSize(players: players.count)
        var state = State(
            players: players,
            cols: size.cols,
            rows: size.rows,
            grid: Array(repeating: -1, count: size.cols * size.rows),
            turn: players.isEmpty ? 0 : rng.int(below: players.count),
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
            // Back in the turn order from the next turn on; their discs never left.
            state.away.remove(at: index)
            return
        }
        guard !state.away.contains(playerId) else { throw OfflineRefusal("You have left this game.") }
        guard state.phase == .playing else { throw OfflineRefusal("The game is over.") }
        switch action {
        case .back:
            return
        case .drop(let turn, let column):
            guard turn == state.turnNumber else { throw OfflineRefusal("That move was for an earlier turn.") }
            guard seat == state.turn else {
                throw OfflineRefusal("It's \(state.players[state.turn].name)'s turn.")
            }
            guard (0..<state.cols).contains(column) else { throw OfflineRefusal("That column is not on the board.") }
            guard landingRow(column: column, in: state) != nil else { throw OfflineRefusal("That column is full.") }
            drop(column: column, seat: seat, in: &state, now: now, timedOut: false)
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
            guard let column = rng.pick(openColumns(state)) else { return }
            state.timeouts[player.id, default: 0] += 1
            drop(column: column, seat: state.turn, in: &state, now: now, timedOut: true)
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
        guard state.phase == .playing else { return }
        let here = state.players.filter { !state.away.contains($0.id) }
        if here.count <= 1 {
            // Nobody left to play against: the one still here wins by default.
            state.ending = .forfeit
            state.winner = here.first?.id
            state.winningCells = []
            state.phase = .done
            state.resultUntil = now + resultPause
            return
        }
        if state.turn == seat { passTurn(&state, now: now) }
    }

    static func view(of state: State, for playerId: String?) -> PlayerView {
        // Four in a Row has no secrets: every phone sees the same board.
        let seats = state.players.enumerated().map { index, player in
            Seat(id: player.id, name: player.name, seat: index, away: state.away.contains(player.id))
        }
        return PlayerView(
            phase: state.phase,
            cols: state.cols,
            rows: state.rows,
            grid: state.grid,
            seats: seats,
            turnPlayer: state.phase == .playing ? state.players[state.turn].id : nil,
            turnNumber: state.turnNumber,
            turnEndsAt: state.turnEndsAt,
            lastMove: state.lastMove,
            ending: state.ending,
            winner: state.winner,
            winningCells: state.winningCells
        )
    }

    static func isOver(_ state: State) -> Bool { state.phase == .over }

    static func standings(_ state: State) -> [OfflineStanding] {
        let seats = Dictionary(uniqueKeysWithValues: state.players.enumerated().map { ($0.element.id, $0.offset) })
        return OfflineStanding.ranked(state.players, score: { player in
            // A win is worth 2; staying to the end 1; leaving 0 — so the
            // table puts the winner first and anyone who left last.
            if player.id == state.winner { return 2 }
            return state.away.contains(player.id) ? 0 : 1
        }, detail: { player in
            var parts: [String] = []
            if player.id == state.winner {
                parts.append(state.ending == .forfeit ? "won by default" : "four in a row")
            } else if state.ending == .draw {
                parts.append("draw")
            }
            let discs = discCount(state, seat: seats[player.id] ?? -1)
            parts.append(discs == 1 ? "1 disc" : "\(discs) discs")
            let timeouts = state.timeouts[player.id] ?? 0
            if timeouts > 0 { parts.append(timeouts == 1 ? "1 turn timed out" : "\(timeouts) turns timed out") }
            if state.away.contains(player.id) { parts.append("left") }
            return parts.joined(separator: " · ")
        })
    }

    // MARK: - The board

    /// The row a disc dropped into `column` would land in, or nil when the
    /// column is full or not on the board.
    static func landingRow(column: Int, in state: State) -> Int? {
        landingRow(column: column, cols: state.cols, rows: state.rows, grid: state.grid)
    }

    /// The same question asked of the board's array — the view uses this too.
    static func landingRow(column: Int, cols: Int, rows: Int, grid: [Int]) -> Int? {
        guard (0..<cols).contains(column), grid.count == cols * rows else { return nil }
        for row in stride(from: rows - 1, through: 0, by: -1) where grid[row * cols + column] < 0 {
            return row
        }
        return nil
    }

    /// Every column with room, left to right (a fixed order, so a random pick
    /// from the seeded generator is reproducible).
    static func openColumns(_ state: State) -> [Int] {
        (0..<state.cols).filter { landingRow(column: $0, in: state) != nil }
    }

    /// Discs dropped by `seat`.
    static func discCount(_ state: State, seat: Int) -> Int {
        guard seat >= 0 else { return 0 }
        return state.grid.filter { $0 == seat }.count
    }

    /// Every space in the line(s) of `lineLength` or more through (`row`,
    /// `col`) that share its owner, as grid indexes in ascending order; empty
    /// when there is no such line.
    static func winningLine(row: Int, col: Int, cols: Int, rows: Int, grid: [Int]) -> [Int] {
        guard (0..<rows).contains(row), (0..<cols).contains(col), grid.count == cols * rows else { return [] }
        let owner = grid[row * cols + col]
        guard owner >= 0 else { return [] }
        var cells: [Int] = []
        // Across, up and down, and the two diagonals.
        for (dr, dc) in [(0, 1), (1, 0), (1, 1), (1, -1)] {
            var run = [row * cols + col]
            for sign in [1, -1] {
                var r = row + dr * sign
                var c = col + dc * sign
                while (0..<rows).contains(r), (0..<cols).contains(c), grid[r * cols + c] == owner {
                    run.append(r * cols + c)
                    r += dr * sign
                    c += dc * sign
                }
            }
            if run.count >= lineLength { cells.append(contentsOf: run) }
        }
        return Array(Set(cells)).sorted()
    }

    // MARK: - Helpers

    /// Drop a checked disc for `seat`: end the match on a line or a full
    /// board, or hand the turn on.
    private static func drop(column: Int, seat: Int, in state: inout State, now: Double, timedOut: Bool) {
        guard let row = landingRow(column: column, in: state) else { return }
        state.grid[row * state.cols + column] = seat
        state.lastMove = Move(playerId: state.players[seat].id, column: column, row: row, timedOut: timedOut)
        state.turnNumber += 1

        let line = winningLine(row: row, col: column, cols: state.cols, rows: state.rows, grid: state.grid)
        if !line.isEmpty {
            state.ending = .line
            state.winner = state.players[seat].id
            state.winningCells = line
            state.phase = .done
            state.resultUntil = now + resultPause
            return
        }
        if !state.grid.contains(-1) {
            state.ending = .draw
            state.phase = .done
            state.resultUntil = now + resultPause
            return
        }
        state.turn = nextSeat(after: state.turn, in: state)
        state.turnEndsAt = now + turnSeconds
    }

    /// Hand the turn to the next player still here, without dropping.
    private static func passTurn(_ state: inout State, now: Double) {
        state.turn = nextSeat(after: state.turn, in: state)
        state.turnNumber += 1
        state.turnEndsAt = now + turnSeconds
    }

    /// The next seat round the table whose player is still here (or `seat`
    /// itself when nobody else is).
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
