import Foundation

/// A thread in the ledger.
struct Conversation: Decodable, Identifiable, Hashable {
    let id: String
    let title: String?
    let source: String?
    let pinned: Bool
    let messageCount: Int
    let modelProvider: String?
    let modelId: String?
    /// Already clipped to 200 characters server-side.
    let preview: String?
    let createdAt: String?
    let updatedAt: String?

    var displayTitle: String {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
        return "Untitled thread"
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
}

struct ChatMessage: Decodable, Identifiable, Hashable {
    let id: String
    let role: String
    var content: String
    let createdAt: String?
    let source: String?
    var toolSteps: [ToolStep]
    var attachments: [ChatAttachment]

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
