import XCTest

final class CommissionUITests: XCTestCase {
    private let awaiting = "11111111-1111-4111-8111-111111111111"

    /// From Today's tile to a note waiting for your call, its double-check's
    /// sign-off sheet, the OK, and the report that comes back.
    @MainActor func testOwnerReviewsApprovesAndSeesTheEvidenceReport() {
        let app = XCUIApplication()
        app.launchArguments = ["-SRDemo", "-SRFreshInstall", "-SRCommissionUITest"]
        app.launch()
        openDaydream(app)

        // The HRV note waits for a call, so it is on the default list, with
        // its double-check's status row.
        let proposal = app.buttons["commission-\(awaiting)"]
        XCTAssertTrue(proposal.waitForExistence(timeout: 15))
        XCTAssertTrue(scroll(app, to: proposal))
        proposal.tap()

        XCTAssertTrue(app.descendants(matching: .any)["commission-track"].firstMatch.waitForExistence(timeout: 15))
        let approve = app.buttons["commission-approve"]
        XCTAssertTrue(approve.waitForExistence(timeout: 15))
        XCTAssertTrue(scroll(app, to: approve, swipes: 12))
        approve.tap()

        let report = app.staticTexts["commission-evidence-report"]
        XCTAssertTrue(report.waitForExistence(timeout: 15))
        XCTAssertTrue(report.label.hasPrefix("The dip still shows."), report.label)
        XCTAssertFalse(approve.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Daydream approved evidence report"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// The four-step strip, the explanation folding away, and each list.
    @MainActor func testTheGuidedPageShowsTheProcess() {
        let app = XCUIApplication()
        app.launchArguments = ["-SRDemo", "-SRFreshInstall"]
        app.launch()
        openDaydream(app)

        XCTAssertTrue(app.descendants(matching: .any)["daydream-pipeline"].firstMatch.waitForExistence(timeout: 15))
        let gotIt = app.buttons["daydream-how-it-works-done"]
        if gotIt.waitForExistence(timeout: 3) {
            attach(app, "Daydream — how it works")
            gotIt.tap()
        }
        XCTAssertTrue(app.buttons["daydream-how-it-works-open"].waitForExistence(timeout: 5))

        // To decide, by default: notes with their three choices.
        XCTAssertTrue(app.buttons.matching(identifier: "noticed-useful").firstMatch.waitForExistence(timeout: 15))
        attach(app, "Daydream — to decide")

        let motion = app.buttons["daydream-stage-motion"]
        XCTAssertTrue(motion.waitForExistence(timeout: 5))
        motion.tap()
        XCTAssertTrue(app.descendants(matching: .any)["daydream-note-demo-note-subscriptions"].firstMatch.waitForExistence(timeout: 5))
        attach(app, "Daydream — in motion")

        let result = app.buttons["daydream-stage-result"]
        result.tap()
        XCTAssertTrue(app.descendants(matching: .any)["daydream-note-demo-note-hall-light"].firstMatch.waitForExistence(timeout: 5))
        let impact = app.descendants(matching: .any)["daydream-impact"].firstMatch
        XCTAssertTrue(impact.waitForExistence(timeout: 5))
        _ = scroll(app, to: impact)
        attach(app, "Daydream — impact")
    }

    /// "It's wrong — say why": the reason goes to the site and comes back on
    /// the card as the lesson kept.
    @MainActor func testOwnerTellsANoteItIsWrongAndWhy() {
        let app = XCUIApplication()
        app.launchArguments = ["-SRDemo", "-SRFreshInstall"]
        app.launch()
        openDaydream(app)
        let gotIt = app.buttons["daydream-how-it-works-done"]
        if gotIt.waitForExistence(timeout: 3) { gotIt.tap() }

        let card = app.descendants(matching: .any)["daydream-note-demo-note-renewals"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        let more = card.buttons["noticed-more"]
        XCTAssertTrue(scroll(app, to: more))
        more.tap()
        let wrong = app.buttons["It's wrong — say why"]
        XCTAssertTrue(wrong.waitForExistence(timeout: 5))
        wrong.tap()

        let why = app.textViews["daydream-ruling-why"]
        XCTAssertTrue(why.waitForExistence(timeout: 5))
        let send = app.buttons["daydream-ruling-send"]
        XCTAssertFalse(send.isEnabled, "A wrong needs a reason")
        why.tap()
        why.typeText("Two of those renew in different months")
        XCTAssertTrue(send.isEnabled)
        attach(app, "Daydream — it's wrong, and why")
        send.tap()

        let lesson = card.staticTexts["daydream-review-lesson"]
        XCTAssertTrue(lesson.waitForExistence(timeout: 10))
        XCTAssertTrue(lesson.label.contains("Two of those renew in different months"), lesson.label)
        XCTAssertTrue(card.buttons["daydream-review-argue"].exists)
        _ = scroll(app, to: lesson)
        attach(app, "Daydream — lesson kept")
    }

    /// "Do it for me": one tap, no further questions, and an Undo.
    @MainActor func testOwnerHasTheStepDoneWithOneTap() {
        let app = XCUIApplication()
        app.launchArguments = ["-SRDemo", "-SRFreshInstall"]
        app.launch()
        openDaydream(app)
        let gotIt = app.buttons["daydream-how-it-works-done"]
        if gotIt.waitForExistence(timeout: 3) { gotIt.tap() }

        let card = app.descendants(matching: .any)["daydream-note-demo-note-renewals"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        let doIt = card.buttons["daydream-do-it"]
        XCTAssertTrue(scroll(app, to: doIt))
        attach(app, "Daydream — do it for me")
        doIt.tap()

        let undo = card.buttons["daydream-act-undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 10))
        XCTAssertFalse(app.sheets.firstMatch.exists, "No further questions")
        _ = scroll(app, to: undo)
        attach(app, "Daydream — done for you")
    }

    // MARK: - Helpers

    @MainActor private func openDaydream(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 20))
        let tile = app.descendants(matching: .any)["today-daydream"].firstMatch
        for _ in 0..<8 {
            if tile.exists && tile.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(tile.isHittable)
        tile.tap()
        XCTAssertTrue(app.descendants(matching: .any)["daydream-screen"].firstMatch.waitForExistence(timeout: 15))
    }

    @MainActor private func scroll(_ app: XCUIApplication, to element: XCUIElement, swipes: Int = 8) -> Bool {
        for _ in 0..<swipes {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
