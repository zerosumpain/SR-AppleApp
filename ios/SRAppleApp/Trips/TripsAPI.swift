import Foundation

/// The phone's lane to the trip planner: `/api/native/trips`.
///
/// Owner-only on the server until phase 5 (decision D2): a member, or the
/// owner looking through "View as", gets a 403, which comes back here as
/// `ownerOnly` so the screen can say so calmly instead of showing an error.
enum TripsAPI {
    enum Failure: Error, Equatable {
        /// 403: not in the family (v5: every family member sees every trip).
        case ownerOnly
        /// No site pairing on this phone.
        case unpaired
        /// The server answered, and refused (status, sentence).
        case refused(Int, String)
        /// No answer at all — offline, timed out. The cache stands.
        case offline(String)
    }

    enum Fetched {
        case fresh(TripBundle, Data)
        /// 304: what the phone holds is current.
        case unchanged
    }

    static func list() async throws -> [TripSummary] {
        let data = try await get("api/native/trips")
        do {
            return try JSONDecoder().decode(TripList.self, from: data).trips
        } catch {
            throw Failure.refused(200, "The server sent a trip list this version of the app cannot read.")
        }
    }

    /// One trip's bundle, conditional on the ETag the phone already holds.
    static func bundle(_ id: String, etag: String?) async throws -> Fetched {
        var headers: [String: String] = [:]
        if let etag { headers["If-None-Match"] = quoted(etag) }
        let (data, http) = try await exchange(path(id), method: "GET", headers: headers)
        if http.statusCode == 304 { return .unchanged }
        try check(http, data)
        do {
            var bundle = try JSONDecoder().decode(TripBundle.self, from: data)
            // The header is the authority when both are present: it is what
            // the next If-None-Match must repeat.
            if let header = http.value(forHTTPHeaderField: "ETag"), !header.isEmpty {
                bundle.etag = unquoted(header)
            }
            return .fresh(bundle, data)
        } catch {
            throw Failure.refused(200, "The server sent a trip this version of the app cannot read.")
        }
    }

    static func send(events: [TripEvent], basePlanVersion: Int, trip id: String) async throws -> TripEventsReply {
        let body = try JSONEncoder().encode(TripEventsBody(events: events, basePlanVersion: basePlanVersion))
        let (data, http) = try await exchange(path(id) + "/events", method: "POST", body: body)
        try check(http, data)
        do {
            return try JSONDecoder().decode(TripEventsReply.self, from: data)
        } catch {
            throw Failure.refused(200, "The server's answer to the day's events was unreadable.")
        }
    }

    static func replan(_ request: TripReplanBody, trip id: String) async throws -> [ReplanOption] {
        try await replanReply(request, trip: id).options
    }

    /// The whole answer: day options, and with scope "trip" the trip options
    /// and the planner's narrative.
    static func replanReply(_ request: TripReplanBody, trip id: String) async throws -> TripReplanReply {
        let body = try JSONEncoder().encode(request)
        // Trip scope asks the planner (a narrative, whole-trip options): a
        // job. Day scope is the solver alone and answers at once.
        if request.scope == "trip" {
            return try await run(path(id) + "/replan", body: body, as: TripReplanReply.self,
                                 unreadable: "The server's options were unreadable.")
        }
        let (data, http) = try await exchange(path(id) + "/replan", method: "POST", body: body)
        try check(http, data)
        do {
            return try JSONDecoder().decode(TripReplanReply.self, from: data)
        } catch {
            throw Failure.refused(200, "The server's options were unreadable.")
        }
    }

    /// One turn of the planning conversation ("Edit plan"). Never queued:
    /// a conversation needs the planner to answer.
    static func converse(_ text: String, trip id: String) async throws -> ConverseResult {
        try await run(path(id) + "/converse", body: try JSONEncoder().encode(ConverseBody(text: text)),
                      as: ConverseResult.self, unreadable: "The planner's answer was unreadable.")
    }

    // MARK: - v5: family trips

    /// A new trip from its opening message ("Rome, 27–30 Oct, staying near
    /// Campo de' Fiori…"). Any family member may; they become its creator.
    static func create(text: String) async throws -> TripCreated {
        try await run("api/native/trips", body: try JSONEncoder().encode(ConverseBody(text: text)),
                      as: TripCreated.self, unreadable: "The new trip's answer was unreadable.")
    }

    private struct IdeasAsk: Encodable {
        let date: String
        let stage: String
        let afterStopId: String?
        let beforeStopId: String?
    }

    /// Ideas that fit a slot of a day — "Make a suggestion". Nothing is saved.
    static func ideas(trip id: String, date: String, stage: DayStage, after: String?, before: String?) async throws -> TripIdeasReply {
        try await run(path(id) + "/ideas", body: try ideasBody(date: date, stage: stage, after: after, before: before),
                      as: TripIdeasReply.self, unreadable: "The planner's ideas were unreadable.")
    }

