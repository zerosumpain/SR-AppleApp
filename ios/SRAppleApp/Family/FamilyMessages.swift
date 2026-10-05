import Foundation
import SwiftUI

// "msg family": a line pushed to everyone else in the family, and their
// replies — an emoji from the quick set or a line of text — under it.
//
// The contract is SR-Main's `GET/POST /api/native/family/messages` and
// `POST /api/native/family/messages/:id/replies`. The site pushes each message
// to every other family phone (category `family-msg`, which wears the reply
// buttons in `AlertActions`) and each reply to the message's sender only
// (`family-msg-reply`). Decoders are lenient: a missing field costs that field.

// MARK: - Wire

struct FamilyMessageReply: Codable, Identifiable, Equatable {
    var id: String
    var fromId: String
    var fromName: String
    var mine: Bool
    var body: String
    var reaction: Bool
    var at: String

    init(id: String, fromId: String, fromName: String, mine: Bool, body: String, reaction: Bool, at: String) {
        self.id = id
        self.fromId = fromId
        self.fromName = fromName
        self.mine = mine
        self.body = body
        self.reaction = reaction
        self.at = at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        fromId = (try? c.decodeIfPresent(String.self, forKey: .fromId)) ?? ""
        fromName = (try? c.decodeIfPresent(String.self, forKey: .fromName)) ?? "Someone"
        mine = (try? c.decodeIfPresent(Bool.self, forKey: .mine)) ?? false
        body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
        reaction = (try? c.decodeIfPresent(Bool.self, forKey: .reaction)) ?? FamilyMessages.reactions.contains(body)
        at = (try? c.decodeIfPresent(String.self, forKey: .at)) ?? ""
    }
}

struct FamilyMessage: Codable, Identifiable, Equatable {
    var id: String
    var fromId: String
    var fromName: String
    var mine: Bool
    var body: String
    var at: String
    var pushed: Int
    var recipients: Int
    var replies: [FamilyMessageReply]

    init(id: String, fromId: String, fromName: String, mine: Bool, body: String, at: String,
         pushed: Int = 0, recipients: Int = 0, replies: [FamilyMessageReply] = []) {
        self.id = id
        self.fromId = fromId
        self.fromName = fromName
        self.mine = mine
        self.body = body
        self.at = at
        self.pushed = pushed
        self.recipients = recipients
        self.replies = replies
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        fromId = (try? c.decodeIfPresent(String.self, forKey: .fromId)) ?? ""
        fromName = (try? c.decodeIfPresent(String.self, forKey: .fromName)) ?? "Someone"
        mine = (try? c.decodeIfPresent(Bool.self, forKey: .mine)) ?? false
        body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
        at = (try? c.decodeIfPresent(String.self, forKey: .at)) ?? ""
        pushed = (try? c.decodeIfPresent(Int.self, forKey: .pushed)) ?? 0
        recipients = (try? c.decodeIfPresent(Int.self, forKey: .recipients)) ?? 0
        replies = (try? c.decodeIfPresent([FamilyMessageReply].self, forKey: .replies)) ?? []
    }

    /// The emoji answers, each once, in the quick set's order, with how many
    /// gave it and whether one of them was me.
    var tally: [FamilyMessages.Tally] {
        let reactions = replies.filter(\.reaction)
        var order = FamilyMessages.reactions.filter { r in reactions.contains { $0.body == r } }
        for r in reactions where !order.contains(r.body) { order.append(r.body) }
        return order.map { emoji in
            let given = reactions.filter { $0.body == emoji }
            return FamilyMessages.Tally(emoji: emoji, count: given.count, mine: given.contains(where: \.mine),
                                        names: given.map(\.fromName))
        }
    }

    /// The text answers, oldest first.
    var textReplies: [FamilyMessageReply] { replies.filter { !$0.reaction } }
}

struct FamilyMessagesFeed: Codable, Equatable {
    struct Me: Codable, Equatable { var id: String }
    var me: Me?
    var reactions: [String]
    var messages: [FamilyMessage]

    init(me: Me? = nil, reactions: [String] = FamilyMessages.reactions, messages: [FamilyMessage]) {
        self.me = me
        self.reactions = reactions
        self.messages = messages
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        me = try? c.decodeIfPresent(Me.self, forKey: .me)
        let sent = (try? c.decodeIfPresent([String].self, forKey: .reactions)) ?? []
        reactions = sent.isEmpty ? FamilyMessages.reactions : sent
        messages = (try? c.decodeIfPresent([FamilyMessage].self, forKey: .messages)) ?? []
    }
}

// MARK: - Rules

enum FamilyMessages {
    /// The quick replies when the site has not said. The site's own list wins.
    static let reactions = ["👍", "👎", "❤️", "😂", "😮", "✅"]
    static let path = "api/native/family/messages"
    static let bodyMax = 500

