import XCTest

/// The Health tab's deeper read, asserted — against `-SRDemo`, whose digest is
/// SR-Health's real output over /health's mock series.
final class HealthHubTests: XCTestCase {

    @MainActor private func openHealth() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-SRDemo"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Health"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Health"].tap()
        // The demo has a lapsed Gmail, so the connections banner sits at the
        // top of the tab. In full it takes ~270pt of the viewport, and a whole
        // swipe can then carry a row from below the fold to UNDER the banner
        // (not hittable) in one step. These tests are about the Health tab:
        // dismiss the banner first.
        let dismiss = app.descendants(matching: .any)["connections-banner-dismiss"].firstMatch
        if dismiss.waitForExistence(timeout: 5) { dismiss.tap() }
        return app
    }

    @MainActor private func shoot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Scroll until the element is on screen, or give up after a few swipes.
    @MainActor private func reveal(_ app: XCUIApplication, _ element: XCUIElement, swipes: Int = 10) -> Bool {
        for _ in 0..<swipes {
            if element.waitForExistence(timeout: 1.5) && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    @MainActor func testTheReadAndTheHeartRateDraw() {
        let app = openHealth()
        // A List builds rows as they scroll in, so nothing below the hero
        // EXISTS until it is on screen: scroll first, then assert.
        let lede = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Today: recovery at")).firstMatch
        XCTAssertTrue(reveal(app, lede), "the one-line read did not draw")
        shoot(app, "Health — the read")

        let chart = app.descendants(matching: .any)["Heart rate over the last 24 hours"].firstMatch
        XCTAssertTrue(reveal(app, chart), "the heart-rate chart did not draw")
        shoot(app, "Health — heart rate")

        let tripped = app.staticTexts["TRIPPED"].firstMatch
        XCTAssertTrue(reveal(app, tripped), "a live tripwire should be on the tab")
        shoot(app, "Health — tripwires and moves")
    }

    @MainActor func testTheFullPicturePushes() {
        let app = openHealth()
        let instruments = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Instruments")).firstMatch
        XCTAssertTrue(reveal(app, instruments, swipes: 14), "the full picture did not draw")
        shoot(app, "Health — the full picture")

        instruments.tap()
        XCTAssertTrue(app.staticTexts["ACWR · EWMA"].waitForExistence(timeout: 10))
        shoot(app, "Health — instruments")
        app.navigationBars.buttons.firstMatch.tap()

        let forecast = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Forecast")).firstMatch
        XCTAssertTrue(reveal(app, forecast), "no Forecast row")
        forecast.tap()
        XCTAssertTrue(app.staticTexts["Rising at +0.03 a month."].firstMatch.waitForExistence(timeout: 10))
        shoot(app, "Health — forecast")
        app.navigationBars.buttons.firstMatch.tap()

        let verdict = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "The verdict")).firstMatch
        XCTAssertTrue(reveal(app, verdict), "no verdict row")
        verdict.tap()
        XCTAssertTrue(app.staticTexts["CAPABLE."].waitForExistence(timeout: 10))
        shoot(app, "Health — the verdict")
    }
}
