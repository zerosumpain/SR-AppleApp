import XCTest
@testable import SRAppleApp

/// The phone's jkai channel (`JkaiEvents.swift`): what a frame says, and what
/// the app does about it.
final class JkaiEventsTests: XCTestCase {

    private func event(_ json: String) -> JkaiEvent? { JkaiEvent.parse(Data(json.utf8)) }

    // MARK: - Reading frames

    func testEachKindIsRead() {
        XCTAssertEqual(event(#"{"type":"connected","scope":"me"}"#), .connected)
        XCTAssertEqual(event(#"{"kind":"turn","conversationId":"c","jobId":"j","status":"running"}"#),
                       .turn(conversationId: "c", jobId: "j", status: "running"))
        XCTAssertEqual(event(#"{"kind":"message","conversationId":"c","role":"assistant","content":"Hi","source":"daydream"}"#),
                       .message(conversationId: "c", role: "assistant"))
        XCTAssertEqual(event(#"{"kind":"gate","conversationId":"c","jobId":"j","gate":"plan","open":true}"#),
                       .gate(conversationId: "c", jobId: "j", gate: "plan", open: true))
    }

    func testUnknownOrIncompleteFramesAreIgnored() {
        XCTAssertNil(event(#"{"kind":"build","conversationId":"c"}"#))
        XCTAssertNil(event(#"{"kind":"turn","conversationId":"c"}"#))
        XCTAssertNil(event(#"{"kind":"turn","jobId":"j","status":"done"}"#), "no thread")
        XCTAssertNil(event(#"{"kind":"gate","conversationId":"c","jobId":"j","gate":"plan"}"#), "open is required")
        XCTAssertNil(event(#"{"kind":"desk","conversationId":"c","phase":"done"}"#), "no message id")
        XCTAssertNil(event("[1,2]"))
        XCTAssertNil(event("keepalive"))
    }

    func testADeskFrameKeepsTheBlocksItCanRead() {
        guard case .desk(let id, let update)? = event("""
        {"kind":"desk","conversationId":"c","messageId":"row-1","phase":"done",
         "blocks":[{"id":"rt-a","type":"prose","markdown":"Check the date."},{"id":"x","type":"hologram"},7]}
        """) else { return XCTFail("not a desk frame") }
        XCTAssertEqual(id, "c")
        XCTAssertEqual(update.messageId, "row-1")
        XCTAssertEqual(update.section, JkaiDeskUpdate.redTeam, "an absent section is the red team")
        XCTAssertEqual(update.blocks.map(\.id), ["rt-a", "x"], "an unknown type holds its place; a non-object is skipped")
    }

    // MARK: - The desk section, as the web puts it on the page

    private func prose(_ id: String, _ text: String = "x") -> PanelBlock {
        PanelBlock(id: id, content: .prose(text, tone: nil))
    }

    private let answer = PanelPage(head: PanelHead(kicker: "This turn", title: "Trains"), sections: [
        PanelSection(id: "rows", label: "Rows", blocks: [PanelBlock(id: "r", content: .prose("row", tone: nil))]),
    ])

    func testTheRedTeamDrawsItsPartsAndTheFinalVerdictWins() {
        let partial = JkaiDeskUpdate(messageId: "m", section: "red-team", phase: "partial", blocks: [prose("rt-a"), prose("rt-b")])
        let once = partial.applied(to: answer)
        XCTAssertEqual(once?.sections.map(\.id), ["rows", "red-team"])
        XCTAssertEqual(once?.sections.last?.label, "Red team")
        XCTAssertEqual(once?.head.title, "Trains", "a page with something on it keeps its head")

        let done = JkaiDeskUpdate(messageId: "m", section: "red-team", phase: "done", blocks: [prose("rt-b", "final")])
        let final = done.applied(to: once)
        XCTAssertEqual(final?.sections.last?.blocks.map(\.id), ["rt-b"], "what the final verdict dropped goes")
        XCTAssertEqual(final?.sections.last?.blocks.first?.content, .prose("final", tone: nil))

        // A replay of the same frame changes nothing.
        XCTAssertEqual(done.applied(to: final), final)
    }

    func testRunningAndFailedChangeNothingOnThePage() {
        for phase in ["running", "failed"] {
            let update = JkaiDeskUpdate(messageId: "m", section: "red-team", phase: phase, blocks: [prose("a")])
            XCTAssertEqual(update.applied(to: answer), answer, phase)
            XCTAssertTrue(update.ops(on: nil).isEmpty, phase)
        }
    }

    func testTheAnalystAppearsOnlyWhenDoneAndHeadsAnEmptyPage() {
        let running = JkaiDeskUpdate(messageId: "m", section: "analyst", phase: "partial", blocks: [prose("an-1")])
        XCTAssertTrue(running.ops(on: nil).isEmpty)
        let done = JkaiDeskUpdate(messageId: "m", section: "analyst", phase: "done", blocks: [prose("an-1")], headline: "Roadworks tonight")
        let page = done.applied(to: nil)
        XCTAssertEqual(page?.head.kicker, "Desk")
        XCTAssertEqual(page?.head.title, "Roadworks tonight")
        XCTAssertEqual(page?.sections.map(\.label), ["Worth knowing"])
        XCTAssertEqual(done.applied(to: answer)?.head.title, "Trains")
    }

    // MARK: - Routing

    func testAnOpenThreadIsUpdatedAndAClosedOneIsMarked() {
        let open: Set<String> = ["a"]
        XCTAssertEqual(JkaiEventAction.route(.message(conversationId: "a", role: "assistant"), open: open), [.reload(conversationId: "a")])
        XCTAssertEqual(JkaiEventAction.route(.message(conversationId: "b", role: "assistant"), open: open), [.mark(conversationId: "b", .reply)])
        XCTAssertEqual(JkaiEventAction.route(.gate(conversationId: "a", jobId: "j", gate: "plan", open: true), open: open), [.probe(conversationId: "a")])
        XCTAssertEqual(JkaiEventAction.route(.gate(conversationId: "b", jobId: "j", gate: "plan", open: true), open: open), [.mark(conversationId: "b", .waiting)])
        XCTAssertEqual(JkaiEventAction.route(.gate(conversationId: "b", jobId: "j", gate: "plan", open: false), open: open), [.unmark(conversationId: "b", .waiting)])
        let desk = JkaiDeskUpdate(messageId: "m", section: "analyst", phase: "done", blocks: [])
        XCTAssertEqual(JkaiEventAction.route(.desk(conversationId: "a", update: desk), open: open), [.desk(conversationId: "a", desk)])
        XCTAssertEqual(JkaiEventAction.route(.desk(conversationId: "b", update: desk), open: open), [], "stored on the row already")
        XCTAssertEqual(JkaiEventAction.route(.connected, open: open), [])
    }

    func testATurnMovesTheRunningDot() {
        let open: Set<String> = ["a"]
        XCTAssertEqual(JkaiEventAction.route(.turn(conversationId: "a", jobId: "j", status: "running"), open: open),
                       [.running(conversationId: "a", true), .probe(conversationId: "a")], "a turn started on the web is joined")
        XCTAssertEqual(JkaiEventAction.route(.turn(conversationId: "a", jobId: "j", status: "interrupted"), open: open),
                       [.running(conversationId: "a", false), .turnEnded(conversationId: "a", jobId: "j")])
        XCTAssertEqual(JkaiEventAction.route(.turn(conversationId: "b", jobId: "j", status: "gated"), open: open),
                       [.running(conversationId: "b", true)])
        XCTAssertEqual(JkaiEventAction.route(.turn(conversationId: "b", jobId: "j", status: "done"), open: open),
                       [.running(conversationId: "b", false), .unmark(conversationId: "b", .waiting)])
    }

    func testARowShowsItsStrongestMark() {
        XCTAssertEqual(JkaiEventAction.strongest([.reply, .running]), .running)
        XCTAssertEqual(JkaiEventAction.strongest([.reply, .waiting]), .waiting)
        XCTAssertEqual(JkaiEventAction.strongest([.reply]), .reply)
        XCTAssertNil(JkaiEventAction.strongest([]))
    }

    // MARK: - Resuming the channel

    func testTheChannelResumesAndGivesUpUntilTheNextForeground() {
        var resume = JkaiEventsResume()
        XCTAssertTrue(resume.accept(nil))
        XCTAssertTrue(resume.accept(7))
        XCTAssertFalse(resume.accept(7), "a replay")
        XCTAssertEqual(resume.lastEventId, 7)
        var waits: [TimeInterval] = []
        while case .reconnect(let wait) = resume.next(afterStatus: nil) { waits.append(wait) }
        XCTAssertEqual(waits, TurnStreamResume.backoff)
        resume.restart()
        XCTAssertEqual(resume.next(afterStatus: 503), .reconnect(after: 1))
        XCTAssertEqual(resume.next(afterStatus: 404), .stop, "the site has no channel")
        XCTAssertEqual(resume.next(afterStatus: 403), .stop)
        XCTAssertEqual(resume.next(afterStatus: 401), .stop)
        XCTAssertEqual(resume.lastEventId, 7, "kept for the next foreground")
    }

    func testFeaturesAreOffUnlessSaidTrue() {
        XCTAssertEqual(JkaiFeatures(nil), .off)
        XCTAssertEqual(JkaiFeatures(["presence": "yes", "events": true]), JkaiFeatures(events: true))
    }

    // MARK: - Asks

    /// A desk button hands the composer what the web's `askAbout` does: the
    /// question is `label`, `detail` is the context it is about.
    func testADeskAskIsTheQuestionAfterItsContext() throws {
        let ask = try JSONDecoder().decode(PanelAsk.self, from: Data(#"{"label":"Why is it late?","detail":"Train 2C41, 8 min late"}"#.utf8))
        XCTAssertEqual(ask.composerText, "Use the selected context from the desk:\nTrain 2C41, 8 min late\n\nWhy is it late?")
    }

    func testTodaysAsksAreItsAskButtonsOnceEach() throws {
        let page = try JSONDecoder().decode(PanelPage.self, from: Data("""
        {"version":1,"producer":"today","head":{"kicker":"Today","title":"Good morning"},"sections":[
          {"id":"asks","label":"","blocks":[{"id":"today-asks","type":"actions","items":[
            {"id":"waiting","label":"What's waiting on me?","kind":"ask","ask":{"label":"What's waiting on me?","detail":"What's waiting on me? List it."}},
            {"id":"site","label":"Open","kind":"link","href":"/jkai"},
            {"id":"post","label":"Do it","kind":"post"},
            {"id":"again","label":"Again","kind":"ask","ask":{"label":"x","detail":"What's waiting on me? List it."}}]}]},
          {"id":"more","label":"More","blocks":[{"id":"g","type":"group","blocks":[
            {"id":"inner","type":"actions","items":[{"id":"brief","label":"Brief me","kind":"ask","ask":{"label":"Brief me","detail":"Brief me on today."}}]}]}]}]}
        """.utf8))
        XCTAssertEqual(page.asks, [
            PanelAsk(label: "What's waiting on me?", detail: "What's waiting on me? List it."),
            PanelAsk(label: "Brief me", detail: "Brief me on today."),
        ])
        XCTAssertEqual(PanelPage().asks, [])
    }
}
