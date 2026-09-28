import Foundation

struct DaydreamCommission: Decodable, Identifiable, Hashable {
    let id: String
    let thoughtId: String
    let backlogSlug: String
    let state: String
    let revision: Int
    let specHash: String
    let spec: ImprovementSpec
    let approvedAt: String?
    let updatedAt: String
    let nextActor: String
    let workflowRunId: String?
    let result: EvidenceReport?
    let error: String?
    let events: [CommissionEvent]
    let url: String

    var label: String {
        switch state {
        case "awaiting_approval": return "Awaiting your approval"
        case "deferred": return "Deferred"
        case "declined": return "Declined"
        case "queued": return "Queued for execution"
        case "running": return "Refreshing evidence"
        case "needs_attention": return "Needs attention"
        case "completed": return "Evidence report ready"
        case "cancelled": return "Cancelled"
        default: return "View current progress"
        }
    }
    var canApprove: Bool { ["awaiting_approval", "deferred"].contains(state) && spec.version == 1 && spec.route == "evidence_refresh" }
    var canCancel: Bool { ["queued", "running", "needs_attention"].contains(state) }
}
struct ImprovementSpec: Decodable, Hashable {
    let version: Int
    let route: String
    let title: String
    let outcome: String
    let currentBehaviour: String
    let improvedBehaviour: String
    let reuseAssessment: [String]
    let acceptance: [String]
    let effects: [String]
    let exclusions: [String]
    let ownerCorrection: String?
    let reads: [EvidenceRead]
    let budget: CommissionBudget
}
struct CommissionBudget: Decodable, Hashable { let maxReads: Int; let maxAttempts: Int; let maxWallSeconds: Int }
struct EvidenceRead: Decodable, Hashable { let sourceRef: String; let tool: String; let args: JSONValue }
struct EvidenceReport: Decodable, Hashable { let summary: String; let evidence: [CommissionEvidence] }
struct CommissionEvidence: Decodable, Hashable {
    let sourceRef: String
    let tool: String
    let retrievedAt: String
    let contentHash: String
    let text: String
    let status: String
    let provenance: String
}
struct CommissionEvent: Decodable, Identifiable, Hashable {
    let id: String
    let sequence: Int
    let kind: String
    let summary: String
    let at: String
}
struct CommissionFeed: Decodable {
    let enabled: Bool
    let commissions: [DaydreamCommission]
}
struct CommissionReply: Decodable { let commission: DaydreamCommission }
struct CommissionDestination: Identifiable { let id: String }

/// The approval binds what was displayed. Never infer authority from a push.
struct CommissionDecisionRequest: Encodable {
    let action = "decide"
    let id: String
    let decision: String
    let revision: Int
    let specHash: String
    let operationKey: String
    init(_ commission: DaydreamCommission, decision: String, operationKey: String = UUID().uuidString) {
        self.id = commission.id; self.decision = decision; self.revision = commission.revision
        self.specHash = commission.specHash; self.operationKey = operationKey
    }
}
