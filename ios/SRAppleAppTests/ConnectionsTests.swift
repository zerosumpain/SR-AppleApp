import XCTest
@testable import SRAppleApp

/// "A connection needs you": the wire contract decoded defensively, the banner's
/// states, the badge sum, and the state file upgrading without losing anything.
final class ConnectionsTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func item(_ id: String, status: String = "expired") -> ConnectionItem {
        ConnectionItem(id: id, label: id.capitalized, status: status, detail: "d",
                       fixUrl: "https://strangeramblings.com/fix/\(id)")
    }

    // MARK: - Decoding

    func testTheFeedDecodes() throws {
        let feed = try decode(ConnectionsFeed.self, """
        {"needsAttention": [
          {"id": "google:gmail", "label": "Gmail", "group": "Google", "status": "expired",
           "detail": "Token expired", "fixHint": "Sign in again",
           "fixUrl": "https://strangeramblings.com/admin/connections", "since": "2026-09-24T08:00:00.000Z"},
          {"id": "cal", "label": "Calendar", "group": "Google", "status": "error",
           "detail": "Failing", "fixHint": null, "fixUrl": "https://strangeramblings.com/x", "since": null}
        ], "checkedAt": "2026-09-25T08:00:00Z"}
        """)
        XCTAssertEqual(feed.needsAttention.map(\.id), ["google:gmail", "cal"])
        let gmail = feed.needsAttention[0]
        XCTAssertEqual(gmail.state, .needsReauth)
        XCTAssertEqual(gmail.headline, "Gmail needs re-authorising")
        XCTAssertEqual(gmail.fixURL?.host, "strangeramblings.com")
        XCTAssertNotNil(gmail.sinceDate)
        XCTAssertEqual(feed.needsAttention[1].state, .failing)
        XCTAssertNil(feed.needsAttention[1].sinceDate)
        XCTAssertEqual(feed.checkedAt, "2026-09-25T08:00:00Z")
        XCTAssertNotNil(ConnectionsStore.snapshot(of: feed).checkedAt)
    }

    func testAnUnknownStatusStillNeedsYou() throws {
        let one = try decode(ConnectionItem.self, #"{"id": "x", "label": "Strava", "status": "quantum-flux", "detail": ""}"#)
        XCTAssertEqual(one.state, .other("quantum-flux"))
        XCTAssertEqual(one.headline, "Strava needs you")
        XCTAssertEqual(one.subline, "Open the site to reconnect it.", "an empty detail falls back rather than showing nothing")
    }

    func testAMalformedItemDoesNotCostTheList() throws {
        // Missing fields, a numeric id, a wrong-typed field, and a non-object.
        let feed = try decode(ConnectionsFeed.self, """
        {"needsAttention": [
          {"id": 7, "label": "Gmail", "status": "revoked", "detail": 3},
          {"label": "Calendar"},
          "not an object"
        ]}
        """)
        XCTAssertEqual(feed.needsAttention.count, 2)
        XCTAssertEqual(feed.needsAttention[0].id, "7")
        XCTAssertEqual(feed.needsAttention[0].detail, "")
        XCTAssertEqual(feed.needsAttention[1].id, "connection-Calendar", "a missing id must still be stable")
        XCTAssertNil(feed.checkedAt)
    }

    func testAnEmptyOrAlienFeedIsNothing() throws {
        XCTAssertTrue(try decode(ConnectionsFeed.self, "{}").needsAttention.isEmpty)
        XCTAssertTrue(try decode(ConnectionsFeed.self, #"{"needsAttention": "soon"}"#).needsAttention.isEmpty)
    }

    func testOnlyAnHTTPSFixIsOpened() {
        XCTAssertNotNil(ConnectionItem(id: "a", label: "A", status: "expired", detail: "", fixUrl: "https://x.test/fix").fixURL)
        XCTAssertNil(ConnectionItem(id: "b", label: "B", status: "expired", detail: "", fixUrl: "http://x.test/fix").fixURL)
        XCTAssertNil(ConnectionItem(id: "c", label: "C", status: "expired", detail: "", fixUrl: "/admin/connections").fixURL)
        XCTAssertNil(ConnectionItem(id: "d", label: "D", status: "expired", detail: "", fixUrl: "javascript:alert(1)").fixURL)
        XCTAssertNil(ConnectionItem(id: "e", label: "E", status: "expired", detail: "").fixURL)
    }

    func testTodayWithoutConnectionsDecodes() throws {
        // An older server: no `connections` key at all.
        let payload = try decode(TodayPayload.self, #"{"generatedAt": "2026-09-25T08:00:00Z"}"#)
        XCTAssertNil(payload.connections)
    }

    func testTodayWithConnectionsDecodes() throws {
        let payload = try decode(TodayPayload.self, """
        {"generatedAt": "2026-09-25T08:00:00Z",
         "connections": {"needsAttention": 4, "items": [{"id": "g", "label": "Gmail", "status": "expired", "detail": "x",
                          "fixHint": null, "fixUrl": "https://strangeramblings.com/f", "since": null}]}}
        """)
        XCTAssertEqual(payload.connections?.needsAttention, 4, "the count can exceed the three-item preview")
        XCTAssertEqual(payload.connections?.items.first?.label, "Gmail")
        let bare = try decode(TodayConnections.self, #"{"items": [{"id": "g", "label": "Gmail"}]}"#)
        XCTAssertEqual(bare.needsAttention, 1, "a missing count falls back to the items")
    }

    // MARK: - The banner

    func testTheBannerIsHiddenWhenNothingNeedsYou() {
        XCTAssertEqual(ConnectionBannerMode.of(items: [], collapsedFor: nil), .hidden)
        XCTAssertEqual(ConnectionBannerMode.of(items: [], collapsedFor: ["a"]), .hidden)
    }

    func testTheBannerShowsInFullUntilCollapsed() {
        XCTAssertEqual(ConnectionBannerMode.of(items: [item("a")], collapsedFor: nil), .full)
        XCTAssertEqual(ConnectionBannerMode.of(items: [item("a")], collapsedFor: ["a"]), .slim)
    }

    func testANewlyLapsedConnectionReopensTheBanner() {
        XCTAssertEqual(ConnectionBannerMode.of(items: [item("a"), item("b")], collapsedFor: ["a"]), .full)
        // One of the collapsed ones fixed: still slim, nothing new to say.
        XCTAssertEqual(ConnectionBannerMode.of(items: [item("b")], collapsedFor: ["a", "b"]), .slim)
    }

    // MARK: - The badge

    func testTheBadgeAddsConnectionsToUnread() {
        XCTAssertEqual(AppBadge.total(unread: 3, connections: 1), 4)
        XCTAssertEqual(AppBadge.total(unread: 0, connections: 2), 2)
        XCTAssertEqual(AppBadge.total(unread: -1, connections: 0), 0, "a negative count never shows")
    }

    @MainActor func testTheBadgeRemembersTheOtherHalf() async {
        let defaults = UserDefaults(suiteName: "connections-tests-\(UUID().uuidString)")!
        await AppBadge.update(unread: 2, defaults: defaults)
        await AppBadge.update(connections: 1, defaults: defaults)
        XCTAssertEqual(defaults.integer(forKey: "badge-unread"), 2)
        XCTAssertEqual(defaults.integer(forKey: "badge-connections"), 1)
    }

    // MARK: - Notifications

    func testAConnectionsAlertIsLoud() throws {
        let alert = try decode(SiteAlert.self, """
        {"id": "n1", "category": "connections", "title": "Gmail needs re-authorising", "body": "Tap to fix",
         "url": null, "severity": "high", "createdAt": "2026-09-25T08:00:00Z", "read": false}
        """)
        XCTAssertTrue(alert.isConnections)
        XCTAssertTrue(alert.isAlert, "severity high is raised at the loudest level")
        XCTAssertEqual(alert.icon, "key.slash")
    }

    // MARK: - The state file

    func testAnOldStateFileDecodesWithoutConnections() throws {
        let old = """
        {"batches":[],"anchors":{},"healthEnabled":["steps"],"sharing":true,"historyStart":768000}
        """
        let state = try JSONDecoder().decode(PersistedState.self, from: Data(old.utf8))
        XCTAssertNil(state.connections)
        XCTAssertEqual(state.healthEnabled, ["steps"], "the upload settings survive")
    }

    func testAnUnreadableConnectionsCacheCostsOnlyTheCache() throws {
        let odd = """
        {"batches":[],"healthEnabled":["steps"],"connections":"a string where an object was"}
        """
        let state = try JSONDecoder().decode(PersistedState.self, from: Data(odd.utf8))
        XCTAssertNil(state.connections)
        XCTAssertEqual(state.healthEnabled, ["steps"])
    }

    @MainActor func testConnectionsSurviveARestartAndACompanionReset() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        let outbox = try Outbox(url: url)
        ConnectionsStore.persist(ConnectionsSnapshot(items: [item("gmail")], checkedAt: Date()), in: outbox)

        let reopened = try Outbox(url: url)
        XCTAssertEqual(reopened.state.connections?.items.map(\.id), ["gmail"])

        // Disconnecting the COMPANION must not forget the SITE's connections.
        try reopened.clear()
        XCTAssertEqual(reopened.state.connections?.items.map(\.id), ["gmail"])
    }

    // MARK: - Demo

    func testTheDemoFixturesDecode() throws {
        let base = "https://strangeramblings.com/"
        let feed = try JSONDecoder().decode(ConnectionsFeed.self, from:
            SRDemoFixtures.reply(method: "GET", url: URL(string: base + "api/native/connections")!, body: nil).body)
        XCTAssertEqual(feed.needsAttention.map(\.label), ["Gmail"])
        XCTAssertNotNil(feed.needsAttention.first?.fixURL)
        let today = try JSONDecoder().decode(TodayPayload.self, from:
            SRDemoFixtures.reply(method: "GET", url: URL(string: base + "api/native/today")!, body: nil).body)
        XCTAssertEqual(today.connections?.needsAttention, 1)
    }
}
