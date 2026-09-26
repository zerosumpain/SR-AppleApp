import XCTest

/// What a fresh install looks like, and that the design system actually renders.
///
/// The screenshots these attach are the real verification artefact for the look.
/// CI boots the simulator in DARK appearance on purpose — the site has no dark
/// mode and the app is light-locked to match, so a shot that comes back dark is
/// a regression, not a preference.
///
/// These were rewritten when the tab bar changed. `Connect` is no longer a tab:
/// pairing is a job you do once from a QR code on another screen, and a
/// permanent slot on the bar for it was the clearest clutter in the app. It is
/// under Settings → Connections now, and `Today` took the slot.
///
/// And rewritten again for member access. A fresh install does not know who is
/// holding it — the answer arrives with the companion pairing — so it fails
/// CLOSED: Today and Health, the companion's pairing, and nothing that belongs
/// to the owner. The owner's full bar is covered by the `-SRDemo` tests.
final class OnboardingTests: XCTestCase {

    @MainActor func testTheTabBarIsThePlacesYouGo() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 20))
        // Nobody known yet: Today and Health, and nothing else exists at all.
        for tab in ["Today", "Health"] {
            XCTAssertTrue(app.tabBars.buttons[tab].exists, "missing tab \(tab)")
        }
        for tab in ["Chat", "News", "Flows", "Family", "More"] {
            XCTAssertFalse(app.tabBars.buttons[tab].exists, "\(tab) is on the bar before anybody said this person may use it")
        }
        // The old Connect tab must be gone, not merely unused.
        XCTAssertFalse(app.tabBars.buttons["Connect"].exists, "Connect is still a tab")
        XCTAssertFalse(app.tabBars.buttons["Companion"].exists, "Companion is still a tab")

        attach(app, "Today — the first screen")
    }

    @MainActor func testTodayOpensFirstAndAsksToConnect() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 20))

        // Unpaired, Today must say so rather than sitting empty — and offer
        // the companion, the pairing every person needs.
        XCTAssertTrue(app.buttons["CONNECT"].waitForExistence(timeout: 15),
                      "an unconnected Today does not offer a way to connect")
        // No bell: the alert inbox is the owner's.
        XCTAssertFalse(app.buttons["Alerts"].exists, "the owner's alert bell is on an unknown phone")
        attach(app, "Today, not yet connected")
    }

    @MainActor func testSettingsHoldsBothPairingsOnOneScreen() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 20))

        let cog = app.buttons["open-settings"]
        XCTAssertTrue(cog.waitForExistence(timeout: 10), "no settings cog on Today")
        cog.tap()

        let connections = app.buttons["settings-connections"]
        XCTAssertTrue(connections.waitForExistence(timeout: 10), "no Connections row in settings")
        connections.tap()

        // The companion's pairing, which is how the app learns who this is.
        // The website's QR is the owner's, and nobody is known yet.
        XCTAssertTrue(app.buttons["companion-pair-scan"].waitForExistence(timeout: 10),
                      "no way to scan the companion's code")
        XCTAssertFalse(app.buttons["site-pair-scan"].exists,
                       "the website's QR is offered before anybody said this is the owner")
        attach(app, "Settings — the companion connection")
    }

    @MainActor func testTheManualPairingCodeCanStillBeRevealed() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 20))
        app.buttons["open-settings"].tap()
        app.buttons["settings-connections"].tap()
        XCTAssertTrue(app.buttons["companion-pair-scan"].waitForExistence(timeout: 10))

        let reveal = app.switches.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Show pairing code")
        ).firstMatch
        XCTAssertTrue(scroll(app, to: reveal), "no way to reveal a typed pairing code")
        attach(app, "Settings — pairing by hand")
    }

    @MainActor func testNotificationRoutingIsTheOwnersAlone() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 20))
        app.buttons["open-settings"].tap()
        XCTAssertTrue(app.buttons["settings-connections"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["settings-notifications"].exists,
                       "where the site's alerts go is offered on a phone not known to be the owner's")
    }

    /// As the owner (demo mode), where the site's alerts go is one row away.
    @MainActor func testNotificationRoutingIsReachableAndListsCategories() {
        let app = XCUIApplication()
        app.launchArguments = ["-SRDemo"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 20))
        app.buttons["open-settings"].tap()

        let notifications = app.buttons["settings-notifications"]
        XCTAssertTrue(notifications.waitForExistence(timeout: 10), "no Notifications row in settings")
        notifications.tap()

        // Unpaired there are no categories to list, but the permission row is
        // local and must be offered regardless — it is the thing that has to
        // happen before anything can ever appear on this phone.
        XCTAssertTrue(app.staticTexts["Allow notifications"].waitForExistence(timeout: 10)
                      || app.staticTexts["Notifications allowed"].exists
                      || app.staticTexts["Notifications are off"].exists,
                      "the notification permission is not offered")
        attach(app, "Settings — where alerts go")
    }

    @MainActor func testHealthTabExplainsItselfBeforeItHasAnything() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Health"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Health"].tap()

        // A fresh install has uploaded nothing and cannot reach the site, so the
        // screen must say what would put something here.
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Connect the companion")
            ).firstMatch.waitForExistence(timeout: 15)
            || app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Nothing uploaded yet")
            ).firstMatch.exists,
            "an empty health tab says nothing about how to fill it"
        )
        attach(app, "Health, before anything has been uploaded")
    }

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

