import Foundation

// MARK: - Demo daydream notes
//
// `-SRDemo` (and the App Review demo) answers for the Noticed card on Today,
// the Noticed section on Health, and the Daydream page. SYNTHETIC — the
// repository is public: no names, places, senders, amounts or anything else
// lifted from a real day. Each note is the kind of thing the loop writes,
// about nobody in particular.
//
// The page's read (`?detail=1`) gets every list filled: three notes waiting
// for a call (one with a double-check waiting for your OK), one in motion
// (a double-check re-reading its sources), and two done (one answered, one
// whose report came back) — plus the pipeline counts and the Impact card.

extension SRDemoFixtures {

    struct DemoNote {
        let id: String
        let outcome: String
        let channel: String
        let title: String
        let body: String
        let minutesAgo: Double
        var feedback: String? = nil
        var next: String? = nil
        var sources: [String] = []
        var stage = "decide"
        var bucket = "decide"
        var checkable = true
        /// A double-check in `CommissionDemoFixtures`, by id and state.
        var commissionId: String? = nil
        var commissionState: String? = nil
        /// The ruling on the claim, as the detailed wire sends it (raw JSON).
        var review: String? = nil
        /// "Do it for me", as the detailed wire sends it (raw JSON).
        var act: String? = nil
        /// "Take it further", as the detailed wire sends it (raw JSON).
        var follow: String? = nil
    }

