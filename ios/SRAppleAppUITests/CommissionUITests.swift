import XCTest

final class CommissionUITests: XCTestCase {
    @MainActor func testOwnerReviewsApprovesAndSeesTheEvidenceReport() {
        let app = XCUIApplication()
        app.launchArguments = ["-SRDemo", "-SRFreshInstall", "-SRCommissionUITest"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 20))
        let tile = app.descendants(matching: .any)["today-daydream"].firstMatch
        for _ in 0..<8 {
            if tile.exists && tile.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(tile.isHittable)
        tile.tap()
        let proposal = app.buttons.containing(.staticText, identifier: "Synthetic evidence refresh").firstMatch
        XCTAssertTrue(proposal.waitForExistence(timeout: 15))
        proposal.tap()
        let approve = app.buttons["Approve evidence refresh"]
        for _ in 0..<12 {
            if approve.exists && approve.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(approve.isHittable)
        approve.tap()
        let report = app.staticTexts["The synthetic query is refreshed; its claim remains unverified."]
        XCTAssertTrue(report.waitForExistence(timeout: 15))
        XCTAssertFalse(approve.exists)
    }
}
