import Foundation

/// Which holes a round plays.
enum MiniGolfLoop: String, CaseIterable, Identifiable, Codable {
    case front
    case back
    case full

    var id: String { rawValue }

    var title: String {
        switch self {
        case .front: return "Front nine"
        case .back: return "Back nine"
        case .full: return "All eighteen"
        }
    }

    var line: String {
        switch self {
        case .front: return "Holes 1 to 9. Ramps, bunkers, bumpers, the windmill and the pond."
        case .back: return "Holes 10 to 18. Narrow bridges, a volcano, the bowl and the grand finale."
        case .full: return "The whole course, from the first putt to the last."
        }
    }

    /// The holes, by index into `MiniGolfCourse.holes`.
    var holeIndices: [Int] {
        switch self {
        case .front: return Array(0..<9)
        case .back: return Array(9..<18)
        case .full: return Array(0..<18)
        }
    }

    var par: Int { holeIndices.reduce(0) { $0 + MiniGolfCourse.holes[$1].par } }
}

/// The course: eighteen holes, each a little harder than the last. The first
/// two are plain putts; then slopes, sand, posts and bumpers arrive one at a
/// time, then the windmill, water and bridges, and the back nine mixes them.
///
/// Every hole is drawn inside a box about 30 units wide (a ball is 2 across)
/// with the tee at the bottom. The tests play every hole with a brute-force
/// search to prove it can be holed within par + 3, fire hundreds of random
/// putts to prove a ball never escapes, and check every windmill's sweep is
/// clear of the walls so a sail can never pin a ball.
enum MiniGolfCourse {
    static let holes: [MiniGolfHole] = [
        firstPutt, dogLeg, ramp, bunkers, bumperBounce, windmill, pond, camber, horseshoe,
        zigZag, tightrope, volcano, pinball, millRace, islandHop, bowl, hairpin, grandFinale,
    ]

    static var par: Int { holes.reduce(0) { $0 + $1.par } }

    private static func v(_ x: Double, _ y: Double) -> MiniGolfVec { MiniGolfVec(x, y) }
    private static func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> [MiniGolfVec] {
        MiniGolfGeo.rect(x, y, w, h)
    }
    private static func frame(_ w: Double, _ h: Double) -> [MiniGolfVec] { MiniGolfGeo.frame(0, 0, w, h) }

    // MARK: - Front nine

    static let firstPutt = MiniGolfHole(
        number: 1, name: "First Putt",
        tip: "Straight up the middle. Pull back further for a harder putt.",
        par: 2, tee: v(12, 44), cup: v(12, 9),
        boundary: frame(24, 52))

    static let dogLeg = MiniGolfHole(
        number: 2, name: "Dog-Leg",
        tip: "Round the corner. Bank it off the angled wall at the top.",
        par: 2, tee: v(7, 54), cup: v(28, 8),
        boundary: [v(0, 5), v(5, 0), v(34, 0), v(34, 16), v(14, 16), v(14, 60), v(0, 60)])

    static let ramp = MiniGolfHole(
        number: 3, name: "The Ramp",
        tip: "Uphill all the way. Too soft and it rolls back to you.",
        par: 3, tee: v(12, 54), cup: v(12, 10),
        boundary: frame(24, 60),
        slopes: [MiniGolfSlope(rect(0, 26, 24, 12), .tilt(v(0, 34)))])

    static let bunkers = MiniGolfHole(
        number: 4, name: "Bunkers",
        tip: "Go round the post, and keep out of the sand: it stops a ball dead.",
        par: 3, tee: v(14, 52), cup: v(14, 8),
        boundary: frame(28, 58),
        posts: [MiniGolfPost(v(14, 31), 1.6)],
        sand: [
            [v(0, 24), v(8, 23), v(11, 28), v(8, 34), v(0, 35)],
            [v(28, 37), v(20, 38), v(17, 43), v(20, 48), v(28, 47)],
            [v(4, 13), v(10.5, 13), v(11, 17), v(5, 19)],
            [v(24, 13), v(17.5, 13), v(17, 17), v(23, 19)],
        ])

