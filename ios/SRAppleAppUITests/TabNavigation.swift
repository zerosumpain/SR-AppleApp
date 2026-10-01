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
        // The app's own More hub: one card per place, `more-<tab>`.
        let card = descendants(matching: .any)["more-\(name.lowercased())"].firstMatch
        // A tap on the bar while the app is still settling from launch can be
        // lost: the hub not appearing is the sign, and tapping again is the
        // fix. Re-tapping a selected tab only pops it to its root, which is
        // where the hub is anyway.
        for attempt in 0..<3 {
            more.tap()
            if card.waitForExistence(timeout: attempt == 0 ? 10 : 5) { break }
        }
        guard card.exists else { return false }
        // The connections banner slides in above the hub when the demo's
        // store loads, and moves every card down as it does. A tap aimed
        // while that happens lands on whatever slid into the card's old place
        // — the banner's own details button, which opens a sheet over
        // everything. Wait for the card to be still, and on screen.
        card.waitUntilStill()
        for _ in 0..<4 where !card.isHittable {
            swipeUp()
            card.waitUntilStill()
        }
        guard card.isHittable else { return false }
        card.tap()
        return true
    }
}

extension XCUIElement {
    /// Waits until this element stops moving — a banner or a sheet arriving
    /// above it shifts it — so a tap lands where the element IS rather than
    /// where it was. Returns false if it was still moving at the timeout.
    @MainActor @discardableResult
    func waitUntilStill(timeout: TimeInterval = 4) -> Bool {
        guard exists else { return false }
        var last = frame
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.4)
            guard exists else { return false }
            let now = frame
            if now == last { return true }
            last = now
        }
        return false
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
    /// way an invited person does: "I have a pairing code", then — with no
    /// code to type — "Continue without a code".
    @MainActor
    func launchPastWelcome() {
        launchArguments += ["-SRFreshInstall"]
        launch()
        let haveCode = buttons["welcome-have-code"]
        if haveCode.waitForExistence(timeout: 20) { haveCode.tap() }
        let skip = buttons["code-skip"]
        if skip.waitForExistence(timeout: 10) { skip.tap() }
    }
}
