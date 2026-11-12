import XCTest
@testable import SRAppleApp

final class NotifyLevelTests: XCTestCase {
    private func alert(_ category: String, _ severity: String, data: JSONValue? = nil) -> SiteAlert {
        SiteAlert(id: "a", category: category, title: "t", body: "b", url: nil,
                  severity: severity, createdAt: "2026-11-12T10:00:00.000Z", read: false, data: data)
    }

    func testALevelHearsItsOwnTierAndEveryQuieterOne() {
        XCTAssertTrue(NotifyLevel.minimal.hears(.minimal))
        XCTAssertFalse(NotifyLevel.minimal.hears(.normal))
        XCTAssertFalse(NotifyLevel.minimal.hears(.verbose))
        XCTAssertTrue(NotifyLevel.normal.hears(.minimal))
        XCTAssertTrue(NotifyLevel.normal.hears(.normal))
        XCTAssertFalse(NotifyLevel.normal.hears(.verbose))
        XCTAssertTrue(NotifyLevel.verbose.hears(.verbose))
    }

    func testAPhoneStartsOnMinimalAndKeepsWhatIsChosen() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "notify-level-tests"))
        defaults.removePersistentDomain(forName: "notify-level-tests")
        XCTAssertEqual(NotifyLevel.stored(in: defaults), .minimal)
        defaults.set("verbose", forKey: NotifyLevel.key)
        XCTAssertEqual(NotifyLevel.stored(in: defaults), .verbose)
        defaults.set("loud", forKey: NotifyLevel.key)
        XCTAssertEqual(NotifyLevel.stored(in: defaults), .minimal, "an unknown value is the default, not a crash")
        defaults.removePersistentDomain(forName: "notify-level-tests")
    }

    func testTheOwnerLedgerIsGradedAsTheSiteGradesIt() {
        XCTAssertEqual(NotifyLevel.tier(for: alert("connections", "info")), .minimal)
        XCTAssertEqual(NotifyLevel.tier(for: alert("uptime", "alert")), .minimal)
        XCTAssertEqual(NotifyLevel.tier(for: alert("health", "warn")), .normal)
        XCTAssertEqual(NotifyLevel.tier(for: alert("daydream", "info")), .verbose)
        XCTAssertEqual(NotifyLevel.tier(for: alert("chat", "info", data: .object(["gate": .string("confirm"), "jobId": .string("j1")]))), .minimal)
        XCTAssertEqual(NotifyLevel.tier(for: alert("chat", "info", data: .object(["kind": .string("reply"), "conversationId": .string("c1")]))), .normal)
        XCTAssertEqual(NotifyLevel.tier(for: alert("drive", "info")), .verbose)
        XCTAssertEqual(NotifyLevel.tier(for: alert("drive", "alert")), .normal)
    }

    func testAnArrivalEstimateIsVerboseAndACrossingNormal() {
        XCTAssertEqual(NotifyLevel.tier(forHousehold: "eta-0123abcd"), .verbose)
        XCTAssertEqual(NotifyLevel.tier(forHousehold: "0d3c1f0e-crossing"), .normal)
    }
}
