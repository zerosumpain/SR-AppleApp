import XCTest
@testable import SRAppleApp

final class HubUsageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_000_000)

    func testNeverUsedKeepsTheHubsOwnOrder() {
        XCTAssertEqual(HubUsage().ordered(["trips", "news", "steps"], now: now), ["trips", "news", "steps"])
    }

    func testTheMostUsedComesFirst() {
        var usage = HubUsage()
        usage.record("steps", now: now)
        usage.record("steps", now: now)
        usage.record("news", now: now)
        XCTAssertEqual(usage.ordered(["trips", "news", "steps"], now: now), ["steps", "news", "trips"])
    }

    /// Fourteen days halve a count: last month's favourite gives way to
    /// today's habit.
    func testOldUseFades() {
        var usage = HubUsage()
        for _ in 0..<4 { usage.record("news", now: now.addingTimeInterval(-30 * 86_400)) }
        usage.record("steps", now: now)
        XCTAssertEqual(usage.score("news", now: now), 4 * pow(0.5, 30.0 / 14), accuracy: 0.001)
        XCTAssertEqual(usage.ordered(["news", "steps"], now: now), ["steps", "news"])
    }

    func testItKeeps() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "hub-usage-test"))
        defaults.removePersistentDomain(forName: "hub-usage-test")
        HubUsage.opened("travel", now: now, defaults: defaults)
        HubUsage.opened("travel", now: now, defaults: defaults)
        XCTAssertEqual(HubUsage.load(defaults).score("travel", now: now), 2, accuracy: 0.001)
    }
}
