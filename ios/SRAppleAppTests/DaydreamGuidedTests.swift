import XCTest
@testable import SRAppleApp

/// The guided Daydream page: the detailed wire (`?detail=1`), what the phone
/// works out for itself when an older server sends only plain notes, the
/// counts and lists, and the words a double-check's reads are given.
final class DaydreamGuidedTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private let detailed = #"""
    {"notes": [{"id": "n", "outcome": "money_analysis", "channel": "money", "title": "Canva twice",
       "body": "Two plans.\n\nNext: Cancel one.", "createdAt": "2026-09-28T08:00:00Z", "url": "/jkai/daydreams?note=n",
       "feedback": null, "summary": "Two plans.", "next": "Cancel one.",
       "sources": ["Bank spend · Canva · last 60 days", "Web page · gov.uk"],
       "stage": "decide", "bucket": "decide", "checkable": true,
       "commissionId": "11111111-1111-4111-8111-111111111111", "commissionState": "awaiting_approval"}],
     "pipeline": {"decide": 3, "motion": 1, "done": 40},
     "impact": {"windowDays": 28, "hitRate": 0.72, "previousHitRate": 0.55, "noticed": 57, "rated": 13,
       "useful": 13, "actedOn": 1, "result": 1,
       "weeks": [{"start": "2026-07-13", "useful": 15, "notUseful": 12, "undecided": 50}]}}
    """#

    // MARK: - The detailed wire

    func testTheDetailedFeedDecodes() throws {
        let feed = try decode(DaydreamFeed.self, detailed)
        let note = try XCTUnwrap(feed.notes.first)
        XCTAssertEqual(note.summary, "Two plans.")
        XCTAssertEqual(note.next, "Cancel one.")
        XCTAssertEqual(note.sources, ["Bank spend · Canva · last 60 days", "Web page · gov.uk"])
        XCTAssertEqual(note.stage, .decide)
        XCTAssertEqual(note.bucket, .decide)
        XCTAssertEqual(note.checkable, true)
        XCTAssertEqual(note.commissionId, "11111111-1111-4111-8111-111111111111")
        XCTAssertEqual(note.commissionState, "awaiting_approval")
        XCTAssertTrue(note.detailed)
        XCTAssertEqual(feed.pipeline, DaydreamPipeline(decide: 3, motion: 1, done: 40))

        let impact = try XCTUnwrap(feed.impact)
        XCTAssertEqual(impact.windowDays, 28)
        XCTAssertEqual(impact.hitRateText, "72%")
        XCTAssertEqual(impact.deltaPoints, 17)
        XCTAssertEqual(impact.answeredShare ?? 0, 13.0 / 57.0, accuracy: 0.0001)
        XCTAssertEqual(impact.weeks.count, 1)
        XCTAssertEqual(impact.weeks.first?.total, 77)
        XCTAssertNotNil(impact.weeks.first?.date)
    }

    func testAnOlderServerStillWorks() throws {
        // No `detail` support: plain notes, no pipeline, no impact.
        let feed = try decode(DaydreamFeed.self, #"""
        {"notes": [
          {"id": "a", "title": "T", "body": "One.\n\nTwo.\n\nNext: Do it.", "feedback": null},
          {"id": "b", "title": "U", "body": "Plain.", "feedback": "useful"}]}
        """#)
        XCTAssertNil(feed.pipeline)
        XCTAssertNil(feed.impact)
        let open = feed.notes[0]
        XCTAssertEqual(open.summary, "One.\n\nTwo.")
        XCTAssertEqual(open.next, "Do it.")
        XCTAssertEqual(open.bucket, .decide)
        XCTAssertEqual(open.stage, .decide)
        XCTAssertNil(open.checkable, "an older server does not say, so the phone offers the check")
        XCTAssertTrue(open.sources.isEmpty)
        XCTAssertFalse(open.detailed)
        let answered = feed.notes[1]
        XCTAssertNil(answered.next)
        XCTAssertEqual(answered.summary, "Plain.")
        XCTAssertEqual(answered.bucket, .done)
        XCTAssertEqual(answered.stage, .result)
    }

    func testANullNextFromTheServerIsNoNextStep() throws {
        // The detailed server has already split the body; `null` means none,
        // even though the body still reads as if it had one.
        let note = try decode(DaydreamNote.self, #"""
        {"id": "n", "title": "T", "body": "S\n\nNext: X", "summary": "S", "next": null, "stage": "result", "bucket": "done"}
        """#)
        XCTAssertNil(note.next)
        XCTAssertEqual(note.summary, "S")
    }

    func testWrongShapesCostOnlyTheirOwnBlock() throws {
        let feed = try decode(DaydreamFeed.self, #"""
        {"notes": [{"id": "n", "title": "T", "sources": ["ok", 4, "", null], "stage": "sideways", "bucket": 7,
                    "checkable": "yes", "commissionState": ""}],
         "pipeline": "soon", "impact": [1, 2]}
        """#)
        XCTAssertNil(feed.pipeline)
        XCTAssertNil(feed.impact)
        let note = try XCTUnwrap(feed.notes.first)
        XCTAssertEqual(note.sources, ["ok"])
        XCTAssertEqual(note.bucket, .decide, "an unknown bucket falls back to the verdict")
        XCTAssertEqual(note.stage, .decide)
        XCTAssertNil(note.checkable)
        XCTAssertNil(note.commissionState)
    }

    func testCountsArriveInWhateverNumberShapeTheServerUses() throws {
        let pipeline = try decode(DaydreamPipeline.self, #"{"decide": 3.0, "motion": "1", "done": -2}"#)
        XCTAssertEqual(pipeline, DaydreamPipeline(decide: 3, motion: 1, done: 0))
        let impact = try decode(DaydreamImpact.self, #"{"hitRate": 1.4, "weeks": [{"useful": 1}, {"start": "2026-07-20"}]}"#)
        XCTAssertEqual(impact.windowDays, 28)
        XCTAssertEqual(impact.hitRateText, "100%")
        XCTAssertNil(impact.deltaPoints, "no previous rate, no delta")
        XCTAssertNil(impact.answeredShare, "nothing noticed, no share")
        XCTAssertEqual(impact.weeks.map(\.start), ["2026-07-20"], "a week without a start is dropped alone")
    }

    // MARK: - Fallbacks

    func testTheNextStepSplitsOnlyOnTheFinalParagraph() {
        XCTAssertEqual(DaydreamNote.split("A\n\nNext: B").next, "B")
        XCTAssertEqual(DaydreamNote.split("A\n\nNext: B").summary, "A")
        XCTAssertNil(DaydreamNote.split("A\n\nNext: B\n\nC").next, "a later paragraph means it was not the last")
        XCTAssertNil(DaydreamNote.split("A\n\nNext:   ").next, "an empty step is no step")
        XCTAssertNil(DaydreamNote.split("Next: B").next, "not a paragraph of its own")
        XCTAssertNil(DaydreamNote.split("Plain.").next)
        XCTAssertEqual(DaydreamNote.split("  Plain.  ").summary, "Plain.")
        XCTAssertEqual(DaydreamNote.split("A\n\nNext: one\n\nNext: two").next, "two")
    }

    func testTheBucketFallsBackToTheVerdictAndTheDoubleCheck() {
        XCTAssertEqual(DaydreamNote.derivedBucket(feedback: nil, commissionState: nil), .decide)
        XCTAssertEqual(DaydreamNote.derivedBucket(feedback: .useful, commissionState: nil), .done)
        XCTAssertEqual(DaydreamNote.derivedBucket(feedback: .notUseful, commissionState: nil), .done)
        XCTAssertEqual(DaydreamNote.derivedBucket(feedback: .never, commissionState: nil), .done)
        XCTAssertEqual(DaydreamNote.derivedBucket(feedback: nil, commissionState: "awaiting_approval"), .decide)
        XCTAssertEqual(DaydreamNote.derivedBucket(feedback: .useful, commissionState: "deferred"), .decide)
        XCTAssertEqual(DaydreamNote.derivedBucket(feedback: nil, commissionState: "queued"), .motion)
        XCTAssertEqual(DaydreamNote.derivedBucket(feedback: nil, commissionState: "running"), .motion)
        XCTAssertEqual(DaydreamNote.derivedBucket(feedback: nil, commissionState: "needs_attention"), .motion)
        XCTAssertEqual(DaydreamNote.derivedBucket(feedback: nil, commissionState: "completed"), .done)
        XCTAssertEqual(DaydreamNote.derivedBucket(feedback: nil, commissionState: "declined"), .decide)
        XCTAssertEqual(DaydreamNote.derivedBucket(feedback: .useful, commissionState: "cancelled"), .done)
        XCTAssertEqual(DaydreamBucket.done.stage, .result)
    }

    func testAPlainCopyDoesNotEraseADetailedOne() throws {
        let rich = try XCTUnwrap(try decode(DaydreamFeed.self, detailed).notes.first)
        // Today's five-minute re-read: the same note, plain, answered on the site.
        let plain = DaydreamNote(id: "n", outcome: .moneyAnalysis, channel: .money, title: "Canva twice",
                                 body: "Two plans.\n\nNext: Cancel one.", createdAt: "2026-09-28T08:00:00Z",
                                 feedback: .useful)
        let merged = DaydreamStore.merge([rich], [plain])
        XCTAssertEqual(merged.count, 1)
        let kept = merged[0]
        XCTAssertEqual(kept.feedback, .useful, "the later verdict comes through")
        XCTAssertEqual(kept.sources, rich.sources, "the sources stay")
        XCTAssertEqual(kept.commissionId, rich.commissionId)
        XCTAssertTrue(kept.detailed)
        XCTAssertEqual(kept.bucket, .decide, "a double-check waiting for an OK still wants the call")
        // A detailed copy always wins.
        XCTAssertEqual(DaydreamStore.merge([plain], [rich]).first, rich)
    }

    func testThePipelineMovesWithAnswersGivenOnThePhone() {
        let notes = [
            DaydreamNote(id: "a", outcome: .research, channel: .health, title: "A", body: "", createdAt: "1"),
            DaydreamNote(id: "b", outcome: .research, channel: .health, title: "B", body: "", createdAt: "2"),
        ]
        let base = DaydreamPipeline(decide: 3, motion: 1, done: 40)
        XCTAssertEqual(base.adjusted(for: notes) { $0.bucket }, base, "nothing moved, nothing changes")
        let moved = base.adjusted(for: notes) { $0.id == "a" ? .done : .motion }
        XCTAssertEqual(moved, DaydreamPipeline(decide: 1, motion: 2, done: 41))
        XCTAssertEqual(DaydreamPipeline(decide: 0, motion: 0, done: 0).adjusted(for: notes) { _ in .done }.decide, 0,
                       "never below zero")
    }

    func testEveryStageHasPlainWords() {
        XCTAssertEqual(DaydreamStage.allCases.map(\.label), ["Spotted", "Your call", "In motion", "Result"])
        XCTAssertEqual(DaydreamStage.allCases.map(\.number), [1, 2, 3, 4])
        for stage in DaydreamStage.allCases {
            XCTAssertFalse(stage.explanation.isEmpty)
            for jargon in ["commission", "evidence refresh", "workflow", "scope"] {
                XCTAssertFalse(stage.explanation.lowercased().contains(jargon), "\(stage): \(jargon)")
            }
        }
        XCTAssertEqual(DaydreamChannel(raw: "money").label, "Money")
        XCTAssertEqual(DaydreamChannel(raw: "").label, "Mixed")
        XCTAssertEqual(DaydreamChannel(raw: "garden_shed").label, "Garden shed")
    }

    // MARK: - A double-check's reads, in words

    private func words(_ tool: String, _ args: String) -> String {
        EvidenceSourceLabel.describe(tool: tool, args: JSONValue.parse(args) ?? .null)
    }

    func testEveryReadIsNamedInPlainWords() {
        XCTAssertEqual(words("spend", #"{"merchant": "Canva", "days": 60}"#), "Bank spend · Canva · last 60 days")
        XCTAssertEqual(words("spend", "{}"), "Bank spend · last 60 days")
        XCTAssertEqual(words("mail_facts", #"{"query": "renewal", "daysBack": 30}"#),
                       "Mail (facts, not bodies) · \u{201C}renewal\u{201D} · last 30 days")
        XCTAssertEqual(words("mail_facts", "{}"), "Mail (facts, not bodies) · last 14 days")
        XCTAssertEqual(words("diary", #"{"from": "2026-09-01", "to": "2026-09-30"}"#), "Your diary · 2026-09-01 to 2026-09-30")
        XCTAssertEqual(words("diary", #"{"from": "-7d"}"#), "Your diary · 7 days ago to 14 days ahead")
        XCTAssertEqual(words("chat_threads", #"{"days": 7}"#), "Your jkai chats · last 7 days")
        XCTAssertEqual(words("activities", #"{"limit": 10}"#), "Recent workouts and outings")
        XCTAssertEqual(words("health_hub", "{}"), "Your /health summary")
        XCTAssertEqual(words("health_series", #"{"metric": "resting_hr", "days": 14}"#), "Health trend · resting hr · last 14 days")
        XCTAssertEqual(words("correlate", #"{"a": "sleep", "b": "hrv"}"#), "Tested a link · sleep against hrv")
        XCTAssertEqual(words("ha_find", #"{"domain": ["light", "lock"], "area": "hall"}"#), "Home sensors · light, lock, hall")
        XCTAssertEqual(words("ha_find", #"{"query": "garage door"}"#), "Home sensors · \u{201C}garage door\u{201D}")
        XCTAssertEqual(words("ha_query_state", #"{"entity_id": "light.hallway_ceiling"}"#), "Home \u{2014} current state · hallway ceiling")
        XCTAssertEqual(words("ha_get_history", #"{"entityId": "sensor.front_door"}"#), "Home \u{2014} history · front door")
        XCTAssertEqual(words("memory_search", #"{"query": "anything"}"#), "jkai memory")
        XCTAssertEqual(words("research_web_search", #"{"query": "zone 2"}"#), "Web search · \u{201C}zone 2\u{201D}")
        XCTAssertEqual(words("fetch_url", #"{"url": "https://www.gov.uk/guidance"}"#), "Web page · gov.uk")
        XCTAssertEqual(words("some_new_tool", "{}"), "Some new tool")
    }

    func testTheSignOffSheetSaysItsLimitsPlainly() {
        let budget = CommissionBudget(maxReads: 2, maxAttempts: 3, maxWallSeconds: 180)
        XCTAssertEqual(budget.plainLimits,
                       ["2 look-ups, nothing else", "Up to 3 tries, 3 minutes each", "Carries on if you close the app"])
        XCTAssertEqual(CommissionBudget(maxReads: 1, maxAttempts: 1, maxWallSeconds: 45).plainLimits,
                       ["1 look-up, nothing else", "1 try, 45 seconds each", "Carries on if you close the app"])
    }

    func testStatesReadAsTheSiteWordsThem() {
        let words = ["awaiting_approval": "Waiting for your OK", "deferred": "Put off for now", "declined": "Declined",
                     "queued": "Queued", "running": "Checking now", "needs_attention": "Needs you",
                     "completed": "Report ready", "cancelled": "Cancelled"]
        for (state, label) in words { XCTAssertEqual(DaydreamCommission.stateLabel(state), label, state) }
        XCTAssertEqual(DaydreamCommission.step(for: "awaiting_approval", approved: false), 0)
        XCTAssertEqual(DaydreamCommission.step(for: "queued", approved: true), 1)
        XCTAssertEqual(DaydreamCommission.step(for: "needs_attention", approved: true), 2)
        XCTAssertEqual(DaydreamCommission.step(for: "completed", approved: true), 3)
        XCTAssertEqual(DaydreamCommission.step(for: "cancelled", approved: false), 0)
    }

    // MARK: - Demo

    func testTheDemoFillsEveryList() throws {
        let base = "https://strangeramblings.com/"
        let reply = SRDemoFixtures.reply(method: "GET", url: URL(string: base + "api/native/daydream?detail=1&limit=40")!, body: nil)
        let feed = try JSONDecoder().decode(DaydreamFeed.self, from: reply.body)
        XCTAssertEqual(Set(feed.notes.map(\.bucket)), [.decide, .motion, .done])
        XCTAssertNotNil(feed.pipeline)
        XCTAssertEqual(feed.impact?.weeks.count, 12)
        XCTAssertTrue(feed.notes.contains { $0.next != nil })
        XCTAssertTrue(feed.notes.allSatisfy { !$0.sources.isEmpty })

        let commissions = try JSONDecoder().decode(CommissionFeed.self, from: Data(
            try XCTUnwrap(CommissionDemoFixtures.reply(method: "GET", query: [:], body: nil)).utf8))
        XCTAssertTrue(commissions.enabled)
        // Every demo double-check belongs to a demo note, so none is orphaned.
        let ids = Set(feed.notes.map(\.id))
        XCTAssertTrue(commissions.commissions.allSatisfy { ids.contains($0.thoughtId) })
    }
}
