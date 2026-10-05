import XCTest
@testable import SRAppleApp

/// "Take it further" on the phone: the wire the site sends with each detailed
/// note (SR-Main `act/follow.ts`), what an unknown or malformed piece costs,
/// and the request the phone sends back.
final class DaydreamFollowTests: XCTestCase {

    private func note(_ follow: String, replaces: String = "[]") throws -> DaydreamNote {
        let json = """
        {"id": "n", "outcome": "suggest", "channel": "research", "title": "Book the Barns Ness walk on 16 October",
         "body": "A walk.", "createdAt": "2026-10-05T13:30:00Z", "summary": "A walk.", "next": null,
         "stage": "spotted", "bucket": "decide", "follow": \(follow), "replaces": \(replaces)}
        """
        return try JSONDecoder().decode(DaydreamNote.self, from: Data(json.utf8))
    }

    func testOffersBriefMessageAndHomeDecode() throws {
        let n = try note(#"""
        {"bookingUrl": "https://example.org/walks", "offers": [
           {"kind": "research", "state": "done", "label": "Research started", "cost": "9 searches", "href": "/research/r1"},
           {"kind": "build", "state": "drafted", "label": "Accept for build", "cost": "3.4M tokens"},
           {"kind": "watch", "state": "offer", "label": "Watch for this instead", "cost": "a few calls"},
           {"kind": "home", "state": "drafted", "label": "Choose what to refresh", "cost": "no call"}],
         "brief": {"outcome": "Name rooms with dead sensors", "acceptance": ["Lists each", 7], "effort": "S", "risk": "low", "readiness": "ready", "acceptedAt": null},
         "watchDraft": "Tell me when the hall drops out.",
         "message": {"text": "Hello, are places left?", "subject": "Walk", "whatsapp": "https://wa.me/447700900123?text=Hello", "mailto": null, "email": null, "draft": null},
         "home": {"found": [{"id": "climate.hall", "name": "Hall"}], "refreshed": [], "refreshedAt": null}}
        """#, replaces: #"[{"id": "old", "title": "The 1 November walk"}]"#)
        let f = try XCTUnwrap(n.follow)
        XCTAssertEqual(f.bookingUrl, "https://example.org/walks")
        XCTAssertEqual(f.pending.map(\.kind), [.watch])
        XCTAssertEqual(f.settled.map(\.href), ["/research/r1"])
        XCTAssertEqual(f.briefToRead?.acceptance, ["Lists each"]) // a non-string criterion is dropped alone
        XCTAssertEqual(f.briefToRead?.meta, "Effort S · risk low · ready")
        XCTAssertEqual(f.watchDraft, "Tell me when the hall drops out.")
        XCTAssertEqual(f.message?.hasNumber, true)
        XCTAssertEqual(f.home?.found.map(\.id), ["climate.hall"])
        XCTAssertEqual(n.replaces, [DaydreamReplaced(id: "old", title: "The 1 November walk")])
    }

    func testAnUnknownOfferIsDroppedAloneAndABadBlockCostsOnlyItself() throws {
        let f = try XCTUnwrap(try note(#"{"offers": [{"kind": "pay", "state": "offer", "label": "x", "cost": "y"}, {"kind": "promote", "state": "offer", "label": "Put it on the build backlog", "cost": "free"}], "message": {"text": ""}}"#).follow)
        XCTAssertEqual(f.offers.map(\.kind), [.promote])
        XCTAssertNil(f.message)
        // A follow block of the wrong shape costs the block, never the note.
        let broken = try note(#""not an object""#)
        XCTAssertNil(broken.follow)
        XCTAssertEqual(broken.title, "Book the Barns Ness walk on 16 October")
    }

    func testAnAcceptedBriefIsNoLongerOfferedForReading() throws {
        let f = try XCTUnwrap(try note(#"{"offers": [{"kind": "build", "state": "drafted", "label": "Accept", "cost": "c"}], "brief": {"outcome": "o", "acceptance": [], "acceptedAt": "2026-10-05T20:00:00Z"}}"#).follow)
        XCTAssertNil(f.briefToRead)
    }

    func testAWhatsAppLinkWithoutANumberSaysSo() throws {
        let f = try XCTUnwrap(try note(#"{"offers": [], "message": {"text": "Hello there", "whatsapp": "https://wa.me/?text=Hello"}}"#).follow)
        XCTAssertEqual(f.message?.hasNumber, false)
        XCTAssertFalse(f.isEmpty)
    }

    func testAnOlderServerSendsNoFollowUps() throws {
        let json = #"{"id": "n", "outcome": "suggest", "channel": "research", "title": "T", "body": "B", "createdAt": "2026-10-05T13:30:00Z"}"#
        let n = try JSONDecoder().decode(DaydreamNote.self, from: Data(json.utf8))
        XCTAssertNil(n.follow)
        XCTAssertEqual(n.replaces, [])
    }

    func testTheRequestCarriesOnlyWhatTheTapNeeds() throws {
        let data = try JSONEncoder().encode(DaydreamFollowRequest(id: "n", op: "home_refresh", description: nil, entities: ["climate.hall"]))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["op"] as? String, "home_refresh")
        XCTAssertEqual(object["entities"] as? [String], ["climate.hall"])
        XCTAssertNil(object["description"])
    }

    func testTheDemoFeedCarriesFollowUps() throws {
        let feed = try JSONDecoder().decode(DaydreamFeed.self, from: Data(SRDemoFixtures.daydreamFeed(scope: nil, limit: 40, detail: true, clock: SRDemoFixtures.DemoClock(now: Date())).utf8))
        let hall = try XCTUnwrap(feed.notes.first { $0.id == "demo-note-hall-light" })
        XCTAssertEqual(hall.follow?.home?.found.count, 2)
        let zone2 = try XCTUnwrap(feed.notes.first { $0.id == "demo-note-zone2" })
        XCTAssertEqual(zone2.follow?.message?.text.hasPrefix("Hello"), true)
    }
}
