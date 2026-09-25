#if DEBUG
import Foundation

// MARK: - Demo daydream notes
//
// `-SRDemo` answers for the Noticed card on Today and the Noticed section on
// Health. SYNTHETIC — the repository is public: no names, places, senders,
// amounts or anything else lifted from a real day. Each note is the kind of
// thing the loop writes, about nobody in particular.

extension SRDemoFixtures {

    struct DemoNote {
        let id: String
        let outcome: String
        let channel: String
        let title: String
        let body: String
        let minutesAgo: Double
        var feedback: String? = nil
    }

    static let demoNotes: [DemoNote] = [
        DemoNote(
            id: "demo-note-sleep-walk",
            outcome: "health_plan",
            channel: "health",
            title: "Late nights are shortening the long walk",
            body: "On the four nights this fortnight that ended after 23:30, the next day's walk was about a third shorter and resting heart rate sat 3 bpm higher. The fixed sleep window already in the plan is the lever; this is the evidence it should hold before the long day is added.",
            minutesAgo: 38
        ),
        DemoNote(
            id: "demo-note-hall-light",
            outcome: "suggest",
            channel: "home",
            title: "The hallway light stays on overnight twice a week",
            body: "On two nights in the last seven the hallway light was switched on after midnight and still on at six. A 20-minute auto-off on that one light would cover both, and nothing else in the house follows the same pattern.",
            minutesAgo: 95,
            feedback: "useful"
        ),
        DemoNote(
            id: "demo-note-hrv-caffeine",
            outcome: "correlate",
            channel: "health",
            title: "HRV dips on the days after a late coffee",
            body: "Across the last 30 days, the nights after a coffee logged past 15:00 averaged an HRV 6 ms lower than the rest. Eight days is a small sample, so this is worth watching rather than acting on.",
            minutesAgo: 60 * 5
        ),
        DemoNote(
            id: "demo-note-zone2",
            outcome: "research",
            channel: "health",
            title: "What counts as easy for a 40-minute run",
            body: "The usual guidance puts easy running below the first ventilatory threshold. On the recent runs that sits near 140 bpm, and two of the last five crept above it in the second half.",
            minutesAgo: 60 * 26
        ),
    ]

    static func noteJSON(_ note: DemoNote, clock: DemoClock) -> String {
        """
        {"id": \(s(note.id)), "outcome": \(s(note.outcome)), "channel": \(s(note.channel)), "title": \(s(note.title)), "body": \(s(note.body)), "createdAt": \(s(clock.iso(minutesAgo: note.minutesAgo))), "url": \(s("/jkai/daydreams?note=\(note.id)")), "feedback": \(s(note.feedback))}
        """
    }

    /// The `daydream` block on Today: the latest two, whatever the channel.
    static func todayDaydream(_ clock: DemoClock) -> String {
        let latest = demoNotes.sorted { $0.minutesAgo < $1.minutesAgo }.prefix(2)
        return "{\"notes\": \(list(latest.map { noteJSON($0, clock: clock) }))}"
    }

    /// `GET api/native/daydream?scope=health&limit=5`.
    static func daydreamFeed(scope: String?, limit: Int, clock: DemoClock) -> String {
        let notes = demoNotes
            .filter { scope != "health" || $0.channel == "health" || $0.outcome == "health_plan" }
            .prefix(max(0, limit))
        return "{\"notes\": \(list(notes.map { noteJSON($0, clock: clock) }))}"
    }
}
#endif
