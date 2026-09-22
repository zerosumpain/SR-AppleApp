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

/// The settings screen renders, and the instrument says what it is standing on.
final class SettingsUITests: XCTestCase {

    @MainActor func testTheCogOpensSettingsFromTheBar() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Companion"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Companion"].tap()

        let cog = app.buttons["sr-bar-action"]
        XCTAssertTrue(cog.waitForExistence(timeout: 10), "no settings cog on the bar")
        cog.tap()

        XCTAssertTrue(app.staticTexts["THE BALANCE,"].waitForExistence(timeout: 10)
                      || app.staticTexts["MEASURED"].waitForExistence(timeout: 2))
        attach(app, "Settings — the battery instrument")
    }

    @MainActor func testPresetsAreOfferedAndEveryValueIsReachable() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Companion"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Companion"].tap()
        app.buttons["sr-bar-action"].tap()

        for preset in ["saver", "balanced", "accurate"] {
            XCTAssertTrue(app.buttons["preset-\(preset)"].waitForExistence(timeout: 10), "missing preset \(preset)")
        }
        attach(app, "Settings — location presets")

        // The advanced block is collapsed by default; every value lives under it.
        app.buttons["preset-balanced"].tap()
        let advanced = app.buttons["toggle-advanced"]
        XCTAssertTrue(advanced.waitForExistence(timeout: 5))
        advanced.tap()
        attach(app, "Settings — every value")
    }

    @MainActor func testTheMotionGateAndItsHistoryAreReachable() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Companion"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Companion"].tap()
        app.buttons["sr-bar-action"].tap()
        XCTAssertTrue(app.buttons["preset-balanced"].waitForExistence(timeout: 15))

        // Section C is below the presets, so this scrolls rather than assuming.
        let toggle = app.switches["motion-enabled"]
        XCTAssertTrue(scroll(app, to: toggle), "no motion gate switch on the settings screen")
        attach(app, "Settings — the motion gate")

        let levers = app.buttons["toggle-motion-advanced"]
        XCTAssertTrue(scroll(app, to: levers))
        levers.tap()
        attach(app, "Settings — every movement value")
    }

    @MainActor func testTheHistoryScreenOpensAndSaysWhatItIsStandingOn() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Companion"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Companion"].tap()
        app.buttons["sr-bar-action"].tap()
        XCTAssertTrue(app.buttons["preset-balanced"].waitForExistence(timeout: 15))

        let open = app.buttons["WHEN GPS WENT ON AND OFF"]
        XCTAssertTrue(scroll(app, to: open), "no route from settings to the history")
        open.tap()

        // A fresh install has nothing logged, and the screen has to SAY that
        // rather than print a confident zero duty cycle.
        XCTAssertTrue(app.staticTexts["WHAT THE GATE"].waitForExistence(timeout: 10)
                      || app.staticTexts["ACTUALLY SAVED"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.segmentedControls["log-window"].waitForExistence(timeout: 5))
        attach(app, "History — the gate opening and closing")
    }

    /// Swipe until it is on screen, or give up. Every one of these sits below
    /// the fold on a phone, which is the point of the sections being ordered by
    /// what you read first rather than by what you change most.
    @MainActor private func scroll(_ app: XCUIApplication, to element: XCUIElement, swipes: Int = 8) -> Bool {
        for _ in 0..<swipes {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
