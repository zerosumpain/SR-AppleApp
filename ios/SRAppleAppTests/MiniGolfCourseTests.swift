import XCTest
@testable import SRAppleApp

/// Mini Golf's eighteen holes: sound as data, windmills that can never pin a
/// ball, and every one of them playable — a brute-force search of putts finds
/// a way to hole out within par + 3 from the tee.
final class MiniGolfCourseTests: XCTestCase {
    func testEighteenHolesNumberedInOrder() {
        XCTAssertEqual(MiniGolfCourse.holes.count, 18)
        XCTAssertEqual(MiniGolfCourse.holes.map(\.number), Array(1...18))
        XCTAssertEqual(Set(MiniGolfCourse.holes.map(\.name)).count, 18, "every hole has its own name")
        XCTAssertEqual(MiniGolfLoop.front.par + MiniGolfLoop.back.par, MiniGolfLoop.full.par)
        XCTAssertEqual(MiniGolfLoop.full.par, MiniGolfCourse.par)
    }

    func testTeesAndCupsAreOnDryFelt() {
        for hole in MiniGolfCourse.holes {
            XCTAssertTrue((2...5).contains(hole.par), "hole \(hole.number)")
            XCTAssertFalse(hole.tip.isEmpty, "hole \(hole.number)")
            for spot in [hole.tee, hole.cup] {
                XCTAssertTrue(hole.isOpen(spot), "hole \(hole.number)")
                XCTAssertFalse(hole.inWater(spot), "hole \(hole.number)")
                XCTAssertFalse(hole.inSand(spot), "hole \(hole.number)")
                XCTAssertFalse(hole.inSweep(spot), "hole \(hole.number)")
                for wall in hole.walls {
                    let gap = MiniGolfGeo.closest(wall.a, wall.b, to: spot).distance(to: spot)
                    XCTAssertGreaterThan(gap, MiniGolfRules.wallContact, "hole \(hole.number): \(spot) is against a wall")
                }
                for post in hole.posts {
                    XCTAssertGreaterThan(spot.distance(to: post.centre), post.radius + MiniGolfRules.ballRadius, "hole \(hole.number)")
                }
            }
            XCTAssertGreaterThan(hole.tee.distance(to: hole.cup), 20, "hole \(hole.number) is a real putt")
        }
    }

    /// The escalation the course promises: each feature turns up somewhere.
    func testEveryFeatureIsOnTheCourse() {
        let holes = MiniGolfCourse.holes
        XCTAssertTrue(holes.contains { $0.slopes.contains { if case .tilt = $0.shape { return true } else { return false } } })
        XCTAssertTrue(holes.contains { $0.slopes.contains { if case .mound = $0.shape { return true } else { return false } } })
        XCTAssertTrue(holes.contains { !$0.sand.isEmpty })
        XCTAssertTrue(holes.contains { !$0.water.isEmpty && !$0.bridges.isEmpty })
        XCTAssertTrue(holes.contains { $0.posts.contains { $0.kind == .bumper } })
        XCTAssertTrue(holes.contains { !$0.windmills.isEmpty })
        XCTAssertTrue(holes.contains { !$0.rails.isEmpty })
        // The first two holes are plain putts.
        for hole in holes.prefix(2) {
            XCTAssertTrue(hole.slopes.isEmpty && hole.water.isEmpty && hole.windmills.isEmpty && hole.posts.isEmpty)
        }
    }

    /// A sail sweeping a ball into a wall would squash it through: so no wall
    /// comes within a sail's reach plus a whole ball of any windmill.
    func testWindmillSweepsAreClearOfWalls() {
        for hole in MiniGolfCourse.holes {
            for mill in hole.windmills {
                let clear = mill.arm + MiniGolfRules.armHalf + 2 * MiniGolfRules.ballRadius
                for wall in hole.walls {
                    let gap = MiniGolfGeo.closest(wall.a, wall.b, to: mill.pivot).distance(to: mill.pivot)
                    XCTAssertGreaterThan(gap - MiniGolfRules.wallHalf, clear, "hole \(hole.number)")
                }
                for post in hole.posts {
                    XCTAssertGreaterThan(post.centre.distance(to: mill.pivot) - post.radius, clear, "hole \(hole.number)")
                }
                XCTAssertTrue(hole.isOpen(mill.pivot), "hole \(hole.number)")
            }
        }
    }

