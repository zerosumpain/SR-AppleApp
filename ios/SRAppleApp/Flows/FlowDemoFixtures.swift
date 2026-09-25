#if DEBUG
import Foundation

// MARK: - Demo workflows
//
// `-SRDemo` answers for `/api/native/workflows/*`. Synthetic throughout — the
// repository is public. Five workflows, one needing attention with a fix
// proposal waiting; the morning brief has a condition with two arms that meet
// again, so the steps list shows a branch.

extension SRDemoFixtures {

    static func flowRoute(method: String, parts: [String], body: Data?, clock: DemoClock) -> String? {
        // parts: ["api", "native", "workflows", ...]
        let rest = Array(parts.dropFirst(3))
        switch (method, rest.count) {
        case ("GET", 0):
            return flowList(clock)
        case ("POST", 0):
            return #"{"slug": "demo-new", "building": false}"#
        case ("GET", 1) where rest[0] == "node-types":
            return flowCatalogue
        case ("GET", 1):
            return flowDetail(slug: rest[0], clock: clock)
        case ("PATCH", 1), ("DELETE", 1):
            return #"{"ok": true}"#
        case ("GET", 2) where rest[0] == "runs":
            return flowRunDetail(runId: rest[1], clock: clock)
        case ("GET", 2) where rest[1] == "runs":
            return "{\"runs\": \(list(demoRuns(slug: rest[0], clock: clock)))}"
        case ("PUT", 2) where rest[1] == "trigger":
            return #"{"ok": true}"#
        case ("POST", 2) where rest[1] == "run":
            return #"{"runId": "demo-run-live"}"#
        case ("POST", 2) where rest[1] == "amend":
            return #"{"version": 8, "outcomes": [{"op": "update_node", "summary": "updated node \"Write the brief\""}]}"#
        case ("POST", 2) where rest[1] == "ask":
            return flowProposal
        case ("GET", 2) where rest[1] == "fix-proposals":
            return "{\"proposals\": []}"
        case ("POST", 3) where rest[1] == "fix-proposals":
            return #"{"ok": true}"#
        default:
            return nil
        }
    }

    struct DemoFlow {
        let slug: String
        let title: String
        let description: String?
        let trigger: String
        let nodeCount: Int
        let lastStatus: String?
        let lastMinutesAgo: Double
        let attention: String?
        let updatedMinutesAgo: Double
    }

    static func cronTrigger(_ cron: String, _ description: String, enabled: Bool, clock: DemoClock, firstIn: Double) -> String {
        let next = enabled ? [firstIn, firstIn + 60 * 24, firstIn + 60 * 48].map { s(clock.iso(minutesAgo: -$0)) } : []
        return """
        {"kind": "cron", "cron": \(s(cron)), "timezone": "Europe/London", "enabled": \(b(enabled)), "description": \(s(description)), "nextRuns": \(list(next))}
        """
    }

    static func demoFlows(_ clock: DemoClock) -> [DemoFlow] {
        [
            DemoFlow(slug: "inbox-triage", title: "Inbox triage",
                     description: "Sort new mail into reply-today, read-later and receipts.",
                     trigger: #"{"kind": "gmail", "cron": null, "timezone": null, "enabled": true, "description": "When a new email arrives in the inbox", "nextRuns": []}"#,
                     nodeCount: 5, lastStatus: "failed", lastMinutesAgo: 22,
                     attention: "The last 3 runs failed at “Label the thread”.", updatedMinutesAgo: 60 * 26),
            DemoFlow(slug: "morning-brief", title: "Morning brief",
                     description: "Calendar and weather, written up and sent before the day starts.",
                     trigger: cronTrigger("0 7 * * 1-5", "Weekdays at 07:00 (Europe/London)", enabled: true, clock: clock, firstIn: 60 * 14),
                     nodeCount: 7, lastStatus: "completed", lastMinutesAgo: 60 * 9, attention: nil, updatedMinutesAgo: 60 * 3),
            DemoFlow(slug: "weekly-review", title: "Weekly review",
                     description: "Training load, reading and open threads for the week, as one note.",
                     trigger: cronTrigger("0 18 * * 0", "Sundays at 18:00 (Europe/London)", enabled: false, clock: clock, firstIn: 60 * 50),
                     nodeCount: 4, lastStatus: "completed", lastMinutesAgo: 60 * 24 * 5, attention: nil, updatedMinutesAgo: 60 * 24 * 2),
            DemoFlow(slug: "garden-lights", title: "Garden lights at dusk",
                     description: nil,
                     trigger: #"{"kind": "webhook", "cron": null, "timezone": null, "enabled": true, "description": "When the sunset webhook is called", "nextRuns": []}"#,
                     nodeCount: 3, lastStatus: "completed", lastMinutesAgo: 60 * 20, attention: nil, updatedMinutesAgo: 60 * 24 * 9),
            DemoFlow(slug: "share-a-run", title: "Share a run",
                     description: "Post the latest activity's map and splits to the family thread.",
                     trigger: #"{"kind": "manual", "cron": null, "timezone": null, "enabled": true, "description": "When you start it", "nextRuns": []}"#,
                     nodeCount: 4, lastStatus: nil, lastMinutesAgo: 0, attention: nil, updatedMinutesAgo: 60 * 24 * 14),
        ]
    }

