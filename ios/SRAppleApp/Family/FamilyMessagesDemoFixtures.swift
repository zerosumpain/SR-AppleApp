import Foundation

// MARK: - Demo msg family
//
// `-SRDemo` answers for `/api/native/family/messages` and
// `/api/native/family/messages/:id/replies`. Synthetic throughout — the
// repository is public — with the demo's family (Sam is "me"). What is sent
// or replied in a demo session is kept for that session only.

extension SRDemoFixtures {
    static func familyMessagesRoute(method: String, parts: [String], body: Data?, clock: DemoClock) -> String? {
        // parts: ["api", "native", "family", "messages", ...]
        switch (method, parts.count) {
        case ("GET", 4):
            return FamilyMessagesDemo.shared.feed(clock)
        case ("POST", 4):
            guard let text = FamilyMessagesDemo.body(body) else { return nil }
            return FamilyMessagesDemo.shared.send(text, clock: clock)
        case ("POST", 6) where parts[5] == "replies":
            guard let text = FamilyMessagesDemo.body(body) else { return nil }
            return FamilyMessagesDemo.shared.reply(text, to: parts[4], clock: clock)
        default:
            return nil
        }
    }
}

final class FamilyMessagesDemo: @unchecked Sendable {
    static let shared = FamilyMessagesDemo()

    private let lock = NSLock()
    /// Sent this session, newest first, as minutes-ago-free records.
    private var sent: [FamilyMessage] = []
    private var replies: [String: [FamilyMessageReply]] = [:]
    private var count = 0

    func reset() {
        lock.lock(); defer { lock.unlock() }
        sent = []
        replies = [:]
        count = 0
    }

    static func body(_ data: Data?) -> String? {
        guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = object["body"] as? String else { return nil }
        return FamilyMessages.sendable(text)
    }

    private func seeded(_ clock: SRDemoFixtures.DemoClock) -> [FamilyMessage] {
        func r(_ id: String, _ who: String, _ name: String, _ body: String, _ ago: Double, mine: Bool = false) -> FamilyMessageReply {
            FamilyMessageReply(id: id, fromId: who, fromName: name, mine: mine, body: body,
                               reaction: FamilyMessages.reactions.contains(body), at: clock.iso(minutesAgo: ago))
        }
        return [
            FamilyMessage(id: "demo-msg-2", fromId: "f_alex", fromName: "Alex", mine: false,
                          body: "Training ran late — home by 7. Save me some dinner?",
                          at: clock.iso(minutesAgo: 25), pushed: 3, recipients: 3,
                          replies: [r("demo-rep-3", "f_robin", "Robin", "👍", 20)]),
            FamilyMessage(id: "demo-msg-1", fromId: "f_sam", fromName: "Sam", mine: true,
                          body: "Pizza tonight? Ordering at six.",
                          at: clock.iso(minutesAgo: 140), pushed: 3, recipients: 3,
                          replies: [
                              r("demo-rep-1", "f_alex", "Alex", "❤️", 130),
                              r("demo-rep-2", "f_robin", "Robin", "Pepperoni please!", 120),
                              r("demo-rep-4", "f_kit", "Kit", "👍", 110),
                          ]),
        ]
    }

    func feed(_ clock: SRDemoFixtures.DemoClock) -> String? {
        lock.lock(); defer { lock.unlock() }
        let messages = (sent + seeded(clock)).map { m -> FamilyMessage in
            var m = m
            m.replies += replies[m.id] ?? []
            return m
        }
        return encode(FamilyMessagesFeed(me: .init(id: "f_sam"), messages: messages))
    }

    func send(_ text: String, clock: SRDemoFixtures.DemoClock) -> String? {
        lock.lock(); defer { lock.unlock() }
        count += 1
        let message = FamilyMessage(id: "demo-msg-new-\(count)", fromId: "f_sam", fromName: "Sam", mine: true,
                                    body: text, at: clock.iso(minutesAgo: 0), pushed: 3, recipients: 3)
        sent.insert(message, at: 0)
        return #"{"pushed":3,"recipients":3}"#
    }

    func reply(_ text: String, to id: String, clock: SRDemoFixtures.DemoClock) -> String? {
        lock.lock(); defer { lock.unlock() }
        count += 1
        let reply = FamilyMessageReply(id: "demo-rep-new-\(count)", fromId: "f_sam", fromName: "Sam", mine: true, body: text,
                                       reaction: FamilyMessages.reactions.contains(text), at: clock.iso(minutesAgo: 0))
        replies[id, default: []].append(reply)
        return #"{"pushed":1}"#
    }

    private func encode<T: Encodable>(_ value: T) -> String? {
        (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) }
    }
}
