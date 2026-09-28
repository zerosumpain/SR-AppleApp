import Foundation

/// Runs only inside the existing synthetic demo transport; never calls a server.
enum CommissionDemoFixtures {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var completed = false
    }
    private static let state = State()
    static func reply(method: String, query: [String: String], body: Data?) -> String? {
        var enabled = false
        #if DEBUG
        enabled = ProcessInfo.processInfo.arguments.contains("-SRCommissionUITest")
        #endif
        guard enabled else { return method == "GET" ? #"{"enabled":false,"commissions":[]}"# : nil }
        state.lock.lock()
        defer { state.lock.unlock() }
        if method == "POST" {
            guard let body, let command = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  command["decision"] as? String == "approve", command["revision"] as? Int == 1,
                  command["specHash"] as? String == String(repeating: "a", count: 64),
                  UUID(uuidString: command["operationKey"] as? String ?? "") != nil else { return nil }
            state.completed = true
        }
        let done = state.completed
        let id = "11111111-1111-4111-8111-111111111111"
        let spec: [String: Any] = ["version": 1, "route": "evidence_refresh", "title": "Synthetic evidence refresh",
            "outcome": "Review the cited sources", "currentBehaviour": "An unverified suggestion", "improvedBehaviour": "A dated evidence report",
            "reuseAssessment": ["Existing source readers"], "acceptance": ["Keep the claim unverified"],
            "effects": ["Read sources"], "exclusions": ["No account changes"], "reads": [],
            "budget": ["maxReads": 1, "maxAttempts": 3, "maxWallSeconds": 180]]
        var commission: [String: Any] = ["id": id, "thoughtId": "demo-note", "backlogSlug": "demo-proposal",
            "state": done ? "completed" : "awaiting_approval", "revision": done ? 2 : 1,
            "specHash": String(repeating: "a", count: 64), "spec": spec, "updatedAt": "2026-09-28T12:00:00Z",
            "nextActor": done ? "None" : "You", "events": [["id": "event", "sequence": 1,
                "kind": done ? "outcome.recorded" : "approval.requested", "summary": done ? "Evidence report recorded" : "Review your proposal",
                "at": "2026-09-28T12:00:00Z"]], "url": "/jkai/daydreams?commission=\(id)"]
        if done { commission["result"] = ["summary": "The synthetic query is refreshed; its claim remains unverified.", "evidence": []] as [String: Any] }
        let payload: [String: Any] = method == "POST" || query["id"] != nil
            ? ["commission": commission] : ["enabled": true, "commissions": [commission]]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
