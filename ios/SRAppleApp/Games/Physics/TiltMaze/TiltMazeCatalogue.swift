import Foundation

/// A level drawn by hand: its name, a line of advice, and the drawing
/// (`TiltMazeLevel.parse`).
struct TiltMazeHandLevel {
    let name: String
    let tip: String
    let map: [String]
}

/// What a level is called and the advice on its card.
struct TiltMazeLevelInfo: Equatable {
    let number: Int
    let name: String
    let tip: String
    let cols: Int
    let rows: Int
}

/// Every Tilt Maze level: ten drawn by hand to teach the board, then thirty
/// generated from fixed seeds that grow from 6 × 8 to 12 × 16 with more holes
/// as they go — forty in all, the same on every phone — and an endless run of
/// fresh mazes that keep growing.
enum TiltMazeCatalogue {
    static let campaignCount = 40
    static var handBuiltCount: Int { hand.count }

    /// Campaign level `number`, 1...40 (clamped).
    static func level(_ number: Int) -> TiltMazeLevel {
        let n = min(max(number, 1), campaignCount)
        if n <= hand.count, let drawn = TiltMazeLevel.parse(hand[n - 1].map) { return drawn }
        return TiltMazeGenerator.make(recipe(campaign: n), seed: seed(campaign: n))
    }

    static func info(_ number: Int) -> TiltMazeLevelInfo {
        let n = min(max(number, 1), campaignCount)
        if n <= hand.count {
            let drawn = hand[n - 1]
            let cols = ((drawn.map.first?.count ?? 3) - 1) / 2
            let rows = (drawn.map.count - 1) / 2
            return TiltMazeLevelInfo(number: n, name: drawn.name, tip: drawn.tip, cols: cols, rows: rows)
        }
        let recipe = recipe(campaign: n)
        let name = woods[(n - hand.count - 1) % woods.count]
        return TiltMazeLevelInfo(number: n, name: name, tip: tip(campaign: n), cols: recipe.cols, rows: recipe.rows)
    }

    /// The size and the share of holes for a generated campaign level.
    static func recipe(campaign n: Int) -> TiltMazeGenerator.Recipe {
        let k = Double(min(max(n - hand.count - 1, 0), 29)) / 29
        let cols = 6 + Int((k * 6).rounded())
        return TiltMazeGenerator.Recipe(cols: cols, rows: rows(for: cols), holeShare: 0.05 + 0.09 * k, braid: 0.04 + 0.06 * k)
    }

    static func seed(campaign n: Int) -> UInt64 { 0x7111_7A2E &+ UInt64(n) &* 7919 }

    /// Endless maze `depth` (0 for the first of a run): a fresh maze from
    /// `seed`, a little bigger and holier every two.
    static func endless(depth: Int, seed: UInt64) -> TiltMazeLevel {
        TiltMazeGenerator.make(endlessRecipe(depth: depth), seed: seed)
    }

    static func endlessRecipe(depth: Int) -> TiltMazeGenerator.Recipe {
        let d = max(0, depth)
        let cols = min(12, 6 + d / 2)
        return TiltMazeGenerator.Recipe(cols: cols, rows: rows(for: cols), holeShare: min(0.16, 0.06 + 0.008 * Double(d)),
                                        braid: 0.06)
    }

    /// Mazes are a little taller than wide, the shape of a phone held upright.
    private static func rows(for cols: Int) -> Int { Int((Double(cols) * 1.35).rounded()) }

    private static func tip(campaign n: Int) -> String {
        switch n {
        case ...15: return "A maze to find your way through. The holes sit just past the turns."
        case ...25: return "Bigger now, with loops. The quickest way is not always the safest."
        case ...35: return "More holes on the corners. Roll over each flag to save your place."
        default: return "The big ones. Steady hands, and don't forget to calibrate."
        }
    }

