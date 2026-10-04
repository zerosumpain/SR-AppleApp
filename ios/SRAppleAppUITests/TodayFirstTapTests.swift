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

    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        // `@AppStorage` reads launch arguments: the steps card on, as a person
        // who switched it on in Settings has it.
        app.launchArguments = ["-SRDemo", "-today-card-steps", "YES"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 20))
        return app
    }

    @MainActor func testTheStepBoardOpensOnTheFirstTap() {
        // Three cold launches: the miss was intermittent, so one pass proves little.
        for attempt in 1...3 {
            let app = launch()
            let card = app.descendants(matching: .any)["today-steps"].firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 15), "no steps card on Today (launch \(attempt))")
            for _ in 0..<4 where !card.isHittable { app.swipeUp() }
            card.tap()
            XCTAssertTrue(
                app.descendants(matching: .any)["steps-hero"].firstMatch.waitForExistence(timeout: 10),
                "one tap on the steps card did not open the board (launch \(attempt))"
            )
            app.terminate()
        }
    }

    /// The family card: a title, and only where everyone is.
    @MainActor func testTheFamilyCardSaysOnlyWhere() {
        let app = launch()
        let card = app.descendants(matching: .any)["today-family"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "no family card on Today")
        XCTAssertTrue(app.staticTexts["FAMILY TRACKING"].exists, "the family card has no title")
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "km/h")).firstMatch.exists,
                       "the family card still says how fast")
        XCTAssertFalse(app.descendants(matching: .any)["today-overnight"].firstMatch.exists, "the Overnight tile is back")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Today — family tracking"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
