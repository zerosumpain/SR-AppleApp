import Foundation

/// The phone's lane to the trip planner: `/api/native/trips`.
///
/// Owner-only on the server until phase 5 (decision D2): a member, or the
/// owner looking through "View as", gets a 403, which comes back here as
/// `ownerOnly` so the screen can say so calmly instead of showing an error.
enum TripsAPI {
    enum Failure: Error, Equatable {
        /// 403: trips are the owner's for now.
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
        let body = try JSONEncoder().encode(request)
        let (data, http) = try await exchange(path(id) + "/replan", method: "POST", body: body)
        try check(http, data)
        do {
            return try JSONDecoder().decode(TripReplanReply.self, from: data).options
        } catch {
            throw Failure.refused(200, "The server's options were unreadable.")
        }
    }

    // MARK: - Plumbing

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
        _ path: String, method: String, body: Data? = nil, headers: [String: String] = [:]
    ) async throws -> (Data, HTTPURLResponse) {
        guard SiteClient.shared.isPaired else { throw Failure.unpaired }
        do {
            return try await SiteClient.shared.exchange(path, method: method, body: body, headers: headers)
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
        case .ownerOnly: return "Trips are owner-only for now."
        case .unpaired: return "Connect this iPhone to Strange Ramblings first."
        case .refused(_, let sentence): return sentence
        case .offline(let why): return why
        }
    }
}
