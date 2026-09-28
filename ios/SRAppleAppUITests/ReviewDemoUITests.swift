import XCTest

/// The App Review demo, the way a reviewer reaches it: Welcome → "I have a
/// pairing code" → the review code → the whole app on made-up data, with the
/// Demo strip on every screen → Settings → Leave demo → Welcome.
///
/// `-SRStubNetwork` stands in for the site (DEBUG only): it says `{demo: true}`
/// to `UITEST-REVIEW-CODE` and 401s anything else, exactly as
/// `POST /api/native/review-demo` does for the real code, which is held on the
/// server and never in the app.
final class ReviewDemoUITests: XCTestCase {

    private let reviewCode = "UITEST-REVIEW-CODE"

    @MainActor func testAReviewerEntersTheDemoWithTheCodeAndLeavesFromSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["-SRFreshInstall", "-SRStubNetwork"]
        app.launch()

        // Welcome, then the code box.
        let haveCode = app.buttons["welcome-have-code"]
        XCTAssertTrue(haveCode.waitForExistence(timeout: 20), "no way to type a code on Welcome")
        haveCode.tap()
        let field = app.textFields["code-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no code field")
        attach(app, "Review demo — the code box")

        // A wrong code is refused, and the phone stays on Welcome.
        field.tap()
        field.typeText("NOT-THE-CODE")
        XCTAssertTrue(app.buttons["code-submit"].exists, "no Continue button")
        // Return submits, as Continue does, and cannot be hidden by the keyboard.
        field.typeText("\n")
        XCTAssertTrue(app.descendants(matching: .any)["code-error"].waitForExistence(timeout: 15), "a wrong code said nothing")
        XCTAssertFalse(app.tabBars.firstMatch.exists, "a wrong code opened the app")

        // The review code opens the app, in the demo.
        field.tap()
        if let typed = field.value as? String, !typed.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: typed.count))
        }
        field.typeText(reviewCode + "\n")
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 20), "the review code did not open the app")
        XCTAssertTrue(badge(app).waitForExistence(timeout: 10), "no Demo strip")
        // Everything, as an owner would see it.
        for tab in ["Today", "Family", "Chat", "Health", "More"] {
            XCTAssertTrue(app.tabBars.buttons[tab].exists, "missing tab \(tab) in the demo")
        }
        attach(app, "Review demo — Today")

        // Family: the map and made-up people.
        XCTAssertTrue(app.openTab("Family"))
        XCTAssertTrue(byId(app, "family-map").waitForExistence(timeout: 15), "no family map in the demo")
        XCTAssertTrue(badge(app).exists, "the Demo strip left on Family")
        attach(app, "Review demo — Family")

        // Health: the figures.
        XCTAssertTrue(app.openTab("Health"))
        attach(app, "Review demo — Health")

        // Chat: a message gets a canned reply.
        XCTAssertTrue(app.openTab("Chat"))
        let thread = byId(app, "thread-demo-thread-training")
        XCTAssertTrue(thread.waitForExistence(timeout: 15), "no demo threads")
        thread.tap()
        let composer = byId(app, "chat-composer")
        XCTAssertTrue(composer.waitForExistence(timeout: 15))
        composer.tap()
        composer.typeText("How did I sleep?")
        app.buttons["chat-send"].tap()
        // The reply's own sign-off, not the strip's words.
        let reply = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "generated on this iPhone")).firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 20), "a demo message got no reply")
        attach(app, "Review demo — Chat reply")
        back(app)

        // News, Games, Steps and Tasks, through More.
        XCTAssertTrue(app.openTab("News"))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "news-row-")).firstMatch
            .waitForExistence(timeout: 15), "no demo stories")
        attach(app, "Review demo — News")
        back(app)
        XCTAssertTrue(app.openTab("Games"))
        XCTAssertTrue(byId(app, "games-screen").waitForExistence(timeout: 15), "no Games lobby in the demo")
        attach(app, "Review demo — Games")
        back(app)
        XCTAssertTrue(app.openTab("Steps"))
        XCTAssertTrue(byId(app, "steps-hero").waitForExistence(timeout: 15), "no step board in the demo")
        attach(app, "Review demo — Steps")
        back(app)

        // Tasks: confirm one waiting for a parent, and it moves on.
        XCTAssertTrue(app.openTab("Tasks"))
        // By label: the row's own identifier (`task-row-…`) is what its
        // children report, the button's included.
        let confirm = app.buttons["Confirm: Reading log signed"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 15), "no task waiting to be confirmed")
        confirm.tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: confirm)
        wait(for: [gone], timeout: 15)
        attach(app, "Review demo — Tasks, one confirmed")
        back(app)

        // Settings says it is a demo, and leaves it.
        XCTAssertTrue(app.openTab("Today"))
        XCTAssertTrue(app.openSettings(), "no way into Settings")
        let leave = app.buttons["settings-leave-demo"]
        XCTAssertTrue(leave.waitForExistence(timeout: 10), "no Leave demo in Settings")
        attach(app, "Review demo — Settings")
        leave.tap()
        XCTAssertTrue(app.buttons["welcome-google"].waitForExistence(timeout: 15), "leaving the demo did not go back to Welcome")
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        XCTAssertFalse(badge(app).exists)
    }

    @MainActor func testTheDemoSurvivesARelaunchUntilLeft() {
        let app = XCUIApplication()
        app.launchArguments = ["-SRFreshInstall", "-SRStubNetwork"]
        app.launch()
        let haveCode = app.buttons["welcome-have-code"]
        XCTAssertTrue(haveCode.waitForExistence(timeout: 20))
        haveCode.tap()
        let field = app.textFields["code-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(reviewCode + "\n")
        XCTAssertTrue(badge(app).waitForExistence(timeout: 20))

        // A reviewer who closes the app comes back to the demo, not Welcome.
        app.terminate()
        app.launchArguments = ["-SRStubNetwork"]
        app.launch()
        XCTAssertTrue(badge(app).waitForExistence(timeout: 20), "a relaunch dropped the demo")
        XCTAssertTrue(app.tabBars.buttons["Today"].exists)

        XCTAssertTrue(app.openSettings())
        let leave = app.buttons["settings-leave-demo"]
        XCTAssertTrue(leave.waitForExistence(timeout: 10))
        leave.tap()
        XCTAssertTrue(app.buttons["welcome-have-code"].waitForExistence(timeout: 15))
    }

    // MARK: - Helpers

    /// Back out of a pushed screen to the root of its stack.
    @MainActor private func back(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.waitForExistence(timeout: 5) { back.tap() }
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 5)
    }

    @MainActor private func badge(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["demo-badge"].firstMatch
    }

    @MainActor private func byId(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
