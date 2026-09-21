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
        closeBrowser(in: app)
        XCTAssertTrue(app.buttons["open-jkai-chat"].waitForExistence(timeout: 5))
        app.buttons["open-jkai-chat"].tap()
        closeBrowser(in: app)
        app.tabBars.buttons["Companion"].tap()
        XCTAssertTrue(app.staticTexts["Connect your iPhone"].waitForExistence(timeout: 5))
    }

    @MainActor func testMainPageWebsiteLinksOpenAndReturn() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["site-jkai"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["site-news"].exists)
        XCTAssertTrue(app.buttons["site-health"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Main page JKAI News and Health links"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        for destination in ["site-news", "site-health"] {
            app.buttons[destination].tap()
            closeBrowser(in: app)
            XCTAssertTrue(app.buttons[destination].waitForExistence(timeout: 5))
        }
        app.swipeUp()
        XCTAssertTrue(app.buttons["Pair by QR code"].exists)
    }

    @MainActor private func closeBrowser(in app: XCUIApplication) {
        // Safari is hosted in a remote process, so wait until its own toolbar
        // is fully available before trying to dismiss it.
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 30))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: close)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Website before closing"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        close.tap()
    }

}
