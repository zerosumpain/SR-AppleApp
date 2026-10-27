import XCTest

/// Colours: picking a palette redraws the app behind the sheet, and the
/// sheet — outside what redraws — stays open while it does.
///
/// The demo always starts on Prism (`SRPaletteChoice.stored`), so whatever
/// this leaves chosen does not follow the next test.
final class ColoursUITests: XCTestCase {

    @MainActor func testAPaletteRedrawsHomeBehindTheSheet() {
        let app = XCUIApplication()
        app.launchArguments = ["-SRDemo"]
        app.launch()
        XCTAssertTrue(app.tray.waitForExistence(timeout: 20))
        let any = app.descendants(matching: .any)

        let open = any["home-colours"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 15), "no Colours button on Home")
        for _ in 0..<12 where !open.isHittable { app.swipeUp() }
        open.tap()

        let prism = any["colours-preset-prism"].firstMatch
        let ocean = any["colours-preset-ocean"].firstMatch
        XCTAssertTrue(ocean.waitForExistence(timeout: 10), "the Colours sheet did not open")
        XCTAssertTrue(prism.isSelected, "a demo starts on Prism")
        ocean.tap()

        // The tabs rebuild a moment later; the sheet must survive it.
        let picked = NSPredicate(format: "isSelected == true")
        expectation(for: picked, evaluatedWith: ocean)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(any["colours-sheet"].firstMatch.exists, "the sheet closed when the app redrew")
        XCTAssertTrue(any["colours-hue-family"].firstMatch.exists, "no colour wheel for the family")

        any["colours-done"].firstMatch.tap()
        XCTAssertTrue(any["today-hero"].firstMatch.waitForExistence(timeout: 10), "Home did not come back after the palette changed")
        XCTAssertTrue(app.home.exists, "the redraw lost the reader's place")
    }

    /// Settings' own Colours row: Settings is a sheet, and a sheet sits
    /// outside the tabs' environment — this tap trapped on a missing Router
    /// (build 121, 2026-10-20) while the Home path above was fine.
    @MainActor func testSettingsOpensColours() {
        let app = XCUIApplication()
        app.launchArguments = ["-SRDemo"]
        app.launch()
        XCTAssertTrue(app.tray.waitForExistence(timeout: 20))
        XCTAssertTrue(app.openSettings(), "no way into Settings")
        let any = app.descendants(matching: .any)
        let row = any["settings-colours"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no Colours row in Settings")
        for _ in 0..<12 where !row.isHittable { app.swipeUp() }
        row.tap()
        let ocean = any["colours-preset-ocean"].firstMatch
        XCTAssertTrue(ocean.waitForExistence(timeout: 10), "Settings did not open Colours")
        ocean.tap()
        expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: ocean)
        waitForExpectations(timeout: 5)
        any["colours-done"].firstMatch.tap()
        XCTAssertTrue(app.tray.waitForExistence(timeout: 10), "the app did not survive Settings → Colours")
    }

    /// Arrange Home's Colours row hands over to the Colours sheet.
    @MainActor func testArrangeHomeOpensColours() {
        let app = XCUIApplication()
        app.launchArguments = ["-SRDemo"]
        app.launch()
        XCTAssertTrue(app.tray.waitForExistence(timeout: 20))
        let any = app.descendants(matching: .any)
        // Arrange happens on Home itself; its List is the Settings → Home list.
        let arrange = any["home-arrange"].firstMatch
        XCTAssertTrue(arrange.waitForExistence(timeout: 15))
        for _ in 0..<12 where !arrange.isHittable { app.swipeUp() }
        arrange.tap()
        let open = any["home-customise"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 10), "Arrange has no List")
        for _ in 0..<12 where !open.isHittable { app.swipeUp() }
        open.tap()
        let row = any["settings-home-colours"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no Colours row on Arrange Home")
        row.tap()
        XCTAssertTrue(any["colours-preset-sunset"].firstMatch.waitForExistence(timeout: 10), "Arrange Home did not open Colours")
    }
}
