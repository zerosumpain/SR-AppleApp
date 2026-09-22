import Foundation
import Security

/// The app's connection to strangeramblings.com.
///
/// Deliberately SEPARATE from `API.swift`, which pairs with the companion server
/// that holds health and family location. Two servers, two credentials, and
/// conflating them would mean revoking a phone's health sync to stop it reading
/// chat. The Keychain accounts differ for the same reason.
///
/// Auth is a device token obtained by redeeming a one-time code from
/// the companion dashboard at `/apple-app`, sent as `Authorization: Bearer`.
/// (That page shows it, but the main site mints it — the pilot server never
/// handles a site credential.) It is exactly as
/// privileged as the browser session that minted it and is revocable from there.
enum SiteError: LocalizedError {
    case unpaired
    case expired
    case message(String)

    var errorDescription: String? {
        switch self {
        case .unpaired: return "Connect this iPhone to Strange Ramblings first."
        case .expired: return "This iPhone needs pairing again."
        case .message(let value): return value
        }
    }
}

enum SiteKeychain {
    static let service = "com.strangeramblings.com.appleapp.site"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "device",
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String?) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "device",
        ]
        let deleted = SecItemDelete(query as CFDictionary)
        guard deleted == errSecSuccess || deleted == errSecItemNotFound else {
            throw SiteError.message("Could not update saved credentials.")
        }
        guard let token else { return }
        var values = query
        values[kSecValueData as String] = Data(token.utf8)
        // Device-only, and only after a first unlock: a background refresh runs
        // while the phone is locked, so `WhenUnlocked` would fail those silently.
        values[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(values as CFDictionary, nil) == errSecSuccess else {
            throw SiteError.message("Could not save credentials.")
        }
    }
}

/// The QR payload minted by `/api/admin/native-devices`.
struct SitePairing: Decodable {
    let type: String
    let version: Int
    let server: String
    let code: String

    /// Parse a scanned string, refusing anything that is not ours.
    ///
    /// The origin check is the one that matters. A QR is a URL somebody else
    /// controls; without this the scanner is a "point your paired phone at my
    /// server" button.
    static func parse(_ raw: String) throws -> SitePairing {
        guard let data = raw.data(using: .utf8),
              let payload = try? JSONDecoder().decode(SitePairing.self, from: data) else {
            throw SiteError.message("That is not a Strange Ramblings pairing code.")
        }
        // Name the ACTUAL mistake. Both codes are minted from the same page, so
        // scanning the wrong one is the likely error by a wide margin — and
        // "a different version of the app" sent the reader looking for a
        // TestFlight update that would not have helped.
        guard payload.type != "sr-companion-pair" else {
            throw SiteError.message(
                "That is the health & location code, for the Companion tab. On the dashboard, scroll to Chat & news and create that code instead."
            )
        }
        guard payload.type == "sr-native-pair" else {
            throw SiteError.message("That is not a Strange Ramblings pairing code.")
        }
        guard payload.version == 1 else {
            throw SiteError.message("That pairing code is from a newer version of the site than this app understands. Update the app.")
        }
        guard let url = URL(string: payload.server), url.scheme == "https" else {
            throw SiteError.message("A pairing code must name an HTTPS address.")
        }
        return payload
    }
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
    }

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        // A chat turn can think for a long time before its first token. The
        // stream's own idle timeout is what ends a dead connection, not this.
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()

    func request(_ path: String, method: String = "GET", body: Data? = nil) throws -> URLRequest {
        guard let token else { throw SiteError.unpaired }
        var req = URLRequest(url: origin.appendingPathComponent(path))
        req.httpMethod = method
        req.httpBody = body
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if body != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return req
    }

    private struct APIError: Decodable { let error: String }

    func send<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        let (data, response) = try await session.data(for: try request(path, method: method, body: body))
        try check(response, data)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SiteError.message("The server sent something this version of the app cannot read.")
        }
    }

    @discardableResult
    func post(_ path: String, body: Data) async throws -> Data {
        let (data, response) = try await session.data(for: try request(path, method: "POST", body: body))
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
            let detail = try? JSONDecoder().decode(APIError.self, from: data)
            throw SiteError.message(detail?.error ?? "The server could not answer that (\(http.statusCode)).")
        }
    }

    // MARK: - Pairing

    private struct PairResponse: Decodable { let token: String; let expiresAt: String }

    func pair(_ payload: SitePairing) async throws {
        guard let url = URL(string: payload.server), url.scheme == "https" else {
            throw SiteError.message("A pairing code must name an HTTPS address.")
        }
        var req = URLRequest(url: url.appendingPathComponent("api/native/pair"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["code": payload.code, "label": deviceLabel()])

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = try? JSONDecoder().decode(APIError.self, from: data)
            throw SiteError.message(detail?.error ?? "That pairing code did not work.")
        }
        let result = try JSONDecoder().decode(PairResponse.self, from: data)
        try SiteKeychain.save(result.token)
        token = result.token
        origin = url
        UserDefaults.standard.set(url, forKey: "site-origin")
    }

    func signOut() {
        try? SiteKeychain.save(nil)
        token = nil
    }

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
    }

    /// Frames from a chat job, resuming after `lastEventId` if one is given.
    ///
    /// The resume point is not optional politeness. The web client learned this
    /// the hard way — replaying a whole buffer into a handler that APPENDS is
    /// what silently doubled every bubble on reconnect, so the server publishes
    /// a sequence number on every frame and honours `Last-Event-ID`.
    func stream(jobId: String, after lastEventId: Int? = nil) throws -> AsyncThrowingStream<StreamFrame, Error> {
        var req = try request("api/workflows/orchestrator/chat/stream?jobId=\(jobId)")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let lastEventId { req.setValue(String(lastEventId), forHTTPHeaderField: "Last-Event-ID") }
        let session = self.session

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: req)
                    if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                        throw SiteError.expired
                    }
                    var pendingId: Int?
                    for try await line in bytes.lines {
                        if line.hasPrefix("id: ") {
                            pendingId = Int(line.dropFirst(4))
                        } else if line.hasPrefix("data: ") {
                            let payload = String(line.dropFirst(6))
                            if let data = payload.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                continuation.yield(StreamFrame(id: pendingId, json: json))
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
