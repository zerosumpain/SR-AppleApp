import Foundation

/// A button on the floor of a tile.
struct TetherPalsButton: Equatable {
    let cell: TetherPalsCell
    let channel: TetherPalsChannel
}

/// One hand-made screen: 16 × 10 tiles drawn as text, a flag, where the pals
/// start, whether they are tied, a par time and the walkthrough the demo
/// plays (and the tests prove it with).
///
/// The map's letters: `.` sky, `#` ground, `^` prickles, `a`/`b` a gold or
/// blue button, `A`/`B` a gold or blue door, `=`/`-` a gold or blue bridge,
/// `F` the flag, `1` `2` `3` where Pip, Bo and Kit start.
struct TetherPalsLevel: Equatable, Identifiable {
    let number: Int
    let name: String
    /// The one trick this level teaches, shown before it starts.
    let tip: String
    /// An SF Symbol for the trick.
    let icon: String
    let tied: Bool
    /// Seconds: a best under this earns the level's star.
    let par: Double
    let columns: Int
    let rows: Int
    let tiles: [TetherPalsTile]
    let flag: TetherPalsCell
    let buttons: [TetherPalsButton]
    let gates: [TetherPalsGate]
    let gateIndex: [TetherPalsCell: Int]
    let prickles: [TetherPalsCell]
    let script: [TetherPalsMove]
    private let spawns: [TetherPalsCell]

    var id: Int { number }

    init(number: Int, name: String, tip: String, icon: String, tied: Bool, par: Double,
         map: [String], script: [TetherPalsMove]) {
        self.number = number
        self.name = name
        self.tip = tip
        self.icon = icon
        self.tied = tied
        self.par = par
        self.script = script
        let rows = max(1, map.count)
        let columns = max(1, map.map(\.count).max() ?? 1)
        self.rows = rows
        self.columns = columns
        var tiles = Array(repeating: TetherPalsTile.empty, count: rows * columns)
        var spawnAt: [Int: TetherPalsCell] = [:]
        var flag: TetherPalsCell?
        var buttons: [TetherPalsButton] = []
        var gates: [TetherPalsGate] = []
        var gateIndex: [TetherPalsCell: Int] = [:]
        var prickles: [TetherPalsCell] = []
        for (row, line) in map.enumerated() {
            for (col, letter) in line.enumerated() {
                let cell = TetherPalsCell(col: col, row: row)
                let tile: TetherPalsTile
                switch letter {
                case "#": tile = .ground
                case "^": tile = .prickles
                case "a": tile = .button(.gold)
                case "b": tile = .button(.blue)
                case "A": tile = .door(.gold)
                case "B": tile = .door(.blue)
                case "=": tile = .bridge(.gold)
                case "-": tile = .bridge(.blue)
                case "F":
                    flag = cell
                    tile = .empty
                case "1", "2", "3":
                    spawnAt[Int(String(letter)).map { $0 - 1 } ?? 0] = cell
                    tile = .empty
                default: tile = .empty
                }
                tiles[row * columns + col] = tile
                switch tile {
                case .button(let channel): buttons.append(TetherPalsButton(cell: cell, channel: channel))
                case .door(let channel):
                    gateIndex[cell] = gates.count
                    gates.append(TetherPalsGate(cell: cell, channel: channel, isDoor: true))
                case .bridge(let channel):
                    gateIndex[cell] = gates.count
                    gates.append(TetherPalsGate(cell: cell, channel: channel, isDoor: false))
                case .prickles: prickles.append(cell)
                case .empty, .ground: break
                }
            }
        }
        self.tiles = tiles
        self.flag = flag ?? TetherPalsCell(col: columns - 2, row: rows - 2)
        self.buttons = buttons
        self.gates = gates
        self.gateIndex = gateIndex
        self.prickles = prickles
        // A missing start goes one tile right of the pal before it.
        var spawns: [TetherPalsCell] = []
        for index in 0..<TetherPalsRules.maxPals {
            if let cell = spawnAt[index] {
                spawns.append(cell)
            } else if let last = spawns.last {
                spawns.append(TetherPalsCell(col: min(columns - 1, last.col + 1), row: last.row))
            } else {
                spawns.append(TetherPalsCell(col: 0, row: rows - 2))
            }
        }
        self.spawns = spawns
    }

