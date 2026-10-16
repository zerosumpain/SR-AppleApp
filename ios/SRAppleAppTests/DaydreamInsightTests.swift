import XCTest
@testable import SRAppleApp

/// Why in one tap, the repeats folded into a note, and the living week plan:
/// the keys the site added on 2026-10-16, and an older server that sends none.
final class DaydreamInsightTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func note(_ extra: String) -> String {
        #"{"id": "n", "outcome": "health_plan", "channel": "health", "title": "Recovery-first week", "body": "Walk today.", "createdAt": "2026-10-16T09:00:00Z", "stage": "decide", "bucket": "decide""# + extra + "}"
    }

    func testTheNewKeysDecode() throws {
        let n = try decode(DaydreamNote.self, note(#", "reason": "already_knew", "seenAgain": ["2026-10-15", "2026-10-16"], "living": true"#))
        XCTAssertEqual(n.reason, .alreadyKnew)
        XCTAssertEqual(n.seenAgain, ["2026-10-15", "2026-10-16"])
        XCTAssertTrue(n.living)
    }

    func testAnOlderServerSendsNone() throws {
        let n = try decode(DaydreamNote.self, note(""))
        XCTAssertNil(n.reason)
        XCTAssertEqual(n.seenAgain, [])
        XCTAssertFalse(n.living)
    }

    func testBadValuesCostTheValueNotTheNote() throws {
        let n = try decode(DaydreamNote.self, note(#", "reason": "meh", "seenAgain": "soon", "living": "yes""#))
        XCTAssertNil(n.reason)
        XCTAssertEqual(n.seenAgain, [])
        XCTAssertFalse(n.living)
        XCTAssertEqual(n.title, "Recovery-first week")
    }

    func testTheReasonsOfferedAfterEachVerdict() {
        XCTAssertEqual(DaydreamReason.after(.useful), [.didIt])
        XCTAssertEqual(DaydreamReason.after(.notUseful), [.alreadyKnew, .notNow, .notMyThing])
        XCTAssertEqual(DaydreamReason.after(.never), [])
        XCTAssertNil(DaydreamReason.notNow.verdict)
        XCTAssertEqual(DaydreamReason.didIt.verdict, .useful)
    }

    func testTheReasonRequestBody() throws {
        let data = try JSONEncoder().encode(DaydreamReasonRequest(id: "n1", reason: .notNow))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(object, ["id": "n1", "reason": "not_now"])
    }

    func testADetailedCopyKeepsItsKeysWhenAPlainOneArrives() throws {
        let detailed = try decode(DaydreamNote.self, note(#", "seenAgain": ["2026-10-15"], "living": true"#))
        let plain = try decode(DaydreamNote.self, #"{"id": "n", "title": "Recovery-first week", "body": "Walk today.", "feedback": "useful"}"#)
        let merged = detailed.merged(with: plain)
        XCTAssertEqual(merged.feedback, .useful)
        XCTAssertEqual(merged.seenAgain, ["2026-10-15"])
        XCTAssertTrue(merged.living)
    }

    func testTheDayReadsShort() {
        XCTAssertEqual(DaydreamNoteCard.shortDay("2026-10-15"), "15 Oct")
        XCTAssertEqual(DaydreamNoteCard.shortDay("soon"), "soon")
    }
}
