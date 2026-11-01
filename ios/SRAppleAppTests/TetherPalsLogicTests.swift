import XCTest
@testable import SRAppleApp

/// The rules on small made-up screens: running, jumping, heads, the boost,
/// the rope, buttons and gates, pops, and the everyone-home rule.
final class TetherPalsLogicTests: XCTestCase {
    private let sky = "................"
    private let right = TetherPalsInput(left: false, right: true, jump: false)
    private let left = TetherPalsInput(left: true, right: false, jump: false)

    // MARK: - Running and jumping

    func testPalsDropOntoTheFloorAndRunAtRunSpeed() {
        var world = flatWorld()
        run(&world, 0.5)
        let start = world.pals[0]
        XCTAssertEqual(start.support, .ground)
        XCTAssertEqual(start.bottom, 9, accuracy: 1e-9)
        run(&world, 1, [right])
        XCTAssertEqual(world.pals[0].x - start.x, TetherPalsRules.runSpeed, accuracy: 0.05)
        XCTAssertEqual(world.pals[0].facing, 1)
    }

    func testAGroundJumpRisesAboutOneAndAHalfTiles() {
        var world = flatWorld()
        run(&world, 0.5)
        let peak = highest(&world, pal: 0, inputs: [TetherPalsInput(left: false, right: false, jump: true)])
        XCTAssertGreaterThan(peak, 1.45)
        XCTAssertLessThan(peak, 1.65)
    }

    func testAJumpClimbsAOneTileStep() {
        let map = mapWith(floorRow: "################", above: ["21....#........."])
        XCTAssertTrue(sweepReaches(map) { $0.support == .ground && abs($0.bottom - 8) < 1e-6 && $0.centreX > 6 && $0.centreX < 7.2 })
    }

    func testNoLonePalTopsATwoTileWall() {
        let map = mapWith(floorRow: "################", above: ["........##......", "21......##......"])
        XCTAssertFalse(sweepReaches(map) { $0.support.standing && $0.bottom <= 7 + 1e-6 })
    }

    func testNoLonePalCrossesAFourTilePit() {
        let map = mapWith(floorRow: "#####....#######", above: ["21.............."])
        XCTAssertFalse(sweepReaches(map) { $0.support.standing && $0.centreX > 9 })
    }

    func testAJumpPressedJustBeforeLandingStillHappens() {
        var world = flatWorld()
        run(&world, 0.5)
        run(&world, 0.3, [TetherPalsInput(left: false, right: false, jump: true)])
        // Falling now: press jump again a moment before touching down.
        var jumped = false
        var held = false
        for _ in 0..<240 {
            let nearFloor = world.pals[0].vy > 0 && world.pals[0].bottom > 8.9
            let input = TetherPalsInput(left: false, right: false, jump: nearFloor && !held ? true : held)
            if nearFloor { held = true }
            let events = world.step([input])
            if held && events.jumped.contains(0) { jumped = true }
        }
        XCTAssertTrue(jumped, "a jump pressed just before landing should go when the pal lands")
    }

    // MARK: - Heads

    func testWalkIntoAPalAndJumpToStandOnTheirHead() {
        var world = flatWorld()
        run(&world, 0.5)
        var pilot = TetherPalsAutopilot(script: [.climb(0, onto: 1)])
        play(&world, &pilot, seconds: 3)
        XCTAssertEqual(world.pals[0].support, .pal(1))
        XCTAssertEqual(world.pals[0].bottom, world.pals[1].y, accuracy: 1e-9)
        XCTAssertEqual(pilot.stalls, 0)
    }

    func testPalsPassEachOtherSideways() {
        var world = flatWorld()
        run(&world, 0.5)
        run(&world, 1, [left])
        XCTAssertLessThan(world.pals[0].centreX, world.pals[1].centreX, "Pip should have walked through Bo")
        XCTAssertEqual(world.pals[0].support, .ground)
    }

    func testACarrierWalksSlowerAndTakesItsRiderAlong() {
        var world = flatWorld()
        run(&world, 0.5)
        var pilot = TetherPalsAutopilot(script: [.climb(0, onto: 1)])
        play(&world, &pilot, seconds: 3)
        run(&world, 0.3)
        let carrier = world.pals[1].x, rider = world.pals[0].x
        run(&world, 0.5, [.none, right])
        let moved = world.pals[1].x - carrier
        XCTAssertEqual(moved, TetherPalsRules.runSpeed * TetherPalsRules.carryShare * 0.5, accuracy: 0.05)
        XCTAssertEqual(world.pals[0].x - rider, moved, accuracy: 1e-9)
        XCTAssertEqual(world.pals[0].support, .pal(1))
    }

