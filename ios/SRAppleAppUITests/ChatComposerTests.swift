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
}