    static func runJSON(id: String, status: String, trigger: String, minutesAgo: Double, durationMs: Double?, error: String?, clock: DemoClock) -> String {
        let done = status == "running" ? "null" : s(clock.iso(minutesAgo: minutesAgo - (durationMs ?? 0) / 60_000))
        return """
        {"id": \(s(id)), "status": \(s(status)), "trigger": \(s(trigger)), "startedAt": \(s(clock.iso(minutesAgo: minutesAgo))), "completedAt": \(done), "durationMs": \(n(durationMs)), "error": \(s(error))}
        """
    }

    static func flowList(_ clock: DemoClock) -> String {
        let rows = demoFlows(clock).map { flow -> String in
            let last = flow.lastStatus.map {
                runJSON(id: "demo-run-\(flow.slug)", status: $0, trigger: "schedule", minutesAgo: flow.lastMinutesAgo,
                        durationMs: 8_400, error: $0 == "failed" ? "Gmail refused the request: token expired." : nil, clock: clock)
            } ?? "null"
            return """
            {"slug": \(s(flow.slug)), "title": \(s(flow.title)), "description": \(s(flow.description)), "trigger": \(flow.trigger), "nodeCount": \(flow.nodeCount), "lastRun": \(last), "needsAttention": \(b(flow.attention != nil)), "attentionReason": \(s(flow.attention)), "updatedAt": \(s(clock.iso(minutesAgo: flow.updatedMinutesAgo)))}
            """
        }
        return "{\"workflows\": \(list(rows))}"
    }

    static func demoRuns(slug: String, clock: DemoClock) -> [String] {
        if slug == "inbox-triage" {
            return [
                runJSON(id: "demo-run-inbox-1", status: "failed", trigger: "gmail", minutesAgo: 22, durationMs: 3_100, error: "Label the thread: Gmail refused the request (token expired).", clock: clock),
                runJSON(id: "demo-run-inbox-2", status: "failed", trigger: "gmail", minutesAgo: 95, durationMs: 2_950, error: "Label the thread: Gmail refused the request (token expired).", clock: clock),
                runJSON(id: "demo-run-inbox-3", status: "completed", trigger: "gmail", minutesAgo: 60 * 5, durationMs: 6_200, error: nil, clock: clock),
            ]
        }
        return [
            runJSON(id: "demo-run-brief-1", status: "completed", trigger: "schedule", minutesAgo: 60 * 9, durationMs: 14_820, error: nil, clock: clock),
            runJSON(id: "demo-run-brief-2", status: "completed", trigger: "schedule", minutesAgo: 60 * 33, durationMs: 12_400, error: nil, clock: clock),
            runJSON(id: "demo-run-brief-3", status: "completed", trigger: "manual", minutesAgo: 60 * 50, durationMs: 16_050, error: nil, clock: clock),
        ]
    }

