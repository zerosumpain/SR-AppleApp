import Foundation
import Security

/// The reason given when a response carries no `{"error": …}` from our
/// server (a proxy's page, an empty body).
let uploadFallbackMessage = "Upload failed. Queued records will retry."
enum CompanionError: LocalizedError {
    case message(String)
    case response(Int, String)
    var errorDescription: String? {
        switch self { case .message(let value): return value; case .response(_, let value): return value }
    }
}
enum Keychain {
    static let service = "com.strangeramblings.com.appleapp"
    static func read() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "device", kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ token: String?) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "device"]
        let deleted = SecItemDelete(query as CFDictionary)
        guard deleted == errSecSuccess || deleted == errSecItemNotFound else { throw CompanionError.message("Could not update device credentials.") }
        guard let token else { return }
        var values = query
        values[kSecValueData as String] = Data(token.utf8)
        values[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(values as CFDictionary, nil) == errSecSuccess else { throw CompanionError.message("Could not save device credentials.") }
    }
}
@MainActor final class API {
    var baseURL: URL?
    var token: String?
    init() { baseURL = UserDefaults.standard.url(forKey: "server"); token = Keychain.read() }
    static func validateURL(_ text: String) throws -> URL {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/" else {
            throw CompanionError.message("Enter an HTTPS server origin, for example https://strangeramblings.com. Local device tests also need trusted HTTPS.")
        }
        return url
    }
    /// `timeout`: 25 s fits the small GETs; a POST sync during a backfill can
    /// spend far longer than that on the wire uploading one batch, so the
    /// caller raises it rather than the request timing out under load the
    /// server is still happily processing.
    /// `query` is separate from `path` on purpose: `appendingPathComponent`
    /// escapes a `?`, so "timeline?from=…" would ask for a path no route has —
    /// the same bug the site client once shipped (see `SiteClient.url(for:)`).
    func request<T: Decodable>(_ path: String, method: String = "GET", data: Data? = nil, query: [URLQueryItem] = [], timeout: TimeInterval = 25) async throws -> T {
        // A demo sends nothing to the companion server — no health, no
        // location, not even a read — and refuses before a request exists.
        if SRDemo.isOn { throw CompanionError.message(Self.demoRefusal) }
        guard let baseURL else { throw CompanionError.message("Pair your iPhone first.") }
        var url = baseURL.appendingPathComponent("api/apple/" + path)
        if !query.isEmpty, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            parts.queryItems = query
            url = parts.url ?? url
        }
        var req = URLRequest(url: url)
        req.httpMethod = method; req.httpBody = data; req.timeoutInterval = timeout
        if data != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        PhoneIdentity.apply(to: &req)
        let (body, response) = try await Self.session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let error = try? JSONDecoder().decode(APIError.self, from: body)
            throw CompanionError.response((response as? HTTPURLResponse)?.statusCode ?? 0, error?.error ?? uploadFallbackMessage)
        }
        return try await OffMain.decode(T.self, from: body)
    }
    /// One session for every companion call, kept for the app's life. A new
    /// one per request (as before) paid a fresh TCP and TLS handshake each
    /// time — twice every 30 s during an outing. Still ephemeral, uncached,
    /// cookie-less and never following a redirect, as each per-request one
    /// was; the timeout stays on each `URLRequest`.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        return URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }()
    static let demoRefusal = "Demo mode: nothing is sent from this iPhone. Leave the demo in Settings to connect."
    struct APIError: Decodable { var error: String }
    struct Acknowledgement: Decodable { var accepted: Int? }
    struct PairResponse: Decodable { var token: String; var userId: String }
    func pair(server: String, code: String) async throws {
        let url = try Self.validateURL(server)
        let previousURL = baseURL; let previousToken = token
        baseURL = url; token = nil
        do {
            let data = try JSONEncoder().encode(["code": code.trimmingCharacters(in: .whitespacesAndNewlines), "label": "SR iPhone"])
            let response: PairResponse = try await request("pair", method: "POST", data: data)
            try Keychain.save(response.token); token = response.token
            UserDefaults.standard.set(url, forKey: "server")
        } catch { baseURL = previousURL; token = previousToken; throw error }
    }
}
/// JSON decoding off the main actor. A plain enum's static async function is
/// nonisolated, so it runs on the global executor (Swift 5 mode), not on the
/// caller's actor: a 100 KB answer no longer decodes on the frame a scroll is
/// waiting for. The error is the decoder's own, unchanged.
enum OffMain {
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) async throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}
final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
