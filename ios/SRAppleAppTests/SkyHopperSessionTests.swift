import XCTest
@testable import SRAppleApp

/// Ordinary touch play, outside the demo: Play puts Hop on the home cloud,
/// a tap on the sky starts the run, the clock moves Hop, Pause stops it,
/// and carrying on waits for another tap.
@MainActor
final class SkyHopperSessionTests: XCTestCase {
    private func spin(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func testTouchPlayStartsPausesAndCarriesOn() throws {
        try XCTSkipIf(SRDemo.isOn, "the demo flies itself; this is ordinary play")
        let session = SkyHopperSession()
        defer { session.leave() }
        XCTAssertEqual(session.stage, .intro)
        XCTAssertFalse(session.scripted)

        session.play()
        XCTAssertEqual(session.stage, .ready, "Play leaves Hop waiting for a tap")
        XCTAssertTrue(session.isSteering, "Pause is live while Hop waits")

        session.start()                               // the tap on the sky
        XCTAssertEqual(session.stage, .playing)
        let before = session.game.time
        spin(1.0)
        XCTAssertGreaterThan(session.game.time, before, "the run did not advance after the tap")

        session.pause()
        XCTAssertEqual(session.stage, .paused)
        let held = session.game.time
        spin(0.4)
        XCTAssertEqual(session.game.time, held, "the sky moved while paused")

        session.resume()
        XCTAssertEqual(session.stage, .ready, "outside the demo, carrying on waits for a tap")
        session.start()
        XCTAssertEqual(session.stage, .playing)

        session.menu()
        XCTAssertEqual(session.stage, .intro)
        session.play()
        XCTAssertEqual(session.stage, .ready, "Play again from the menu")
    }

    func testAStartTapOutsideReadyDoesNothing() {
        let session = SkyHopperSession()
        defer { session.leave() }
        session.start()
        XCTAssertEqual(session.stage, .intro, "a tap on the sky behind the card must not start a run")
    }
}
