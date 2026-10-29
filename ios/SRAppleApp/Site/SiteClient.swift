import Foundation
import Security

/// The app's connection to strangeramblings.com.
///
/// Deliberately SEPARATE from `API.swift`, which pairs with the companion server
/// that holds health and family location. Two servers, two credentials, and
/// conflating them would mean revoking a phone's health sync to stop it reading
/// chat. The Keychain accounts differ for the same reason.
///
/// Auth is a device token obtained by redeeming a one-time code — the one
/// pairing code at strangeramblings.com/welcome, or a sign-in from Welcome —
/// sent as `Authorization: Bearer`. It is exactly as privileged as the person
/// it was minted for and is revocable from the website.
enum SiteError: LocalizedError {
    case unpaired
    case expired
    case message(String)
    /// A non-2xx answer, with the status kept. A screen needs to tell "that
    /// activity does not exist" (404) from "Health is down" (503), and a flat
    /// message string threw the difference away.
    case status(Int, String)
    /// A refusal that names the field it is about — `422 { error, field }` from
    /// the workflows lane — so a form can put the message beside that field.
    case invalid(String, field: String)

    var errorDescription: String? {
        switch self {
        case .unpaired: return "Connect this iPhone to Strange Ramblings first."
        case .expired: return "This iPhone needs pairing again."
        case .message(let value): return value
        case .status(_, let value): return value
        case .invalid(let value, _): return value
        }
    }

    /// The HTTP status, when the server answered with one.
    var status: Int? {
        if case .expired = self { return 401 }
        if case .status(let code, _) = self { return code }
        if case .invalid = self { return 422 }
        return nil
    }
}

enum SiteKeychain {
    static let service = "com.strangeramblings.com.appleapp.site"

    static func read(account: String = "device") -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String?, account: String = "device") throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        guard let token else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw SiteError.message("Could not remove saved credentials.")
            }
            return
        }
        let attrs: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw SiteError.message("Could not update saved credentials.") }
        let values = query.merging(attrs) { _, new in new }
        guard SecItemAdd(values as CFDictionary, nil) == errSecSuccess else {
            throw SiteError.message("Could not save credentials.")
        }
    }
}

/// A site pairing code handed to this phone by the site itself — a member's
/// automatic pairing (`SitePairOffer`). Never scanned: the one code a person
/// scans is `PairingPayload`, redeemed by `CodePairing`.
struct SitePairing: Decodable {
    let type: String
    let version: Int
    let server: String
    let code: String
}

@MainActor
final class SiteClient {
    static let shared = SiteClient()

    private(set) var origin: URL
    private(set) var token: String?

    /// The production origin, and the default. A pairing QR can point the app at
    /// another HTTPS host — that is how a staging box is reached — but it can
    /// never point it at plain HTTP.
    static let defaultOrigin = URL(string: "https://strangeramblings.com")!

    var isPaired: Bool { token != nil }

    private init() {
        origin = UserDefaults.standard.url(forKey: "site-origin") ?? Self.defaultOrigin
        token = SiteKeychain.read()
        demoChanged()
    }

    /// Demo mode — the review demo, or `-SRDemo` in DEBUG: paired with a
    /// pretend credential that lives in memory and is never written to the
    /// Keychain, against the default origin, with every request answered by
    /// `SRDemoFixtures`. Out of it, the real credential again (if any).
    func demoChanged() {
        if SRDemo.isOn {
            origin = Self.defaultOrigin
            token = SRDemo.token
        } else if token == SRDemo.token {
            origin = UserDefaults.standard.url(forKey: "site-origin") ?? Self.defaultOrigin
            token = SiteKeychain.read()
        }
        Task { await retryPendingRevocations() }
    }

    /// The session for this request: in a demo, one whose only transport is
    /// the fixtures, so no request made in a demo can reach the network.
    /// Chosen per request, because the review demo starts and stops at run time.
    private var session: URLSession { SRDemo.isOn ? demoSession : liveSession }

    private lazy var liveSession: URLSession = Self.makeSession(demo: false)
    private lazy var demoSession: URLSession = Self.makeSession(demo: true)

    /// A chat turn's stream has a session of its own.
    ///
    /// The shared one caps every request at 600 s, which ended a long turn's
    /// stream as an error at ten minutes even while the turn was running. A
    /// stream is not a request with an end: what ends a DEAD one is silence,
    /// and a running job sends a heartbeat frame every five seconds, so twenty
    /// seconds with no bytes is a connection that has gone (`ChatStore`
    /// reconnects from the last frame it saw). The server still ends the turn
    /// itself at its own limits; this only stops the phone ending it first.
    private var streamSession: URLSession { SRDemo.isOn ? demoSession : liveStreamSession }
    private lazy var liveStreamSession: URLSession = Self.makeSession(demo: false, stream: true)

