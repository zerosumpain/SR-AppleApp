import Foundation

/// One wall layout for Maze mode. The first is open from the start; each of
/// the others opens when you score `unlockScore` on the one before it.
///
/// Every layout is drawn on the standard 15 × 17 board and keeps the start
/// row clear, so the snake never begins with a wall in its face (the tests
/// check that, and that every free cell can be reached).
struct SnakeMaze: Identifiable, Equatable {
    let id: String
    let name: String
    let line: String
    /// Score needed on the previous maze to open this one. 0 for the first.
    let unlockScore: Int
    let walls: Set<SnakePoint>

    static let all: [SnakeMaze] = [pillars, box, corners, crossroads, corridors]

    static func named(_ id: String) -> SnakeMaze {
        all.first { $0.id == id } ?? all[0]
    }

    /// The maze before this one, which opens it; nil for the first.
    var previous: SnakeMaze? {
        guard let index = SnakeMaze.all.firstIndex(of: self), index > 0 else { return nil }
        return SnakeMaze.all[index - 1]
    }

    // MARK: - The layouts

    static let pillars = SnakeMaze(
        id: "pillars", name: "Pillars", line: "Four stone pillars. A gentle start.", unlockScore: 0,
        walls: join([block(3, 3, 2, 2), block(10, 3, 2, 2), block(3, 12, 2, 2), block(10, 12, 2, 2)]))

    static let box = SnakeMaze(
        id: "box", name: "The box", line: "A wall all round with a gap in each side. Out of one gap, in at the other.",
        unlockScore: 100,
        walls: border(gapX: 6...8, gapY: 7...9))

    static let corners = SnakeMaze(
        id: "corners", name: "Corners", line: "Four corners walled in. Apples like to hide behind them.",
        unlockScore: 120,
        walls: join([row(2, 2...5), column(2, 2...5), row(2, 9...12), column(12, 2...5),
                     row(14, 2...5), column(2, 11...14), row(14, 9...12), column(12, 11...14)]))

    static let crossroads = SnakeMaze(
        id: "crossroads", name: "Crossroads", line: "A wall down the middle and four arms. Find the gap.",
        unlockScore: 150,
        walls: join([column(7, 0...5), column(7, 11...16), row(4, 0...4), row(4, 10...14),
                     row(12, 0...4), row(12, 10...14)]))

    static let corridors = SnakeMaze(
        id: "corridors", name: "Corridors", line: "Long walls across the board. Plan every turn.",
        unlockScore: 200,
        walls: join([row(2, 2...12), row(5, 0...5), row(5, 9...14), row(11, 0...5), row(11, 9...14),
                     row(14, 2...12)]))

    // MARK: - Building blocks

    private static func join(_ parts: [Set<SnakePoint>]) -> Set<SnakePoint> {
        var out = Set<SnakePoint>()
        for part in parts { out.formUnion(part) }
        return out
    }

    private static func block(_ x: Int, _ y: Int, _ width: Int, _ height: Int) -> Set<SnakePoint> {
        var out = Set<SnakePoint>()
        for dy in 0..<height {
            for dx in 0..<width { out.insert(SnakePoint(x + dx, y + dy)) }
        }
        return out
    }

    private static func row(_ y: Int, _ xs: ClosedRange<Int>) -> Set<SnakePoint> {
        Set(xs.map { SnakePoint($0, y) })
    }

    private static func column(_ x: Int, _ ys: ClosedRange<Int>) -> Set<SnakePoint> {
        Set(ys.map { SnakePoint(x, $0) })
    }

    /// The board's edge, less a gap in the middle of each side.
    private static func border(gapX: ClosedRange<Int>, gapY: ClosedRange<Int>) -> Set<SnakePoint> {
        let columns = SnakeRules.columns, rows = SnakeRules.rows
        var out = Set<SnakePoint>()
        for x in 0..<columns where !gapX.contains(x) {
            out.insert(SnakePoint(x, 0))
            out.insert(SnakePoint(x, rows - 1))
        }
        for y in 0..<rows where !gapY.contains(y) {
            out.insert(SnakePoint(0, y))
            out.insert(SnakePoint(columns - 1, y))
        }
        return out
    }
}
