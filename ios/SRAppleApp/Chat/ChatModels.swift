import Foundation

/// A thread in the ledger.
struct Conversation: Decodable, Identifiable, Hashable {
    let id: String
    /// `var`, because a rename and a pin are done from the list itself and the
    /// row has to redraw before the reload comes back. A `let` here forced a
    /// full refetch to show a pin landing, which on a slow connection looked
    /// like the swipe had not registered.
    var title: String?
    let source: String?
    var pinned: Bool
    let messageCount: Int
    let modelProvider: String?
    let modelId: String?
    /// Already clipped to 200 characters server-side.
    let preview: String?
    let createdAt: String?
    let updatedAt: String?

    /// Never "Untitled". The site names a thread from its opening message on
    /// the first reply; one it has not named yet is called by what was last
    /// said in it, and one with nothing said in it is exactly what it is — new.
    var displayTitle: String {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "new thread" {
            return title
        }
        if let said = oneLinePreview { return Self.clip(said) }
        return "New thread"
    }

    /// A line cut at a whole word, the way the site cuts a title.
    static func clip(_ text: String, max: Int = 48) -> String {
        guard text.count > max else { return text }
        let cut = String(text.prefix(max))
        let words = cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? cut
        return words.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:—-")) + "…"
    }

    /// Worth a row: somebody wrote in it, it is pinned, or it was opened in
    /// the last half hour. The site leaves the rest out already; this holds
    /// the line against an older server.
    func isListable(now: Date = Date()) -> Bool {
        if messageCount > 0 || pinned { return true }
        guard let created = createdAt.flatMap(parseTimestamp) else { return false }
        return now.timeIntervalSince(created) < 30 * 60
    }

    /// The one-line preview. A transcript's newlines would turn a two-line cell
    /// into a ten-line one.
    var oneLinePreview: String? {
        guard let preview else { return nil }
        let flat = preview
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return flat.isEmpty ? nil : flat
    }

    var isWhatsApp: Bool { source == "whatsapp" }

    /// A thread known only by its id — from Spotlight, or from a notification.
    ///
    /// The screen fetches the real row on appear and replaces the title; this
    /// exists so navigating does not have to wait for a round trip first.
    static func placeholder(id: String) -> Conversation {
        Conversation(
            id: id,
            title: nil,
            source: nil,
            pinned: false,
            messageCount: 0,
            modelProvider: nil,
            modelId: nil,
            preview: nil,
            createdAt: nil,
            updatedAt: nil
        )
    }
}

/// The thread list, cut into the spans a person remembers a conversation by.
///
/// One undifferentiated run of four hundred rows is a list you search, not
/// one you read. Today, Yesterday, the last week and the last month, then one
/// section per month — the shape every message app on the phone already uses.
/// The server orders by `updatedAt`, so this only draws the lines. PURE.
enum ThreadSections {
    struct Group: Identifiable, Equatable {
        let id: String
        let title: String
        let threads: [Conversation]
    }

    static func group(_ threads: [Conversation], now: Date = Date(), calendar: Calendar = .current) -> [Group] {
        var order: [String] = []
        var titles: [String: String] = [:]
        var buckets: [String: [Conversation]] = [:]
        let today = calendar.startOfDay(for: now)
        for thread in threads {
            let (key, title) = bucket(thread.updatedAt.flatMap(parseTimestamp), today: today, now: now, calendar: calendar)
            if buckets[key] == nil { order.append(key); titles[key] = title }
            buckets[key, default: []].append(thread)
        }
        return order.map { Group(id: $0, title: titles[$0] ?? $0, threads: buckets[$0] ?? []) }
    }

    private static func bucket(_ date: Date?, today: Date, now: Date, calendar: Calendar) -> (String, String) {
        guard let date else { return ("earlier", "Earlier") }
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        switch days {
        case ..<1: return ("today", "Today")
        case 1: return ("yesterday", "Yesterday")
        case 2..<7: return ("week", "Previous 7 days")
        case 7..<30: return ("month", "Previous 30 days")
        default:
            let parts = calendar.dateComponents([.year, .month], from: date)
            let sameYear = parts.year == calendar.component(.year, from: now)
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = Locale(identifier: "en_GB")
            formatter.dateFormat = sameYear ? "LLLL" : "LLLL yyyy"
            return ("m-\(parts.year ?? 0)-\(parts.month ?? 0)", formatter.string(from: date))
        }
    }
}

struct ConversationPage: Decodable {
    let conversations: [Conversation]
    let cursor: Cursor?
    let hasMore: Bool

    struct Cursor: Decodable, Hashable {
        let pinned: Bool
        let before: String
        let beforeId: String
    }
}

/// A tool step as the transcript shows it — what ran and whether it worked.
/// Arguments and results are deliberately not sent; they are the largest thing
/// in a turn's metadata and can carry file paths and query bodies.
struct ToolStep: Decodable, Hashable {
    let tool: String?
    let status: String?
    let summary: String?

    var failed: Bool { status == "error" }
}

struct ChatAttachment: Decodable, Hashable, Identifiable {
    let id: String
    let filename: String?
    let kind: String?
    let mimeType: String?
    let sizeBytes: Int?

    var isImage: Bool { kind == "image" || (mimeType ?? "").hasPrefix("image/") }
    var isAudio: Bool { kind == "audio" || (mimeType ?? "").hasPrefix("audio/") }
}

struct ChatMessage: Decodable, Identifiable, Hashable {
    let id: String
    let role: String
    var content: String
    let createdAt: String?
    let source: String?
    var toolSteps: [ToolStep]
    var attachments: [ChatAttachment]
    /// Charts, tables and diagrams the turn made, already reduced by the site.
    /// Optional, so a thread from an older server — and every fixture — still
    /// decodes: synthesised `Decodable` throws on a missing non-optional key.
    var artifacts: [ChatArtifact]?
    /// The files and research the turn cited.
    var sources: [ChatSource]?

    var isUser: Bool { role == "user" }

    /// A turn in flight, before the server has given it a real id.
    static func pending(id: String, role: String, content: String) -> ChatMessage {
        ChatMessage(
            id: id,
            role: role,
            content: content,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            source: "web",
            toolSteps: [],
            attachments: []
        )
    }
}

struct MessagePage: Decodable {
    let conversation: Thread
    let hasOlder: Bool
    let cursor: Cursor?
    let messages: [ChatMessage]

    struct Thread: Decodable {
        let id: String
        let title: String?
        let source: String?
    }

    struct Cursor: Decodable, Hashable {
        let before: String
        let beforeId: String
    }
}

/// What the assistant is doing right now, between the send and the first token.
struct TurnActivity: Hashable {
    var status: String?
    var thinking: String = ""
    var steps: [ToolStep] = []

    var isEmpty: Bool { status == nil && thinking.isEmpty && steps.isEmpty }
}

/// A turn that opened a gate this app cannot answer.
///
/// Chat can ask for a plan approval, a dangerous-command confirmation, a
/// clarification or a credential. All four are desk-shaped and out of scope for
/// the phone — but a turn that opens one and gets no answer HANGS, so the app
/// says so and offers the website rather than spinning forever.
struct BlockedTurn: Hashable {
    let kind: String
    let detail: String

    var sentence: String {
        switch kind {
        case "plan": return "This turn wants a plan approved."
        case "confirm": return "This turn is waiting on a confirmation."
        case "clarify": return "This turn asked a question back."
        case "secret_request": return "This turn needs a credential."
        case "approval": return "This turn wants to run something that needs approving."
        default: return "This turn needs an answer the app cannot give."
        }
    }
}
