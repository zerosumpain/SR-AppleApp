import XCTest

/// Today's cards answer the FIRST tap.
///
/// The step board took two or three taps to open from Today (reported
/// 2026-10-05). The family card above it was re-read every fifteen seconds and
/// its rows changed height as place names resolved, so the cards beneath moved
/// under the thumb and a tap that began on the steps card ended off it. These
/// tap as early as the card is there — the moment that used to miss — and
/// allow exactly one tap.
final class TodayFirstTapTests: XCTestCase {

    @MainActor private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        // `@AppStorage` reads launch arguments: the steps card on, as a person
        // who switched it on in Settings has it.
        app.launchArguments = ["-SRDemo", "-today-card-steps", "YES"] + extra
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 20))
        return app
    }

    @MainActor func testTheStepBoardOpensOnTheFirstTap() {
        // Three cold launches: the miss was intermittent, so one pass proves little.
        for attempt in 1...3 {
            let app = launch()
            let card = app.descendants(matching: .any)["today-steps"].firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 15), "no steps card on Today (launch \(attempt))")
            // No swiping to "find" it: `tap()` scrolls a card into view itself,
            // and only when it must. The card is the second row of Home, just
            // under the pinned banners (connections, an urgent alert); a blind
            // swipe up slid it beneath them, and the tap was aimed at the
            // banners' edge and went through to the tile behind — Family
            // opened instead (CI 2026-10-20, launch 2).
            card.tap()
            XCTAssertTrue(
                app.descendants(matching: .any)["steps-hero"].firstMatch.waitForExistence(timeout: 10),
                "one tap on the steps card did not open the board (launch \(attempt))"
            )
            app.terminate()
        }
    }

    /// Nothing under the sky moves once it is there: the sun comes up and
    /// the rings sweep in on the first Today of a launch, and the cards
    /// under the hero must not shift while they do (a fixed-height hero is
    /// the whole point). Read once Today's own loads have landed, then again
    /// well after the sunrise.
    ///
    /// What is measured is the hero's part and nothing else. `-SRStoreShots`
    /// drops the demo's urgent alert, whose banner is pinned over the page
    /// whenever the alert inbox lands; the steps card is read only after its
    /// "Reading the board…" line has become the board; and the steps card is
    /// placed against the family card only once the trip card between them
    /// is there. Positions are taken against the hero, so a page that moves
    /// as a whole for some other reason is not blamed on the sky.
    @MainActor func testTodayDoesNotMoveUnderTheThumb() {
        let app = launch(["-SRStoreShots"])
        let any = app.descendants(matching: .any)
        let hero = any["today-hero"].firstMatch
        let family = any["today-family"].firstMatch
        let steps = any["today-steps"].firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 15), "no hero on Today")
        XCTAssertTrue(family.waitForExistence(timeout: 15), "no family card on Today")
        XCTAssertTrue(steps.waitForExistence(timeout: 15), "no steps card on Today")
        let loaded = expectation(
            for: NSPredicate(format: "NOT (label CONTAINS %@)", "Reading the board"), evaluatedWith: steps
        )
        wait(for: [loaded], timeout: 15)
        // Whichever trip card the demo's trips give, once it is drawn.
        let trip = any.matching(NSPredicate(format: "identifier IN %@", ["today-trip", "today-trips", "today-plan-trip"])).firstMatch
        _ = trip.waitForExistence(timeout: 10)

        func read() -> (hero: CGFloat, family: CGRect, steps: CGRect) {
            let top = hero.frame.maxY
            return (hero.frame.height,
                    family.frame.offsetBy(dx: 0, dy: -top),
                    steps.frame.offsetBy(dx: 0, dy: -family.frame.maxY))
        }
        let before = read()
        let pause = expectation(description: "past the sunrise")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { pause.fulfill() }
        wait(for: [pause], timeout: 10)
        let after = read()
        XCTAssertEqual(after.hero, before.hero, "the hero changed height during the sunrise")
        Self.assertSame(after.family, before.family, "the family card moved under the hero after it appeared")
        Self.assertSame(after.steps, before.steps, "the steps card moved after it appeared")
    }

    /// Within a point: a card the scroll transition is easing at the screen's
    /// edge (Home's tiles scale a little as they leave) can settle by a third
    /// of a point, which is not a card moving under a thumb — a sunrise that
    /// pushes the page is tens of points.
    private static func assertSame(_ a: CGRect, _ b: CGRect, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        for (x, y) in [(a.minX, b.minX), (a.minY, b.minY), (a.width, b.width), (a.height, b.height)] {
            XCTAssertEqual(x, y, accuracy: 1, "\(message): \(a) vs \(b)", file: file, line: line)
        }
    }

    /// A member's sun is their Move ring: nothing of the owner's readiness.
    @MainActor func testMemberSunIsMoveOnly() {
        let app = launch(["-SRDemoMember"])
        let sun = app.descendants(matching: .any)["today-health"].firstMatch
        XCTAssertTrue(sun.waitForExistence(timeout: 15), "no sun on a member's Today")
        XCTAssertTrue(sun.label.contains("Move"), "the member's sun does not say Move: \(sun.label)")
        XCTAssertFalse(sun.label.contains("Readiness"), "the member's sun reads the owner's readiness: \(sun.label)")
    }

    /// The family tile: the Orbit, and only where everyone is.
    @MainActor func testTheFamilyCardSaysOnlyWhere() {
        let app = launch()
        let card = app.descendants(matching: .any)["today-family"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "no family tile on Home")
        XCTAssertTrue(app.descendants(matching: .any)["family-orbit"].firstMatch.waitForExistence(timeout: 10),
                      "the family tile has no Orbit")
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "km/h")).firstMatch.exists,
                       "the family card still says how fast")
        XCTAssertFalse(app.descendants(matching: .any)["today-overnight"].firstMatch.exists, "the Overnight tile is back")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Home — family Orbit"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
