import Foundation

/// Where each door on the hub sits, and how big it is (John, 2026-11-02:
/// "the big features to keep 2x2 sizing, and the rest 1x1 / 1x2 / 2x1 sizing
/// to make the page look dynamic but beautiful").
///
/// The page is four columns of square cells. Settings, Drive, Captures and
/// News are always 2x2 — the size every door used to be — and everything else
/// is a 1x1, a 2x1 (wide) or a 1x2 (tall). The page is built from bands two
/// cells tall, each split into two 2x2 halves: a big door fills a half on its
/// own, and the smaller doors fill a half between them in one of a few shapes
/// (two talls, two wides, a tall or a wide with two squares, four squares).
/// Because every half is exactly full, the page has no holes whatever doors a
/// person has — members see fewer than the owner — and when the halves come
/// out odd, one half's worth of doors is laid as a one-cell strip across the
/// foot instead.
///
/// Sizes depend only on the ids and their order, never on what a door says,
/// so a count arriving does not move anything; the order is read once a
/// visit (`MoreScreen.onAppear`), so the page holds still while it is open.
///
/// Foundation only: the Linux harness tests it (`scripts/home-check.sh`).
enum HubTileSize: String, Equatable, CaseIterable {
    /// 2x2: Settings, Drive, Captures and News.
    case big
    /// 2x1.
    case wide
    /// 1x2.
    case tall
    /// 1x1.
    case small
    /// 4x1, the whole width: only for a set too small to tile any other way
    /// (a single small door: Play nearby beside an even number of big ones,
    /// on a phone that sees little else).
    case banner

    var columns: Int {
        switch self {
        case .big, .wide: return 2
        case .tall, .small: return 1
        case .banner: return 4
        }
    }

    var rows: Int {
        switch self {
        case .big, .tall: return 2
        case .wide, .small, .banner: return 1
        }
    }

    var area: Int { columns * rows }
}

/// One door's place: its size, and its top-left cell (column 0–3, row from 0).
struct HubPlacement: Equatable {
    let id: String
    let size: HubTileSize
    let column: Int
    let row: Int
}

enum HubLayout {
    static let columns = 4

    /// The four that are always 2x2. The ids are `MoreScreen.Item.id`.
    static let bigIds: Set<String> = ["settings", "drive", "captures", "news"]

    /// How many rows of cells `placements` take.
    static func rows(_ placements: [HubPlacement]) -> Int {
        placements.map { $0.row + $0.size.rows }.max() ?? 0
    }

    /// Lays out `ids`, in the order given (most used first). The big doors
    /// keep their order among themselves and so do the rest; a big door and
    /// a half of smaller ones share each band, the big one swapping sides
    /// band by band so the page zig-zags instead of stacking in a column.
    static func pack(_ ids: [String], big: Set<String> = bigIds) -> [HubPlacement] {
        var seen = Set<String>()
        let unique = ids.filter { seen.insert($0).inserted }
        let bigs = unique.filter { big.contains($0) }
        let others = unique.filter { !big.contains($0) }

        guard others.count >= 2 else { return fallback(bigs: bigs, others: others) }

        var halves = otherHalves(others, bigCount: bigs.count)
        var strip: Half?
        // An odd number of halves cannot pair into bands: the last (least
        // used) half of small doors goes across the foot as a strip.
        if (bigs.count + halves.count) % 2 == 1 { strip = halves.popLast() }

        var out: [HubPlacement] = []
        var row = 0
        var band = 0
        var bigQueue = bigs[...]
        var halfQueue = halves[...]
        var shape = 0
        func place(_ half: Half, column: Int) {
            out += half.lay(column: column, row: row, variant: shape)
            shape += 1
        }
        while !bigQueue.isEmpty || !halfQueue.isEmpty {
            if let id = bigQueue.first, let half = halfQueue.first {
                bigQueue.removeFirst()
                halfQueue.removeFirst()
                let bigLeft = band % 2 == 0
                out.append(HubPlacement(id: id, size: .big, column: bigLeft ? 0 : 2, row: row))
                place(half, column: bigLeft ? 2 : 0)
            } else if !bigQueue.isEmpty {
                // Pairs by construction: what is left after the zip is even.
                let pair = bigQueue.prefix(2)
                bigQueue.removeFirst(pair.count)
                for (index, id) in pair.enumerated() {
                    out.append(HubPlacement(id: id, size: .big, column: index * 2, row: row))
                }
            } else {
                let pair = halfQueue.prefix(2)
                halfQueue.removeFirst(pair.count)
                for (index, half) in pair.enumerated() { place(half, column: index * 2) }
            }
            row += 2
            band += 1
        }
        if let strip { out += strip.strip(row: row, variant: shape) }
        return out
    }

    // MARK: Halves

    /// A 2x2 half of a band's worth of smaller doors.
    struct Half {
        enum Shape {
            /// Two doors of two cells each.
            case pair
            /// One door of two cells, two of one.
            case mixed
            /// Four doors of one cell.
            case quad
        }

        let shape: Shape
        let ids: [String]