    static let briefForm = """
    [
      {"key": "prompt", "label": "Instructions", "kind": "template", "placeholder": "What should the model write?", "help": "Plain English. The calendar and weather arrive as the input.", "advanced": false, "section": "Prompt"},
      {"key": "model", "label": "Model", "kind": "dropdown", "options": [{"value": "auto", "label": "Workload default"}, {"value": "fast", "label": "Fast and cheap"}, {"value": "deep", "label": "Careful"}], "advanced": false, "section": "Model"},
      {"key": "temperature", "label": "Temperature", "kind": "number", "min": 0, "max": 1, "step": 0.1, "advanced": false, "section": "Model"},
      {"key": "includeWeather", "label": "Mention the weather", "kind": "toggle", "advanced": false, "section": "Model"},
      {"key": "tags", "label": "Tags", "kind": "chips", "advanced": false, "section": "Model"},
      {"key": "maxTokens", "label": "Longest answer (tokens)", "kind": "number", "min": 100, "max": 4000, "step": 100, "advanced": true},
      {"key": "responseSchema", "label": "Response shape", "kind": "json", "advanced": true},
      {"key": "styleHint", "label": "Style hint", "kind": "sparkle-slider", "advanced": true}
    ]
    """

    static func flowDetail(slug: String, clock: DemoClock) -> String {
        let flows = demoFlows(clock)
        guard let flow = flows.first(where: { $0.slug == slug }) else {
            // A blank one, as "New → Blank" would make it.
            return """
            {"slug": \(s(slug)), "title": "New workflow", "description": null, "version": 1, "trigger": {"kind": "manual", "enabled": true, "description": "When you start it", "nextRuns": []}, "building": false, "buildError": null, "steps": [{"id": "start", "type": "manual-trigger", "label": "Start", "category": "trigger", "icon": null, "summary": "When you start it", "config": {}, "form": [], "next": [], "legacy": false}], "edges": [], "recentRuns": [], "fixProposals": []}
            """
        }
        let runs = list(demoRuns(slug: slug, clock: clock))
        if slug == "inbox-triage" {
            return """
            {"slug": "inbox-triage", "title": \(s(flow.title)), "description": \(s(flow.description)), "version": 12, "trigger": \(flow.trigger), "building": false, "buildError": null,
             "steps": [
               {"id": "mail", "type": "gmail-trigger", "label": "New email", "category": "trigger", "icon": "mail", "summary": "Inbox, not from me", "config": {"label": "INBOX"}, "form": [], "next": [{"handle": null, "targetId": "classify"}], "legacy": false},
               {"id": "classify", "type": "llm", "label": "Classify it", "category": "ai", "icon": null, "summary": "reply-today / read-later / receipt", "config": {"prompt": "Classify this email."}, "form": [], "next": [{"handle": null, "targetId": "label"}], "legacy": false},
               {"id": "label", "type": "gmail-label", "label": "Label the thread", "category": "integration", "icon": null, "summary": "Adds the class as a Gmail label", "config": {"labelPrefix": "sr/"}, "form": [{"key": "labelPrefix", "label": "Label prefix", "kind": "text", "advanced": false}], "next": [], "legacy": true}
             ],
             "edges": [{"id": "e1", "source": "mail", "target": "classify", "sourceHandle": null}, {"id": "e2", "source": "classify", "target": "label", "sourceHandle": null}],
             "recentRuns": \(runs),
             "fixProposals": [{"id": "demo-fix-1", "nodeId": "label", "nodeLabel": "Label the thread", "description": "Retry with the refreshed Gmail connection and create the label if it is missing. The retry succeeded.", "createdAt": \(s(clock.iso(minutesAgo: 21))), "runId": "demo-run-inbox-1"}]}
            """
        }
        // The morning brief — and, for the other demo slugs, the same shape.
        let config = """
        {"prompt": "Write me a short brief for the day from {{calendar.events}} and {{weather.summary}}. Lead with anything before nine.", "model": "auto", "temperature": 0.4, "includeWeather": true, "tags": ["brief", "morning"], "maxTokens": 600, "responseSchema": {"type": "object", "properties": {"text": {"type": "string"}}}}
        """
        return """
        {"slug": \(s(flow.slug)), "title": \(s(flow.title)), "description": \(s(flow.description)), "version": 7, "trigger": \(flow.trigger), "building": false, "buildError": null,
         "steps": [
           {"id": "t", "type": "cron-trigger", "label": "Weekday mornings", "category": "trigger", "icon": "clock", "summary": "07:00 Mon–Fri", "config": {}, "form": [], "next": [{"handle": null, "targetId": "calendar"}], "legacy": false},
           {"id": "calendar", "type": "google-calendar", "label": "Read today’s calendar", "category": "integration", "icon": null, "summary": "Primary calendar, today", "config": {"range": "today"}, "form": [{"key": "range", "label": "Range", "kind": "dropdown", "options": ["today", "tomorrow", "week"], "advanced": false}], "next": [{"handle": null, "targetId": "weather"}], "legacy": false},
           {"id": "weather", "type": "http-request", "label": "Fetch the weather", "category": "integration", "icon": null, "summary": "GET the forecast", "config": {"url": "https://example.test/forecast", "method": "GET"}, "form": [{"key": "url", "label": "URL", "kind": "text", "advanced": false}, {"key": "headers", "label": "Headers", "kind": "json", "advanced": true}], "next": [{"handle": null, "targetId": "check"}], "legacy": false},
           {"id": "check", "type": "condition", "label": "Anything before nine?", "category": "logic", "icon": null, "summary": "first event starts before 09:00", "config": {"expression": "calendar.first.start < '09:00'"}, "form": [{"key": "expression", "label": "Condition", "kind": "code", "advanced": false}], "next": [{"handle": "true", "targetId": "early"}, {"handle": "false", "targetId": "brief"}], "legacy": false},
           {"id": "early", "type": "llm", "label": "Early warning", "category": "ai", "icon": null, "summary": "Two lines: what, where, when to leave", "config": {"prompt": "Two lines on the first event.", "model": "fast"}, "form": \(briefForm), "next": [{"handle": null, "targetId": "send"}], "legacy": false},
           {"id": "brief", "type": "llm", "label": "Write the brief", "category": "ai", "icon": null, "summary": "One paragraph, plain English", "config": \(config), "form": \(briefForm), "next": [{"handle": null, "targetId": "send"}], "legacy": false},
           {"id": "send", "type": "whatsapp", "label": "WhatsApp me", "category": "output", "icon": null, "summary": "To the owner", "config": {"to": "owner"}, "form": [{"key": "to", "label": "To", "kind": "phone", "advanced": false}], "next": [], "legacy": false}
         ],
         "edges": [
           {"id": "e1", "source": "t", "target": "calendar", "sourceHandle": null},
           {"id": "e2", "source": "calendar", "target": "weather", "sourceHandle": null},
           {"id": "e3", "source": "weather", "target": "check", "sourceHandle": null},
           {"id": "e4", "source": "check", "target": "early", "sourceHandle": "true"},
           {"id": "e5", "source": "check", "target": "brief", "sourceHandle": "false"},
           {"id": "e6", "source": "early", "target": "send", "sourceHandle": null},
           {"id": "e7", "source": "brief", "target": "send", "sourceHandle": null}
         ],
         "recentRuns": \(runs),
         "fixProposals": []}
        """
    }

