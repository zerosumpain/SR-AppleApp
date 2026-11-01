import XCTest
@testable import SRAppleApp

/// The twelve levels (each proved finishable by its own walkthrough), the
/// records, the pad's buttons and the words on the HUD.
final class TetherPalsLevelsTests: XCTestCase {
    // MARK: - Levels

    func testEveryLevelIsWellFormed() {
        let levels = TetherPalsCatalogue.all
        XCTAssertEqual(levels.count, 12)
        XCTAssertEqual(Set(levels.map(\.name)).count, levels.count, "names are unique")
        for (index, level) in levels.enumerated() {
            XCTAssertEqual(level.number, index + 1)
            XCTAssertEqual(level.columns, TetherPalsRules.columns, level.name)
            XCTAssertEqual(level.rows, TetherPalsRules.rows, level.name)
            XCTAssertGreaterThan(level.par, 0)
            XCTAssertFalse(level.tip.isEmpty)
            XCTAssertFalse(level.script.isEmpty)
            XCTAssertEqual(level.tile(col: level.flag.col, row: level.flag.row), .empty, "\(level.name): the flag stands in the open")
            XCTAssertTrue(isFloor(level, below: level.flag), "\(level.name): the flag stands on the ground")
            for pal in 0..<TetherPalsRules.maxPals {
                let spawn = level.spawn(pal)
                XCTAssertEqual(level.tile(col: spawn.col, row: spawn.row), .empty, "\(level.name): pal \(pal) starts in the open")
                XCTAssertTrue(isFloor(level, below: spawn), "\(level.name): pal \(pal) starts on the ground")
            }
            for button in level.buttons {
                XCTAssertTrue(level.gates.contains { $0.channel == button.channel }, "\(level.name): every button works something")
            }
        }
    }

    func testTheTricksArriveInOrder() {
        let tied = TetherPalsCatalogue.all.filter(\.tied).map(\.number)
        XCTAssertEqual(tied.first, 7, "the rope comes after stacking and buttons")
        XCTAssertFalse(TetherPalsCatalogue.level(1).tied)
        XCTAssertTrue(TetherPalsCatalogue.level(1).buttons.isEmpty, "level one is plain running and jumping")
        XCTAssertTrue(TetherPalsCatalogue.level(11).uses(.blue))
        XCTAssertEqual(TetherPalsCatalogue.level(0).number, 1)
        XCTAssertEqual(TetherPalsCatalogue.level(99).number, 12)
    }

    func testEveryLevelIsFinishedByItsWalkthroughUnderPar() {
        for level in TetherPalsCatalogue.all {
            for team in 2...3 {
                let (world, pilot) = walk(level, team: team)
                XCTAssertTrue(world.won, "\(level.name) with \(team) pals is not finished by its walkthrough")
                XCTAssertEqual(pilot.stalls, 0, "\(level.name) with \(team) pals: a line of the walkthrough got stuck")
                XCTAssertEqual(world.pops, 0, "\(level.name) with \(team) pals: the walkthrough lost a pal")
                XCTAssertLessThan(world.time * 2.5, level.par, "\(level.name): par leaves room for real players")
            }
        }
    }