    func testAJumpOffAHeadIsSpringier() {
        var world = flatWorld()
        run(&world, 0.5)
        var pilot = TetherPalsAutopilot(script: [.climb(0, onto: 1)])
        play(&world, &pilot, seconds: 3)
        run(&world, 0.3)
        let head = world.pals[0].bottom
        var peak = head
        var boosted = false
        for step in 0..<120 {
            let events = world.step([TetherPalsInput(left: false, right: false, jump: step < 2), .none])
            if events.boosted.contains(0) { boosted = true }
            peak = min(peak, world.pals[0].bottom)
        }
        XCTAssertTrue(boosted)
        XCTAssertGreaterThan(head - peak, 2.05)
        XCTAssertLessThan(head - peak, 2.3)
    }

    func testOffAHeadAPalClearsTheBigPitAndTheWall() {
        let pit = makeWorld(mapWith(floorRow: "#####....#######", above: ["21.............."]))
        var a = pit
        var pilotA = TetherPalsAutopilot(script: [.walk(1, 4.6), .climb(0, onto: 1), .hop(0, 11)])
        play(&a, &pilotA, seconds: 8)
        XCTAssertEqual(a.pals[0].support, .ground)
        XCTAssertGreaterThan(a.pals[0].centreX, 9)
        XCTAssertEqual(a.pops, 0)

        var b = makeWorld(mapWith(floorRow: "################", above: ["........##......", "21......##......"]))
        var pilotB = TetherPalsAutopilot(script: [.walk(1, 7.6), .climb(0, onto: 1), .hop(0, 9.5)])
        play(&b, &pilotB, seconds: 8)
        XCTAssertEqual(b.pals[0].support, .ground)
        XCTAssertEqual(b.pals[0].bottom, 7, accuracy: 1e-9)
    }

    // MARK: - Pops

    func testPricklesPopAPalBackToItsStart() {
        var world = makeWorld(mapWith(floorRow: "################", above: ["2.1.^..........."]))
        run(&world, 0.3)
        let spawn = world.pals[0].spawnX
        var popped = false, back = false
        for _ in 0..<240 {
            let events = world.step([right])
            if events.popped.contains(0) { popped = true }
            if events.respawned.contains(0) {
                back = true
                break
            }
        }
        XCTAssertTrue(popped)
        XCTAssertTrue(back)
        XCTAssertEqual(world.pals[0].x, spawn, accuracy: 1e-9)
        XCTAssertEqual(world.pops, 1)
        XCTAssertTrue(world.pals[1].active, "an untied pal stays where it is")
    }

    func testFallingOffTheBottomPops() {
        var world = makeWorld(mapWith(floorRow: "####............", above: ["21.............."]))
        var popped = false
        for _ in 0..<480 where !popped {
            popped = world.step([right]).popped.contains(0)
        }
        XCTAssertTrue(popped)
    }

    func testTiedPalsPopTogether() {
        var world = makeWorld(mapWith(floorRow: "################", above: ["21..^..........."]), tied: true)
        var both = false
        for _ in 0..<240 where !both {
            let events = world.step([right])
            both = events.popped.contains(0) && events.popped.contains(1)
        }
        XCTAssertTrue(both)
        XCTAssertEqual(world.pops, 1, "only the pal that touched the prickles counts")
    }

    // MARK: - The rope

    func testTheRopeDragsAStandingPalAlong() {
        var world = makeWorld(mapWith(floorRow: "################", above: ["21.............."]), tied: true)
        run(&world, 0.5)
        let bo = world.pals[1].x
        run(&world, 2, [right])
        XCTAssertGreaterThan(world.pals[1].x - bo, 1)
        XCTAssertLessThanOrEqual(world.ropeLength(0, 1), TetherPalsRules.rope + 0.01)
    }

    func testTheRopeHoldsAJumperBackFromAStandingPal() {
        var world = makeWorld(mapWith(floorRow: "################", above: ["2..1............"]), tied: true)
        run(&world, 0.5)
        let bo = world.pals[1].x
        var longest = 0.0
        world.step([TetherPalsInput(left: false, right: true, jump: true)])
        while !world.pals[0].support.standing && world.time < 5 {
            world.step([right])
            longest = max(longest, world.ropeLength(0, 1))
            // Once Pip lands both are standing and share the pull; until then Bo holds firm.
            if !world.pals[0].support.standing {
                XCTAssertEqual(world.pals[1].x, bo, accuracy: 1e-9, "a pal on the ground holds firm")
            }
        }
        XCTAssertLessThanOrEqual(longest, TetherPalsRules.rope + 0.01)
    }