    static func ideasBody(date: String, stage: DayStage, after: String?, before: String?) throws -> Data {
        try JSONEncoder().encode(IdeasAsk(date: date, stage: stage.rawValue, afterStopId: after, beforeStopId: before))
    }

    // MARK: - v6: planner calls run as jobs
    //
    // The planner's calls (ideas, the conversation, a new trip, a whole-trip
    // re-plan) take 40–90 s; the app's requests time out at 30 s and
    // Cloudflare cuts a request at ~100 s. So each is STARTED with
    // `"async": true` — the server answers 202 `{ job }` at once — and its
    // result is collected by short polls of `GET /api/native/trips/jobs/:id`
    // every two seconds. A server too old for jobs simply answers 200 with
    // the result, which is read the same way.

    enum Started: Equatable {
        case job(String)
        case result(Data)
    }

    /// Poll interval, and when to give up on a job.
    static let pollEvery: UInt64 = 2_000_000_000
    static let giveUpAfter: TimeInterval = 180
    /// The starting request: long enough for an old server to do the work
    /// itself, short of Cloudflare's cut.
    static let startTimeout: TimeInterval = 95

    private struct JobStarted: Decodable {
        struct Job: Decodable { let id: String }
        let job: Job
    }

    private struct JobPolled<T: Decodable>: Decodable {
        struct Job: Decodable {
            let status: String
            let error: String?
            let result: T?
        }
        let job: Job
    }

    /// POST `body` with `"async": true` added.
    static func start(_ route: String, body: Data) async throws -> Started {
        var object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        object["async"] = true
        let data = try JSONSerialization.data(withJSONObject: object)
        let (reply, http) = try await exchange(route, method: "POST", body: data, timeout: startTimeout)
        if http.statusCode == 202, let started = try? JSONDecoder().decode(JobStarted.self, from: reply) {
            return .job(started.job.id)
        }
        try check(http, reply)
        return .result(reply)
    }

    /// The result of a started call: read at once, or polled until done.
    /// A network blip while polling is retried (the phone may be waking from
    /// the background); a job the server has forgotten (a deploy restarted
    /// it) is said plainly.
    static func result<T: Decodable>(_ started: Started, as type: T.Type, since: Date, unreadable: String) async throws -> T {
        switch started {
        case .result(let data):
            do { return try JSONDecoder().decode(T.self, from: data) } catch { throw Failure.refused(200, unreadable) }
        case .job(let id):
            while true {
                try Task.checkCancellation()
                if Date().timeIntervalSince(since) > giveUpAfter {
                    throw Failure.refused(504, "That took too long — try again.")
                }
                do {
                    let (data, http) = try await exchange("api/native/trips/jobs/" + escape(id), method: "GET")
                    if http.statusCode == 404 { throw Failure.refused(404, "That got lost in an update — try again.") }
                    try check(http, data)
                    guard let polled = try? JSONDecoder().decode(JobPolled<T>.self, from: data) else {
                        throw Failure.refused(200, unreadable)
                    }
                    switch polled.job.status {
                    case "done":
                        guard let result = polled.job.result else { throw Failure.refused(200, unreadable) }
                        return result
                    case "failed":
                        throw Failure.refused(500, polled.job.error ?? "The planner couldn't finish that — try again.")
                    default:
                        break
                    }
                } catch Failure.offline {
                    // Keep polling: a connection lost mid-job is the usual blip.
                }
                try await Task.sleep(nanoseconds: pollEvery)
            }
        }
    }

    /// Start and collect in one.
    static func run<T: Decodable>(_ route: String, body: Data, as type: T.Type, unreadable: String) async throws -> T {
        let since = Date()
        return try await result(try await start(route, body: body), as: type, since: since, unreadable: unreadable)
    }

    private struct SuggestBody: Encodable {
        let date: String
        let stage: String
        let wish: WishDraft
        let note: String?
        let fitText: String?

