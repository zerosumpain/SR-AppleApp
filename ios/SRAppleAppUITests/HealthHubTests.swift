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

    /// The tab itself: the hero, the five areas, and this iPhone's heart rate
    /// under them.
    @MainActor func testTheAreasAndTheHeartRateDraw() {
        let app = openHealth()
        for id in ["health-all-activities", "health-segments", "health-routes", "health-insights", "health-sleep"] {
            let tile = app.buttons[id]
            XCTAssertTrue(reveal(app, tile), "no \(id) tile on the tab")
        }
        shoot(app, "Health — the four areas")

        let chart = app.descendants(matching: .any)["Heart rate over the last 24 hours"].firstMatch
        XCTAssertTrue(reveal(app, chart), "the heart-rate chart did not draw")
        shoot(app, "Health — heart rate")
    }

    /// Sleep analytics: last night, the week from both devices, the overnight
    /// vitals and /health's sleep reads, one push off the tab.
    @MainActor func testSleepAnalyticsOpensWithTheNight() {
        let app = openHealth()
        let tile = app.buttons["health-sleep"]
        XCTAssertTrue(reveal(app, tile), "no Sleep analytics tile on the tab")
        tile.tap()
        XCTAssertTrue(app.navigationBars["Sleep analytics"].waitForExistence(timeout: 10), "Sleep analytics did not open")
        XCTAssertTrue(app.descendants(matching: .any)["sleep-last-night"].firstMatch.waitForExistence(timeout: 10), "no last night")
        shoot(app, "Health — sleep analytics")
        XCTAssertTrue(reveal(app, app.descendants(matching: .any)["sleep-week"].firstMatch), "no week of nights")
        XCTAssertTrue(reveal(app, app.descendants(matching: .any)["health-vital-rhr"].firstMatch), "no overnight vitals")
        shoot(app, "Health — sleep analytics, vitals")
    }

    /// The compact hero is the readiness answer, not a door to a second
    /// Readiness screen: it says the verdict, and a figure line opens that
    /// figure's own page.
    @MainActor func testTheHeroSaysTheVerdictAndOpensAFigure() {
        let app = openHealth()
        let hero = app.descendants(matching: .any)["health-readiness"].firstMatch
        XCTAssertTrue(reveal(app, hero), "no readiness card on the tab")
        XCTAssertTrue(hero.label.localizedCaseInsensitiveContains("Primed"), "the card does not say the verdict")
        XCTAssertFalse(app.navigationBars["Readiness"].exists)
        shoot(app, "Health — readiness hero")

        let hrv = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "HRV")).firstMatch
        XCTAssertTrue(reveal(app, hrv), "no HRV line on the hero")
        hrv.tap()
        XCTAssertTrue(app.navigationBars["HRV"].waitForExistence(timeout: 10), "the HRV line did not open its page")
    }

    /// Insights: the read and the live tripwires, one push off the tab.
    @MainActor func testTheReadDrawsInInsights() {
        let app = openInsights()
        // A List builds rows as they scroll in, so nothing below the top
        // EXISTS until it is on screen: scroll first, then assert.
        let lede = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Today: recovery at")).firstMatch
        XCTAssertTrue(reveal(app, lede), "the one-line read did not draw")
        shoot(app, "Health — the read")

        let tripped = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "TRIPPED")).firstMatch
        XCTAssertTrue(reveal(app, tripped), "a live tripwire should be in Insights")
        XCTAssertFalse(app.staticTexts["THE PLANNER WOULD COMMISSION"].exists, "Today is gone from Insights")
        shoot(app, "Health — tripwires and moves")
    }

    /// The forecast is a two-by-two grid on the page: four tiles, each one
    /// element, each opening the charts.
    @MainActor func testTheForecastGridPushes() {
        let app = openInsights()
        let tiles = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "forecast:"))
        XCTAssertTrue(reveal(app, tiles.firstMatch), "no forecast tile")
        XCTAssertEqual(tiles.count, 4, "the demo's four forecasts should be four tiles")
        shoot(app, "Health — forecast grid")
        tiles.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Sleep"].waitForExistence(timeout: 10), "the Sleep tile should open Sleep's forecast")
        shoot(app, "Health — forecast")
        // ONE screen was pushed: a single Back is Insights again.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: 10), "one Back should return to Insights")
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

        let verdict = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "The verdict")).firstMatch
        XCTAssertTrue(reveal(app, verdict), "no verdict row")
        verdict.tap()
        XCTAssertTrue(app.staticTexts["CAPABLE."].waitForExistence(timeout: 10))
        shoot(app, "Health — the verdict")
    }
}