    func testAPalInAPitDanglesAndIsHauledOut() {
        let map = ["..............F."] + Array(repeating: sky, count: 3)
            + ["......2.1......."] + Array(repeating: "######..########", count: 5)
        var world = makeWorld(map, tied: true)
        run(&world, 2)
        XCTAssertTrue(world.pals[1].active, "the rope holds Bo above the bottom")
        XCTAssertEqual(world.pals[1].support, .none)
        XCTAssertGreaterThan(world.pals[1].bottom, 6)
        XCTAssertEqual(world.pals[0].centreX, 8.5, accuracy: 1e-9, "Pip holds firm")
        run(&world, 2, [right])
        XCTAssertTrue(world.pals[1].support.standing)
        XCTAssertEqual(world.pals[1].bottom, 5, accuracy: 1e-9)
        XCTAssertGreaterThan(world.pals[1].centreX, 8)
        XCTAssertEqual(world.pops, 0)
    }

    func testWalkingAwayHaulsAPalUpALedge() {
        let map = Array(repeating: sky, count: 3) + [
            "...........1..F.",
            "..........######",
            ".........2######",
        ] + Array(repeating: "################", count: 4)
        var world = makeWorld(map, tied: true)
        run(&world, 0.5)
        run(&world, 2.5, [right])
        XCTAssertTrue(world.pals[1].support.standing)
        XCTAssertEqual(world.pals[1].bottom, 4, accuracy: 1e-9, "Bo is up on the ledge")
    }

    // MARK: - Buttons, doors and bridges

    func testADoorOpensOnlyWhileItsButtonIsHeld() {
        var world = makeWorld(mapWith(floorRow: "################", above: ["......A.........", "2...1aA........."]))
        XCTAssertTrue(world.isSolid(col: 6, row: 8))
        var pilot = TetherPalsAutopilot(script: [.walk(0, 5.5)])
        play(&world, &pilot, seconds: 2)
        XCTAssertTrue(pilot.finished)
        XCTAssertTrue(world.isPressed(.gold))
        XCTAssertFalse(world.isSolid(col: 6, row: 8))
        run(&world, 0.6, [left])
        XCTAssertFalse(world.isPressed(.gold))
        XCTAssertTrue(world.isSolid(col: 6, row: 8))
    }

    func testADoorNeverShutsOnAPal() {
        var world = makeWorld(mapWith(floorRow: "################", above: ["....1aA2........"]))
        // Pip holds the button; Bo walks into the doorway and stops there.
        var pilot = TetherPalsAutopilot(script: [.walk(0, 5.5), .walk(1, 6.5)])
        play(&world, &pilot, seconds: 4)
        XCTAssertTrue(pilot.finished)
        // Pip steps off the button: the door waits for Bo.
        run(&world, 0.6, [left])
        XCTAssertFalse(world.isPressed(.gold))
        XCTAssertFalse(world.isSolid(col: 6, row: 8))
        run(&world, 0.6, [.none, right])
        XCTAssertTrue(world.isSolid(col: 6, row: 8))
    }

    func testBridgesComeWithTheirButtonAndColoursKeepApart() {
        var world = makeWorld(mapWith(floorRow: "#####===########", above: ["...........B....", "2a1........B...."]))
        run(&world, 0.3)
        XCTAssertFalse(world.isSolid(col: 6, row: 9), "nobody is on a button yet")
        XCTAssertTrue(world.isSolid(col: 11, row: 8))
        var pilot = TetherPalsAutopilot(script: [.walk(0, 1.5)])
        play(&world, &pilot, seconds: 2)
        XCTAssertTrue(world.isPressed(.gold))
        XCTAssertFalse(world.isPressed(.blue))
        XCTAssertTrue(world.isSolid(col: 6, row: 9), "the gold bridge is out")
        XCTAssertTrue(world.isSolid(col: 11, row: 8), "a gold button leaves the blue door shut")
    }

    // MARK: - The flag

    func testEveryoneMustReachTheFlag() {
        var world = makeWorld(mapWith(floorRow: "################", above: ["..2.....1F......"]))
        run(&world, 1)
        XCTAssertTrue(world.home[0])
        XCTAssertFalse(world.won, "Bo is not there yet")
        var arrived = false
        for _ in 0..<480 where !world.won {
            if world.step([.none, right]).arrived.contains(1) { arrived = true }
        }
        XCTAssertTrue(arrived)
        XCTAssertTrue(world.won)
        let after = world.time
        world.step([right, right])
        XCTAssertEqual(world.time, after, "a won level stops")
    }

    // MARK: - Determinism and robustness

    func testSameInputsSameGame() {
        let level = TetherPalsCatalogue.level(12)
        var a = TetherPalsWorld(level: level, team: 3)
        var b = TetherPalsWorld(level: level, team: 3)
        var random = TetherPalsRandom(seed: 42)
        var inputs = Array(repeating: TetherPalsInput.none, count: 3)
        for step in 0..<3000 {
            if step % 15 == 0 { inputs = randomInputs(&random, count: 3) }
            a.step(inputs)
            b.step(inputs)
        }
        XCTAssertEqual(a, b)
    }

