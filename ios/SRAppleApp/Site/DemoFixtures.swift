#if DEBUG
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Demo mode
//
// A DEBUG-only way to see every tab full. CI's UI tests only ever run the app
// unpaired, so the screenshots they attach are empty states — useless for
// reviewing a redesign. Launched with `-SRDemo`, the site client pretends to be
// paired and answers every `/api/native/...` request from the canned JSON below,
// in-process, without touching the network or the Keychain.
//
// EVERYTHING HERE IS SYNTHETIC. The repository is public: no real names beyond
// "John", no phone numbers, no addresses, no real routes. The tracks are drawn
// around Central Park, New York, which the unit tests already use for the same
// reason, and segment names are the made-up word triples the tests use.
//
// Dates are generated relative to NOW at request time, so "2h ago" reads live.

enum SRDemo {
    /// On when the app was launched with `-SRDemo` (a UI test's launch argument,
    /// or a scheme argument). Never on in a Release build — this whole file is
    /// compiled out.
    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("-SRDemo") }

    /// The pretend credential. Held in memory only; never written anywhere.
    static let token = "demo"

    /// `-SRDemoMember` as well: a family member the owner gave the Family and
    /// Games tabs and nothing else — no chat, no news. The screenshot that
    /// proves a feature somebody lacks is absent rather than disabled.
    static var isMember: Bool { ProcessInfo.processInfo.arguments.contains("-SRDemoMember") }

    /// What demo mode may use: everything, as the owner, unless a member.
    static var access: AppAccess {
        isMember ? AppAccess(family: true, games: true) : .everything
    }
}

/// Answers the site client's requests from `SRDemoFixtures`.
///
/// Registered only on `SiteClient`'s own session, and only in demo mode, so it
/// takes every request that session makes.
final class SRDemoURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let reply = SRDemoFixtures.reply(
            method: request.httpMethod ?? "GET",
            url: url,
            body: Self.body(of: request)
        )
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: reply.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotParseResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// A request body reaches a URLProtocol as a STREAM, not as `httpBody`,
    /// once URLSession has taken it — so read whichever is there.
    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

struct SRDemoReply {
    let status: Int
    let body: Data
}

// MARK: - The fixtures

enum SRDemoFixtures {

    static func reply(method: String, url: URL, body: Data?, now: Date = Date()) -> SRDemoReply {
        let rawPath = url.path
        let path = rawPath.removingPercentEncoding ?? rawPath
        var query: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] where query[item.name] == nil {
            query[item.name] = item.value ?? ""
        }
        let clock = DemoClock(now: now)
        if let json = route(method: method.uppercased(), path: path, query: query, body: body, clock: clock) {
            return SRDemoReply(status: 200, body: Data(json.utf8))
        }
        return SRDemoReply(status: 404, body: Data(#"{"error":"demo: no fixture"}"#.utf8))
    }

    /// Every path the app asks for. `nil` is a 404.
    static func route(method: String, path: String, query: [String: String], body: Data?, clock: DemoClock) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        let joined = parts.joined(separator: "/")

        switch (method, joined) {
        case ("GET", "api/native/me"):
            return me(clock)
        case ("POST", "api/native/pair"):
            return nil
        case ("GET", "api/native/today"):
            return today(clock)
        case ("GET", "api/native/daydream"):
            return daydreamFeed(scope: query["scope"], limit: Int(query["limit"] ?? "") ?? 5, clock: clock)
        case ("POST", "api/native/daydream/feedback"):
            return #"{"ok":true}"#
        case ("GET", "api/native/health/summary"):
            return healthSummary(clock)
        case ("GET", "api/native/health/hub"):
            return healthHub
        case ("GET", "api/native/health/activities"):
            return activitiesPage(limit: Int(query["limit"] ?? "") ?? 30, before: query["before"], clock: clock)
        case ("GET", "api/native/health/segments"):
            return segmentsPage(clock)
        case ("GET", "api/native/chat/conversations"):
            return conversationPage(term: query["q"], clock: clock)
        case ("POST", "api/native/chat/conversations"):
            return newConversation(clock)
        case ("POST", "api/workflows/orchestrator/chat"):
            // Calm, not clever: the composer shows this as the turn's error.
            return #"{"jobId":null,"error":"Demo mode: sending is switched off."}"#
        case ("GET", "api/native/chat/conversations/demo-thread-training/model"),
             ("GET", "api/native/chat/conversations/demo-thread-new/model"):
            return demoModel(locked: path.contains("training"))
        case ("POST", "api/native/chat/attachments"):
            return #"{"id":"demo-attachment","filename":"Photo.jpg","kind":"image","mimeType":"image/jpeg","sizeBytes":182044}"#
        case ("DELETE", "api/workflows/orchestrator/chat"):
            return #"{"ok":true}"#
        case ("GET", "api/native/news"):
            return newsFeed(view: query["view"] ?? "top", sort: query["sort"] ?? "time", clock: clock)
        case ("POST", "api/native/news/actions"):
            return #"{"ok":true,"favourite":true}"#
        case ("GET", "api/native/notifications"):
            return alertFeed(clock)
        case ("GET", "api/native/connections"):
            return connectionsFeed(clock)
        case ("POST", "api/native/notifications"):
            return #"{"ok":true}"#
        case ("GET", "api/native/notifications/routes"):
            return alertRoutes(change: nil)
        case ("PUT", "api/native/notifications/routes"):
            return alertRoutes(change: body)
        default:
            break
        }

        // Paths with an id in them.
        if parts.count == 5, joined.hasPrefix("api/native/health/activities/") {
            return method == "GET" ? activityDetail(id: parts[4], clock: clock) : nil
        }
        if parts.count == 5, joined.hasPrefix("api/native/health/segments/") {
            guard method == "GET", let id = Int(parts[4]) else { return nil }
            return segmentDetail(id: id, clock: clock)
        }
        if parts.count == 5, joined.hasPrefix("api/native/chat/conversations/") {
            // PATCH (rename, pin) and DELETE. The app reads nothing back.
            return method == "GET" ? nil : #"{"ok":true}"#
        }
        if parts.count == 6, joined.hasPrefix("api/native/chat/conversations/"), parts[5] == "messages" {
            return method == "GET" ? messagePage(id: parts[4], clock: clock) : nil
        }
        if parts.count == 6, joined.hasPrefix("api/native/news/story/") {
            return method == "GET" ? article(source: parts[4], id: parts[5], clock: clock) : nil
        }
        // Family games — `Games/GamesDemoFixtures.swift`.
        if joined == "api/native/games" || joined.hasPrefix("api/native/games/") {
            return gamesRoute(method: method, parts: parts, body: body, clock: clock)
        }
        // Workflows — `FlowDemoFixtures.swift`.
        if joined == "api/native/workflows" || joined.hasPrefix("api/native/workflows/") {
            return flowRoute(method: method, parts: parts, body: body, clock: clock)
        }
        // Everything else — the chat stream included — is a 404.
        return nil
    }

    // MARK: - Helpers

    struct DemoClock {
        let now: Date

        func date(minutesAgo: Double) -> Date { now.addingTimeInterval(-minutesAgo * 60) }

        func iso(minutesAgo: Double) -> String { iso(date(minutesAgo: minutesAgo)) }

        func iso(_ date: Date) -> String {
            let format = ISO8601DateFormatter()
            format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return format.string(from: date)
        }

        /// "2026-09-22 07:12:00" in the phone's own zone — the shape of
        /// `startDateLocal`, which is read as written and never re-zoned.
        func local(_ date: Date) -> String {
            let format = DateFormatter()
            format.locale = Locale(identifier: "en_US_POSIX")
            format.timeZone = TimeZone.current
            format.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return format.string(from: date)
        }
    }

    /// A JSON string literal, or `null`.
    static func s(_ value: String?) -> String {
        guard let value else { return "null" }
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    /// A JSON number, or `null`. Whole values print without a decimal point.
    static func n(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "null" }
        if value == value.rounded(), abs(value) < 1e12 { return String(Int(value)) }
        return String(format: "%.2f", value)
    }

    static func b(_ value: Bool) -> String { value ? "true" : "false" }

    static func list(_ items: [String]) -> String { "[" + items.joined(separator: ", ") + "]" }

    static func coord(_ value: Double) -> String { String(format: "%.5f", value) }

    // MARK: - Pairing

    static func me(_ clock: DemoClock) -> String {
        """
        {"ownerEmail": "john@example.com", "label": "iPhone (demo)", "expiresAt": \(s(clock.iso(minutesAgo: -60 * 24 * 80)))}
        """
    }

    // MARK: - Health

    struct DemoFigure {
        let key: String
        let label: String
        let value: Double
        let unit: String
        let display: String
        let delta: Double?
        let deltaDisplay: String?
        let direction: String?
        let improving: Bool?
        let caption: String
        let series: [Double]
    }

    static let figures: [DemoFigure] = [
        DemoFigure(key: "rhr", label: "Resting HR", value: 52, unit: "bpm", display: "52",
                   delta: -2, deltaDisplay: "−2 vs 7d", direction: "down", improving: true, caption: "7-day mean",
                   series: [56, 55, 55, 56, 54, 54, 53, 54, 53, 53, 52, 53, 52, 52]),
        DemoFigure(key: "hrv", label: "HRV", value: 64, unit: "ms", display: "64",
                   delta: 5, deltaDisplay: "+5 vs 7d", direction: "up", improving: true, caption: "7-day mean",
                   series: [57, 59, 58, 55, 60, 61, 59, 62, 58, 63, 61, 65, 63, 64]),
        DemoFigure(key: "sleep", label: "Sleep", value: 7.4, unit: "h", display: "7h 24m",
                   delta: 0.3, deltaDisplay: "+18m vs 7d", direction: "up", improving: true, caption: "last night",
                   series: [6.8, 7.1, 6.5, 7.6, 7.0, 6.9, 7.3, 7.8, 6.6, 7.2, 7.0, 7.5, 7.1, 7.4]),
        DemoFigure(key: "steps", label: "Steps", value: 9120, unit: "", display: "9,120",
                   delta: 800, deltaDisplay: "+800 vs 7d", direction: "up", improving: true, caption: "yesterday",
                   series: [7200, 8100, 10400, 6600, 9900, 8300, 11250, 7400, 8800, 12100, 6900, 9400, 8700, 9120]),
    ]

    static func figureJSON(_ f: DemoFigure, withSeries: Bool) -> String {
        var fields = [
            "\"key\": \(s(f.key))",
            "\"label\": \(s(f.label))",
            "\"value\": \(n(f.value))",
            "\"unit\": \(s(f.unit))",
            "\"display\": \(s(f.display))",
            "\"delta\": \(n(f.delta))",
            "\"deltaDisplay\": \(s(f.deltaDisplay))",
            "\"direction\": \(s(f.direction))",
            "\"improving\": \(f.improving.map(b) ?? "null")",
            "\"caption\": \(s(f.caption))",
        ]
        if withSeries { fields.append("\"series\": \(list(f.series.map { n($0) }))") }
        return "{" + fields.joined(separator: ", ") + "}"
    }

