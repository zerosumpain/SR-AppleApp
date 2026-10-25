import XCTest
@testable import SRAppleApp

/// Who is shown which notes: once each, newest first, nothing a person cannot
/// open, and nothing at all on a fresh install.
@MainActor
final class WhatsNewTests: XCTestCase {

    private func release(_ id: String, ownerOnly: Bool = false) -> WhatsNewRelease {
        WhatsNewRelease(id: id, when: "October 2026", title: id, items: [
            WhatsNewItem(icon: "sparkles", title: "\(id) item", detail: "detail", ownerOnly: ownerOnly),
        ])
    }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: WhatsNew.seenKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: WhatsNew.seenKey)
        super.tearDown()
    }

    func testOnlyWhatHasNotBeenShown() {
        let all = [release("c"), release("b"), release("a")]
        XCTAssertEqual(WhatsNew.unseen(in: all, seen: ["a"], owner: false).map(\.id), ["c", "b"])
        XCTAssertTrue(WhatsNew.unseen(in: all, seen: ["a", "b", "c"], owner: false).isEmpty)
    }

    func testALongWayBehindSeesTheLatestFew() {
        let all = (1...6).reversed().map { release("r\($0)") }
        let shown = WhatsNew.unseen(in: all, seen: [], owner: false)
        XCTAssertEqual(shown.count, WhatsNew.shownAtOnce)
        XCTAssertEqual(shown.first?.id, "r6")
    }

    func testOwnerOnlyNotesAreNotNewsToAnyoneElse() {
        let all = [release("owner", ownerOnly: true), release("everyone")]
        XCTAssertEqual(WhatsNew.unseen(in: all, seen: [], owner: false).map(\.id), ["everyone"])
        XCTAssertEqual(WhatsNew.unseen(in: all, seen: [], owner: true).map(\.id), ["owner", "everyone"])
    }

    func testAFreshInstallStartsWithEverythingSeen() {
        WhatsNew.prepareLaunch(paired: false)
        XCTAssertEqual(WhatsNew.seen, Set(WhatsNew.releases.map(\.id)))
    }

    func testALockedLaunchDecidesNothing() {
        // Before the first unlock the pairing cannot be read, so "not paired"
        // is unknown, not a fresh install.
        WhatsNew.prepareLaunch(paired: false, protectedDataAvailable: false)
        XCTAssertNil(UserDefaults.standard.object(forKey: WhatsNew.seenKey))
    }

    func testAnUpdateFromBeforeThisScreenIsShownWhatItMissed() {
        WhatsNew.prepareLaunch(paired: true)
        XCTAssertTrue(WhatsNew.seen.isEmpty)
        XCTAssertFalse(WhatsNew.unseen(seen: WhatsNew.seen, owner: false).isEmpty)
    }

    func testOnceShownNeverAgain() {
        WhatsNew.markSeen(["x"])
        WhatsNew.markSeen(["y"])
        XCTAssertEqual(WhatsNew.seen, ["x", "y"])
        // A later launch with a record already kept leaves it alone.
        WhatsNew.prepareLaunch(paired: false)
        XCTAssertEqual(WhatsNew.seen, ["x", "y"])
    }

    func testReleaseIdsAreUniqueAndNotesAreWritten() {
        XCTAssertEqual(Set(WhatsNew.releases.map(\.id)).count, WhatsNew.releases.count)
        for release in WhatsNew.releases {
            XCTAssertFalse(release.items.isEmpty, release.id)
            XCTAssertEqual(Set(release.items.map(\.id)).count, release.items.count, "item titles are ids within \(release.id)")
            for item in release.items { XCTAssertFalse(item.detail.isEmpty) }
        }
    }
}
