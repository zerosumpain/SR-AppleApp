import XCTest

/// Seven places for the owner, and an iPhone shows five: Games, News and Flows
/// sit behind the app's own "More" hub. A member with Family and Games
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
        // The app's own More hub: one card per place, `more-<tab>`.
        let card = descendants(matching: .any)["more-\(name.lowercased())"].firstMatch
        guard card.waitForExistence(timeout: 10) else { return false }
        card.tap()
        return true
    }
}
