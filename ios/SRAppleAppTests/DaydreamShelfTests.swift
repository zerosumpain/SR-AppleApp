import XCTest
@testable import SRAppleApp

/// Notes past their date: the `stale` flag on a note, the site's count on the
/// feed, an older server that sends neither, and the shelf request bodies.
final class DaydreamShelfTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func note(stale: String) -> String {
        #"{"id": "n", "outcome": "research", "channel": "research", "title": "Walk", "body": "A walk.", "createdAt": "2026-10-03T09:00:00Z", "stage": "spotted", "bucket": "decide", "stale": "# + stale + "}"
    }

    func testAFlaggedNoteAndTheCountDecode() throws {
        let json = #"{"notes": ["# + note(stale: #"{"until": "2026-10-09", "basis": "date", "why": "The date it is about, 9 Oct, has passed."}"#) + #"], "stale": 136}"#
        let feed = try decode(DaydreamFeed.self, json)
        XCTAssertEqual(feed.stale, 136)
        XCTAssertEqual(feed.notes.first?.stale, DaydreamStale(until: "2026-10-09", basis: "date", why: "The date it is about, 9 Oct, has passed."))
    }

    func testAnOlderServerSendsNoFlagAndNoCount() throws {
        let feed = try decode(DaydreamFeed.self, #"{"notes": [{"id": "n", "title": "Walk", "body": "A walk."}]}"#)
        XCTAssertNil(feed.stale)
        XCTAssertNil(feed.notes.first?.stale)
    }

    func testABadFlagCostsTheFlagNotTheNote() throws {
        for bad in [#""soon""#, #"{"until": "2026-10-09"}"#, "[1]"] {
            let feed = try decode(DaydreamFeed.self, #"{"notes": ["# + note(stale: bad) + #"], "stale": "x"}"#)
            XCTAssertEqual(feed.notes.count, 1, bad)
            XCTAssertNil(feed.notes.first?.stale, bad)
            XCTAssertNil(feed.stale)
        }
        XCTAssertEqual(try decode(DaydreamFeed.self, #"{"notes": [], "stale": -3}"#).stale, 0)
    }

    func testAPlainCopyKeepsTheFlag() throws {
        let detailed = try XCTUnwrap(try decode(DaydreamFeed.self, #"{"notes": ["# + note(stale: #"{"why": "Old."}"#) + #"]}"#).notes.first)
        let plain = DaydreamNote(id: "n", outcome: .research, channel: .research, title: "Walk", body: "A walk.", createdAt: "2026-10-03T09:00:00Z", feedback: .useful)
        XCTAssertEqual(detailed.merged(with: plain).stale?.why, "Old.")
    }

    func testTheShelfRequests() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        func json(_ r: DaydreamShelfRequest) throws -> String { String(decoding: try encoder.encode(r), as: UTF8.self) }
        XCTAssertEqual(try json(.file("n")), #"{"id":"n","op":"file"}"#)
        XCTAssertEqual(try json(.keep("n")), #"{"id":"n","op":"keep"}"#)
        XCTAssertEqual(try json(.fileAll), #"{"all":true,"op":"file"}"#)
    }

    func testTheDemoHasANotePastItsDate() throws {
        let base = "https://strangeramblings.com/"
        let all = try JSONDecoder().decode(DaydreamFeed.self, from: SRDemoFixtures.reply(
            method: "GET", url: URL(string: base + "api/native/daydream?detail=1&limit=40")!, body: nil).body)
        XCTAssertEqual(all.stale, 1)
        let only = try JSONDecoder().decode(DaydreamFeed.self, from: SRDemoFixtures.reply(
            method: "GET", url: URL(string: base + "api/native/daydream?detail=1&stale=1&limit=80")!, body: nil).body)
        XCTAssertEqual(only.notes.map(\.id), ["demo-note-open-studios"])
        XCTAssertNotNil(only.notes.first?.stale)
    }
}