    static let readiness = """
    {"score": 72, "label": "Primed", "recommendation": "Sleep and HRV are both back above baseline. A quality session is on the cards today.",
     "factors": [{"key": "recovery", "label": "Recovery", "score": 68, "weight": 0.4}, {"key": "sleepQuality", "label": "Sleep quality", "score": 81, "weight": 0.2}]}
    """

    static func healthSummary(_ clock: DemoClock) -> String {
        """
        {
          "generatedAt": \(s(clock.iso(minutesAgo: 12))),
          "isMock": false,
          "strap": "Recovered and ready.",
          "readiness": \(readiness),
          "figures": \(list(figures.map { figureJSON($0, withSeries: true) })),
          "week": {"activities": 5, "distanceKm": 42.1, "durationMinutes": 268, "elevationM": 412, "avgRecovery": 68, "avgSleep": 82},
          "records": [
            {"label": "Longest run", "display": "21.1 km", "date": \(s(String(clock.iso(minutesAgo: 60 * 24 * 142).prefix(10))))},
            {"label": "Fastest 5K", "display": "22:48", "date": \(s(String(clock.iso(minutesAgo: 60 * 24 * 37).prefix(10))))},
            {"label": "Biggest week", "display": "58.4 km", "date": \(s(String(clock.iso(minutesAgo: 60 * 24 * 64).prefix(10))))},
            {"label": "Most climbing", "display": "612 m", "date": null}
          ],
          "fingerprint": "demo"
        }
        """
    }

    // MARK: - Today

    static func today(_ clock: DemoClock) -> String {
        let alerts = demoAlerts(clock).prefix(3).map { alert in
            """
            {"id": \(s(alert.id)), "category": \(s(alert.category)), "title": \(s(alert.title)), "severity": \(s(alert.severity)), "createdAt": \(s(clock.iso(minutesAgo: alert.minutesAgo)))}
            """
        }
        let stories = demoStories.prefix(4).map { story in
            """
            {"key": \(s(story.key)), "title": \(s(story.title)), "sourceLabel": \(s(story.sourceLabel)), "url": \(s(story.url)), "heat": \(n(story.heat))}
            """
        }
        let thread = demoThreads[0]
        return """
        {
          "generatedAt": \(s(clock.iso(minutesAgo: 0))),
          "health": {
            "isMock": false,
            "strap": "Recovered and ready.",
            "readiness": \(readiness),
            "figures": \(list(figures.map { figureJSON($0, withSeries: false) })),
            "generatedAt": \(s(clock.iso(minutesAgo: 12)))
          },
          "alerts": {"pending": 0, "unread": 2, "latest": \(list(alerts))},
          "news": {"updatedAt": \(s(clock.iso(minutesAgo: 6))), "unseen": 5, "stories": \(list(stories))},
          "lastThread": {"id": \(s(thread.id)), "title": \(s(thread.title)), "updatedAt": \(s(clock.iso(minutesAgo: thread.minutesAgo)))},
          "connections": \(todayConnections(clock)),
          "daydream": \(todayDaydream(clock))
        }
        """
    }

    // MARK: - Activities

    struct DemoActivity {
        let id: String
        let name: String
        let type: String
        let minutesAgo: Double
        let distanceM: Double?
        let durationS: Double
        let movingS: Double?
        let gainM: Double?
        let avgHR: Double?
        let pace: Double?
        let kcal: Double?
        let hasTrack: Bool
        let segmentCount: Int
        let highlightLabel: String?
        let highlightDetail: String?
        /// Origins whose copy of this outing the server folded into this row.
        var alsoFrom: [String] = []

        /// `apple`, `strava`, `companion` — the id's own prefix.
        var source: String { String(id.split(separator: ":").first ?? "apple") }
        /// Captured by the app from location: no workout, so no elevation or
        /// heart rate, and a type guessed from speed.
        var captured: Bool { source == "companion" }
    }

    static let demoActivities: [DemoActivity] = [
        DemoActivity(id: "apple:6F1C2A9E-1B2C-4D5E-8F90-ABCDEF012345", name: "Morning park loop", type: "run",
                     minutesAgo: 60 * 5, distanceM: 7423.4, durationS: 2533, movingS: 2470, gainM: 58.2,
                     avgHR: 148.6, pace: 332.7, kcal: 512, hasTrack: true, segmentCount: 3,
                     highlightLabel: "2nd best", highlightDetail: "heron.slate.ridge, 4:12"),
        // An outing the app caught itself from background location: no
        // workout was started, so no heart rate, no elevation, no energy.
        DemoActivity(id: "companion:1758560400", name: "Captured walk", type: "walk",
                     minutesAgo: 60 * 19, distanceM: 2410, durationS: 1935, movingS: nil, gainM: nil,
                     avgHR: nil, pace: 803, kcal: nil, hasTrack: true, segmentCount: 0,
                     highlightLabel: nil, highlightDetail: nil),
        DemoActivity(id: "strava:1234567", name: "Evening ride", type: "ride",
                     minutesAgo: 60 * 27, distanceM: 32180, durationS: 4210, movingS: 4050, gainM: 310,
                     avgHR: 138, pace: 125.9, kcal: 820, hasTrack: true, segmentCount: 2,
                     highlightLabel: nil, highlightDetail: nil),
        DemoActivity(id: "apple:0A1B2C3D-4E5F-4A6B-8C7D-0E1F2A3B4C5D", name: "Reservoir intervals", type: "run",
                     minutesAgo: 60 * 52, distanceM: 6012, durationS: 2011, movingS: 1900, gainM: 22,
                     avgHR: 161, pace: 316, kcal: 470, hasTrack: true, segmentCount: 1,
                     highlightLabel: "PB", highlightDetail: "wren.amber.causeway, 1:21"),
        DemoActivity(id: "apple:1B2C3D4E-5F60-4B7C-9D8E-1F2A3B4C5D6E", name: "Lunch walk", type: "walk",
                     minutesAgo: 60 * 76, distanceM: 3120, durationS: 2280, movingS: 2200, gainM: 12,
                     avgHR: 96, pace: 705, kcal: 180, hasTrack: true, segmentCount: 0,
                     highlightLabel: nil, highlightDetail: nil, alsoFrom: ["companion"]),
        DemoActivity(id: "strava:1234512", name: "Long run", type: "run",
                     minutesAgo: 60 * 24 * 5 + 180, distanceM: 16104, durationS: 5820, movingS: 5710, gainM: 142,
                     avgHR: 151, pace: 354.6, kcal: 1130, hasTrack: true, segmentCount: 4,
                     highlightLabel: "Longest this month", highlightDetail: "16.1 km, the furthest since May"),
        DemoActivity(id: "apple:2C3D4E5F-6071-4C8D-8E9F-2A3B4C5D6E7F", name: "Recovery spin", type: "ride",
                     minutesAgo: 60 * 24 * 6 + 60, distanceM: 18400, durationS: 2700, movingS: 2650, gainM: 90,
                     avgHR: 118, pace: 144, kcal: 380, hasTrack: false, segmentCount: 0,
                     highlightLabel: nil, highlightDetail: nil),
        DemoActivity(id: "apple:3D4E5F60-7182-4D9E-9FA0-3B4C5D6E7F80", name: "Easy run", type: "run",
                     minutesAgo: 60 * 24 * 8, distanceM: 5020, durationS: 1830, movingS: 1790, gainM: 31,
                     avgHR: 139, pace: 356.6, kcal: 350, hasTrack: true, segmentCount: 2,
                     highlightLabel: nil, highlightDetail: nil),
        DemoActivity(id: "strava:1234498", name: "Hill repeats", type: "run",
                     minutesAgo: 60 * 24 * 10 + 240, distanceM: 8210, durationS: 3050, movingS: 2890, gainM: 204,
                     avgHR: 157, pace: 352, kcal: 640, hasTrack: true, segmentCount: 3,
                     highlightLabel: "3rd best", highlightDetail: "kestrel.moss.rise, 2:58"),
    ]

    static func rowFields(_ a: DemoActivity, _ clock: DemoClock) -> String {
        let start = clock.date(minutesAgo: a.minutesAgo)
        var highlight = "null"
        if let label = a.highlightLabel, let detail = a.highlightDetail {
            highlight = "{\"label\": \(s(label)), \"detail\": \(s(detail))}"
        }
        return """
        "id": \(s(a.id)), "name": \(s(a.name)), "activityType": \(s(a.type)),
        "startDate": \(s(clock.iso(start))), "startDateLocal": \(s(clock.local(start))),
        "distanceM": \(n(a.distanceM)), "durationS": \(n(a.durationS)), "movingS": \(n(a.movingS)),
        "elevationGainM": \(n(a.gainM)), "avgHeartrate": \(n(a.avgHR)), "paceSPerKm": \(n(a.pace)),
        "energyKcal": \(n(a.kcal)), "hasTrack": \(b(a.hasTrack)), "segmentCount": \(a.segmentCount),
        "highlight": \(highlight),
        "source": \(s(a.source)), "alsoFrom": \(list(a.alsoFrom.map { s($0) }))
        """
    }

    static func activitiesPage(limit: Int, before: String?, clock: DemoClock) -> String {
        // One page is the whole history: there is no older page to fetch.
        let rows = before == nil ? Array(demoActivities.prefix(max(1, limit))) : []
        let objects = rows.map { "{" + rowFields($0, clock) + "}" }
        return "{\"activities\": \(list(objects)), \"nextBefore\": null}"
    }

    /// A made-up loop inside Central Park: an ellipse along the park's long
    /// axis, with a wobble so it does not read as a drawing tool's ellipse.
    static func loop(points count: Int = 72) -> [(Double, Double)] {
        let centre = (lat: 40.7824, lng: -73.9656)
        // Half the long axis (north-north-east) and half the short one, in degrees.
        let long = (lat: 0.01520, lng: 0.01115)
        let short = (lat: -0.00120, lng: 0.00285)
        var out: [(Double, Double)] = []
        for i in 0...count {
            let theta = Double(i) / Double(count) * 2 * Double.pi
            let wobble = 1 + 0.06 * sin(theta * 5) + 0.03 * cos(theta * 11)
            let lat = centre.lat + cos(theta) * long.lat * 0.92 + sin(theta) * short.lat * wobble
            let lng = centre.lng + cos(theta) * long.lng * 0.92 + sin(theta) * short.lng * wobble
            out.append((lat, lng))
        }
        return out
    }

    static func routeJSON(_ points: [(Double, Double)]) -> String {
        list(points.map { "[\(coord($0.0)), \(coord($0.1))]" })
    }

    static func boundsJSON(_ points: [(Double, Double)]) -> String {
        guard !points.isEmpty else { return "null" }
        let lats = points.map { $0.0 }
        let lngs = points.map { $0.1 }
        return "{\"n\": \(coord(lats.max()!)), \"s\": \(coord(lats.min()!)), \"e\": \(coord(lngs.max()!)), \"w\": \(coord(lngs.min()!))}"
    }

