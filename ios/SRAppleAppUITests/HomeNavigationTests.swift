import XCTest

/// The way round the app since 2026-10-27: Home is the house at the top left
/// of every place's first page, the tray along the foot holds the places and
/// More, and Home's tiles are widgets the reader arranges on Home itself.
final class HomeNavigationTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-SRDemo"]
        app.launch()
        XCTAssertTrue(app.tray.waitForExistence(timeout: 20), "no tray")
        return app
    }

    /// Home has no button in the tray; every other place's first page has a
    /// house that goes back to it.
    @MainActor func testTheHouseGoesHome() {
        let app = launch()
        XCTAssertTrue(app.home.waitForExistence(timeout: 10), "the app did not open on Home")
        XCTAssertFalse(app.buttons["tray-today"].exists, "Home is in the tray")
        XCTAssertFalse(app.buttons["open-home"].exists, "Home shows a house that goes to itself")

        app.trayButton("Health").tap()
        let house = app.buttons["open-home"].firstMatch
        XCTAssertTrue(house.waitForExistence(timeout: 10), "no house on Health")
        XCTAssertFalse(app.home.exists)
        house.tap()
        XCTAssertTrue(app.home.waitForExistence(timeout: 10), "the house did not go Home")
    }

    /// More, in the tray, opens the More apps page — with the tray still
    /// along its foot and More lit.
    @MainActor func testMoreIsInTheTray() {
        let app = launch()
        XCTAssertTrue(app.openHub(), "More did not open the More apps page")
        XCTAssertTrue(app.tray.exists, "no tray on More")
        XCTAssertTrue(app.trayButton("More").isSelected, "More is not lit on More")
        // Every door the same size, and square.
        let first = app.descendants(matching: .any)["more-travel"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertEqual(first.frame.width, first.frame.height, accuracy: 2, "a More door is not square")
    }

    /// The bat phone is a tile of its own on a family phone's Home, and no
    /// longer in the header.
    @MainActor func testTheBatPhoneHasATile() {
        let app = launch()
        let tile = app.descendants(matching: .any)["home-bat-phone"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 15), "no bat phone tile")
        let hero = app.descendants(matching: .any)["today-hero"].firstMatch
        XCTAssertFalse(hero.buttons["bat-phone"].exists, "the bat phone is still in the header")
    }

    /// Arrange happens on Home: − on the tiles, sizes, and Done.
    @MainActor func testArrangeOnHome() {
        let app = launch()
        let arrange = app.descendants(matching: .any)["home-arrange"].firstMatch
        XCTAssertTrue(arrange.waitForExistence(timeout: 15))
        for _ in 0..<12 where !arrange.isHittable { app.swipeUp() }
        arrange.tap()
        let done = app.descendants(matching: .any)["home-arrange-done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10), "Arrange did not start")
        XCTAssertTrue(app.descendants(matching: .any)["home-arrange-banner"].firstMatch.exists)
        // The bat phone cannot come off; msg family can.
        XCTAssertFalse(app.buttons["home-remove-batPhone"].exists, "the bat phone can be taken off")
        XCTAssertTrue(app.buttons["home-remove-messages"].exists, "msg family cannot be taken off")
        for _ in 0..<12 where !done.isHittable { app.swipeUp() }
        done.tap()
        XCTAssertTrue(arrange.waitForExistence(timeout: 10), "Done did not end Arrange")
    }
}
