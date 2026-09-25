import XCTest
@testable import SRAppleApp

/// Today's alerts card: which rows it lists, and clearing them off it.
final class TodayTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "TodayTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func alert(_ id: String) -> SiteAlert {
        SiteAlert(id: id, category: "build", title: "Alert \(id)", body: "", url: nil,
                  severity: "info", createdAt: "2026-09-25T08:00:00Z", read: false)
    }

    private func latest(_ id: String) -> TodayAlerts.Latest {
        TodayAlerts.Latest(id: id, category: "build", title: "Alert \(id)", severity: "info",
                           createdAt: "2026-09-25T08:00:00Z")
    }

    // MARK: - Rows

    func testRowsFallBackToTodaysOwnBeforeTheInboxAnswers() {
        let rows = TodayAlerts.rows(recent: [], latest: [latest("a"), latest("b")], cleared: [])
        XCTAssertEqual(rows.map(\.id), ["a", "b"])
    }

    func testRowsPreferTheInboxAndStopAtThree() {
        let rows = TodayAlerts.rows(
            recent: ["1", "2", "3", "4"].map(alert),
            latest: [latest("a")],
            cleared: []
        )
        XCTAssertEqual(rows.map(\.id), ["1", "2", "3"])
    }

    func testAClearedRowMakesRoomForTheNextOne() {
        let rows = TodayAlerts.rows(recent: ["1", "2", "3", "4"].map(alert), latest: [], cleared: ["2"])
        XCTAssertEqual(rows.map(\.id), ["1", "3", "4"])
    }

    func testEverythingClearedLeavesTheCardEmpty() {
        let rows = TodayAlerts.rows(recent: ["1", "2"].map(alert), latest: [latest("1")], cleared: ["1", "2"])
        XCTAssertTrue(rows.isEmpty)
    }

    // MARK: - Clearing

    @MainActor func testClearingIsRememberedAcrossLaunches() {
        let store = AlertStore(defaults: defaults)
        store.clearFromToday(["1", "2", "2"])
        XCTAssertEqual(store.clearedFromToday, ["1", "2"])
        XCTAssertEqual(defaults.stringArray(forKey: AlertStore.clearedKey), ["1", "2"])

        let relaunched = AlertStore(defaults: defaults)
        XCTAssertEqual(relaunched.clearedFromToday, ["1", "2"])
    }

    @MainActor func testTheClearedListIsCappedOldestFirst() {
        let store = AlertStore(defaults: defaults)
        let ids = (0..<(AlertStore.clearedCap + 5)).map { "id-\($0)" }
        store.clearFromToday(ids)
        XCTAssertEqual(store.clearedFromToday.count, AlertStore.clearedCap)
        XCTAssertFalse(store.clearedFromToday.contains("id-0"))
        XCTAssertTrue(store.clearedFromToday.contains("id-\(AlertStore.clearedCap + 4)"))
        XCTAssertEqual(defaults.stringArray(forKey: AlertStore.clearedKey)?.first, "id-5")
    }
}
