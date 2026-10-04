import XCTest
@testable import SRAppleApp

/// Today's four squares, the urgent banner, and the Daydream list they open.
final class TodayTilesTests: XCTestCase {

    // MARK: - Which tiles

    func testTheOwnerGetsAllFourInReadingOrder() {
        XCTAssertEqual(TodayTile.kinds(access: .everything, sitePaired: true), [.ask, .health, .daydream, .games])
    }

    func testWithoutTheSiteOnlyHealthAndGamesAreLeft() {
        // Ask and Daydream both ride the site credential.
        XCTAssertEqual(TodayTile.kinds(access: .everything, sitePaired: false), [.health, .games])
    }

    func testAMemberGetsNoDaydream() {
        let member = AppAccess(chat: true, family: true, games: true)
        XCTAssertEqual(TodayTile.kinds(access: member, sitePaired: true), [.ask, .health, .games])
    }

    func testAMemberWithoutChatOrGamesStillHasHealth() {
        XCTAssertEqual(TodayTile.kinds(access: AppAccess(family: true), sitePaired: true), [.health])
    }

    func testOvernightFollowsHealthOnceTheServerHasARead() {
        XCTAssertEqual(TodayTile.kinds(access: .everything, sitePaired: true, overnight: true),
                       [.ask, .health, .overnight, .daydream, .games])
        // No read yet: no door to nothing on the first screen.
        XCTAssertFalse(TodayTile.kinds(access: .everything, sitePaired: true, overnight: false).contains(.overnight))
        // The owner's /health, over the site credential.
        XCTAssertFalse(TodayTile.kinds(access: .everything, sitePaired: false, overnight: true).contains(.overnight))
        let member = AppAccess(chat: true, family: true, games: true)
        XCTAssertFalse(TodayTile.kinds(access: member, sitePaired: true, overnight: true).contains(.overnight))
    }

    // MARK: - The overnight read

    private func today(_ json: String) throws -> TodayPayload {
        try JSONDecoder().decode(TodayPayload.self, from: Data(json.utf8))
    }

    func testTodayCarriesTheOvernightRead() throws {
        let payload = try today(#"{"generatedAt": "x", "overnight": {"headline": "SpO₂ apart last night", "brief": "SpO₂ 96.1 · 92.6%", "tone": "watch"}}"#)
        XCTAssertEqual(payload.overnight, TodayOvernight(headline: "SpO₂ apart last night", brief: "SpO₂ 96.1 · 92.6%", tone: .watch))
    }

    func testAnOlderOrBrokenOvernightCostsOnlyTheTile() throws {
        XCTAssertNil(try today(#"{"generatedAt": "x"}"#).overnight)
        XCTAssertNil(try today(#"{"generatedAt": "x", "overnight": null}"#).overnight)
        let broken = try today(#"{"generatedAt": "x", "overnight": "soon", "daydream": {"notes": []}}"#)
        XCTAssertNil(broken.overnight)
        XCTAssertNotNil(broken.daydream, "the rest of Today still decodes")
    }

    func testTheDemoTodayAndHealthTellOneStory() throws {
        let payload = try today(SRDemoFixtures.today(SRDemoFixtures.DemoClock(now: Date())))
        let hub = try JSONDecoder().decode(HubDigest.self, from: Data(SRDemoFixtures.healthHub.utf8))
        XCTAssertEqual(payload.overnight?.headline, hub.vitals?.headline)
    }

    // MARK: - The urgent banner

    private func alert(_ id: String, severity: String = "alert", read: Bool = false) -> SiteAlert {
        SiteAlert(id: id, category: "home", title: "Alert \(id)", body: "", url: nil,
                  severity: severity, createdAt: "2026-09-27T08:00:00Z", read: read)
    }

    func testTheNewestUnreadAlertTakesTheBanner() {
        let recent = [alert("info", severity: "info"), alert("loud"), alert("older")]
        XCTAssertEqual(TodayAlerts.urgent(in: recent, dismissed: [])?.id, "loud")
    }

    func testHighCountsAsUrgentToo() {
        XCTAssertEqual(TodayAlerts.urgent(in: [alert("h", severity: "high")], dismissed: [])?.id, "h")
    }

    func testNothingQuieterThanAnAlertEverTakesTheBanner() {
        let recent = [alert("i", severity: "info"), alert("w", severity: "warn")]
        XCTAssertNil(TodayAlerts.urgent(in: recent, dismissed: []))
    }

    func testAReadOrWavedAlertGivesWayToTheNext() {
        let recent = [alert("read", read: true), alert("waved"), alert("next")]
        XCTAssertEqual(TodayAlerts.urgent(in: recent, dismissed: ["waved"])?.id, "next")
        XCTAssertNil(TodayAlerts.urgent(in: recent, dismissed: ["waved", "next"]))
    }

    // MARK: - The Daydream list

    private func note(_ id: String, at createdAt: String, title: String = "T") -> DaydreamNote {
        DaydreamNote(id: id, outcome: .research, channel: .health, title: title, body: "", createdAt: createdAt)
    }

    func testMergingKeepsOneOfEachNewestFirst() {
        let held = [note("a", at: "2026-09-27T08:00:00Z"), note("b", at: "2026-09-27T07:00:00Z")]
        let incoming = [note("c", at: "2026-09-27T09:00:00Z"), note("a", at: "2026-09-27T08:00:00Z")]
        XCTAssertEqual(DaydreamStore.merge(held, incoming).map(\.id), ["c", "a", "b"])
    }

    func testTodaysShortListDoesNotShrinkThePage() {
        let page = (0..<5).map { note("n\($0)", at: "2026-09-27T0\($0):00:00Z") }
        let today = Array(page.suffix(2))
        XCTAssertEqual(DaydreamStore.merge(page, today).count, 5)
    }

    func testALaterCopyOfANoteWins() {
        let held = [note("a", at: "2026-09-27T08:00:00Z", title: "Old")]
        let incoming = [note("a", at: "2026-09-27T08:00:00Z", title: "New")]
        XCTAssertEqual(DaydreamStore.merge(held, incoming).first?.title, "New")
    }
}
