import XCTest
@testable import SRAppleApp

/// The Watch's contract, tested from the phone: what the snapshot carries for
/// whom, that it survives the trip, and what each command from the wrist means.
/// WatchConnectivity itself cannot be driven from a simulator test — that round
/// trip is on the device checklist (docs/DEVICE-TESTING.md).
final class WatchBridgeTests: XCTestCase {

    private func alert(_ id: String, read: Bool = false) -> SiteAlert {
        SiteAlert(id: id, category: "build", title: "Alert \(id)", body: "", url: nil,
                  severity: "info", createdAt: "2026-09-26T08:00:00Z", read: read)
    }

    private func health() throws -> TodayHealth {
        try JSONDecoder().decode(TodayHealth.self, from: Data("""
        {"isMock": false, "strap": "", "generatedAt": "2026-09-26T08:00:00Z",
         "readiness": {"score": 71.6, "label": "Primed", "recommendation": "Go"},
         "figures": [
           {"key": "recovery", "label": "Recovery", "value": 64, "unit": "%", "display": "64", "caption": "today"},
           {"key": "hrv", "label": "HRV", "value": 58, "unit": "ms", "display": "58", "caption": "7-day mean"},
           {"key": "steps", "label": "Steps", "value": 9120, "unit": "", "display": "9,120", "caption": "yesterday"},
           {"key": "sleep", "label": "Sleep", "value": 7.4, "unit": "h", "display": "7h 24m", "caption": "last night"}
         ]}
        """.utf8))
    }

    private let pins = [
        WatchSnapshot.PinnedFlow(slug: "a", title: "A"), WatchSnapshot.PinnedFlow(slug: "b", title: "B"),
        WatchSnapshot.PinnedFlow(slug: "c", title: "C"), WatchSnapshot.PinnedFlow(slug: "d", title: "D"),
    ]