    /// The phone's jkai channel (`JkaiLive`) is quieter than a turn: nothing
    /// but a `: keepalive` comment every thirty seconds when nothing happens.
    /// Twenty seconds of silence would end it between every pair of them, so
    /// it waits two and a half keepalives instead.
    private var eventsSession: URLSession { SRDemo.isOn ? demoSession : liveEventsSession }
    private lazy var liveEventsSession: URLSession = Self.makeSession(demo: false, stream: true, idle: 75)

    private static func makeSession(demo: Bool, transport: [AnyClass] = [], stream: Bool = false, idle: TimeInterval? = nil) -> URLSession {
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        config.timeoutIntervalForRequest = idle ?? (stream ? TurnStreamResume.silence : 30)
        // A chat turn can think for a long time before its first token. The
        // stream's own idle timeout is what ends a dead connection, not this.
        config.timeoutIntervalForResource = stream ? 24 * 60 * 60 : 600
        var first: [AnyClass] = transport
        if demo { first = [SRDemoURLProtocol.self] }
        #if DEBUG
        // UI tests: a stand-in for the site's answers to the few calls made
        // BEFORE a demo exists (the review code). Never in a Release build.
        if !demo, ProcessInfo.processInfo.arguments.contains("-SRStubNetwork") {
            first.insert(SRStubURLProtocol.self, at: 0)
        }
        #endif
        config.protocolClasses = first + (config.protocolClasses ?? [])
        return URLSession(configuration: config)
    }

    #if DEBUG
    /// Tests: put a recording transport under the LIVE session, to prove a
    /// demo never uses it.
    func useLiveTransport(_ transport: [AnyClass]) {
        liveSession = Self.makeSession(demo: false, transport: transport)
        liveStreamSession = Self.makeSession(demo: false, transport: transport, stream: true)
        liveEventsSession = Self.makeSession(demo: false, transport: transport, stream: true, idle: 75)
    }
    #endif

    /// Build an absolute URL from a path that may carry a query string.
    ///
    /// NOT `appendingPathComponent`. That treats the WHOLE string as a single
    /// path component and percent-encodes the reserved characters in it — so
    /// `api/native/news?view=top` becomes `/api/native/news%3Fview=top`, which
    /// is a path no route matches. The server answered 404 with an HTML error
    /// page, the app tried to decode `APIError` out of HTML, and the reader got
    /// a generic failure with no hint of the cause. Every call WITHOUT a query
    /// worked, which is why pairing succeeded and nothing else did.
    ///
    /// `percentEncodedQuery` rather than `query`: the thread search already
    /// encodes its term with `addingPercentEncoding`, and assigning to `query`
    /// would encode the `%` signs again.
    func url(for path: String) throws -> URL {
        guard var components = URLComponents(url: origin, resolvingAgainstBaseURL: false) else {
            throw SiteError.message("The saved server address is not usable.")
        }
        let parts = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let path = "/" + parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // A path that arrives already escaped — an activity id is `apple:UUID`
        // and goes out as `apple%3AUUID` — is kept verbatim. Assigning it to
        // `path` would escape the `%` again and ask for `apple%253AUUID`, which
        // no route decodes back to the id. Every other caller passes a plain
        // path and keeps the old behaviour.
        if path.contains("%") {
            components.percentEncodedPath = path
        } else {
            components.path = path
        }
        components.percentEncodedQuery = parts.count > 1 && !parts[1].isEmpty ? String(parts[1]) : nil
        guard let built = components.url else {
            throw SiteError.message("Could not build a request for \(path).")
        }
        return built
    }

    /// Names the person the owner is viewing the app as. Read by SR-Main's
    /// `nativeViewAs`, which honours it on the owner's credential alone.
    static let viewAsHeader = "X-SR-View-As"