    /// The generated levels are named after woods.
    private static let woods = [
        "Oak", "Ash", "Beech", "Birch", "Cedar", "Elm", "Hazel", "Larch", "Maple", "Pine",
        "Rowan", "Willow", "Yew", "Alder", "Walnut", "Cherry", "Holly", "Juniper", "Linden", "Poplar",
        "Spruce", "Sycamore", "Teak", "Ebony", "Mahogany", "Chestnut", "Hawthorn", "Hornbeam", "Cypress", "Redwood",
    ]

    /// The ten drawn by hand, gentlest first.
    static let hand: [TiltMazeHandLevel] = [
        TiltMazeHandLevel(
            name: "First roll",
            tip: "Tilt gently. The marble keeps rolling until something stops it.",
            map: [
                "+-+-+-+-+-+",
                "|S        |",
                "+-+-+-+-+ +",
                "|         |",
                "+ +-+-+-+-+",
                "|         |",
                "+-+-+-+-+ +",
                "|         |",
                "+ +-+-+-+-+",
                "|        G|",
                "+-+-+-+-+-+",
            ]
        ),
        TiltMazeHandLevel(
            name: "Snail shell",
            tip: "Round and round to the middle. Ease off before each corner.",
            map: [
                "+-+-+-+-+-+-+",
                "|S          |",
                "+-+-+-+-+-+ +",
                "|         | |",
                "+ +-+-+-+ + +",
                "| |     | | |",
                "+ + +-+ + + +",
                "| | |G| | | |",
                "+ + + + + + +",
                "| | |   | | |",
                "+ + +-+-+ + +",
                "| |       | |",
                "+ +-+-+-+-+ +",
                "|           |",
                "+-+-+-+-+-+-+",
            ]
        ),
        TiltMazeHandLevel(
            name: "Mind the holes",
            tip: "An open floor with holes in it. Steer round them.",
            map: [
                "+-+-+-+-+-+",
                "|S        |",
                "+ + + + + +",
                "|    O    |",
                "+ + + + + +",
                "|O        |",
                "+ + + + + +",
                "|    O   O|",
                "+ + + + + +",
                "|  O      |",
                "+ + + + + +",
                "|      O  |",
                "+ + + + + +",
                "|O       G|",
                "+-+-+-+-+-+",
            ]
        ),
        TiltMazeHandLevel(
            name: "Zigzag",
            tip: "Each turn has a hole just past it. Slow down before you turn.",
            map: [
                "+-+-+-+-+-+-+",
                "|S          |",
                "+-+-+-+-+ +-+",
                "|O          |",
                "+-+ +-+-+-+-+",
                "|          O|",
                "+-+-+-+-+ +-+",
                "|O          |",
                "+-+ +-+-+-+-+",
                "|          O|",
                "+-+-+-+-+ +-+",
                "|O          |",
                "+-+ +-+-+-+-+",
                "|          O|",
                "+-+-+-+-+ +-+",
                "|G          |",
                "+-+-+-+-+-+-+",
            ]
        ),
        TiltMazeHandLevel(
            name: "Halfway house",
            tip: "Roll over the flag and a fall brings you back there, not to the start.",
            map: [
                "+-+-+-+-+-+-+-+",
                "|S    |       |",
                "+-+-+ + +-+-+ +",
                "|     |   |   |",
                "+ + +-+-+ + +-+",
                "| | |     |   |",
                "+ +-+ +-+-+-+ +",
                "|     |       |",
                "+-+-+-+ +-+-+-+",
                "|      C      |",
                "+ + + + + + + +",
                "|  O     O    |",
                "+ + + + + + + +",
                "|O   O     O  |",
                "+ + + + + + + +",
                "|      O      |",
                "+ + + + + + + +",
                "|G O       O O|",
                "+-+-+-+-+-+-+-+",
            ]
        ),
        TiltMazeHandLevel(
            name: "Stepping stones",
            tip: "One safe way across. Small tilts win.",
            map: [
                "+-+-+-+-+-+-+-+",
                "|S   O       O|",
                "+ + + + + + + +",
                "|O   O   O    |",
                "+ + + + + + + +",
                "|    O   O O  |",
                "+ + + + + + + +",
                "|  O O     O  |",
                "+ + + + + + + +",
                "|      O   O  |",
                "+ + + + + + + +",
                "|O O   O      |",
                "+ + + + + + + +",
                "|      O O O  |",
                "+ + + + + + + +",
                "|  O       O  |",
                "+ + + + + + + +",
                "|G O O O      |",
                "+-+-+-+-+-+-+-+",
            ]
        ),
        TiltMazeHandLevel(
            name: "Rings",
            tip: "Three rings, one way in to each. The holes close the short way round.",
            map: [
                "+-+-+-+-+-+-+-+",
                "|S     O      |",
                "+ +-+-+-+-+-+ +",
                "| |    O    | |",
                "+ + +-+-+-+ + +",
                "| | |     | |O|",
                "+ + + +-+ + + +",
                "| | | |O| | | |",
                "+ + + + + + + +",
                "| |   |G| |C  |",
                "+ + + + + + + +",
                "| | | | | | | |",
                "+ + + + + + + +",
                "| | |O    | | |",
                "+ + +-+-+-+ + +",
                "| |         | |",
                "+ +-+-+-+-+-+ +",
                "|             |",
                "+-+-+-+-+-+-+-+",
            ]
        ),
        TiltMazeHandLevel(
            name: "Crossroads",
            tip: "Four rooms off a crossroads. Only one door leads home.",
            map: [
                "+-+-+-+-+-+-+-+",
                "|S    |O|     |",
                "+ + + + + + + +",
                "|  O  |    O  |",
                "+ + + + + + + +",
                "|    O| |     |",
                "+ + + + + + + +",
                "|       |     |",
                "+-+-+-+ +-+-+-+",
                "|O     C     O|",
                "+-+ +-+ +-+ +-+",
                "|     | |     |",
                "+ + + + + + + +",
                "|     | |O   O|",
                "+ + + + + + + +",
                "|  O  | |     |",
                "+ + + + + + + +",
                "|     |O|  O G|",
                "+-+-+-+-+-+-+-+",
            ]
        ),
        TiltMazeHandLevel(
            name: "Switchbacks",
            tip: "Wide lanes with holes in both sides. Weave.",
            map: [
                "+-+-+-+-+-+-+-+-+",
                "|S   O       O  |",
                "+ + + + + + + + +",
                "|        O      |",
                "+-+-+-+-+-+-+-+ +",
                "|  O       O    |",
                "+ + + + + + + + +",
                "|      O       O|",
                "+ +-+-+-+-+-+-+-+",
                "|C   O       O  |",
                "+ + + + + + + + +",
                "|        O      |",
                "+-+-+-+-+-+-+-+ +",
                "|        O      |",
                "+ + + + + + + + +",
                "|    O       O  |",
                "+ +-+-+-+-+-+-+-+",
                "|C       O      |",
                "+ + + + + + + + +",
                "|    O       O G|",
                "+-+-+-+-+-+-+-+-+",
            ]
        ),
        TiltMazeHandLevel(
            name: "The labyrinth",
            tip: "A proper maze, with two flags on the way. Dead ends hide holes.",
            map: [
                "+-+-+-+-+-+-+-+-+",
                "|S|   |     |   |",
                "+ + + + +-+ + + +",
                "|   | | |O| | |O|",
                "+-+-+ + + + +-+ +",
                "|   |   |   |   |",
                "+ +-+-+-+ +-+ + +",
                "|O|       |O  | |",
                "+ + +-+-+-+ + + +",
                "|   |O    | | | |",
                "+ +-+-+ + +-+ + +",
                "|C    |C|   | | |",
                "+-+-+ + +-+ + + +",
                "|O  | | |O    | |",
                "+ +-+ + +-+-+-+ +",
                "|     |     |O  |",
                "+ +-+-+-+-+ +-+ +",
                "|         |   | |",
                "+-+-+-+-+ +-+ + +",
                "|       |     | |",
                "+ + +-+-+-+-+-+ +",
                "| |          O G|",
                "+-+-+-+-+-+-+-+-+",
            ]
        ),
    ]
}
