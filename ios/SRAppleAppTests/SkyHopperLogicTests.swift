import XCTest
@testable import SRAppleApp

final class SkyHopperLogicTests: XCTestCase {
    // MARK: - Helpers

    private func cloud(_ id: Int, _ kind: SkyHopperCloudKind = .plain, x: Double = 50, y: Double,
                       half: Double = 9, vx: Double = 0, phase: Double = 0, spring: Double? = nil,
                       onPath: Bool = false) -> SkyHopperCloud {
        SkyHopperCloud(id: id, kind: kind, x: x, y: y, halfWidth: half, vx: vx, phase: phase,
                       spring: spring, onPath: onPath)
    }

    /// Steps until a landing (or `limit` steps); the events of that step.
    @discardableResult
    private func stepUntilLanding(_ game: inout SkyHopperGame, steer: Double = 0, limit: Int = 600) -> SkyHopperEvents? {
        for _ in 0..<limit {
            let events = game.step(steer: steer)
            if !events.landings.isEmpty { return events }
            if game.isOver { return nil }
        }
        return nil
    }

    private func playToTheEnd(_ game: inout SkyHopperGame, limit: Int = 6000) {
        var n = 0
        while !game.isOver && n < limit {
            game.step(steer: 0)
            n += 1
        }
    }

    private func generate(seed: UInt64, to top: Double) -> [SkyHopperCloud] {
        var generator = SkyHopperGenerator(seed: seed)
        var clouds: [SkyHopperCloud] = []
        var pickups: [SkyHopperPickup] = []
        generator.start(clouds: &clouds, pickups: &pickups)
        generator.fill(upTo: top, clouds: &clouds, pickups: &pickups)
        while generator.pathY < top {
            generator.fill(upTo: top, clouds: &clouds, pickups: &pickups)
        }
        return clouds
    }

    // MARK: - Randomness and determinism

    func testRandomIsSeededAndInRange() {
        var a = SkyHopperRandom(seed: 42)
        var b = SkyHopperRandom(seed: 42)
        var c = SkyHopperRandom(seed: 43)
        var differs = false
        for _ in 0..<500 {
            let x = a.unit()
            XCTAssertEqual(x, b.unit())
            if x != c.unit() { differs = true }
            XCTAssertGreaterThanOrEqual(x, 0)
            XCTAssertLessThan(x, 1)
            let d = a.double(in: 3...7)
            _ = b.double(in: 3...7)
            XCTAssertTrue((3...7).contains(d))
            let n = a.below(5)
            _ = b.below(5)
            XCTAssertTrue((0..<5).contains(n))
        }
        XCTAssertTrue(differs)
    }

    func testSameSeedSameSky() {
        var a = SkyHopperGame(seed: 7)
        var b = SkyHopperGame(seed: 7)
        for _ in 0..<3000 {
            a.step(steer: SkyHopperAutopilot.steer(for: a))
            b.step(steer: SkyHopperAutopilot.steer(for: b))
        }
        XCTAssertEqual(a, b)
        XCTAssertGreaterThan(a.climb, 300)
    }