    func testMashingNeverLeavesTheScreenOrSticksInAWall() {
        var random = TetherPalsRandom(seed: 7)
        for level in TetherPalsCatalogue.all {
            for team in 2...3 {
                var world = TetherPalsWorld(level: level, team: team)
                var inputs = Array(repeating: TetherPalsInput.none, count: team)
                for step in 0..<(120 * 20) where !world.won {
                    if step % 15 == 0 { inputs = randomInputs(&random, count: team) }
                    world.step(inputs)
                    for pal in world.pals where pal.active {
                        XCTAssertTrue(pal.x.isFinite && pal.y.isFinite)
                        XCTAssertGreaterThanOrEqual(pal.x, -1e-6, "level \(level.number)")
                        XCTAssertLessThanOrEqual(pal.x + pal.size, Double(level.columns) + 1e-6, "level \(level.number)")
                        XCTAssertFalse(world.isSolid(col: Int(floor(pal.centreX)), row: Int(floor(pal.centreY))),
                                       "level \(level.number): a pal inside a wall")
                    }
                }
            }
        }
    }

    func testRopeSharesFollowWhoIsStanding() {
        XCTAssertEqual(TetherPalsWorld.shares(true, true).0, 0.5)
        XCTAssertEqual(TetherPalsWorld.shares(false, false).1, 0.5)
        XCTAssertEqual(TetherPalsWorld.shares(true, false).0, 0)
        XCTAssertEqual(TetherPalsWorld.shares(true, false).1, 1)
        XCTAssertEqual(TetherPalsWorld.shares(false, true).0, 1)
    }

    func testDescribeSaysWhereAPalIs() {
        var world = flatWorld()
        run(&world, 0.5)
        XCTAssertTrue(world.describe(0).hasPrefix("Pip is standing"))
        XCTAssertTrue(world.describe(1).contains("steps left of the flag"))
        var pilot = TetherPalsAutopilot(script: [.climb(0, onto: 1)])
        play(&world, &pilot, seconds: 3)
        XCTAssertTrue(world.describe(0).hasPrefix("Pip is on Bo's head"))
        XCTAssertEqual(world.describe(7), "")
    }

    // MARK: - Helpers

    private func mapWith(floorRow: String, above: [String]) -> [String] {
        ["..............F."] + Array(repeating: sky, count: 9 - above.count - 1) + above + [floorRow]
    }

    private func makeWorld(_ map: [String], tied: Bool = false, team: Int = 2) -> TetherPalsWorld {
        TetherPalsWorld(level: TetherPalsLevel(number: 99, name: "Test", tip: "", icon: "star", tied: tied, par: 60,
                                               map: map, script: []), team: team)
    }

    private func flatWorld() -> TetherPalsWorld {
        makeWorld(mapWith(floorRow: "################", above: ["......21........"]))
    }

    private func run(_ world: inout TetherPalsWorld, _ seconds: Double, _ inputs: [TetherPalsInput] = []) {
        for _ in 0..<Int((seconds / TetherPalsRules.step).rounded()) { world.step(inputs) }
    }

    private func play(_ world: inout TetherPalsWorld, _ pilot: inout TetherPalsAutopilot, seconds: Double) {
        for _ in 0..<Int((seconds / TetherPalsRules.step).rounded()) where !pilot.finished {
            world.step(pilot.inputs(for: world))
        }
    }

    /// How high a pal gets, in tiles above where it stood, holding `inputs` for one second.
    private func highest(_ world: inout TetherPalsWorld, pal: Int, inputs: [TetherPalsInput]) -> Double {
        let floor = world.pals[pal].bottom
        var top = floor
        for _ in 0..<120 {
            world.step(inputs)
            top = min(top, world.pals[pal].bottom)
        }
        return floor - top
    }

    /// Pip runs right from a standstill and jumps once, at every moment in
    /// turn; true if any of those runs ever meets `goal`. Bo stands at the far left.
    private func sweepReaches(_ map: [String], goal: (TetherPalsPal) -> Bool) -> Bool {
        for jumpAt in stride(from: 0, to: 240, by: 2) {
            var world = makeWorld(map)
            run(&world, 0.3)
            for step in 0..<480 {
                world.step([TetherPalsInput(left: false, right: true, jump: step == jumpAt)])
                if world.pals[0].active && goal(world.pals[0]) { return true }
            }
        }
        return false
    }

    private func randomInputs(_ random: inout TetherPalsRandom, count: Int) -> [TetherPalsInput] {
        (0..<count).map { _ in
            TetherPalsInput(left: random.unit() < 0.3, right: random.unit() < 0.4, jump: random.unit() < 0.2)
        }
    }
}
