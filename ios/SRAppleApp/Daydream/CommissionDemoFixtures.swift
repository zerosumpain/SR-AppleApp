import Foundation

/// The demo's double-checks. Runs only inside the existing synthetic demo
/// transport (`-SRDemo`, the UI tests, the App Review demo); never calls a
/// server. SYNTHETIC, like every other fixture: the repository is public.
///
/// Three to start, one for each place a double-check can be:
///   - waiting for your OK, on the HRV note (the UI test approves this one),
///   - checking now, on the subscriptions note,
///   - report ready, on the easy-run note.
/// "Double-check it" on any other note prepares a fourth, which can be
/// approved, put off, declined or stopped like the rest.
///
/// A decision must carry the revision and plan hash the sheet showed and a
/// fresh operation key, or it is refused — the same binding the site holds.
enum CommissionDemoFixtures {
    static let awaitingId = "11111111-1111-4111-8111-111111111111"
    static let runningId = "22222222-2222-4222-8222-222222222222"
    static let completedId = "33333333-3333-4333-8333-333333333333"
    static let specHash = String(repeating: "a", count: 64)

    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var commissions: [String: [String: Any]] = [:]
        var order: [String] = []
        var prepared = 0
    }
    private static let state = State()

    static func reply(method: String, query: [String: String], body: Data?) -> String? {
        state.lock.lock()
        defer { state.lock.unlock() }
        if state.commissions.isEmpty { seed() }

        if method == "POST" {
            guard let body, let command = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
            switch command["action"] as? String {
            case "prepare":
                guard let thought = command["thoughtId"] as? String, !thought.isEmpty else { return nil }
                return encode(["commission": prepare(thoughtId: thought)])
            case "decide":
                guard let updated = decide(command) else { return nil }
                return encode(["commission": updated])
            default:
                return nil
            }
        }
        if let id = query["id"] {
            guard let one = state.commissions[id] else { return nil }
            return encode(["commission": one])
        }
        let all = state.order.reversed().compactMap { state.commissions[$0] }
        return encode(["enabled": true, "commissions": all])
    }

    // MARK: - Decisions

    private static func decide(_ command: [String: Any]) -> [String: Any]? {
        guard let id = command["id"] as? String, var commission = state.commissions[id],
              let decision = command["decision"] as? String,
              command["revision"] as? Int == commission["revision"] as? Int,
              command["specHash"] as? String == specHash,
              UUID(uuidString: command["operationKey"] as? String ?? "") != nil else { return nil }
        let current = commission["state"] as? String ?? ""
        let revision = (commission["revision"] as? Int ?? 1) + 1
        let next: String
        switch (decision, current) {
        case ("approve", "awaiting_approval"), ("approve", "deferred"): next = "completed"
        case ("defer", "awaiting_approval"): next = "deferred"
        case ("decline", "awaiting_approval"), ("decline", "deferred"): next = "declined"
        case ("cancel", "queued"), ("cancel", "running"), ("cancel", "needs_attention"): next = "cancelled"
        case ("retry", "needs_attention"): next = "running"
        default: return nil
        }
        commission["state"] = next
        commission["revision"] = revision
        commission["updatedAt"] = iso(minutesAgo: 0)
        commission["nextActor"] = next == "deferred" ? "You, in a week" : "Nobody"
        if decision == "approve" {
            // The demo has no worker: an approval comes straight back with
            // its report, so the sheet can be seen through to the end.
            commission["approvedAt"] = iso(minutesAgo: 0)
            let thought = commission["thoughtId"] as? String ?? ""
            let reads = (commission["spec"] as? [String: Any])?["reads"] as? [[String: Any]] ?? []
            commission["result"] = result(for: thought, reads: reads)
        }
        var events = commission["events"] as? [[String: Any]] ?? []
        events.append(event(events.count + 1, summary: summary(of: decision), minutesAgo: 0))
        if decision == "approve" {
            events.append(event(events.count + 1, summary: "Report ready", minutesAgo: 0))
        }
        commission["events"] = events
        state.commissions[id] = commission
        state.order.removeAll { $0 == id }
        state.order.append(id)
        return commission
    }

    private static func summary(of decision: String) -> String {
        switch decision {
        case "approve": return "You approved it"
        case "defer": return "You put it off for a week"
        case "decline": return "You declined it"
        case "cancel": return "You stopped it"
        case "retry": return "You asked it to try again"
        default: return "Updated"
        }
    }

    private static func prepare(thoughtId: String) -> [String: Any] {
        if let existing = state.commissions.values.first(where: { $0["thoughtId"] as? String == thoughtId }) {
            return existing
        }
        state.prepared += 1
        let id = String(format: "44444444-4444-4444-8444-%012ld", state.prepared)
        let title = SRDemoFixtures.demoNotes.first { $0.id == thoughtId }?.title ?? "this note"
        let commission = make(
            id: id, thoughtId: thoughtId, state: "awaiting_approval",
            spec: spec(
                title: "Double-check: \(title)",
                outcome: "Re-read the sources this note cited and say whether it still holds.",
                reads: [["sourceRef": "r1", "tool": "memory_search", "args": ["query": title]]],
                acceptance: ["The report says whether the note still holds, and when each source was read.",
                             "A source it cannot reach is named, not guessed."],
                exclusions: ["Nothing is changed, sent or bought", "No sources beyond the one listed"]
            ),
            events: [event(1, summary: "Plan drawn up for your OK", minutesAgo: 0)],
            minutesAgo: 0
        )
        state.commissions[id] = commission
        state.order.append(id)
        return commission
    }

    // MARK: - The three it starts with

    private static func seed() {
        let awaiting = make(
            id: awaitingId, thoughtId: "demo-note-hrv-caffeine", state: "awaiting_approval",
            spec: spec(
                title: "Double-check: HRV dips on the days after a late coffee",
                outcome: "Re-read the heart-rate-variability trend and the late-coffee days, and say whether the dip still shows.",
                reads: [
                    ["sourceRef": "r1", "tool": "health_series", "args": ["metric": "hrv", "days": 30] as [String: Any]],
                    ["sourceRef": "r2", "tool": "correlate", "args": ["a": "caffeine_late", "b": "hrv", "days": 30] as [String: Any]],
                ],
                acceptance: ["The report says whether the dip still shows, with the days it read.",
                             "A source it cannot reach is named, not guessed."],
                exclusions: ["No changes to your health data", "No messages sent", "Nothing outside these two look-ups"]
            ),
            events: [event(1, summary: "Plan drawn up for your OK", minutesAgo: 40)],
            minutesAgo: 40
        )
        var running = make(
            id: runningId, thoughtId: "demo-note-subscriptions", state: "running",
            spec: spec(
                title: "Double-check: Two music subscriptions have overlapped since spring",
                outcome: "Re-read the bank lines and the receipts, and say whether both services are still billing.",
                reads: [
                    ["sourceRef": "r1", "tool": "spend", "args": ["merchant": "music services", "days": 180] as [String: Any]],
                    ["sourceRef": "r2", "tool": "mail_facts", "args": ["query": "receipt", "daysBack": 60] as [String: Any]],
                ],
                acceptance: ["The report lists which services billed in each of the last six months."],
                exclusions: ["Nothing is cancelled or changed", "No mail bodies are read — only dates and senders"]
            ),
            events: [
                event(1, summary: "Plan drawn up for your OK", minutesAgo: 30),
                event(2, summary: "You approved it", minutesAgo: 6),
                event(3, summary: "Started re-reading the sources", minutesAgo: 5),
            ],
            minutesAgo: 5
        )
        running["approvedAt"] = iso(minutesAgo: 6)
        running["workflowRunId"] = "demo-run"
        var completed = make(
            id: completedId, thoughtId: "demo-note-zone2", state: "completed",
            spec: spec(
                title: "Double-check: What counts as easy for a 40-minute run",
                outcome: "Re-read the guidance and the recent runs, and say where easy sits now.",
                reads: [
                    ["sourceRef": "r1", "tool": "research_web_search", "args": ["query": "easy run heart rate threshold"]],
                    ["sourceRef": "r2", "tool": "activities", "args": ["limit": 10]],
                    ["sourceRef": "r3", "tool": "fetch_url", "args": ["url": "https://www.example.org/running/easy-pace"]],
                ],
                acceptance: ["The report gives a heart-rate ceiling for easy runs, with the runs it read."],
                exclusions: ["No changes to your training plan"]
            ),
            events: [
                event(1, summary: "Plan drawn up for your OK", minutesAgo: 60 * 20),
                event(2, summary: "You approved it", minutesAgo: 60 * 19),
                event(3, summary: "Report ready", minutesAgo: 60 * 19 - 3),
            ],
            minutesAgo: 60 * 19 - 3
        )
        completed["approvedAt"] = iso(minutesAgo: 60 * 19)
        completed["result"] = [
            "summary": "Easy still sits near 140 bpm. Four of the last ten runs went above it after the 25-minute mark; the other six stayed under.",
            "evidence": [
                evidence("r1", "research_web_search", text: "Guidance consistently places easy running below the first ventilatory threshold, commonly estimated at 75–80% of maximum heart rate.", minutesAgo: 60 * 19 - 2, seed: "1"),
                evidence("r2", "activities", text: "10 runs, 38–44 minutes each. Four crossed 140 bpm after minute 25; median heart rate 136 bpm.", minutesAgo: 60 * 19 - 2, seed: "2"),
                evidence("r3", "fetch_url", text: "", minutesAgo: 60 * 19 - 2, seed: "3", status: "unavailable"),
            ],
        ] as [String: Any]
        for commission in [completed, running, awaiting] {
            let id = commission["id"] as? String ?? ""
            state.commissions[id] = commission
            state.order.append(id)
        }
    }

    private static func result(for thoughtId: String, reads: [[String: Any]]) -> [String: Any] {
        if thoughtId == "demo-note-hrv-caffeine" {
            return [
                "summary": "The dip still shows. On the eight late-coffee days in the last 30, HRV averaged 6 ms lower the next night. Eight days is still a small sample.",
                "evidence": [
                    evidence("r1", "health_series", text: "HRV, 30 nights: mean 48 ms; range 37–61 ms.", minutesAgo: 0, seed: "4"),
                    evidence("r2", "correlate", text: "Late coffee (8 days) against next-night HRV: −6 ms, r = −0.41.", minutesAgo: 0, seed: "5"),
                ],
            ]
        }
        let first = reads.first
        return [
            "summary": "The note still holds. Its source says the same as it did when the note was written.",
            "evidence": [
                evidence(first?["sourceRef"] as? String ?? "r1", first?["tool"] as? String ?? "memory_search",
                         text: "The same facts as the note cited, read again just now.", minutesAgo: 0, seed: "6"),
            ],
        ]
    }

    // MARK: - Shapes

    private static func make(id: String, thoughtId: String, state: String, spec: [String: Any],
                             events: [[String: Any]], minutesAgo: Double) -> [String: Any] {
        [
            "id": id, "thoughtId": thoughtId, "backlogSlug": "demo-double-check-\(thoughtId)",
            "state": state, "revision": 1, "specHash": specHash, "spec": spec,
            "updatedAt": iso(minutesAgo: minutesAgo), "nextActor": state == "awaiting_approval" ? "You" : "jkai",
            "events": events, "url": "/jkai/daydreams?commission=\(id)",
        ]
    }

    private static func spec(title: String, outcome: String, reads: [[String: Any]], acceptance: [String],
                             exclusions: [String]) -> [String: Any] {
        [
            "version": 1, "route": "evidence_refresh", "title": title, "outcome": outcome,
            "currentBehaviour": "The note rests on sources read when it was written.",
            "improvedBehaviour": "A dated report of what the same sources say now.",
            "reuseAssessment": ["Uses the same reads the note cited. Nothing new is built."],
            "acceptance": acceptance,
            "effects": ["Reads the sources listed, once each, up to three tries"],
            "exclusions": exclusions,
            "reads": reads,
            "budget": ["maxReads": max(1, reads.count), "maxAttempts": 3, "maxWallSeconds": 180],
        ]
    }

    private static func event(_ sequence: Int, summary: String, minutesAgo: Double) -> [String: Any] {
        ["id": "event-\(sequence)-\(Int(minutesAgo))", "sequence": sequence, "kind": "demo", "summary": summary,
         "at": iso(minutesAgo: minutesAgo)]
    }

    private static func evidence(_ ref: String, _ tool: String, text: String, minutesAgo: Double, seed: String,
                                 status: String = "read") -> [String: Any] {
        ["sourceRef": ref, "tool": tool, "retrievedAt": iso(minutesAgo: minutesAgo),
         "contentHash": String(repeating: seed, count: 64), "text": text, "status": status, "provenance": "demo"]
    }

    private static func iso(minutesAgo: Double) -> String {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime]
        return format.string(from: Date().addingTimeInterval(-minutesAgo * 60))
    }

    private static func encode(_ payload: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