    func tile(col: Int, row: Int) -> TetherPalsTile {
        guard col >= 0, col < columns, row >= 0, row < rows else { return .empty }
        return tiles[row * columns + col]
    }

    /// Where pal `index` starts.
    func spawn(_ index: Int) -> TetherPalsCell {
        spawns[min(max(0, index), spawns.count - 1)]
    }

    /// Whether this level has buttons of a colour.
    func uses(_ channel: TetherPalsChannel) -> Bool {
        buttons.contains { $0.channel == channel }
    }
}

/// The twelve levels, one new trick at a time: plain running and jumping,
/// then standing on heads, then buttons, then the rope, then all of it.
enum TetherPalsCatalogue {
    static var count: Int { all.count }

    static func level(_ number: Int) -> TetherPalsLevel {
        all[min(max(1, number), all.count) - 1]
    }

    private static let sky = "................"

    static let all: [TetherPalsLevel] = [
        TetherPalsLevel(
            number: 1, name: "First steps", tip: "Run and jump. Everyone has to reach the flag.",
            icon: "figure.run", tied: false, par: 25,
            map: Array(repeating: sky, count: 7) + [
                "..........#.....",
                "213......##..F..",
                "######..########",
            ],
            script: [0, 1, 2].flatMap { pal -> [TetherPalsMove] in
                [.walk(pal, 5.4), .hop(pal, 8.5), .hop(pal, 9.5), .hop(pal, 10.5)]
            } + [.walk(0, 14.2), .walk(1, 13.4), .walk(2, 12.6)]),
        TetherPalsLevel(
            number: 2, name: "Up on my head", tip: "Too high? Walk into a pal, jump onto their head, then jump again.",
            icon: "person.2.fill", tied: false, par: 40,
            map: Array(repeating: sky, count: 6) + [
                "...........a..F.",
                ".........#######",
                "213.....=#######",
                "################",
            ],
            script: [
                .walk(1, 8.6), .climb(0, onto: 1), .hop(0, 10.5), .walk(0, 11.5),
                .walk(1, 7.3), .hop(1, 8.5), .hop(1, 9.6),
                .walk(2, 7.3), .hop(2, 8.5), .hop(2, 9.6),
                .walk(1, 14.5), .walk(2, 15.2), .walk(0, 13.6),
            ]),
        TetherPalsLevel(
            number: 3, name: "Hold the door", tip: "Stand on a button to open the door. Take turns.",
            icon: "door.left.hand.open", tied: false, par: 35,
            map: Array(repeating: ".......#........", count: 6) + [
                ".......A........",
                ".......A........",
                "213...aAa.^...F.",
                "################",
            ],
            script: [
                .walk(1, 6.5), .walk(0, 8.5),
                .walk(2, 9.5), .hop(2, 11.5),
                .walk(1, 9.5), .hop(1, 11.5),
                .walk(0, 9.5), .hop(0, 11.5),
                .walk(0, 14.5), .walk(1, 13.7), .walk(2, 15.2),
            ]),
        TetherPalsLevel(
            number: 4, name: "Big leap", tip: "Too far to jump? Jump off a pal's head: it's springy.",
            icon: "arrow.up.right", tied: false, par: 35,
            map: Array(repeating: sky, count: 8) + [
                "213..........aF.",
                "#######====#####",
            ],
            script: [
                .walk(1, 6.6), .climb(0, onto: 1), .hop(0, 12.0), .walk(0, 13.5),
                .walk(1, 14.3), .walk(2, 15.0),
            ]),
        TetherPalsLevel(
            number: 5, name: "Prickle wall", tip: "Mind the prickles. Get over the wall, then open it from behind.",
            icon: "exclamationmark.triangle.fill", tied: false, par: 40,
            map: Array(repeating: sky, count: 7) + [
                ".........A......",
                "213..^...A..a.F.",
                "################",
            ],
            script: [0, 1, 2].flatMap { pal -> [TetherPalsMove] in [.walk(pal, 4.5), .hop(pal, 6.5)] } + [
                .walk(1, 8.6), .climb(0, onto: 1), .hop(0, 10.5), .walk(0, 12.5),
                .walk(1, 14.2), .walk(2, 15.0), .walk(0, 13.4),
            ]),
        TetherPalsLevel(
            number: 6, name: "High button", tip: "A button up on the shelf. Who can reach it?",
            icon: "arrow.up.to.line", tied: false, par: 40,
            map: Array(repeating: sky, count: 6) + [
                "..a.............",
                "###.............",
                "...213.......aF.",
                "######======####",
            ],
            script: [
                .walk(1, 3.4), .climb(0, onto: 1), .hop(0, 1.5), .walk(0, 2.5),
                .walk(1, 13.5), .walk(2, 14.9), .walk(0, 14.2),
            ]),
        TetherPalsLevel(
            number: 7, name: "Tied together", tip: "You're tied together. Stay close and jump the gaps one at a time.",
            icon: "link", tied: true, par: 30,
            map: Array(repeating: sky, count: 5) + [
                "213........#.F..",
            ] + Array(repeating: "######..########", count: 4),
            script: [
                .gather(5.4), .hop(0, 8.6), .walk(1, 5.4), .hop(1, 8.4), .walk(2, 5.4), .hop(2, 8.2),
                .gather(10.5), .hop(0, 11.5), .hop(1, 11.5), .hop(2, 11.5),
                .gather(14.2),
            ]),
        TetherPalsLevel(
            number: 8, name: "Haul away", tip: "Climb up, then walk away from the edge to pull your pal up after you.",
            icon: "arrow.up.circle.fill", tied: true, par: 35,
            map: Array(repeating: sky, count: 3) + [
                ".............F..",
                "..........######",
                "213.......######",
            ] + Array(repeating: "################", count: 4),
            script: [
                .gather(9.6), .walk(1, 9.6), .climb(0, onto: 1), .hop(0, 11.0), .walk(0, 15.0),
                .wait(1.0), .gather(15.0),
            ]),
        TetherPalsLevel(
            number: 9, name: "Up and up", tip: "Two ledges. Climb, haul, and climb again.",
            icon: "stairs", tied: true, par: 45,
            map: Array(repeating: sky, count: 4) + [
                "..............F.",
                "..........######",
                "..........######",
                "....############",
                "213.############",
                "################",
            ],
            script: [
                .gather(3.6), .walk(1, 3.6), .climb(0, onto: 1), .hop(0, 5.5), .walk(0, 9.5),
                .wait(0.6), .gather(9.6), .walk(1, 9.6), .climb(0, onto: 1), .hop(0, 11.5),
                .walk(0, 15.4), .wait(0.8), .gather(15.4),
            ]),
        TetherPalsLevel(
            number: 10, name: "Rope and doors", tip: "Hold the door for your pals, then haul them up the ledge.",
            icon: "link.circle.fill", tied: true, par: 50,
            map: Array(repeating: ".......#........", count: 6) + [
                ".......A......F.",
                ".......A...#####",
                "213...aAa..#####",
                "################",
            ],
            script: [
                .walk(1, 6.5), .walk(0, 8.5), .walk(2, 9.4), .walk(1, 10.6), .walk(2, 10.0),
                .climb(0, onto: 1), .hop(0, 12.5), .walk(0, 15.4), .wait(0.8), .gather(15.4),
            ]),
        TetherPalsLevel(
            number: 11, name: "Two keys", tip: "Gold buttons work gold things, blue buttons blue things.",
            icon: "key.fill", tied: false, par: 50,
            map: Array(repeating: sky, count: 7) + [
                "............B...",
                "213........aB.bF",
                "######====######",
            ],
            script: [
                .walk(1, 5.6), .climb(0, onto: 1), .hop(0, 10.8), .walk(0, 11.5),
                .walk(1, 11.6), .walk(2, 11.0),
                .climb(0, onto: 1), .hop(0, 14.5), .walk(1, 15.4), .walk(2, 15.0),
            ]),
        TetherPalsLevel(
            number: 12, name: "All together now", tip: "Everything you've learned, tied together.",
            icon: "star.fill", tied: true, par: 60,
            map: Array(repeating: "....#...........", count: 4) + [
                "....A.........F.",
                "....A......#####",
                "213aAa.....#####",
            ] + Array(repeating: "########..######", count: 3),
            script: [
                .walk(1, 3.5), .walk(0, 5.5), .walk(2, 6.6), .walk(1, 6.9),
                .walk(0, 7.5), .hop(0, 10.5), .walk(1, 7.5), .hop(1, 10.5), .walk(2, 7.5), .hop(2, 10.5),
                .walk(1, 10.6), .climb(0, onto: 1), .hop(0, 12.5), .walk(0, 15.4), .wait(0.8), .gather(15.4),
            ]),
    ]
}