    static func activityDetail(id: String, clock: DemoClock) -> String? {
        guard let a = demoActivities.first(where: { $0.id == id }) else { return nil }
        let distance = a.distanceM ?? 0
        let time = a.movingS ?? a.durationS
        // A captured walk covers only part of the loop — it is 2.4 km, not 6.
        let route = a.hasTrack ? (a.captured ? Array(loop().prefix(28)) : loop()) : []

        // Elevation: rolling, the park's own gentle hills.
        var elevation: [String] = []
        if a.hasTrack, distance > 0, !a.captured {
            for i in 0...40 {
                let d = distance * Double(i) / 40
                let x = Double(i) / 40 * 2 * Double.pi
                let e = 24 + 11 * sin(x * 1.5) + 5 * sin(x * 4.3 + 1) + 2 * cos(x * 9)
                elevation.append("{\"d\": \(n(d.rounded())), \"e\": \(String(format: "%.1f", e))}")
            }
        }

        // Heart rate: a warm-up, then work that drifts upward.
        var heartRate: [String] = []
        if let avg = a.avgHR {
            let step = max(30, (time / 60).rounded())
            var t = 0.0
            var i = 0
            while t <= time {
                let warm = min(1, t / 420)
                let drift = t / max(time, 1) * 8
                let wave = 5 * sin(Double(i) * 0.9) + 3 * cos(Double(i) * 2.3)
                let v = (avg - 42) + 42 * warm + drift - 4 + wave
                heartRate.append("{\"t\": \(n(t)), \"v\": \(n(v.rounded()))}")
                t += step
                i += 1
            }
        }

        // Splits by kilometre, with the part-kilometre last.
        var splits: [String] = []
        if distance >= 1000, let pace = a.pace {
            let whole = Int(distance / 1000)
            for k in 1...whole {
                let p = (pace + 9 * sin(Double(k) * 1.7) + (k == whole ? -6 : 0)).rounded()
                let gain = max(0, (6 * sin(Double(k) * 1.1) + 5).rounded())
                splits.append("{\"index\": \(k), \"distanceM\": 1000, \"durationS\": \(n(p)), \"paceSPerKm\": \(n(p)), \"elevationGainM\": \(a.captured ? "null" : n(gain))}")
            }
            let rest = distance - Double(whole) * 1000
            if rest >= 50 {
                let d = rest.rounded()
                let p = pace + 4
                splits.append("{\"index\": \(whole + 1), \"distanceM\": \(n(d)), \"durationS\": \(n((d / 1000 * p).rounded())), \"paceSPerKm\": \(n(p)), \"elevationGainM\": null}")
            }
        }

        let efforts = demoSegments.prefix(a.segmentCount).enumerated().map { pair -> String in
            let index = pair.offset
            let seg = pair.element
            let duration = (seg.best * (1.02 + 0.03 * Double(index))).rounded()
            let rank = index == 0 && a.highlightLabel == "PB" ? 1 : index + 2
            return """
            {"segmentId": \(seg.id), "name": \(s(seg.name)), "descriptor": \(s(seg.descriptor)), "distanceM": \(n(seg.distance)), "durationS": \(n(duration)), "paceSPerKm": \(n((duration / seg.distance * 1000).rounded())), "avgHeartrate": \(n((a.avgHR ?? 150) + 9)), "rankByTime": \(rank), "rankedByTimeOf": \(seg.efforts), "effortCount": \(seg.efforts)}
            """
        }

        var highlights: [String] = []
        if let label = a.highlightLabel, let detail = a.highlightDetail {
            highlights.append("{\"label\": \(s(label)), \"detail\": \(s(detail))}")
        }
        if splits.count >= 4 {
            highlights.append("{\"label\": \"Fastest km\", \"detail\": \"Kilometre 4, a touch under target\"}")
        }

        let physio = a.avgHR == nil ? "null" : """
        {"trimp": 96.4, "efficiencyFactor": 1.37, "decouplingPct": 4.2, "hrr60": 31,
         "zones": [{"zone": 1, "seconds": \(n((time * 0.12).rounded()))}, {"zone": 2, "seconds": \(n((time * 0.34).rounded()))}, {"zone": 3, "seconds": \(n((time * 0.33).rounded()))}, {"zone": 4, "seconds": \(n((time * 0.17).rounded()))}, {"zone": 5, "seconds": \(n((time * 0.04).rounded()))}]}
        """

        return """
        {
          "activity": {
            \(rowFields(a, clock)),
            "maxHeartrate": \(n(a.avgHR.map { ($0 + 23).rounded() })), "avgCadence": \(a.type == "run" ? "168" : "null"),
            "elevationLossM": \(n(a.gainM.map { ($0 * 0.95).rounded() })), "temperatureC": 12.5,
            "timezone": "America/New_York",
            "route": \(routeJSON(route)),
            "bounds": \(boundsJSON(route)),
            "elevation": \(list(elevation)),
            "heartRate": \(list(heartRate)),
            "splits": \(list(splits))
          },
          "physio": \(physio),
          "highlights": \(list(highlights)),
          "segments": \(list(Array(efforts)))
        }
        """
    }

    // MARK: - Segments

    struct DemoSegment {
        let id: Int
        let name: String
        let descriptor: String
        let type: String
        let distance: Double
        let gain: Double
        let gradient: Double
        let terrain: String
        let efforts: Int
        let best: Double
        let direction: String
        let deltaPct: Double?
        let daysSincePb: Int?
        let spark: [Double]
        /// Which stretch of the loop it covers.
        let from: Int
        let to: Int
    }

    static let demoSegments: [DemoSegment] = [
        DemoSegment(id: 41, name: "heron.slate.ridge", descriptor: "0.9 km at 4.1%", type: "run", distance: 910,
                    gain: 37.4, gradient: 4.1, terrain: "climb", efforts: 7, best: 246, direction: "improving",
                    deltaPct: -3.2, daysSincePb: 41, spark: [270, 266, 259, 262, 255, 252, 249], from: 4, to: 14),
        DemoSegment(id: 57, name: "wren.amber.causeway", descriptor: "0.4 km, flat", type: "run", distance: 402,
                    gain: 0.5, gradient: 0.1, terrain: "flat", efforts: 12, best: 81, direction: "holding",
                    deltaPct: 0.4, daysSincePb: 2, spark: [86, 84, 85, 83, 84, 82, 81], from: 20, to: 25),
        DemoSegment(id: 63, name: "otter.linen.bend", descriptor: "1.2 km, rolling", type: "run", distance: 1210,
                    gain: 14, gradient: 0.6, terrain: "rolling", efforts: 9, best: 318, direction: "slipping",
                    deltaPct: 2.8, daysSincePb: 96, spark: [318, 322, 325, 329, 331, 334], from: 30, to: 44),
        DemoSegment(id: 72, name: "kestrel.moss.rise", descriptor: "0.6 km at 6.3%", type: "run", distance: 610,
                    gain: 38.4, gradient: 6.3, terrain: "climb", efforts: 15, best: 172, direction: "improving",
                    deltaPct: -1.9, daysSincePb: 10, spark: [190, 186, 181, 183, 178, 175, 172, 178], from: 48, to: 55),
        DemoSegment(id: 88, name: "finch.cobalt.straight", descriptor: "0.8 km at -3.0%", type: "run", distance: 800,
                    gain: 2, gradient: -3.0, terrain: "descent", efforts: 4, best: 199, direction: "unknown",
                    deltaPct: nil, daysSincePb: nil, spark: [], from: 58, to: 66),
    ]

    static func segmentFields(_ seg: DemoSegment, _ clock: DemoClock) -> String {
        let form = seg.spark.isEmpty ? "null" : """
        {"direction": \(s(seg.direction)), "deltaPct": \(n(seg.deltaPct)), "daysSincePb": \(seg.daysSincePb.map { String($0) } ?? "null"), "spark": \(list(seg.spark.map { n($0) }))}
        """
        return """
        "id": \(seg.id), "name": \(s(seg.name)), "descriptor": \(s(seg.descriptor)), "activityType": \(s(seg.type)),
        "distanceM": \(n(seg.distance)), "elevationGainM": \(n(seg.gain)), "gradientPct": \(n(seg.gradient)), "terrain": \(s(seg.terrain)),
        "effortCount": \(seg.efforts), "lastEffortAt": \(s(clock.iso(minutesAgo: 60 * 5 - 18))),
        "bestDurationS": \(n(seg.best)), "bestPaceSPerKm": \(n((seg.best / seg.distance * 1000).rounded())),
        "form": \(form)
        """
    }

    static func segmentsPage(_ clock: DemoClock) -> String {
        "{\"segments\": \(list(demoSegments.map { "{" + segmentFields($0, clock) + "}" }))}"
    }

    static func segmentDetail(id: Int, clock: DemoClock) -> String? {
        guard let seg = demoSegments.first(where: { $0.id == id }) else { return nil }
        let points = loop()
        let route = Array(points[max(0, seg.from)...min(points.count - 1, seg.to)])
        let runs = demoActivities.filter { $0.type == "run" }
        var efforts: [String] = []
        for i in 0..<min(seg.efforts, 6) {
            let run = runs[i % runs.count]
            let isBest = i == 2
            let duration = isBest ? seg.best : (seg.best * (1.015 + 0.02 * Double(i))).rounded()
            efforts.append("""
            {"id": \(900 - i), "activityId": \(s(run.id)), "activityName": \(s(run.name)), "activityType": "run", "startedAt": \(s(clock.iso(minutesAgo: run.minutesAgo + Double(i) * 60 * 24 * 9 - 18))), "durationS": \(n(duration)), "paceSPerKm": \(n((duration / seg.distance * 1000).rounded())), "avgHeartrate": \(n(Double(158 + i))), "efficiencyFactor": \(i == 3 ? "null" : "1.4"), "isBest": \(b(isBest))}
            """)
        }
        return """
        {
          "segment": {
            \(segmentFields(seg, clock)),
            "route": \(routeJSON(route)),
            "elevationLossM": 1.2,
            "conditions": {"meanC": 11.4, "quickestC": 9.0, "slowestC": 17.5}
          },
          "efforts": \(list(efforts))
        }
        """
    }

    // MARK: - Chat

    struct DemoThread {
        let id: String
        let title: String?
        let source: String
        let pinned: Bool
        let messageCount: Int
        let preview: String
        let minutesAgo: Double
    }

    static let demoThreads: [DemoThread] = [
        DemoThread(id: "demo-thread-training", title: "Marathon block, week 6 review", source: "web", pinned: true,
                   messageCount: 14, preview: "You ran 42.1 km across five sessions, the most since the block started, and recovery held at 68% on average.",
                   minutesAgo: 38),
        DemoThread(id: "demo-thread-backups", title: "Home server backup plan", source: "web", pinned: true,
                   messageCount: 31, preview: "Nightly restic to the second box, weekly to object storage, and a restore drill on the first Sunday of the month.",
                   minutesAgo: 60 * 26),
        DemoThread(id: "demo-thread-whatsapp", title: "Quick questions", source: "whatsapp", pinned: false,
                   messageCount: 52, preview: "Yes, the 07:42 is running on time. Platform 3.",
                   minutesAgo: 95),
        DemoThread(id: "demo-thread-blog", title: "Draft: what a year of route data says", source: "web", pinned: false,
                   messageCount: 9, preview: "The strongest pattern is not distance but time of day: the morning runs are 11 seconds per km quicker.",
                   minutesAgo: 60 * 5),
        DemoThread(id: "demo-thread-swiftui", title: "SwiftUI glass tab bar notes", source: "web", pinned: false,
                   messageCount: 18, preview: "tabViewBottomAccessory only exists on iOS 26, so gate it behind an availability check and keep the old bar below.",
                   minutesAgo: 60 * 9),
        DemoThread(id: "demo-thread-lakes", title: "Weekend in the Lakes: packing list", source: "web", pinned: false,
                   messageCount: 7, preview: "Waterproofs, the lighter stove, two maps (OL6 and OL7), and a spare battery for the head torch.",
                   minutesAgo: 60 * 30),
        DemoThread(id: "demo-thread-untitled", title: nil, source: "web", pinned: false,
                   messageCount: 2, preview: "What is the difference between HRV RMSSD and SDNN?",
                   minutesAgo: 60 * 50),
        DemoThread(id: "demo-thread-reading", title: "Reading list triage", source: "web", pinned: false,
                   messageCount: 23, preview: "Kept 6, archived 14. The three on database internals are worth reading in order.",
                   minutesAgo: 60 * 24 * 4),
    ]

