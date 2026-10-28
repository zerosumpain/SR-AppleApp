import Foundation

/// Four in a Row's computer player, for solo play and spare seats.
///
/// It looks one move ahead and no further: it takes a winning drop, blocks a
/// drop that would win for somebody else, will not put a disc where the next
/// player could win straight on top of it, and otherwise leans towards the
/// middle columns, where most lines run, with a little randomness so no two
/// games go the same way. Enough to punish a careless move; easy to beat by
/// setting up two threats at once.
extension FourInARowRules: OfflineBotRules {
    static func botActions(_ state: State, for playerId: String, rng: inout OfflineRNG) -> [Action] {
        guard state.phase == .playing,
              let seat = state.players.firstIndex(where: { $0.id == playerId }) else { return [] }
        if state.away.contains(playerId) { return [.back] }
        guard seat == state.turn else { return [] }
        return botColumns(state, seat: seat, rng: &rng).map { .drop(turn: state.turnNumber, column: $0) }
    }

    /// Every open column, best first, for `seat`.
    static func botColumns(_ state: State, seat: Int, rng: inout OfflineRNG) -> [Int] {
        let rivals = state.players.indices.filter { $0 != seat && !state.away.contains(state.players[$0].id) }
        let centre = Double(state.cols - 1) / 2
        let scored = openColumns(state).map { column -> (column: Int, score: Double) in
            var score = -abs(Double(column) - centre) * 3 + rng.double(in: 0...2.5)
            if wins(column: column, seat: seat, in: state) { score += 1_000 }
            if rivals.contains(where: { wins(column: column, seat: $0, in: state) }) { score += 500 }
            if handsOver(column: column, seat: seat, rivals: rivals, in: state) { score -= 200 }
            return (column, score)
        }
        return scored.sorted { $0.score == $1.score ? $0.column < $1.column : $0.score > $1.score }.map(\.column)
    }

    /// A disc from `seat` in `column` would make a line.
    static func wins(column: Int, seat: Int, in state: State) -> Bool {
        guard let row = landingRow(column: column, in: state) else { return false }
        var grid = state.grid
        grid[row * state.cols + column] = seat
        return !winningLine(row: row, col: column, cols: state.cols, rows: state.rows, grid: grid).isEmpty
    }

    /// A disc from `seat` in `column` would let a rival win on top of it.
    static func handsOver(column: Int, seat: Int, rivals: [Int], in state: State) -> Bool {
        guard let row = landingRow(column: column, in: state), row > 0 else { return false }
        var grid = state.grid
        grid[row * state.cols + column] = seat
        let above = row - 1
        return rivals.contains { rival in
            var next = grid
            next[above * state.cols + column] = rival
            return !winningLine(row: above, col: column, cols: state.cols, rows: state.rows, grid: next).isEmpty
        }
    }
}
