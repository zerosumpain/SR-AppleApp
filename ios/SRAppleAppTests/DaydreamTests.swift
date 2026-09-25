import XCTest
@testable import SRAppleApp

/// Noticed: the daydream loop's notes, decoded defensively on Today and the
/// Health tab, and the feedback body the site expects.
final class DaydreamTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private let note = """
    {"id": "n1", "outcome": "health_plan", "channel": "health", "title": "Bed earlier",
     "body": "Four late nights cost the long walk.", "createdAt": "2026-09-25T08:00:00Z",
     "url": "/jkai/daydreams?note=n1", "feedback": null}
    """

    // MARK: - Today

    func testTodayWithoutTheDaydreamKeyDecodes() throws {
        // An older server: no `daydream` key at all.
        let payload = try decode(TodayPayload.self, #"{"generatedAt": "2026-09-25T08:00:00Z"}"#)
        XCTAssertNil(payload.daydream)
    }

    func testTodayWithANullDaydreamDecodes() throws {
        let payload = try decode(TodayPayload.self, #"{"generatedAt": "2026-09-25T08:00:00Z", "daydream": null}"#)
        XCTAssertNil(payload.daydream)
    }

    func testTodayWithTheDaydreamKeyDecodes() throws {
        let payload = try decode(TodayPayload.self, """
        {"generatedAt": "2026-09-25T08:00:00Z", "daydream": {"notes": [\(note)]}}
        """)
        let notes = try XCTUnwrap(payload.daydream?.notes)
        XCTAssertEqual(notes.count, 1)
        let first = notes[0]
        XCTAssertEqual(first.id, "n1")
        XCTAssertEqual(first.outcome, .healthPlan)
        XCTAssertEqual(first.outcome.label, "Health plan")
        XCTAssertEqual(first.channel, .health)
        XCTAssertEqual(first.title, "Bed earlier")
        XCTAssertEqual(first.url, "/jkai/daydreams?note=n1")
        XCTAssertNil(first.feedback)
    }

    func testAMalformedDaydreamBlockCostsOnlyTheCard() throws {
        // The wrong shape entirely must not blank the first screen.
        let payload = try decode(TodayPayload.self, #"{"generatedAt": "x", "daydream": "soon"}"#)
        XCTAssertEqual(payload.daydream?.notes ?? [], [])
        let empty = try decode(TodayPayload.self, #"{"generatedAt": "x", "daydream": {"notes": []}}"#)
        XCTAssertEqual(empty.daydream?.notes.isEmpty, true)
    }

    // MARK: - Notes

    func testAnUnknownOutcomeFallsBackToAGenericLabel() throws {
        let one = try decode(DaydreamNote.self, """
        {"id": "n2", "outcome": "horoscope", "channel": "tarot", "title": "T", "body": "B",
         "createdAt": "2026-09-25T08:00:00Z", "url": "/x", "feedback": "maybe"}
        """)
        XCTAssertEqual(one.outcome, .other("horoscope"))
        XCTAssertEqual(one.outcome.label, "Noticed")
        XCTAssertEqual(one.channel, .other("tarot"))
        XCTAssertNil(one.feedback, "a verdict this build does not know is no verdict")
    }

    func testEveryKnownOutcomeHasHumanWording() {
        let raws = ["correlate", "efficiency", "quality_of_life", "research", "build", "health_plan", "suggest", "money_analysis"]
        for raw in raws {
            let outcome = DaydreamOutcome(raw: raw)
            XCTAssertNotEqual(outcome, .other(raw), raw)
            XCTAssertEqual(outcome.raw, raw)
            XCTAssertFalse(outcome.label.contains("_"), raw)
        }
        XCTAssertEqual(DaydreamOutcome(raw: "money_analysis").label, "Money")
        XCTAssertEqual(DaydreamOutcome(raw: "suggest").label, "Worth trying")
    }

    func testRecordedFeedbackDecodes() throws {
        let useful = try decode(DaydreamNote.self, #"{"id": "a", "title": "T", "feedback": "useful"}"#)
        XCTAssertEqual(useful.feedback, .useful)
        let not = try decode(DaydreamNote.self, #"{"id": "b", "title": "T", "feedback": "not_useful"}"#)
        XCTAssertEqual(not.feedback, .notUseful)
    }

    func testAMissingUrlFallsBackToTheNotePage() throws {
        let one = try decode(DaydreamNote.self, #"{"id": "n 3", "title": "T"}"#)
        XCTAssertEqual(one.url, "/jkai/daydreams?note=n%203")
        XCTAssertEqual(one.body, "")
        XCTAssertEqual(one.outcome.label, "Noticed")
    }

    func testABadNoteDoesNotCostTheList() throws {
        let feed = try decode(DaydreamFeed.self, """
        {"notes": [\(note), {"title": "no id"}, {"id": "no-title"}, "not an object", {"id": 7, "title": "numeric id"}]}
        """)
        XCTAssertEqual(feed.notes.map(\.id), ["n1", "7"])
    }

    func testTheScopedFeedDecodes() throws {
        let feed = try decode(DaydreamFeed.self, "{\"notes\": [\(note)]}")
        XCTAssertEqual(feed.notes.first?.channel, .health)
        XCTAssertTrue(try decode(DaydreamFeed.self, "{}").notes.isEmpty)
    }

    // MARK: - Feedback

    func testTheFeedbackBodyIsTheContract() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        func body(_ verdict: DaydreamVerdict) throws -> String {
            String(decoding: try encoder.encode(DaydreamFeedbackRequest(id: "n1", verdict: verdict)), as: UTF8.self)
        }
        XCTAssertEqual(try body(.useful), #"{"id":"n1","verdict":"useful"}"#)
        XCTAssertEqual(try body(.notUseful), #"{"id":"n1","verdict":"not_useful"}"#)
        XCTAssertEqual(try body(.never), #"{"id":"n1","verdict":"never"}"#)
    }

    // MARK: - Demo

    func testTheDemoFixturesDecode() throws {
        let base = "https://strangeramblings.com/"
        let today = try JSONDecoder().decode(TodayPayload.self, from:
            SRDemoFixtures.reply(method: "GET", url: URL(string: base + "api/native/today")!, body: nil).body)
        XCTAssertEqual(today.daydream?.notes.count, 2, "the card shows two, so the demo sends two")

        let health = try JSONDecoder().decode(DaydreamFeed.self, from:
            SRDemoFixtures.reply(method: "GET", url: URL(string: base + "api/native/daydream?scope=health&limit=5")!, body: nil).body)
        XCTAssertFalse(health.notes.isEmpty)
        XCTAssertTrue(health.notes.allSatisfy { $0.channel == .health || $0.outcome == .healthPlan })

        let reply = SRDemoFixtures.reply(
            method: "POST", url: URL(string: base + "api/native/daydream/feedback")!,
            body: Data(#"{"id":"demo-note-sleep-walk","verdict":"useful"}"#.utf8))
        XCTAssertEqual(reply.status, 200)
    }
}
