import XCTest
@testable import SRAppleApp

final class NewsTests: XCTestCase {
    private func story(favourite: Bool?) throws -> NewsStory {
        var json: [String: Any] = [
            "key": "hn:1", "source": "hn", "sourceLabel": "Hacker News", "id": "1",
            "title": "A story", "url": "https://example.com", "discussionUrl": "https://example.com/d",
            "domain": "example.com", "publishedAt": "2026-10-26T08:00:00Z",
            "score": 10, "commentCount": 2, "heat": 1.5, "rank": 1, "read": false, "kept": false, "alsoOn": [],
        ]
        if let favourite { json["favourite"] = favourite }
        return try JSONDecoder().decode(NewsStory.self, from: JSONSerialization.data(withJSONObject: json))
    }

    /// The favourite action is a toggle: a saved story drawn unsaved on Top
    /// is one tap from being un-saved by somebody trying to save it.
    @MainActor func testASavedStoryShowsSavedOnEveryView() throws {
        let store = NewsStore()
        XCTAssertTrue(store.isSaved(try story(favourite: true)))
        XCTAssertFalse(store.isSaved(try story(favourite: false)))
        XCTAssertFalse(store.isSaved(try story(favourite: nil)), "an older site: Top says nothing about saved")
        store.view = .favourites
        XCTAssertTrue(store.isSaved(try story(favourite: nil)), "an older site's Saved view holds only saved stories")
    }
}
