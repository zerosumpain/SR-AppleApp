import XCTest
@testable import SRAppleApp

/// Rulings on a note's claim: the double-check's verdict and yours ("It's
/// wrong", with why), on the wire and in the lists.
final class DaydreamRulingTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func note(review: String) -> String {
        #"""
        {"notes": [{"id": "n", "outcome": "money_analysis", "channel": "money", "title": "Two £79 Apple charges",
           "body": "Twice.", "feedback": null, "summary": "Twice.", "next": null, "sources": [],
           "stage": "spotted", "bucket": "decide", "checkable": true, "commissionId": null, "commissionState": null,
           "review": \#(review)}]}
        """#
    }

    func testYourRulingDecodesWithItsLesson() throws {
        let feed = try decode(DaydreamFeed.self, note(review: #"""
        {"verdict": "wrong", "by": "owner", "reasoning": "One is the receipt email.", "lesson": "One is the receipt email."}
        """#))
        let review = try XCTUnwrap(feed.notes.first?.review)
        XCTAssertEqual(review.verdict, .wrong)
        XCTAssertTrue(review.byOwner)
        XCTAssertEqual(review.lesson, "One is the receipt email.")
        XCTAssertEqual(review.headline, "You said this is wrong")
    }

    func testACheckVerdictIsNotYourAnswer() throws {
        let feed = try decode(DaydreamFeed.self, note(review: #"{"verdict": "verified-ish", "by": "check", "reasoning": "?"}"#))
        let review = try XCTUnwrap(feed.notes.first?.review)
        // Anything unknown is unclear, never holds.
        XCTAssertEqual(review.verdict, .unclear)
        XCTAssertFalse(review.byOwner)
        XCTAssertEqual(review.headline, "A double-check could not settle this")
    }

    func testAMalformedRulingCostsOnlyItself() throws {
        let feed = try decode(DaydreamFeed.self, note(review: #"{"by": "owner"}"#))
        XCTAssertEqual(feed.notes.count, 1)
        XCTAssertNil(feed.notes.first?.review)
        XCTAssertNil(try decode(DaydreamFeed.self, note(review: "null")).notes.first?.review)
    }

    func testYourRulingAnswersTheNote() {
        XCTAssertEqual(DaydreamNote.derivedBucket(feedback: nil, commissionState: nil, ruled: true), .done)
        XCTAssertEqual(DaydreamNote.derivedBucket(feedback: nil, commissionState: nil, ruled: false), .decide)
        let mine = DaydreamNote(id: "n", outcome: .moneyAnalysis, channel: .money, title: "T", body: "", createdAt: "1",
                                review: DaydreamReview(verdict: .wrong, byOwner: true, reasoning: "x", lesson: "x"))
        XCTAssertEqual(mine.bucket, .done)
        let checked = DaydreamNote(id: "m", outcome: .moneyAnalysis, channel: .money, title: "T", body: "", createdAt: "1",
                                   review: DaydreamReview(verdict: .wrong, byOwner: false, reasoning: "x"))
        XCTAssertEqual(checked.bucket, .decide)
    }

    func testAPlainCopyKeepsTheRuling() {
        let detailed = DaydreamNote(id: "n", outcome: .moneyAnalysis, channel: .money, title: "T", body: "", createdAt: "1",
                                    review: DaydreamReview(verdict: .holds, byOwner: false, reasoning: "two bank lines"),
                                    detailed: true)
        let plain = DaydreamNote(id: "n", outcome: .moneyAnalysis, channel: .money, title: "T", body: "", createdAt: "1",
                                 feedback: .useful)
        XCTAssertEqual(detailed.merged(with: plain).review?.reasoning, "two bank lines")
    }

    func testTheRulingRequestCarriesWhy() throws {
        let body = try JSONEncoder().encode(DaydreamRulingRequest(id: "n", verdict: .wrong, why: "receipt"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(object, ["id": "n", "verdict": "wrong", "why": "receipt"])
    }

    // MARK: - The report

    func testTheReportLeadsWithItsVerdict() throws {
        let report = try decode(EvidenceReport.self, #"""
        {"summary": "It was wrong. One bank line.", "evidence": [],
         "review": {"verdict": "wrong", "claim": "Apple charged twice",
           "challenges": [{"doubt": "Is one an email?", "finding": "Yes.", "survives": false}, {"finding": "no doubt"}],
           "reasoning": "One bank line; the other is the receipt.", "lesson": "I check each charge has its own bank line.",
           "overruled": null, "model": "m", "checkedAt": "2026-10-02T08:00:00Z"}}
        """#)
        let review = try XCTUnwrap(report.review)
        XCTAssertEqual(review.verdict, .wrong)
        XCTAssertEqual(review.challenges, [.init(doubt: "Is one an email?", finding: "Yes.", survives: false)])
        XCTAssertEqual(review.lesson, "I check each charge has its own bank line.")
        XCTAssertNil(review.overruled)
    }

    func testAnOlderReportAndABrokenVerdictStillDecode() throws {
        XCTAssertNil(try decode(EvidenceReport.self, #"{"summary": "s", "evidence": []}"#).review)
        XCTAssertNil(try decode(EvidenceReport.self, #"{"summary": "s", "evidence": [], "review": null}"#).review)
        XCTAssertNil(try decode(EvidenceReport.self, #"{"summary": "s", "evidence": [], "review": {"claim": 3}}"#).review)
    }

    func testTheSiteSaysAvailableForASourceItRead() throws {
        let evidence = try decode([CommissionEvidence].self, #"""
        [{"sourceRef": "r", "tool": "spend", "retrievedAt": "", "contentHash": "", "text": "t", "status": "available", "provenance": "query_result"},
         {"sourceRef": "s", "tool": "spend", "retrievedAt": "", "contentHash": "", "text": "", "status": "unavailable", "provenance": "query_result"}]
        """#)
        XCTAssertEqual(evidence.map(\.wasRead), [true, false])
    }

    // MARK: - Do it for me

    func testDoItForMeDecodesAndAnswersTheNoteOnceDone() throws {
        let feed = try decode(DaydreamFeed.self, note(review: "null").replacingOccurrences(of: #""review": null"#,
            with: #""review": null, "act": {"status": "done", "label": "Added “Chase” to your Home calendar on Sat 10 Oct", "doneAt": "x"}"#))
        let act = try XCTUnwrap(feed.notes.first?.act)
        XCTAssertEqual(act.status, .done)
        XCTAssertFalse(act.canDo)
        let done = DaydreamNote(id: "n", outcome: .efficiency, channel: .mail, title: "T", body: "", createdAt: "1",
                                act: DaydreamAct(status: .done, label: "x"))
        XCTAssertEqual(done.bucket, .done)
        XCTAssertTrue(DaydreamAct(status: .open, label: "x").canDo)
        XCTAssertTrue(DaydreamAct(status: .undone, label: "x").canDo)
    }

    func testAnUnknownActStatusCostsOnlyTheAct() throws {
        let feed = try decode(DaydreamFeed.self, note(review: "null").replacingOccurrences(of: #""review": null"#,
            with: #""review": null, "act": {"status": "launch_rockets", "label": "?"}"#))
        XCTAssertEqual(feed.notes.count, 1)
        XCTAssertNil(feed.notes.first?.act)
    }

    func testTheActRequestSendsOnlyWhatItNeeds() throws {
        let body = try JSONEncoder().encode(DaydreamActRequest(id: "n", op: "do", calendar: nil))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(object, ["id": "n", "op": "do"])
    }

    func testADraftIsShownToReadAndASentOneCannotBeUndone() throws {
        let drafted = #"{"status": "done", "label": "Drafted a reply to orders@bikeshop.co.uk — read it, then send", "undoable": true, "draft": {"to": "orders@bikeshop.co.uk", "subject": "Re: Your order", "body": "Hello", "gmailUrl": "https://mail.google.com/mail/u/0/#drafts?compose=m1"}}"#
        let act = try decode(DaydreamAct.self, drafted)
        XCTAssertEqual(act.draft?.to, "orders@bikeshop.co.uk")
        XCTAssertTrue(act.undoable)
        let sent = try decode(DaydreamAct.self, #"{"status": "sent", "label": "Sent to orders@bikeshop.co.uk", "undoable": false}"#)
        XCTAssertEqual(sent.status, .sent)
        XCTAssertFalse(sent.undoable)
        let done = DaydreamNote(id: "n", outcome: .efficiency, channel: .mail, title: "T", body: "", createdAt: "1", act: sent)
        XCTAssertEqual(done.bucket, .done)
    }

    func testAnOlderServerWithoutUndoableStillOffersUndoOnADiaryEntry() throws {
        let act = try decode(DaydreamAct.self, #"{"status": "done", "label": "Added it"}"#)
        XCTAssertTrue(act.undoable)
        XCTAssertNil(act.draft)
    }

    func testTheDemoOffersDoItForMe() throws {
        let clock = SRDemoFixtures.DemoClock(now: Date())
        let feed = try decode(DaydreamFeed.self, SRDemoFixtures.daydreamFeed(scope: nil, limit: 40, detail: true, clock: clock))
        XCTAssertEqual(feed.notes.first { $0.id == "demo-note-renewals" }?.act?.status, .ready)
        let reply = try decode(DaydreamActReply.self, SRDemoFixtures.daydreamAct(Data(#"{"id":"demo-note-renewals","op":"do"}"#.utf8)))
        XCTAssertEqual(reply.status, "done")
    }

    func testTheDemoShowsAVerdict() throws {
        let clock = SRDemoFixtures.DemoClock(now: Date())
        let feed = try decode(DaydreamFeed.self, SRDemoFixtures.daydreamFeed(scope: nil, limit: 40, detail: true, clock: clock))
        let zone2 = try XCTUnwrap(feed.notes.first { $0.id == "demo-note-zone2" })
        XCTAssertEqual(zone2.review?.verdict, .holds)
        XCTAssertEqual(feed.notes.filter { $0.review != nil }.count, 1)
    }
}
