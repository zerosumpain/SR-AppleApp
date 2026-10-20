import XCTest
@testable import SRAppleApp

/// Today's urgent banner from the first frame: the alert Today showed last time
/// is kept, so a standing banner does not arrive with the first refresh and
/// move every card under a thumb.
final class TodayUrgentLaunchTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "today-urgent-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func alert(_ id: String, severity: String = "alert", read: Bool = false) -> SiteAlert {
        SiteAlert(id: id, category: "home", title: "Front door has been open 10 minutes", body: "", url: nil,
                  severity: severity, createdAt: "2026-10-20T15:26:00Z", read: read)
    }

    func testTheUrgentAlertComesBackAsItWasSaved() {
        let saved = alert("a1")
        AlertStore.saveUrgent(saved, defaults: defaults)
        XCTAssertEqual(AlertStore.savedUrgent(defaults: defaults), saved)
    }

    func testNoUrgentAlertClearsWhatWasKept() {
        AlertStore.saveUrgent(alert("a1"), defaults: defaults)
        AlertStore.saveUrgent(nil, defaults: defaults)
        XCTAssertNil(AlertStore.savedUrgent(defaults: defaults))
    }

    func testADayOldAlertIsNotPutUp() {
        let then = Date()
        AlertStore.saveUrgent(alert("a1"), defaults: defaults, now: then)
        XCTAssertNotNil(AlertStore.savedUrgent(defaults: defaults, now: then.addingTimeInterval(AlertStore.launchUrgentMaxAge - 60)))
        XCTAssertNil(AlertStore.savedUrgent(defaults: defaults, now: then.addingTimeInterval(AlertStore.launchUrgentMaxAge + 60)))
    }

    func testClearingRemovesIt() {
        AlertStore.saveUrgent(alert("a1"), defaults: defaults)
        AlertStore.clearLaunchUrgent(defaults: defaults)
        XCTAssertNil(AlertStore.savedUrgent(defaults: defaults))
    }

    func testOnlyAnUnreadAlertAtTheLoudestLevelIsKept() {
        // What `refresh` saves is what Today's banner would show.
        XCTAssertNil(TodayAlerts.urgent(in: [alert("w", severity: "warn"), alert("r", read: true)], dismissed: []))
        XCTAssertEqual(TodayAlerts.urgent(in: [alert("w", severity: "warn"), alert("u")], dismissed: [])?.id, "u")
    }

    func testAnAlertRoundTripsThroughJSON() throws {
        let a = alert("a1")
        XCTAssertEqual(try JSONDecoder().decode(SiteAlert.self, from: JSONEncoder().encode(a)), a)
    }
}
