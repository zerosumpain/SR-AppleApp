import Foundation

// "No guessing" fields: lay mines, then let a simple solver play from the
// first dig using only the rules a careful person uses — a number already
// has all its mines (the rest are safe), a number needs every covered square
// round it (they are all mines), one number's squares sit inside another's
// (the difference is settled), and the mine counter itself. If the solver
// clears the field, so can the player without a coin toss. If not, lay again,
// up to a cap; past the cap the last field is played as it is.

enum MinesweeperSolver {
    /// True when logic alone clears `board` (mines laid, nothing dug) from a
    /// first dig at `start`.
    static func solves(_ board: MinesweeperBoard, from start: Int) -> Bool {
        guard board.minesLaid, start >= 0, start < board.size else { return false }
        var play = board
        let size = play.size
        var known = Array(repeating: false, count: size) // squares known to be mines
        var knownCount = 0
        // Showing numbers that still touch something unknown: the only squares worth reading.
        var frontier: [Int] = []

        func dig(_ index: Int) {
            let outcome = play.reveal(index)
            for o in outcome.opened where play.counts[o.index] > 0 { frontier.append(o.index) }
        }

        dig(start)
        var unknown: [Int] = []
        unknown.reserveCapacity(8)

        while play.status == .playing {
            var progress = false
            var safe: [Int] = []
            var rules: [MinesweeperRule] = []
            var active: [Int] = []
            active.reserveCapacity(frontier.count)

            // Each showing number, as a rule over the squares round it still unknown.
            for i in frontier {
                unknown.removeAll(keepingCapacity: true)
                var found = 0
                let cells = play.cells
                play.forEachNeighbour(of: i) { n in
                    if known[n] {
                        found += 1
                    } else if cells[n] != .revealed {
                        unknown.append(n)
                    }
                }
                if unknown.isEmpty { continue }
                active.append(i)
                let need = play.counts[i] - found
                if need == 0 {
                    safe.append(contentsOf: unknown)
                } else if need == unknown.count {
                    for u in unknown where !known[u] {
                        known[u] = true
                        knownCount += 1
                        progress = true
                    }
                } else {
                    rules.append(MinesweeperRule(cells: unknown, need: need))
                }
            }
            frontier = active

            if !safe.isEmpty {
                for s in safe where play.cells[s] == .hidden { dig(s) }
                continue
            }
            if progress { continue }

            // One rule's squares inside another's: the leftover squares hold
            // the difference in mines — none, or all of them.
            if subsetStep(rules, safe: &safe, mines: &known, count: &knownCount) {
                for s in safe where play.cells[s] == .hidden { dig(s) }
                continue
            }

            // The counter: no mines left means everything covered is safe;
            // as many left as covered squares means they are all mines.
            let remaining = play.mineCount - knownCount
            var covered: [Int] = []
            for i in 0..<size where play.cells[i] != .revealed && !known[i] { covered.append(i) }
            if covered.isEmpty { break }
            if remaining == 0 {
                for s in covered where play.cells[s] == .hidden { dig(s) }
                continue
            }
            if remaining == covered.count {
                for c in covered {
                    known[c] = true
                    knownCount += 1
                }
                continue
            }
            break
        }
        return play.status == .won
    }

    private static func subsetStep(_ rules: [MinesweeperRule], safe: inout [Int],
                                   mines: inout [Bool], count: inout Int) -> Bool {
        guard rules.count > 1 else { return false }
        // Which rules mention each square, so only overlapping pairs are compared.
        var byCell: [Int: [Int]] = [:]
        for (r, rule) in rules.enumerated() {
            for c in rule.cells { byCell[c, default: []].append(r) }
        }
        var progress = false
        for (a, small) in rules.enumerated() {
            guard let first = small.cells.first, let partners = byCell[first] else { continue }
            for b in partners where b != a {
                let big = rules[b]
                guard big.cells.count > small.cells.count, small.cells.allSatisfy({ big.cells.contains($0) }) else { continue }
                let rest = big.cells.filter { !small.cells.contains($0) }
                let extra = big.need - small.need
                if extra == 0 {
                    for r in rest where !mines[r] && !safe.contains(r) {
                        safe.append(r)
                        progress = true
                    }
                } else if extra == rest.count {
                    for r in rest where !mines[r] {
                        mines[r] = true
                        count += 1
                        progress = true
                    }
                }
            }
        }
        return progress
    }
}

/// "These squares hold `need` mines."
private struct MinesweeperRule {
    var cells: [Int]
    var need: Int
}

/// A laid field, ready for its first dig.
struct MinesweeperField: Sendable {
    var board: MinesweeperBoard
    /// The solver cleared it from the first dig.
    var logical: Bool
    var attempts: Int
}

enum MinesweeperGenerator {
    /// How many fields to try for a no-guessing board before settling for
    /// the last one. Small fields are cheap to solve and usually pass in a
    /// handful; Expert needs more tries and each costs more.
    static func attemptCap(width: Int, height: Int) -> Int {
        let cells = max(1, width * height)
        return max(150, min(3000, 240_000 / cells))
    }

    /// Lays a field for a first dig at `first`. With `noGuess` it keeps
    /// laying until the solver clears one, up to `maxAttempts` (or the
    /// `deadline`), and otherwise returns the last try.
    static func field(width: Int, height: Int, mines: Int, firstDig first: Int, noGuess: Bool,
                      seed: UInt64, maxAttempts: Int? = nil, deadline: Date? = nil) -> MinesweeperField {
        var rng = MinesweeperRandom(seed: seed)
        let cap = max(1, maxAttempts ?? attemptCap(width: width, height: height))
        var last = MinesweeperBoard(width: width, height: height, mines: mines)
        last.layMines(sparing: first, using: &rng)
        guard noGuess else { return MinesweeperField(board: last, logical: false, attempts: 1) }
        var attempts = 1
        while true {
            if MinesweeperSolver.solves(last, from: first) {
                return MinesweeperField(board: last, logical: true, attempts: attempts)
            }
            if attempts >= cap { break }
            if let deadline, Date() >= deadline { break }
            attempts += 1
            var next = MinesweeperBoard(width: width, height: height, mines: mines)
            next.layMines(sparing: first, using: &rng)
            last = next
        }
        return MinesweeperField(board: last, logical: false, attempts: attempts)
    }
}
