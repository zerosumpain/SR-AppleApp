import Foundation

// MARK: - Demo owner lane
//
// `-SRDemo` (and the App Review demo) answers Talk, Chronicle, Inventions and
// whispers from the same made-up valley as the map (`WildmindDemo`): day five
// of the third life, spring, JKai walking up to Heron Lake, Wren at work by the
// hearth, a fire drill and a reed basket invented, three ideas refused. Every
// word here is written for the demo; the repository is public.
//
// Whispers are live in the demo: a POST is kept (in memory, for this launch),
// shows as waiting for two seconds, and is then heard by a thought of JKai's
// that turns up in Talk under it — so the showcase can photograph the whole
// round trip. Foundation only, so the unit tests and the Linux harness run it.

final class WildmindDemoLane: @unchecked Sendable {
    static let shared = WildmindDemoLane()

    /// How long a demo whisper waits before JKai hears it.
    static let hearingDelay: TimeInterval = 2

    private struct Sent {
        let logId: Int
        let text: String
        let at: Date
    }

    private let lock = NSLock()
    private var sent: [Sent] = []

    /// Forget every whisper sent in this launch (tests).
    func reset() {
        lock.lock(); defer { lock.unlock() }
        sent = []
    }

    // MARK: Routes

    /// `parts` from `api/native/wildmind/<route>`; nil is a 404.
    func route(method: String, route: String, query: [String: String], body: Data?, now: Date) -> String? {
        switch (method, route) {
        case ("GET", "talk"): return talk(query: query, now: now)
        case ("GET", "chronicle"): return chronicle(id: query["id"].flatMap { $0.isEmpty ? nil : $0 } ?? "main", now: now)
        case ("GET", "inventions"): return inventions()
        case ("GET", "whispers"): return whispers(limit: Int(query["limit"] ?? "") ?? 20, now: now)
        case ("POST", "whisper"): return whisper(body: body, now: now)
        default: return nil
        }
    }

    // MARK: The valley's words

    static let valley: [String: Any] = ["seed": 7, "generation": 3, "day": 5, "clock": "Day 5, 15:30"]
    /// The valley's minute now: day five, 15:30.
    static let nowMinute = 5 * 1440 + 15 * 60 + 30

    private struct Line {
        let id: Int
        let day: Int
        let hour: Int
        let minute: Int
        let who: String
        let kind: String
        var to: String? = nil
        let text: String
        var detail: String? = nil
        var answers: Int? = nil

        var valleyMinute: Int { day * 1440 + hour * 60 + minute }
        var when: String { String(format: "Day %d, %02d:%02d", day, hour, minute) }
    }

    private static func name(_ who: String?) -> Any {
        switch who {
        case "main"?: return "JKai"
        case "companion"?: return "Wren"
        default: return NSNull()
        }
    }

    /// Two days of the valley, oldest first.
    private static let lines: [Line] = [
        Line(id: 101, day: 4, hour: 7, minute: 10, who: "main", kind: "thought",
             text: "Cold night. The fire drill works, but my hands are raw from it.",
             detail: "Goal: Keep the fire going \u{00B7} Mood: tired"),
        Line(id: 102, day: 4, hour: 7, minute: 25, who: "main", kind: "speech", to: "companion",
             text: "Morning. Did the fire hold for you?"),
        Line(id: 103, day: 4, hour: 7, minute: 26, who: "companion", kind: "speech", to: "main",
             text: "Down to embers. I fed it twice in the night."),
        Line(id: 104, day: 4, hour: 10, minute: 5, who: "companion", kind: "thought",
             text: "The reeds by the water bend without snapping. A basket, maybe.",
             detail: "Goal: Weave something to carry roots in \u{00B7} Mood: curious"),
        Line(id: 105, day: 4, hour: 21, minute: 0, who: "companion", kind: "diary",
             text: "Wren\u{2019}s diary, day 4: Made a basket from lake reeds. It holds roots and lets out hardly any grit. JKai calls it a triumph. I call it a start."),
        Line(id: 106, day: 4, hour: 21, minute: 5, who: "main", kind: "diary",
             text: "JKai\u{2019}s diary, day 4: Wren made a basket. I spent the day failing to make a better fire drill. Tomorrow, the lake, and whatever lives on it."),
        Line(id: 107, day: 5, hour: 5, minute: 40, who: "main", kind: "whisper",
             text: "Ducks on Heron Lake might mean eggs in the reeds."),
        Line(id: 108, day: 5, hour: 6, minute: 10, who: "main", kind: "thought",
             text: "Ducks on the lake. Where there are ducks there may be eggs. Worth a look before the day warms up.",
             detail: "Goal: Look for eggs at Heron Lake \u{00B7} Mood: hopeful", answers: 107),
        Line(id: 109, day: 5, hour: 6, minute: 15, who: "main", kind: "speech", to: "companion",
             text: "I\u{2019}m going up to the lake. Want anything?"),
        Line(id: 110, day: 5, hour: 6, minute: 16, who: "companion", kind: "speech", to: "main",
             text: "More reeds, if you can carry them. Mind the soft ground by the marsh."),
        Line(id: 111, day: 5, hour: 9, minute: 30, who: "companion", kind: "thought",
             text: "The store is half full. A second basket would let us carry twice the roots.",
             detail: "Goal: Weave a second basket \u{00B7} Mood: steady"),
        Line(id: 112, day: 5, hour: 12, minute: 5, who: "main", kind: "speech",
             text: "Raven Fells look closer from up here than they are."),
        Line(id: 113, day: 5, hour: 13, minute: 20, who: "main", kind: "thought",
             text: "Three eggs. Small, but food. The marsh is softer than it looks, so I\u{2019}ll go round it.",
             detail: "Goal: Carry the eggs back whole \u{00B7} Mood: pleased"),
        Line(id: 114, day: 5, hour: 15, minute: 10, who: "companion", kind: "speech", to: "main",
             text: "You\u{2019}re back! What\u{2019}s in the cloth?"),
        Line(id: 115, day: 5, hour: 15, minute: 12, who: "main", kind: "speech", to: "companion",
             text: "Eggs. Three. And your reeds, mostly dry."),
        Line(id: 116, day: 5, hour: 15, minute: 25, who: "companion", kind: "thought",
             text: "He remembered the reeds. That counts for something.",
             detail: "Goal: Finish the second basket before dark \u{00B7} Mood: warm"),
    ]

