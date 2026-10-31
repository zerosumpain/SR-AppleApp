import XCTest

/// Sky Hopper, opened from its tile on the Games tab in the demo, started,
/// and photographed: the start card, a run under way (the demo's autopilot
/// steers), and the results card when the demo lets Hop fall.
final class SuggestedSkyHopperUITests: XCTestCase {
    private let gameId = "sky-hopper"
    private let title = "Sky Hopper"

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    @MainActor func testSuggestedSkyHopper() {
        let app = XCUIApplication()
        app.launchArguments = ["-SRDemo"]
        app.launch()

        XCTAssertTrue(app.openTab("Games"), "no Games tab")
        XCTAssertTrue(byId(app, "games-screen").waitForExistence(timeout: 20), "the Games page did not open")

        // The demo's Games page opens on its invites and forty-odd rooms, so
        // the search field is pages down: the pinned "All games" chip jumps
        // the page to Play (`choose` scrolls to `games-play`) first.
        let all = byId(app, "games-strip-all")
        if all.waitForExistence(timeout: 10), all.isHittable {
            all.tap()
            beat(1)
        }

        // Search by name: one result, right under the field, whatever the shelf order.
        // The return key puts the keyboard away so it cannot cover the tile.
        let card = byId(app, "games-new-\(gameId)")
        let search = app.textFields["games-search"]
        if scroll(app, to: search) {
            search.tap()
            search.typeText(title + "\n")
        }
        XCTAssertTrue(scroll(app, to: card), "no \(title) tile (games-new-\(gameId))")
        card.tap()

        XCTAssertTrue(byId(app, "\(gameId)-screen").waitForExistence(timeout: 15), "the game did not open")
        soft(byId(app, "\(gameId)-intro").waitForExistence(timeout: 10), "no start card")
        beat(1.5)
        attach(app, "Suggested — \(title) — start")

        let start = byId(app, "\(gameId)-start")
        soft(start.waitForExistence(timeout: 10), "no \(gameId)-start")
        if start.exists && start.isHittable { start.tap() }
        beat(4)                                   // the demo plays itself (SRDemo.isOn)
        attach(app, "Suggested — \(title) — playing")

        let pause = byId(app, "\(gameId)-pause")
        if pause.waitForExistence(timeout: 5), pause.isHittable {
            pause.tap()
            let paused = byId(app, "\(gameId)-paused")
            soft(paused.waitForExistence(timeout: 5), "no pause card")
            beat(1)
            attach(app, "Suggested — \(title) — paused")
            let resume = byId(app, "\(gameId)-resume")
            if resume.waitForExistence(timeout: 5), resume.isHittable { resume.tap() }
        } else {
            soft(false, "no \(gameId)-pause")
        }

        // The demo climbs for about twenty seconds of play, then lets Hop fall.
        let over = byId(app, "\(gameId)-over")
        soft(over.waitForExistence(timeout: 45), "no results card")
        beat(1.5)
        attach(app, "Suggested — \(title) — result")
        soft(byId(app, "\(gameId)-again").exists, "no \(gameId)-again")
    }

    // MARK: - Helpers

    @MainActor private func byId(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// Down the page, then back up it, until the element can be tapped.
    @MainActor private func scroll(_ app: XCUIApplication, to element: XCUIElement, swipes: Int = 8) -> Bool {
        if element.waitForExistence(timeout: 10), element.isHittable { return true }
        for _ in 0..<swipes {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        for _ in 0..<swipes {
            if element.exists && element.isHittable { return true }
            app.swipeDown()
        }
        return element.exists && element.isHittable
    }

    /// A pause for animations, without failing the test.
    @MainActor private func beat(_ seconds: TimeInterval) {
        let done = expectation(description: "beat")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 5)
    }

    /// Record a miss without stopping the method.
    private func soft(_ condition: Bool, _ note: String) {
        guard !condition else { return }
        XCTContext.runActivity(named: "Soft miss: \(note)") { _ in }
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
