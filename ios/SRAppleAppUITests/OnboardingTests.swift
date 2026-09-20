import XCTest

final class OnboardingTests: XCTestCase {
    @MainActor func testUnpairedLaunchAndHTTPSValidation() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Connect your iPhone"].waitForExistence(timeout: 15))
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
}
