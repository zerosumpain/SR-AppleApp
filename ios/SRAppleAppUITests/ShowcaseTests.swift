import XCTest

/// Every tab, FULL — for reviewing the look, not for asserting behaviour.
///
/// The onboarding tests only ever see the app unpaired, so every screenshot they
/// attach is an empty state. These launch with `-SRDemo`, which (in a DEBUG
/// build only) pretends the phone is paired and answers every site request from
/// canned, synthetic fixtures (`Site/DemoFixtures.swift`).
///
/// The screenshots are the point. One method per screen, so a lookup that fails
/// on one screen never costs the others, and element lookups are SOFT: a missing
/// element is recorded and the shot is still taken of whatever is on screen.
final class ShowcaseTests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    // MARK: - Today

    @MainActor func testShowcaseToday() {
        let app = launch()
        soft(app.tabBars.buttons["Today"].waitForExistence(timeout: 20), "no Today tab")
        settle(app, on: byId(app, "today-health"))
        attach(app, "Showcase — Today")

        app.swipeUp()
        settle(app)
        attach(app, "Showcase — Today, scrolled")
    }

    /// Daydream: the tile on Today, then the page in More it opens.
    @MainActor func testShowcaseTodayNoticed() {
        let app = launch()
        soft(app.tabBars.buttons["Today"].waitForExistence(timeout: 20), "no Today tab")
        let tile = byId(app, "today-daydream")
        settle(app, on: tile)
        guard scroll(app, to: tile) else { return soft(false, "no Daydream tile on Today") }
        tile.tap()
        settle(app, on: byId(app, "daydream-screen"))
        // The SECOND note's actions: scrolled to those, two whole cards are up.
        let last = app.buttons.matching(identifier: "noticed-useful").element(boundBy: 1)
        soft(scroll(app, to: last), "no notes on the Daydream page")
        settle(app)
        attach(app, "Showcase — Daydream")
    }

    // MARK: - Family

    /// The mini-map on Today, then the tab it opens: pins, today's lines, and
    /// the cards — a low battery in red, a day that is not yours left off.
    @MainActor func testShowcaseFamily() {
        let app = launch()
        soft(app.tabBars.buttons["Today"].waitForExistence(timeout: 20), "no Today tab")
        let mini = byId(app, "today-family")
        soft(mini.waitForExistence(timeout: 15), "no family map on Today")
        settle(app, seconds: 3)
        // The travel desk card under the map: Kit's quiet phone, then the next moves.
        soft(byId(app, "today-forecast").waitForExistence(timeout: 5), "no 'Family · next' card on Today")
        attach(app, "Showcase — Today, family map")

        if mini.exists && mini.isHittable {
            mini.tap()
        } else {
            openTab(app, "Family")
        }
        settle(app, on: byId(app, "family-person-sam"), seconds: 3)
        // The travel desk forecast: Sam's next move under the row, Kit's quiet phone above the list.
        soft(byId(app, "family-next-sam").waitForExistence(timeout: 5), "no forecast line for Sam")
        soft(byId(app, "family-watch").exists, "no 'what looks off' card")
        attach(app, "Showcase — Family")

        let sam = byId(app, "family-person-sam")
        if sam.exists && sam.isHittable { sam.tap() }
        settle(app, seconds: 3)
        soft(byId(app, "family-person-next").waitForExistence(timeout: 5), "no next move on Sam's page")
        attach(app, "Showcase — Family, one person")

        app.swipeUp()
        settle(app)
        attach(app, "Showcase — Family, scrolled")
    }

    // MARK: - Family steps and tasks

    /// Both optional Today cards (switched on through the launch arguments,
    /// which `@AppStorage` reads), then the step board they open.
    @MainActor func testShowcaseFamilySteps() {
        let app = launch(["-today-card-steps", "YES", "-today-card-tasks", "YES"])
        soft(app.tabBars.buttons["Today"].waitForExistence(timeout: 20), "no Today tab")
        let card = byId(app, "today-steps")
        settle(app, on: card, seconds: 2)
        soft(scroll(app, to: card), "no steps card on Today")
        attach(app, "Showcase — Today, family steps and tasks")

        openTab(app, "Steps")
        settle(app, on: byId(app, "steps-hero"), seconds: 2)
        attach(app, "Showcase — Steps")

        app.swipeUp()
        settle(app)
        attach(app, "Showcase — Steps, scrolled")
    }

    /// The task list: Open (waiting for a parent, to do), Completed, Owed,
    /// and the add sheet with a reward.
    @MainActor func testShowcaseFamilyTasks() {
        let app = launch()
        soft(app.tabBars.buttons["Today"].waitForExistence(timeout: 20), "no Today tab")
        openTab(app, "Tasks")
        settle(app, on: byId(app, "task-row-t_dishes"), seconds: 2)
        attach(app, "Showcase — Tasks")

        app.swipeUp()
        settle(app)
        attach(app, "Showcase — Tasks, scrolled")
        app.swipeDown()

        let completed = app.segmentedControls.buttons["Completed"]
        if completed.waitForExistence(timeout: 5) {
            completed.tap()
            settle(app, on: byId(app, "task-row-t_hoover"))
            attach(app, "Showcase — Tasks, completed")
        } else {
            soft(false, "no Completed segment")
        }

        let owed = app.segmentedControls.buttons["Owed"]
        if owed.waitForExistence(timeout: 5) {
            owed.tap()
            settle(app, on: byId(app, "tasks-owed-total"))
            attach(app, "Showcase — Tasks, owed")
        } else {
            soft(false, "no Owed segment")
        }

        let add = byId(app, "tasks-add")
        guard add.waitForExistence(timeout: 5) else { return soft(false, "no add button") }
        add.tap()
        let title = byId(app, "task-title")
        settle(app, on: title)
        if title.exists {
            title.tap()
            title.typeText("Take the recycling out")
        }
        let reward = app.switches["task-reward"].firstMatch
        if reward.waitForExistence(timeout: 5) {
            // The switch itself, not the middle of the row.
            reward.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        } else {
            soft(false, "no reward switch")
        }
        let pounds = byId(app, "task-pounds")
        if pounds.waitForExistence(timeout: 5) {
            pounds.tap()
            pounds.typeText("2.50")
        }
        settle(app)
        attach(app, "Showcase — Tasks, new task")
    }

    /// The Home Screen widgets, drawn in the app (Settings → Today → Widget
    /// previews, demo only): a UI test cannot reach the Home Screen.
    @MainActor func testShowcaseFamilyWidgets() {
        let app = launch()
        soft(app.tabBars.buttons["Today"].waitForExistence(timeout: 20), "no Today tab")
        guard app.openSettings() else { return soft(false, "no way into Settings") }
        let link = byId(app, "settings-widget-previews")
        guard scroll(app, to: link) else { return soft(false, "no widget previews row") }
        link.tap()
        settle(app, on: byId(app, "widget-gallery"), seconds: 2)
        attach(app, "Showcase — Widgets")
    }

    // MARK: - Chat

    @MainActor func testShowcaseChatList() {
        let app = launch()
        openTab(app, "Chat")
        settle(app, on: thread(app, "demo-thread-training"))
        attach(app, "Showcase — Chat threads")
    }

    @MainActor func testShowcaseChatThread() {
        let app = launch()
        openTab(app, "Chat")
        let first = thread(app, "demo-thread-training")
        if first.waitForExistence(timeout: 15) {
            first.tap()
        } else {
            // The redesign may rename the cell; fall back to the thread's title.
            let byTitle = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "week 6 review")
            ).firstMatch
            soft(byTitle.waitForExistence(timeout: 5), "no thread cell to open")
            if byTitle.exists { byTitle.tap() }
        }
        settle(app, on: app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "42.1 km")
        ).firstMatch)
        attach(app, "Showcase — Chat thread")

        app.swipeUp()
        settle(app)
        attach(app, "Showcase — Chat thread, scrolled")
    }

    // MARK: - News

    @MainActor func testShowcaseNewsList() {
        let app = launch()
        openTab(app, "News")
        settle(app, on: newsRow(app, "hn:41200001"))
        attach(app, "Showcase — News")
    }

    @MainActor func testShowcaseNewsStory() {
        let app = launch()
        openTab(app, "News")
        let row = newsRow(app, "hn:41200001")
        if row.waitForExistence(timeout: 15) {
            row.tap()
        } else {
            let byTitle = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "SQLite extension")
            ).firstMatch
            soft(byTitle.waitForExistence(timeout: 5), "no story row to open")
            if byTitle.exists { byTitle.tap() }
        }
        settle(app, on: app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "demonstration text")
        ).firstMatch)
        attach(app, "Showcase — News story")
    }

    // MARK: - Health

    @MainActor func testShowcaseHealth() {
        let app = launch()
        openTab(app, "Health")
        settle(app, on: app.staticTexts["Primed"])
        attach(app, "Showcase — Health")

        app.swipeUp()
        settle(app)
        attach(app, "Showcase — Health, scrolled")

        app.swipeUp()
        settle(app)
        attach(app, "Showcase — Health, scrolled further")
    }

    /// The health notes, under "The read".
    @MainActor func testShowcaseHealthNoticed() {
        let app = launch()
        openTab(app, "Health")
        settle(app, on: app.staticTexts["Primed"])
        let useful = app.buttons.matching(identifier: "noticed-useful").firstMatch
        soft(scroll(app, to: useful), "no Noticed section on Health")
        settle(app)
        attach(app, "Showcase — Health, noticed")
    }

    @MainActor func testShowcaseActivityDetail() {
        let app = launch()
        openTab(app, "Health")

        let all = app.buttons["health-all-activities"]
        if scroll(app, to: all) {
            all.tap()
            settle(app)
            attach(app, "Showcase — All activities")
        } else {
            soft(false, "no route to the activities list; trying a recent row")
        }

        let run = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Morning park loop")
        ).firstMatch
        let runText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Morning park loop")
        ).firstMatch
        if run.waitForExistence(timeout: 10) {
            run.tap()
        } else if runText.waitForExistence(timeout: 5) {
            runText.tap()
        } else {
            soft(false, "no activity row to open")
        }
        // A map takes a moment to draw its tiles.
        settle(app, seconds: 4)
        attach(app, "Showcase — Activity detail")

        app.swipeUp()
        settle(app)
        attach(app, "Showcase — Activity detail, scrolled")

        app.swipeUp()
        settle(app)
        attach(app, "Showcase — Activity detail, scrolled further")
    }

    /// An outing the SR app caught by itself: the origin note under the hero is
    /// the thing to look at.
    @MainActor func testShowcaseCapturedWalk() {
        let app = launch()
        openTab(app, "Health")

        let all = app.buttons["health-all-activities"]
        if scroll(app, to: all) {
            all.tap()
            settle(app)
        } else {
            soft(false, "no route to the activities list; trying a recent row")
        }

        let walk = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Captured walk")
        ).firstMatch
        let walkText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Captured walk")
        ).firstMatch
        if walk.waitForExistence(timeout: 10) {
            walk.tap()
        } else if walkText.waitForExistence(timeout: 5) {
            walkText.tap()
        } else {
            soft(false, "no captured walk to open")
        }
        settle(app, seconds: 4)
        attach(app, "Showcase — Captured walk")
    }

    @MainActor func testShowcaseSegments() {
        let app = launch()
        openTab(app, "Health")
        let segments = app.buttons["health-segments"]
        guard scroll(app, to: segments) else {
            soft(false, "no route to the segments list")
            attach(app, "Showcase — Segments (not reached)")
            return
        }
        segments.tap()
        settle(app)
        attach(app, "Showcase — Segments")
    }

    // MARK: - Flows

    @MainActor func testShowcaseFlows() {
        let app = launch()
        openTab(app, "Flows")
        let brief = byId(app, "flow-row-morning-brief")
        settle(app, on: brief)
        attach(app, "Showcase — Flows")

        if brief.exists {
            brief.tap()
        } else {
            let byTitle = app.staticTexts["Morning brief"]
            soft(byTitle.waitForExistence(timeout: 5), "no workflow row to open")
            if byTitle.exists { byTitle.tap() }
        }
        settle(app, on: app.staticTexts["Anything before nine?"])
        attach(app, "Showcase — Flow detail")

        app.swipeUp()
        settle(app)
        attach(app, "Showcase — Flow detail, scrolled")

        let step = byId(app, "flow-step-brief")
        if scroll(app, to: step) {
            step.tap()
            settle(app, on: app.staticTexts["Instructions"])
            attach(app, "Showcase — Flow step editor")
        } else {
            soft(false, "no step row to open")
        }
    }

    @MainActor func testShowcaseFlowAttentionAndRun() {
        let app = launch()
        openTab(app, "Flows")
        let triage = byId(app, "flow-row-inbox-triage")
        if triage.waitForExistence(timeout: 15) {
            triage.tap()
        } else {
            soft(false, "no inbox-triage row")
        }
        settle(app, on: byId(app, "flow-fix-demo-fix-1"))
        attach(app, "Showcase — Flow needing attention")

        let run = byId(app, "flow-run-demo-run-inbox-1")
        if scroll(app, to: run) {
            run.tap()
            settle(app, on: byId(app, "flow-run-summary"))
            attach(app, "Showcase — Flow run")
        } else {
            soft(false, "no run row to open")
        }
    }

    /// A Describe-it build that stopped to ask. The row says so in the list;
    /// the detail leads with the question card.
    @MainActor func testShowcaseFlowQuestion() {
        let app = launch()
        openTab(app, "Flows")
        let row = byId(app, "flow-row-hourly-jokes")
        settle(app, on: row)
        attach(app, "Showcase — Flows with a question")
        if row.exists {
            row.tap()
        } else {
            soft(false, "no hourly-jokes row")
        }
        let card = byId(app, "flow-question")
        settle(app, on: card)
        soft(app.staticTexts["What time should the jokes stop?"].exists, "the question text did not draw")
        attach(app, "Showcase — Flow question")

        let field = byId(app, "flow-question-field")
        if field.waitForExistence(timeout: 5) {
            field.tap()
            field.typeText("At ten tonight, and not at all on Sundays")
            settle(app)
            soft(byId(app, "flow-question-send").isEnabled, "Send stayed disabled with an answer typed")
            attach(app, "Showcase — Flow question, answer typed")
        } else {
            soft(false, "no answer field")
        }
    }

    // MARK: - A connection needs you

    /// The demo has one lapsed Gmail, so the banner sits at the top of every
    /// tab. Today and Flows are photographed on purpose: one scrolls a page,
    /// the other a searchable list, and the inline title must still paint
    /// under the banner in both.
    @MainActor func testShowcaseConnectionsBanner() {
        let app = launch()
        soft(app.tabBars.buttons["Today"].waitForExistence(timeout: 20), "no Today tab")
        let banner = byId(app, "connections-banner")
        settle(app, on: banner)
        attach(app, "Showcase — Connection banner on Today")

        openTab(app, "Flows")
        settle(app, on: byId(app, "flow-row-morning-brief"))
        soft(banner.exists, "no banner on Flows")
        attach(app, "Showcase — Connection banner on Flows")

        let details = byId(app, "connections-banner-details")
        if details.waitForExistence(timeout: 5) {
            details.tap()
            settle(app, on: byId(app, "connection-gmail:2"))
            attach(app, "Showcase — Connections needing you")
            let done = byId(app, "connections-sheet-done")
            if done.waitForExistence(timeout: 5) { done.tap() }
            settle(app)
        } else {
            soft(false, "no banner details button")
        }

        let dismiss = byId(app, "connections-banner-dismiss")
        if dismiss.waitForExistence(timeout: 5) {
            dismiss.tap()
            settle(app)
            soft(!byId(app, "connections-banner").exists, "the banner did not go when dismissed")
            attach(app, "Showcase — Connection banner, dismissed")
        } else {
            soft(false, "no dismiss button")
        }
    }

    // MARK: - Settings

    @MainActor func testShowcaseSettings() {
        let app = launch()
        soft(app.tabBars.buttons["Today"].waitForExistence(timeout: 20), "no Today tab")
        soft(app.openSettings(), "no way into Settings from Today or More")
        settle(app)
        attach(app, "Showcase — Settings")

        let notifications = app.buttons["settings-notifications"]
        if notifications.waitForExistence(timeout: 5) {
            notifications.tap()
            settle(app)
            attach(app, "Showcase — Settings, where alerts go")
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists { back.tap() }
            settle(app)
        }

        let connections = app.buttons["settings-connections"]
        if connections.waitForExistence(timeout: 5) {
            connections.tap()
            settle(app, on: byId(app, "connection-gmail:2"))
            attach(app, "Showcase — Settings, site connections that need you")
        } else {
            soft(false, "no Connections row in Settings")
        }
    }

    // MARK: - Games

    /// The Games tab — one invitation from Sam, one room of John's — then the
    /// new-game sheet, then the room's lobby.
    @MainActor func testShowcaseGames() {
        let app = launch()
        openTab(app, "Games")
        settle(app, on: byId(app, "games-invite-g_demo_invite"))
        soft(byId(app, "games-delivery-note").exists, "no line saying invites need the app open")
        attach(app, "Showcase — Games")

        let new = byId(app, "games-new")
        if scroll(app, to: new) {
            new.tap()
            settle(app, on: byId(app, "games-difficulty-medium"))
            attach(app, "Showcase — Games, new Tap Duel")
            let cancel = byId(app, "games-new-cancel")
            if cancel.waitForExistence(timeout: 5) { cancel.tap() }
            settle(app)
        } else {
            soft(false, "no Tap Duel card")
        }

        let room = byId(app, "games-room-g_demo_lobby")
        if scroll(app, to: room) {
            room.tap()
            settle(app, on: byId(app, "tapduel-start"), seconds: 2)
            soft(byId(app, "tapduel-player-p_sam").exists, "Sam is not in the lobby")
            attach(app, "Showcase — Tap Duel lobby")
        } else {
            soft(false, "no room to resume")
        }
    }

    /// Wordle Race: the new-game sheet opened from its card (game picked,
    /// difficulty lines from the Wordle table), then Sam's race half played —
    /// my three rows and the keyboard, Sam and Robin as colours only.
    @MainActor func testShowcaseWordleRace() {
        let app = launch()
        openTab(app, "Games")
        settle(app, on: byId(app, "games-invite-g_demo_invite"))

        let card = byId(app, "games-new-wordle-race")
        if scroll(app, to: card) {
            card.tap()
            settle(app, on: byId(app, "games-game-wordle-race"))
            soft(byId(app, "games-game-tap-duel").exists, "the sheet cannot switch game")
            soft(byId(app, "games-difficulty-hard").exists, "no difficulty choices")
            attach(app, "Showcase — Games, new Wordle Race")
            let cancel = byId(app, "games-new-cancel")
            if cancel.waitForExistence(timeout: 5) { cancel.tap() }
            settle(app)
        } else {
            soft(false, "no Wordle Race card")
        }

        let room = byId(app, "games-room-g_demo_wordle")
        if scroll(app, to: room) {
            room.tap()
            settle(app, on: byId(app, "wordle-keyboard"), seconds: 2)
            soft(byId(app, "wordle-other-p_sam").exists, "Sam is not in the strip")
            soft(byId(app, "wordle-other-p_robin").exists, "Robin is not in the strip")
            soft(byId(app, "wordle-key-q").exists, "no Q key")
            soft(byId(app, "wordle-enter").exists, "no Enter key")
            soft(byId(app, "wordle-delete").exists, "no Delete key")
            soft(byId(app, "wordle-timer").exists, "no time limit on screen")
            attach(app, "Showcase — Wordle Race, playing")
        } else {
            soft(false, "no Wordle Race to resume")
        }
    }

    /// Quiz Night: John's quiz on an open question (four answers, the clock,
    /// who has answered), then Sam's on a reveal (the right answer ticked,
    /// everyone's picks, the explanation), then the new-game sheet with Quiz
    /// Night picked (topic, audience).
    @MainActor func testShowcaseQuizNight() {
        let app = launch()
        openTab(app, "Games")
        settle(app, on: byId(app, "games-invite-g_demo_invite"))
        soft(byId(app, "games-invite-about-g_demo_quiz_invite").exists, "the quiz invite does not say what it is about")

        let question = byId(app, "games-room-g_demo_quiz")
        if scroll(app, to: question) {
            question.tap()
            settle(app, on: byId(app, "quiz-option-0"), seconds: 2)
            soft(byId(app, "quiz-prompt").exists, "no question on screen")
            soft(byId(app, "quiz-option-3").exists, "fewer than four answers")
            soft(byId(app, "quiz-timer").exists, "no clock on the question")
            soft(byId(app, "quiz-answered").exists, "no row of who has answered")
            attach(app, "Showcase — Quiz Night, question")
            let answer = byId(app, "quiz-option-1")
            if answer.exists {
                answer.tap()
                settle(app, on: byId(app, "quiz-locked"))
                attach(app, "Showcase — Quiz Night, answer locked in")
            }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.waitForExistence(timeout: 5) { back.tap() }
            settle(app, on: byId(app, "games-screen"))
        } else {
            soft(false, "no quiz on a question to resume")
        }

        let reveal = byId(app, "games-room-g_demo_quiz_reveal")
        if scroll(app, to: reveal) {
            reveal.tap()
            settle(app, on: byId(app, "quiz-reveal"), seconds: 2)
            soft(byId(app, "quiz-explain").exists, "no explanation on the reveal")
            soft(byId(app, "quiz-picks").exists, "no picks on the reveal")
            soft(byId(app, "quiz-pick-p_sam").exists, "Sam's pick is missing")
            attach(app, "Showcase — Quiz Night, reveal")
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.waitForExistence(timeout: 5) { back.tap() }
            settle(app, on: byId(app, "games-screen"))
        } else {
            soft(false, "no quiz on a reveal to resume")
        }

        let card = byId(app, "games-new-quiz-night")
        if scroll(app, to: card) {
            card.tap()
            settle(app, on: byId(app, "games-game-quiz-night"))
            soft(byId(app, "games-quiz-topic").exists, "no topic field")
            soft(byId(app, "games-audience-kids").exists, "no audience choices")
            soft(byId(app, "games-difficulty-hard").exists, "no difficulty choices")
            attach(app, "Showcase — Games, new Quiz Night")
            let cancel = byId(app, "games-new-cancel")
            if cancel.waitForExistence(timeout: 5) { cancel.tap() }
        } else {
            soft(false, "no Quiz Night card")
        }
    }

    /// Anagram Blitz, Quick Maths Sprint and Sequence Memory, each mid-play:
    /// John's tiles and words, John's problem and keypad on a bonus streak, a
    /// Sequence Memory round waiting on John's taps with Robin out. (The
    /// new-game sheet is shot by the older games' tests; the suite is near its
    /// time limit.)
    @MainActor func testShowcaseAnagramSprintMemory() {
        let app = launch()
        openTab(app, "Games")
        settle(app, on: byId(app, "games-invite-g_demo_invite"))

        let anagram = byId(app, "games-room-g_demo_anagram")
        if scroll(app, to: anagram) {
            anagram.tap()
            settle(app, on: byId(app, "anagram-tiles"), seconds: 2)
            soft(byId(app, "anagram-tile-6").exists, "fewer than seven tiles")
            soft(byId(app, "anagram-word").exists, "no word row")
            soft(byId(app, "anagram-shuffle").exists, "no Shuffle")
            soft(byId(app, "anagram-enter").exists, "no Enter")
            soft(byId(app, "anagram-timer").exists, "no clock")
            soft(byId(app, "anagram-other-p_sam").exists, "Sam is not in the strip")
            soft(byId(app, "anagram-my-words").exists, "no list of my words")
            attach(app, "Showcase — Anagram Blitz, playing")
            back(app)
        } else {
            soft(false, "no Anagram Blitz to resume")
        }

        let sprint = byId(app, "games-room-g_demo_sprint")
        if scroll(app, to: sprint) {
            sprint.tap()
            settle(app, on: byId(app, "sprint-keypad"), seconds: 2)
            soft(byId(app, "sprint-problem").exists, "no problem on screen")
            soft(byId(app, "sprint-key-0").exists, "no 0 key")
            soft(byId(app, "sprint-key-minus").exists, "no minus key")
            soft(byId(app, "sprint-go").exists, "no Go key")
            soft(byId(app, "sprint-streak").exists, "no streak")
            soft(byId(app, "sprint-timer").exists, "no clock")
            soft(byId(app, "sprint-other-p_sam").exists, "Sam is not in the strip")
            attach(app, "Showcase — Quick Maths Sprint, playing")
            back(app)
        } else {
            soft(false, "no Quick Maths Sprint to resume")
        }

        let memory = byId(app, "games-room-g_demo_memory")
        if scroll(app, to: memory) {
            memory.tap()
            settle(app, on: byId(app, "memory-grid"), seconds: 2)
            soft(byId(app, "memory-tile-5").exists, "fewer than six tiles on medium")
            soft(byId(app, "memory-taps").exists, "no row of taps")
            soft(byId(app, "memory-undo").exists, "no Undo")
            soft(byId(app, "memory-player-p_robin").exists, "Robin is not in the players")
            attach(app, "Showcase — Sequence Memory, input")
            back(app)
        } else {
            soft(false, "no Sequence Memory to resume")
        }
    }

    // MARK: - A member

    /// A family member given Family and Games and nothing else. Chat, News and
    /// Flows are not disabled or explained — they are not there, and with
    /// four tabs nor is More: Games is on the bar.
    @MainActor func testShowcaseMemberWithoutChatOrNews() {
        let app = XCUIApplication()
        app.launchArguments = ["-SRDemo", "-SRDemoMember"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 20))
        for tab in ["Today", "Health", "Family", "Games"] {
            XCTAssertTrue(app.tabBars.buttons[tab].exists, "missing tab \(tab)")
        }
        for tab in ["Chat", "News", "Flows", "More"] {
            XCTAssertFalse(app.tabBars.buttons[tab].exists, "\(tab) is on a member's bar")
        }
        XCTAssertFalse(app.buttons["today-ask"].exists, "Ask jkai is on Today without chat")
        settle(app)
        attach(app, "Showcase — a member: Today, Health, Family, Games and nothing else")
    }

    // MARK: - Helpers

    @MainActor private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-SRDemo"] + extra
        app.launch()
        return app
    }

    /// Back out of a room to the Games tab.
    @MainActor private func back(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.waitForExistence(timeout: 5) { back.tap() }
        settle(app, on: byId(app, "games-screen"))
    }

    @MainActor private func openTab(_ app: XCUIApplication, _ name: String) {
        soft(app.openTab(name), "no \(name) tab")
    }

    @MainActor private func thread(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)["thread-\(id)"].firstMatch
    }

    @MainActor private func byId(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    @MainActor private func newsRow(_ app: XCUIApplication, _ key: String) -> XCUIElement {
        app.descendants(matching: .any)["news-row-\(key)"].firstMatch
    }

    /// Wait for a landmark if there is one, then a beat for animations and
    /// fonts. Never fails the test — the shot is taken regardless.
    @MainActor private func settle(_ app: XCUIApplication, on landmark: XCUIElement? = nil, seconds: TimeInterval = 1.5) {
        if let landmark {
            soft(landmark.waitForExistence(timeout: 15), "a landmark did not appear")
        }
        let pause = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { pause.fulfill() }
        wait(for: [pause], timeout: seconds + 5)
    }

    /// Record a miss without stopping the method.
    private func soft(_ condition: Bool, _ note: String) {
        guard !condition else { return }
        XCTContext.runActivity(named: "Soft miss: \(note)") { _ in }
    }

    /// Down the page first, then back up it: an element above a card the
    /// test has already scrolled to (a Games room above the game cards) is
    /// found on the way back.
    @MainActor private func scroll(_ app: XCUIApplication, to element: XCUIElement, swipes: Int = 8) -> Bool {
        if element.waitForExistence(timeout: 10), element.isHittable { return true }
        for _ in 0..<swipes {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        for _ in 0..<swipes {
            if element.exists && element.isHittable { return true }
            app.swipeDown()
        }
        return element.exists && element.isHittable
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
