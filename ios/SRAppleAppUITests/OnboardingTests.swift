import XCTest

final class OnboardingTests: XCTestCase {
    @MainActor func testUnpairedLaunchAndHTTPSValidation() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Connect your iPhone"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Connect"].isEnabled)
        let server = app.textFields["HTTPS server address"]
        server.tap(); server.typeText("http://example.test")
        let code = app.secureTextFields["One-time pairing code"]
        code.tap(); code.typeText("invalid-code")
        app.buttons["Connect"].tap()
        let status = app.staticTexts["sync-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("HTTPS"))
        XCTAssertFalse(app.switches["Share location with my family"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Unpaired iPhone onboarding"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