    /// `asSelf`: never as the person being viewed. For the calls that are
    /// about THIS phone, not about whose data is on screen — registering for
    /// push, answering a notification — which View as (look-only) would refuse.
    func request(_ path: String, method: String = "GET", body: Data? = nil, asSelf: Bool = false) throws -> URLRequest {
        guard let token else { throw SiteError.unpaired }
        var req = URLRequest(url: try url(for: path))
        req.httpMethod = method
        req.httpBody = body
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if body != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        PhoneIdentity.apply(to: &req)
        // Settings → View as: the site answers this request as that person's
        // phone would be answered — their threads, their stories — and refuses
        // anything but a read. Without it the look showed the OWNER's data
        // under the other person's tabs (SR-Main `nativeViewAs`).
        if !asSelf, let viewing = AccessStore.shared.viewingAs {
            req.setValue(viewing.email, forHTTPHeaderField: Self.viewAsHeader)
        }
        return req
    }

    private struct APIError: Decodable { let error: String; var field: String? = nil }

    /// `timeout`: for the few calls that legitimately think for longer than the
    /// session's 30 s — planning a route is up to eight openrouteservice round
    /// trips in a row on the server.
    func send<T: Decodable>(
        _ path: String, method: String = "GET", body: Data? = nil, asSelf: Bool = false, timeout: TimeInterval? = nil
    ) async throws -> T {
        var req = try request(path, method: method, body: body, asSelf: asSelf)
        if let timeout { req.timeoutInterval = timeout }
        let (data, response) = try await session.data(for: req)
        try check(response, data)
        do {
            return try await OffMain.decode(T.self, from: data)
        } catch {
            throw SiteError.message("The server sent something this version of the app cannot read.")
        }
    }

    /// A chat turn's POST, answered as it came: the status, the body and any
    /// `Retry-After`, because a 409 here is not one thing. With `pending` it
    /// means "the same send is still being accepted, ask again"; without, "that
    /// id belongs to another message". `TurnStart.classify` reads it. Only a
    /// 401 throws, as everywhere.
    func postTurn(_ body: Data) async throws -> (status: Int, body: Data, retryAfter: String?) {
        let (data, response) = try await session.data(for: try request("api/workflows/orchestrator/chat", method: "POST", body: body))
        guard let http = response as? HTTPURLResponse else { throw SiteError.message("No reply from the server.") }
        if http.statusCode == 401 { throw SiteError.expired }
        return (http.statusCode, data, http.value(forHTTPHeaderField: "Retry-After"))
    }

    @discardableResult
    func post(_ path: String, body: Data) async throws -> Data {
        let (data, response) = try await session.data(for: try request(path, method: "POST", body: body))
        try check(response, data)
        return data
    }