        /// The half at `column` (0 or 2), `row`; `variant` turns the same
        /// shape a different way each time so neighbours never match.
        func lay(column c: Int, row r: Int, variant: Int) -> [HubPlacement] {
            switch shape {
            case .pair:
                if variant % 2 == 0 {
                    return [HubPlacement(id: ids[0], size: .tall, column: c, row: r),
                            HubPlacement(id: ids[1], size: .tall, column: c + 1, row: r)]
                }
                return [HubPlacement(id: ids[0], size: .wide, column: c, row: r),
                        HubPlacement(id: ids[1], size: .wide, column: c, row: r + 1)]
            case .mixed:
                switch variant % 4 {
                case 0:
                    return [HubPlacement(id: ids[0], size: .tall, column: c, row: r),
                            HubPlacement(id: ids[1], size: .small, column: c + 1, row: r),
                            HubPlacement(id: ids[2], size: .small, column: c + 1, row: r + 1)]
                case 1:
                    return [HubPlacement(id: ids[0], size: .wide, column: c, row: r),
                            HubPlacement(id: ids[1], size: .small, column: c, row: r + 1),
                            HubPlacement(id: ids[2], size: .small, column: c + 1, row: r + 1)]
                case 2:
                    return [HubPlacement(id: ids[0], size: .tall, column: c + 1, row: r),
                            HubPlacement(id: ids[1], size: .small, column: c, row: r),
                            HubPlacement(id: ids[2], size: .small, column: c, row: r + 1)]
                default:
                    return [HubPlacement(id: ids[0], size: .wide, column: c, row: r + 1),
                            HubPlacement(id: ids[1], size: .small, column: c, row: r),
                            HubPlacement(id: ids[2], size: .small, column: c + 1, row: r)]
                }
            case .quad:
                return ids.enumerated().map { index, id in
                    HubPlacement(id: id, size: .small, column: c + index % 2, row: r + index / 2)
                }
            }
        }

        /// The same doors as one strip across the page, one cell tall: a
        /// two-cell door is laid wide.
        func strip(row r: Int, variant: Int) -> [HubPlacement] {
            switch shape {
            case .pair:
                return [HubPlacement(id: ids[0], size: .wide, column: 0, row: r),
                        HubPlacement(id: ids[1], size: .wide, column: 2, row: r)]
            case .mixed:
                if variant % 2 == 0 {
                    return [HubPlacement(id: ids[0], size: .wide, column: 0, row: r),
                            HubPlacement(id: ids[1], size: .small, column: 2, row: r),
                            HubPlacement(id: ids[2], size: .small, column: 3, row: r)]
                }
                return [HubPlacement(id: ids[1], size: .small, column: 0, row: r),
                        HubPlacement(id: ids[2], size: .small, column: 1, row: r),
                        HubPlacement(id: ids[0], size: .wide, column: 2, row: r)]
            case .quad:
                return ids.enumerated().map { index, id in HubPlacement(id: id, size: .small, column: index, row: r) }
            }
        }
    }

    /// The smaller doors cut into halves. Each door takes one cell or two;
    /// the total is chosen as a whole number of halves, as near as it can be
    /// to an even mix of ones and twos, preferring a total that pairs with
    /// the big doors into whole bands (no strip). The most used door of a
    /// mixed half is its two-cell one.
    static func otherHalves(_ others: [String], bigCount: Int) -> [Half] {
        let k = others.count
        let target = Double(k) * 1.5
        let candidates = stride(from: 4, through: 2 * k, by: 4).filter { $0 >= k }
        guard let area = candidates.min(by: { a, b in
            let pa = (bigCount + a / 4) % 2, pb = (bigCount + b / 4) % 2
            if pa != pb { return pa < pb }
            let da = abs(Double(a) - target), db = abs(Double(b) - target)
            if da != db { return da < db }
            return a > b
        }) else { return [] }

        let doubles = area - k
        let singles = 2 * k - area
        // As many mixed halves as the counts allow (the liveliest shape),
        // keeping the doubles left over even, so they pair.
        var mixed = min(doubles, singles / 2)
        if (doubles - mixed) % 2 != 0 { mixed -= 1 }
        mixed = max(mixed, 0)
        var pairs = (doubles - mixed) / 2
        var quads = (singles - 2 * mixed) / 4

        // Taken in turn — mixed, pair, quad — so like shapes do not bunch.
        var shapes: [Half.Shape] = []
        while mixed + pairs + quads > 0 {
            if mixed > 0 { shapes.append(.mixed); mixed -= 1 }
            if pairs > 0 { shapes.append(.pair); pairs -= 1 }
            if quads > 0 { shapes.append(.quad); quads -= 1 }
        }

        var rest = others[...]
        return shapes.map { shape in
            let count: Int
            switch shape {
            case .pair: count = 2
            case .mixed: count = 3
            case .quad: count = 4
            }
            let ids = Array(rest.prefix(count))
            rest.removeFirst(count)
            return Half(shape: shape, ids: ids)
        }
    }

    /// Fewer than two smaller doors cannot fill a half. One small door
    /// beside an odd big one takes the other half's square; on its own it
    /// is a strip across the foot. With none, an odd big door ends the page
    /// alone — the only layout with a gap, and one no phone has.
    static func fallback(bigs: [String], others: [String]) -> [HubPlacement] {
        var out: [HubPlacement] = []
        var row = 0
        var index = 0
        while index < bigs.count {
            out.append(HubPlacement(id: bigs[index], size: .big, column: 0, row: row))
            if index + 1 < bigs.count {
                out.append(HubPlacement(id: bigs[index + 1], size: .big, column: 2, row: row))
            } else if let lone = others.first {
                out.append(HubPlacement(id: lone, size: .big, column: 2, row: row))
                return out
            }
            index += 2
            row += 2
        }
        if let lone = others.first { out.append(HubPlacement(id: lone, size: .banner, column: 0, row: row)) }
        return out
    }
}
