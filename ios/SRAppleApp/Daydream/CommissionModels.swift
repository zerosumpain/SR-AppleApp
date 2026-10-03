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

    /// The state in words — the same words the site uses.
    var label: String { Self.stateLabel(state) }

    static func stateLabel(_ state: String) -> String {
        switch state {
        case "awaiting_approval": return "Waiting for your OK"
        case "deferred": return "Put off for now"
        case "declined": return "Declined"
        case "queued": return "Queued"
        case "running": return "Checking now"
        case "needs_attention": return "Needs you"
        case "completed": return "Report ready"
        case "cancelled": return "Cancelled"
        default: return "In progress"
        }
    }

    /// Where it is on Proposed → Approved → Checking → Report ready, 0…3.
    var step: Int { Self.step(for: state, approved: approvedAt != nil) }

    static func step(for state: String, approved: Bool) -> Int {
        switch state {
        case "awaiting_approval", "deferred", "declined": return 0
        case "queued": return 1
        case "running", "needs_attention": return 2
        case "completed": return 3
        case "cancelled": return approved ? 2 : 0
        default: return approved ? 1 : 0
        }
    }

    /// The reads this plan makes, in words, in the order it makes them.
    var readLabels: [String] { spec.reads.map { EvidenceSourceLabel.describe(tool: $0.tool, args: $0.args) } }

    /// A source in the report, named as the plan named it.
    func label(for evidence: CommissionEvidence) -> String {
        if let read = spec.reads.first(where: { $0.sourceRef == evidence.sourceRef }) {
            return EvidenceSourceLabel.describe(tool: read.tool, args: read.args)
        }
        return EvidenceSourceLabel.describe(tool: evidence.tool, args: .null)
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
struct CommissionBudget: Decodable, Hashable {
    let maxReads: Int
    let maxAttempts: Int
    let maxWallSeconds: Int

    /// The budget, as the three things it means to the person signing off.
    var plainLimits: [String] {
        let lookups = maxReads == 1 ? "1 look-up, nothing else" : "\(maxReads) look-ups, nothing else"
        let tries = maxAttempts == 1 ? "1 try" : "Up to \(maxAttempts) tries"
        return [lookups, "\(tries), \(Self.duration(maxWallSeconds)) each", "Carries on if you close the app"]
    }

    static func duration(_ seconds: Int) -> String {
        if seconds >= 60, seconds % 60 == 0 {
            let minutes = seconds / 60
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }
        return seconds == 1 ? "1 second" : "\(seconds) seconds"
    }
}
struct EvidenceRead: Decodable, Hashable { let sourceRef: String; let tool: String; let args: JSONValue }
struct EvidenceReport: Decodable, Hashable {
    let summary: String
    let evidence: [CommissionEvidence]
    /// The double-check's verdict after arguing against the note. Absent on a
    /// report written before it existed, `null` when it could not run — and a
    /// verdict of the wrong shape costs only itself, never the report.
    let review: CommissionReview?

    init(summary: String, evidence: [CommissionEvidence], review: CommissionReview? = nil) {
        self.summary = summary
        self.evidence = evidence
        self.review = review
    }

    enum CodingKeys: String, CodingKey { case summary, evidence, review }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = try c.decode(String.self, forKey: .summary)
        evidence = try c.decode([CommissionEvidence].self, forKey: .evidence)
        review = c.lenient(CommissionReview.self, .review)
    }
}
struct CommissionEvidence: Decodable, Hashable {
    let sourceRef: String
    let tool: String
    let retrievedAt: String
    let contentHash: String
    let text: String
    let status: String
    let provenance: String

