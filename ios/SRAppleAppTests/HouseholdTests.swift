import XCTest
import UserNotifications
@testable import SRAppleApp

/// The household lane on the phone: the sharing question, the member defaults,
/// and the drain of `/api/apple/alerts` into local notifications.
final class HouseholdTests: XCTestCase {

    private struct Refused: Error {}

    private func alert(_ id: String) -> HouseholdAlert {
        HouseholdAlert(id: id, title: "Someone arrived", body: "Arrived at a named place 17:52", at: "2026-09-26T16:52:00Z")
    }

    // MARK: - /me

    func testProfileDecodesTheOwnerFlag() throws {
        let member = try JSONDecoder().decode(Profile.self, from: Data(#"{"id":"u1","name":"A","email":"a@example.com","sharing":false,"demo":false,"owner":false}"#.utf8))
        XCTAssertEqual(member.owner, false)
        let owner = try JSONDecoder().decode(Profile.self, from: Data(#"{"id":"u2","name":"B","sharing":true,"owner":true}"#.utf8))
        XCTAssertEqual(owner.owner, true)
    }

    func testAnOlderServerWithoutOwnerStillDecodes() throws {
        let profile = try JSONDecoder().decode(Profile.self, from: Data(#"{"id":"u1","name":"A","sharing":true}"#.utf8))
        XCTAssertNil(profile.owner, "missing means not told — neither owner nor member")
        XCTAssertTrue(profile.sharing)
    }

    // MARK: - The sharing question

    func testTheQuestionIsOnlyForAPairedPhoneThatIsNotSharing() {
        XCTAssertTrue(SharingQuestion.shouldAsk(paired: true, asked: false, sharing: false))
        XCTAssertFalse(SharingQuestion.shouldAsk(paired: false, asked: false, sharing: false), "nothing to share with before pairing")
        XCTAssertFalse(SharingQuestion.shouldAsk(paired: true, asked: true, sharing: false), "asked once, never again")
        XCTAssertFalse(SharingQuestion.shouldAsk(paired: true, asked: false, sharing: true),
                       "a phone already sharing has answered; a default-off question must not switch it off")
    }

    func testTheQuestionIsWordedAsAgreed() {
        XCTAssertEqual(SharingQuestion.title, "Share your location with the household?")
        XCTAssertEqual(SharingQuestion.message, "Your family will see where you are and when you arrive or leave places you've named. You can change this any time in Settings.")
    }

    func testAnExistingStateFileHasNotBeenAsked() throws {
        let old = #"{"batches":[],"anchors":{},"healthEnabled":["activity"],"sharing":false,"historyStart":768000}"#
        let state = try JSONDecoder().decode(PersistedState.self, from: Data(old.utf8))
        XCTAssertFalse(state.sharingAsked)
        XCTAssertEqual(state.healthEnabled, ["activity"], "the upload settings survive")
    }

    @MainActor func testRePairingAsksAgainAndStartsWithSharingAndHealthOff() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        let outbox = try Outbox(url: url)
        try outbox.change { $0.sharingAsked = true; $0.sharing = true; $0.healthEnabled = ["activity", "heart"] }
        XCTAssertTrue(try Outbox(url: url).state.sharingAsked, "the answer is persisted")

        try outbox.clear()
        XCTAssertFalse(outbox.state.sharingAsked, "a new pairing may be a different person")
        XCTAssertFalse(outbox.state.sharing, "sharing is off until they say yes")
        // D4: every Health group is off for a fresh pairing, owner or member.
        // Nothing turns one on but the reader, so there is no default to undo.
        XCTAssertTrue(outbox.state.healthEnabled.isEmpty)
        XCTAssertTrue(PersistedState().healthEnabled.isEmpty)
    }

    /// I-1: the question's default must never unshare anybody. "Not now" (and a
    /// swipe, which answers the same way) records the answer and sends nothing:
    /// no local switch-off, and no pending change for the next flush to PUT.
    @MainActor func testNotNowOnlyRecordsTheAnswer() async throws {
        for sharing in [true, false] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let outbox = try Outbox(url: directory.appendingPathComponent("state.json"))
            try outbox.change { $0.sharing = sharing }
            let companion = Companion(outbox: outbox)

            await companion.answerSharingQuestion(false)

            XCTAssertTrue(outbox.state.sharingAsked, "answered, so never asked again")
            XCTAssertEqual(outbox.state.sharing, sharing, "Not now must not change sharing")
            XCTAssertNil(outbox.state.pendingSharing, "and must queue nothing for the server")
        }
    }

    /// I-1: a re-paired phone whose person is already sharing on the server
    /// adopts that, and so is never asked.
    func testARePairedPhoneAdoptsTheServersSharing() {
        XCTAssertTrue(SharingQuestion.adoptsServerSharing(local: false, pending: nil, server: true))
        XCTAssertFalse(SharingQuestion.adoptsServerSharing(local: false, pending: nil, server: false))
        XCTAssertFalse(SharingQuestion.adoptsServerSharing(local: true, pending: nil, server: true), "already on")
        XCTAssertFalse(SharingQuestion.adoptsServerSharing(local: false, pending: false, server: true),
                       "a local choice not yet delivered outranks the server")

        // Adopted, the question is then not due.
        let local = SharingQuestion.adoptsServerSharing(local: false, pending: nil, server: true)
        XCTAssertFalse(SharingQuestion.shouldAsk(paired: true, asked: false, sharing: local))
    }

    // MARK: - The alerts drain

    /// I-2: the drain rides on a flush and must not make a failed one wait
    /// longer; and its requests are short.
    func testTheDrainIsSkippedWhenTheFlushsUploadFailed() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(HouseholdAlerts.due(last: nil, now: start, uploadFailed: true))
        XCTAssertFalse(HouseholdAlerts.due(last: start, now: start.addingTimeInterval(3600), uploadFailed: true))
        XCTAssertTrue(HouseholdAlerts.due(last: nil, now: start, uploadFailed: false))
        XCTAssertLessThanOrEqual(HouseholdAlerts.requestTimeout, 6)
    }

    func testTheQueueDecodes() throws {
        let body = #"{"alerts":[{"id":"e1","title":"Someone arrived","body":"Arrived 17:52","at":"2026-09-26T16:52:00Z"},{"id":"e2","title":"Someone left","body":"Left 18:10"}]}"#
        let queue = try JSONDecoder().decode(HouseholdAlertsResponse.self, from: Data(body.utf8))
        XCTAssertEqual(queue.alerts.map(\.id), ["e1", "e2"])
        XCTAssertEqual(queue.alerts[1].body, "Left 18:10")
        XCTAssertNil(queue.alerts[1].at)
    }

    func testANotificationIsTheServersWordsUnderTheAlertsId() {
        let request = HouseholdAlerts.request(for: alert("e1"))
        XCTAssertEqual(request.identifier, "e1", "a repeated drain replaces, never doubles")
        XCTAssertEqual(request.content.title, "Someone arrived")
        XCTAssertEqual(request.content.body, "Arrived at a named place 17:52", "verbatim: the body carries the crossing time")
        XCTAssertEqual(request.content.categoryIdentifier, "household")
        XCTAssertNil(request.trigger)
    }

    @MainActor func testOnlyWhatIOSAcceptedIsAcknowledged() async {
        var tried: [String] = []
        let delivered = await HouseholdAlerts.post([alert("a"), alert("b"), alert("c")]) { request in
            tried.append(request.identifier)
            if request.identifier == "b" { throw Refused() }
        }
        XCTAssertEqual(tried, ["a", "b", "c"], "one failure does not stop the rest")
        XCTAssertEqual(delivered, ["a", "c"], "the refused one stays queued on the server")
    }

    @MainActor func testNothingPostedMeansNothingAcknowledged() async {
        let delivered = await HouseholdAlerts.post([alert("a")]) { _ in throw Refused() }
        XCTAssertTrue(delivered.isEmpty)
    }

    func testTheDrainAsksAtMostOnceAMinute() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(HouseholdAlerts.due(last: nil, now: start))
        XCTAssertFalse(HouseholdAlerts.due(last: start, now: start.addingTimeInterval(59)))
        XCTAssertTrue(HouseholdAlerts.due(last: start, now: start.addingTimeInterval(60)))
    }
}
