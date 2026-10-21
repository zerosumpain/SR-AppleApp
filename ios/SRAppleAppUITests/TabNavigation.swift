import XCTest

/// Five places at most on the bar, the same for everyone: Home, Family,
/// Games, Chat, Health. News, Flows, Daydream, Wildmind, the family boards and
/// Settings are in the hub — the ⊞ (`open-hub`) at the top left of every tab's
/// first page. Every test that opens a place by name goes through here, so a
/// place moving between the bar and the hub changes one place, not every test.
extension XCUIApplication {
    /// Opens a place by its label: its tab when it has one, else its card in
    /// the hub. "More" opens the hub itself. Returns false when neither route
    /// finds it.
    @MainActor @discardableResult
    func openTab(_ name: String, timeout: TimeInterval = 20) -> Bool {
        if name == "More" { return openHub(timeout: timeout) }
        let direct = tabBars.buttons[name]
        if direct.waitForExistence(timeout: 2) {
            direct.tap()
            return true
        }
        // A swipe up the page folds the iOS 26 bar down to the selected tab
        // alone (`tabBarMinimizeBehavior(.onScrollDown)`), so the tab may be
        // there and folded away. A swipe back down opens it out again.
        swipeDown()
        if direct.waitForExistence(timeout: 2) {
            direct.tap()
            return true
        }
        guard openHub(timeout: timeout) else { return false }
        // The hub: one card per place, `more-<place>`.
        let card = descendants(matching: .any)["more-\(name.lowercased())"].firstMatch
        guard card.waitForExistence(timeout: 10) else { return false }
        // The connections banner slides in above the hub when the demo's
        // store loads, and moves every card down as it does. A tap aimed
        // while that happens lands on whatever slid into the card's old place
        // — the banner's own details button, which opens a sheet over
        // everything. Wait for the card to be still, then tap: `tap()` scrolls
        // a card below the fold into view itself.
        card.waitUntilStill()
        card.tap()
        return true
    }

    /// Opens the hub from the page on screen — the ⊞ at the top left of a
    /// tab's first page. A tap while the app is still settling from launch
    /// can be lost: the hub not appearing is the sign, and tapping again is
    /// the fix.
    @MainActor @discardableResult
    func openHub(timeout: TimeInterval = 20) -> Bool {
        let button = buttons["open-hub"].firstMatch
        let hub = descendants(matching: .any)["more-screen"].firstMatch
        // Already on it: a test's "back" from a tab's first page lands on the
        // ⊞ (the bar's first button there) and opens the hub itself.
        if hub.exists { return true }
        guard button.waitForExistence(timeout: timeout) else { return hub.exists }
        for attempt in 0..<3 {
            if button.exists && button.isHittable { button.tap() }
            if hub.waitForExistence(timeout: attempt == 0 ? 10 : 5) { return true }
        }
        return false
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
    /// Opens Settings: the row at the foot of the hub, for everyone.
    @MainActor @discardableResult
    func openSettings(timeout: TimeInterval = 10) -> Bool {
        guard openHub(timeout: max(timeout, 20)) else { return false }
        // Settings is the hub's last row, below the fold on a phone.
        let row = buttons["open-settings"]
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

extension XCUIApplication {
    /// The Family tab's top: "Orbit" or "Map". Remembered on the phone, so a
    /// test that switches to the map switches back when it is done.
    @MainActor @discardableResult
    func selectFamilyTop(_ name: String, timeout: TimeInterval = 10) -> Bool {
        let segment = segmentedControls.buttons[name]
        guard segment.waitForExistence(timeout: timeout) else { return false }
        if !segment.isSelected { segment.tap() }
        return true
    }
}
