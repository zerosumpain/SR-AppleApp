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

extension XCUIApplication {
    /// Opens Settings wherever this person keeps it: the cog on Today when the
    /// bar has no More (an unknown phone, a member with four places), else
    /// the Settings row at the foot of the More hub.
    @MainActor @discardableResult
    func openSettings(timeout: TimeInterval = 10) -> Bool {
        let cog = buttons["open-settings"]
        let more = tabBars.buttons["More"]
        // Whichever turns up first: the cog on Today, or the More tab.
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline && !(cog.exists && cog.isHittable) && !more.exists {
            _ = cog.waitForExistence(timeout: 0.5)
        }
        if cog.exists && cog.isHittable {
            cog.tap()
            return true
        }
        guard more.exists else { return false }
        more.tap()
        // Settings is the hub's last row, below the fold on a phone.
        let row = buttons["open-settings"]
        guard descendants(matching: .any)["more-screen"].firstMatch.waitForExistence(timeout: timeout) else { return false }
        for _ in 0..<8 where !(row.exists && row.isHittable) { swipeUp() }
        guard row.exists && row.isHittable else { return false }
        row.tap()
        return true
    }
}

extension XCUIApplication {
    /// A fresh install opens on Welcome now. Tests of the app behind it go the
    /// way an invited person does: "I have a pairing code".
    @MainActor
    func launchPastWelcome() {
        launchArguments += ["-SRFreshInstall"]
        launch()
        let skip = buttons["welcome-have-code"]
        if skip.waitForExistence(timeout: 20) { skip.tap() }
    }
}
