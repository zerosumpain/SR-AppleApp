import XCTest
@testable import SRAppleApp

final class HubLayoutTests: XCTestCase {
    /// The owner's hub, most used first as a new install sees it.
    private let owner = ["trips", "news", "drive", "daydream", "wildmind", "captures", "steps", "tasks", "backlog",
                         "landgrab", "flows", "travel", "offline", "settings"]
    /// A family member's: no Drive, Captures or the owner's loop.
    private let member = ["news", "steps", "tasks", "backlog", "messages", "games", "travel", "offline", "settings"]

    /// Every cell of the page's rectangle covered exactly once, nothing off
    /// the four columns, every id placed once.
    private func assertTiles(_ ids: [String], file: StaticString = #filePath, line: UInt = #line) {
        let placements = HubLayout.pack(ids)
        XCTAssertEqual(placements.map(\.id).sorted(), Array(Set(ids)).sorted(), "every door placed once", file: file, line: line)
        let rows = HubLayout.rows(placements)
        var grid = Array(repeating: Array(repeating: 0, count: HubLayout.columns), count: rows)
        for p in placements {
            XCTAssertGreaterThanOrEqual(p.column, 0, file: file, line: line)
            XCTAssertLessThanOrEqual(p.column + p.size.columns, HubLayout.columns, "\(p.id) runs off the page", file: file, line: line)
            for r in p.row..<(p.row + p.size.rows) {
                for c in p.column..<(p.column + p.size.columns) { grid[r][c] += 1 }
            }
        }
        for (r, cells) in grid.enumerated() {
            XCTAssertEqual(cells, [1, 1, 1, 1], "row \(r) has a hole or an overlap", file: file, line: line)
        }
        for p in placements {
            if HubLayout.bigIds.contains(p.id) {
                XCTAssertEqual(p.size, .big, "\(p.id) must be 2x2", file: file, line: line)
            } else {
                XCTAssertNotEqual(p.size, .big, "\(p.id) is not one of the big four", file: file, line: line)
                XCTAssertNotEqual(p.size, .banner, "\(p.id): no banner while there are two or more small doors", file: file, line: line)
            }
        }
    }

    func testTheOwnersHubTilesWithoutGaps() {
        assertTiles(owner)
    }

    func testTheOwnersHubMixesSizes() {
        let sizes = Set(HubLayout.pack(owner).map(\.size))
        XCTAssertTrue(sizes.isSuperset(of: [.big, .wide, .tall, .small]), "got \(sizes)")
    }

    func testTheBigDoorsZigZag() {
        let bigs = HubLayout.pack(owner).filter { $0.size == .big }.sorted { $0.row < $1.row }
        XCTAssertEqual(bigs.map(\.id), ["news", "drive", "captures", "settings"])
        XCTAssertEqual(bigs.map(\.column), [0, 2, 0, 2])
    }

    func testAMembersHubTilesWithoutGaps() {
        assertTiles(member)
        assertTiles(["news", "steps", "tasks", "backlog", "travel", "offline", "settings"])
        assertTiles(["games", "travel", "offline", "settings"])
    }

    func testSmallSetsTileWithoutGaps() {
        assertTiles(["travel", "offline", "settings"])
        assertTiles(["travel", "offline", "news", "settings"])
        assertTiles(["travel", "offline", "steps", "settings"])
        assertTiles(["a", "b", "c", "d", "e"])
        assertTiles(["a", "b"])
    }

    /// Any number of small doors, with any number of the big four.
    func testEverySizeOfSetTiles() {
        let bigFour = ["news", "drive", "captures", "settings"]
        for bigCount in 0...4 {
            for small in 2...20 {
                let ids = Array(bigFour.prefix(bigCount)) + (0..<small).map { "door\($0)" }
                assertTiles(ids)
            }
        }
    }

    func testTheSameDoorsGiveTheSameLayout() {
        XCTAssertEqual(HubLayout.pack(owner), HubLayout.pack(owner))
    }

    func testTheMostUsedSmallDoorLeadsAndIsNeverTheSmallest() {
        let first = HubLayout.pack(owner).first { $0.id == "trips" }
        XCTAssertNotNil(first)
        XCTAssertEqual(first?.size.area, 2)
    }

    func testOneSmallDoorBesideAnOddBigOneTakesTheSquare() {
        let placements = HubLayout.pack(["settings", "travel"])
        XCTAssertEqual(placements, [HubPlacement(id: "settings", size: .big, column: 0, row: 0),
                                    HubPlacement(id: "travel", size: .big, column: 2, row: 0)])
    }

    func testOneSmallDoorUnderEvenBigOnesIsAStrip() {
        let placements = HubLayout.pack(["settings", "news", "travel"])
        XCTAssertEqual(placements.last, HubPlacement(id: "travel", size: .banner, column: 0, row: 2))
        XCTAssertEqual(HubLayout.rows(placements), 3)
    }

    func testDuplicatesArePlacedOnce() {
        XCTAssertEqual(HubLayout.pack(["travel", "travel", "offline", "settings"]).count, 3)
    }

    func testNothingIsAnEmptyPage() {
        XCTAssertEqual(HubLayout.pack([]), [])
        XCTAssertEqual(HubLayout.rows([]), 0)
    }
}
