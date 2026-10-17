import XCTest
@testable import SRAppleApp

/// Today's alerts card: which rows it lists, and clearing them off it.
final class TodayTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "TodayTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func alert(_ id: String) -> SiteAlert {
        SiteAlert(id: id, category: "build", title: "Alert \(id)", body: "", url: nil,
                  severity: "info", createdAt: "2026-09-25T08:00:00Z", read: false)
    }

    private func latest(_ id: String) -> TodayAlerts.Latest {
        TodayAlerts.Latest(id: id, category: "build", title: "Alert \(id)", severity: "info",
                           createdAt: "2026-09-25T08:00:00Z")
    }

    // MARK: - Rows

    func testRowsFallBackToTodaysOwnBeforeTheInboxAnswers() {
        let rows = TodayAlerts.rows(recent: [], latest: [latest("a"), latest("b")], cleared: [])
        XCTAssertEqual(rows.map(\.id), ["a", "b"])
    }

    func testRowsPreferTheInboxAndStopAtThree() {
        let rows = TodayAlerts.rows(
            recent: ["1", "2", "3", "4"].map(alert),
            latest: [latest("a")],
            cleared: []
        )
        XCTAssertEqual(rows.map(\.id), ["1", "2", "3"])
    }

    func testAClearedRowMakesRoomForTheNextOne() {
        let rows = TodayAlerts.rows(recent: ["1", "2", "3", "4"].map(alert), latest: [], cleared: ["2"])
        XCTAssertEqual(rows.map(\.id), ["1", "3", "4"])
    }

    func testEverythingClearedLeavesTheCardEmpty() {
        let rows = TodayAlerts.rows(recent: ["1", "2"].map(alert), latest: [latest("1")], cleared: ["1", "2"])
        XCTAssertTrue(rows.isEmpty)
    }

    // MARK: - Clearing

    @MainActor func testClearingIsRememberedAcrossLaunches() {
        let store = AlertStore(defaults: defaults)
        store.clearFromToday(["1", "2", "2"])
        XCTAssertEqual(store.clearedFromToday, ["1", "2"])
        XCTAssertEqual(defaults.stringArray(forKey: AlertStore.clearedKey), ["1", "2"])

        let relaunched = AlertStore(defaults: defaults)
        XCTAssertEqual(relaunched.clearedFromToday, ["1", "2"])
    }

    @MainActor func testTheClearedListIsCappedOldestFirst() {
        let store = AlertStore(defaults: defaults)
        let ids = (0..<(AlertStore.clearedCap + 5)).map { "id-\($0)" }
        store.clearFromToday(ids)
        XCTAssertEqual(store.clearedFromToday.count, AlertStore.clearedCap)
        XCTAssertFalse(store.clearedFromToday.contains("id-0"))
        XCTAssertTrue(store.clearedFromToday.contains("id-\(AlertStore.clearedCap + 4)"))
        XCTAssertEqual(defaults.stringArray(forKey: AlertStore.clearedKey)?.first, "id-5")
    }

    // MARK: - Health rings

    private func health(_ json: String) throws -> TodayHealth {
        try JSONDecoder().decode(TodayHealth.self, from: Data(json.utf8))
    }

    private let recoveryFigure = """
    {"key": "recovery", "label": "Recovery", "value": 64, "unit": "%", "display": "64", "delta": 3,
     "deltaDisplay": "+3 vs 7d", "direction": "up", "improving": true, "caption": "this morning"}
    """

    func testTheThreeRingsAreMoveRecoveryReadinessInThatOrder() throws {
        let today = try health("""
        {"isMock": false, "strap": "", "generatedAt": "2026-09-26T08:00:00Z",
         "readiness": {"score": 71.6, "label": "Primed", "recommendation": "Go"},
         "figures": [\(recoveryFigure)]}
        """)
        let move = MoveRingStore.Reading(value: 320, goal: 640, unit: "kcal")
        let vitals = TodayVital.make(health: today, move: move)
        XCTAssertEqual(vitals.map(\.key), ["move", "recovery", "readiness"])
        XCTAssertEqual(vitals[0].value, "50%")
        XCTAssertEqual(vitals[0].caption, "320/640 kcal")
        XCTAssertEqual(vitals[1].value, "64%")
        XCTAssertEqual(vitals[1].fraction ?? 0, 0.64, accuracy: 0.0001)
        XCTAssertEqual(vitals[2].value, "72")
        XCTAssertEqual(vitals[2].caption, "Primed")
    }

    func testRecoveryFallsBackToTheReadinessFactor() throws {
        let today = try health("""
        {"isMock": false, "strap": "", "generatedAt": "2026-09-26T08:00:00Z",
         "readiness": {"score": 50, "label": "Steady", "recommendation": "Go",
                       "factors": [{"key": "recovery", "label": "Recovery", "score": 41.4, "weight": 0.4}]},
         "figures": []}
        """)
        XCTAssertEqual(TodayVital.recoveryVital(today).value, "41%")
    }

    func testAMalformedFactorListDoesNotCostTheReadiness() throws {
        let today = try health("""
        {"isMock": false, "strap": "", "generatedAt": "2026-09-26T08:00:00Z",
         "readiness": {"score": 50, "label": "Steady", "recommendation": "Go", "factors": [{"key": 3}]},
         "figures": []}
        """)
        XCTAssertEqual(today.readiness?.score, 50)
        XCTAssertTrue(today.readiness?.factors.isEmpty ?? false)
    }

    func testMissingNumbersSayDashRatherThanZero() {
        let vitals = TodayVital.make(health: nil, move: nil)
        XCTAssertEqual(vitals.map(\.value), ["—", "—", "—"])
        XCTAssertTrue(vitals.allSatisfy { $0.fraction == nil })
    }

    func testAMoveRingPastItsGoalReadsOverAHundred() {
        let vital = TodayVital.moveVital(MoveRingStore.Reading(value: 900, goal: 600, unit: "kcal"))
        XCTAssertEqual(vital.value, "150%")
    }

    // MARK: - The sun

    private func owner(score: Double?, generatedAt: String = "2026-09-26T08:00:00Z", isMock: Bool = false) throws -> TodayHealth {
        let readiness = score.map { #", "readiness": {"score": \#($0), "label": "Primed", "recommendation": "A quality session is on the cards."}"# } ?? ""
        return try health("""
        {"isMock": \(isMock), "strap": "", "generatedAt": "\(generatedAt)"\(readiness), "figures": [\(recoveryFigure)]}
        """)
    }

    private let morning = isoDate("2026-09-26T08:30:00Z")!
    private let move = MoveRingStore.Reading(value: 412, goal: 600, unit: "kcal")

    func testAMembersSunIsTheMoveRingAlone() throws {
        let lead = TodayHeroLead.make(ownerSite: false, health: try owner(score: 72), move: move, now: morning)
        XCTAssertEqual(lead.rings.map(\.key), ["move"])
        XCTAssertEqual(lead.figure, "69%")
        XCTAssertEqual(lead.word, "Move")
        XCTAssertEqual(lead.band, .neutral)
        // Nothing of the site's: no figures behind the long press, and no
        // readiness in what is read out.
        XCTAssertTrue(lead.figures.isEmpty)
        XCTAssertNil(lead.recommendation)
        XCTAssertFalse(lead.spoken.contains("Readiness"))
        XCTAssertEqual(lead.moveDetail, "412 / 600 kcal")
    }

    func testTheOwnersSunIsThreeRingsAndTheScore() throws {
        let lead = TodayHeroLead.make(ownerSite: true, health: try owner(score: 72), move: move, now: morning)
        XCTAssertEqual(lead.rings.map(\.key), ["move", "recovery", "readiness"])
        XCTAssertEqual(lead.figure, "72")
        XCTAssertEqual(lead.figureValue, 72)
        XCTAssertEqual(lead.word, "Primed")
        XCTAssertEqual(lead.band, .good)
        XCTAssertFalse(lead.stale)
        XCTAssertEqual(lead.spoken, lead.rings.map(\.spoken).joined(separator: ". "))
    }

    func testTheBandTurnsAtFortyAndSeventy() throws {
        let bands = try [39.0, 40, 69, 70].map {
            TodayHeroLead.make(ownerSite: true, health: try owner(score: $0), move: nil, now: morning).band
        }
        XCTAssertEqual(bands, [.low, .mid, .mid, .good])
    }

    func testFiguresMoreThanThreeHoursOldAreStale() throws {
        let health = try owner(score: 72, generatedAt: "2026-09-26T08:00:00Z")
        let fresh = TodayHeroLead.make(ownerSite: true, health: health, move: nil, now: isoDate("2026-09-26T10:59:00Z")!)
        XCTAssertFalse(fresh.stale)
        let stale = TodayHeroLead.make(ownerSite: true, health: health, move: nil, now: isoDate("2026-09-26T11:00:01Z")!)
        XCTAssertTrue(stale.stale)
        // Said, not printed: the label gains when they are from.
        XCTAssertTrue(stale.spoken.contains(", as of "))
        XCTAssertFalse(fresh.spoken.contains(", as of "))
    }

    func testDemonstrationFiguresSaySo() throws {
        let lead = TodayHeroLead.make(ownerSite: true, health: try owner(score: 72, isMock: true), move: nil, now: morning)
        XCTAssertTrue(lead.spoken.hasSuffix(". Demonstration figures"))
    }

    func testNoPayloadIsADashAndNoWord() {
        let lead = TodayHeroLead.make(ownerSite: true, health: nil, move: nil, now: morning)
        XCTAssertEqual(lead.figure, "—")
        XCTAssertEqual(lead.word, "")
        XCTAssertEqual(lead.band, .neutral)
        XCTAssertEqual(lead.rings.count, 3)
        XCTAssertTrue(lead.rings.allSatisfy { $0.fraction == nil })

        let member = TodayHeroLead.make(ownerSite: false, health: nil, move: nil, now: morning)
        XCTAssertEqual(member.figure, "—")
    }

    // MARK: - Workflow numbers

    private func flows(_ json: String) throws -> [FlowSummary] {
        try JSONDecoder().decode(FlowList.self, from: Data(#"{"workflows": \#(json)}"#.utf8)).workflows
    }

    func testFlowStatsCountFailingAndFindTheNextRun() throws {
        let now = isoDate("2026-09-26T10:00:00Z")!
        let list = try flows("""
        [
          {"slug": "a", "title": "Morning brief", "needsAttention": false,
           "trigger": {"kind": "cron", "enabled": true, "nextRuns": ["2026-09-26T09:00:00Z", "2026-09-27T07:00:00Z"]}},
          {"slug": "b", "title": "Hourly check", "needsAttention": false,
           "trigger": {"kind": "cron", "enabled": true, "nextRuns": ["2026-09-26T11:00:00Z"]}},
          {"slug": "c", "title": "Paused", "needsAttention": false,
           "trigger": {"kind": "cron", "enabled": false, "nextRuns": ["2026-09-26T10:30:00Z"]}},
          {"slug": "d", "title": "Broken", "needsAttention": true, "attentionReason": "Last run failed"},
          {"slug": "e", "title": "Half done", "needsAttention": false, "lastRun": {"id": "r1", "status": "completed_with_errors"}}
        ]
        """)
        let stats = FlowStats(list, now: now)
        XCTAssertEqual(stats.working, 3)
        XCTAssertEqual(stats.failing, 2)
        XCTAssertEqual(stats.next?.title, "Hourly check")
        XCTAssertEqual(stats.next?.at, isoDate("2026-09-26T11:00:00Z"))
    }

    func testNoScheduleMeansNoNextRun() throws {
        let stats = FlowStats(try flows(#"[{"slug": "m", "title": "Manual"}]"#), now: Date())
        XCTAssertNil(stats.next)
        XCTAssertEqual(stats.working, 1)
        XCTAssertEqual(stats.failing, 0)
    }

    // MARK: - Noticed

    @MainActor func testANoteThatArrivesAlreadyRatedIsNotShown() {
        let fresh = DaydreamNote(id: "today-fresh", outcome: .research, channel: .health, title: "T", body: "",
                                 createdAt: "2026-09-26T08:00:00Z")
        let rated = DaydreamNote(id: "today-rated", outcome: .research, channel: .health, title: "T", body: "",
                                 createdAt: "2026-09-26T08:00:00Z", feedback: .useful)
        XCTAssertTrue(NoticedFeedback.shared.isShowing(fresh))
        XCTAssertFalse(NoticedFeedback.shared.isShowing(rated))
    }
}
