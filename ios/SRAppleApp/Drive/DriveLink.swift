import Foundation

/// Where a Drive link leads: a space, a folder in it, and maybe one file.
///
/// One grammar (build map D3), query form so a `/` inside a folder needs no
/// rule of its own:
///
///     sr://drive?space=<mine|shared>&folder=<percent-encoded path>&file=<id>
///
/// Every part is optional: `sr://drive` is the top of My files. A tapped
/// "Saved invoice.pdf" push carries one of these as its `url` (and nothing
/// else survives a phone that hides notification details), as does
/// "Open Drive" from a Shortcut.
///
/// The site's own page link (`/drive?path=…&file=…`, the push's `webUrl`) is
/// read too, as My files: the web page is the owner's own drive.
///
/// Foundation only, so the Linux harness can compile and run it.
struct DriveLink: Equatable, Hashable {
    var space: DriveSpace = .mine
    /// Relative to the space: "" for its top, else "Mail/important/2026-11".
    var folder: String = ""
    var fileId: String? = nil

    static func from(url: URL) -> DriveLink? {
        guard let scheme = url.scheme?.lowercased() else { return nil }
        if scheme == "sr" {
            guard url.host?.lowercased() == "drive" else { return nil }
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let space = value("space", in: items).flatMap { DriveSpace(rawValue: $0.lowercased()) } ?? .mine
            return DriveLink(space: space, folder: cleanFolder(value("folder", in: items)),
                             fileId: cleanId(value("file", in: items)))
        }
        guard scheme == "https" || scheme == "http",
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.path == "/drive" || parts.path == "/drive/" else { return nil }
        let items = parts.queryItems ?? []
        return DriveLink(space: .mine, folder: cleanFolder(value("path", in: items)), fileId: cleanId(value("file", in: items)))
    }

    /// A string link: `sr://drive?…`, `https://<site>/drive?…` or the site
    /// path `/drive?…`.
    static func from(link raw: String) -> DriveLink? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let absolute = trimmed.hasPrefix("/") ? "https://site.invalid" + trimmed : trimmed
        guard let url = URL(string: absolute) else { return nil }
        return from(url: url)
    }

    /// A tapped notification's `url`, when it is a Drive one.
    static func from(userInfo: [AnyHashable: Any]) -> DriveLink? {
        guard let text = userInfo["url"] as? String else { return nil }
        return from(link: text)
    }

    /// `sr://drive?space=…&folder=…&file=…`, with only the parts that say something.
    var url: URL {
        var query = ["space=\(space.rawValue)"]
        if !folder.isEmpty { query.append("folder=\(Self.encode(folder))") }
        if let fileId { query.append("file=\(Self.encode(fileId))") }
        return URL(string: "sr://drive?" + query.joined(separator: "&"))!
    }

    /// The same place on the website: `/drive?path=…&file=…`. The web page
    /// is the owner's whole drive, so a folder of My files is the same path
    /// there; the family's Shared folder has no page of its own.
    var webPath: String {
        var query: [String] = []
        if !folder.isEmpty { query.append("path=\(Self.encode(folder))") }
        if let fileId { query.append("file=\(Self.encode(fileId))") }
        return query.isEmpty ? "/drive" : "/drive?" + query.joined(separator: "&")
    }

    // MARK: - Reading

    private static func value(_ name: String, in items: [URLQueryItem]) -> String? {
        guard let raw = items.first(where: { $0.name == name })?.value else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// "/Mail//important/" → "Mail/important". A link naming `.` or `..`
    /// anywhere is not a folder of this space, so it opens the top instead.
    static func cleanFolder(_ raw: String?) -> String {
        guard let raw else { return "" }
        let parts = raw.split(separator: "/", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !parts.contains(where: { $0 == "." || $0 == ".." }),
              !raw.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return "" }
        let joined = parts.joined(separator: "/")
        return joined.count <= 1024 ? joined : ""
    }

    /// A file id as the site mints them; anything else is dropped, so a link
    /// can never address another route.
    static func cleanId(_ raw: String?) -> String? {
        guard let raw, raw.range(of: #"^[A-Za-z0-9_.:-]{1,128}$"#, options: .regularExpression) != nil else { return nil }
        return raw
    }

    /// `encodeURIComponent`: RFC 3986 unreserved kept, everything else escaped
    /// — `/` too, so a folder is one query value.
    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    private static let unreserved: CharacterSet = {
        var set = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        set.insert(charactersIn: "-._~")
        return set
    }()
}
