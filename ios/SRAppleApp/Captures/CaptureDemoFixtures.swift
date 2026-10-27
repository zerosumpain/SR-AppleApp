import Foundation

// Captures in demo mode (`-SRDemo`, and the review demo): a short list, one
// capture read in full with two speakers, follow-ups in every state, a
// search and an entity page. Synthetic throughout — Alex, Sam and Robin,
// Central Park — like every other fixture. Shapes are the CONTRACT's, and
// `CaptureDemoTests` decodes each against the real models.

extension SRDemoFixtures {
    static func capturesRoute(method: String, parts: [String], query: [String: String], body: Data?, clock: DemoClock) -> String? {
        // parts: api, native, captures, …
        let rest = Array(parts.dropFirst(3))
        switch (method, rest.count) {
        case ("GET", 0):
            return captureList(clock)
        case ("POST", 0):
            return #"{"id":"cap_demo_new","uploadAudio":"/api/native/captures/cap_demo_new/audio","uploadScreen":"/api/native/captures/cap_demo_new/screen"}"#
        default:
            break
        }
        if rest.first == "search", method == "GET" {
            return captureSearch(query["q"] ?? "", person: query["person"], app: query["app"], clock: clock)
        }
        if rest.first == "entities", rest.count == 2, method == "GET" {
            return captureEntity(rest[1], clock: clock)
        }
        guard let id = rest.first else { return nil }
        if rest.count == 2, rest[1] == "audio" || rest[1] == "screen" {
            // The PUTs answer 204 on the site; any 2xx will do. A GET of the
            // bytes has nothing to play in a demo.
            return method == "PUT" ? "{}" : nil
        }
        if rest.count == 3, rest[1] == "actions", method == "POST" {
            return captureDecision(id: id, actionId: rest[2], body: body, clock: clock)
        }
        guard rest.count == 1 else { return nil }
        switch method {
        case "GET": return captureDetail(id, confirmed: [:], clock: clock)
        case "PATCH": return captureDetail(id, confirmed: confirmations(body), clock: clock)
        case "DELETE": return "{}"
        default: return nil
        }
    }

    private struct DemoCapture {
        let id: String
        let title: String
        let minutesAgo: Double
        let duration: Double
        let app: String?
        let speakers: [String]
        let open: Int
        let snippet: String
        let status: String
    }

    private static let demoCaptures: [DemoCapture] = [
        DemoCapture(id: "cap_demo_park", title: "Saturday in the park", minutesAgo: 42, duration: 247, app: "Calendar",
                    speakers: ["You", "Sam"], open: 2, snippet: "Thanks Sam — can you send the plan by Friday?", status: "ready"),
        DemoCapture(id: "cap_demo_idea", title: "Idea: a bird feeder log", minutesAgo: 190, duration: 38, app: nil,
                    speakers: ["You"], open: 1, snippet: "Count what visits the feeder each morning and chart it.", status: "ready"),
        DemoCapture(id: "cap_demo_call", title: "", minutesAgo: 3, duration: 95, app: "WhatsApp",
                    speakers: [], open: 0, snippet: "", status: "analysing"),
        DemoCapture(id: "cap_demo_robin", title: "Robin's school trip", minutesAgo: 60 * 26, duration: 412, app: "Mail",
                    speakers: ["You", "Robin", "Alex"], open: 0, snippet: "The coach leaves at eight, so we need to be there by quarter to.", status: "ready"),
    ]

    private static func summaryJSON(_ c: DemoCapture, clock: DemoClock, score: Double? = nil) -> String {
        """
        {"id":\(s(c.id)),"title":\(s(c.title)),"startedAt":\(s(clock.iso(minutesAgo: c.minutesAgo))),\
        "durationS":\(n(c.duration)),"status":\(s(c.status)),"app":\(s(c.app)),\
        "speakers":[\(c.speakers.map { s($0) }.joined(separator: ","))],"actionsOpen":\(c.open),\
        "snippet":\(s(c.snippet))\(score.map { ",\"score\":\(n($0))" } ?? "")}
        """
    }

