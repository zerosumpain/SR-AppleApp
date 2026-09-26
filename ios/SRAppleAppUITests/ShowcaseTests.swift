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

    /// The daydream loop's Noticed card, under the health slab.
    @MainActor func testShowcaseTodayNoticed() {
        let app = launch()
        soft(app.tabBars.buttons["Today"].waitForExistence(timeout: 20), "no Today tab")
        settle(app, on: app.staticTexts["Primed"])
        // The SECOND note's actions: scrolled to those, the whole card is up,
        // not just the first row's.
        let last = app.buttons.matching(identifier: "noticed-useful").element(boundBy: 1)
        soft(scroll(app, to: last), "no Noticed card on Today")
        settle(app)
        attach(app, "Showcase — Today, noticed")
    }

    // MARK: - Family

    /// The mini-map on Today, then the tab it opens: pins, today's lines, and
    /// the cards — a low battery in red, a day that is not yours left off.
    @MainActor func testShowcaseFamily() {
        let app = launch()
        soft(app.tabBars.buttons["Today"].waitForExistence(timeout: 20), "no Today tab")
        let mini = byId(app, "today-family")
        soft(mini.waitForExistence(timeout: 15), "no family map on Today")
        settle(app, seconds: 3)
        attach(app, "Showcase — Today, family map")

        if mini.exists && mini.isHittable {
            mini.tap()
        } else {
            openTab(app, "Family")
        }
        settle(app, on: byId(app, "family-person-sam"), seconds: 3)
        attach(app, "Showcase — Family")

        let sam = byId(app, "family-person-sam")
        if sam.exists && sam.isHittable { sam.tap() }
        settle(app, seconds: 3)
        attach(app, "Showcase — Family, one person")

        app.swipeUp()
        settle(app)
        attach(app, "Showcase — Family, scrolled")
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

    /// The health notes, under "The read".
    @MainActor func testShowcaseHealthNoticed() {
        let app = launch()
        openTab(app, "Health")
        settle(app, on: app.staticTexts["Primed"])
        let useful = app.buttons.matching(identifier: "noticed-useful").firstMatch
        soft(scroll(app, to: useful), "no Noticed section on Health")
        settle(app)
        attach(app, "Showcase — Health, noticed")
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

    // MARK: - Flows

    @MainActor func testShowcaseFlows() {
        let app = launch()
        openTab(app, "Flows")
        let brief = byId(app, "flow-row-morning-brief")
        settle(app, on: brief)
        attach(app, "Showcase — Flows")

        if brief.exists {
            brief.tap()
        } else {
            let byTitle = app.staticTexts["Morning brief"]
            soft(byTitle.waitForExistence(timeout: 5), "no workflow row to open")
            if byTitle.exists { byTitle.tap() }
        }
        settle(app, on: app.staticTexts["Anything before nine?"])
        attach(app, "Showcase — Flow detail")

        app.swipeUp()
        settle(app)
        attach(app, "Showcase — Flow detail, scrolled")

        let step = byId(app, "flow-step-brief")
        if scroll(app, to: step) {
            step.tap()
            settle(app, on: app.staticTexts["Instructions"])
            attach(app, "Showcase — Flow step editor")
        } else {
            soft(false, "no step row to open")
        }
    }

    @MainActor func testShowcaseFlowAttentionAndRun() {
        let app = launch()
        openTab(app, "Flows")
        let triage = byId(app, "flow-row-inbox-triage")
        if triage.waitForExistence(timeout: 15) {
            triage.tap()
        } else {
            soft(false, "no inbox-triage row")
        }
        settle(app, on: byId(app, "flow-fix-demo-fix-1"))
        attach(app, "Showcase — Flow needing attention")

        let run = byId(app, "flow-run-demo-run-inbox-1")
        if scroll(app, to: run) {
            run.tap()
            settle(app, on: byId(app, "flow-run-summary"))
            attach(app, "Showcase — Flow run")
        } else {
            soft(false, "no run row to open")
        }
    }

    /// A Describe-it build that stopped to ask. The row says so in the list;
    /// the detail leads with the question card.
    @MainActor func testShowcaseFlowQuestion() {
        let app = launch()
        openTab(app, "Flows")
        let row = byId(app, "flow-row-hourly-jokes")
        settle(app, on: row)
        attach(app, "Showcase — Flows with a question")
        if row.exists {
            row.tap()
        } else {
            soft(false, "no hourly-jokes row")
        }
        let card = byId(app, "flow-question")
        settle(app, on: card)
        soft(app.staticTexts["What time should the jokes stop?"].exists, "the question text did not draw")
        attach(app, "Showcase — Flow question")

        let field = byId(app, "flow-question-field")
        if field.waitForExistence(timeout: 5) {
            field.tap()
            field.typeText("At ten tonight, and not at all on Sundays")
            settle(app)
            soft(byId(app, "flow-question-send").isEnabled, "Send stayed disabled with an answer typed")
            attach(app, "Showcase — Flow question, answer typed")
        } else {
            soft(false, "no answer field")
        }
    }

    // MARK: - A connection needs you

    /// The demo has one lapsed Gmail, so the banner sits at the top of every
    /// tab. Today and Flows are photographed on purpose: one scrolls a page,
    /// the other a searchable list, and the inline title must still paint
    /// under the banner in both.
    @MainActor func testShowcaseConnectionsBanner() {
        let app = launch()
        soft(app.tabBars.buttons["Today"].waitForExistence(timeout: 20), "no Today tab")
        let banner = byId(app, "connections-banner")
        settle(app, on: banner)
        attach(app, "Showcase — Connection banner on Today")

        openTab(app, "Flows")
        settle(app, on: byId(app, "flow-row-morning-brief"))
        soft(banner.exists, "no banner on Flows")
        attach(app, "Showcase — Connection banner on Flows")

        let details = byId(app, "connections-banner-details")
        if details.waitForExistence(timeout: 5) {
            details.tap()
            settle(app, on: byId(app, "connection-gmail:2"))
            attach(app, "Showcase — Connections needing you")
            let done = byId(app, "connections-sheet-done")
            if done.waitForExistence(timeout: 5) { done.tap() }
            settle(app)
        } else {
            soft(false, "no banner details button")
        }

        let collapse = byId(app, "connections-banner-collapse")
        if collapse.waitForExistence(timeout: 5) {
            collapse.tap()
            settle(app, on: byId(app, "connections-banner-expand"))
            attach(app, "Showcase — Connection banner, made smaller")
        } else {
            soft(false, "no collapse button")
        }
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
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists { back.tap() }
            settle(app)
        }

        let connections = app.buttons["settings-connections"]
        if connections.waitForExistence(timeout: 5) {
            connections.tap()
            settle(app, on: byId(app, "connection-gmail:2"))
            attach(app, "Showcase — Settings, site connections that need you")
        } else {
            soft(false, "no Connections row in Settings")
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
        soft(app.openTab(name), "no \(name) tab")
    }

    @MainActor private func thread(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)["thread-\(id)"].firstMatch
    }

    @MainActor private func byId(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
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
