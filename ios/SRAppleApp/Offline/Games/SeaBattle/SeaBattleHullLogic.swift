import Foundation

// How Sea Battle draws a ship: not as grey squares but as one hull laid
// across its squares, rounded at the bow and the stern. Each square of a ship
// needs to know which part of the hull it is and which way the ship lies;
// this works that out from the ship's squares alone, so it is the same for
// every phone and never touches the rules. Foundation only, unit-tested.

/// Which part of a hull one square is.
enum SeaBattleHullPart: Equatable {
    /// A ship one square long (none in the standard fleet, but safe).
    case single
    /// The first square: the bow.
    case start
    case middle
    /// The last square: the stern.
    case end
}

/// One square's piece of a hull.
struct SeaBattleHullMark: Equatable {
    let part: SeaBattleHullPart
    /// The ship lies across (left to right) rather than down.
    let across: Bool
    /// Which ship in the fleet, for picking.
    let ship: Int
}

enum SeaBattleHull {
    /// The part of each of `count` squares, bow first.
    static func parts(count: Int) -> [SeaBattleHullPart] {
        guard count > 0 else { return [] }
        if count == 1 { return [.single] }
        return (0..<count).map { index in
            if index == 0 { return .start }
            if index == count - 1 { return .end }
            return .middle
        }
    }

    /// Whether `cells` (bow first) lie across a grid `size` wide: each one
    /// step right of the last, on one row.
    static func liesAcross(_ cells: [Int], size: Int) -> Bool {
        guard cells.count > 1, size > 0 else { return true }
        return cells[1] - cells[0] == 1 && cells[0] / size == cells[1] / size
    }

    /// The hull marks for a fleet: each ship's squares (bow first) to marks
    /// keyed by square. A square claimed twice keeps the first ship's mark.
    static func marks(ships: [[Int]], size: Int) -> [Int: SeaBattleHullMark] {
        var out: [Int: SeaBattleHullMark] = [:]
        for (ship, cells) in ships.enumerated() {
            let across = liesAcross(cells, size: size)
            for (cell, part) in zip(cells, parts(count: cells.count)) where out[cell] == nil {
                out[cell] = SeaBattleHullMark(part: part, across: across, ship: ship)
            }
        }
        return out
    }
}
