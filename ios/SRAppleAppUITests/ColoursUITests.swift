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
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 20))
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
        XCTAssertTrue(app.tabBars.buttons["Home"].isSelected, "the redraw lost the reader's tab")
    }

    /// Arrange Home's Colours row hands over to the Colours sheet.
    @MainActor func testArrangeHomeOpensColours() {
        let app = XCUIApplication()
        app.launchArguments = ["-SRDemo"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 20))
        let any = app.descendants(matching: .any)
        let open = any["home-customise"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        for _ in 0..<12 where !open.isHittable { app.swipeUp() }
        open.tap()
        let row = any["settings-home-colours"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no Colours row on Arrange Home")
        row.tap()
        XCTAssertTrue(any["colours-preset-sunset"].firstMatch.waitForExistence(timeout: 10), "Arrange Home did not open Colours")
    }
}
