import Foundation

/// Dots and Boxes' computer player, for solo play and spare seats.
///
/// The beginner's strategy, which is also most people's: close any box that
/// has three sides, never draw the third side of a box if there is a safe
/// line left, and when only unsafe lines remain, give away as few boxes as
/// it can. It does not count chains, so a player who knows the long-chain
/// rule beats it at the end.
extension DotsAndBoxesRules: OfflineBotRules {
    static func botActions(_ state: State, for playerId: String, rng: inout OfflineRNG) -> [Action] {
        guard state.phase == .playing,
              let seat = state.players.firstIndex(where: { $0.id == playerId }) else { return [] }
        if state.away.contains(playerId) { return [.back] }
        guard seat == state.turn else { return [] }
        return botLines(state, rng: &rng).map { .draw(turn: state.turnNumber, line: $0) }
    }

    /// Every open line, best first.
    static func botLines(_ state: State, rng: inout OfflineRNG) -> [Line] {
        let scored = openLines(state).map { line -> (line: Line, score: Double) in
            var closes = 0
            var gives = 0
            for box in boxes(touching: line, rows: state.rows, cols: state.cols) {
                switch drawnSides(row: box.row, col: box.col, in: state) {
                case 3: closes += 1
                case 2: gives += 1
                default: break
                }
            }
            return (line, Double(closes * 100 - gives * 50) + rng.double(in: 0...1))
        }
        return scored.sorted { $0.score > $1.score }.map(\.line)
    }

    /// The one or two boxes a line is a side of.
    static func boxes(touching line: Line, rows: Int, cols: Int) -> [(row: Int, col: Int)] {
        var out: [(row: Int, col: Int)] = []
        if line.horizontal {
            if line.row > 0 { out.append((line.row - 1, line.col)) }
            if line.row < rows { out.append((line.row, line.col)) }
        } else {
            if line.col > 0 { out.append((line.row, line.col - 1)) }
            if line.col < cols { out.append((line.row, line.col)) }
        }
        return out
    }

    /// Sides of box (`row`, `col`) already drawn.
    static func drawnSides(row: Int, col: Int, in state: State) -> Int {
        sides(row: row, col: col).filter { isDrawn($0, in: state) == true }.count
    }
}
