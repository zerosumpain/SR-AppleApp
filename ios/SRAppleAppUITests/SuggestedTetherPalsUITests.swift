import XCTest

/// Tether Pals, opened from its tile on the Games tab in the demo, started,
/// and photographed: the start card, the pals under way (the demo's
/// autopilot plays level 2, "Up on my head"), and the result card when
/// everyone reaches the flag (or the pause card, if the result is slow).
final class SuggestedTetherPalsUITests: XCTestCase {
    private let gameId = "tether-pals"
    private let title = "Tether Pals"

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    @MainActor func testSuggestedTetherPals() {
        let app = XCUIApplication()
        app.launchArguments = ["-SRDemo"]
        app.launch()

        XCTAssertTrue(app.openTab("Games"), "no Games tab")
        XCTAssertTrue(byId(app, "games-screen").waitForExistence(timeout: 20), "the Games page did not open")

        // "On this phone": the page jumps to the games, phone-played ones only.
        // The phone chip starts off the right edge: scroll the strip first.
        let phone = byId(app, "games-strip-phone")
        XCTAssertTrue(phone.waitForExistence(timeout: 10), "no On this phone chip")
        revealChip(app, phone)
        phone.tap()
        beat(1.5)
        let card = byId(app, "games-new-\(gameId)")
        XCTAssertTrue(scroll(app, to: card), "no \(title) tile (games-new-\(gameId))")
        card.tap()

        XCTAssertTrue(byId(app, "\(gameId)-screen").waitForExistence(timeout: 15), "the game did not open")
        beat(1.5)
        attach(app, "Suggested — \(title) — start")

        // Play sits at the foot of the start card, over the pad strips; the
        // pad leaves the tree under a card, so Play is the element there.
        let start = byId(app, "\(gameId)-start")
        soft(start.waitForExistence(timeout: 10), "no \(gameId)-start")
        soft(waitHittable(start, timeout: 5), "\(gameId)-start not hittable")
        if start.exists { start.tap() }

        // The card slides away and the demo plays itself (SRDemo.isOn).
        let board = byId(app, "\(gameId)-board")
        let pause = byId(app, "\(gameId)-pause")
        soft(byId(app, "\(gameId)-intro").waitForNonExistence(timeout: 5), "the start card did not go")
        soft(waitHittable(board, timeout: 10), "no \(gameId)-board")
        soft(waitHittable(pause, timeout: 10), "no \(gameId)-pause while playing")
        beat(2.5)
        attach(app, "Suggested — \(title) — playing")

        // The autopilot clears the level in about ten seconds; the card follows.
        let over = byId(app, "\(gameId)-over")
        if over.waitForExistence(timeout: 40) {
            beat(1)
        } else {
            soft(false, "no \(gameId)-over")
            if pause.exists, pause.isHittable {
                pause.tap()
                soft(byId(app, "\(gameId)-paused").waitForExistence(timeout: 5), "no pause card")
            }
            beat(1)
        }
        attach(app, "Suggested — \(title) — result")
    }

    // MARK: - Helpers

    @MainActor private func byId(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// Swipe the chip strip left by whichever of its chips is on screen until
    /// `chip` is: the off-screen chip itself cannot be swiped or tapped.
    @MainActor private func revealChip(_ app: XCUIApplication, _ chip: XCUIElement) {
        let ids = ["games-strip-all", "games-strip-rooms", "games-strip-invites", "games-strip-family"]
        for _ in 0..<5 where !chip.isHittable {
            guard let handle = ids.map({ byId(app, $0) }).first(where: { $0.exists && $0.isHittable }) else { break }
            handle.swipeLeft(velocity: .slow)
            beat(0.5)
        }
        XCTAssertTrue(chip.isHittable, "\(chip.identifier) not reachable on the chip strip")
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

    /// Polls until the element exists and can be tapped, or time runs out.
    @MainActor private func waitHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.isHittable { return true }
            beat(0.25)
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