    func testTheWalkthroughIsTheSameEveryTime() {
        let level = TetherPalsCatalogue.level(10)
        let (a, _) = walk(level, team: 3)
        let (b, _) = walk(level, team: 3)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.steps, b.steps)
    }

    func testStackLevelsCannotBeRunAndJumpedAlone() {
        // Pip runs at the obstacle and jumps at every moment in turn; Bo stays at the start.
        for number in [2, 4, 5] {
            let level = TetherPalsCatalogue.level(number)
            var reached = false
            for jumpAt in stride(from: 0, to: 360, by: 3) where !reached {
                var world = TetherPalsWorld(level: level, team: 2)
                for step in 0..<720 where !reached {
                    world.step([TetherPalsInput(left: false, right: true, jump: step == jumpAt)])
                    reached = world.isInZone(world.pals[0]) || world.pals[0].centreX > Double(level.flag.col) - 3
                }
            }
            XCTAssertFalse(reached, "\(level.name) can be done by one pal alone")
        }
    }

    // MARK: - Records

    func testRecordsKeepTheBestAndOpenLevelsInOrder() {
        var records = TetherPalsRecords()
        XCTAssertEqual(records.unlocked, 1)
        XCTAssertFalse(records.isOpen(2))
        let first = records.record(level: 1, time: 30, pops: 2, players: .two)
        XCTAssertFalse(first.newBest, "a first clear is not a new best")
        XCTAssertEqual(first.opened, 2)
        XCTAssertFalse(first.star, "30 s is over level 1's par")
        XCTAssertEqual(records.unlocked, 2)
        let second = records.record(level: 1, time: 12, pops: 0, players: .solo)
        XCTAssertTrue(second.newBest)
        XCTAssertTrue(second.star)
        XCTAssertTrue(second.newStar)
        XCTAssertNil(second.opened)
        let slower = records.record(level: 1, time: 20, pops: 0, players: .solo)
        XCTAssertFalse(slower.newBest)
        XCTAssertEqual(slower.best, 12)
        XCTAssertFalse(slower.newStar)
        XCTAssertEqual(records.best(1), 12)
        XCTAssertEqual(records.clears, 3)
        XCTAssertEqual(records.pops, 2)
        XCTAssertEqual(records.stars, 1)
    }

    func testClearingEveryLevelSaysSo() {
        var records = TetherPalsRecords()
        var last: TetherPalsResult?
        for level in TetherPalsCatalogue.all { last = records.record(level: level.number, time: 99, pops: 0, players: .solo) }
        XCTAssertEqual(last?.allCleared, true)
        XCTAssertNil(last?.opened)
        XCTAssertEqual(records.unlocked, 12)
        XCTAssertEqual(records.stars, 0, "99 s is over every par")
    }

    func testTheStartLevelIsAlwaysOpen() {
        var records = TetherPalsRecords()
        records.level = 9
        XCTAssertEqual(records.startLevel, 1)
        records.record(level: 1, time: 10, pops: 0, players: .solo)
        records.level = 2
        XCTAssertEqual(records.startLevel, 2)
    }

    func testRecordsSurviveARoundTripAndAnOlderSave() throws {
        let suite = "tether-pals-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TetherPalsRecordStore(defaults: defaults)
        var records = store.load()
        XCTAssertEqual(records, TetherPalsRecords())
        records.record(level: 1, time: 14.5, pops: 1, players: .three)
        records.players = .three
        records.level = 2
        store.save(records)
        XCTAssertEqual(store.load(), records)
        // An older save with fewer fields still loads.
        defaults.set(Data(#"{"bestTimes":{"1":20.5,"2":31}}"#.utf8), forKey: TetherPalsRecordStore.key)
        let old = store.load()
        XCTAssertEqual(old.best(2), 31)
        XCTAssertEqual(old.players, .solo)
        XCTAssertEqual(old.unlocked, 3)
        // Rubbish starts afresh rather than failing.
        defaults.set(Data("nope".utf8), forKey: TetherPalsRecordStore.key)
        XCTAssertEqual(store.load(), TetherPalsRecords())
    }

    func testPlayersChooseTheTeamAndStrips() {
        XCTAssertEqual(TetherPalsPlayers.solo.team, 2)
        XCTAssertEqual(TetherPalsPlayers.solo.strips, 1)
        XCTAssertEqual(TetherPalsPlayers.two.team, 2)
        XCTAssertEqual(TetherPalsPlayers.three.team, 3)
        XCTAssertEqual(TetherPalsPlayers.three.strips, 3)
    }

    // MARK: - The pad

    func testPadZonesCoverEveryStripWithNoGaps() {
        let width = 340.0, height = 180.0
        for solo in [true, false] {
            let strips = solo ? 1 : 3
            var keys: [TetherPalsKey] = []
            for x in stride(from: 0.0, through: width, by: 1) {
                let hit = TetherPalsPadLayout.hit(x: x, y: 10, width: width, height: height, strips: strips, solo: solo)
                XCTAssertNotNil(hit)
                if let key = hit?.key, keys.last != key { keys.append(key) }
            }
            XCTAssertEqual(keys, solo ? [.left, .right, .swap, .jump] : [.left, .right, .jump])
        }
        XCTAssertEqual(TetherPalsPadLayout.hit(x: 10, y: 179, width: width, height: height, strips: 3, solo: false)?.player, 2)
        XCTAssertEqual(TetherPalsPadLayout.hit(x: 10, y: 61, width: width, height: height, strips: 3, solo: false)?.player, 1)
        XCTAssertNil(TetherPalsPadLayout.hit(x: -1, y: 10, width: width, height: height, strips: 3, solo: false))
        XCTAssertNil(TetherPalsPadLayout.hit(x: 10, y: 181, width: width, height: height, strips: 3, solo: false))
    }

    func testPadButtonsAreBigEnoughAndInsideThePad() {
        let buttons = TetherPalsPadLayout.buttons(width: 343, height: 156, strips: 3, solo: false)
        XCTAssertEqual(buttons.count, 9)
        for button in buttons {
            XCTAssertGreaterThanOrEqual(button.width, 44)
            XCTAssertGreaterThanOrEqual(button.height, 44)
            XCTAssertGreaterThanOrEqual(button.x, 0)
            XCTAssertLessThanOrEqual(button.x + button.width, 343)
            XCTAssertLessThanOrEqual(button.y + button.height, 156)
        }
        XCTAssertEqual(TetherPalsPadLayout.buttons(width: 343, height: 70, strips: 1, solo: true).map(\.key), [.left, .right, .swap, .jump])
    }

    func testFingersBecomeEachPlayersHolds() {
        let holds = TetherPalsPadLayout.holds([(0, .left), (0, .jump), (1, .right), (1, .swap), (5, .jump)], strips: 2)
        XCTAssertEqual(holds.count, 2)
        XCTAssertEqual(holds[0], TetherPalsHold(left: true, right: false, jump: true))
        XCTAssertEqual(holds[1], TetherPalsHold(left: false, right: true, jump: false))
        XCTAssertEqual(holds[1].input.direction, 1)
    }

    // MARK: - Words and numbers

    func testTimesReadAsMinutesSecondsAndTenths() {
        XCTAssertEqual(TetherPalsFormat.time(7.45), "0:07.4")
        XCTAssertEqual(TetherPalsFormat.time(62), "1:02.0")
        XCTAssertEqual(TetherPalsFormat.time(0), "0:00.0")
        XCTAssertEqual(TetherPalsFormat.time(nil), "–")
        XCTAssertEqual(TetherPalsFormat.time(-.infinity), "–")
        XCTAssertEqual(TetherPalsFormat.par(40), "0:40")
        XCTAssertEqual(TetherPalsFormat.par(65), "1:05")
        XCTAssertEqual(TetherPalsFormat.pops(0), "no pops")
        XCTAssertEqual(TetherPalsFormat.pops(1), "1 pop")
        XCTAssertEqual(TetherPalsFormat.pops(4), "4 pops")
        XCTAssertEqual(TetherPalsCast.name(2), "Kit")
        XCTAssertEqual(TetherPalsCast.name(5), "Pal 6")
    }

    func testRandomIsSeededAndInRange() {
        var a = TetherPalsRandom(seed: 9)
        var b = TetherPalsRandom(seed: 9)
        var c = TetherPalsRandom(seed: 10)
        var differs = false
        for _ in 0..<500 {
            let x = a.unit()
            XCTAssertEqual(x, b.unit())
            XCTAssertGreaterThanOrEqual(x, 0)
            XCTAssertLessThan(x, 1)
            if x != c.unit() { differs = true }
            let r = a.range(2, 5)
            _ = b.range(2, 5)
            XCTAssertTrue((2..<5).contains(r))
        }
        XCTAssertTrue(differs)
    }

    // MARK: - Helpers

    private func isFloor(_ level: TetherPalsLevel, below cell: TetherPalsCell) -> Bool {
        let world = TetherPalsWorld(level: level, team: 2)
        return world.isSolid(col: cell.col, row: cell.row + 1)
    }

    private func walk(_ level: TetherPalsLevel, team: Int) -> (TetherPalsWorld, TetherPalsAutopilot) {
        var world = TetherPalsWorld(level: level, team: team)
        var pilot = TetherPalsAutopilot(script: level.script)
        for _ in 0..<(120 * 90) where !world.won {
            world.step(pilot.inputs(for: world))
        }
        return (world, pilot)
    }
}
