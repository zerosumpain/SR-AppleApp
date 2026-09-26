import XCTest

/// Seven tabs for the owner, and an iPhone shows five: past the fourth (Games,
/// News, Flows) they sit under iOS's "More". A member with Family and Games
/// has four and no More. Every test that opens a tab by name goes through here,
/// so a tab moving under More — or back — changes one place, not every test.
extension XCUIApplication {
    /// Opens a tab by its label, through More when it is not on the bar.
    /// Returns false when neither route finds it.
    @MainActor @discardableResult
    func openTab(_ name: String, timeout: TimeInterval = 20) -> Bool {
        let direct = tabBars.buttons[name]
        if direct.waitForExistence(timeout: 2) {
            direct.tap()
            return true
        }
        let more = tabBars.buttons["More"]
        guard more.waitForExistence(timeout: timeout) else { return false }
        more.tap()
        let row = cells.staticTexts[name].firstMatch
        guard row.waitForExistence(timeout: 10) else { return false }
        row.tap()
        return true
    }
}