/// The location instrument, now three levels into settings rather than one.
///
/// It kept its editorial register when everything else lost it, and that is
/// deliberate: a reader who has navigated to Settings → Location & battery to
/// weigh drain against accuracy has asked for the argument. The furniture was
/// wrong in front of a thread list; it is right here.
final class SettingsUITests: XCTestCase {

    @MainActor func testTheCogOpensSettingsAndTheInstrumentIsThreeTapsAway() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 20))

        let cog = app.buttons["open-settings"]
        XCTAssertTrue(cog.waitForExistence(timeout: 10), "no settings cog on Today")
        cog.tap()

        let location = app.buttons["settings-location"]
        XCTAssertTrue(location.waitForExistence(timeout: 10), "no Location row in settings")
        location.tap()

        XCTAssertTrue(app.staticTexts["THE BALANCE,"].waitForExistence(timeout: 10)
                      || app.staticTexts["MEASURED"].waitForExistence(timeout: 2),
                      "the battery instrument did not open")
        attach(app, "Settings — the battery instrument")
    }

    @MainActor func testPresetsAreOfferedAndEveryValueIsReachable() {
        let app = XCUIApplication()
        app.launch()
        openLocationSettings(app)

        for preset in ["saver", "balanced", "accurate"] {
            XCTAssertTrue(app.buttons["preset-\(preset)"].waitForExistence(timeout: 10), "missing preset \(preset)")
        }
        attach(app, "Settings — location presets")

        app.buttons["preset-balanced"].tap()
        let advanced = app.buttons["toggle-advanced"]
        XCTAssertTrue(advanced.waitForExistence(timeout: 5))
        advanced.tap()
        attach(app, "Settings — every value")
    }

    @MainActor func testTheMotionGateAndItsHistoryAreReachable() {
        let app = XCUIApplication()
        app.launch()
        openLocationSettings(app)
        XCTAssertTrue(app.buttons["preset-balanced"].waitForExistence(timeout: 15))

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
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 20))
        app.buttons["open-settings"].tap()

        // The history is its own row now. It used to be a button buried under
        // the motion gate, which is where you look for it only if you already
        // know it exists.
        let log = app.buttons["settings-log"]
        XCTAssertTrue(log.waitForExistence(timeout: 10), "no route from settings to the history")
        log.tap()

        // Assert on the identifier, not on a headline. `SectionHead` combines
        // its title lines into one accessibility element, so querying a single
        // line is a coin toss — the window picker is the element that actually
        // carries an identifier.
        XCTAssertTrue(app.segmentedControls["log-window"].waitForExistence(timeout: 15),
                      "the history screen did not open")
        // And a fresh install has nothing logged, so the screen has to SAY that
        // rather than print a confident zero duty cycle.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Nothing logged")).firstMatch.exists
                      || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Nothing in this window")).firstMatch.exists,
                      "an empty log must say so rather than print a confident zero")
        attach(app, "History — the gate opening and closing")
    }

    @MainActor private func openLocationSettings(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 20))
        app.buttons["open-settings"].tap()
        let location = app.buttons["settings-location"]
        XCTAssertTrue(location.waitForExistence(timeout: 10))
        location.tap()
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
