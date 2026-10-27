import Foundation

/// A Home tile's footprint, in the iPhone Home Screen's own terms: a shortcut
/// is 2×1, a square 2×2, a wide tile 4×2 and the Orbit 4×4.
///
/// John, 2026-10-27: tiles are widgets now. A widget the reader can resize
/// says so in `HomeTileKind.sizes`; one with nothing to show folds to a
/// square on its own (`HomeSizing.resolve`) and opens out again when it has
/// something — a diary with no events is a 2×2, the same diary with a
/// meeting at two is a 4×2.
///
/// Foundation only, like the briefing, so every rule here is a unit test the
/// Linux harness runs (`scripts/home-check.sh`).
enum HomeSize: String, Codable, CaseIterable, Comparable {
    case compact, square, wide, hero

    static func < (a: HomeSize, b: HomeSize) -> Bool { a.rank < b.rank }

    private var rank: Int {
        switch self {
        case .compact: return 0
        case .square: return 1
        case .wide: return 2
        case .hero: return 3
        }
    }

    /// What the size button in Arrange says.
    var title: String {
        switch self {
        case .compact: return "Small"
        case .square: return "Square"
        case .wide: return "Wide"
        case .hero: return "Large"
        }
    }

    /// "2×1", "2×2", "4×2", "4×4" — the grid cells it takes.
    var cells: String {
        switch self {
        case .compact: return "2×1"
        case .square: return "2×2"
        case .wide: return "4×2"
        case .hero: return "4×4"
        }
    }

    /// Half the row: a square or a shortcut sits beside something.
    var half: Bool { self == .compact || self == .square }
}

/// How Home's rows are made from the tiles' sizes.
///
/// `full` is a wide tile or the Orbit, or a shortcut with nothing to sit
/// beside. `pair` is two squares, or two shortcuts. `stack` is a square with
/// one or two shortcuts stacked beside it — the Home Screen's own trick, two
/// small widgets in the room of one square. `single` is a square nothing
/// could be found to sit beside: it stays a square, at half the width, rather
/// than being stretched across the row (a tile that folded to 2×2 because it
/// had nothing to say must not then be drawn 4×2).
enum HomePackedRow<Member: Hashable>: Hashable, Identifiable {
    case full(Member)
    case pair(Member, Member)
    case single(Member)
    case stack(Member, [Member])

    var members: [Member] {
        switch self {
        case .full(let a), .single(let a): return [a]
        case .pair(let a, let b): return [a, b]
        case .stack(let a, let rest): return [a] + rest
        }
    }

    var id: [Member] { members }
}

enum HomeSizing {
    /// The size a tile is drawn at. PURE.
    ///
    /// `chosen` is the reader's (or the tile's default), kept to what the
    /// tile allows. An `adaptive` tile with nothing to show folds a wide or
    /// large choice down to a square; `hasContent` nil means not known yet —
    /// still loading — and keeps the choice, so a tile does not shrink on
    /// launch and grow again a second later.
    static func resolve(chosen: HomeSize, allowed: [HomeSize], adaptive: Bool, hasContent: Bool?) -> HomeSize {
        let size = allowed.contains(chosen) ? chosen : (allowed.first ?? chosen)
        guard adaptive, hasContent == false, size > .square, allowed.contains(.square) else { return size }
        return .square
    }

    /// The size after `size` in the tile's own list, round again at the end:
    /// what one press of the size button in Arrange gives. PURE.
    static func next(after size: HomeSize, allowed: [HomeSize]) -> HomeSize {
        let sorted = allowed.sorted()
        guard let at = sorted.firstIndex(of: size) else { return sorted.first ?? size }
        return sorted[(at + 1) % sorted.count]
    }

    /// How far ahead a square looks for something to sit beside. Far enough
    /// to step past one wide tile; not so far that a tile from the foot of
    /// the page jumps to the top.
    static let lookahead = 3

    /// The rows, in the reader's order as near as the sizes allow. PURE.
    ///
    /// A square takes the next square within `lookahead` as its partner —
    /// pulling it up past a wide tile if it must — else up to two shortcuts
    /// to stack beside it, else it stands alone at its own size. A shortcut
    /// takes the next shortcut, else the next square (stacked beside it),
    /// else the whole row. At the accessibility text sizes (`folded`)
    /// everything is one column.
    static func pack<Member: Hashable>(_ tiles: [(id: Member, size: HomeSize)], folded: Bool = false) -> [HomePackedRow<Member>] {
        if folded { return tiles.map { .full($0.id) } }
        var used = Set<Int>()
        var rows: [HomePackedRow<Member>] = []
        for index in tiles.indices where !used.contains(index) {
            used.insert(index)
            let tile = tiles[index]
            let ahead = Array(tiles.indices.filter { $0 > index && !used.contains($0) }.prefix(lookahead))
            switch tile.size {
            case .hero, .wide:
                rows.append(.full(tile.id))
            case .square:
                if let partner = ahead.first(where: { tiles[$0].size == .square }) {
                    used.insert(partner)
                    rows.append(.pair(tile.id, tiles[partner].id))
                } else {
                    let small = Array(ahead.filter { tiles[$0].size == .compact }.prefix(2))
                    if small.isEmpty {
                        rows.append(.single(tile.id))
                    } else {
                        small.forEach { used.insert($0) }
                        rows.append(.stack(tile.id, small.map { tiles[$0].id }))
                    }
                }
            case .compact:
                if let partner = ahead.first(where: { tiles[$0].size == .compact }) {
                    used.insert(partner)
                    rows.append(.pair(tile.id, tiles[partner].id))
                } else if let square = ahead.first(where: { tiles[$0].size == .square }) {
                    used.insert(square)
                    rows.append(.stack(tiles[square].id, [tile.id]))
                } else {
                    rows.append(.full(tile.id))
                }
            }
        }
        return rows
    }
}

/// The owner's diary for the Calendar tile: what is left of today, and the
/// next thing after it. Fed plain values, so the rule is a unit test.
enum HomeDiary {
    struct Entry: Equatable, Identifiable {
        let id: String
        let title: String
        let start: Date
        var end: Date? = nil
        var place: String? = nil
        var leaveBy: Date? = nil
    }

    struct Agenda: Equatable {
        /// Today's entries not yet over, soonest first.
        var today: [Entry]
        /// The first entry after today, for a quiet day's "Next: …".
        var next: Entry?
        /// False when the diary could not be read: never "nothing on".
        var readable: Bool

        /// Something to show: the tile opens out to 4×2 for it.
        var hasContent: Bool { readable && !today.isEmpty }
    }

    /// An entry with no end is taken to last an hour.
    static let assumedLength: TimeInterval = 3600

    /// PURE.
    static func agenda(_ entries: [Entry], now: Date, zone: TimeZone, readable: Bool = true) -> Agenda {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let sorted = entries.sorted { $0.start < $1.start }
        let today = sorted.filter { entry in
            calendar.isDate(entry.start, inSameDayAs: now) && (entry.end ?? entry.start.addingTimeInterval(assumedLength)) > now
        }
        let next = sorted.first { !calendar.isDate($0.start, inSameDayAs: now) && $0.start > now }
        return Agenda(today: today, next: next, readable: readable)
    }

    /// "Now", "In 25 min", "14:00" — when an entry starts, said from `now`.
    static func when(_ entry: Entry, now: Date, zone: TimeZone) -> String {
        if entry.start <= now { return "Now" }
        let minutes = Int((entry.start.timeIntervalSince(now) / 60).rounded())
        if minutes < 60 { return "In \(minutes) min" }
        return HomeBriefing.clock(entry.start, zone)
    }
}