    /// What JKai thinks on hearing a demo whisper, in turn.
    private static let answers: [(thought: String, goal: String, mood: String)] = [
        ("That voice again, the one from before dawn. It might be right. I\u{2019}ll put it to Wren before I try it.",
         "Talk it over with Wren", "thoughtful"),
        ("Another nudge from nowhere. Fine. I\u{2019}ll look into it once the eggs are safe in the store.",
         "Store the eggs, then look into it", "amused"),
    ]

    private func entry(_ line: Line) -> [String: Any] {
        [
            "id": line.id, "minute": line.valleyMinute, "when": line.when,
            "who": line.who, "name": Self.name(line.who), "kind": line.kind,
            "to": line.to ?? NSNull(), "toName": line.to.map(Self.name) ?? NSNull(),
            "text": line.text, "detail": line.detail ?? NSNull(),
        ]
    }

    /// The fixed lines and this launch's whispers (and their answers, once
    /// heard), oldest first.
    private func everything(now: Date) -> [Line] {
        lock.lock(); let sent = self.sent; lock.unlock()
        var all = Self.lines
        for (index, whisper) in sent.enumerated() {
            all.append(Line(id: whisper.logId, day: 5, hour: 15, minute: 30, who: "main", kind: "whisper", text: whisper.text))
            if now.timeIntervalSince(whisper.at) >= Self.hearingDelay {
                let answer = Self.answers[index % Self.answers.count]
                all.append(Line(id: whisper.logId + 1, day: 5, hour: 15, minute: 31, who: "main", kind: "thought",
                                text: answer.thought, detail: "Goal: \(answer.goal) \u{00B7} Mood: \(answer.mood)",
                                answers: whisper.logId))
            }
        }
        return all.sorted { $0.id < $1.id }
    }