    static func flowRunDetail(runId: String, clock: DemoClock) -> String? {
        let failed = runId.hasPrefix("demo-run-inbox")
        if failed {
            return """
            {"run": \(runJSON(id: runId, status: "failed", trigger: "gmail", minutesAgo: 22, durationMs: 3_100, error: "Label the thread: Gmail refused the request (token expired).", clock: clock)),
             "steps": [
               {"nodeId": "mail", "label": "New email", "type": "gmail-trigger", "status": "completed", "startedAt": \(s(clock.iso(minutesAgo: 22))), "durationMs": 40, "error": null, "output": "{\\n  \\"subject\\": \\"Your order has shipped\\",\\n  \\"from\\": \\"shop@example.test\\"\\n}", "rows": null},
               {"nodeId": "classify", "label": "Classify it", "type": "llm", "status": "completed", "startedAt": \(s(clock.iso(minutesAgo: 22))), "durationMs": 2410, "error": null, "output": "\\"receipt\\"", "rows": null},
               {"nodeId": "label", "label": "Label the thread", "type": "gmail-label", "status": "failed", "startedAt": \(s(clock.iso(minutesAgo: 21.9))), "durationMs": 650, "error": "Gmail refused the request (token expired).", "output": null, "rows": null}
             ]}
            """
        }
        let live = runId == "demo-run-live"
        return """
        {"run": \(runJSON(id: runId, status: "completed", trigger: live ? "manual" : "schedule", minutesAgo: live ? 0.3 : 60 * 9, durationMs: 14_820, error: nil, clock: clock)),
         "steps": [
           {"nodeId": "t", "label": "Weekday mornings", "type": "cron-trigger", "status": "completed", "startedAt": \(s(clock.iso(minutesAgo: 60 * 9))), "durationMs": 12, "error": null, "output": null, "rows": null},
           {"nodeId": "calendar", "label": "Read today’s calendar", "type": "google-calendar", "status": "completed", "startedAt": \(s(clock.iso(minutesAgo: 60 * 9))), "durationMs": 820, "error": null, "output": "[\\n  {\\"title\\": \\"Design review\\", \\"start\\": \\"08:30\\"},\\n  {\\"title\\": \\"Long run\\", \\"start\\": \\"18:00\\"}\\n]", "rows": 2},
           {"nodeId": "weather", "label": "Fetch the weather", "type": "http-request", "status": "completed", "startedAt": \(s(clock.iso(minutesAgo: 60 * 9))), "durationMs": 310, "error": null, "output": "{\\"summary\\": \\"Dry, 14°, light wind\\"}", "rows": null},
           {"nodeId": "check", "label": "Anything before nine?", "type": "condition", "status": "completed", "startedAt": \(s(clock.iso(minutesAgo: 60 * 9))), "durationMs": 3, "error": null, "output": "true", "rows": null},
           {"nodeId": "early", "label": "Early warning", "type": "llm", "status": "completed", "startedAt": \(s(clock.iso(minutesAgo: 60 * 9))), "durationMs": 11800, "error": null, "output": "\\"Design review at 08:30 — leave by 08:05. Dry, 14°.\\"", "rows": null},
           {"nodeId": "send", "label": "WhatsApp me", "type": "whatsapp", "status": "completed", "startedAt": \(s(clock.iso(minutesAgo: 60 * 9))), "durationMs": 1870, "error": null, "output": "{\\"sent\\": true}", "rows": null}
         ]}
        """
    }

