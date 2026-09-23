import XCTest

/// Every tab, FULL — for reviewing the look, not for asserting behaviour.
///
/// The onboarding tests only ever see the app unpaired, so every screenshot they
/// attach is an empty state. These launch with `-SRDemo`, which (in a DEBUG
/// build only) pretends the phone is paired and answers every site request from
/// canned, synthetic fixtures (`Site/DemoFixtures.swift`).
///
/// The screenshots are the point. One method per screen, so a lookup that fails
/// on one screen never costs the others, and element lookups are SOFT: a missing
/// element is recorded and the shot is still taken of whatever is on screen.
final class ShowcaseTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    // MARK: - Today

    @MainActor func testShowcaseToday() {
        let app = launch()
        soft(app.tabBars.buttons["Today"].waitForExistence(timeout: 20), "no Today tab")
        settle(app, on: app.staticTexts["Primed"])
        attach(app, "Showcase — Today")

        app.swipeUp()
        settle(app)
        attach(app, "Showcase — Today, scrolled")
    }

    // MARK: - Chat

    @MainActor func testShowcaseChatList() {
        let app = launch()
        openTab(app, "Chat")
        settle(app, on: thread(app, "demo-thread-training"))
        attach(app, "Showcase — Chat threads")
    }

    @MainActor func testShowcaseChatThread() {
        let app = launch()
        openTab(app, "Chat")
        let first = thread(app, "demo-thread-training")
        if first.waitForExistence(timeout: 15) {
            first.tap()
        } else {
            // The redesign may rename the cell; fall back to the thread's title.
            let byTitle = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "week 6 review")
            ).firstMatch
            soft(byTitle.waitForExistence(timeout: 5), "no thread cell to open")
            if byTitle.exists { byTitle.tap() }
        }
        settle(app, on: app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "42.1 km")
        ).firstMatch)
        attach(app, "Showcase — Chat thread")

        app.swipeUp()
        settle(app)
        attach(app, "Showcase — Chat thread, scrolled")
    }

    // MARK: - News

    @MainActor func testShowcaseNewsList() {
        let app = launch()
        openTab(app, "News")
        settle(app, on: newsRow(app, "hn:41200001"))
        attach(app, "Showcase — News")
    }

    @MainActor func testShowcaseNewsStory() {
        let app = launch()
        openTab(app, "News")
        let row = newsRow(app, "hn:41200001")
        if row.waitForExistence(timeout: 15) {
            row.tap()
        } else {
            let byTitle = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "SQLite extension")
            ).firstMatch
            soft(byTitle.waitForExistence(timeout: 5), "no story row to open")
            if byTitle.exists { byTitle.tap() }
        }
        settle(app, on: app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "demonstration text")
        ).firstMatch)
        attach(app, "Showcase — News story")
    }

    // MARK: - Health

    @MainActor func testShowcaseHealth() {
        let app = launch()
        openTab(app, "Health")
        settle(app, on: app.staticTexts["Primed"])
        attach(app, "Showcase — Health")

        app.swipeUp()
        settle(app)
        attach(app, "Showcase — Health, scrolled")

        app.swipeUp()
        settle(app)
        attach(app, "Showcase — Health, scrolled further")
    }

    @MainActor func testShowcaseActivityDetail() {
        let app = launch()
        openTab(app, "Health")

        let all = app.buttons["health-all-activities"]
        if scroll(app, to: all) {
            all.tap()
            settle(app)
            attach(app, "Showcase — All activities")
        } else {
            soft(false, "no route to the activities list; trying a recent row")
        }

        let run = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Morning park loop")
        ).firstMatch
        let runText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Morning park loop")
        ).firstMatch
        if run.waitForExistence(timeout: 10) {
            run.tap()
        } else if runText.waitForExistence(timeout: 5) {
            runText.tap()
        } else {
            soft(false, "no activity row to open")
        }
        // A map takes a moment to draw its tiles.
        settle(app, seconds: 4)
        attach(app, "Showcase — Activity detail")

        app.swipeUp()
        settle(app)
        attach(app, "Showcase — Activity detail, scrolled")

        app.swipeUp()
        settle(app)
        attach(app, "Showcase — Activity detail, scrolled further")
    }

    /// An outing the SR app caught by itself: the origin note under the hero is
    /// the thing to look at.
    @MainActor func testShowcaseCapturedWalk() {
        let app = launch()
        openTab(app, "Health")

        let all = app.buttons["health-all-activities"]
        if scroll(app, to: all) {
            all.tap()
            settle(app)
        } else {
            soft(false, "no route to the activities list; trying a recent row")
        }

        let walk = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Captured walk")
        ).firstMatch
        let walkText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Captured walk")
        ).firstMatch
        if walk.waitForExistence(timeout: 10) {
            walk.tap()
        } else if walkText.waitForExistence(timeout: 5) {
            walkText.tap()
        } else {
            soft(false, "no captured walk to open")
        }
        settle(app, seconds: 4)
        attach(app, "Showcase — Captured walk")
    }

    @MainActor func testShowcaseSegments() {
        let app = launch()
        openTab(app, "Health")
        let segments = app.buttons["health-segments"]
        guard scroll(app, to: segments) else {
            soft(false, "no route to the segments list")
            attach(app, "Showcase — Segments (not reached)")
            return
        }
        segments.tap()
        settle(app)
        attach(app, "Showcase — Segments")
    }

    // MARK: - Settings

    @MainActor func testShowcaseSettings() {
        let app = launch()
        soft(app.tabBars.buttons["Today"].waitForExistence(timeout: 20), "no Today tab")
        let cog = app.buttons["open-settings"]
        if cog.waitForExistence(timeout: 10) {
            cog.tap()
        } else {
            soft(false, "no settings cog on Today")
        }
        settle(app)
        attach(app, "Showcase — Settings")

        let notifications = app.buttons["settings-notifications"]
        if notifications.waitForExistence(timeout: 5) {
            notifications.tap()
            settle(app)
            attach(app, "Showcase — Settings, where alerts go")
        }
    }

    // MARK: - Helpers

    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-SRDemo"]
        app.launch()
        return app
    }

    @MainActor private func openTab(_ app: XCUIApplication, _ name: String) {
        let tab = app.tabBars.buttons[name]
        if tab.waitForExistence(timeout: 20) {
            tab.tap()
        } else {
            soft(false, "no \(name) tab")
        }
    }

    @MainActor private func thread(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)["thread-\(id)"].firstMatch
    }

    @MainActor private func newsRow(_ app: XCUIApplication, _ key: String) -> XCUIElement {
        app.descendants(matching: .any)["news-row-\(key)"].firstMatch
    }

    /// Wait for a landmark if there is one, then a beat for animations and
    /// fonts. Never fails the test — the shot is taken regardless.
    @MainActor private func settle(_ app: XCUIApplication, on landmark: XCUIElement? = nil, seconds: TimeInterval = 1.5) {
        if let landmark {
            soft(landmark.waitForExistence(timeout: 15), "a landmark did not appear")
        }
        let pause = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { pause.fulfill() }
        wait(for: [pause], timeout: seconds + 5)
    }

    /// Record a miss without stopping the method.
    private func soft(_ condition: Bool, _ note: String) {
        guard !condition else { return }
        XCTContext.runActivity(named: "Soft miss: \(note)") { _ in }
    }

    @MainActor private func scroll(_ app: XCUIApplication, to element: XCUIElement, swipes: Int = 8) -> Bool {
        if element.waitForExistence(timeout: 10), element.isHittable { return true }
        for _ in 0..<swipes {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
