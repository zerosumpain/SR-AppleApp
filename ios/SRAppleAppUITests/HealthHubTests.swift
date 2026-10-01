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

    @MainActor private func openInsights() -> XCUIApplication {
        let app = openHealth()
        let insights = app.buttons["health-insights"]
        XCTAssertTrue(reveal(app, insights), "no Insights tile on the tab")
        insights.tap()
        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: 10))
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

    /// The tab itself: the hero, the four areas two by two, and this iPhone's
    /// heart rate under them.
    @MainActor func testTheAreasAndTheHeartRateDraw() {
        let app = openHealth()
        for id in ["health-all-activities", "health-segments", "health-routes", "health-insights"] {
            let tile = app.buttons[id]
            XCTAssertTrue(reveal(app, tile), "no \(id) tile on the tab")
        }
        shoot(app, "Health — the four areas")

        let chart = app.descendants(matching: .any)["Heart rate over the last 24 hours"].firstMatch
        XCTAssertTrue(reveal(app, chart), "the heart-rate chart did not draw")
        shoot(app, "Health — heart rate")
    }

    /// The compact hero opens Readiness: the verdict, its parts, today's
    /// rings and the fortnight — and a figure there opens its own page.
    @MainActor func testTheHeroOpensReadiness() {
        let app = openHealth()
        let hero = app.descendants(matching: .any)["health-readiness"].firstMatch
        XCTAssertTrue(reveal(app, hero), "no readiness card on the tab")
        XCTAssertTrue(hero.label.localizedCaseInsensitiveContains("Primed"), "the card does not say the verdict")
        hero.tap()
        XCTAssertTrue(app.navigationBars["Readiness"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["WHAT READINESS IS MADE OF"].waitForExistence(timeout: 10))
        shoot(app, "Health — readiness")

        let hrv = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "HRV")).firstMatch
        XCTAssertTrue(reveal(app, hrv), "no HRV tile on Readiness")
        hrv.tap()
        XCTAssertTrue(app.navigationBars["HRV"].waitForExistence(timeout: 10), "the HRV tile did not open its page")
    }

    /// Insights: the read and the live tripwires, one push off the tab.
    @MainActor func testTheReadDrawsInInsights() {
        let app = openInsights()
        // A List builds rows as they scroll in, so nothing below the top
        // EXISTS until it is on screen: scroll first, then assert.
        let lede = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Today: recovery at")).firstMatch
        XCTAssertTrue(reveal(app, lede), "the one-line read did not draw")
        shoot(app, "Health — the read")

        let tripped = app.staticTexts["TRIPPED"].firstMatch
        XCTAssertTrue(reveal(app, tripped), "a live tripwire should be in Insights")
        shoot(app, "Health — tripwires and moves")
    }

    @MainActor func testTheFullPicturePushes() {
        let app = openInsights()
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