    static let flowCatalogue = """
    {"categories": [
      {"id": "ai", "label": "AI", "types": [
        {"type": "llm", "label": "Ask a model", "description": "Write, summarise or classify with the workload's model.", "icon": "sparkles", "defaultConfig": {"prompt": ""}, "form": []},
        {"type": "llm-agent", "label": "Agent with tools", "description": "A model that can call site tools until it is done.", "icon": null, "defaultConfig": {}, "form": []}
      ]},
      {"id": "logic", "label": "Logic", "types": [
        {"type": "condition", "label": "Condition", "description": "Branch on true or false.", "icon": null, "defaultConfig": {"expression": ""}, "form": []},
        {"type": "delay", "label": "Wait", "description": "Pause for a while before carrying on.", "icon": null, "defaultConfig": {"seconds": 60}, "form": []}
      ]},
      {"id": "output", "label": "Send", "types": [
        {"type": "whatsapp", "label": "WhatsApp", "description": "Message the owner or a saved contact.", "icon": null, "defaultConfig": {"to": "owner"}, "form": []},
        {"type": "notify-owner", "label": "Tell me", "description": "Raise a notification on the phone and the site.", "icon": null, "defaultConfig": {}, "form": []}
      ]},
      {"id": "integration", "label": "Integrations", "types": [
        {"type": "http-request", "label": "HTTP request", "description": "Call a URL and keep the answer.", "icon": null, "defaultConfig": {"method": "GET"}, "form": []}
      ]}
    ]}
    """

    static let flowProposal = """
    {"summary": "Send the brief at 06:45 on Mondays too, and add a line about the first train when there is an early meeting.",
     "ops": [
       {"op": "update_node", "nodeId": "early", "config": {"prompt": "Two lines on the first event, and the first train that gets there in time."}},
       {"op": "insert_between", "sourceNodeId": "early", "targetNodeId": "send", "type": "http-request", "label": "Check the trains", "config": {"method": "GET"}}
     ],
     "warnings": ["The trains step needs a departure board URL before it can run."]}
    """
}
#endif
