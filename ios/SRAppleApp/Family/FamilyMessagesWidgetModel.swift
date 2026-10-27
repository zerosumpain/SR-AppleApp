import Foundation

// msg family on the Home Screen and the Lock Screen: what the app leaves on
// the Keychain shelf (`FamilyShelf`, account `.messages`) for the widgets,
// the thin feed a widget reads for itself, and the bat phone's link — every
// rule about them as a pure function.
//
// SHARED with the widget extension (`SRAppleLive`, see watch.yml), so nothing
// here may reach for the app: no `SR`, no `FamilyMessagesStore`, no
// `parseTimestamp`. Foundation only, so the Linux harness runs its tests
// (`scripts/home-check.sh`).
//
// The widget never sends anything. It shows the latest threads and what has
// not been read, and every tap opens the app: msg family for a message, the
// bat phone's check for the bat phone (John, 2026-10-27).

// MARK: - The feed, as a widget reads it

/// `GET /api/native/family/messages`, as thinly as a widget needs it. The app
/// maps its own `FamilyMessage` into this; the widget decodes it straight off
/// the wire when it refreshes on its own. Lenient like the app's decoders: a
/// missing field costs that field.
struct FamilyMessagesWidgetFeed: Decodable, Equatable {
    struct Reply: Decodable, Equatable {
        var fromName: String
        var mine: Bool
        var body: String
        var reaction: Bool
        var at: String

        init(fromName: String, mine: Bool, body: String, reaction: Bool, at: String) {
            self.fromName = fromName
            self.mine = mine
            self.body = body
            self.reaction = reaction
            self.at = at
        }

        private enum CodingKeys: String, CodingKey { case fromName, mine, body, reaction, at }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            fromName = (try? c.decodeIfPresent(String.self, forKey: .fromName)) ?? "Someone"
            mine = (try? c.decodeIfPresent(Bool.self, forKey: .mine)) ?? false
            body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
            // The site marks a quick-set emoji; a lone emoji from an older
            // site reads as one too.
            reaction = (try? c.decodeIfPresent(Bool.self, forKey: .reaction)) ?? FamilyMessagesWidget.looksLikeReaction(body)
            at = (try? c.decodeIfPresent(String.self, forKey: .at)) ?? ""
        }
    }

    struct Message: Decodable, Equatable {
        var id: String
        var fromName: String
        var mine: Bool
        var body: String
        var at: String
        var replies: [Reply]

        init(id: String, fromName: String, mine: Bool, body: String, at: String, replies: [Reply] = []) {
            self.id = id
            self.fromName = fromName
            self.mine = mine
            self.body = body
            self.at = at
            self.replies = replies
        }

        private enum CodingKeys: String, CodingKey { case id, fromName, mine, body, at, replies }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            fromName = (try? c.decodeIfPresent(String.self, forKey: .fromName)) ?? "Someone"
            mine = (try? c.decodeIfPresent(Bool.self, forKey: .mine)) ?? false
            body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
            at = (try? c.decodeIfPresent(String.self, forKey: .at)) ?? ""
            replies = (try? c.decodeIfPresent([Reply].self, forKey: .replies)) ?? []
        }
    }

    var messages: [Message]

    init(messages: [Message]) {
        self.messages = messages
    }

    private enum CodingKeys: String, CodingKey { case messages }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // One bad message costs that message, not the widget.
        let lossy = (try? c.decodeIfPresent([Lossy<Message>].self, forKey: .messages)) ?? []
        messages = lossy.compactMap(\.value)
    }

    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }
}

// MARK: - What the shelf holds

/// One thread, as a widget row draws it.
struct FamilyMessagesWidgetLine: Codable, Equatable, Identifiable {
    var id: String
    /// "You", or the sender's first name.
    var who: String
    /// One or two letters for the sender's circle.
    var initials: String
    /// The message, on one line and cut short. A poll is its question.
    var text: String
    /// When the thread last moved: the message, or its newest reply.
    var at: Date?
    /// Answers in words.
    var replies: Int
    /// Emoji answers.
    var reactions: Int
    /// The newest answer, when there is one: "Robin: On my way", "Kit 👍".
    var latest: String?
    /// Something in it from somebody else that this phone has not seen.
    var unread: Bool
    var mine: Bool
}

