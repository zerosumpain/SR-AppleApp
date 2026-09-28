import XCTest
@testable import SRAppleApp

final class CommissionTests: XCTestCase {
    private let id = "11111111-1111-4111-8111-111111111111"

    private func decode(state: String = "awaiting_approval", version: Int = 1) throws -> DaydreamCommission {
        let spec: [String: Any] = ["version": version, "route": "evidence_refresh", "title": "Refresh the evidence",
            "outcome": "A dated report", "currentBehaviour": "An unverified claim", "improvedBehaviour": "A scoped evidence refresh",
            "reuseAssessment": ["Existing private reads"], "acceptance": ["Record unavailable evidence"],
            "effects": ["Read approved sources"], "exclusions": ["No account changes"], "reads": [],
            "budget": ["maxReads": 1, "maxAttempts": 3, "maxWallSeconds": 180]]
        let wire: [String: Any] = ["id": id, "thoughtId": "thought", "backlogSlug": "proposal", "state": state,
            "revision": 7, "specHash": String(repeating: "a", count: 64), "spec": spec,
            "updatedAt": "2026-09-28T12:00:00Z", "nextActor": "You", "events": [], "url": "/jkai/daydreams?commission=\(id)"]
        return try JSONDecoder().decode(DaydreamCommission.self, from: JSONSerialization.data(withJSONObject: wire))
    }

    func testDecisionCarriesTheDisplayedRevisionAndImmutableScope() throws {
        let c = try decode()
        XCTAssertTrue(c.canApprove)
        let data = try JSONEncoder().encode(CommissionDecisionRequest(c, decision: "approve", operationKey: id))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(body["revision"] as? Int, 7)
        XCTAssertEqual(body["specHash"] as? String, c.specHash)
        XCTAssertEqual(body["operationKey"] as? String, id)
        XCTAssertNil(body["approved"])
    }

    func testUnknownPlansAndTerminalStatesCannotBeApprovedByAnOlderClient() throws {
        XCTAssertFalse(try decode(version: 99).canApprove)
        XCTAssertFalse(try decode(state: "awaiting_merge").canApprove)
        XCTAssertFalse(try decode(state: "completed").canApprove)
        XCTAssertFalse(try decode(state: "cancelled").canCancel)
    }

    func testNotificationDestinationIsOptionalAndVersioned() throws {
        var wire: [String: Any] = ["id": id, "category": "daydream", "title": "Report ready", "body": "Open history",
            "severity": "info", "createdAt": "2026-09-28T12:00:00Z", "read": false]
        func alert() throws -> SiteAlert { try JSONDecoder().decode(SiteAlert.self, from: JSONSerialization.data(withJSONObject: wire)) }
        XCTAssertNil(try alert().commissionId)
        wire["data"] = ["schemaVersion": 1, "destination": "daydream_commission", "commissionId": id]
        XCTAssertEqual(try alert().commissionId, id)
        wire["data"] = ["schemaVersion": 99, "destination": "daydream_commission", "commissionId": id]
        XCTAssertNil(try alert().commissionId)
        wire["data"] = ["schemaVersion": 1, "destination": "daydream_commission", "commissionId": "malformed"]
        XCTAssertNil(try alert().commissionId)
    }
}
