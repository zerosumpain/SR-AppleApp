import Foundation

/// Makes a maze from a seed: a recursive backtracker carves a perfect maze
/// (one way between any two cells), a few extra walls come out so there are
/// loops to choose between, the goal goes at the cell furthest from the
/// start, and then the holes go in — never on the way through, and first of
/// all just off it, at the junctions, where a ball rolling too fast
/// overshoots the turn. Long mazes get checkpoints along the way.
///
/// The same seed and size always make the same maze, on every phone.
enum TiltMazeGenerator {
    struct Recipe: Equatable {
        var cols: Int
        var rows: Int
        /// Holes as a share of the cells.
        var holeShare: Double
        /// Extra walls knocked out, as a share of the cells: loops.
        var braid: Double
    }

    static func make(_ recipe: Recipe, seed: UInt64) -> TiltMazeLevel {
        let cols = max(2, recipe.cols), rows = max(2, recipe.rows)
        var rng = TiltMazeRandom(seed: seed)
        var walls = TiltMazeLevel.solidWalls(cols: cols, rows: rows)
        let start = TiltMazeCell(0, 0)

        // A perfect maze, carved depth first.
        var visited = [Bool](repeating: false, count: cols * rows)
        var stack: [TiltMazeCell] = [start]
        visited[0] = true
        var options: [TiltMazeCell] = []
        options.reserveCapacity(4)
        while let top = stack.last {
            options.removeAll(keepingCapacity: true)
            for next in top.sides where next.x >= 0 && next.y >= 0 && next.x < cols && next.y < rows
                && !visited[next.y * cols + next.x] {
                options.append(next)
            }
            guard !options.isEmpty else {
                stack.removeLast()
                continue
            }
            let next = options[rng.int(options.count)]
            knock(top, next, cols: cols, walls: &walls)
            visited[next.y * cols + next.x] = true
            stack.append(next)
        }

        // A few loops: inner walls knocked out at random.
        var inner: [(TiltMazeCell, TiltMazeCell)] = []
        for y in 0..<rows {
            for x in 0..<cols {
                if x + 1 < cols && walls.vertical[y * (cols + 1) + x + 1] {
                    inner.append((TiltMazeCell(x, y), TiltMazeCell(x + 1, y)))
                }
                if y + 1 < rows && walls.horizontal[(y + 1) * cols + x] {
                    inner.append((TiltMazeCell(x, y), TiltMazeCell(x, y + 1)))
                }
            }
        }
        rng.shuffle(&inner)
        let loops = min(inner.count, Int((Double(cols * rows) * max(0, recipe.braid)).rounded()))
        for pair in inner.prefix(loops) { knock(pair.0, pair.1, cols: cols, walls: &walls) }

        // The goal: the cell furthest from the start (the lowest, rightmost
        // of the furthest, so a tie always breaks the same way).
        let open = TiltMazeLevel(cols: cols, rows: rows, vertical: walls.vertical, horizontal: walls.horizontal,
                                 start: start, goal: start, holes: [], checkpoints: [])
        let distance = open.distances(from: start)
        var goalIndex = 0
        for i in 0..<distance.count where distance[i] >= distance[goalIndex] { goalIndex = i }
        let goal = open.cell(at: goalIndex)
        let plain = TiltMazeLevel(cols: cols, rows: rows, vertical: walls.vertical, horizontal: walls.horizontal,
                                  start: start, goal: goal, holes: [], checkpoints: [])
        let solution = plain.solution ?? [start, goal]
        let onPath = Set(solution)

        // Holes: first the cells just off the way through, then anywhere else
        // off it; never beside the start, so the first second is not a drop.
        let nearStart = Set(plain.neighbours(of: start))
        var junctions: [TiltMazeCell] = []
        var elsewhere: [TiltMazeCell] = []
        var placed = Set<TiltMazeCell>()
        for cell in solution {
            for side in plain.neighbours(of: cell) where !onPath.contains(side) && !placed.contains(side) {
                placed.insert(side)
                junctions.append(side)
            }
        }
        for i in 0..<(cols * rows) {
            let cell = plain.cell(at: i)
            if !onPath.contains(cell) && !placed.contains(cell) { elsewhere.append(cell) }
        }
        rng.shuffle(&junctions)
        rng.shuffle(&elsewhere)
        let wanted = Int((Double(cols * rows) * max(0, recipe.holeShare)).rounded())
        var holes: [TiltMazeCell] = []
        for cell in junctions + elsewhere where holes.count < wanted {
            if cell == start || cell == goal || nearStart.contains(cell) { continue }
            holes.append(cell)
        }

        // Checkpoints, evenly along the way through, on long mazes.
        var checkpoints: [TiltMazeCell] = []
        let count = min(3, (solution.count - 1) / 26)
        if count > 0 {
            for k in 1...count {
                let at = solution.count * k / (count + 1)
                checkpoints.append(solution[min(max(1, at), solution.count - 2)])
            }
        }

        return TiltMazeLevel(cols: cols, rows: rows, vertical: walls.vertical, horizontal: walls.horizontal,
                             start: start, goal: goal, holes: holes, checkpoints: checkpoints)
    }

    /// Take down the wall between two side-by-side cells.
    private static func knock(_ a: TiltMazeCell, _ b: TiltMazeCell, cols: Int,
                              walls: inout (vertical: [Bool], horizontal: [Bool])) {
        if a.y == b.y {
            walls.vertical[a.y * (cols + 1) + max(a.x, b.x)] = false
        } else {
            walls.horizontal[max(a.y, b.y) * cols + a.x] = false
        }
    }
}