    static let bumperBounce = MiniGolfHole(
        number: 5, name: "Bumper Bounce",
        tip: "The red bumpers kick back harder than you hit them.",
        par: 3, tee: v(15, 56), cup: v(15, 8),
        boundary: frame(30, 62),
        posts: [
            MiniGolfPost(v(15, 24), 2.4, .bumper),
            MiniGolfPost(v(8, 34), 2.0, .bumper),
            MiniGolfPost(v(22, 34), 2.0, .bumper),
            MiniGolfPost(v(15, 44), 2.0, .bumper),
        ])

    static let windmill = MiniGolfHole(
        number: 6, name: "The Windmill",
        tip: "Time it: go when the sails have passed, then through the gap in the hedge.",
        par: 3, tee: v(15.5, 66), cup: v(15.5, 9),
        boundary: frame(32, 72),
        blocks: [rect(0, 24, 12, 8), rect(19, 24, 13, 8)],
        windmills: [MiniGolfWindmill(v(20.5, 45), arm: 7, speed: 1.0)])

    static let pond = MiniGolfHole(
        number: 7, name: "The Pond",
        tip: "Over the bridge. Miss it and you're in the pond: a stroke, and back you go.",
        par: 3, tee: v(11, 63), cup: v(22, 10),
        boundary: frame(30, 72),
        water: [rect(0, 30, 30, 14)],
        bridges: [[v(8, 45.5), v(14, 45.5), v(22, 28.5), v(16, 28.5)]])

    static let camber = MiniGolfHole(
        number: 8, name: "Camber",
        tip: "The green leans right, towards the stream. Aim left of the flag.",
        par: 3, tee: v(12, 60), cup: v(12, 8),
        boundary: frame(30, 66),
        water: [rect(24, 18, 6, 30)],
        slopes: [MiniGolfSlope(rect(0, 14, 30, 38), .tilt(v(13, 0)))])

    /// An upside-down U: up the right, round the banked top, down the left.
    static let horseshoe: MiniGolfHole = {
        let c = v(18, 26)
        let outer = MiniGolfGeo.arc(c, 15, from: .pi, to: 2 * .pi, steps: 24)
        let inner = MiniGolfGeo.arc(c, 7, from: .pi, to: 2 * .pi, steps: 16)
        let boundary = [v(3, 60)] + outer + [v(33, 60)]
        let island = [v(11, 60)] + inner + [v(25, 60)]
        return MiniGolfHole(
            number: 9, name: "Horseshoe",
            tip: "The top is banked: hit it hard and the ball rides the outside wall round.",
            par: 3, tee: v(29, 54), cup: v(7, 52),
            boundary: boundary, blocks: [island],
            slopes: [
                MiniGolfSlope([v(3, 26)] + outer + [v(33, 26)], .mound(centre: c, strength: 30)),
                MiniGolfSlope(rect(3, 30, 8, 30), .tilt(v(0, -10))),
            ])
    }()

    // MARK: - Back nine

    static let zigZag = MiniGolfHole(
        number: 10, name: "Zig-Zag",
        tip: "Through the gap on the right, then the gap on the left.",
        par: 3, tee: v(7, 72), cup: v(22, 10),
        boundary: frame(30, 80),
        rails: [[v(0, 54), v(20, 54)], [v(10, 28), v(30, 28)]])

    static let tightrope = MiniGolfHole(
        number: 11, name: "Tightrope",
        tip: "A long, narrow bridge. Line it up carefully before you putt.",
        par: 3, tee: v(13, 74), cup: v(13, 9),
        boundary: frame(26, 82),
        water: [rect(0, 24, 26, 34)],
        bridges: [rect(11, 23, 4, 36)])

    static let volcano = MiniGolfHole(
        number: 12, name: "Volcano",
        tip: "The cup is on top of the hill. Just enough to climb, or it rolls straight back down.",
        par: 3, tee: v(16, 56), cup: v(16, 22),
        boundary: frame(32, 62),
        posts: [MiniGolfPost(v(7, 34), 1.5), MiniGolfPost(v(25, 34), 1.5)],
        slopes: [MiniGolfSlope(MiniGolfGeo.disc(v(16, 22), 7), .mound(centre: v(16, 22), strength: 34))])

