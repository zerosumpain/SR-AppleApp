import Foundation

// The family backlog's wire shapes, and the share sheet's way in.
//
// SHARED with the share extension (`SRAppleShare`, see watch.yml): Foundation
// only, and nothing of the app's beyond `FamilyBoardModels.swift` and the
// Keychain shelf in `FamilyWidgetShared.swift`, which the extension compiles
// too.
//
// The extension has no pairing of its own. It posts with the site credential
// the app already leaves on the shelf for the family widgets — there exactly
// while this person may see the family boards (`FamilyWidgetBridge.sync`),
// gone the moment they may not. So "Share → SR" works for precisely the
// people who can open the Backlog page, and for nobody else.

/// One thing on the backlog (`GET /api/native/family/backlog`).
struct FamilyBacklogItem: Codable, Equatable, Identifiable {
    var id: String
    /// "video", "page" or "idea".
    var kind: String
    var url: String?
    /// "youtube", "tiktok", "instagram" or "web"; nil for an idea.
    var provider: String?
    var title: String?
    var siteName: String?
    var thumbnailUrl: String?
    var note: String?
    /// Who it was shared for; nil is everyone.
    var forId: String?
    var addedById: String
    /// "new", "done" or "dismissed".
    var status: String
    var doneById: String?
    var doneAt: String?
    var createdAt: String
}

struct FamilyBacklogBoard: Codable, Equatable {
    var me: FamilyTaskMe
    var people: [FamilyTaskPerson]
    /// Still to watch, read or do — newest first.
    var items: [FamilyBacklogItem]
    /// Done or not for us, in the last 30 days.
    var finished: [FamilyBacklogItem]

    init(me: FamilyTaskMe, people: [FamilyTaskPerson], items: [FamilyBacklogItem], finished: [FamilyBacklogItem]) {
        self.me = me; self.people = people; self.items = items; self.finished = finished
    }

    private enum CodingKeys: String, CodingKey { case me, people, items, finished }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        me = (try? c.decodeIfPresent(FamilyTaskMe.self, forKey: .me)) ?? FamilyTaskMe(id: "", parent: false)
        people = (try? c.decodeIfPresent([FamilyTaskPerson].self, forKey: .people)) ?? []
        items = (try? c.decodeIfPresent([FamilyBacklogItem].self, forKey: .items)) ?? []
        finished = (try? c.decodeIfPresent([FamilyBacklogItem].self, forKey: .finished)) ?? []
    }
}

/// `POST /api/native/family/backlog` — what the share sheet hands over. The
/// site finds the link, cleans it and names it; the phone sends it as it came.
struct FamilyBacklogShare: Codable, Equatable {
    var url: String?
    var text: String?
    var note: String?
    var forId: String?
}

struct FamilyBacklogAdded: Decodable {
    var item: FamilyBacklogItem
    var duplicate: Bool
}

/// `PATCH /api/native/family/backlog/[id]` — `{ action }`.
enum FamilyBacklogAction: String, CaseIterable {
    case done, dismiss, reopen, delete
}

/// Words and choices both the page and the share sheet use.
enum FamilyBacklogText {
    /// "youtube.com" from a link — what an item without a title is called.
    static func host(_ url: String?) -> String? {
        guard let url, let host = URL(string: url)?.host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The line a row leads with: its title, else its site, else its link.
    static func title(_ item: FamilyBacklogItem) -> String {
        if let title = item.title, !title.isEmpty { return title }
        return host(item.url) ?? item.url ?? "Untitled"
    }

    /// The first web link in shared text — what the extension shows while
    /// the site works out the rest.
    static func firstLink(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range)
            .compactMap(\.url)
            .first { $0.scheme == "https" || $0.scheme == "http" }
    }
}

/// Posting a share with the shelf's credential, from the extension or from
/// the app draining what the extension could not send.
enum FamilyBacklogPost {
    enum Outcome: Equatable {
        case added(FamilyBacklogItem, duplicate: Bool)
        /// No credential on the shelf: open the app once, or no family access.
        case notSignedIn
        /// The site said no, in its own words.
        case refused(String)
        /// Never reached the site: worth keeping and sending later.
        case unreachable
    }

    /// The list, for the share sheet's "For" picker. Nil when there is no
    /// credential or no answer — the picker then offers only "Everyone".
    static func board() async -> FamilyBacklogBoard? {
        guard let credential = FamilyShelf.load(FamilyWidgetCredential.self, .credential),
              let origin = URL(string: credential.origin), origin.scheme == "https" else { return nil }
        var request = URLRequest(url: origin.appending(path: "api/native/family/backlog"))
        request.timeoutInterval = 10
        request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(FamilyBacklogBoard.self, from: data)
    }

    static func send(_ share: FamilyBacklogShare, timeout: TimeInterval = 20) async -> Outcome {
        guard let credential = FamilyShelf.load(FamilyWidgetCredential.self, .credential),
              let origin = URL(string: credential.origin), origin.scheme == "https",
              let body = try? JSONEncoder().encode(share) else { return .notSignedIn }
        var request = URLRequest(url: origin.appending(path: "api/native/family/backlog"))
        request.httpMethod = "POST"
        request.httpBody = body
        // The site follows a short link and reads the page before it answers.
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return .unreachable }
        switch http.statusCode {
        case 200..<300:
            guard let added = try? JSONDecoder().decode(FamilyBacklogAdded.self, from: data) else { return .unreachable }
            return .added(added.item, duplicate: added.duplicate)
        case 401, 403:
            return .notSignedIn
        case 400..<500:
            let error = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            return .refused(error ?? "The site would not take that.")
        default:
            return .unreachable
        }
    }
}

/// Shares the extension could not send — no signal on the bus — kept on the
/// shelf until the app next opens and sends them. Bounded: a share sheet
/// that fails twenty times is not going to be helped by a twenty-first.
enum FamilyBacklogQueue {
    static let limit = 20

    struct Pending: Codable, Equatable {
        var share: FamilyBacklogShare
        var at: Date
    }

    static func all() -> [Pending] {
        FamilyShelf.load([Pending].self, .backlogQueue) ?? []
    }

    @discardableResult
    static func add(_ share: FamilyBacklogShare, at: Date = Date()) -> Bool {
        var list = all()
        guard !list.contains(where: { $0.share == share }) else { return true }
        list.append(Pending(share: share, at: at))
        return FamilyShelf.write(try? JSONEncoder().encode(Array(list.suffix(limit))), .backlogQueue)
    }

    static func replace(_ list: [Pending]) {
        FamilyShelf.write(list.isEmpty ? nil : (try? JSONEncoder().encode(list)), .backlogQueue)
    }
}
