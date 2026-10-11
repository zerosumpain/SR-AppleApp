import XCTest
@testable import SRAppleApp

/// The family backlog: the wire contract (as SR-Main's
/// `/api/native/family/backlog` sends it), the page's filters and words, and
/// the share path's reading of shared text.
final class FamilyBacklogTests: XCTestCase {

    private let boardJSON = #"""
    { "me": { "id": "f_me", "parent": false },
      "people": [ { "id": "f_me", "name": "Kit" }, { "id": "f_p", "name": "Robin" } ],
      "items": [
        { "id": "b1", "kind": "video", "url": "https://www.youtube.com/watch?v=aaaaaaaaaaa", "provider": "youtube",
          "title": "Volcanoes", "siteName": "YouTube", "thumbnailUrl": "https://i.ytimg.com/vi/x/hqdefault.jpg",
          "note": "film night?", "forId": "f_me", "addedById": "f_p", "status": "new", "doneById": null, "doneAt": null,
          "createdAt": "2026-10-11T17:38:44.161Z", "updatedAt": "2026-10-11T17:38:44.161Z" },
        { "id": "b2", "kind": "page", "url": "https://www.example.com/walks", "provider": "web", "title": null,
          "siteName": null, "thumbnailUrl": null, "note": null, "forId": null, "addedById": "f_me", "status": "new",
          "doneById": null, "doneAt": null, "createdAt": "2026-10-11T12:00:00Z", "updatedAt": "2026-10-11T12:00:00Z" },
        { "id": "b3", "kind": "idea", "url": null, "provider": null, "title": "Go to the coast", "siteName": null,
          "thumbnailUrl": null, "note": null, "forId": null, "addedById": "f_p", "status": "new", "doneById": null,
          "doneAt": null, "createdAt": "2026-10-10T12:00:00Z", "updatedAt": "2026-10-10T12:00:00Z" } ],
      "finished": [
        { "id": "b4", "kind": "video", "url": "https://www.tiktok.com/@/video/12345", "provider": "tiktok", "title": null,
          "siteName": "TikTok", "thumbnailUrl": null, "note": null, "forId": null, "addedById": "f_p", "status": "dismissed",
          "doneById": "f_me", "doneAt": "2026-10-11T13:00:00Z", "createdAt": "2026-10-09T12:00:00Z",
          "updatedAt": "2026-10-11T13:00:00Z" } ] }
    """#

    private func board() throws -> FamilyBacklogBoard {
        try JSONDecoder().decode(FamilyBacklogBoard.self, from: Data(boardJSON.utf8))
    }

    func testDecodesTheSitesBoard() throws {
        let b = try board()
        XCTAssertEqual(b.me.id, "f_me")
        XCTAssertEqual(b.items.map(\.id), ["b1", "b2", "b3"])
        XCTAssertEqual(b.finished.first?.status, "dismissed")
        XCTAssertEqual(b.items.first?.thumbnailUrl, "https://i.ytimg.com/vi/x/hqdefault.jpg")
    }

    func testAMissingListIsEmptyNotAFailure() throws {
        let b = try JSONDecoder().decode(FamilyBacklogBoard.self, from: Data(#"{ "me": { "id": "f_me", "parent": true } }"#.utf8))
        XCTAssertTrue(b.items.isEmpty)
        XCTAssertTrue(b.finished.isEmpty)
    }

    func testShelvesSortByKind() throws {
        let b = try board()
        XCTAssertEqual(FamilyBacklogShelf.all.items(b).map(\.id), ["b1", "b2", "b3"])
        XCTAssertEqual(FamilyBacklogShelf.watch.items(b).map(\.id), ["b1"])
        XCTAssertEqual(FamilyBacklogShelf.read.items(b).map(\.id), ["b2"])
        XCTAssertEqual(FamilyBacklogShelf.ideas.items(b).map(\.id), ["b3"])
        XCTAssertEqual(FamilyBacklogShelf.done.items(b).map(\.id), ["b4"])
    }

    func testAnUntitledLinkIsCalledByItsSite() throws {
        let b = try board()
        XCTAssertEqual(FamilyBacklogText.title(b.items[0]), "Volcanoes")
        XCTAssertEqual(FamilyBacklogText.title(b.items[1]), "example.com")
        XCTAssertEqual(FamilyBacklogText.title(b.items[2]), "Go to the coast")
    }

    func testBylineNamesWhoAndForWhom() throws {
        let b = try board()
        let now = ISO8601DateFormatter().date(from: "2026-10-11T18:45:00Z")!
        XCTAssertEqual(FamilyBacklogRules.byline(b.items[0], b, now: now), "Robin · 1h · for you")
        XCTAssertTrue(FamilyBacklogRules.byline(b.items[1], b, now: now).hasPrefix("You · "))
        XCTAssertTrue(FamilyBacklogRules.byline(b.finished[0], b, now: now).hasSuffix("You passed"))
    }

    func testOnlyTheSharerOrAParentMayDelete() throws {
        var b = try board()
        XCTAssertFalse(FamilyBacklogRules.mayDelete(b.items[0], b))
        XCTAssertTrue(FamilyBacklogRules.mayDelete(b.items[1], b))
        b.me.parent = true
        XCTAssertTrue(FamilyBacklogRules.mayDelete(b.items[0], b))
    }

    func testMoreSaysWhatIsForYouFirst() throws {
        var b = try board()
        XCTAssertEqual(FamilyBacklogRules.status(b), "1 for you")
        b.items[0].forId = nil
        XCTAssertEqual(FamilyBacklogRules.status(b), "3 on the list")
        b.items = []
        XCTAssertNil(FamilyBacklogRules.status(b))
    }

    func testFindsTheLinkInATikTokCaption() {
        XCTAssertEqual(
            FamilyBacklogText.firstLink(in: "Look at this! https://vm.tiktok.com/ZNabc123/ #fyp")?.absoluteString,
            "https://vm.tiktok.com/ZNabc123/"
        )
        XCTAssertNil(FamilyBacklogText.firstLink(in: "Go to the coast"))
    }

    func testTheShareBodyIsWhatTheSiteReads() throws {
        let body = try JSONEncoder().encode(FamilyBacklogShare(url: "https://example.com", text: nil, note: "n", forId: nil))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["url"] as? String, "https://example.com")
        XCTAssertEqual(object["note"] as? String, "n")
    }

    func testAnOlderSiteWithoutReactionsStillDecodes() throws {
        let b = try board()
        XCTAssertNil(b.items[0].reactions)
        XCTAssertNil(b.items[0].taskId)
        XCTAssertFalse(b.digest)
        XCTAssertTrue(b.quickReactions.isEmpty)
    }

    func testReadsReactionsTheRoundUpAndTheTask() throws {
        let json = #"""
        { "me": { "id": "f_me", "parent": false }, "people": [], "quickReactions": ["👍", "❤️"], "digest": true,
          "items": [ { "id": "b1", "kind": "idea", "title": "Coast", "addedById": "f_p", "status": "new",
                       "createdAt": "2026-10-11T12:00:00Z", "taskId": null,
                       "reactions": [ { "emoji": "👍", "by": ["f_p", "f_me"] } ] } ],
          "finished": [ { "id": "b2", "kind": "idea", "title": "Whitby", "addedById": "f_p", "status": "done",
                          "createdAt": "2026-10-10T12:00:00Z", "taskId": "t9", "reactions": [] } ] }
        """#
        let b = try JSONDecoder().decode(FamilyBacklogBoard.self, from: Data(json.utf8))
        XCTAssertTrue(b.digest)
        XCTAssertEqual(b.quickReactions, ["👍", "❤️"])
        XCTAssertEqual(FamilyBacklogRules.myReaction(b.items[0], b), "👍")
        XCTAssertEqual(b.finished[0].taskId, "t9")
    }

    func testPickPrefersVideosAndNeverRepeatsWhileThereIsAChoice() throws {
        let b = try board()
        for _ in 0..<20 { XCTAssertEqual(FamilyBacklogRules.pick(b)?.kind, "video") }
        var noVideos = b
        noVideos.items = b.items.filter { $0.kind != "video" }
        for _ in 0..<20 {
            let last = FamilyBacklogRules.pick(noVideos)?.id
            XCTAssertNotEqual(FamilyBacklogRules.pick(noVideos, avoiding: last)?.id, last)
        }
        noVideos.items = []
        XCTAssertNil(FamilyBacklogRules.pick(noVideos))
    }

    func testTheTaskActionIsWhatTheSiteReads() {
        XCTAssertEqual(FamilyBacklogAction.toTask.rawValue, "to_task")
    }

    func testTheBacklogHasALink() {
        XCTAssertEqual(FamilyPage.from(url: URL(string: "sr://family/backlog")!), .backlog)
        XCTAssertEqual(FamilyPage.from(category: "family-backlog", userInfo: [:]), .backlog)
    }
}