    static func conversationJSON(_ t: DemoThread, _ clock: DemoClock) -> String {
        """
        {"id": \(s(t.id)), "title": \(s(t.title)), "source": \(s(t.source)), "pinned": \(b(t.pinned)), "messageCount": \(t.messageCount), "modelProvider": "anthropic", "modelId": "claude-sonnet-4-5", "preview": \(s(t.preview)), "createdAt": \(s(clock.iso(minutesAgo: t.minutesAgo + 60 * 24 * 3))), "updatedAt": \(s(clock.iso(minutesAgo: t.minutesAgo)))}
        """
    }

    static func conversationPage(term: String?, clock: DemoClock) -> String {
        var threads = demoThreads
        if let term = term?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !term.isEmpty {
            threads = threads.filter { ($0.title ?? "").lowercased().contains(term) || $0.preview.lowercased().contains(term) }
        }
        return "{\"conversations\": \(list(threads.map { conversationJSON($0, clock) })), \"cursor\": null, \"hasMore\": false}"
    }

    static func demoModel(locked: Bool) -> String {
        """
        {"current": {"provider": "codex", "modelId": "codex/gpt-6-astra", "label": "GPT-6 Astra"},
         "locked": \(b(locked)), "thinkingLevel": "medium", "supportsThinking": true,
         "levels": ["low", "medium", "high", "xhigh"],
         "choices": [
           {"provider": "codex", "modelId": "codex/gpt-6-astra", "label": "GPT-6 Astra", "group": "default"},
           {"provider": "codex", "modelId": "codex/gpt-5.6-sol", "label": "GPT-5.6 Sol", "group": "codex"},
           {"provider": "openrouter", "modelId": "anthropic/claude-sonnet-5", "label": "Claude Sonnet 5", "group": "recent"},
           {"provider": "openrouter", "modelId": "z-ai/glm-5.2", "label": "GLM 5.2", "group": "recent"}
         ]}
        """
    }

    static func newConversation(_ clock: DemoClock) -> String {
        """
        {"id": "demo-thread-new", "title": "New thread", "source": "web", "pinned": false, "messageCount": 0, "modelProvider": null, "modelId": null, "preview": null, "createdAt": \(s(clock.iso(minutesAgo: 0))), "updatedAt": \(s(clock.iso(minutesAgo: 0)))}
        """
    }

    static func messagePage(id: String, clock: DemoClock) -> String? {
        let thread = demoThreads.first(where: { $0.id == id })
        if thread == nil && id != "demo-thread-new" { return nil }
        let head = "{\"id\": \(s(id)), \"title\": \(s(thread?.title ?? "New thread")), \"source\": \(s(thread?.source ?? "web"))}"
        let messages: String
        switch id {
        case "demo-thread-new":
            messages = "[]"
        case "demo-thread-whatsapp":
            messages = whatsappMessages(clock)
        case "demo-thread-training":
            messages = trainingMessages(clock)
        default:
            messages = genericMessages(thread?.preview ?? "", clock)
        }
        return "{\"conversation\": \(head), \"hasOlder\": false, \"cursor\": null, \"messages\": \(messages)}"
    }

