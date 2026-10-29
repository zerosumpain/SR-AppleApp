import Foundation

/// Where a link to one jkai thread leads, and how to write one.
///
/// - `sr://chat/<id>` — the app's own link: a Shortcut, a widget, another app.
///   `sr://chat` alone is the Chat page.
/// - A tapped chat push. SR-Main sends `conversationId` in `userInfo` when it
///   has one, and always a `url` — `/jkai?c=<id>` — which is all that survives
///   on a phone that hides notification details (`privatePush` keeps only
///   `category` and `url`). Both are read, in that order.
/// - Handoff and "Open jkai on the web": `/jkai?c=<id>` on the paired site,
///   which the web desk opens on that thread.
///
/// Foundation only: the Linux harness compiles and tests it.
struct ChatLink: Equatable {
    /// Nil: the Chat page itself.
    var conversationId: String?

    static func from(url: URL) -> ChatLink? {
        guard url.scheme?.lowercased() == "sr", url.host?.lowercased() == "chat" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard let raw = parts.first else { return ChatLink(conversationId: nil) }
        guard let id = clean(raw.removingPercentEncoding ?? raw) else { return ChatLink(conversationId: nil) }
        return ChatLink(conversationId: id)
    }

    /// The thread a tapped notification is about, if it names one.
    static func conversationId(userInfo: [AnyHashable: Any]) -> String? {
        if let id = (userInfo["conversationId"] as? String).flatMap(clean) { return id }
        guard let raw = userInfo["url"] as? String else { return nil }
        return conversationId(link: raw)
    }

    /// `sr://chat/<id>`, `/jkai?c=<id>` or `https://<site>/jkai?c=<id>`.
    static func conversationId(link raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("sr:"), let url = URL(string: trimmed) {
            return from(url: url)?.conversationId
        }
        // A site path or an absolute site link. Only `/jkai`: a `c=` on any
        // other page means something else.
        let absolute = trimmed.hasPrefix("/") ? "https://site.invalid" + trimmed : trimmed
        guard let parts = URLComponents(string: absolute),
              parts.scheme == "https" || parts.scheme == "http",
              parts.path == "/jkai" || parts.path == "/jkai/" else { return nil }
        return parts.queryItems?.first(where: { $0.name == "c" })?.value.flatMap(clean)
    }

    /// `jkai?c=<id>`, for `SiteClient.webURL`. The id is escaped as a query
    /// VALUE, because `url(for:)` takes the query verbatim.
    static func webPath(_ conversationId: String) -> String {
        "jkai?c=" + (conversationId.addingPercentEncoding(withAllowedCharacters: queryValue) ?? conversationId)
    }

    /// `sr://chat/<id>`.
    static func appURL(_ conversationId: String) -> URL? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/%?#")
        let id = conversationId.addingPercentEncoding(withAllowedCharacters: allowed) ?? conversationId
        return URL(string: "sr://chat/\(id)")
    }

    /// A thread id as the site writes them: short, and nothing that could
    /// carry a path or a query of its own. Anything else is not a thread.
    static func clean(_ raw: String) -> String? {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id.count <= 128,
              id.unicodeScalars.allSatisfy({ idCharacters.contains($0) }) else { return nil }
        return id
    }

    private static let idCharacters: CharacterSet = {
        var set = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        set.insert(charactersIn: "-_.:")
        return set
    }()

    /// RFC 3986 unreserved.
    private static let queryValue: CharacterSet = {
        var set = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        set.insert(charactersIn: "-._~")
        return set
    }()
}