    /// One file, as the request body, with its name and any other fields in
    /// the query string.
    ///
    /// NOT `multipart/form-data`, which is what build 20 sent and why every
    /// upload came back 403 "Cross-site POST form submissions are forbidden".
    /// SvelteKit refuses a form-encoded POST whose `Origin` does not match the
    /// site, before any route runs. A browser always sends one; this app sends
    /// none. A raw body is not a form, so the check does not apply, and the
    /// bearer token is what actually rules out a forged request.
    func upload<T: Decodable>(
        _ path: String,
        file: Data,
        filename: String,
        mimeType: String,
        fields: [String: String] = [:]
    ) async throws -> T {
        // `url(for:)` keeps the query VERBATIM, so each value is escaped here,
        // and strictly: `urlQueryAllowed` lets `&`, `=` and `+` through, and a
        // photo named "Run & ride.jpg" would split into two parameters.
        var strict = CharacterSet.urlQueryAllowed
        strict.remove(charactersIn: "&=+?#")
        let query = (["filename": filename].merging(fields) { a, _ in a })
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: strict) ?? "")" }
            .joined(separator: "&")

        var req = try request("\(path)?\(query)", method: "POST", body: file)
        req.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: req)
        try check(response, data)
        do {
            return try await OffMain.decode(T.self, from: data)
        } catch {
            throw SiteError.message("The server sent something this version of the app cannot read.")
        }
    }

    /// Any method, reply read as raw bytes (or ignored). For writes whose
    /// answer the caller does not need — a PATCH or DELETE that may answer
    /// `{ ok: true }`, an empty 204, or anything in between.
    @discardableResult
    func call(_ path: String, method: String, body: Data? = nil) async throws -> Data {
        let (data, response) = try await session.data(for: try request(path, method: method, body: body))
        try check(response, data)
        return data
    }

    /// One request whose answer the caller reads for itself, refusals and
    /// all: the body, the status and the headers come back as they are. Only
    /// a 401 throws (`expired`), as it does everywhere else. For a write that
    /// carries its own headers and must read a refusal's — the Wildmind
    /// whisper sends an `Idempotency-Key` and reads `retry-after` off a 429.
    ///
    /// `timeout`: for a call that legitimately takes longer than the
    /// session's 30 s (trips: starting a planner job on a server too old to
    /// run it in the background; an approval that re-solves the plan).
    func exchange(
        _ path: String, method: String = "POST", body: Data? = nil, headers: [String: String] = [:],
        timeout: TimeInterval? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        var req = try request(path, method: method, body: body)
        if let timeout { req.timeoutInterval = timeout }
        for (name, value) in headers { req.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw SiteError.message("No reply from the server.")
        }
        if http.statusCode == 401 { throw SiteError.expired }
        return (data, http)
    }

    /// Raw bytes — an attachment's image, which is not JSON.
    func bytes(_ path: String) async throws -> Data {
        let (data, response) = try await session.data(for: try request(path))
        try check(response, data)
        return data
    }

    private func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SiteError.message("No reply from the server.")
        }
        // 401 means the credential is gone — revoked from the website, or past
        // its ninety days. It is the app's signal to show pairing again, so it
        // gets its own case rather than folding into a generic failure.
        if http.statusCode == 401 { throw SiteError.expired }
        guard (200..<300).contains(http.statusCode) else {
            // A 404 comes back as the site's HTML error page, not JSON. Decoding
            // it fails and the reader is told nothing useful, so name the status
            // and say where it was pointed — that is what would have identified
            // this as a malformed URL rather than a server fault.
            if let detail = try? JSONDecoder().decode(APIError.self, from: data) {
                if let field = detail.field, !field.isEmpty {
                    throw SiteError.invalid(detail.error, field: field)
                }
                throw SiteError.status(http.statusCode, detail.error)
            }
            let where_ = response.url?.path ?? "the server"
            throw SiteError.status(http.statusCode, "\(http.statusCode) from \(where_). The app asked for something that is not there.")
        }
    }

    // MARK: - Pairing

    private struct PairResponse: Decodable { let token: String; let expiresAt: String }

    func pair(_ payload: SitePairing) async throws {
        guard let url = URL(string: payload.server), url.scheme == "https" else {
            throw SiteError.message("A pairing code must name an HTTPS address.")
        }
        try await redeem(code: payload.code, at: url)
    }

    /// Spend a one-time code for this phone's credential — the one pairing
    /// code, a member's automatic pairing, or a sign-in from Welcome (which is
    /// why it defaults to the saved origin: the code came from there).
    ///
    /// The code shown at /welcome connects only a phone signed in as the person
    /// it was made for, so this says who this phone is: the credential it
    /// already holds (to the same site only — never handed to another host),
    /// or `identity`, from a sign-in made just now for this code. A refusal
    /// keeps its status: 428 is "sign in first", 409 is "this is someone
    /// else's code" (`CodePairing`).
    /// `join`: the code is an install link's (`/app/<name>-<tag>`), sent as
    /// `join` so the site pairs by the link's signature rather than a code row.
    func redeem(code: String, at server: URL? = nil, identity: String? = nil, join: Bool = false) async throws {
        // Never let a demo session reach the Keychain.
        if SRDemo.isOn { throw SiteError.message("Demo mode: pairing is switched off. Leave the demo in Settings first.") }
        let url = server ?? origin
        guard url.scheme == "https" else { throw SiteError.message("A pairing code must name an HTTPS address.") }
        var req = URLRequest(url: url.appending(path: "api/native/pair"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        PhoneIdentity.apply(to: &req)
        if let token, url.host() == origin.host(), url.port == origin.port {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        var body = [join ? "join" : "code": code, "label": deviceLabel()]
        if let identity { body["identity"] = identity }
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw SiteError.message("No reply from the server.") }
        guard (200..<300).contains(http.statusCode) else {
            let detail = try? JSONDecoder().decode(APIError.self, from: data)
            throw SiteError.status(http.statusCode, detail?.error ?? "That pairing code did not work.")
        }
        let result = try JSONDecoder().decode(PairResponse.self, from: data)
        try SiteKeychain.save(result.token)
        token = result.token
        origin = url
        UserDefaults.standard.set(url, forKey: "site-origin")
        // A new credential holds no push token yet: hand it this phone's.
        Task { await PushRegistration.shared.sync() }
    }

    /// Is this the App Review code? `POST api/native/review-demo {code}`,
    /// answered `{demo: true}` by the site for the one code it holds. Never
    /// throws: anything but that answer — wrong code, route switched off,
    /// offline — is "no", and the caller treats the code as a pairing code.
    func isReviewDemoCode(_ code: String) async -> Bool {
        guard !SRDemo.isOn, let body = try? JSONEncoder().encode(["code": code]) else { return false }
        var req = URLRequest(url: origin.appending(path: "api/native/review-demo"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        guard let answer = try? await liveSession.data(for: req) else { return false }
        return ReviewDemo.switchesOn(status: (answer.1 as? HTTPURLResponse)?.statusCode ?? 0, body: answer.0)
    }

    /// A POST with NO credential — the one route that takes a sign-in from a
    /// phone nobody knows yet (`api/native/register/apple`). Everything else
    /// goes through `request`, which refuses to run unpaired.
    func sendAnonymous<T: Decodable>(_ path: String, body: Data) async throws -> T {
        var req = URLRequest(url: try url(for: path))
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        PhoneIdentity.apply(to: &req)
        let (data, response) = try await session.data(for: req)
        try check(response, data)
        do {
            return try await OffMain.decode(T.self, from: data)
        } catch {
            throw SiteError.message("The server sent something this version of the app cannot read.")
        }
    }

    @discardableResult func signOut() -> Bool {
        if ReviewDemo.isActive {
            ReviewDemo.shared.leave()
            return true
        }
        if SRDemo.isOn {
            token = nil
            return true
        }
        // Queue before dropping the active credential. Only the device-only
        // Keychain holds the retry secret; it can be used solely to revoke.
        do {
            if let token {
                var pending = pendingRevocations()
                if !pending.contains(where: { $0.token == token && $0.origin == origin }) {
                    pending.append(Revocation(origin: origin, token: token))
                }
                try SiteKeychain.save(String(decoding: JSONEncoder().encode(pending), as: UTF8.self), account: "pending-revocations")
            }
            try SiteKeychain.save(nil)
        } catch { return false }
        token = nil
        // A revoked credential must not leave thread titles behind in iPhone
        // search. The index is a file other system processes read.
        ThreadIndex.clear()
        // Nor a copy of itself, or a family board, for the widgets — nor the
        // family view kept for a cold start.
        FamilyWidgetBridge.clear()
        FamilyViewCache.clear()
        AlertStore.clearLaunchUrgent()
        FamilyStepsStore.shared.reset()
        FamilyTasksStore.shared.reset()
        FamilyBacklogStore.shared.reset()
        LandgrabStore.shared.reset()
        CaptureStore.shared.reset()
        Task {
            await JourneyLive.shared.endAll()
            await retryPendingRevocations()
        }
        return true
    }

    private struct Revocation: Codable, Equatable { let origin: URL; let token: String }
    private var revoking = false
    private func pendingRevocations() -> [Revocation] {
        guard let raw = SiteKeychain.read(account: "pending-revocations"),
              let data = raw.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([Revocation].self, from: data)) ?? []
    }

    func retryPendingRevocations() async {
        guard !SRDemo.isOn, !revoking else { return }
        revoking = true
        defer { revoking = false }
        let retrySession = URLSession(configuration: .ephemeral, delegate: RevokeRedirectBlocker(), delegateQueue: nil)
        defer { retrySession.invalidateAndCancel() }
        for item in pendingRevocations() {
            guard item.origin.scheme == "https" else { continue }
            var request = URLRequest(url: item.origin.appendingPathComponent("api/native/session"))
            request.httpMethod = "DELETE"
            request.timeoutInterval = 10
            request.setValue("Bearer \(item.token)", forHTTPHeaderField: "Authorization")
            do {
                let (_, response) = try await retrySession.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { continue }
                // Preserve revocations enqueued while this request was in flight.
                let left = pendingRevocations().filter { $0 != item }
                try SiteKeychain.save(String(decoding: JSONEncoder().encode(left), as: UTF8.self), account: "pending-revocations")
            } catch { /* Retry at next launch or foreground; no credential logging. */ }
        }
    }

    /// The website's own address for something, for a share sheet or a Link.
    ///
    /// Built off `origin` rather than the production constant, so a phone
    /// paired to a staging host shares staging links instead of silently
    /// pointing a reader at production.
    func webURL(_ path: String) -> URL {
        (try? url(for: path)) ?? Self.defaultOrigin
    }

    /// `/jkai` with a question already in the box.
    ///
    /// `?q=` and `?send=1` are read by the page's own loader, so a Shortcut can
    /// hand a typed or dictated sentence straight to the desk. Percent-encoded
    /// here because `url(for:)` assigns `percentEncodedQuery` verbatim — it
    /// must not encode a term the caller already encoded.
    ///
    /// **Not `.urlQueryAllowed`.** That set is the characters legal anywhere in
    /// a query STRING, which includes `&`, `=`, `+` and `?` — exactly the four
    /// that must be escaped inside a query VALUE. A dictated "what is my RHR &
    /// why?" would have arrived as `q=what is my RHR ` plus a parameter called
    /// ` why?`, and the desk would have been asked half the question.
    func askURL(_ question: String, send: Bool = false) -> URL {
        let encoded = question.addingPercentEncoding(withAllowedCharacters: Self.queryValue) ?? ""
        return webURL("jkai?q=\(encoded)" + (send ? "&send=1" : ""))
    }

    /// RFC 3986 unreserved. Everything else in a query value is escaped.
    private static let queryValue: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    private func deviceLabel() -> String {
        // `UIDevice.name` is personal data on iOS 16+ and returns the model name
        // anyway unless entitled, so there is nothing to gain by asking for it.
        "iPhone"
    }

    // MARK: - Server-sent events
    //
    // `URLSession.bytes` rather than a third-party EventSource: the framing is
    // four lines of parsing and a dependency here would be a dependency in a
    // signed build.

    struct StreamFrame {
        let id: Int?
        let json: [String: Any]
        /// The frame's `data:` bytes as sent, for a caller that decodes a
        /// `Decodable` rather than picking at a dictionary.
        let data: Data
    }

    /// Frames from a chat job, resuming after `lastEventId` if one is given.
    ///
    /// The resume point is not optional politeness. The web client learned this
    /// the hard way — replaying a whole buffer into a handler that APPENDS is
    /// what silently doubled every bubble on reconnect, so the server publishes
    /// a sequence number on every frame and honours `Last-Event-ID`.
    func stream(jobId: String, after lastEventId: Int? = nil) throws -> AsyncThrowingStream<StreamFrame, Error> {
        try stream(path: "api/workflows/orchestrator/chat/stream?jobId=\(jobId)", after: lastEventId, session: streamSession)
    }

    /// The phone's jkai channel, `GET /api/jkai/events?scope=me`, resuming
    /// after `lastEventId`. Always as this phone's own person: the channel is
    /// never opened while viewing as somebody (`JkaiLive`).
    func events(after lastEventId: Int? = nil) throws -> AsyncThrowingStream<StreamFrame, Error> {
        try stream(path: "api/jkai/events?scope=me", after: lastEventId, session: eventsSession, asSelf: true)
    }

    /// Frames from any server-sent-events route on the site — a chat job, a
    /// game room (`api/native/games/<id>/stream`).
    ///
    /// A non-2xx answer throws BEFORE any line is read. Without that a 404 —
    /// an HTML error page — was read as a stream with no `data:` lines, which
    /// finished cleanly, and the caller could not tell "the room has gone"
    /// from "the room said nothing".
    func stream(path: String, after lastEventId: Int? = nil) throws -> AsyncThrowingStream<StreamFrame, Error> {
        try stream(path: path, after: lastEventId, session: session)
    }

    private func stream(path: String, after lastEventId: Int?, session: URLSession, asSelf: Bool = false) throws -> AsyncThrowingStream<StreamFrame, Error> {
        var req = try request(path, asSelf: asSelf)
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let lastEventId { req.setValue(String(lastEventId), forHTTPHeaderField: "Last-Event-ID") }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: req)
                    if let http = response as? HTTPURLResponse {
                        if http.statusCode == 401 { throw SiteError.expired }
                        guard (200..<300).contains(http.statusCode) else {
                            throw SiteError.status(http.statusCode, "\(http.statusCode) from \(http.url?.path ?? "the server").")
                        }
                    }
                    var pendingId: Int?
                    for try await line in bytes.lines {
                        if line.hasPrefix("id: ") {
                            pendingId = Int(line.dropFirst(4))
                        } else if line.hasPrefix("data: ") || line.hasPrefix("data:") {
                            let payload = line.hasPrefix("data: ") ? String(line.dropFirst(6)) : String(line.dropFirst(5))
                            let data = Data(payload.utf8)
                            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                continuation.yield(StreamFrame(id: pendingId, json: json, data: data))
                            }
                            pendingId = nil
                        }
                        // A blank line ends a frame and a `:` line is a
                        // keepalive; neither carries anything to act on.
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private final class RevokeRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