    static func trainingMessages(_ clock: DemoClock) -> String {
        #"""
        [
          {"id": "m1", "role": "user", "content": "How did week 6 go? Plan attached.", "createdAt": \#(s(clock.iso(minutesAgo: 52))), "source": "web", "toolSteps": [],
           "attachments": [{"id": "att-1", "filename": "week-6-plan.pdf", "kind": "document", "mimeType": "application/pdf", "sizeBytes": 184320}]},
          {"id": "m2", "role": "assistant", "content": "## Week 6, in one line\n\nYou ran **42.1 km** across five sessions, the most since the block started, and recovery held at **68%** on average.\n\n- Long run: 16.1 km at 5:55 /km, heart-rate drift 4.2%\n- Intervals: 6 x 800 m, every rep inside target\n- Easy runs stayed easy, averaging 139 bpm\n\n> One flag: HRV dipped on Thursday after the hill session. Worth an extra easy day before the next one.\n\nThe query behind the weekly totals, if you want to rerun it:\n\n```sql\nSELECT date_trunc('week', start_date) AS week,\n       round(sum(distance_m) / 1000.0, 1) AS km\nFROM activities\nWHERE activity_type = 'run'\nGROUP BY 1\nORDER BY 1 DESC\nLIMIT 6;\n```\n\nWant me to draft week 7 around an 18 km long run?", "createdAt": \#(s(clock.iso(minutesAgo: 51))), "source": "web",
           "toolSteps": [
             {"tool": "health_activities", "status": "ok", "summary": "Read 42 runs since 1 August"},
             {"tool": "health_summary", "status": "ok", "summary": "Readiness, HRV and sleep for 14 days"},
             {"tool": "web_search", "status": "error", "summary": "Rate limited, used cached pace tables"}
           ],
           "artifacts": [
             {"type": "chart", "simple": true, "mark": "bar",
              "x": {"field": "week", "title": "Week", "type": "ordinal"},
              "y": {"field": "km", "title": "Distance (km)", "type": "quantitative"},
              "color": null,
              "rows": [{"week": "W1", "km": 31.2}, {"week": "W2", "km": 34.8}, {"week": "W3", "km": 36.1}, {"week": "W4", "km": 28.4}, {"week": "W5", "km": 39.7}, {"week": "W6", "km": 42.1}],
              "caption": "Weekly running distance"}
           ],
           "sources": [
             {"kind": "research", "title": "Marathon taper, what the studies say", "passage": "Cutting volume by 40 to 60 per cent over two weeks while holding intensity preserved fitness.", "url": "https://example.org/taper", "domain": "example.org"},
             {"kind": "file", "title": "week-6-plan.pdf", "passage": "Long run 16 km, last 4 at goal pace.", "url": null, "domain": null}
           ],
           "attachments": []},
          {"id": "m3", "role": "user", "content": "Yes, but keep Tuesday free.", "createdAt": \#(s(clock.iso(minutesAgo: 40))), "source": "web", "toolSteps": [], "attachments": []},
          {"id": "m4", "role": "assistant", "content": "Done. Week 7, with Tuesday off:\n\n1. **Mon** easy 6 km\n2. **Wed** 5 x 1 km at threshold\n3. **Thu** easy 8 km\n4. **Sat** long run, 18 km, last 3 at marathon pace\n5. **Sun** recovery spin, 45 minutes\n\nThat is 44 km of running, a 5% step up. I saved it to `plans/week-7.md` so it shows on the site too.", "createdAt": \#(s(clock.iso(minutesAgo: 38))), "source": "web",
           "toolSteps": [{"tool": "drive_write", "status": "ok", "summary": "Saved plans/week-7.md"}],
           "artifacts": [
             {"type": "table", "caption": "Week 7",
              "columns": [{"key": "day", "label": "Day", "align": "left"}, {"key": "session", "label": "Session", "align": "left"}, {"key": "km", "label": "km", "align": "right"}],
              "rows": [{"day": "Mon", "session": "Easy", "km": 6}, {"day": "Wed", "session": "5 x 1 km threshold", "km": 9}, {"day": "Thu", "session": "Easy", "km": 8}, {"day": "Sat", "session": "Long run", "km": 18}, {"day": "Sun", "session": "Recovery spin", "km": null}, {"day": "Tue", "session": "Rest", "km": null}],
              "totalRows": 6}
           ],
           "attachments": []}
        ]
        """#
    }

    static func whatsappMessages(_ clock: DemoClock) -> String {
        #"""
        [
          {"id": "w1", "role": "user", "content": "Is the 07:42 running?", "createdAt": \#(s(clock.iso(minutesAgo: 97))), "source": "whatsapp", "toolSteps": [], "attachments": []},
          {"id": "w2", "role": "assistant", "content": "Yes, the 07:42 is running on time. Platform 3.", "createdAt": \#(s(clock.iso(minutesAgo: 96))), "source": "whatsapp",
           "toolSteps": [{"tool": "rail_departures", "status": "ok", "summary": "Checked live departures"}], "attachments": []},
          {"id": "w3", "role": "user", "content": "Thanks. Remind me to book the car service at lunchtime", "createdAt": \#(s(clock.iso(minutesAgo: 95))), "source": "whatsapp", "toolSteps": [], "attachments": []},
          {"id": "w4", "role": "assistant", "content": "Reminder set for **12:30** today: book the car service.", "createdAt": \#(s(clock.iso(minutesAgo: 95))), "source": "whatsapp",
           "toolSteps": [{"tool": "reminders_create", "status": "ok", "summary": "Reminder at 12:30"}], "attachments": []}
        ]
        """#
    }

    static func genericMessages(_ preview: String, _ clock: DemoClock) -> String {
        """
        [
          {"id": "g1", "role": "user", "content": "Can you pick this back up where we left off?", "createdAt": \(s(clock.iso(minutesAgo: 70))), "source": "web", "toolSteps": [], "attachments": []},
          {"id": "g2", "role": "assistant", "content": \(s(preview + "\n\nShall I carry on from there?")), "createdAt": \(s(clock.iso(minutesAgo: 69))), "source": "web", "toolSteps": [], "attachments": []}
        ]
        """
    }

    // MARK: - News

    struct DemoStory {
        let source: String
        let sourceLabel: String
        let id: String
        let title: String
        let url: String
        let discussionUrl: String
        let domain: String
        let author: String?
        let minutesAgo: Double
        let score: Int
        let comments: Int
        let heat: Double
        let read: Bool
        let kept: Bool
        let alsoOn: [String]
        let correlationWhy: String?
        let correlationNames: [String]
        let correlationNotes: Int

        var key: String { "\(source):\(id)" }
    }

    static let demoStories: [DemoStory] = [
        DemoStory(source: "hn", sourceLabel: "Hacker News", id: "41200001",
                  title: "Show HN: A 40-line SQLite extension for vector search",
                  url: "https://github.com/example/sqlite-vec-tiny", discussionUrl: "https://news.ycombinator.com/item?id=41200001",
                  domain: "github.com", author: "tinyvec", minutesAgo: 25, score: 412, comments: 138, heat: 0.94,
                  read: false, kept: false, alsoOn: ["lobsters"],
                  correlationWhy: "You kept three notes on vector indexes this month.", correlationNames: ["SQLite", "pgvector"], correlationNotes: 3),
        DemoStory(source: "bbc", sourceLabel: "BBC", id: "c0demo0001",
                  title: "Regulator opens consultation on independent audits of AI models",
                  url: "https://www.bbc.co.uk/news/articles/c0demo0001", discussionUrl: "https://www.bbc.co.uk/news/articles/c0demo0001",
                  domain: "bbc.co.uk", author: nil, minutesAgo: 62, score: 0, comments: 0, heat: 0.81,
                  read: false, kept: false, alsoOn: [],
                  correlationWhy: "Matches your policy analysis notes on model assurance.", correlationNames: ["AI assurance", "Regulation"], correlationNotes: 5),
        DemoStory(source: "ft", sourceLabel: "Financial Times", id: "demo-ft-7731",
                  title: "Chipmakers race to secure advanced packaging capacity",
                  url: "https://www.ft.com/content/demo-ft-7731", discussionUrl: "https://www.ft.com/content/demo-ft-7731",
                  domain: "ft.com", author: nil, minutesAgo: 118, score: 0, comments: 0, heat: 0.72,
                  read: false, kept: false, alsoOn: ["hn"],
                  correlationWhy: nil, correlationNames: [], correlationNotes: 0),
        DemoStory(source: "lobsters", sourceLabel: "Lobsters", id: "x7demo",
                  title: "Why SwiftUI's layout system surprises everyone exactly once",
                  url: "https://example.dev/posts/swiftui-layout", discussionUrl: "https://lobste.rs/s/x7demo",
                  domain: "example.dev", author: "layoutnerd", minutesAgo: 170, score: 58, comments: 21, heat: 0.64,
                  read: true, kept: false, alsoOn: [],
                  correlationWhy: "You have an open thread on SwiftUI tab bars.", correlationNames: ["SwiftUI"], correlationNotes: 2),
        DemoStory(source: "hn", sourceLabel: "Hacker News", id: "41200017",
                  title: "Postgres 18's asynchronous I/O, measured on real workloads",
                  url: "https://example.org/blog/pg18-aio", discussionUrl: "https://news.ycombinator.com/item?id=41200017",
                  domain: "example.org", author: "pgperf", minutesAgo: 290, score: 233, comments: 91, heat: 0.61,
                  read: false, kept: true, alsoOn: ["lobsters"],
                  correlationWhy: "Postgres is the most-noted entity in your graph.", correlationNames: ["PostgreSQL"], correlationNotes: 14),
        DemoStory(source: "bbc", sourceLabel: "BBC", id: "c0demo0002",
                  title: "Rail operators trial tap-in season tickets on commuter routes",
                  url: "https://www.bbc.co.uk/news/articles/c0demo0002", discussionUrl: "https://www.bbc.co.uk/news/articles/c0demo0002",
                  domain: "bbc.co.uk", author: nil, minutesAgo: 410, score: 0, comments: 0, heat: 0.48,
                  read: false, kept: false, alsoOn: [],
                  correlationWhy: nil, correlationNames: [], correlationNotes: 0),
        DemoStory(source: "hn", sourceLabel: "Hacker News", id: "41199950",
                  title: "Ask HN: What does your home server look like in 2026?",
                  url: "https://news.ycombinator.com/item?id=41199950", discussionUrl: "https://news.ycombinator.com/item?id=41199950",
                  domain: "news.ycombinator.com", author: "selfhoster", minutesAgo: 540, score: 301, comments: 402, heat: 0.57,
                  read: false, kept: false, alsoOn: [],
                  correlationWhy: nil, correlationNames: [], correlationNotes: 0),
        DemoStory(source: "ft", sourceLabel: "Financial Times", id: "demo-ft-7702",
                  title: "Pension funds weigh a bigger allocation to infrastructure",
                  url: "https://www.ft.com/content/demo-ft-7702", discussionUrl: "https://www.ft.com/content/demo-ft-7702",
                  domain: "ft.com", author: nil, minutesAgo: 720, score: 0, comments: 0, heat: 0.39,
                  read: false, kept: false, alsoOn: [],
                  correlationWhy: nil, correlationNames: [], correlationNotes: 0),
    ]

    static func alsoJSON(_ story: DemoStory) -> String {
        list(story.alsoOn.map { other in
            let label = other == "lobsters" ? "Lobsters" : "Hacker News"
            let discussion = other == "lobsters" ? "https://lobste.rs/s/demo\(story.id.suffix(3))" : "https://news.ycombinator.com/item?id=4119\(story.id.suffix(4))"
            return "{\"source\": \(s(other)), \"sourceLabel\": \(s(label)), \"discussionUrl\": \(s(discussion)), \"score\": \(other == "lobsters" ? 34 : 187), \"commentCount\": \(other == "lobsters" ? 12 : 64)}"
        })
    }

    static func storyJSON(_ story: DemoStory, rank: Int, clock: DemoClock) -> String {
        var correlation = "null"
        if let why = story.correlationWhy {
            correlation = """
            {"score": \(n(story.heat - 0.1)), "names": \(list(story.correlationNames.map { s($0) })), "why": \(s(why)), "evidence": {"notes": \(story.correlationNotes), "lastSeen": \(s(clock.iso(minutesAgo: 60 * 24 * 3)))}}
            """
        }
        return """
        {"key": \(s(story.key)), "source": \(s(story.source)), "sourceLabel": \(s(story.sourceLabel)), "id": \(s(story.id)),
         "title": \(s(story.title)), "url": \(s(story.url)), "discussionUrl": \(s(story.discussionUrl)), "domain": \(s(story.domain)),
         "author": \(s(story.author)), "publishedAt": \(s(clock.iso(minutesAgo: story.minutesAgo))),
         "score": \(story.score), "commentCount": \(story.comments), "heat": \(n(story.heat)), "rank": \(rank),
         "read": \(b(story.read)), "kept": \(b(story.kept)), "alsoOn": \(alsoJSON(story)), "correlation": \(correlation)}
        """
    }

    static func newsFeed(view: String, sort: String, clock: DemoClock) -> String {
        var stories = demoStories
        switch view {
        case "for-you":
            stories = stories.filter { $0.correlationWhy != nil }
        case "favourites":
            stories = stories.filter { $0.kept || $0.read }
        case "best":
            stories.sort { $0.heat > $1.heat }
        default:
            break
        }
        let objects = stories.enumerated().map { storyJSON($0.element, rank: $0.offset + 1, clock: clock) }
        return """
        {
          "view": \(s(view)), "sort": \(s(sort)), "updatedAt": \(s(clock.iso(minutesAgo: 6))), "cached": false,
          "newSinceLast": 5, "anchorCount": 42,
          "sources": [
            {"source": "hn", "label": "Hacker News", "count": 3, "ok": true, "error": null},
            {"source": "lobsters", "label": "Lobsters", "count": 1, "ok": true, "error": null},
            {"source": "bbc", "label": "BBC", "count": 2, "ok": true, "error": null},
            {"source": "ft", "label": "Financial Times", "count": 2, "ok": true, "error": null}
          ],
          "stories": \(list(objects))
        }
        """
    }

    static func article(source: String, id: String, clock: DemoClock) -> String? {
        guard let story = demoStories.first(where: { $0.source == source && $0.id == id }) else { return nil }
        let content = """
        \(story.title).

        This is demonstration text standing in for the extracted article. The real desk fetches the page, strips the navigation and the adverts, and keeps the body so it can be read here without leaving the app.

        The second paragraph carries on in the same register. It exists so the reading column has enough text to show its measure, its leading and how a long paragraph wraps on a phone held in one hand.

        A third, shorter paragraph closes the piece.
        """
        return """
        {
          "story": {"key": \(s(story.key)), "source": \(s(story.source)), "sourceLabel": \(s(story.sourceLabel)), "id": \(s(story.id)),
                    "title": \(s(story.title)), "url": \(s(story.url)), "discussionUrl": \(s(story.discussionUrl)), "domain": \(s(story.domain)),
                    "author": \(s(story.author)), "publishedAt": \(s(clock.iso(minutesAgo: story.minutesAgo))),
                    "score": \(story.score), "commentCount": \(story.comments), "heat": \(n(story.heat)), "alsoOn": \(alsoJSON(story))},
          "mode": "article",
          "contentTitle": \(s(story.title)),
          "content": \(s(content)),
          "summary": \(s("A short summary of the piece: what happened, who it affects, and why it surfaced on your desk.")),
          "finalUrl": \(s(story.url)),
          "truncated": false,
          "message": null,
          "favourite": \(b(story.kept))
        }
        """
    }

    // MARK: - Alerts

    struct DemoAlert {
        let id: String
        let category: String
        let title: String
        let body: String
        let url: String?
        let severity: String
        let minutesAgo: Double
        let read: Bool
    }

    static func demoAlerts(_ clock: DemoClock) -> [DemoAlert] {
        [
            DemoAlert(id: "demo-alert-1", category: "deploy", title: "Release 412 is live", body: "The glass overhaul shipped. All checks green.",
                      url: "/admin/releases", severity: "info", minutesAgo: 14, read: false),
            DemoAlert(id: "demo-alert-2", category: "health", title: "Readiness is up to 72", body: "Primed: sleep and HRV back above baseline.",
                      url: "/health", severity: "info", minutesAgo: 60 * 3, read: false),
            DemoAlert(id: "demo-alert-3", category: "uptime", title: "A page was slow for 4 minutes", body: "/news answered in 3.1s at peak, then recovered.",
                      url: nil, severity: "warn", minutesAgo: 60 * 7, read: true),
            DemoAlert(id: "demo-alert-4", category: "build", title: "Build finished: route heatmap", body: "Opened a pull request with 6 files changed.",
                      url: "/jkai/builds", severity: "info", minutesAgo: 60 * 20, read: true),
            DemoAlert(id: "demo-alert-5", category: "chat", title: "A turn is waiting on you", body: "The backup plan thread asked a question back.",
                      url: "/jkai", severity: "alert", minutesAgo: 60 * 26, read: true),
            DemoAlert(id: "demo-alert-6", category: "news", title: "A story matches your notes", body: "Show HN: A 40-line SQLite extension for vector search",
                      url: "/news", severity: "info", minutesAgo: 60 * 30, read: true),
        ]
    }

    static func alertFeed(_ clock: DemoClock) -> String {
        let recent = demoAlerts(clock).map { alert in
            """
            {"id": \(s(alert.id)), "category": \(s(alert.category)), "title": \(s(alert.title)), "body": \(s(alert.body)), "url": \(s(alert.url)), "severity": \(s(alert.severity)), "createdAt": \(s(clock.iso(minutesAgo: alert.minutesAgo))), "read": \(b(alert.read))}
            """
        }
        // `pending` stays empty: the app raises a local notification for each
        // one, and a demo must not fire real banners.
        return "{\"pending\": [], \"recent\": \(list(recent)), \"unread\": 2}"
    }

    struct DemoRoute {
        let id: String
        let label: String
        let description: String
        var whatsapp: Bool
        var native: Bool
        var minIntervalSeconds: Int
        let customised: Bool
    }

    static let demoRoutes: [DemoRoute] = [
        DemoRoute(id: "health", label: "Health", description: "Readiness changes, missed syncs, illness signals.",
                  whatsapp: true, native: true, minIntervalSeconds: 10800, customised: true),
        DemoRoute(id: "chat", label: "Chat", description: "A turn that stalled or needs an answer.",
                  whatsapp: true, native: true, minIntervalSeconds: 0, customised: false),
        DemoRoute(id: "build", label: "Builds", description: "Autonomous builds finishing or failing.",
                  whatsapp: false, native: true, minIntervalSeconds: 3600, customised: false),
        DemoRoute(id: "deploy", label: "Deploys", description: "Production releases and rollbacks.",
                  whatsapp: true, native: false, minIntervalSeconds: 0, customised: true),
        DemoRoute(id: "uptime", label: "Uptime", description: "A public page stopped answering.",
                  whatsapp: true, native: true, minIntervalSeconds: 900, customised: false),
        DemoRoute(id: "news", label: "News", description: "A story that matches something you keep notes on.",
                  whatsapp: false, native: true, minIntervalSeconds: 21600, customised: false),
        DemoRoute(id: "intel", label: "Intelligence", description: "New entities and links found overnight.",
                  whatsapp: false, native: false, minIntervalSeconds: 0, customised: false),
    ]

    /// The routes, with a PUT's change applied so a toggle does not spring back.
    /// Not remembered: the next GET is the canned list again.
    static func alertRoutes(change body: Data?) -> String {
        var routes = demoRoutes
        if let body,
           let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
           let category = object["category"] as? String,
           let index = routes.firstIndex(where: { $0.id == category }) {
            if let value = object["whatsapp"] as? Bool { routes[index].whatsapp = value }
            if let value = object["native"] as? Bool { routes[index].native = value }
            if let value = object["minIntervalSeconds"] as? Int { routes[index].minIntervalSeconds = value }
        }
        let objects = routes.map { r in
            "{\"id\": \(s(r.id)), \"label\": \(s(r.label)), \"description\": \(s(r.description)), \"whatsapp\": \(b(r.whatsapp)), \"native\": \(b(r.native)), \"minIntervalSeconds\": \(r.minIntervalSeconds), \"customised\": \(b(r.customised))}"
        }
        return "{\"categories\": \(list(objects))}"
    }
}

// MARK: - Heart rate, for the Health tab's day chart

extension SRDemoFixtures {
    /// A plausible day: low and flat through a night's sleep, a rise on
    /// waking, the desk, an evening run, and back down. Built rather than
    /// canned so the chart always ends at "now".
    static func heartTimeline(now: Date) -> HeartTimeline {
        let to = Int(now.timeIntervalSince1970)
        let from = to - 24 * 3600
        let step = 900
        let iso = ISO8601DateFormatter()
        var bins: [[Double]] = []
        let runStart = to - 5 * 3600, runEnd = runStart + 48 * 60
        let sleepStart = to - 20 * 3600, sleepEnd = sleepStart + Int(7.4 * 3600)
        var t = from
        var i = 0
        while t < to {
            let bpm: Double
            if t >= sleepStart && t < sleepEnd {
                bpm = 51 + 3 * sin(Double(i) / 3)
            } else if t >= runStart && t < runEnd {
                bpm = 138 + 12 * sin(Double(t - runStart) / 900)
            } else {
                bpm = 68 + 9 * sin(Double(i) / 5) + Double(i % 3)
            }
            // A gap, as a real day has: the phone was not worn for an hour.
            if !(t > to - 11 * 3600 && t < to - 10 * 3600) {
                bins.append([Double(t), bpm.rounded()])
            }
            t += step
            i += 1
        }
        func stamp(_ s: Int) -> String { iso.string(from: Date(timeIntervalSince1970: TimeInterval(s))) }
        return HeartTimeline(
            from: from,
            to: to,
            heartRate: .init(seconds: step, bins: bins),
            restingHeartRate: .init(value: 52, at: stamp(sleepEnd)),
            workouts: [.init(activity: "running", start: stamp(runStart), end: stamp(runEnd))],
            sleep: [
                .init(stage: "asleepCore", start: stamp(sleepStart), end: stamp(sleepStart + 3 * 3600)),
                .init(stage: "asleepDeep", start: stamp(sleepStart + 3 * 3600), end: stamp(sleepEnd)),
            ]
        )
    }
}

// MARK: - /health's digest

extension SRDemoFixtures {
    /// A REAL digest: SR-Health's `toHubDigest` run over /health's own mock
    /// series (`tests/routes/health-hub.test.ts` writes it with
    /// `HUB_SAMPLE_OUT`), not a hand-written guess at the shape. Regenerate it
    /// there when the contract moves, rather than editing it here.
    static let healthHub: String = #"""
{
  "generatedAt": "2026-09-24T07:30:00.000Z",
  "syncedAgoSeconds": 1260,
  "isMock": true,
  "lede": "Today: recovery at 28% (-32 on the seven-day average), a resting heart rate 4 bpm over baseline and 5.6 hours of sleep. The composite reads recovery priority.",
  "readiness": {
    "score": 46,
    "label": "Recovery Priority",
    "recommendation": "Light movement only",
    "factors": [
      {
        "key": "recovery",
        "label": "Recovery",
        "score": 28,
        "weight": 0.4
      },
      {
        "key": "hrvTrend",
        "label": "HRV trend",
        "score": 38,
        "weight": 0.2
      },
      {
        "key": "sleepQuality",
        "label": "Sleep quality",
        "score": 52,
        "weight": 0.2
      },
      {
        "key": "loadBalance",
        "label": "Load balance",
        "score": 85,
        "weight": 0.2
      }
    ]
  },
  "planner": {
    "headline": "Readiness 46 clears the walk-substitution gate (<40) but not the steady-climb gate (<55), so the climbing stays steady.",
    "detail": "ACWR 0.57 sits in the undertraining band, so the target gains 10% on the recent median."
  },
  "tiles": [
    {
      "key": "recovery",
      "label": "Recovery",
      "display": "28",
      "unit": "%",
      "foot": "↓32 vs 7d · wk 60%",
      "tone": "watch",
      "series": [
        63,
        61,
        68,
        77,
        56,
        36,
        48,
        70,
        28
      ]
    },
    {
      "key": "hrv",
      "label": "HRV RMSSD",
      "display": "31",
      "unit": "ms",
      "foot": "7d mean 50 · trough 31",
      "tone": "watch",
      "series": [
        54,
        53,
        59,
        59,
        50,
        38,
        47,
        53,
        31
      ]
    },
    {
      "key": "rhr",
      "label": "Resting HR",
      "display": "64",
      "unit": "bpm",
      "foot": "+4 on 60 · peak 65",
      "tone": "watch",
      "series": [
        58,
        60,
        59,
        59,
        61,
        63,
        60,
        61,
        64
      ]
    },
    {
      "key": "sleep",
      "label": "Sleep",
      "display": "5.6",
      "unit": "h",
      "foot": "30d mean 7.2",
      "tone": "watch",
      "series": [
        7.23,
        7.08,
        7.04,
        8.01,
        6.52,
        6.68,
        6.26,
        8.12,
        5.6
      ]
    },
    {
      "key": "volume",
      "label": "Week volume",
      "display": "26.9",
      "unit": "km",
      "foot": "3 sessions · 4h39m · 7wk low",
      "tone": "watch",
      "series": [
        39.68,
        37.06,
        30.74,
        33.38,
        33.65,
        27.78,
        26.87
      ]
    },
    {
      "key": "vo2max",
      "label": "VO₂max",
      "display": "45.1",
      "unit": null,
      "foot": "+0.31/mo · 71st pct",
      "tone": "good",
      "series": [
        44.4,
        44.1,
        44.4,
        44.6,
        44.9,
        45,
        44.8,
        44.7,
        45.1
      ]
    }
  ],
  "instruments": [
    {
      "key": "acwr",
      "label": "ACWR · EWMA",
      "window": "28d",
      "display": "0.57",
      "unit": null,
      "tone": "watch",
      "reading": "0.57 · undertraining",
      "meaning": "Acute 7-day EWMA against chronic 28-day. Below 0.8 is undertraining, and the planner reads it as licence to add 10%. Two more weeks this thin and it drops into detraining."
    },
    {
      "key": "monotony",
      "label": "Monotony · strain",
      "window": "7d",
      "display": "0.7",
      "unit": null,
      "tone": "good",
      "reading": "0.7 · low",
      "meaning": "Mean ÷ SD of daily load, strain 196. Low, which on a thin week usually means one session and six rest days rather than deliberate variation."
    },
    {
      "key": "polarised",
      "label": "Intensity mix · 28d",
      "window": "28d",
      "display": "88",
      "unit": "% easy",
      "tone": "none",
      "reading": "88% easy",
      "meaning": "Verdict: Pyramid, not polarised — polarised needs 80% easy AND 10% hard. No junk middle, which is the real trap. One weekly hard effort would tip it. Hard share is 2%."
    },
    {
      "key": "sri",
      "label": "Sleep regularity · SRI",
      "window": "30d",
      "display": "94",
      "unit": null,
      "tone": "good",
      "reading": "94 · regular",
      "meaning": "Phillips 2017 index: the chance any two nights agree minute-for-minute. At or past the 85 target — bed and wake times are landing in the same window."
    },
    {
      "key": "circadian",
      "label": "Circadian drift",
      "window": "21d",
      "display": "+1.0",
      "unit": "h",
      "tone": "watch",
      "reading": "+1.0 h · drift late",
      "meaning": "Sleep midpoint has moved 1h01m later over the last week versus the fortnight before. Anything past 1 hour is flagged. Phase, not duration — and the two go wrong together."
    },
    {
      "key": "autonomic",
      "label": "Autonomic balance",
      "window": "28d",
      "display": "44",
      "unit": null,
      "tone": "none",
      "reading": "44 · slightly suppressed",
      "meaning": "HRV z minus RHR z, mapped to 0–100. Under the midpoint: HRV below its own baseline while resting heart rate sits above. Mild, consistent, and consistent with short sleep."
    },
    {
      "key": "balance",
      "label": "Sleep balance",
      "window": "7 nights",
      "display": "−43",
      "unit": "min/night",
      "tone": "watch",
      "reading": "−43 min/night · short",
      "meaning": "Average actual sleep 7h27m against 8h10m fresh need; 6 of 7 nights below it. Carried debt is excluded and WHOOP's nap adjustment is included, so each minute is counted once. Actual sleep is +25 min/night versus the preceding nights. WHOOP's latest separate debt adjustment is 20 minutes; it is not summed here."
    },
    {
      "key": "efficiency",
      "label": "Efficiency · beats/km",
      "window": "48 outings",
      "display": "1213",
      "unit": null,
      "tone": "none",
      "reading": "1213 · vs 1194 baseline",
      "meaning": "Heartbeats spent per kilometre — the cleanest read on whether fitness is moving. Up 2% on baseline, on 48 outings. Needs volume before it means anything; watch, don't act."
    }
  ],
  "forecasts": [
    {
      "key": "sleep",
      "label": "Sleep · 30d mean",
      "unit": "h",
      "horizonDays": 90,
      "now": 7.179,
      "projected": 7.281,
      "low": 4.967,
      "high": 9.595,
      "reading": "Rising at +0.03 a month.",
      "history": [
        {
          "date": "2026-08-28",
          "value": 7.51
        },
        {
          "date": "2026-08-29",
          "value": 7.21
        },
        {
          "date": "2026-08-30",
          "value": 7.18
        },
        {
          "date": "2026-08-31",
          "value": 7.2
        },
        {
          "date": "2026-09-01",
          "value": 7.17
        },
        {
          "date": "2026-09-02",
          "value": 7.14
        },
        {
          "date": "2026-09-03",
          "value": 6.89
        },
        {
          "date": "2026-09-04",
          "value": 6.89
        },
        {
          "date": "2026-09-05",
          "value": 7.1
        },
        {
          "date": "2026-09-06",
          "value": 7.23
        },
        {
          "date": "2026-09-07",
          "value": 7.22
        },
        {
          "date": "2026-09-08",
          "value": 7.31
        },
        {
          "date": "2026-09-09",
          "value": 7.36
        },
        {
          "date": "2026-09-10",
          "value": 7.4
        },
        {
          "date": "2026-09-11",
          "value": 7.3
        },
        {
          "date": "2026-09-12",
          "value": 7.12
        },
        {
          "date": "2026-09-13",
          "value": 6.93
        },
        {
          "date": "2026-09-14",
          "value": 6.89
        },
        {
          "date": "2026-09-15",
          "value": 6.92
        },
        {
          "date": "2026-09-16",
          "value": 6.85
        },
        {
          "date": "2026-09-17",
          "value": 6.81
        },
        {
          "date": "2026-09-18",
          "value": 6.89
        },
        {
          "date": "2026-09-19",
          "value": 6.98
        },
        {
          "date": "2026-09-20",
          "value": 7.19
        },
        {
          "date": "2026-09-21",
          "value": 7.45
        },
        {
          "date": "2026-09-22",
          "value": 7.45
        },
        {
          "date": "2026-09-23",
          "value": 7.54
        },
        {
          "date": "2026-09-24",
          "value": 7.45
        }
      ],
      "cone": [
        {
          "date": "2026-09-24",
          "value": 7.179,
          "low": 7.179,
          "high": 7.179
        },
        {
          "date": "2026-10-01",
          "value": 7.187,
          "low": 6.542,
          "high": 7.832
        },
        {
          "date": "2026-10-08",
          "value": 7.195,
          "low": 6.282,
          "high": 8.108
        },
        {
          "date": "2026-10-15",
          "value": 7.203,
          "low": 6.085,
          "high": 8.321
        },
        {
          "date": "2026-10-22",
          "value": 7.211,
          "low": 5.92,
          "high": 8.502
        },
        {
          "date": "2026-10-29",
          "value": 7.219,
          "low": 5.776,
          "high": 8.662
        },
        {
          "date": "2026-11-05",
          "value": 7.226,
          "low": 5.645,
          "high": 8.807
        },
        {
          "date": "2026-11-12",
          "value": 7.234,
          "low": 5.527,
          "high": 8.941
        },
        {
          "date": "2026-11-19",
          "value": 7.242,
          "low": 5.417,
          "high": 9.067
        },
        {
          "date": "2026-11-26",
          "value": 7.25,
          "low": 5.314,
          "high": 9.186
        },
        {
          "date": "2026-12-03",
          "value": 7.258,
          "low": 5.217,
          "high": 9.299
        },
        {
          "date": "2026-12-10",
          "value": 7.266,
          "low": 5.126,
          "high": 9.406
        },
        {
          "date": "2026-12-17",
          "value": 7.274,
          "low": 5.039,
          "high": 9.509
        },
        {
          "date": "2026-12-23",
          "value": 7.281,
          "low": 4.967,
          "high": 9.595
        }
      ]
    },
    {
      "key": "hrv",
      "label": "HRV · 7d mean",
      "unit": "ms",
      "horizonDays": 90,
      "now": 45.939,
      "projected": 23.365,
      "low": 0,
      "high": 54.076,
      "reading": "Declining at −7.53 a month.",
      "history": [
        {
          "date": "2026-08-28",
          "value": 52.86
        },
        {
          "date": "2026-08-29",
          "value": 53.14
        },
        {
          "date": "2026-08-30",
          "value": 52.14
        },
        {
          "date": "2026-08-31",
          "value": 52.14
        },
        {
          "date": "2026-09-01",
          "value": 53.14
        },
        {
          "date": "2026-09-02",
          "value": 53.86
        },
        {
          "date": "2026-09-03",
          "value": 52
        },
        {
          "date": "2026-09-04",
          "value": 52.71
        },
        {
          "date": "2026-09-05",
          "value": 50.71
        },
        {
          "date": "2026-09-06",
          "value": 51.57
        },
        {
          "date": "2026-09-07",
          "value": 51
        },
        {
          "date": "2026-09-08",
          "value": 50.71
        },
        {
          "date": "2026-09-09",
          "value": 49.57
        },
        {
          "date": "2026-09-10",
          "value": 50.71
        },
        {
          "date": "2026-09-11",
          "value": 48
        },
        {
          "date": "2026-09-12",
          "value": 48.29
        },
        {
          "date": "2026-09-13",
          "value": 45.29
        },
        {
          "date": "2026-09-14",
          "value": 44.14
        },
        {
          "date": "2026-09-15",
          "value": 44.86
        },
        {
          "date": "2026-09-16",
          "value": 42.14
        },
        {
          "date": "2026-09-17",
          "value": 41.71
        },
        {
          "date": "2026-09-18",
          "value": 43.14
        },
        {
          "date": "2026-09-19",
          "value": 46.14
        },
        {
          "date": "2026-09-20",
          "value": 48.29
        },
        {
          "date": "2026-09-21",
          "value": 50.14
        },
        {
          "date": "2026-09-22",
          "value": 50.71
        },
        {
          "date": "2026-09-23",
          "value": 52.14
        },
        {
          "date": "2026-09-24",
          "value": 49.86
        }
      ],
      "cone": [
        {
          "date": "2026-09-24",
          "value": 45.939,
          "low": 45.939,
          "high": 45.939
        },
        {
          "date": "2026-10-01",
          "value": 44.183,
          "low": 35.618,
          "high": 52.748
        },
        {
          "date": "2026-10-08",
          "value": 42.428,
          "low": 30.315,
          "high": 54.541
        },
        {
          "date": "2026-10-15",
          "value": 40.672,
          "low": 25.837,
          "high": 55.507
        },
        {
          "date": "2026-10-22",
          "value": 38.916,
          "low": 21.786,
          "high": 56.046
        },
        {
          "date": "2026-10-29",
          "value": 37.16,
          "low": 18.008,
          "high": 56.312
        },
        {
          "date": "2026-11-05",
          "value": 35.405,
          "low": 14.425,
          "high": 56.385
        },
        {
          "date": "2026-11-12",
          "value": 33.649,
          "low": 10.989,
          "high": 56.309
        },
        {
          "date": "2026-11-19",
          "value": 31.893,
          "low": 7.668,
          "high": 56.118
        },
        {
          "date": "2026-11-26",
          "value": 30.137,
          "low": 4.442,
          "high": 55.832
        },
        {
          "date": "2026-12-03",
          "value": 28.382,
          "low": 1.298,
          "high": 55.466
        },
        {
          "date": "2026-12-10",
          "value": 26.626,
          "low": 0,
          "high": 55.032
        },
        {
          "date": "2026-12-17",
          "value": 24.87,
          "low": 0,
          "high": 54.54
        },
        {
          "date": "2026-12-23",
          "value": 23.365,
          "low": 0,
          "high": 54.076
        }
      ]
    },
    {
      "key": "vo2max",
      "label": "VO₂max",
      "unit": null,
      "horizonDays": 90,
      "now": 44.896,
      "projected": 44.931,
      "low": 44.51,
      "high": 45.352,
      "reading": "Rising at +0.01 a month.",
      "history": [
        {
          "date": "2026-08-26",
          "value": 44.97
        },
        {
          "date": "2026-08-29",
          "value": 44.97
        },
        {
          "date": "2026-09-01",
          "value": 44.9
        },
        {
          "date": "2026-09-04",
          "value": 44.8
        },
        {
          "date": "2026-09-07",
          "value": 44.8
        },
        {
          "date": "2026-09-10",
          "value": 44.77
        },
        {
          "date": "2026-09-13",
          "value": 44.9
        },
        {
          "date": "2026-09-16",
          "value": 44.83
        },
        {
          "date": "2026-09-19",
          "value": 44.97
        },
        {
          "date": "2026-09-22",
          "value": 45
        }
      ],
      "cone": [
        {
          "date": "2026-09-22",
          "value": 44.896,
          "low": 44.896,
          "high": 44.896
        },
        {
          "date": "2026-09-29",
          "value": 44.899,
          "low": 44.782,
          "high": 45.016
        },
        {
          "date": "2026-10-06",
          "value": 44.902,
          "low": 44.736,
          "high": 45.068
        },
        {
          "date": "2026-10-13",
          "value": 44.904,
          "low": 44.701,
          "high": 45.107
        },
        {
          "date": "2026-10-20",
          "value": 44.907,
          "low": 44.672,
          "high": 45.142
        },
        {
          "date": "2026-10-27",
          "value": 44.91,
          "low": 44.648,
          "high": 45.172
        },
        {
          "date": "2026-11-03",
          "value": 44.912,
          "low": 44.625,
          "high": 45.199
        },
        {
          "date": "2026-11-10",
          "value": 44.915,
          "low": 44.605,
          "high": 45.225
        },
        {
          "date": "2026-11-17",
          "value": 44.918,
          "low": 44.586,
          "high": 45.25
        },
        {
          "date": "2026-11-24",
          "value": 44.92,
          "low": 44.568,
          "high": 45.272
        },
        {
          "date": "2026-12-01",
          "value": 44.923,
          "low": 44.552,
          "high": 45.294
        },
        {
          "date": "2026-12-08",
          "value": 44.926,
          "low": 44.537,
          "high": 45.315
        },
        {
          "date": "2026-12-15",
          "value": 44.928,
          "low": 44.522,
          "high": 45.334
        },
        {
          "date": "2026-12-21",
          "value": 44.931,
          "low": 44.51,
          "high": 45.352
        }
      ]
    },
    {
      "key": "acwr",
      "label": "ACWR",
      "unit": null,
      "horizonDays": 90,
      "now": 0.646,
      "projected": 0.748,
      "low": 0.555,
      "high": 0.941,
      "reading": "Rising at +0.03 a month.",
      "history": [
        {
          "date": "2026-08-28",
          "value": 0.59
        },
        {
          "date": "2026-08-29",
          "value": 0.6
        },
        {
          "date": "2026-08-30",
          "value": 0.6
        },
        {
          "date": "2026-08-31",
          "value": 0.61
        },
        {
          "date": "2026-09-01",
          "value": 0.62
        },
        {
          "date": "2026-09-02",
          "value": 0.62
        },
        {
          "date": "2026-09-03",
          "value": 0.63
        },
        {
          "date": "2026-09-04",
          "value": 0.63
        },
        {
          "date": "2026-09-05",
          "value": 0.64
        },
        {
          "date": "2026-09-06",
          "value": 0.64
        },
        {
          "date": "2026-09-07",
          "value": 0.65
        },
        {
          "date": "2026-09-08",
          "value": 0.65
        },
        {
          "date": "2026-09-09",
          "value": 0.64
        },
        {
          "date": "2026-09-10",
          "value": 0.64
        },
        {
          "date": "2026-09-11",
          "value": 0.64
        },
        {
          "date": "2026-09-12",
          "value": 0.64
        },
        {
          "date": "2026-09-13",
          "value": 0.64
        },
        {
          "date": "2026-09-14",
          "value": 0.63
        },
        {
          "date": "2026-09-15",
          "value": 0.63
        },
        {
          "date": "2026-09-16",
          "value": 0.63
        },
        {
          "date": "2026-09-17",
          "value": 0.63
        },
        {
          "date": "2026-09-18",
          "value": 0.63
        },
        {
          "date": "2026-09-19",
          "value": 0.63
        },
        {
          "date": "2026-09-20",
          "value": 0.63
        },
        {
          "date": "2026-09-21",
          "value": 0.64
        },
        {
          "date": "2026-09-22",
          "value": 0.64
        },
        {
          "date": "2026-09-23",
          "value": 0.64
        },
        {
          "date": "2026-09-24",
          "value": 0.65
        }
      ],
      "cone": [
        {
          "date": "2026-09-24",
          "value": 0.646,
          "low": 0.646,
          "high": 0.646
        },
        {
          "date": "2026-10-01",
          "value": 0.654,
          "low": 0.6,
          "high": 0.708
        },
        {
          "date": "2026-10-08",
          "value": 0.662,
          "low": 0.586,
          "high": 0.738
        },
        {
          "date": "2026-10-15",
          "value": 0.67,
          "low": 0.577,
          "high": 0.763
        },
        {
          "date": "2026-10-22",
          "value": 0.678,
          "low": 0.571,
          "high": 0.785
        },
        {
          "date": "2026-10-29",
          "value": 0.686,
          "low": 0.566,
          "high": 0.806
        },
        {
          "date": "2026-11-05",
          "value": 0.694,
          "low": 0.562,
          "high": 0.826
        },
        {
          "date": "2026-11-12",
          "value": 0.702,
          "low": 0.56,
          "high": 0.844
        },
        {
          "date": "2026-11-19",
          "value": 0.709,
          "low": 0.557,
          "high": 0.861
        },
        {
          "date": "2026-11-26",
          "value": 0.717,
          "low": 0.556,
          "high": 0.878
        },
        {
          "date": "2026-12-03",
          "value": 0.725,
          "low": 0.555,
          "high": 0.895
        },
        {
          "date": "2026-12-10",
          "value": 0.733,
          "low": 0.555,
          "high": 0.911
        },
        {
          "date": "2026-12-17",
          "value": 0.741,
          "low": 0.555,
          "high": 0.927
        },
        {
          "date": "2026-12-23",
          "value": 0.748,
          "low": 0.555,
          "high": 0.941
        }
      ]
    }
  ],
  "moves": [
    {
      "rank": 1,
      "title": "FIXED LIGHTS-OUT WINDOW",
      "buys": "Pulls the sleep midpoint back inside the 1-hour flag. Brings the seven-night sleep balance back toward even.",
      "costs": "Evening time, every night.",
      "leverage": "4/5 · 2 INSTRUMENTS"
    },
    {
      "rank": 2,
      "title": "ONE LONG EASY DAY A WEEK",
      "buys": "ACWR 0.57→0.85, into the band where fitness builds. Weekly volume 26.9→33.7 km, back on the twelve-week median. Keeps the easy share above 80%.",
      "costs": "Two to three hours of calendar a week. Adding volume while the seven-night sleep balance is short can widen the nightly gap.",
      "leverage": "4/5 · 2 INSTRUMENTS"
    },
    {
      "rank": 3,
      "title": "TIP THE MIX TO POLARISED",
      "buys": "The strongest single stimulus for VO₂max there is. Doubles as segment PB attempts, so it is measurable.",
      "costs": "The highest injury and HRV cost on this list. Should not start before the moves above it have run four weeks.",
      "leverage": "3/5 · GATED ON 01+02"
    },
    {
      "rank": 4,
      "title": "BOOK ONE BIG DAY",
      "buys": "Turns the long easy day from discipline into preparation. Fixes the horizon every other number is measured against.",
      "costs": "A deadline can override the readiness gates. Commit to the date, not to going regardless of what the panel says.",
      "leverage": "3/5 · BEHAVIOURAL"
    },
    {
      "rank": 5,
      "title": "DO NOTHING NEW · HOLD AND WATCH",
      "buys": "Zero cost. Keeps the tripwires as the whole system until something actually trips.",
      "costs": "Zero cost, and a slope: doing nothing is still a decision. ACWR is already at 0.57 and heading for the detraining edge.",
      "leverage": "1/5 · BASELINE"
    }
  ],
  "tripwires": [
    {
      "key": "sleep-balance",
      "state": "tripped",
      "signal": "Sleep balance",
      "window": "7-night average",
      "trigger": "< −30 min/night",
      "now": "−43 min/night",
      "meaning": "6 of 7 nights below fresh need: 7h27m actual against 8h10m needed. Protect the next few nights; there is no historical bill to repay."
    },
    {
      "key": "weekly-volume",
      "state": "clear",
      "signal": "Weekly volume",
      "window": "vs 12wk median",
      "trigger": "< 50%",
      "now": "26.9 km · 80%",
      "meaning": "Week to 14 Sep at 80% of the 33.7 km median. Nothing to do."
    },
    {
      "key": "acwr",
      "state": "close",
      "signal": "ACWR",
      "window": "EWMA 7:28",
      "trigger": "< 0.50",
      "now": "0.57",
      "meaning": "Below the 0.80 undertraining edge and heading for 0.50. The alert worth having is the forecast, not the value."
    },
    {
      "key": "hrv-crossing",
      "state": "clear",
      "signal": "HRV 7d mean",
      "window": "vs 28d baseline",
      "trigger": "below 2 days",
      "now": "50 vs 49",
      "meaning": "At or above its own baseline."
    },
    {
      "key": "resting-hr",
      "state": "clear",
      "signal": "Resting HR",
      "window": "vs 28d baseline",
      "trigger": "+4 bpm, 3 days",
      "now": "64 · +3 bpm",
      "meaning": "The earliest illness and overreach signal you have, and it is quiet. 3 days, not one."
    },
    {
      "key": "recovery-reds",
      "state": "clear",
      "signal": "Recovery reds",
      "window": "consecutive",
      "trigger": "3 in a row",
      "now": "1 · 28% today",
      "meaning": "Three reds is a pattern; one is a Tuesday. Nothing running."
    },
    {
      "key": "strain-balance",
      "state": "clear",
      "signal": "Strain vs recovery",
      "window": "7d balance",
      "trigger": "> 8.0",
      "now": "6.4",
      "meaning": "Comfortable. Expect this to climb as volume lands — it is the number that says \"too fast\"."
    },
    {
      "key": "vo2-slope",
      "state": "clear",
      "signal": "VO₂max slope",
      "window": "90d regression",
      "trigger": "< −0.20/mo",
      "now": "0.31/mo",
      "meaning": "Slope, never value — the percentile is pinned to a fixed age profile, so the rank is noise and the direction is not. 3.7 a year at this rate."
    },
    {
      "key": "segment-pb",
      "state": "tripped",
      "signal": "Segment PB in range",
      "window": "gap to all-time",
      "trigger": "gap < 3% & improving",
      "now": "2 gettable",
      "meaning": "The only positive tripwire here — a record is genuinely gettable rather than a fantasy. Closest is Woodland descent, 0.7% off it."
    }
  ],
  "segments": {
    "improving": 2,
    "holding": 0,
    "slipping": 4,
    "noRead": 2,
    "gettable": [
      {
        "name": "Woodland descent",
        "gapPct": 0.7,
        "detail": "pb 36d · 7 efforts"
      },
      {
        "name": "Hill lane climb",
        "gapPct": 0.7,
        "detail": "pb 36d · 6 efforts"
      }
    ]
  },
  "plan": {
    "sport": "Walk",
    "headline": "Walk · 5.2 km",
    "why": [
      "Readiness 46 is under the steady-climb gate, so today stays easy.",
      "Load has eased over three weeks; the distance is the recent median."
    ],
    "evidence": [
      {
        "label": "Readiness",
        "display": "46 · recovery priority"
      },
      {
        "label": "ACWR read",
        "display": "0.57 · undertraining"
      },
      {
        "label": "Week hours",
        "display": "2.4 · vs 3.6 typical"
      },
      {
        "label": "Days since hard",
        "display": "6 · threshold or above"
      }
    ]
  },
  "experiments": [
    {
      "status": "live",
      "title": "THE FIXED WINDOW",
      "change": "Lights out inside one fixed 30-minute window, five nights in seven.",
      "hold": "Training volume, wake time, caffeine. Nothing else moves for 21 days.",
      "measure": "circadian drift +1.0h → under 1h, seven-night sleep balance −43 min/night → within 30 and HRV 7d mean.",
      "stop": "Judge on 24 Sep 2026. If nothing has moved, the window is not the constraint — look at wake time.",
      "counter": "DAY 21 OF 21"
    },
    {
      "status": "queued",
      "title": "THE DULL LONG DAY",
      "change": "One 12–15 km outing a week at hike heart rate. Nothing added to the other days.",
      "hold": "Session count and intensity distribution. The variable is duration, not effort.",
      "measure": "ACWR 0.57 → 0.85, weekly volume 26.9 km → 33.7 km, beats-per-km against the 28-day baseline and monotony must stay under 2.",
      "stop": "Abort if the strain-recovery balance passes 8.0 or three recovery reds land in a row. The sleep experiment wins ties.",
      "counter": "WEEK 2 OF 6"
    },
    {
      "status": "queued",
      "title": "ONE HARD EFFORT",
      "change": "One weekly Z4–5 effort on a gettable segment. Takes the hard share 2% → 10%.",
      "hold": "The fixed sleep window and the long day, both proven by then.",
      "measure": "The verdict flips from pyramid to polarised: hard share 2% → 10%. VO₂max slope. Segment gap closing.",
      "stop": "Do not start before 25 Oct 2026, and not at all unless the seven-night sleep balance is within 30 minutes per night of fresh need.",
      "counter": "GATED ON E1+E2"
    }
  ],
  "verdict": {
    "headline": [
      "CAPABLE.",
      "UNDER-SLEPT."
    ],
    "body": [
      "The engine is in good order. Resting heart rate is on a 61 bpm baseline, cardio fitness reads excellent at the 71st percentile and the week has genuine hard/easy shape at a monotony of 0.7.",
      "The inputs are the problem. Sleep is 43 minutes short of fresh need per night over the latest seven, the sleep midpoint has slid 1h01m later, weekly volume is 26.9 km against a 33.7 km median, acute load sits at 0.57 of its own chronic base and the nervous system reads 44 out of 100."
    ],
    "quote": "Go to bed at the same time. Then put one long, dull walk in the diary every week.",
    "reviewOn": "2026-09-24"
  }
}
"""#
}
#endif
