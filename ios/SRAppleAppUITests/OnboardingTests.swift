import XCTest

final class OnboardingTests: XCTestCase {
    @MainActor func testUnpairedLaunchAndHTTPSValidation() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Connect your iPhone"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Pair by QR code"].exists)
        XCTAssertFalse(app.buttons["Connect"].isEnabled)
        let server = app.textFields["HTTPS server address"]
        server.tap(); server.typeText("http://example.test\n")
        let code = app.secureTextFields["One-time pairing code"]
        code.typeText("invalid-code\n")
        let status = app.staticTexts["sync-status"]
        let validation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "HTTPS"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [validation], timeout: 10), .completed)
        XCTAssertFalse(app.switches["Share location with my family"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Unpaired iPhone onboarding"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
    @MainActor func testVisibleManualCodeAndScannerFallback() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Pair by QR code"].waitForExistence(timeout: 15))
        app.buttons["Pair by QR code"].tap()
        XCTAssertTrue(app.staticTexts["Camera scanning is unavailable on this device. Use manual pairing instead."].waitForExistence(timeout: 10))
        app.buttons["Cancel"].tap()
        app.swipeUp()
        app.switches["Show pairing code"].tap()
        let code = app.textFields["One-time pairing code"]
        code.tap(); code.typeText("visible-test-code")
        XCTAssertEqual(code.value as? String, "visible-test-code")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Readable pairing fields with system dark appearance"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor func testJKAIChatCanOpenBeforeHealthPairingAndReturn() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["JKAI"].waitForExistence(timeout: 15))
        app.tabBars.buttons["JKAI"].tap()
        XCTAssertTrue(app.buttons["open-jkai-chat"].waitForExistence(timeout: 5))
        let entry = XCTAttachment(screenshot: app.screenshot())
        entry.name = "JKAI companion tab"
        entry.lifetime = .keepAlways
        add(entry)
        app.buttons["open-jkai-chat"].tap()
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 15))
        close.tap()
        XCTAssertTrue(app.buttons["open-jkai-chat"].waitForExistence(timeout: 5))
        app.buttons["open-jkai-chat"].tap()
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        close.tap()
        app.tabBars.buttons["Companion"].tap()
        XCTAssertTrue(app.staticTexts["Connect your iPhone"].waitForExistence(timeout: 5))
    }

}
