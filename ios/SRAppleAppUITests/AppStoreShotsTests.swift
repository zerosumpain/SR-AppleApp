import XCTest

/// The App Store listing's eight pictures, and nothing else.
///
/// `ShowcaseTests` photographs every screen for reviewing the look, softly: a
/// missed landmark is noted and the shot is taken anyway, so a "Steps" picture
/// can quietly be of Today. These are the opposite. Each one HARD-asserts that
/// its screen is up (a known identifier or text) before it shoots, waits for
/// spinners to go, and names the attachment `Store NN — …` so the
/// `App Store screenshots` workflow can pick exactly these out of the result
/// bundle (docs/APP-STORE.md §7).
///
/// `-SRStoreShots` on top of `-SRDemo` keeps the same fixtures but takes out
/// what a listing must not show: the "a connection needs you" banner, the
/// urgent alert pinned under Today, and real brand names (`SRStoreShots`).
final class AppStoreShotsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // One method per shot: a miss stops that shot, never the others.
        continueAfterFailure = false
    }

    // MARK: - The eight

    @MainActor func testStore01Today() {
        let app = launch()
        require(app.tabBars.buttons["Today"], "the Today tab")
        require(byId(app, "today-family"), "the family map on Today")
        require(byId(app, "today-steps"), "the Steps card on Today")
        require(byId(app, "today-tasks"), "the Tasks card on Today")
        noBanners(app)
        shoot(app, "Store 01 — Today")
    }

    @MainActor func testStore02FamilyMap() {
        let app = launch()
        require(app.tabBars.buttons["Today"], "the Today tab")
        XCTAssertTrue(app.openTab("Family"), "no way to the Family tab")
        require(byId(app, "family-map"), "the family map")
        require(byId(app, "family-person-sam"), "Sam's row on Family")
        noBanners(app)
        // Map tiles and pins draw after the page does.
        shoot(app, "Store 02 — Family map", extra: 3)
    }

    @MainActor func testStore03Steps() {
        let app = launch()
        require(app.tabBars.buttons["Today"], "the Today tab")
        openPage(app, card: "today-steps", orTab: "Steps")
        require(byId(app, "steps-hero"), "the step board's hero")
        noBanners(app)
        shoot(app, "Store 03 — Steps leaderboard")
    }

    @MainActor func testStore04TasksOpen() {
        let app = launch()
        require(app.tabBars.buttons["Today"], "the Today tab")
        openPage(app, card: "today-tasks", orTab: "Tasks")
        require(byId(app, "family-tasks-screen"), "the task list")
        let segment = app.segmentedControls.buttons["Open"]
        require(segment, "the Open segment")
        if !segment.isSelected { segment.tap() }
        require(byId(app, "task-row-t_dishes"), "an open task row")
        noBanners(app)
        shoot(app, "Store 04 — Tasks, open")
    }

    @MainActor func testStore05TasksOwed() {
        let app = launch()
        require(app.tabBars.buttons["Today"], "the Today tab")
        openPage(app, card: "today-tasks", orTab: "Tasks")
        require(byId(app, "family-tasks-screen"), "the task list")
        let segment = app.segmentedControls.buttons["Owed"]
        require(segment, "the Owed segment")
        segment.tap()
        require(byId(app, "tasks-owed-total"), "the owed total")
        noBanners(app)
        shoot(app, "Store 05 — Tasks, owed")
    }

    @MainActor func testStore06Health() {
        let app = launch()
        require(app.tabBars.buttons["Today"], "the Today tab")
        XCTAssertTrue(app.openTab("Health"), "no way to the Health tab")
        // The verdict draws uppercased ("PRIMED"): match its label, any case.
        require(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Primed")).firstMatch,
                "the readiness verdict on Health")
        noBanners(app)
        shoot(app, "Store 06 — Health")
    }

    @MainActor func testStore07ChatThread() {
        let app = launch()
        require(app.tabBars.buttons["Today"], "the Today tab")
        XCTAssertTrue(app.openTab("Chat"), "no way to the Chat tab")
        let thread = byId(app, "thread-demo-thread-training")
        require(thread, "the training thread in the list")
        thread.tap()
        require(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "42.1 km")).firstMatch,
                "the week 6 reply in the thread")
        noBanners(app)
        shoot(app, "Store 07 — Chat thread")
    }

    @MainActor func testStore08Games() {
        let app = launch()
        require(app.tabBars.buttons["Today"], "the Today tab")
        XCTAssertTrue(app.openTab("Games"), "no way to the Games tab")
        require(byId(app, "games-screen"), "the Games page")
        require(byId(app, "games-invite-g_demo_invite"), "Sam's invitation")
        noBanners(app)
        shoot(app, "Store 08 — Games")
    }

    // MARK: - Helpers

    /// The demo, for the store: both optional Today cards on (`@AppStorage`
    /// reads the launch arguments), no connection banner, no urgent alert.
    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-SRDemo", "-SRStoreShots",
                               "-today-card-steps", "YES", "-today-card-tasks", "YES"]
        app.launch()
        return app
    }

    @MainActor private func byId(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// A landmark the shot is worthless without. Stops the method on a miss.
    @MainActor private func require(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 20) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "not on screen: \(what)")
    }

    /// A family page by its Today card (the way a person gets there), else
    /// through More.
    @MainActor private func openPage(_ app: XCUIApplication, card id: String, orTab tab: String) {
        let card = byId(app, id)
        if card.waitForExistence(timeout: 15) {
            for _ in 0..<4 where !card.isHittable { app.swipeUp() }
        }
        if card.exists && card.isHittable {
            card.tap()
        } else {
            XCTAssertTrue(app.openTab(tab), "no way to \(tab)")
        }
    }

    /// Nothing a listing must not show: the connections banner, the urgent alert.
    @MainActor private func noBanners(_ app: XCUIApplication) {
        XCTAssertFalse(byId(app, "connections-banner").exists, "the connections banner is up")
        XCTAssertFalse(byId(app, "today-urgent").exists, "an urgent alert is pinned")
    }

    /// Wait out the spinners, a beat for fonts and animation, then shoot.
    @MainActor private func shoot(_ app: XCUIApplication, _ name: String, extra: TimeInterval = 0) {
        let spinners = app.activityIndicators
        let deadline = Date().addingTimeInterval(20)
        while spinners.count > 0 && Date() < deadline { pause(0.5) }
        XCTAssertEqual(spinners.count, 0, "still loading after 20s: \(name)")
        pause(1.5 + extra)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor private func pause(_ seconds: TimeInterval) {
        let done = expectation(description: "pause")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { done.fulfill() }
        wait(for: [done], timeout: seconds + 5)
    }
}