        private enum Keys: String, CodingKey { case date, stage, wish, note, fitText }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(date, forKey: .date)
            try c.encode(stage, forKey: .stage)
            try c.encode(wish, forKey: .wish)
            try c.encodeIfPresent(note, forKey: .note)
            try c.encodeIfPresent(fitText, forKey: .fitText)
        }
    }

    /// Suggest something for a slot; it waits for a parent.
    @discardableResult
    static func suggest(trip id: String, date: String, stage: DayStage, wish: WishDraft, note: String?, fitText: String?) async throws -> TripSuggestion? {
        let body = try JSONEncoder().encode(SuggestBody(date: date, stage: stage.rawValue, wish: wish, note: note, fitText: fitText))
        let (data, http) = try await exchange(path(id) + "/suggestions", method: "POST", body: body, timeout: 60)
        try check(http, data)
        return Self.suggestion(in: data)
    }

    /// `POST …/suggestions/:sid` → what happened to it.
    struct Decided: Decodable {
        var suggestionId: String?
        var status: String?
        var planVersion: Int?
        /// Said when the approval went through but something is worth knowing.
        var warning: String?
    }

    /// "approve", "reject" or "withdraw". 409 when someone decided first.
    @discardableResult
    static func decide(trip id: String, suggestion sid: String, action: String) async throws -> Decided {
        let body = try JSONEncoder().encode(["action": action])
        // Approving adds the wish and re-solves the plan: give it time.
        let (data, http) = try await exchange(path(id) + "/suggestions/" + escape(sid), method: "POST", body: body, timeout: 90)
        if http.statusCode == 409 { throw Failure.refused(409, "Someone has already decided that one.") }
        try check(http, data)
        return (try? JSONDecoder().decode(Decided.self, from: data)) ?? Decided()
    }

    /// The answer is a suggestion, or `{ suggestion }`; either is read, and
    /// neither is required — the bundle is re-read after any decision.
    private static func suggestion(in data: Data) -> TripSuggestion? {
        struct Wrapped: Decodable { let suggestion: TripSuggestion }
        return (try? JSONDecoder().decode(Wrapped.self, from: data).suggestion)
            ?? (try? JSONDecoder().decode(TripSuggestion.self, from: data))
    }

    /// A leg drawn in another mode (display only: the plan is unchanged).
    static func route(trip id: String, date: String, from: String, to: String, mode: TravelMode) async throws -> TripRoute {
        var q = URLComponents()
        q.queryItems = [
            URLQueryItem(name: "from", value: from), URLQueryItem(name: "to", value: to),
            URLQueryItem(name: "mode", value: mode.rawValue), URLQueryItem(name: "date", value: date),
        ]
        let query = q.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B") ?? ""
        let (data, http) = try await exchange(path(id) + "/route?" + query, method: "GET", timeout: 60)
        try check(http, data)
        do {
            return try JSONDecoder().decode(TripRoute.self, from: data)
        } catch {
            throw Failure.refused(200, "That route was unreadable.")
        }
    }

    // MARK: - Plumbing

    private static func escape(_ part: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/%?#")
        return part.addingPercentEncoding(withAllowedCharacters: allowed) ?? part
    }

    /// Ids are the server's own (url-safe), escaped all the same: a `/` in
    /// one would otherwise address a different route.
    static func path(_ id: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/%?#")
        return "api/native/trips/" + (id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id)
    }

    private static func get(_ path: String) async throws -> Data {
        let (data, http) = try await exchange(path, method: "GET")
        try check(http, data)
        return data
    }

    /// `SiteClient.exchange`, with its failures sorted into the four this
    /// lane distinguishes.
    private static func exchange(
        _ path: String, method: String, body: Data? = nil, headers: [String: String] = [:], timeout: TimeInterval? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        guard await SiteClient.shared.isPaired else { throw Failure.unpaired }
        do {
            return try await SiteClient.shared.exchange(path, method: method, body: body, headers: headers, timeout: timeout)
        } catch let error as SiteError {
            if case .unpaired = error { throw Failure.unpaired }
            if error.status == 401 { throw error }
            throw Failure.offline(error.localizedDescription)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Failure.offline(error.localizedDescription)
        }
    }

    private struct APIError: Decodable { let error: String }

    private static func check(_ http: HTTPURLResponse, _ data: Data) throws {
        if (200..<300).contains(http.statusCode) { return }
        if http.statusCode == 403 { throw Failure.ownerOnly }
        let sentence = (try? JSONDecoder().decode(APIError.self, from: data))?.error
            ?? "\(http.statusCode) from the trip planner."
        throw Failure.refused(http.statusCode, sentence)
    }

    private static func quoted(_ tag: String) -> String {
        tag.hasPrefix("\"") || tag.hasPrefix("W/") ? tag : "\"\(tag)\""
    }

    private static func unquoted(_ tag: String) -> String {
        var t = tag
        if t.hasPrefix("W/") { t.removeFirst(2) }
        if t.hasPrefix("\""), t.hasSuffix("\""), t.count >= 2 { t = String(t.dropFirst().dropLast()) }
        return t
    }
}

extension TripsAPI.Failure: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .ownerOnly: return "Trips are for the family — this phone isn't in the Family Circle."
        case .unpaired: return "Connect this iPhone to Strange Ramblings first."
        case .refused(_, let sentence): return sentence
        case .offline(let why): return why
        }
    }
}
