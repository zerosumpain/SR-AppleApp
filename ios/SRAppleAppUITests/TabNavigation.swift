import XCTest

/// The tray along the foot of every place's first page: Family, Games, Chat
/// and Health as this person may open them, and More, which opens the hub
/// (`open-hub`). Home is not in the tray: it is the house (`open-home`) at the
/// top left of every other place's first page (John, 2026-10-27). The tray is
/// the app's own (`SRTray`), not the system tab bar, so tests find its
/// buttons as `tray-<place>`. Every test that opens a place by name goes
/// through here, so a place moving between the tray and the hub changes one
/// place, not every test.
extension XCUIApplication {
    /// The tray: on every place's first page and on More. Its being there is
    /// how a test knows the app is past Welcome and up.
    @MainActor var tray: XCUIElement { descendants(matching: .any)["sr-tray"].firstMatch }

    /// Home's first page.
    @MainActor var home: XCUIElement { descendants(matching: .any)["today-hero"].firstMatch }

    /// A place's button in the tray, by its label: "Family", "Games", "Chat",
    /// "Health" — or "More".
    @MainActor func trayButton(_ name: String) -> XCUIElement {
        name == "More" ? buttons["open-hub"].firstMatch : buttons["tray-\(name.lowercased())"].firstMatch
    }

    /// Back out of pushed pages until a first page — with the tray — shows.
    /// Pushed pages have no tray, as a game room or a thread never had a bar.
    @MainActor
    func backToFirstPage(limit: Int = 5) {
        for _ in 0..<limit where !tray.exists {
            let back = navigationBars.buttons.element(boundBy: 0)
            guard back.exists, back.identifier != "open-home" else { return }
            back.tap()
            _ = tray.waitForExistence(timeout: 2)
        }
    }

    /// Opens a place by its label: Home by its house, a place in the tray by
    /// its button, else its card in the hub. "More" opens the hub itself.
    /// Returns false when no route finds it.
    @MainActor @discardableResult
    func openTab(_ name: String, timeout: TimeInterval = 20) -> Bool {
        if name == "More" { return openHub(timeout: timeout) }
        if name == "Home" { return openHome(timeout: timeout) }
        let direct = trayButton(name)
        if direct.waitForExistence(timeout: 2) {
            direct.tap()
            return true
        }
        backToFirstPage()
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

    /// Home, by the house at the top left of a place's first page.
    @MainActor @discardableResult
    func openHome(timeout: TimeInterval = 20) -> Bool {
        if home.exists { return true }
        backToFirstPage()
        if home.exists { return true }
        let house = buttons["open-home"].firstMatch
        guard house.waitForExistence(timeout: timeout) else { return home.exists }
        house.tap()
        return home.waitForExistence(timeout: 10)
    }

    /// Opens the hub — More, in the tray. A tap while the app is still
    /// settling from launch can be lost: the hub not appearing is the sign,
    /// and tapping again is the fix.
    @MainActor @discardableResult
    func openHub(timeout: TimeInterval = 20) -> Bool {
        let button = buttons["open-hub"].firstMatch
        let hub = descendants(matching: .any)["more-screen"].firstMatch
        if hub.exists { return true }
        if !button.exists { backToFirstPage() }
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