    static func captureList(_ clock: DemoClock) -> String {
        let ordered = demoCaptures.sorted { $0.minutesAgo < $1.minutesAgo }
        return #"{"items":["# + ordered.map { summaryJSON($0, clock: clock) }.joined(separator: ",") + "]}"
    }

    static func captureSearch(_ q: String, person: String?, app: String?, clock: DemoClock) -> String {
        let needle = q.lowercased()
        let hits = demoCaptures.filter { c in
            (needle.isEmpty || c.title.lowercased().contains(needle) || c.snippet.lowercased().contains(needle))
                && (person.map { c.speakers.contains($0) } ?? true)
                && (app.map { c.app == $0 } ?? true)
        }
        let entities = needle.isEmpty || "sam".contains(needle) || needle.contains("sam")
            ? #"[{"id":"ent_demo_sam","name":"Sam","type":"person","captureCount":2},{"id":"ent_demo_park","name":"Central Park","type":"place","captureCount":1}]"#
            : "[]"
        return #"{"captures":["# + hits.map { summaryJSON($0, clock: clock, score: 0.8) }.joined(separator: ",")
            + #"],"entities":"# + entities + "}"
    }

    static func captureEntity(_ id: String, clock: DemoClock) -> String {
        let park = id == "ent_demo_park"
        let entity = park
            ? #"{"id":"ent_demo_park","name":"Central Park","type":"place","summary":"Where Saturday's plan starts."}"#
            : #"{"id":"ent_demo_sam","name":"Sam","type":"person","summary":"Plans the Saturday walks. Mentioned in two captures."}"#
        let captures = demoCaptures.filter { park ? $0.id == "cap_demo_park" : $0.speakers.contains("Sam") || $0.id == "cap_demo_robin" }
        let neighbours = park
            ? #"[{"id":"ent_demo_sam","name":"Sam","type":"person","relation":"walks in"}]"#
            : #"[{"id":"ent_demo_park","name":"Central Park","type":"place","relation":"walks in"},{"id":"ent_demo_alex","name":"Alex","type":"person","relation":"family of"}]"#
        return #"{"entity":"# + entity + #","captures":["# + captures.map { summaryJSON($0, clock: clock) }.joined(separator: ",")
            + #"],"neighbours":"# + neighbours + "}"
    }

    /// `{speakers:[{label, confirmed:{name}}]}` from a PATCH body.
    private static func confirmations(_ body: Data?) -> [String: String] {
        guard let body, let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let speakers = object["speakers"] as? [[String: Any]] else { return [:] }
        var out: [String: String] = [:]
        for speaker in speakers {
            if let label = speaker["label"] as? String, let name = (speaker["confirmed"] as? [String: Any])?["name"] as? String {
                out[label] = name
            }
        }
        return out
    }

