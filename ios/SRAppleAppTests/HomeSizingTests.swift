import XCTest
@testable import SRAppleApp

/// Home's widgets: how big each is drawn, how they pack into rows, and the
/// Calendar tile's day.
///
/// Foundation only: `scripts/home-check.sh` runs this file on Linux too.
final class HomeSizingTests: XCTestCase {

    // MARK: - Adaptive size

    func testATileWithNothingToShowFoldsToASquare() {
        XCTAssertEqual(HomeSizing.resolve(chosen: .wide, allowed: [.square, .wide], adaptive: true, hasContent: false), .square)
        XCTAssertEqual(HomeSizing.resolve(chosen: .wide, allowed: [.square, .wide], adaptive: true, hasContent: true), .wide)
    }

    func testStillLoadingKeepsTheChoice() {
        XCTAssertEqual(HomeSizing.resolve(chosen: .wide, allowed: [.square, .wide], adaptive: true, hasContent: nil), .wide,
                       "a tile must not shrink on launch and grow a second later")
    }

    func testAFixedTileNeverFolds() {
        XCTAssertEqual(HomeSizing.resolve(chosen: .wide, allowed: [.square, .wide], adaptive: false, hasContent: false), .wide)
    }

    func testAChosenSquareStaysASquareWithContent() {
        XCTAssertEqual(HomeSizing.resolve(chosen: .square, allowed: [.square, .wide], adaptive: true, hasContent: true), .square)
    }

    func testAShortcutIsNeverFolded() {
        XCTAssertEqual(HomeSizing.resolve(chosen: .compact, allowed: [.compact, .square], adaptive: true, hasContent: false), .compact)
    }

    func testASizeTheTileDoesNotAllowFallsBackToItsFirst() {
        XCTAssertEqual(HomeSizing.resolve(chosen: .hero, allowed: [.square, .wide], adaptive: false, hasContent: true), .square)
    }

    func testAWideOnlyTileCannotFoldToASquareItDoesNotHave() {
        XCTAssertEqual(HomeSizing.resolve(chosen: .wide, allowed: [.wide], adaptive: true, hasContent: false), .wide)
    }

    func testTheSizeButtonGoesRound() {
        XCTAssertEqual(HomeSizing.next(after: .square, allowed: [.wide, .square]), .wide)
        XCTAssertEqual(HomeSizing.next(after: .wide, allowed: [.wide, .square]), .square)
        XCTAssertEqual(HomeSizing.next(after: .hero, allowed: [.compact, .square]), .compact)
    }

    // MARK: - Rows

    private func pack(_ tiles: [(String, HomeSize)], folded: Bool = false) -> [HomePackedRow<String>] {
        HomeSizing.pack(tiles.map { (id: $0.0, size: $0.1) }, folded: folded)
    }

    func testTwoSquaresPair() {
        XCTAssertEqual(pack([("a", .square), ("b", .square)]), [.pair("a", "b")])
    }

    func testASquarePullsTheNextSquarePastAWideTile() {
        XCTAssertEqual(pack([("a", .square), ("w", .wide), ("b", .square)]), [.pair("a", "b"), .full("w")])
    }

    func testALoneSquareStaysASquare() {
        XCTAssertEqual(pack([("w", .wide), ("a", .square)]), [.full("w"), .single("a")])
    }

    func testASquareLooksOnlySoFarAhead() {
        let far = pack([("a", .square), ("w1", .wide), ("w2", .wide), ("w3", .wide), ("b", .square)])
        XCTAssertEqual(far, [.single("a"), .full("w1"), .full("w2"), .full("w3"), .single("b")])
    }

    func testShortcutsStackBesideASquare() {
        XCTAssertEqual(pack([("a", .square), ("s1", .compact), ("s2", .compact)]), [.stack("a", ["s1", "s2"])])
        XCTAssertEqual(pack([("a", .square), ("s1", .compact)]), [.stack("a", ["s1"])])
    }

    func testShortcutsPairBeforeTheyStack() {
        XCTAssertEqual(pack([("s1", .compact), ("a", .square), ("s2", .compact)]), [.pair("s1", "s2"), .single("a")])
    }

    func testAShortcutPullsASquareWhenItHasNoTwin() {
        XCTAssertEqual(pack([("s1", .compact), ("a", .square)]), [.stack("a", ["s1"])])
    }

    func testALoneShortcutTakesTheRow() {
        XCTAssertEqual(pack([("w", .wide), ("s", .compact)]), [.full("w"), .full("s")])
    }

    func testEveryTileIsDrawnOnce() {
        let tiles: [(String, HomeSize)] = [("a", .square), ("b", .compact), ("c", .wide), ("d", .square), ("e", .compact),
                                           ("f", .hero), ("g", .square), ("h", .compact), ("i", .compact), ("j", .square)]
        let drawn = pack(tiles).flatMap(\.members)
        XCTAssertEqual(drawn.count, tiles.count)
        XCTAssertEqual(Set(drawn), Set(tiles.map(\.0)))
    }

    func testFoldedIsOneColumnInOrder() {
        XCTAssertEqual(pack([("a", .square), ("b", .square), ("c", .compact)], folded: true), [.full("a"), .full("b"), .full("c")])
    }

    // MARK: - The diary

    private let london = TimeZone(identifier: "Europe/London")!
    /// Tuesday 27 October 2026, 10:00 in London (GMT).
    private let ten = Date(timeIntervalSince1970: 1_793_095_200)

    private func entry(_ id: String, hours: Double, length: Double? = nil) -> HomeDiary.Entry {
        let start = ten.addingTimeInterval(hours * 3600)
        return HomeDiary.Entry(id: id, title: id, start: start, end: length.map { start.addingTimeInterval($0 * 3600) })
    }

    func testTodayIsWhatIsLeftOfItInOrder() {
        let agenda = HomeDiary.agenda([entry("late", hours: 6), entry("done", hours: -3, length: 1), entry("soon", hours: 1),
                                       entry("on", hours: -0.5, length: 2), entry("tomorrow", hours: 24)],
                                      now: ten, zone: london)
        XCTAssertEqual(agenda.today.map(\.id), ["on", "soon", "late"])
        XCTAssertEqual(agenda.next?.id, "tomorrow")
        XCTAssertTrue(agenda.hasContent)
    }

    func testAnEntryWithNoEndLastsAnHour() {
        let agenda = HomeDiary.agenda([entry("standup", hours: -0.75)], now: ten, zone: london)
        XCTAssertEqual(agenda.today.map(\.id), ["standup"])
        XCTAssertTrue(HomeDiary.agenda([entry("standup", hours: -1.25)], now: ten, zone: london).today.isEmpty)
    }

    func testAClearDayHasNothingToShowButSaysWhatIsNext() {
        let agenda = HomeDiary.agenda([entry("tomorrow", hours: 26)], now: ten, zone: london)
        XCTAssertFalse(agenda.hasContent)
        XCTAssertEqual(agenda.next?.id, "tomorrow")
    }

    func testAnUnreadableDiaryIsNeverAFullDay() {
        XCTAssertFalse(HomeDiary.agenda([entry("soon", hours: 1)], now: ten, zone: london, readable: false).hasContent)
    }

    func testWhenInWords() {
        XCTAssertEqual(HomeDiary.when(entry("a", hours: -0.1), now: ten, zone: london), "Now")
        XCTAssertEqual(HomeDiary.when(entry("a", hours: 0.25), now: ten, zone: london), "In 15 min")
        XCTAssertEqual(HomeDiary.when(entry("a", hours: 4), now: ten, zone: london), "14:00")
    }
}