    /// Whether the source answered. Anything but a read is "could not be
    /// reached" — the report says so rather than guessing.
    /// The site writes `available` / `unavailable`.
    var wasRead: Bool { ["available", "read", "ok", "fresh", "retrieved"].contains(status.lowercased()) }
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

/// A source read, in words: `spend {merchant: "Canva", days: 60}` is "Bank
/// spend · Canva · last 60 days". The same wording the site's sign-off page
/// uses, so a plan reads the same on both. Argument names follow the
/// daydream's tool schemas (`src/lib/daydream/think/tools.ts` in SR-Main);
/// anything missing is left out rather than guessed.
enum EvidenceSourceLabel {
    static func describe(tool: String, args: JSONValue) -> String {
        func text(_ keys: String...) -> String? {
            for key in keys {
                if let value = args[key]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { return value }
                if let value = args[key]?.number { return value.rounded() == value ? String(Int(value)) : String(value) }
            }
            return nil
        }
        func days(_ keys: String..., fallback: Int) -> Int {
            for key in keys {
                if let value = args[key]?.number, value.isFinite, value > 0 { return Int(value.rounded()) }
                if let value = args[key]?.string, let parsed = Int(value), parsed > 0 { return parsed }
            }
            return fallback
        }
        func list(_ key: String) -> [String] {
            if let one = args[key]?.string, !one.isEmpty { return [one] }
            return (args[key]?.array ?? []).compactMap { $0.string }.filter { !$0.isEmpty }
        }
        func join(_ parts: [String?]) -> String { parts.compactMap { $0 }.joined(separator: " · ") }
        func lastDays(_ n: Int) -> String { n == 1 ? "last day" : "last \(n) days" }
        func quoted(_ value: String?) -> String? { value.map { "\u{201C}\($0)\u{201D}" } }

        switch tool {
        case "spend":
            return join(["Bank spend", text("merchant"), lastDays(days("days", fallback: 60))])
        case "mail_facts":
            return join(["Mail (facts, not bodies)", quoted(text("query")), lastDays(days("daysBack", "days", fallback: 14))])
        case "diary":
            return "Your diary · \(dayWords(text("from") ?? "today")) to \(dayWords(text("to") ?? "+14d"))"
        case "chat_threads":
            return join(["Your jkai chats", lastDays(days("days", fallback: 14))])
        case "activities":
            return "Recent workouts and outings"
        case "health_hub":
            return "Your /health summary"
        case "health_series":
            return join(["Health trend", text("metric").map(words), lastDays(days("days", fallback: 28))])
        case "correlate":
            let a = text("a").map(words) ?? "one measure"
            let b = text("b").map(words) ?? "another"
            return "Tested a link · \(a) against \(b)"
        case "ha_find":
            let scope = list("domain") + list("domains") + list("area") + list("areas")
            if !scope.isEmpty { return "Home sensors · " + scope.map(words).joined(separator: ", ") }
            return join(["Home sensors", quoted(text("query"))])
        case "ha_query_state":
            return join(["Home \u{2014} current state", text("entity_id", "entityId").map(entityTail)])
        case "ha_get_history":
            return join(["Home \u{2014} history", text("entity_id", "entityId").map(entityTail)])
        case "memory_search":
            return "jkai memory"
        case "research_web_search":
            return join(["Web search", quoted(text("query", "q"))])
        case "fetch_url":
            let host = text("url").flatMap { URL(string: $0)?.host }
            return join(["Web page", host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }])
        default:
            let plain = words(tool)
            return plain.isEmpty ? "A source" : plain.prefix(1).uppercased() + plain.dropFirst()
        }
    }

    /// `resting_hr` → "resting hr".
    static func words(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// `light.hallway_ceiling` → "hallway ceiling".
    static func entityTail(_ id: String) -> String {
        let tail = id.split(separator: ".", maxSplits: 1).last.map(String.init) ?? id
        return words(tail)
    }

    /// The diary's relative forms: "-7d" → "7 days ago", "+14d" → "14 days
    /// ahead". A date is left as written.
    static func dayWords(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3, trimmed.hasSuffix("d"), let sign = trimmed.first, sign == "+" || sign == "-",
              let n = Int(trimmed.dropFirst().dropLast()) else { return trimmed }
        let unit = n == 1 ? "day" : "days"
        if n == 0 { return "today" }
        return sign == "-" ? "\(n) \(unit) ago" : "\(n) \(unit) ahead"
    }
}