    static func captureDetail(_ id: String, confirmed: [String: String], clock: DemoClock) -> String {
        let c = demoCaptures.first { $0.id == id } ?? demoCaptures[0]
        let started = clock.date(minutesAgo: c.minutesAgo)
        let ended = started.addingTimeInterval(c.duration)
        let s2Confirmed = confirmed["S2"].map { #"{"name":"# + s($0) + "}" } ?? "null"

        if c.status == "analysing" {
            return """
            {"id":\(s(c.id)),"startedAt":\(s(clock.iso(started))),"endedAt":\(s(clock.iso(ended))),"durationS":\(n(c.duration)),\
            "transcript":"","transcriptSource":"phone","turns":[],"speakers":[],"screen":{"app":null,"summary":"","ocrText":"","denied":true},\
            "place":null,"title":null,"summary":null,"flow":[],"entities":[],"status":"analysing","error":null,\
            "audioUrl":"/api/native/captures/\(c.id)/audio","screenUrl":null,"actions":[]}
            """
        }

        let turns: String
        let speakers: String
        let flow: String
        let actions: String
        let entities: String
        switch c.id {
        case "cap_demo_idea":
            turns = #"[{"speaker":"S1","start":0,"end":38,"text":"Idea: count what visits the bird feeder each morning, log it with the weather, and chart it over the winter."}]"#
            speakers = #"[{"label":"S1","guess":null,"confirmed":null,"isOwner":true}]"#
            flow = #"[{"topic":"The bird feeder log","from_s":0,"to_s":38,"speakers":["S1"]}]"#
            actions = """
            [{"id":"act_idea_1","captureId":"cap_demo_idea","kind":"research","title":"Which birds visit feeders in winter","detail":"A short list to log against.",\
            "who":null,"dueAt":null,"params":{"question":"Which garden birds visit feeders in a UK winter, and how to tell them apart?"},\
            "state":"proposed","refKind":null,"refId":null,"error":null,"createdAt":\(s(clock.iso(ended))),"decidedAt":null}]
            """
            entities = #"[{"name":"Bird feeder","type":"object","mention":"the bird feeder"}]"#
        case "cap_demo_robin":
            turns = """
            [{"speaker":"S1","start":0,"end":6,"text":"When does the coach leave on Thursday?"},\
            {"speaker":"S2","start":6.4,"end":12,"text":"The coach leaves at eight, so we need to be there by quarter to."},\
            {"speaker":"S3","start":12.5,"end":16,"text":"I'll pack the lunches the night before."}]
            """
            speakers = """
            [{"label":"S1","guess":null,"confirmed":null,"isOwner":true},\
            {"label":"S2","guess":null,"confirmed":{"name":"Robin","entityId":"ent_demo_robin"},"isOwner":false},\
            {"label":"S3","guess":null,"confirmed":{"name":"Alex"},"isOwner":false}]
            """
            flow = #"[{"topic":"The school trip","from_s":0,"to_s":16,"speakers":["S1","S2","S3"]}]"#
            actions = """
            [{"id":"act_robin_1","captureId":"cap_demo_robin","kind":"todo_me","title":"Be at school by 7:45 on Thursday","detail":null,\
            "who":null,"dueAt":\(s(clock.iso(minutesAgo: -60 * 40))),"params":{},"state":"done","refKind":"followup","refId":"f1",\
            "error":null,"createdAt":\(s(clock.iso(ended))),"decidedAt":\(s(clock.iso(ended)))},\
            {"id":"act_robin_2","captureId":"cap_demo_robin","kind":"todo_other","title":"Alex packs the lunches","detail":"The night before.",\
            "who":"S3","dueAt":null,"params":{"draft":"Lunches for Thursday?"},"state":"dismissed","refKind":null,"refId":null,\
            "error":null,"createdAt":\(s(clock.iso(ended))),"decidedAt":\(s(clock.iso(ended)))}]
            """
            entities = #"[{"name":"Robin","type":"person","mention":"Robin"},{"name":"School trip","type":"event","mention":"the coach"}]"#
        default:
            turns = """
            [{"speaker":"S1","start":0,"end":5.2,"text":"Thanks Sam — can you send the plan by Friday?"},\
            {"speaker":"S2","start":5.6,"end":9.1,"text":"Will do. I'll put Saturday's walk in it too, from the north gate."},\
            {"speaker":"S1","start":9.5,"end":14,"text":"Great. Let's say ten o'clock, and ask Alex if he's coming."},\
            {"speaker":"S2","start":14.4,"end":16.2,"text":"Ten it is."}]
            """
            speakers = """
            [{"label":"S1","guess":null,"confirmed":null,"isOwner":true},\
            {"label":"S2","guess":{"name":"Sam","entityId":"ent_demo_sam","confidence":0.82,"evidence":["named twice","in your calendar"]},\
            "confirmed":\(s2Confirmed),"isOwner":false}]
            """
            flow = """
            [{"topic":"The plan, by Friday","from_s":0,"to_s":9.1,"speakers":["S1","S2"]},\
            {"topic":"Saturday's walk","from_s":9.1,"to_s":16.2,"speakers":["S1","S2"]}]
            """
            actions = """
            [{"id":"act_park_1","captureId":"cap_demo_park","kind":"calendar","title":"Walk in Central Park","detail":"From the north gate.",\
            "who":null,"dueAt":null,"params":{"title":"Walk in Central Park","start":"2026-10-31T10:00:00Z","location":"Central Park, north gate","attendees":["Sam","Alex"]},\
            "state":"proposed","refKind":null,"refId":null,"error":null,"createdAt":\(s(clock.iso(ended))),"decidedAt":null},\
            {"id":"act_park_2","captureId":"cap_demo_park","kind":"todo_other","title":"Sam sends the plan","detail":"By Friday.",\
            "who":"S2","dueAt":"2026-10-30T17:00:00Z","params":{},"state":"proposed","refKind":null,"refId":null,"error":null,\
            "createdAt":\(s(clock.iso(ended))),"decidedAt":null},\
            {"id":"act_park_3","captureId":"cap_demo_park","kind":"remember","title":"Sam plans the Saturday walks","detail":null,\
            "who":null,"dueAt":null,"params":{"fact":"Sam plans the Saturday walks","entity":"Sam"},"state":"done","refKind":"note","refId":"n1",\
            "error":null,"createdAt":\(s(clock.iso(ended))),"decidedAt":\(s(clock.iso(ended)))}]
            """
            entities = """
            [{"name":"Sam","type":"person","mention":"Thanks Sam"},{"name":"Central Park","type":"place","mention":"from the north gate"},\
            {"name":"Alex","type":"person","mention":"ask Alex"},{"name":"Saturday walk","type":"event","mention":"Saturday's walk"}]
            """
        }
        let screen = c.app.map {
            #"{"app":{"name":"# + s($0) + #","confidence":0.74},"summary":"A week view with Saturday free.","ocrText":"Sat 31","corrected":null,"denied":false}"#
        } ?? "null"
        return """
        {"id":\(s(c.id)),"spaceId":"owner","startedAt":\(s(clock.iso(started))),"endedAt":\(s(clock.iso(ended))),\
        "durationS":\(n(c.duration)),"transcript":"","transcriptSource":"phone","turns":\(turns),"speakers":\(speakers),\
        "screen":\(screen),"place":{"lat":40.7812,"lon":-73.9665},"title":\(s(c.title)),"summary":\(s(c.snippet)),\
        "flow":\(flow),"entities":\(entities),"status":"ready","error":null,"analysisCostUsd":0.004,\
        "createdAt":\(s(clock.iso(ended))),"updatedAt":\(s(clock.iso(ended))),\
        "audioUrl":"/api/native/captures/\(c.id)/audio","screenUrl":null,"actions":\(actions)}
        """
    }

    static func captureDecision(id: String, actionId: String, body: Data?, clock: DemoClock) -> String {
        let decision = (body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })?["decision"] as? String
        let state = decision == "dismiss" ? "dismissed" : "done"
        let titles = ["act_park_1": ("calendar", "Walk in Central Park"), "act_park_2": ("todo_other", "Sam sends the plan"),
                      "act_idea_1": ("research", "Which birds visit feeders in winter")]
        let (kind, title) = titles[actionId] ?? ("todo_me", "Follow-up")
        return """
        {"id":\(s(actionId)),"captureId":\(s(id)),"kind":\(s(kind)),"title":\(s(title)),"detail":null,"who":null,"dueAt":null,\
        "params":{},"state":\(s(state)),"refKind":\(state == "done" ? "\"demo\"" : "null"),"refId":null,"error":null,\
        "createdAt":\(s(clock.iso(minutesAgo: 40))),"decidedAt":\(s(clock.iso(clock.now)))}
        """
    }
}
