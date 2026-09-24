import XCTest

/// The composer's behaviour, asserted — unlike `ShowcaseTests`, a miss here fails.
///
/// Runs against `-SRDemo`, where the chat endpoint answers every send with a
/// calm refusal. That is enough: what is under test is what the composer does
/// with the draft, not what the server does with the turn.
final class ChatComposerTests: XCTestCase {

    @MainActor func testSendingEmptiesTheComposer() {
        let app = XCUIApplication()
        app.launchArguments = ["-SRDemo"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Chat"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Chat"].tap()
        let thread = app.descendants(matching: .any)["thread-demo-thread-training"].firstMatch
        XCTAssertTrue(thread.waitForExistence(timeout: 15))
        thread.tap()

        let composer = app.descendants(matching: .any)["chat-composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 15))
        composer.tap()
        composer.typeText("How did the long run go")

        let send = app.buttons["chat-send"]
        XCTAssertTrue(send.isEnabled)
        send.tap()

        // Past the deferred second clear, so a draft written back by the text
        // view would be on screen by now.
        let later = expectation(description: "after the send")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { later.fulfill() }
        wait(for: [later], timeout: 5)

        let value = (composer.value as? String) ?? ""
        XCTAssertFalse(value.contains("long run"), "the sent text is still in the composer: \(value)")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Chat — after a send"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor func testAttachOffersPhotosAndFiles() {
        let app = XCUIApplication()
        app.launchArguments = ["-SRDemo"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Chat"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Chat"].tap()
        let thread = app.descendants(matching: .any)["thread-demo-thread-training"].firstMatch
        XCTAssertTrue(thread.waitForExistence(timeout: 15))
        thread.tap()

        let attach = app.descendants(matching: .any)["chat-attach"].firstMatch
        XCTAssertTrue(attach.waitForExistence(timeout: 15))
        attach.tap()
        XCTAssertTrue(app.buttons["Photo Library"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Choose File"].exists)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Chat — attach menu"
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: - The richer thread

    @MainActor private func openTrainingThread() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-SRDemo"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Chat"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Chat"].tap()
        let thread = app.descendants(matching: .any)["thread-demo-thread-training"].firstMatch
        XCTAssertTrue(thread.waitForExistence(timeout: 15))
        thread.tap()
        return app
    }

    @MainActor private func shoot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor func testAnEmptyComposerOffersTheMic() {
        let app = openTrainingThread()
        XCTAssertTrue(app.descendants(matching: .any)["chat-mic"].firstMatch.waitForExistence(timeout: 15),
                      "an empty composer should show the mic in the send button's place")
        let composer = app.descendants(matching: .any)["chat-composer"].firstMatch
        composer.tap()
        composer.typeText("x")
        XCTAssertTrue(app.buttons["chat-send"].waitForExistence(timeout: 5), "typing should bring Send back")
    }

    @MainActor func testChartsTablesAndSourcesDraw() {
        let app = openTrainingThread()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "2 sources")).firstMatch.waitForExistence(timeout: 15),
                      "the sources line did not draw")
        shoot(app, "Chat — chart and sources")
        app.swipeUp()
        shoot(app, "Chat — table")
        let sources = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "sources")).firstMatch
        if sources.exists && sources.isHittable {
            sources.tap()
            XCTAssertTrue(app.staticTexts["Marathon taper, what the studies say"].waitForExistence(timeout: 5))
            shoot(app, "Chat — sources sheet")
        }
    }

    @MainActor func testModelAndThinkingSheet() {
        let app = openTrainingThread()
        let actions = app.buttons["Thread actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 15))
        actions.tap()
        let item = app.buttons["Model & thinking"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        XCTAssertTrue(app.staticTexts["GPT-6 Astra"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Medium"].exists, "the thinking levels did not list")
        shoot(app, "Chat — model and thinking")
    }

    @MainActor func testANewThreadOffersStarters() {
        let app = XCUIApplication()
        app.launchArguments = ["-SRDemo"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Chat"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Chat"].tap()
        let new = app.buttons["thread-new"]
        XCTAssertTrue(new.waitForExistence(timeout: 15))
        new.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Check the house")).firstMatch.waitForExistence(timeout: 15))
        shoot(app, "Chat — a new thread")
    }
}