    static func repliesPath(_ id: String) -> String {
        let safe = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? id
        return "\(path)/\(safe)/replies"
    }

    /// What may be sent: trimmed, non-empty, under the cap.
    static func sendable(_ text: String) -> String? {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.count <= bodyMax else { return nil }
        return body
    }

    struct Tally: Equatable, Identifiable {
        var emoji: String
        var count: Int
        var mine: Bool
        var names: [String]
        var id: String { emoji }
    }

    /// "5m", "2h", "Mon", "3 Oct" — beside a name.
    static func when(_ iso: String, now: Date = Date()) -> String {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        guard let date = format.date(from: iso) ?? plain.date(from: iso) else { return "" }
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_GB")
        out.dateFormat = seconds < 6 * 86_400 ? "EEE" : "d MMM"
        return out.string(from: date)
    }
}

// MARK: - Store

@MainActor
final class FamilyMessagesStore: ObservableObject {
    static let shared = FamilyMessagesStore()

    @Published private(set) var feed: FamilyMessagesFeed?
    @Published private(set) var loading = false
    @Published private(set) var loaded = false
    /// "new", or the id of the message a reply is on its way to.
    @Published private(set) var busy: String?
    @Published var message: String?

    /// Oldest first, the way a conversation reads.
    var thread: [FamilyMessage] { (feed?.messages ?? []).reversed() }

    /// The newest message or reply, for the thread list's row.
    private var newest: (who: String, body: String, at: String)? {
        let lines = (feed?.messages ?? []).flatMap { m in
            [(who: m.mine ? "You" : m.fromName, body: m.body, at: m.at)]
                + m.replies.map { (who: $0.mine ? "You" : $0.fromName, body: $0.body, at: $0.at) }
        }
        return lines.max { (parseTimestamp($0.at) ?? .distantPast) < (parseTimestamp($1.at) ?? .distantPast) }
    }
    var lastActivityISO: String? { newest?.at }
    var lastActivity: Date? { newest.flatMap { parseTimestamp($0.at) } }
    var latestLine: String? { newest.map { "\($0.who): \($0.body)" } }
    var reactions: [String] { feed?.reactions ?? FamilyMessages.reactions }

    func load() async {
        guard SiteClient.shared.isPaired, !loading else { return }
        loading = true
        defer { loading = false; loaded = true }
        do {
            let fetched: FamilyMessagesFeed = try await SiteClient.shared.send(FamilyMessages.path)
            feed = fetched
            message = nil
        } catch is CancellationError {
            return
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            if let failure = error as? SiteError, failure.status == 401 || failure.status == 403 { feed = nil }
            message = Self.sentence(for: error)
        }
    }

    /// Send to the family. True when it went.
    func send(_ text: String) async -> Bool {
        guard busy == nil, let body = FamilyMessages.sendable(text) else { return false }
        busy = "new"
        defer { busy = nil }
        do {
            let data = try JSONEncoder().encode(["body": body])
            let _: EmptyReply = try await SiteClient.shared.send(FamilyMessages.path, method: "POST", body: data)
            SRHaptic.ok()
            message = nil
            await load()
            return true
        } catch {
            SRHaptic.bad()
            message = Self.sentence(for: error)
            return false
        }
    }

    /// An emoji or a line of text under a message. True when it went.
    func reply(to id: String, _ text: String) async -> Bool {
        guard busy == nil, let body = FamilyMessages.sendable(text) else { return false }
        busy = id
        defer { busy = nil }
        if await Self.post(reply: body, to: id, asSelf: false) == nil {
            SRHaptic.ok()
            message = nil
            await load()
            return true
        }
        SRHaptic.bad()
        message = "Your reply was not sent."
        return false
    }

    /// The reply call itself, shared with the notification's buttons — which
    /// answer as this phone's own person (`asSelf`), whoever the app is being
    /// viewed as. Nil when it went; otherwise why not.
    static func post(reply body: String, to id: String, asSelf: Bool) async -> String? {
        do {
            let data = try JSONEncoder().encode(["body": body])
            let _: EmptyReply = try await SiteClient.shared.send(FamilyMessages.repliesPath(id), method: "POST", body: data, asSelf: asSelf)
            return nil
        } catch {
            return sentence(for: error)
        }
    }

    func reset() {
        feed = nil
        loaded = false
        message = nil
    }

    static func sentence(for error: Error) -> String {
        switch error as? SiteError {
        case .status(let code, let text)?:
            switch code {
            case 403 where AccessStore.shared.viewingAs != nil: return "View as is look-only."
            case 403: return text.isEmpty ? "Messages are for the family." : text
            case 404: return "That message has gone."
            default: return text
            }
        case .invalid(let text, _)?:
            return text
        default:
            return error.localizedDescription
        }
    }
}