    private func json(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Talk

    private func talk(query: [String: String], now: Date) -> String {
        let limit = max(1, min(200, Int(query["limit"] ?? "") ?? 100))
        let who = query["who"].flatMap { $0.isEmpty ? nil : $0 }
        let kinds = Set((query["kinds"] ?? "").split(separator: ",").map(String.init))
        let matching = everything(now: now).filter { line in
            (who == nil || line.who == who) && (kinds.isEmpty || kinds.contains(line.kind))
        }
        let page: [Line]
        let more: Bool
        if let since = query["since"].flatMap({ Int($0) }) {
            // Newer than `since`, the nearest first taken, then newest first.
            let newer = matching.filter { $0.id > since }
            page = Array(newer.prefix(limit)).reversed()
            more = newer.count > limit
        } else {
            let before = query["before"].flatMap { Int($0) }
            let older = matching.filter { before == nil || $0.id < before! }
            page = Array(older.suffix(limit)).reversed()
            more = older.count > limit
        }
        return json([
            "state": "live", "v": 1, "valley": Self.valley,
            "entries": page.map(entry),
            "oldestId": page.last?.id ?? NSNull(), "latestId": page.first?.id ?? NSNull(),
            "more": more,
        ])
    }

    // MARK: Chronicle

    private func chronicle(id: String, now: Date) -> String? {
        let main = id == "main"
        guard main || id == "companion" else { return nil }
        let who: [String: Any] = main
            ? ["id": "main", "name": "JKai", "alive": true, "causeOfDeath": NSNull(),
               "persona": "JKai (they/them). An engineer at heart: methodical, curious, happiest when a problem gives way to patient hands. Keeps a running list of what to try next."]
            : ["id": "companion", "name": "Wren", "alive": true, "causeOfDeath": NSNull(),
               "persona": "Wren (she/her). Grew up mending nets, so she trusts what she can test with her hands. Practical, dry, and loyal once you have earned it."]
        let heard = everything(now: now).last { $0.who == "main" && $0.kind == "thought" }
        let nowBlock: [String: Any] = main
            ? [
                "lastThought": heard?.text ?? "", "mood": heard.flatMap { WildmindTalkEntry.part("Mood", of: $0.detail) } ?? "pleased",
                "goal": heard.flatMap { WildmindTalkEntry.part("Goal", of: $0.detail) } ?? "Carry the eggs back whole",
                "ambitions": [["text": "Make fire without the drill", "status": "active"],
                              ["text": "Find out what is past Raven Fells", "status": "active"],
                              ["text": "Build a shelter that keeps the rain out", "status": "done"]],
                "values": [["text": "Share what I find", "strength": 60, "since": "Day 2, 09:00", "kept": 4, "broken": 0,
                            "rules": [["effect": "prefer", "verb": "give", "target": "Wren"]]]],
                "attitudes": [["subject": "Heron Lake", "feeling": 40, "reason": "Ducks, reeds and now eggs.", "since": "Day 5, 13:20"]],
                "people": [["name": "Wren", "set": true, "trust": 62, "affection": 55, "note": "Makes things that work the first time.", "partner": false]],
            ]
            : [
                "lastThought": "He remembered the reeds. That counts for something.", "mood": "warm",
                "goal": "Finish the second basket before dark",
                "ambitions": [["text": "Weave a basket that holds water", "status": "active"]],
                "values": [["text": "Test before trusting", "strength": 45, "since": "Day 1, 08:00", "kept": 3, "broken": 1,
                            "rules": [["effect": "prefer", "verb": "experiment", "target": "any"]]]],
                "attitudes": [["subject": "the marsh", "feeling": -20, "reason": "It swallowed a good stick.", "since": "Day 3, 11:00"]],
                "people": [["name": "JKai", "set": true, "trust": 50, "affection": 58, "note": "Talks to the lake, but works hard.", "partner": false]],
            ]
        let events: [(Int, Int, Int, String, String, String)] = main
            ? [
                (5, 15, 12, "social", "\u{1F4AC}", "JKai brought Wren three eggs and her reeds."),
                (5, 13, 20, "food", "\u{1F95A}", "JKai found three duck eggs in the reeds at Heron Lake."),
                (5, 6, 10, "whisper", "\u{1F442}", "JKai heard a whisper about ducks and went to look."),
                (4, 16, 0, "invent", "\u{1F4A1}", "JKai tried to improve the fire drill. The referee said no."),
                (3, 18, 30, "build", "\u{1F3E0}", "JKai finished the shelter by the camp."),
                (2, 11, 0, "invent", "\u{1F4A1}", "JKai invented the fire drill."),
                (1, 7, 0, "explore", "\u{1F9ED}", "JKai found Heron Lake."),
                (0, 17, 0, "start", "\u{1F331}", "JKai\u{2019}s mind woke for the first time."),
            ]
            : [
                (5, 15, 10, "social", "\u{1F4AC}", "Wren welcomed JKai back from the lake."),
                (4, 10, 30, "invent", "\u{1F4A1}", "Wren invented the reed basket."),
                (3, 9, 0, "build", "\u{1F3E0}", "Wren built a store for roots."),
                (1, 7, 30, "explore", "\u{1F9ED}", "Wren found Long Strand."),
                (0, 17, 0, "start", "\u{1F331}", "Wren\u{2019}s mind woke for the first time."),
            ]
        let timeline = events.map { day, hour, minute, kind, icon, text -> [String: Any] in
            ["minute": day * 1440 + hour * 60 + minute, "day": day,
             "when": String(format: "Day %d, %02d:%02d", day, hour, minute), "kind": kind, "icon": icon, "text": text]
        }
        let diary: [[String: Any]] = Self.lines
            .filter { $0.kind == "diary" && $0.who == id }
            .map { ["day": $0.day, "text": $0.text.components(separatedBy: ": ").dropFirst().joined(separator: ": ")] }
            + (main
               ? [["day": 3, "text": "The shelter is up. It leans, but the rain stays out. Wren says it will fall in a week; I say a fortnight."]]
               : [["day": 3, "text": "Built a store for roots. JKai has started naming the rocks."]])
        return json(["state": "live", "v": 1, "valley": Self.valley, "who": who, "now": nowBlock,
                     "timeline": timeline, "diary": diary])
    }

    // MARK: Inventions

    private func inventions() -> String {
        let list: [[String: Any]] = [
            ["id": "reed_basket", "name": "Reed basket", "kind": "container",
             "description": "Green lake reeds woven over a ring of bent willow. Light, and tight enough to carry roots without losing the small ones.",
             "inventor": "Wren", "day": 4, "placed": true,
             "summary": "craft: 12 Reeds, 2 Willow withies; 90 min; capabilities: container (6 slots)",
             "notes": ["Capacity clamped to what reeds hold: six slots, not ten.", "Does not hold water."],
             "rationale": "Reeds bend without snapping when green; a willow ring keeps the mouth open while the weave dries."],
            ["id": "fire_drill", "name": "Fire drill", "kind": "tool",
             "description": "A straight stick spun hard against a notched board until the dust smoulders.",
             "inventor": "JKai", "day": 2, "placed": false,
             "summary": "craft: 1 Straight stick, 1 Dry board; 30 min; capabilities: make fire (slow)",
             "notes": ["Works only with dry wood.", "Slow: about ten minutes of spinning a fire."],
             "rationale": "Friction heats the wood; the notch gathers the hot dust into an ember."],
        ]
        let refused: [[String: String]] = [
            ["when": "Day 4, 16:00", "text": "JKai\u{2019}s idea \u{201C}Bow drill with a gut string\u{201D} doesn\u{2019}t work out: there is no gut to make the string from yet."],
            ["when": "Day 3, 12:40", "text": "Wren\u{2019}s idea \u{201C}Clay pot\u{201D} doesn\u{2019}t work out: nobody has found clay in this valley."],
            ["when": "Day 1, 19:15", "text": "JKai\u{2019}s idea \u{201C}Stone boat\u{201D} doesn\u{2019}t work out: stone does not float."],
        ]
        return json(["state": "live", "v": 1, "valley": Self.valley, "inventions": list, "refused": refused])
    }

    // MARK: Whispers

    private func whispers(limit: Int, now: Date) -> String {
        lock.lock(); let sent = self.sent; lock.unlock()
        var list: [[String: Any]] = []
        var pending: [String] = []
        for (index, whisper) in sent.enumerated().reversed() {
            let heard = now.timeIntervalSince(whisper.at) >= Self.hearingDelay
            if !heard { pending.insert(whisper.text, at: 0) }
            let answer = Self.answers[index % Self.answers.count]
            list.append([
                "logId": whisper.logId, "when": "Day 5, 15:30", "text": whisper.text,
                "status": heard ? "heard" : "pending",
                "answer": heard
                    ? ["logId": whisper.logId + 1, "when": "Day 5, 15:31", "thought": answer.thought,
                       "goal": answer.goal, "mood": answer.mood] as [String: Any]
                    : NSNull(),
            ])
        }
        list.append([
            "logId": 107, "when": "Day 5, 05:40", "text": "Ducks on Heron Lake might mean eggs in the reeds.",
            "status": "heard",
            "answer": ["logId": 108, "when": "Day 5, 06:10",
                       "thought": "Ducks on the lake. Where there are ducks there may be eggs. Worth a look before the day warms up.",
                       "goal": "Look for eggs at Heron Lake", "mood": "hopeful"] as [String: Any],
        ])
        return json([
            "state": "live", "v": 1, "pending": Array(pending.suffix(2)), "reserveLeftUsd": 0.25,
            "modelAvailable": true, "whispers": Array(list.prefix(max(1, min(50, limit)))),
        ])
    }

    private func whisper(body: Data?, now: Date) -> String? {
        guard let body,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let raw = object["text"] as? String,
              WildmindWhisperText.problem(raw) == nil else { return nil }
        let text = WildmindWhisperText.clean(raw)
        lock.lock()
        let logId = 200 + sent.count * 2
        sent.append(Sent(logId: logId, text: text, at: now))
        let pending = Array(sent.suffix(2).map(\.text))
        lock.unlock()
        return json([
            "v": 1, "ok": true, "logId": logId, "when": "Day 5, 15:30", "pending": pending,
            "dropped": NSNull(), "asleep": false, "modelAvailable": true,
        ])
    }
}