    func testDifferentSeedsLayDifferentSkies() {
        let a = SkyHopperGame(seed: 1).clouds.map(\.x)
        let b = SkyHopperGame(seed: 2).clouds.map(\.x)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Bouncing

    func testHopBouncesOffTheHomeCloudAtOnce() {
        var game = SkyHopperGame(seed: 3)
        XCTAssertTrue(game.clouds.contains { $0.home && $0.halfWidth == SkyHopperRules.width / 2 })
        let events = stepUntilLanding(&game, limit: 3)
        XCTAssertNotNil(events)
        XCTAssertEqual(game.hopper.vy, SkyHopperRules.bounce, accuracy: 0.001)
        XCTAssertEqual(game.bounces, 1)
        XCTAssertFalse(game.isOver)
    }

    func testCloudsAreLandedOnOnlyFromAbove() {
        var game = SkyHopperGame(hopper: SkyHopperHopper(x: 50, y: 10, vx: 0, vy: SkyHopperRules.bounce),
                                 clouds: [cloud(1, y: 30)])
        var highest = game.hopper.y
        var landing: SkyHopperEvents?
        for _ in 0..<400 {
            let events = game.step(steer: 0)
            if !events.landings.isEmpty {
                landing = events
                break
            }
            highest = max(highest, game.hopper.y)
        }
        // Up through the cloud to the top of the bounce, then down onto it.
        XCTAssertGreaterThan(highest, 50)
        XCTAssertEqual(landing?.landings.first?.y, 30)
        XCTAssertEqual(game.hopper.y, 30)
        XCTAssertEqual(game.hopper.vy, SkyHopperRules.bounce, accuracy: 0.001)
    }

    func testASpringLaunchesFarHigherButOnlyOnTheSpring() {
        var onSpring = SkyHopperGame(hopper: SkyHopperHopper(x: 50, y: 4), clouds: [cloud(1, y: 0, spring: 0)])
        let events = stepUntilLanding(&onSpring)
        XCTAssertEqual(events?.landings.first?.spring, true)
        XCTAssertEqual(onSpring.hopper.vy, SkyHopperRules.springBounce, accuracy: 0.001)
        XCTAssertEqual(onSpring.springs, 1)
        XCTAssertGreaterThan(SkyHopperRules.springHeight, SkyHopperRules.bounceHeight * 2.5)

        var beside = SkyHopperGame(hopper: SkyHopperHopper(x: 57.5, y: 4), clouds: [cloud(1, y: 0, spring: 0)])
        let plain = stepUntilLanding(&beside)
        XCTAssertEqual(plain?.landings.first?.spring, false)
        XCTAssertEqual(beside.hopper.vy, SkyHopperRules.bounce, accuracy: 0.001)
        XCTAssertEqual(beside.springs, 0)
    }

    func testMissingTheCloudSideways() {
        // 9 half-width plus 3 slack: 13 units off is a miss.
        var game = SkyHopperGame(hopper: SkyHopperHopper(x: 63, y: 4), clouds: [cloud(1, y: 0)])
        XCTAssertNil(stepUntilLanding(&game))
        XCTAssertTrue(game.isOver)
        XCTAssertEqual(game.fall, .missed)
    }

    func testTheSidesWrapRound() {
        var game = SkyHopperGame(hopper: SkyHopperHopper(x: 99, y: 0, vx: SkyHopperRules.topSpeed, vy: 0),
                                 clouds: [cloud(1, y: 0, half: 50)])
        for _ in 0..<6 { game.step(steer: 1) }
        XCTAssertLessThan(game.hopper.x, 10)
        XCTAssertGreaterThanOrEqual(game.hopper.x, 0)
        XCTAssertEqual(SkyHopperRules.wrapDelta(from: 98, to: 2), 4, accuracy: 1e-9)
        XCTAssertEqual(SkyHopperRules.wrapDelta(from: 2, to: 98), -4, accuracy: 1e-9)
        XCTAssertEqual(SkyHopperRules.wrap(-3), 97, accuracy: 1e-9)
    }

    func testSteeringIsCappedAtTopSpeed() {
        var game = SkyHopperGame(hopper: SkyHopperHopper(x: 50, y: 0), clouds: [cloud(1, y: 0, half: 50)])
        for _ in 0..<240 { game.step(steer: 5) }
        XCTAssertLessThanOrEqual(game.hopper.vx, SkyHopperRules.topSpeed + 1e-9)
        XCTAssertGreaterThan(game.hopper.vx, SkyHopperRules.topSpeed * 0.95)
        for _ in 0..<240 { game.step(steer: .nan) }
        XCTAssertEqual(game.hopper.vx, 0, accuracy: 1)
    }

    // MARK: - Cloud kinds

    func testACrumblyCloudTakesOneBounce() {
        var game = SkyHopperGame(hopper: SkyHopperHopper(x: 50, y: 1), clouds: [cloud(1, .crumbly, y: 0)])
        XCTAssertNotNil(stepUntilLanding(&game))
        XCTAssertNotNil(game.clouds.first?.crumbledAt)
        playToTheEnd(&game)
        XCTAssertTrue(game.isOver)
        XCTAssertEqual(game.bounces, 1)
        XCTAssertEqual(game.fall, .crumbled)
    }

    func testABlinkingCloudIsSolidOnlyWhileItShows() {
        XCTAssertEqual(SkyHopperRules.blinkAlpha(time: 0, phase: 0), 1)
        XCTAssertEqual(SkyHopperRules.blinkAlpha(time: 2.5, phase: 0), 0)
        XCTAssertEqual(SkyHopperRules.blinkAlpha(time: 0.5, phase: 2.0), 0)
        XCTAssertEqual(SkyHopperRules.blinkAlpha(time: 2.5 + SkyHopperRules.blinkPeriod, phase: 0), 0, accuracy: 1e-9)
        let showing = cloud(1, .blinking, y: 0, phase: 0)
        XCTAssertTrue(showing.isSolid(at: 1))
        XCTAssertFalse(showing.isSolid(at: 2.5))

        // Gone as Hop arrives: straight through.
        var gone = SkyHopperGame(hopper: SkyHopperHopper(x: 50, y: 0.5), clouds: [cloud(1, .blinking, y: 0, phase: 2.45)])
        XCTAssertNil(stepUntilLanding(&gone))
        XCTAssertEqual(gone.fall, .blinked)

        // There as Hop arrives: a bounce.
        var there = SkyHopperGame(hopper: SkyHopperHopper(x: 50, y: 0.5), clouds: [cloud(1, .blinking, y: 0, phase: 0)])
        XCTAssertNotNil(stepUntilLanding(&there))
    }

    func testASlidingCloudGlidesAndTurnsAtTheSides() {
        let sliding = cloud(2, .sliding, x: 80, y: 300, half: 9, vx: 30)
        let predicted = sliding.x(after: 1.0)
        var game = SkyHopperGame(hopper: SkyHopperHopper(x: 50, y: 0), clouds: [cloud(1, y: 0, half: 50), sliding])
        var lowest = 100.0, highest = 0.0
        for _ in 0..<120 {
            game.step(steer: 0)
            if let c = game.clouds.first(where: { $0.id == 2 }) {
                lowest = min(lowest, c.x)
                highest = max(highest, c.x)
            }
        }
        let after = game.clouds.first { $0.id == 2 }
        XCTAssertNotNil(after)
        // 80 + 30 hits the side at 91 and comes back to 72.
        XCTAssertEqual(predicted, 72, accuracy: 0.01)
        XCTAssertEqual(after?.x ?? 0, predicted, accuracy: 0.5)
        XCTAssertLessThan(after?.vx ?? 0, 0)
        XCTAssertLessThanOrEqual(highest, 91 + 1e-9)
        XCTAssertGreaterThanOrEqual(lowest, 9)
    }

    // MARK: - Stars and power-ups

    func testStarsAddToTheScore() {
        let star = SkyHopperPickup(id: 9, kind: .star, x: 50, y: 104.5)
        var game = SkyHopperGame(hopper: SkyHopperHopper(x: 50, y: 100), clouds: [cloud(1, y: 100)], pickups: [star])
        let events = game.step(steer: 0)
        XCTAssertEqual(events.grabs.map(\.kind), [.star])
        XCTAssertEqual(game.stars, 1)
        XCTAssertTrue(game.pickups.isEmpty)
        XCTAssertEqual(game.metres, 20)
        XCTAssertEqual(game.score, 20 + SkyHopperRules.starPoints)
        XCTAssertEqual(SkyHopperRules.score(metres: 120, stars: 4), 140)
        XCTAssertEqual(SkyHopperRules.metres(climb: 99.9), 19)
        XCTAssertEqual(SkyHopperRules.metres(climb: -5), 0)
    }

    func testThePropellerCapLiftsWithoutLanding() {
        let cap = SkyHopperPickup(id: 9, kind: .propeller, x: 50, y: 64)
        var game = SkyHopperGame(hopper: SkyHopperHopper(x: 50, y: 60, vx: 0, vy: -50),
                                 clouds: [cloud(1, y: 58)], pickups: [cap])
        let first = game.step(steer: 0)
        XCTAssertEqual(first.grabs.map(\.kind), [.propeller])
        XCTAssertEqual(game.powerUps, 1)
        var landed = false
        var ended = false
        for _ in 0..<Int(SkyHopperRules.propellerTime * 120) + 4 {
            let events = game.step(steer: 0)
            landed = landed || !events.landings.isEmpty
            ended = ended || events.propellerEnded
        }
        XCTAssertFalse(landed)
        XCTAssertTrue(ended)
        XCTAssertEqual(game.propellerLeft, 0)
        XCTAssertGreaterThan(game.hopper.y, 60 + SkyHopperRules.propellerLift * (SkyHopperRules.propellerTime - 0.1))
    }

    func testTheMagnetPullsStarsIn() {
        let far = SkyHopperPickup(id: 9, kind: .star, x: 80, y: 5)
        var plain = SkyHopperGame(hopper: SkyHopperHopper(x: 50, y: 0), clouds: [cloud(1, y: 0, half: 50)], pickups: [far])
        for _ in 0..<60 { plain.step(steer: 0) }
        XCTAssertEqual(plain.stars, 0)

        var pulled = SkyHopperGame(hopper: SkyHopperHopper(x: 50, y: 0), clouds: [cloud(1, y: 0, half: 50)], pickups: [far])
        pulled.grant(.magnet)
        XCTAssertGreaterThan(pulled.magnetLeft, 0)
        for _ in 0..<60 { pulled.step(steer: 0) }
        XCTAssertEqual(pulled.stars, 1)
    }

    // MARK: - The end of a run

    func testFallingOffTheBottomEndsTheRun() {
        var game = SkyHopperGame(hopper: SkyHopperHopper(x: 50, y: 50), clouds: [])
        var fell = false
        for _ in 0..<2000 where !game.isOver {
            fell = game.step(steer: 0).fell
        }
        XCTAssertTrue(game.isOver)
        XCTAssertTrue(fell)
        XCTAssertEqual(game.fall, .missed)
        XCTAssertLessThan(game.hopper.y + SkyHopperRules.hopperHeight, game.cameraY)
        let time = game.time
        XCTAssertTrue(game.step(steer: 1).isEmpty)
        XCTAssertEqual(game.time, time)
    }

    func testABubbleSavesOneFall() {
        var game = SkyHopperGame(hopper: SkyHopperHopper(x: 50, y: 50), clouds: [])
        game.grant(.bubble)
        XCTAssertTrue(game.hasBubble)
        var saved = false
        for _ in 0..<2000 where !saved {
            saved = game.step(steer: 0).saved
        }
        XCTAssertTrue(saved)
        XCTAssertFalse(game.isOver)
        XCTAssertFalse(game.hasBubble)
        XCTAssertEqual(game.saves, 1)
        XCTAssertEqual(game.hopper.vy, SkyHopperRules.springBounce, accuracy: 0.001)
        playToTheEnd(&game)
        XCTAssertTrue(game.isOver)
        XCTAssertEqual(game.fall, .launched)
    }

    func testTheCameraNeverComesDownAndHopStaysInView() {
        var game = SkyHopperGame(seed: 11, viewHeight: 150)
        var camera = game.cameraY
        for _ in 0..<4000 where !game.isOver {
            game.step(steer: SkyHopperAutopilot.steer(for: game))
            XCTAssertGreaterThanOrEqual(game.cameraY, camera)
            XCTAssertLessThan(game.hopper.y, game.cameraY + game.viewHeight)
            camera = game.cameraY
        }
        XCTAssertGreaterThan(game.cameraY, 200)
        // Clouds below the window are let go of, so the sky never piles up.
        XCTAssertLessThan(game.clouds.count, 40)
        XCTAssertTrue(game.clouds.allSatisfy { $0.y >= game.cameraY - 40 })
    }

    func testTheViewIsClamped() {
        var game = SkyHopperGame(seed: 1, viewHeight: 20)
        XCTAssertEqual(game.viewHeight, SkyHopperRules.viewHeights.lowerBound)
        game.resize(viewHeight: 900)
        XCTAssertEqual(game.viewHeight, SkyHopperRules.viewHeights.upperBound)
        // More sky to show: it is laid out at once.
        XCTAssertTrue(game.clouds.contains { $0.y > game.viewHeight })
    }

    // MARK: - Zones and difficulty

    func testZonesClimbInOrder() {
        XCTAssertEqual(SkyHopperZone.at(metres: 0), .meadow)
        XCTAssertEqual(SkyHopperZone.at(metres: 149), .meadow)
        XCTAssertEqual(SkyHopperZone.at(metres: 150), .breeze)
        XCTAssertEqual(SkyHopperZone.at(metres: 5000), .space)
        let starts = SkyHopperZone.allCases.map(\.metres)
        XCTAssertEqual(starts, starts.sorted())
        XCTAssertEqual(Set(SkyHopperZone.allCases.map(\.name)).count, SkyHopperZone.allCases.count)
        XCTAssertNil(SkyHopperZone.space.next)

        var game = SkyHopperGame(hopper: SkyHopperHopper(x: 50, y: 740), clouds: [])
        game.grant(.propeller)
        var entered: SkyHopperZone?
        for _ in 0..<240 where entered == nil {
            entered = game.step(steer: 0).zone
        }
        XCTAssertEqual(entered, .breeze)
        XCTAssertEqual(game.zone, .breeze)
    }

    func testDifficultyRisesSteadilyAndStopsAtTheTop() {
        XCTAssertEqual(SkyHopperRules.difficulty(climb: -10), 0)
        XCTAssertEqual(SkyHopperRules.difficulty(climb: 1_000_000), 1)
        var last = SkyHopperRules.gapRange(difficulty: 0)
        var lastSlide = SkyHopperRules.slideChance(difficulty: 0)
        var lastPower = SkyHopperRules.powerUpChance(difficulty: 0)
        for step in 1...20 {
            let d = Double(step) / 20
            let range = SkyHopperRules.gapRange(difficulty: d)
            XCTAssertGreaterThanOrEqual(range.lowerBound, last.lowerBound)
            XCTAssertGreaterThanOrEqual(range.upperBound, last.upperBound)
            XCTAssertLessThanOrEqual(range.upperBound, SkyHopperRules.fairGap)
            XCTAssertGreaterThanOrEqual(SkyHopperRules.slideChance(difficulty: d), lastSlide)
            XCTAssertLessThanOrEqual(SkyHopperRules.powerUpChance(difficulty: d), lastPower)
            XCTAssertGreaterThan(SkyHopperRules.powerUpChance(difficulty: d), 0)
            last = range
            lastSlide = SkyHopperRules.slideChance(difficulty: d)
            lastPower = SkyHopperRules.powerUpChance(difficulty: d)
        }
        XCTAssertEqual(SkyHopperRules.gapRange(difficulty: 3), SkyHopperRules.gapRange(difficulty: 1))
    }

    // MARK: - Fairness

    func testTheBiggestGapCanBeCrossedFromAnywhere() throws {
        XCTAssertLessThan(SkyHopperRules.fairGap, SkyHopperRules.bounceHeight - 3)
        let time = try XCTUnwrap(SkyHopperRules.airTime(height: SkyHopperRules.fairGap))
        // Half the wrapping sky is the furthest any cloud can be, even
        // starting at full speed the wrong way.
        XCTAssertGreaterThanOrEqual(SkyHopperRules.reach(time: time), SkyHopperRules.width / 2)
        XCTAssertNil(SkyHopperRules.airTime(height: SkyHopperRules.bounceHeight + 1))
    }

    func testEveryCloudHasTheWayUpWithinReachEvenWhenCrumblyOnesGo() {
        for seed in UInt64(1)...40 {
            let clouds = generate(seed: seed, to: 8000)
            let path = clouds.filter(\.onPath).sorted { $0.y < $1.y }
            XCTAssertGreaterThan(path.count, 150)
            XCTAssertFalse(path.contains { $0.kind == .blinking }, "seed \(seed): a blinking path cloud")
            for (a, b) in zip(path, path.dropFirst()) {
                XCTAssertLessThanOrEqual(b.y - a.y, SkyHopperRules.fairGap + 1e-9, "seed \(seed) at \(a.y)")
                XCTAssertFalse(a.kind == .crumbly && b.kind == .crumbly, "seed \(seed): two crumbly in a row")
            }
            let top = path.last { $0.kind != .crumbly }?.y ?? 0
            for c in clouds where c.y < top - 1 {
                let next = path.first { $0.y > c.y + 1e-9 && $0.kind != .crumbly }
                XCTAssertNotNil(next, "seed \(seed): nothing above \(c.y)")
                if let next {
                    XCTAssertLessThanOrEqual(next.y - c.y, SkyHopperRules.fairGap + 1e-9, "seed \(seed): stranded at \(c.y)")
                }
                XCTAssertGreaterThanOrEqual(c.x - c.halfWidth, -1e-9)
                XCTAssertLessThanOrEqual(c.x + c.halfWidth, SkyHopperRules.width + 1e-9)
            }
        }
    }

    func testTheFirstSpringAndPropellerCapComeEarly() {
        for seed in UInt64(1)...10 {
            let game = SkyHopperGame(seed: seed, viewHeight: 220)
            let path = game.clouds.filter { $0.onPath && !$0.home }.sorted { $0.y < $1.y }
            XCTAssertGreaterThanOrEqual(path.count, SkyHopperRules.firstPropellerIndex)
            XCTAssertNotNil(path[SkyHopperRules.firstSpringIndex - 1].spring, "seed \(seed)")
            let cap = game.pickups.first { $0.kind == .propeller }
            XCTAssertNotNil(cap, "seed \(seed)")
            XCTAssertLessThan(cap?.y ?? .infinity, 300)
            XCTAssertFalse(game.clouds.contains { $0.kind == .crumbly && $0.y < SkyHopperRules.crumblyFrom })
        }
    }

    func testTheAutopilotClimbsEverySeed() {
        for seed in UInt64(1)...20 {
            var game = SkyHopperGame(seed: seed)
            while !game.isOver && game.climb < 4000 && game.time < 300 {
                game.step(steer: SkyHopperAutopilot.steer(for: game))
            }
            XCTAssertFalse(game.isOver, "seed \(seed) fell at \(game.metres) m")
            XCTAssertGreaterThanOrEqual(game.climb, 4000, "seed \(seed) stuck at \(game.metres) m")
            XCTAssertGreaterThan(game.stars, 0)
        }
    }

    func testTheDemoRunClimbsThenEnds() {
        var game = SkyHopperGame(seed: 7)
        while !game.isOver && game.time < 120 {
            game.step(steer: SkyHopperAutopilot.steer(for: game, giveUpAfter: 20))
        }
        XCTAssertTrue(game.isOver)
        XCTAssertGreaterThan(game.time, 20)
        XCTAssertLessThan(game.time, 60)
        XCTAssertGreaterThan(game.metres, 50)
        XCTAssertNotNil(game.fall)
    }

    func testEventsMerge() {
        var a = SkyHopperEvents()
        XCTAssertTrue(a.isEmpty)
        var b = SkyHopperEvents()
        b.grabs = [SkyHopperGrab(kind: .star, x: 1, y: 2)]
        b.zone = .sunset
        b.saved = true
        a.merge(b)
        XCTAssertFalse(a.isEmpty)
        XCTAssertEqual(a.grabs.count, 1)
        XCTAssertEqual(a.zone, .sunset)
        XCTAssertTrue(a.saved)
        XCTAssertFalse(a.fell)
    }
}