/// What the app leaves on the shelf each time msg family loads, and each
/// time it is read.
struct FamilyMessagesSnapshot: Codable, Equatable {
    /// Lines from other people since msg family was last open on this phone —
    /// the same count as the app's badge (`FamilyMessagesStore.unreadCount`).
    var unread: Int
    /// Whoever wrote the newest line that was not mine.
    var newestFrom: String?
    var newestInitials: String?
    /// The threads that moved last, newest first.
    var threads: [FamilyMessagesWidgetLine]
    /// When msg family was last open here, so a widget that refreshes on its
    /// own counts what is unread the way the app would.
    var readAt: Date?
    var savedAt: Date

    /// Equal but for when it was saved — so an unchanged feed costs no
    /// Keychain write and no widget reload.
    func sameContent(as other: FamilyMessagesSnapshot?) -> Bool {
        guard var other else { return false }
        other.savedAt = savedAt
        return other == self
    }
}

// MARK: - Rules

enum FamilyMessagesWidget {
    /// The most threads any widget draws (the large one).
    static let keep = 5
    /// How much of a message a row carries; a row is one line anyway.
    static let textMax = 120

    /// The shelf's snapshot of a feed, as of `now`. PURE.
    static func snapshot(_ messages: [FamilyMessagesWidgetFeed.Message], readAt: Date?, now: Date = Date(),
                         keep: Int = FamilyMessagesWidget.keep) -> FamilyMessagesSnapshot {
        // Every line, the message and its replies, as who, when and whose.
        typealias Line = (name: String, at: Date?, mine: Bool)
        func lines(_ m: FamilyMessagesWidgetFeed.Message) -> [Line] {
            [(m.fromName, date(m.at), m.mine)] + m.replies.map { ($0.fromName, date($0.at), $0.mine) }
        }
        func isUnread(_ line: Line) -> Bool {
            guard !line.mine, let at = line.at else { return false }
            return readAt.map { at > $0 } ?? true
        }

        let all = messages.flatMap(lines)
        let newest = all.compactMap { line -> (name: String, at: Date)? in
            guard !line.mine, let at = line.at else { return nil }
            return (line.name, at)
        }.max { $0.at < $1.at }

        // Newest activity first; the feed's own order breaks a tie.
        let ordered = messages.enumerated().sorted { a, b in
            let x = activity(a.element) ?? .distantPast, y = activity(b.element) ?? .distantPast
            return x == y ? a.offset < b.offset : x > y
        }.map(\.element)

        let threads = ordered.prefix(max(keep, 0)).map { m -> FamilyMessagesWidgetLine in
            let text = m.replies.filter { !$0.reaction }
            let newestReply = m.replies.enumerated().max { a, b in
                let x = date(a.element.at) ?? .distantPast, y = date(b.element.at) ?? .distantPast
                return x == y ? a.offset < b.offset : x < y
            }?.element
            return FamilyMessagesWidgetLine(
                id: m.id,
                who: m.mine ? "You" : firstName(m.fromName),
                initials: initials(m.fromName),
                text: short(m.body),
                at: activity(m),
                replies: text.count,
                reactions: m.replies.count - text.count,
                latest: newestReply.map(latestLine),
                unread: lines(m).contains(where: isUnread),
                mine: m.mine
            )
        }

        return FamilyMessagesSnapshot(
            unread: all.filter(isUnread).count,
            newestFrom: newest.map { firstName($0.name) },
            newestInitials: newest.map { initials($0.name) },
            threads: Array(threads),
            readAt: readAt,
            savedAt: now
        )
    }

    /// When a thread last moved.
    static func activity(_ m: FamilyMessagesWidgetFeed.Message) -> Date? {
        ([m.at] + m.replies.map(\.at)).compactMap(date).max()
    }

    /// "Robin: On my way", or "Kit 👍" for an emoji answer.
    static func latestLine(_ reply: FamilyMessagesWidgetFeed.Reply) -> String {
        let who = reply.mine ? "You" : firstName(reply.fromName)
        return reply.reaction ? "\(who) \(reply.body)" : "\(who): \(short(reply.body))"
    }