    private func build(access: AppAccess, ownerSite: Bool) throws -> WatchSnapshot {
        WatchSnapshotBuilder.build(
            health: try health(),
            recent: [alert("1"), alert("2"), alert("3"), alert("4")],
            latest: [],
            cleared: ["2"],
            unread: 3,
            access: access,
            ownerSite: ownerSite,
            sync: WatchSnapshot.Sync(queued: 4, lastUpload: nil, gate: "armed"),
            connectionNeedsFixing: true,
            pinned: pins,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    // MARK: - Who sees what

    func testTheOwnerGetsTheInboxTheWorkflowsAndTheConnections() throws {
        let snapshot = try build(access: .everything, ownerSite: true)
        XCTAssertTrue(snapshot.showsAlerts)
        XCTAssertEqual(snapshot.alerts.map(\.id), ["1", "3", "4"], "cleared rows stay off, three at most")
        XCTAssertEqual(snapshot.unread, 3)
        XCTAssertTrue(snapshot.connectionNeedsFixing)
        XCTAssertEqual(snapshot.pinnedFlows.map(\.slug), ["a", "b", "c"], "three pins at most")
        XCTAssertTrue(snapshot.canAsk)
    }

    func testAFamilyMembersWatchNeverCarriesTheOwnersInbox() throws {
        let snapshot = try build(access: AppAccess(family: true), ownerSite: false)
        XCTAssertFalse(snapshot.showsAlerts)
        XCTAssertTrue(snapshot.alerts.isEmpty)
        XCTAssertEqual(snapshot.unread, 0)
        XCTAssertFalse(snapshot.connectionNeedsFixing)
        XCTAssertTrue(snapshot.pinnedFlows.isEmpty)
        XCTAssertFalse(snapshot.canAsk)
        // Their own body's numbers still go: Today and Health are everybody's.
        XCTAssertEqual(snapshot.readiness?.display, "72")
    }

    func testAMemberWithChatMayAskFromTheWrist() throws {
        XCTAssertTrue(try build(access: AppAccess(chat: true), ownerSite: false).canAsk)
    }

    // MARK: - Health

    func testHealthCarriesReadinessRecoveryAndTheLeadFigures() throws {
        let snapshot = try build(access: .everything, ownerSite: true)
        XCTAssertEqual(snapshot.readiness?.label, "Primed")
        XCTAssertEqual(snapshot.readiness?.fraction ?? 0, 0.716, accuracy: 0.0001)
        XCTAssertEqual(snapshot.recovery?.display, "64")
        XCTAssertEqual(snapshot.figures.map(\.key), ["hrv", "sleep"], "steps is not a lead figure; rhr was not sent")
        XCTAssertEqual(snapshot.figures.first?.unit, "ms")
    }

    func testNoHealthMeansNoNumbersRatherThanZeros() {
        XCTAssertNil(WatchSnapshotBuilder.readiness(nil))
        XCTAssertNil(WatchSnapshotBuilder.recovery(nil))
        XCTAssertTrue(WatchSnapshotBuilder.figures(nil).isEmpty)
    }

    // MARK: - The wire

    func testTheSnapshotSurvivesTheApplicationContext() throws {
        let sent = try build(access: .everything, ownerSite: true)
        let received = WatchSnapshot.from(context: sent.context())
        XCTAssertEqual(received, sent)
    }

    func testOnlyTheTimestampMovingIsNotANewSnapshot() throws {
        let a = try build(access: .everything, ownerSite: true)
        let b = WatchSnapshotBuilder.build(
            health: try health(), recent: [alert("1"), alert("2"), alert("3"), alert("4")], latest: [],
            cleared: ["2"], unread: 3, access: .everything, ownerSite: true,
            sync: WatchSnapshot.Sync(queued: 4, lastUpload: nil, gate: "armed"),
            connectionNeedsFixing: true, pinned: pins, now: Date(timeIntervalSince1970: 1_900_000_000))
        XCTAssertTrue(WatchSnapshotBuilder.sameContent(a, b))
        let c = WatchSnapshotBuilder.build(
            health: try health(), recent: [alert("1")], latest: [], cleared: [], unread: 1,
            access: .everything, ownerSite: true, sync: a.sync, connectionNeedsFixing: true,
            pinned: pins, now: a.generatedAt)
        XCTAssertFalse(WatchSnapshotBuilder.sameContent(a, c))
    }

    func testEveryCommandSurvivesTheTrip() {
        let commands: [WatchCommand] = [
            .markRead(id: "a1"), .clearFromToday(id: "a1"), .syncNow,
            .ask(question: "How did I sleep?"), .runFlow(slug: "morning"), .refresh,
        ]
        for command in commands {
            XCTAssertEqual(WatchCommand(message: command.message), command)
        }
    }

    func testMalformedCommandsAreRefused() {
        XCTAssertNil(WatchCommand(message: [:]))
        XCTAssertNil(WatchCommand(message: [WatchCommand.key: "launchMissiles"]))
        XCTAssertNil(WatchCommand(message: [WatchCommand.key: "markRead"]))
        XCTAssertNil(WatchCommand(message: [WatchCommand.key: "ask", "question": "   "]))
        XCTAssertNil(WatchCommand(message: [WatchCommand.key: "runFlow", "slug": ""]))
    }

    func testADictatedQuestionIsTrimmed() {
        XCTAssertEqual(WatchCommand(message: [WatchCommand.key: "ask", "question": "  Hello \n"]),
                       .ask(question: "Hello"))
    }

    func testARepliesDefaultsAreHonest() {
        XCTAssertEqual(WatchReply(message: [:]), WatchReply(ok: false, text: "The iPhone did not answer."))
        XCTAssertEqual(WatchReply(message: WatchReply(ok: true, text: "Synced").message).text, "Synced")
    }

    // MARK: - Pins

    @MainActor func testPinsStopAtThreeAndSurviveARelaunch() {
        let suite = "WatchBridgeTests.pins"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PinnedFlows(defaults: defaults)
        for slug in ["a", "b", "c", "d"] { store.toggle(slug: slug, title: slug.uppercased()) }
        XCTAssertEqual(store.pins.map(\.slug), ["a", "b", "c"])
        XCTAssertTrue(store.isFull)

        store.toggle(slug: "b", title: "B")
        XCTAssertEqual(store.pins.map(\.slug), ["a", "c"])
        XCTAssertEqual(PinnedFlows(defaults: defaults).pins.map(\.slug), ["a", "c"])
    }

    @MainActor func testPinsFollowTheSitesTitlesAndDropDeletedFlows() throws {
        let suite = "WatchBridgeTests.reconcile"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PinnedFlows(defaults: defaults)
        store.toggle(slug: "a", title: "Old name")
        store.toggle(slug: "gone", title: "Deleted")
        let list = try JSONDecoder().decode(FlowList.self, from: Data(#"{"workflows": [{"slug": "a", "title": "New name"}]}"#.utf8))
        store.reconcile(with: list.workflows)
        XCTAssertEqual(store.pins, [WatchSnapshot.PinnedFlow(slug: "a", title: "New name")])
    }
}
