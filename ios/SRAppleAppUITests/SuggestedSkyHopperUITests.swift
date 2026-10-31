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
        // the shelves are pages down. The pinned "On this phone" chip holds
        // the page to the phone-played games and scrolls them up under the
        // strip (`choose` scrolls to `games-play`). Query the chip itself,
        // never the strip container: CI found the chips but not the strip,
        // and a guard on the strip skipped both chips. No search field: in
        // CI it took the tap but not the typing. "Invites 2" and "Your games
        // 41" come first, so the chip starts past the right edge: swipe a
        // chip that is on screen left until it can be tapped (never the
        // off-screen chip itself: CI fails that action outright).
        let card = byId(app, "games-new-\(gameId)")
        let phone = byId(app, "games-strip-phone")
        let physics = byId(app, "games-strip-physics")
        if pick(app, phone) || pick(app, physics) {
            beat(1.5)
        } else {
            soft(false, "no shelf chip on screen")
        }
        // Held drags, not flicks: a flick's momentum carried the page past a
        // 164-pt tile between looks, and eight of them did not always get
        // down past the demo's forty-odd rooms when the chip's jump fell short.
        XCTAssertTrue(hunt(app, to: card, steps: 24), "no \(title) tile (games-new-\(gameId))")

        // "Hittable" holds for a tile half under the pinned chip strip or the
        // tray, and a tap there lands on a chip ("Invites" jumps the page back
        // to the top) or on nothing. Bring the tile to the middle of the window
        // and let it settle first; if the tap still went astray, find it and
        // tap once more.
        let screen = byId(app, "\(gameId)-screen")
        centre(app, card)
        card.waitUntilStill()
        card.tap()
        if !screen.waitForExistence(timeout: 8), hunt(app, to: card, steps: 24) {
            centre(app, card)
            card.waitUntilStill()
            card.tap()
        }
        XCTAssertTrue(screen.waitForExistence(timeout: 15), "the game did not open")
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
        soft(over.waitForExistence(timeout: 30), "no results card")
        beat(1.5)
        attach(app, "Suggested — \(title) — result")
        soft(byId(app, "\(gameId)-again").exists, "no \(gameId)-again")
    }

    // MARK: - Helpers

    /// Bring a shelf chip on screen and tap it once, so the shelf is held.
    /// The chip starts past the right edge (CI: "On this phone" at x=404 in a
    /// 402-pt window), and swiping or tapping an off-screen chip fails the
    /// test ("visible frame is empty"), so the strip is moved by swiping
    /// whichever chip IS hittable. A second tap on a lit chip lets the shelf
    /// go again, so it is tapped only while unlit.
    @MainActor private func pick(_ app: XCUIApplication, _ chip: XCUIElement) -> Bool {
        guard chip.waitForExistence(timeout: 10) else { return false }
        if chip.isSelected { return true }
        for _ in 0..<8 where !chip.isHittable {
            guard let handle = visibleChip(app, except: chip) else { break }
            handle.swipeLeft(velocity: .slow)
            beat(0.5)
        }
        guard chip.isHittable else { return false }
        _ = chip.waitUntilStill(timeout: 2)
        chip.tap()
        return true
    }

    /// A chip of the Games strip that is on screen now (never the strip
    /// container, which CI does not find), other than `chip`.
    @MainActor private func visibleChip(_ app: XCUIApplication, except chip: XCUIElement) -> XCUIElement? {
        let ids = ["all", "rooms", "invites", "top", "phone", "family", "leaderboard", "ideas"]
            .map { "games-strip-\($0)" }
            .filter { $0 != chip.identifier }
        return ids.map { byId(app, $0) }.first { $0.exists && $0.isHittable }
    }

    @MainActor private func byId(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// Down the page, then back up it, a held drag at a time (no momentum, so
    /// each step moves well under a window and nothing slips past between
    /// looks), until the element can be tapped.
    @MainActor private func hunt(_ app: XCUIApplication, to element: XCUIElement, steps: Int) -> Bool {
        if element.waitForExistence(timeout: 5), element.isHittable { return true }
        for _ in 0..<steps {
            drag(app, by: 0.4)
            if element.exists && element.isHittable { return true }
        }
        for _ in 0..<steps {
            drag(app, by: -0.4)
            if element.exists && element.isHittable { return true }
        }
        return element.exists && element.isHittable
    }

    /// Move the page so the element sits in the middle band of the window,
    /// clear of the pinned strip at the top and the tray at the foot.
    @MainActor private func centre(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<4 {
            let window = app.frame
            guard element.exists, window.height > 0 else { return }
            let mid = element.frame.midY
            let low = window.minY + window.height * 0.3
            let high = window.minY + window.height * 0.7
            if mid >= low && mid <= high { return }
            // Below the middle: drag the page up by the gap, and the other way.
            drag(app, by: (mid - window.midY) / window.height)
        }
    }

    /// One held vertical drag through the middle of the window: `fraction` of
    /// its height (at most 0.45), positive to move the page up (further down
    /// the content), negative to move it back. The hold at the end stops the
    /// page dead.
    @MainActor private func drag(_ app: XCUIApplication, by fraction: CGFloat) {
        let step = max(-0.45, min(0.45, fraction))
        guard abs(step) >= 0.05 else { return }
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5 + step / 2))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5 - step / 2))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2)
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
