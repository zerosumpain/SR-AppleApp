import XCTest
@testable import SRAppleApp

/// The desk drawer's data: a turn's page as the site sends it, read tolerantly.
///
/// The rule under test is that a page can only ever cost the DRAWER — an
/// unknown block, a missing field or a panel that is not an object at all must
/// leave the message, and the transcript, exactly as they were.
final class DeskTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - Decoding

    func testDecodesAFullPage() throws {
        let page = try decode(PanelPage.self, """
        {"version": 1, "producer": "model", "quiet": false,
         "head": {"kicker": "HEALTH", "context": ["health", "sleep"], "title": "Load is ramping", "standfirst": "This week."},
         "sections": [{"id": "s", "label": "This week", "blocks": [
           {"id": "f", "type": "figures", "items": [{"label": "HRV", "value": "64", "unit": "ms", "delta": "+5", "direction": "up", "spark": [1, 2, 3]}]},
           {"id": "s", "type": "series", "zero": true, "series": [{"key": "k", "label": "Hours", "points": [{"x": "Mon", "y": 7.1}]}]},
           {"id": "b", "type": "bars", "rows": [{"id": "r", "label": "Recovery", "value": 68, "highlight": true}]},
           {"id": "h", "type": "heat", "columns": ["a"], "rows": [{"label": "w1", "values": [1, null]}]},
           {"id": "r", "type": "rows", "numbered": true, "rows": [{"id": "1", "title": "One", "href": "/health"}]},
           {"id": "t", "type": "table", "columns": ["A", "B"], "rows": [["x", 1.5, null]], "pick": 1},
           {"id": "tl", "type": "timeline", "events": [{"id": "e", "when": "09:00", "what": "Run", "hot": true}]},
           {"id": "kv", "type": "kv", "items": [{"label": "A", "value": "1"}]},
           {"id": "p", "type": "prose", "markdown": "**hi**"},
           {"id": "en", "type": "entity", "entityId": "e1", "name": "Alex"},
           {"id": "ac", "type": "actions", "items": [{"id": "a", "label": "Ask", "kind": "ask", "ask": {"label": "Draft", "detail": "Draft week 8"}}]},
           {"id": "g", "type": "group", "blocks": [{"id": "g1", "type": "kv", "items": [{"label": "x", "value": "y"}]}]}
         ]}]}
        """)
        XCTAssertEqual(page.producer, "model")
        XCTAssertEqual(page.head.kicker, "HEALTH")
        XCTAssertEqual(page.head.context, ["health", "sleep"])
        XCTAssertEqual(page.head.standfirst, "This week.")
        XCTAssertEqual(page.sections.first?.blocks.map(\.kind),
                       [.figures, .series, .bars, .heat, .rows, .table, .timeline, .kv, .prose, .entity, .actions, .group])
        guard case .figures(let items) = page.sections[0].blocks[0].content else { return XCTFail("not figures") }
        XCTAssertEqual(items.first?.spark, [1, 2, 3])
        XCTAssertEqual(items.first?.direction, "up")
        guard case .table(_, let rows, let pick) = page.sections[0].blocks[5].content else { return XCTFail("not a table") }
        XCTAssertEqual(pick, 1)
        XCTAssertEqual(rows.first?.map(\.display), ["x", "1.5", "—"])
        XCTAssertTrue(page.hasContent)
    }

    func testAnUnknownBlockTypeIsSkippedAndTheRestKept() throws {
        let page = try decode(PanelPage.self, """
        {"producer": "turn", "head": {"kicker": "T", "title": "T"}, "sections": [
          {"id": "a", "blocks": [
            {"id": "x", "type": "hologram", "items": [1, 2]},
            {"id": "k", "type": "kv", "items": [{"label": "x", "value": "y"}]},
            {"id": "n", "type": "artifact", "artifact": {}}
          ]},
          {"id": "only-unknown", "blocks": [{"id": "z", "type": "zzz"}]}
        ]}
        """)
        XCTAssertEqual(page.sections.count, 1, "a section left with nothing to draw is dropped")
        XCTAssertEqual(page.sections[0].blocks.map(\.id), ["k"])
    }

    func testABrokenElementCostsOnlyItself() throws {
        let page = try decode(PanelPage.self, """
        {"sections": [{"id": "a", "blocks": [
          {"id": "b", "type": "bars", "rows": [{"id": "ok", "label": "OK", "value": 3}, {"id": "bad", "label": "No value"}]},
          {"id": "r", "type": "rows", "rows": [{"id": "1", "title": "Kept"}, {"id": "2"}, null]},
          {"id": "a", "type": "actions", "items": [{"id": "p", "label": "Post", "kind": "post", "endpoint": "/api/x"}, {"id": "l", "label": "Open", "kind": "link", "href": "/health"}]}
        ]}]}
        """)
        let blocks = page.sections[0].blocks
        guard case .bars(let bars) = blocks[0].content else { return XCTFail("not bars") }
        XCTAssertEqual(bars.map(\.id), ["ok"])
        guard case .rows(let rows, _, _) = blocks[1].content else { return XCTFail("not rows") }
        XCTAssertEqual(rows.map(\.title), ["Kept"])
        guard case .actions(let actions) = blocks[2].content else { return XCTFail("not actions") }
        XCTAssertEqual(actions.map(\.kind), ["link"], "a button that posts is never drawn on the phone")
    }

    func testMissingOptionalFieldsTakeTheirDefaults() throws {
        let page = try decode(PanelPage.self, #"{"sections": [{"id": "a", "blocks": [{"id": "k", "type": "kv", "items": [{"label": "x", "value": "y"}]}]}]}"#)
        XCTAssertEqual(page.version, 1)
        XCTAssertEqual(page.producer, "turn")
        XCTAssertEqual(page.head.title, "")
        XCTAssertEqual(page.head.context, [])
        XCTAssertNil(page.head.standfirst)
        XCTAssertFalse(page.quiet)
        XCTAssertEqual(page.sections[0].label, "")
        XCTAssertFalse(page.sections[0].blocks[0].isCard)
        XCTAssertTrue(page.hasContent)
    }

    func testAMessageWithoutAPanelOrWithAJunkOneStillDecodes() throws {
        let messages = try decode(MessagePage.self, """
        {"conversation": {"id": "c", "title": null, "source": "web"}, "hasOlder": false, "cursor": null, "messages": [
          {"id": "a", "role": "assistant", "content": "older server", "createdAt": null, "source": "web", "toolSteps": [], "attachments": []},
          {"id": "b", "role": "assistant", "content": "null panel", "createdAt": null, "source": "web", "toolSteps": [], "attachments": [], "panel": null},
          {"id": "c", "role": "assistant", "content": "junk panel", "createdAt": null, "source": "web", "toolSteps": [], "attachments": [], "panel": 7},
          {"id": "d", "role": "assistant", "content": "junk sections", "createdAt": null, "source": "web", "toolSteps": [], "attachments": [], "panel": {"sections": "no"}}
        ]}
        """).messages
        XCTAssertEqual(messages.map(\.content), ["older server", "null panel", "junk panel", "junk sections"])
        XCTAssertNil(messages[0].panel)
        XCTAssertNil(messages[1].panel)
        XCTAssertEqual(messages[2].panel?.hasContent, false)
        XCTAssertEqual(messages[3].panel?.hasContent, false)
    }

    // MARK: - Which page

    private let page = PanelPage(sections: [PanelSection(id: "a", blocks: [PanelBlock(id: "b", content: .kv([PanelKV(label: "x", value: "y")]))])])

    private var turns: [DeskTurn] {
        [DeskTurn(id: "u1", isAssistant: false, page: nil),
         DeskTurn(id: "a1", isAssistant: true, page: page),
         DeskTurn(id: "u2", isAssistant: false, page: nil),
         DeskTurn(id: "a2", isAssistant: true, page: nil),
         DeskTurn(id: "u3", isAssistant: false, page: nil),
         DeskTurn(id: "a3", isAssistant: true, page: page)]
    }

    func testATurnWithAPageOpensOnIt() {
        XCTAssertEqual(DeskPager.choose(turns: turns, focus: "a1"), .init(index: 0, held: false))
        XCTAssertEqual(DeskPager.choose(turns: turns, focus: "a3"), .init(index: 1, held: false))
    }

    func testAQuietTurnHoldsTheNearestEarlierPage() {
        XCTAssertEqual(DeskPager.choose(turns: turns, focus: "a2"), .init(index: 0, held: true))
    }

    func testNoFocusMeansTheLatestAnswer() {
        XCTAssertEqual(DeskPager.choose(turns: turns, focus: nil), .init(index: 1, held: false))
    }

    func testAThreadWithNoPagesShowsToday() {
        let bare = [DeskTurn(id: "u", isAssistant: false, page: nil), DeskTurn(id: "a", isAssistant: true, page: nil)]
        XCTAssertEqual(DeskPager.choose(turns: bare, focus: nil), .init(index: nil, held: false))
        XCTAssertEqual(DeskPager.choose(turns: [], focus: nil), .init(index: nil, held: false))
    }

    // MARK: - Links

    func testLinksResolveAgainstTheSiteAndRefuseTheRest() {
        let origin = URL(string: "https://strangeramblings.com")!
        XCTAssertEqual(DeskLinks.resolve("/health?view=week", origin: origin)?.absoluteString, "https://strangeramblings.com/health?view=week")
        XCTAssertEqual(DeskLinks.resolve("https://example.org/a", origin: origin)?.host, "example.org")
        XCTAssertNil(DeskLinks.resolve("//evil.example", origin: origin))
        XCTAssertNil(DeskLinks.resolve("javascript:alert(1)", origin: origin))
        XCTAssertNil(DeskLinks.resolve(nil, origin: origin))
    }

    // MARK: - Today, and the demo

    func testTodayBecomesAPage() throws {
        let clock = SRDemoFixtures.DemoClock(now: Date())
        let payload = try decode(TodayPayload.self, SRDemoFixtures.today(clock))
        let page = DeskToday.page(from: payload)
        XCTAssertEqual(page.producer, "today")
        XCTAssertEqual(page.head.kicker, "Today")
        XCTAssertEqual(page.sections.map(\.id), ["today-health", "today-alerts", "today-news"])
        guard case .figures(let figures) = page.sections[0].blocks[0].content else { return XCTFail("no figures") }
        XCTAssertEqual(figures.first?.label, "Readiness")
        XCTAssertEqual(figures.first?.value, "72")
    }

    func testTodayWithNothingStillSaysSomething() {
        let page = DeskToday.page(from: nil)
        XCTAssertTrue(page.hasContent)
    }

    /// The demo thread the showcase photographs carries two rich pages, and
    /// they decode against the real models.
    func testTheDemoThreadHasTwoDeskPages() throws {
        let clock = SRDemoFixtures.DemoClock(now: Date())
        let body = try XCTUnwrap(SRDemoFixtures.messagePage(id: "demo-thread-training", clock: clock))
        let messages = try decode(MessagePage.self, body).messages
        let pages = messages.compactMap(\.panel).filter(\.hasContent)
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].sections.flatMap(\.blocks).map(\.kind), [.figures, .series, .bars, .kv, .actions])
        XCTAssertEqual(pages[1].sections.flatMap(\.blocks).map(\.kind), [.rows, .table, .rows, .timeline])
    }

    @MainActor func testTheBylineIsAClock() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // November, not September: en_GB spells that month "Sept" on iOS 17+.
        let now = ISO8601DateFormatter().date(from: "2026-11-02T15:00:00Z")!
        XCTAssertEqual(ChatBubble.clock("2026-11-02T14:02:00Z", now: now, calendar: calendar), "14:02")
        XCTAssertEqual(ChatBubble.clock("2026-11-01T09:05:00Z", now: now, calendar: calendar), "1 Nov 09:05")
        XCTAssertEqual(ChatBubble.clock("not a date", now: now, calendar: calendar), "")
    }
}
