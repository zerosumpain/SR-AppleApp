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
        // the shelves are pages down. A pinned shelf chip holds the page to
        // its games and scrolls them up under the strip (`choose` scrolls to
        // `games-play`): no keyboard to cover the tile. In CI the search field
        // took the tap but not the typing, and the keyboard sat over an
        // unfiltered page. The strip scrolls sideways, and in the demo
        // "Invites 2" and "Your games 41" come first, so "On this phone" and
        // Physics start past the right edge: swipe the strip until one shows.
        let card = byId(app, "games-new-\(gameId)")
        let strip = byId(app, "games-strip")
        let physics = byId(app, "games-strip-physics")
        let phone = byId(app, "games-strip-phone")
        _ = physics.waitForExistence(timeout: 10)
        if reveal(app, physics, in: strip) {
            physics.tap()
            beat(1.5)
        } else if reveal(app, phone, in: strip) {
            phone.tap()
            beat(1.5)
        } else {
            soft(false, "no shelf chip on screen")
        }
        if !scroll(app, to: card, swipes: 4) {
            findBySearch(app)
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

    /// The way round if the Physics chip did not bring the tile up: every
    /// game again ("All games" also jumps to Play), then search by name, typing
    /// only once the keyboard is up, and put the keyboard away after.
    @MainActor private func findBySearch(_ app: XCUIApplication) {
        let all = byId(app, "games-strip-all")
        if all.waitForExistence(timeout: 5), all.isHittable {
            all.tap()
            beat(1.5)
        }
        let search = app.textFields["games-search"]
        guard scroll(app, to: search) else {
            soft(false, "no games-search")
            return
        }
        search.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 5) {
            search.tap()
        }
        guard app.keyboards.firstMatch.waitForExistence(timeout: 5) else {
            soft(false, "no keyboard for games-search")
            return
        }
        // Into whatever holds the focus: the field's own `typeText` found no
        // focus in CI though the keyboard was up for it.
        app.typeText(title)
        beat(0.5)
        let go = app.keyboards.buttons["search"]
        if go.exists && go.isHittable { go.tap() } else { app.typeText("\n") }
        beat(1)
    }

    /// Slow swipes along the chip strip, left then back right, until `chip`
    /// is on screen and can be tapped.
    @MainActor private func reveal(_ app: XCUIApplication, _ chip: XCUIElement, in strip: XCUIElement,
                                   swipes: Int = 6) -> Bool {
        guard chip.exists, strip.exists else { return false }
        if chip.isHittable { return true }
        for _ in 0..<swipes {
            strip.swipeLeft(velocity: .slow)
            if chip.isHittable { return true }
        }
        for _ in 0..<(swipes * 2) {
            strip.swipeRight(velocity: .slow)
            if chip.isHittable { return true }
        }
        return chip.isHittable
    }

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