    /// Every hole can be holed within par + 3, found by trying putts.
    ///
    /// A beam search: from each resting spot it tries every direction round
    /// the compass (and a few straight at the cup) at a dozen strengths, keeps
    /// the few spots that end nearest the cup by the walking distance round the
    /// walls (not over them, and not through water), and goes again.
    func testEveryHoleCanBeHoledWithinParPlusThree() {
        for hole in MiniGolfCourse.holes {
            let strokes = MiniGolfSolver.solve(hole)
            XCTAssertNotNil(strokes, "hole \(hole.number) \(hole.name) could not be holed within par + 3")
            if let strokes { XCTAssertLessThanOrEqual(strokes, hole.par + 3, "hole \(hole.number)") }
        }
    }
}

/// A brute-force golfer for the course test.
enum MiniGolfSolver {
    /// The fewest strokes the search found to hole out, or nil if none within par + 3.
    static func solve(_ hole: MiniGolfHole, beam width: Int = 3) -> Int? {
        let field = MiniGolfWalkField(hole)
        var beam = [MiniGolfBallSim(hole: hole)]
        var events: [MiniGolfEvent] = []
        let powers = stride(from: 0.08, through: 1.0001, by: 0.08).map { $0 }
        for depth in 1...(hole.par + 3) {
            var landed: [(Double, MiniGolfBallSim)] = []
            for start in beam {
                var angles = (0..<40).map { Double($0) / 40 * 2 * .pi }
                let direct = (hole.cup - start.position).angle
                angles += [-0.06, -0.03, 0, 0.03, 0.06].map { direct + $0 }
                for angle in angles {
                    for power in powers {
                        var sim = start
                        sim.putt(angle: angle, power: power)
                        sim.finishShot(events: &events)
                        events.removeAll(keepingCapacity: true)
                        if sim.state == .holed { return depth }
                        // A splash costs a stroke and goes nowhere: not worth keeping.
                        guard sim.state == .resting else { continue }
                        landed.append((field.distance(at: sim.position), sim))
                    }
                }
            }
            landed.sort { $0.0 < $1.0 }
            var kept: [MiniGolfBallSim] = []
            for (_, sim) in landed where !kept.contains(where: { $0.position.distance(to: sim.position) < 1.5 }) {
                kept.append(sim)
                if kept.count == width { break }
            }
            if kept.isEmpty { return nil }
            beam = kept
        }
        return nil
    }
}

/// How far each spot on a hole is from the cup, walking round the walls and
/// the water: a flood over a half-unit grid.
struct MiniGolfWalkField {
    let hole: MiniGolfHole
    let cell = 0.5
    let nx: Int
    let ny: Int
    private var steps: [Double]

    init(_ hole: MiniGolfHole) {
        self.hole = hole
        let b = hole.bounds
        nx = Int((b.width / cell).rounded(.up)) + 1
        ny = Int((b.height / cell).rounded(.up)) + 1
        var open = [Bool](repeating: false, count: nx * ny)
        for j in 0..<ny {
            for i in 0..<nx {
                let p = MiniGolfVec(b.minX + Double(i) * cell, b.minY + Double(j) * cell)
                open[j * nx + i] = hole.isOpen(p) && !hole.inWater(p)
            }
        }
        steps = [Double](repeating: .infinity, count: nx * ny)
        let ci = Int(((hole.cup.x - b.minX) / cell).rounded()), cj = Int(((hole.cup.y - b.minY) / cell).rounded())
        steps[cj * nx + ci] = 0
        var queue = [cj * nx + ci]
        var queued = [Bool](repeating: false, count: nx * ny)
        queued[cj * nx + ci] = true
        var head = 0
        let moves: [(Int, Int, Double)] = [(1, 0, 1), (-1, 0, 1), (0, 1, 1), (0, -1, 1),
                                           (1, 1, 1.414), (1, -1, 1.414), (-1, 1, 1.414), (-1, -1, 1.414)]
        while head < queue.count {
            let here = queue[head]
            head += 1
            queued[here] = false
            let i = here % nx, j = here / nx
            for (di, dj, w) in moves {
                let a = i + di, c = j + dj
                guard a >= 0, a < nx, c >= 0, c < ny else { continue }
                let there = c * nx + a
                guard open[there] else { continue }
                let d = steps[here] + w * cell
                if d < steps[there] - 1e-9 {
                    steps[there] = d
                    if !queued[there] {
                        queued[there] = true
                        queue.append(there)
                    }
                }
            }
        }
    }

    func distance(at p: MiniGolfVec) -> Double {
        let b = hole.bounds
        let i = Int(((p.x - b.minX) / cell).rounded()), j = Int(((p.y - b.minY) / cell).rounded())
        guard i >= 0, i < nx, j >= 0, j < ny else { return .infinity }
        return steps[j * nx + i]
    }
}
