import XCTest

/// What a fresh install looks like, and that the design system actually renders.
///
/// The screenshots these attach are the real verification artefact for the look.
/// CI boots the simulator in DARK appearance on purpose — the site has no dark
/// mode and the app is light-locked to match, so a shot that comes back dark is
/// a regression, not a preference.
final class OnboardingTests: XCTestCase {

    @MainActor func testFourTabsAndChatAsksToConnect() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Chat"].waitForExistence(timeout: 20))
        for tab in ["Chat", "News", "Companion", "Connect"] {
            XCTAssertTrue(app.tabBars.buttons[tab].exists, "missing tab \(tab)")
        }

        // Chat opens first and, unpaired, must say so rather than sitting empty.
        XCTAssertTrue(app.staticTexts["CONNECT TO"].waitForExistence(timeout: 10)
                      || app.staticTexts["READ YOUR THREADS"].waitForExistence(timeout: 2))

        attach(app, "Chat tab, not yet connected")
    }

    @MainActor func testNewsAndChatBothGateOnPairing() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["News"].waitForExistence(timeout: 20))

        app.tabBars.buttons["News"].tap()
        XCTAssertTrue(app.buttons["CONNECT"].waitForExistence(timeout: 10))
        attach(app, "News tab, not yet connected")

        // The Connect button on an unpaired tab must land on the Connect tab.
        app.buttons["CONNECT"].tap()
        XCTAssertTrue(app.buttons["site-pair-scan"].waitForExistence(timeout: 10))
        attach(app, "Site pairing screen")
    }

    @MainActor func testSitePairingExplainsTheTwoCredentials() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Connect"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Connect"].tap()

        XCTAssertTrue(app.buttons["site-pair-scan"].waitForExistence(timeout: 10))
        // Two pairings in one app is the thing a reader will get wrong, so the
        // screen has to say it outright.
        XCTAssertTrue(app.staticTexts["WHAT THIS IS NOT"].exists)
        attach(app, "Site pairing, with the two-credential note")
    }

    @MainActor func testCompanionPairingStillWorksAndIsOnTheSystem() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Companion"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Companion"].tap()

        XCTAssertTrue(app.buttons["PAIR BY QR CODE"].waitForExistence(timeout: 10))
        attach(app, "Companion tab on the design system")

        let server = app.textFields["HTTPS server address"]
        XCTAssertTrue(server.waitForExistence(timeout: 5))
        server.tap()
        server.typeText("http://example.test\n")

        let code = app.secureTextFields["One-time pairing code"]
        code.typeText("invalid-code\n")

        // Plain HTTP must be refused, and the refusal must reach the reader.
        let status = app.staticTexts["sync-status"]
        let validation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "HTTPS"),
            object: status
        )
        XCTAssertEqual(XCTWaiter.wait(for: [validation], timeout: 15), .completed)
        attach(app, "Companion refusing plain HTTP")
    }

    @MainActor func testManualPairingCodeCanBeRevealed() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Companion"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Companion"].tap()

        XCTAssertTrue(app.switches["Show pairing code"].waitForExistence(timeout: 10))
        app.switches["Show pairing code"].tap()
        let code = app.textFields["One-time pairing code"]
        code.tap()
        code.typeText("visible-test-code")
        XCTAssertEqual(code.value as? String, "visible-test-code")
        attach(app, "Readable pairing fields under system dark appearance")
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