    static let pinball = MiniGolfHole(
        number: 13, name: "Pinball",
        tip: "Five bumpers and two bunkers. Pick a gap and trust it.",
        par: 3, tee: v(16, 60), cup: v(16, 8),
        boundary: frame(32, 66),
        posts: [
            MiniGolfPost(v(10, 22), 2.0, .bumper),
            MiniGolfPost(v(22, 22), 2.0, .bumper),
            MiniGolfPost(v(16, 32), 2.0, .bumper),
            MiniGolfPost(v(8, 42), 2.0, .bumper),
            MiniGolfPost(v(24, 42), 2.0, .bumper),
        ],
        sand: [
            [v(3, 4), v(9, 4), v(9, 12), v(3, 14)],
            [v(29, 4), v(23, 4), v(23, 12), v(29, 14)],
        ])

    static let millRace = MiniGolfHole(
        number: 14, name: "Mill Race",
        tip: "A faster windmill, then the gap in the hedge. The top runs downhill to the stream.",
        par: 4, tee: v(8, 78), cup: v(16, 13),
        boundary: frame(32, 84),
        blocks: [rect(0, 36, 18, 8), rect(25, 36, 7, 8)],
        water: [rect(0, 0, 32, 4)],
        slopes: [MiniGolfSlope(rect(0, 4, 32, 30), .tilt(v(0, -14)))],
        windmills: [MiniGolfWindmill(v(14, 57), arm: 7.5, speed: 1.6, phase: 0.4)])

    static let islandHop = MiniGolfHole(
        number: 15, name: "Island Hop",
        tip: "Two ponds, two bridges, an island between. Take them one at a time.",
        par: 4, tee: v(16, 68), cup: v(16, 7),
        boundary: frame(32, 74),
        water: [rect(0, 44, 32, 12), rect(0, 16, 32, 12)],
        bridges: [rect(4, 43, 6, 14), rect(22, 15, 6, 14)])

    static let bowl = MiniGolfHole(
        number: 16, name: "The Bowl",
        tip: "Get past the hedge and into the bowl: it all runs down to the cup.",
        par: 3, tee: v(16, 58), cup: v(16, 16),
        boundary: frame(32, 66),
        blocks: [rect(10, 38, 12, 5)],
        posts: [MiniGolfPost(v(7, 30), 1.5), MiniGolfPost(v(25, 30), 1.5)],
        slopes: [MiniGolfSlope(MiniGolfGeo.disc(v(16, 16), 9), .mound(centre: v(16, 16), strength: -30))])

    /// The horseshoe the other way round, with a narrow bridge on the way down.
    static let hairpin: MiniGolfHole = {
        let c = v(18, 28)
        let outer = MiniGolfGeo.arc(c, 15, from: .pi, to: 2 * .pi, steps: 24)
        let inner = MiniGolfGeo.arc(c, 7, from: .pi, to: 2 * .pi, steps: 16)
        let boundary = [v(3, 72)] + outer + [v(33, 72)]
        let island = [v(11, 72)] + inner + [v(25, 72)]
        return MiniGolfHole(
            number: 17, name: "Hairpin",
            tip: "Ride the banked bend, then hug the right-hand wall over the bridge.",
            par: 4, tee: v(7, 66), cup: v(29, 64),
            boundary: boundary, blocks: [island],
            water: [rect(25, 40, 8, 10)],
            bridges: [rect(27.5, 39, 5.5, 12)],
            slopes: [
                MiniGolfSlope([v(3, 28)] + outer + [v(33, 28)], .mound(centre: c, strength: 30)),
                MiniGolfSlope(rect(25, 52, 8, 20), .tilt(v(0, -10))),
            ])
    }()

    static let grandFinale = MiniGolfHole(
        number: 18, name: "Grand Finale",
        tip: "Everything at once: sand, a ramp, the hedge, the windmill and the pond. Good luck.",
        par: 5, tee: v(17, 98), cup: v(11, 7),
        boundary: frame(34, 104),
        blocks: [rect(0, 48, 13, 6), rect(21, 48, 13, 6)],
        sand: [
            [v(2, 80), v(10, 80), v(11, 88), v(2, 89)],
            [v(32, 80), v(24, 80), v(23, 88), v(32, 89)],
        ],
        water: [rect(0, 14, 34, 12)],
        bridges: [rect(20, 13, 6, 14)],
        slopes: [MiniGolfSlope(rect(0, 64, 34, 9), .tilt(v(0, 36)))],
        windmills: [MiniGolfWindmill(v(11, 37), arm: 6.5, speed: -1.2)])
}
