import XCTest
@testable import SRAppleApp

final class EfficiencyTests: XCTestCase {
    func testOfflineAllowlistExcludesPermissionsLocationsAndActions() {
        XCTAssertTrue(OfflineSnapshots.allowed("api/native/today?fresh=1"))
        XCTAssertTrue(OfflineSnapshots.allowed("api/native/health/summary"))
        XCTAssertTrue(OfflineSnapshots.allowed("api/native/news/story/wire/story"))
        for path in ["api/apple/household/live", "api/native/family/tasks", "api/native/access", "api/native/news/actions"] {
            XCTAssertFalse(OfflineSnapshots.allowed(path), path)
        }
        XCTAssertEqual(OfflineSnapshots.normalized("api/native/news?view=top&fresh=1&sort=time"), "api/native/news?sort=time&view=top")
    }

    func testLateJournalCleanupKeepsANewerPendingMessage() async throws {
        struct Turn: Codable { let requestId: String }
        let journal = LocalJournal()
        let scope = OfflineSnapshots.digest(UUID().uuidString)
        try await journal.save(Turn(requestId: "new"), scope: scope, key: "turn")
        await journal.removeIfMatching(Turn.self, scope: scope, key: "turn") { $0.requestId == "old" }
        let kept = await journal.read(Turn.self, scope: scope, key: "turn")
        XCTAssertEqual(kept?.requestId, "new")
        await journal.removeIfMatching(Turn.self, scope: scope, key: "turn") { $0.requestId == "new" }
        let removed = await journal.read(Turn.self, scope: scope, key: "turn")
        XCTAssertNil(removed)
    }

    func testDiagnosticsContainCountsWithoutPersonalValues() {
        var state = PersistedState()
        state.anchors["private-anchor"] = Data("secret-anchor".utf8)
        state.batches = [UploadBatch(deleted: ["private-record-id"])]
        let report = SyncDiagnostics.report(state)
        XCTAssertTrue(report.contains("Health records: 1"))
        XCTAssertFalse(report.contains("private-record-id"))
        XCTAssertFalse(report.contains("private-anchor"))
        XCTAssertFalse(report.contains("secret-anchor"))
    }

    func testFirstHealthUploadWarningDoesNotClaimReadDenial() {
        let now = Date()
        let items = PersonalHealthCheck.items(paired: true, healthEnabled: true, reviewNeeded: false, lastUpload: nil, enabledSince: now.addingTimeInterval(-90000), now: now)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.id, "personal:health-first-upload")
    }
}
