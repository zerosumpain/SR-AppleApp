import Foundation
import SwiftUI

// "msg family": a line pushed to everyone else in the family, and their
// replies — an emoji from the quick set or a line of text — under it. Each
// message is a THREAD: its replies hang under it, the sender's own follow-ups
// in line with the message and everybody else's indented, each line marked
// with its person's circle (John, 2026-10-21).
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
    /// The sender's place in the household (the map's subject), for their
    /// circle and colour; nil from an older site or for somebody not on it.
    var fromSubject: String?
    var mine: Bool
    var body: String
    var reaction: Bool
    var at: String

    init(id: String, fromId: String, fromName: String, fromSubject: String? = nil, mine: Bool, body: String, reaction: Bool, at: String) {
        self.id = id
        self.fromId = fromId
        self.fromName = fromName
        self.fromSubject = fromSubject
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
        fromSubject = (try? c.decodeIfPresent(String.self, forKey: .fromSubject)) ?? nil
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
    var fromSubject: String?
    var mine: Bool
    var body: String
    var at: String
    var pushed: Int
    var recipients: Int
    var replies: [FamilyMessageReply]

    init(id: String, fromId: String, fromName: String, fromSubject: String? = nil, mine: Bool, body: String, at: String,
         pushed: Int = 0, recipients: Int = 0, replies: [FamilyMessageReply] = []) {
        self.id = id
        self.fromId = fromId
        self.fromName = fromName
        self.fromSubject = fromSubject
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
        fromSubject = (try? c.decodeIfPresent(String.self, forKey: .fromSubject)) ?? nil
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

    /// A reply from whoever started the thread: drawn in line with the
    /// message, where everybody else's are indented under it.
    func isFromSender(_ reply: FamilyMessageReply) -> Bool {
        if !fromId.isEmpty, !reply.fromId.isEmpty { return reply.fromId == fromId }
        return mine && reply.mine
    }

    /// When the thread last moved: the message, or its newest reply.
    var lastActivity: Date? {
        ([at] + replies.map(\.at)).compactMap(parseTimestamp).max()
    }

    /// Everybody who answered in words, once each, in the order they first did.
    var repliers: [FamilyMessageReply] {
        var seen = Set<String>()
        return textReplies.filter { seen.insert($0.fromId.isEmpty ? $0.fromName : $0.fromId).inserted }
    }
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

    /// One message or reply: where it is deleted.
    static func itemPath(_ id: String) -> String {
        let safe = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? id
        return "\(path)/\(safe)"
    }

    static func repliesPath(_ id: String) -> String { "\(itemPath(id))/replies" }

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
    /// What is on its way: "new", or the id of a message a reply (or a
    /// delete) is going to. One per item, not one for the store: a single
    /// slot meant a reaction on one thread silently did nothing while a
    /// quick line or another thread's reply was still sending.
    @Published private(set) var inFlight: Set<String> = []

    func isBusy(_ key: String) -> Bool { inFlight.contains(key) }
    @Published var message: String?
    /// A passing confirmation — "Reminder set for 18:00".
    @Published var notice: String?
    /// When this phone last had msg family in front of somebody. Lines from
    /// other people newer than this are unread.
    @Published private(set) var readAt: Date? = UserDefaults.standard.object(forKey: FamilyMessagesStore.readKey) as? Date
    /// Threads pinned to the top of msg family, on this phone only.
    @Published private(set) var pinned: Set<String> = Set(UserDefaults.standard.stringArray(forKey: FamilyMessagesStore.pinnedKey) ?? [])

    static let readKey = "familyMessages.readAt"
    static let pinnedKey = "familyMessages.pinned"
    static let draftsKey = "familyMessages.drafts"

    /// The threads, the one that moved last at the foot — the way a
    /// conversation reads, and where the box to write in is. Undo and the
    /// suggestions read it; msg family itself draws `stream`.
    var thread: [FamilyMessage] {
        (feed?.messages ?? []).reversed().enumerated().sorted { a, b in
            let x = a.element.lastActivity ?? .distantPast, y = b.element.lastActivity ?? .distantPast
            return x == y ? a.offset < b.offset : x < y
        }.map(\.element)
    }

    /// Every message and reply in words as one conversation, oldest first,
    /// the way msg family draws it (`FamilyChatStream`).
    var stream: [FamilyChatStream.Line] {
        FamilyChatStream.lines((feed?.messages ?? []).reversed().map(Self.streamed), now: Date())
    }

    /// A message as the stream reads it: emoji and poll votes are counted on
    /// the message, so they are not lines.
    static func streamed(_ message: FamilyMessage) -> FamilyChatStream.Message {
        let poll = FamilyPoll.parse(message.body)
        return FamilyChatStream.Message(
            id: message.id, from: message.fromId.isEmpty ? message.fromName : message.fromId, name: message.fromName,
            body: message.body, at: parseTimestamp(message.at), mine: message.mine,
            replies: message.replies.map { reply in
                FamilyChatStream.Reply(
                    id: reply.id, from: reply.fromId.isEmpty ? reply.fromName : reply.fromId, name: reply.fromName,
                    body: reply.body, at: parseTimestamp(reply.at), mine: reply.mine,
                    counted: reply.reaction || poll?.option(of: reply.body) != nil, subject: reply.fromSubject
                )
            },
            subject: message.fromSubject
        )
    }

    /// One thread, by its message.
    func threadMessage(_ id: String) -> FamilyMessage? { feed?.messages.first { $0.id == id } }

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

    // MARK: - Unread

    /// Every line in a thread — the message and its replies — as when and whose.
    static func lines(_ message: FamilyMessage) -> [(at: Date?, mine: Bool)] {
        [(parseTimestamp(message.at), message.mine)] + message.replies.map { (parseTimestamp($0.at), $0.mine) }
    }

    /// Lines from other people since msg family was last open here.
    var unreadCount: Int {
        FamilyMessageTools.unread((feed?.messages ?? []).flatMap(Self.lines), since: readAt)
    }

    /// Whether a thread has a line from somebody else newer than `since`.
    func isUnread(_ message: FamilyMessage, since: Date?) -> Bool {
        FamilyMessageTools.unread(Self.lines(message), since: since) > 0
    }

    /// Everything here has now been seen.
    func markRead() {
        let at = max(lastActivity ?? .distantPast, Date())
        readAt = at
        UserDefaults.standard.set(at, forKey: Self.readKey)
    }

    // MARK: - Pins and drafts (this phone only)

    func togglePin(_ id: String) {
        if pinned.contains(id) { pinned.remove(id) } else { pinned.insert(id) }
        UserDefaults.standard.set(Array(pinned).sorted(), forKey: Self.pinnedKey)
        SRHaptic.select()
    }

    /// What was being written in a box ("new", or a thread's id) when it was left.
    static func draft(_ key: String) -> String {
        (UserDefaults.standard.dictionary(forKey: draftsKey) as? [String: String])?[key] ?? ""
    }

    static func saveDraft(_ text: String, for key: String) {
        var all = (UserDefaults.standard.dictionary(forKey: draftsKey) as? [String: String]) ?? [:]
        all[key] = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        UserDefaults.standard.set(all, forKey: draftsKey)
    }

    // MARK: - Names

    /// This phone's own person's first name, for "@" mentions of them.
    var myName: String? {
        if let me = FamilyStore.current?.view?.people.first(where: \.isSelf) { return Self.first(me.name) }
        return (feed?.messages ?? []).first(where: \.mine).map { Self.first($0.fromName) }
    }

    /// Everyone else an "@" could name: the household, then anyone who has
    /// written here.
    var mentionNames: [String] {
        let household = (FamilyStore.current?.view?.people ?? []).filter { !$0.isSelf }.map { Self.first($0.name) }
        let writers = (feed?.messages ?? []).flatMap { m in [(m.fromName, m.mine)] + m.replies.map { ($0.fromName, $0.mine) } }
            .filter { !$0.1 }.map { Self.first($0.0) }
        return FamilyMessageTools.mentionCandidates("", names: household + writers)
    }

    /// `nonisolated`: pure, and the reminder scheduler calls it off the main actor.
    nonisolated static func first(_ name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    // MARK: - Polls

    /// The votes under a poll, as the tally reads them.
    static func votes(_ message: FamilyMessage) -> [FamilyPoll.Vote] {
        message.replies.map {
            FamilyPoll.Vote(voter: $0.fromId.isEmpty ? $0.fromName : $0.fromId, name: $0.mine ? "You" : first($0.fromName),
                            body: $0.body, at: parseTimestamp($0.at), mine: $0.mine)
        }
    }

    /// Vote for an option: take back this person's earlier votes, then reply
    /// with the option's marker. Voting for the option already held takes it back.
    func vote(_ option: Int, in message: FamilyMessage, poll: FamilyPoll) async {
        guard !isBusy(message.id), FamilyPoll.markers.indices.contains(option) else { return }
        let mine = message.replies.filter { $0.mine && poll.option(of: $0.body) != nil }
        let held = mine.contains { poll.option(of: $0.body) == option }
        for reply in mine { _ = await delete(reply.id) }
        if !held { _ = await reply(to: message.id, FamilyPoll.markers[option]) }
    }

    func load() async {
        guard SiteClient.shared.isPaired, !loading else { return }
        loading = true
        defer { loading = false; loaded = true }
        do {
            let fetched: FamilyMessagesFeed = try await SiteClient.shared.send(FamilyMessages.path)
            feed = fetched
            FamilyMessagesWidgetBridge.save(self)
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
    ///
    /// `quiet` is the bat phone's: no success or failure buzz, because a phone
    /// held by somebody who needs help must not give them away, and it goes
    /// as this phone's own person (`asSelf`) whoever is being viewed.
    func send(_ text: String, quiet: Bool = false) async -> Bool {
        guard !isBusy("new"), let body = FamilyMessages.sendable(text) else { return false }
        inFlight.insert("new")
        defer { inFlight.remove("new") }
        do {
            let data = try JSONEncoder().encode(["body": body])
            let _: EmptyReply = try await SiteClient.shared.send(FamilyMessages.path, method: "POST", body: data, asSelf: quiet)
            if !quiet { SRHaptic.ok() }
            message = nil
            await load()
            return true
        } catch {
            if !quiet { SRHaptic.bad() }
            message = Self.sentence(for: error)
            return false
        }
    }

    /// An emoji or a line of text under a message. True when it went.
    func reply(to id: String, _ text: String) async -> Bool {
        guard !isBusy(id), let body = FamilyMessages.sendable(text) else { return false }
        inFlight.insert(id)
        defer { inFlight.remove(id) }
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

    /// Take back a message (with every reply under it) or one of this
    /// person's replies — the site refuses anyone else's. True when it went.
    func delete(_ id: String) async -> Bool {
        guard !isBusy(id) else { return false }
        inFlight.insert(id)
        defer { inFlight.remove(id) }
        do {
            _ = try await SiteClient.shared.call(FamilyMessages.itemPath(id), method: "DELETE")
            SRHaptic.ok()
            message = nil
            await load()
            return true
        } catch {
            SRHaptic.bad()
            message = Self.sentence(for: error)
            // Already gone (another phone of theirs got there first): show the list as it is.
            if case .status(404, _)? = error as? SiteError { await load() }
            return false
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