    /// "Sam Lee" → "SL", "sam" → "S". A question mark for no name at all.
    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        let letters = words.compactMap(\.first).map { String($0).uppercased() }.joined()
        return letters.isEmpty ? "?" : letters
    }

    static func firstName(_ name: String) -> String {
        name.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? name
    }

    /// A message on one line, cut at a word near `max`. A poll is written as
    /// its question over numbered options (`FamilyPoll`); a row shows the
    /// question.
    static func short(_ body: String, max: Int = FamilyMessagesWidget.textMax) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = trimmed.hasPrefix("📊") ? (trimmed.split(separator: "\n").first.map(String.init) ?? trimmed) : trimmed
        let flat = source.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard flat.count > max else { return flat }
        let cut = String(flat.prefix(max))
        let word = cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? cut
        return (word.count > max / 2 ? word : cut) + "…"
    }

    /// "now", "5m", "2h", "Mon", "3 Oct" — beside a name, as msg family says it.
    static func when(_ date: Date?, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date else { return "" }
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_GB")
        out.calendar = calendar
        out.timeZone = calendar.timeZone
        out.dateFormat = seconds < 6 * 86_400 ? "EEE" : "d MMM"
        return out.string(from: date)
    }

    /// The site's timestamps: ISO 8601, with or without fractions.
    static func date(_ iso: String) -> Date? {
        guard !iso.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    /// The quick set's emoji (`FamilyMessages.reactions`), for an older site
    /// that does not say.
    static func looksLikeReaction(_ body: String) -> Bool {
        ["👍", "👎", "❤️", "😂", "😮", "✅"].contains(body)
    }

    /// "3 unread", "1 unread", or nil for none — the small widget's line and
    /// every widget's VoiceOver label.
    static func unreadPhrase(_ count: Int) -> String? {
        count > 0 ? "\(count) unread" : nil
    }

    /// "2 replies", "1 reply", or nil.
    static func repliesPhrase(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count == 1 ? "1 reply" : "\(count) replies"
    }
}

// MARK: - The bat phone's link

/// `sr://batphone`: the bat phone widget and control open the app on a check
/// before anything is sent — a thumb brushing a Home Screen is not a decision.
enum BatPhoneURL {
    static let url = URL(string: "sr://batphone")!

    static func matches(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "sr" && url.host?.lowercased() == "batphone"
    }
}

// MARK: - Samples

/// A made-up family for a widget's placeholder and the gallery. The repo is
/// public: made-up names only.
enum FamilyMessagesWidgetSamples {
    static func snapshot(now: Date = Date()) -> FamilyMessagesSnapshot {
        func ago(_ minutes: Double) -> String {
            ISO8601DateFormatter().string(from: now.addingTimeInterval(-minutes * 60))
        }
        let messages = [
            FamilyMessagesWidgetFeed.Message(id: "w1", fromName: "Robin", mine: false, body: "Who's in for pizza tonight?", at: ago(42), replies: [
                .init(fromName: "Kit", mine: false, body: "Me!", reaction: false, at: ago(30)),
                .init(fromName: "You", mine: true, body: "👍", reaction: true, at: ago(25)),
                .init(fromName: "Sam", mine: false, body: "Pepperoni please", reaction: false, at: ago(6)),
            ]),
            FamilyMessagesWidgetFeed.Message(id: "w2", fromName: "Kit", mine: false, body: "Left my PE kit by the door, can someone bring it?", at: ago(18)),
            FamilyMessagesWidgetFeed.Message(id: "w3", fromName: "You", mine: true, body: "Home by six", at: ago(95), replies: [
                .init(fromName: "Robin", mine: false, body: "❤️", reaction: true, at: ago(90)),
            ]),
            FamilyMessagesWidgetFeed.Message(id: "w4", fromName: "Sam", mine: false, body: "Bins go out tonight", at: ago(300)),
            FamilyMessagesWidgetFeed.Message(id: "w5", fromName: "Robin", mine: false, body: "Dentist moved to Thursday", at: ago(1_500)),
        ]
        return FamilyMessagesWidget.snapshot(messages, readAt: now.addingTimeInterval(-20 * 60), now: now)
    }
}