    static let demoNotes: [DemoNote] = [
        DemoNote(
            id: "demo-note-sleep-walk",
            outcome: "health_plan",
            channel: "health",
            title: "Late nights are shortening the long walk",
            body: "On the four nights this fortnight that ended after 23:30, the next day's walk was about a third shorter and resting heart rate sat 3 bpm higher. The fixed sleep window already in the plan is the lever; this is the evidence it should hold before the long day is added.\n\nNext: Keep the 23:00 lights-out for two more weeks before adding the long day.",
            minutesAgo: 38,
            next: "Keep the 23:00 lights-out for two more weeks before adding the long day.",
            sources: ["Your /health summary", "Recent workouts and outings", "Health trend · resting hr · last 14 days"],
            stage: "spotted"
        ),
        DemoNote(
            id: "demo-note-hall-light",
            outcome: "suggest",
            channel: "home",
            title: "The hallway light stays on overnight twice a week",
            body: "On two nights in the last seven the hallway light was switched on after midnight and still on at six. A 20-minute auto-off on that one light would cover both, and nothing else in the house follows the same pattern.\n\nNext: Add a 20-minute auto-off to the hallway light.",
            minutesAgo: 95,
            feedback: "useful",
            next: "Add a 20-minute auto-off to the hallway light.",
            sources: ["Home — history · hallway ceiling", "Home sensors · light"],
            stage: "result",
            bucket: "done",
            follow: #"""
            {"bookingUrl": null, "offers": [
              {"kind": "promote", "state": "offer", "label": "Put it on the build backlog", "cost": "No model call. It waits in the backlog as “Proposed” until you accept it."},
              {"kind": "watch", "state": "offer", "label": "Watch for this instead", "cost": "Setting it up is a few model calls, once. Then it checks on a schedule (every 6 hours unless you say otherwise)."},
              {"kind": "home", "state": "drafted", "label": "Choose what to refresh", "cost": "No model call. Asks Home Assistant to refresh the devices you pick."}],
             "watchDraft": "Tell me when this needs attention: the hallway light is on after midnight.",
             "home": {"found": [{"id": "light.hallway_ceiling", "name": "Hallway ceiling (Hall)"}, {"id": "binary_sensor.hall_motion", "name": "Hall motion (Hall)"}], "refreshed": [], "refreshedAt": null}}
            """#
        ),
        DemoNote(
            id: "demo-note-subscriptions",
            outcome: "money_analysis",
            channel: "money",
            title: "Two music subscriptions have overlapped since spring",
            body: "Both services have billed every month since April, and only one of them shows up in the listening history. Together they cost about twice what either does alone.",
            minutesAgo: 60 * 3,
            next: "Cancel the one used least before it renews next month.",
            sources: ["Bank spend · music services · last 180 days", "Mail (facts, not bodies) · “receipt” · last 60 days"],
            stage: "motion",
            bucket: "motion",
            commissionId: CommissionDemoFixtures.runningId,
            commissionState: "running"
        ),
        DemoNote(
            id: "demo-note-hrv-caffeine",
            outcome: "correlate",
            channel: "health",
            title: "HRV dips on the days after a late coffee",
            body: "Across the last 30 days, the nights after a coffee logged past 15:00 averaged an HRV 6 ms lower than the rest. Eight days is a small sample, so this is worth watching rather than acting on.",
            minutesAgo: 60 * 5,
            sources: ["Health trend · hrv · last 30 days", "Tested a link · caffeine late against hrv"],
            commissionId: CommissionDemoFixtures.awaitingId,
            commissionState: "awaiting_approval"
        ),
        DemoNote(
            id: "demo-note-renewals",
            outcome: "efficiency",
            channel: "mail",
            title: "Three renewals fall in the same week next month",
            body: "The insurance, the breakdown cover and a domain name all renew within five days of each other. Each reminder arrives separately, a fortnight ahead.\n\nNext: Put all three on one diary reminder the week before.",
            minutesAgo: 60 * 9,
            next: "Put all three on one diary reminder the week before.",
            sources: ["Mail (facts, not bodies) · “renewal” · last 30 days", "Your diary · today to 45 days ahead"],
            act: #"{"status": "ready", "label": "Add “Renewals: insurance, breakdown, domain” to your diary on Mon 9 Nov", "doneAt": null}"#
        ),
        DemoNote(
            id: "demo-note-zone2",
            outcome: "research",
            channel: "health",
            title: "What counts as easy for a 40-minute run",
            body: "The usual guidance puts easy running below the first ventilatory threshold. On the recent runs that sits near 140 bpm, and two of the last five crept above it in the second half.",
            minutesAgo: 60 * 26,
            next: "Cap the next three easy runs at 140 bpm and see whether the pace holds.",
            sources: ["Web search · “easy run heart rate threshold”", "Recent workouts and outings"],
            stage: "result",
            bucket: "done",
            commissionId: CommissionDemoFixtures.completedId,
            commissionState: "completed",
            review: #"{"verdict": "holds", "by": "check", "reasoning": "It holds: four of the last ten easy runs went above 140 bpm after 25 minutes, on different days.", "lesson": null}"#,
            follow: #"""
            {"bookingUrl": "https://example.org/run-club", "offers": [
              {"kind": "research", "state": "done", "label": "Research started", "cost": "A brief research run.", "href": "/research/demo-research"},
              {"kind": "message", "state": "drafted", "label": "Message drafted", "cost": "One short model call to draft it. Nothing is sent — you send it yourself."}],
             "message": {"text": "Hello, does the Thursday easy-pace group still meet at 7? I'd like to join next week. Thanks, John", "subject": "Thursday easy run", "whatsapp": "https://wa.me/?text=Hello", "mailto": null, "email": null, "draft": null}}
            """#
        ),
    ]

    /// The note as the plain feed sends it — Today's block and the Health
    /// tab's read. No detail keys: the phone splits the body itself.
    static func noteJSON(_ note: DemoNote, clock: DemoClock) -> String {
        """
        {"id": \(s(note.id)), "outcome": \(s(note.outcome)), "channel": \(s(note.channel)), "title": \(s(note.title)), "body": \(s(note.body)), "createdAt": \(s(clock.iso(minutesAgo: note.minutesAgo))), "url": \(s("/jkai/daydreams?note=\(note.id)")), "feedback": \(s(note.feedback))}
        """
    }

    /// The note as `?detail=1` sends it.
    static func detailedNoteJSON(_ note: DemoNote, clock: DemoClock) -> String {
        let summary = SRDemoFixtures.summary(of: note.body)
        return """
        {"id": \(s(note.id)), "outcome": \(s(note.outcome)), "channel": \(s(note.channel)), "title": \(s(note.title)), "body": \(s(note.body)), "createdAt": \(s(clock.iso(minutesAgo: note.minutesAgo))), "url": \(s("/jkai/daydreams?note=\(note.id)")), "feedback": \(s(note.feedback)), "summary": \(s(summary)), "next": \(s(note.next)), "sources": \(list(note.sources.map { s($0) })), "stage": \(s(note.stage)), "bucket": \(s(note.bucket)), "checkable": \(note.checkable ? "true" : "false"), "commissionId": \(s(note.commissionId)), "commissionState": \(s(note.commissionState)), "review": \(note.review ?? "null"), "act": \(note.act ?? "null"), "follow": \(note.follow ?? "null")}
        """
    }

    /// `POST api/native/daydream/act` — done, or undone, as asked. SYNTHETIC:
    /// the demo writes to no calendar.
    static func daydreamAct(_ body: Data?) -> String {
        let request = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        switch request["op"] as? String {
        case "undo":
            return #"{"ok": true, "status": "undone", "label": "Add “Renewals: insurance, breakdown, domain” to your diary on Mon 9 Nov", "calendar": "Home"}"#
        case "calendar":
            return #"{"ok": true}"#
        default:
            return #"{"ok": true, "status": "done", "label": "Added “Renewals: insurance, breakdown, domain” to your Home calendar on Mon 9 Nov", "calendar": "Home"}"#
        }
    }

    /// `POST api/native/daydream/follow` — SYNTHETIC: the demo starts no run,
    /// writes no backlog and messages no one.
    static func daydreamFollow(_ body: Data?) -> String {
        let request = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        switch request["op"] as? String {
        case "research": return #"{"ok": true, "message": "Research started — a brief run, back in a few minutes.", "href": "/research/demo-research"}"#
        case "watch": return #"{"ok": true, "message": "Watching — it checks every 6 hours.", "href": "/jkai/daydreams/watches"}"#
        default: return #"{"ok": true, "message": "Done."}"#
        }
    }

    /// The body without its closing "Next:" paragraph, as the site sends it.
    static func summary(of body: String) -> String {
        guard let range = body.range(of: "\n\nNext: ", options: .backwards) else { return body }
        return String(body[..<range.lowerBound])
    }

    /// The `daydream` block on Today: the latest two, whatever the channel.
    static func todayDaydream(_ clock: DemoClock) -> String {
        let latest = demoNotes.sorted { $0.minutesAgo < $1.minutesAgo }.prefix(2)
        return "{\"notes\": \(list(latest.map { noteJSON($0, clock: clock) }))}"
    }

    /// `GET api/native/daydream?scope=health&limit=5`, and the page's
    /// `?detail=1&limit=40`.
    static func daydreamFeed(scope: String?, limit: Int, detail: Bool = false, clock: DemoClock) -> String {
        let notes = demoNotes
            .filter { scope != "health" || $0.channel == "health" || $0.outcome == "health_plan" }
            .prefix(max(0, limit))
        guard detail else {
            return "{\"notes\": \(list(notes.map { noteJSON($0, clock: clock) }))}"
        }
        let count = { (bucket: String) in notes.filter { $0.bucket == bucket }.count }
        return """
        {"notes": \(list(notes.map { detailedNoteJSON($0, clock: clock) })), "pipeline": {"decide": \(count("decide")), "motion": \(count("motion")), "done": \(count("done"))}, "impact": \(demoImpact(clock))}
        """
    }

    /// Twelve synthetic weeks, answered better as they go — the shape the
    /// card is for, not anybody's record.
    static func demoImpact(_ clock: DemoClock) -> String {
        let useful = [3, 4, 3, 5, 4, 6, 5, 7, 6, 8, 7, 5]
        let notUseful = [5, 4, 5, 4, 4, 3, 3, 3, 2, 2, 2, 1]
        let undecided = [6, 7, 5, 5, 6, 4, 5, 3, 4, 3, 3, 6]
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: clock.now)?.start ?? clock.now
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: "UTC")
        format.dateFormat = "yyyy-MM-dd"
        let weeks = (0..<12).map { index -> String in
            let start = calendar.date(byAdding: .weekOfYear, value: index - 11, to: thisWeek) ?? thisWeek
            return "{\"start\": \(s(format.string(from: start))), \"useful\": \(useful[index]), \"notUseful\": \(notUseful[index]), \"undecided\": \(undecided[index])}"
        }
        return """
        {"windowDays": 28, "hitRate": 0.72, "previousHitRate": 0.55, "noticed": 46, "rated": 25, "useful": 18, "actedOn": 3, "result": 2, "weeks": \(list(weeks))}
        """
    }
}
