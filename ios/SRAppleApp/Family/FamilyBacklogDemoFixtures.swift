import Foundation

// MARK: - Demo family backlog
//
// `-SRDemo` answers for `/api/native/family/backlog` and
// `/api/native/family/backlog/:id`. Synthetic throughout — the repository is
// public — with the demo's family (Sam is "me"). No pictures: a screenshot
// must not depend on somebody else's server. What is added or moved in a demo
// session is kept for that session only.

extension SRDemoFixtures {
    static func familyBacklogRoute(method: String, parts: [String], body: Data?, clock: DemoClock) -> String? {
        // parts: ["api", "native", "family", "backlog", ...]
        switch (method, parts.count) {
        case ("GET", 4):
            return FamilyBacklogDemo.shared.board(clock)
        case ("POST", 4):
            return FamilyBacklogDemo.shared.add(body, clock: clock)
        case ("PUT", 5) where parts[4] == "digest":
            return FamilyBacklogDemo.shared.digest(body)
        case ("PATCH", 5):
            return FamilyBacklogDemo.shared.act(on: parts[4], body: body, clock: clock)
        case ("POST", 6) where parts[5] == "reaction":
            return FamilyBacklogDemo.shared.react(on: parts[4], body: body)
        default:
            return nil
        }
    }
}

final class FamilyBacklogDemo: @unchecked Sendable {
    static let shared = FamilyBacklogDemo()

    private let lock = NSLock()
    private var added: [FamilyBacklogItem] = []
    /// id → status ("deleted" removes it), for seeded and added items alike.
    private var moved: [String: String] = [:]
    /// item id → Sam's emoji this session.
    private var mine: [String: String] = [:]
    private var digestOn = false
    private var count = 0

    func reset() {
        lock.lock(); defer { lock.unlock() }
        added = []
        moved = [:]
        mine = [:]
        digestOn = false
        count = 0
    }

    private func seeded(_ clock: SRDemoFixtures.DemoClock) -> [FamilyBacklogItem] {
        func item(_ id: String, _ kind: String, _ provider: String?, _ title: String, site: String?, url: String?,
                  by: String, ago: Double, note: String? = nil, for forId: String? = nil) -> FamilyBacklogItem {
            FamilyBacklogItem(id: id, kind: kind, url: url, provider: provider, title: title, siteName: site,
                              thumbnailUrl: nil, note: note, forId: forId, addedById: by, status: "new",
                              doneById: nil, doneAt: nil, createdAt: clock.iso(minutesAgo: ago))
        }
        return [
            item("demo-bl-1", "video", "tiktok", "How to make a paper plane that flies 30 metres", site: "TikTok",
                 url: "https://www.tiktok.com/@example/video/1", by: "f_kit", ago: 35, for: "f_sam"),
            {
                var i = item("demo-bl-2", "video", "youtube", "The deepest hole we have ever dug", site: "YouTube",
                             url: "https://www.youtube.com/watch?v=aaaaaaaaaaa", by: "f_alex", ago: 300, note: "Film night?")
                i.reactions = [FamilyBacklogReaction(emoji: "👍", by: ["f_robin", "f_kit"])]
                return i
            }(),
            item("demo-bl-3", "idea", nil, "Go to the coast and find fossils", site: nil, url: nil,
                 by: "f_robin", ago: 1_500),
            item("demo-bl-4", "page", "web", "Ten walks with a tea shop at the end", site: "example.com",
                 url: "https://example.com/walks", by: "f_sam", ago: 2_900, note: "For half term"),
        ]
    }

    private func finished(_ clock: SRDemoFixtures.DemoClock) -> [FamilyBacklogItem] {
        [
            FamilyBacklogItem(id: "demo-bl-9", kind: "video", url: "https://www.youtube.com/watch?v=bbbbbbbbbbb",
                              provider: "youtube", title: "Building a marble run out of cardboard", siteName: "YouTube",
                              thumbnailUrl: nil, note: nil, forId: nil, addedById: "f_kit", status: "done",
                              doneById: "f_alex", doneAt: clock.iso(minutesAgo: 2_000), createdAt: clock.iso(minutesAgo: 6_000)),
        ]
    }

    func board(_ clock: SRDemoFixtures.DemoClock) -> String? {
        lock.lock(); defer { lock.unlock() }
        let all = (added + seeded(clock) + finished(clock)).compactMap { item -> FamilyBacklogItem? in
            var item = item
            if let emoji = mine[item.id] {
                var list = (item.reactions ?? []).map { r in FamilyBacklogReaction(emoji: r.emoji, by: r.by.filter { $0 != "f_sam" }) }
                if let i = list.firstIndex(where: { $0.emoji == emoji }) { list[i].by.append("f_sam") } else { list.append(.init(emoji: emoji, by: ["f_sam"])) }
                item.reactions = list.filter { !$0.by.isEmpty }
            }
            guard let status = moved[item.id] else { return item }
            if status == "deleted" { return nil }
            if status == "done", moved[item.id + ":task"] != nil { item.taskId = "demo-task-from-\(item.id)" }
            item.status = status
            if status == "new" { item.doneById = nil; item.doneAt = nil } else if item.doneById == nil {
                item.doneById = "f_sam"; item.doneAt = clock.iso(minutesAgo: 0)
            }
            return item
        }
        let board = FamilyBacklogBoard(
            me: FamilyTaskMe(id: "f_sam", parent: true),
            people: [
                .init(id: "f_sam", name: "Sam"), .init(id: "f_alex", name: "Alex"),
                .init(id: "f_robin", name: "Robin"), .init(id: "f_kit", name: "Kit"),
            ],
            items: all.filter { $0.status == "new" },
            finished: all.filter { $0.status != "new" },
            quickReactions: FamilyMessages.reactions,
            digest: digestOn
        )
        return encode(board)
    }

    func add(_ body: Data?, clock: SRDemoFixtures.DemoClock) -> String? {
        guard let body, let share = try? JSONDecoder().decode(FamilyBacklogShare.self, from: body) else { return nil }
        let text = (share.text ?? share.url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        lock.lock(); defer { lock.unlock() }
        count += 1
        let link = share.url.flatMap(URL.init(string:)) ?? FamilyBacklogText.firstLink(in: text)
        let item = FamilyBacklogItem(
            id: "demo-bl-new-\(count)", kind: link == nil ? "idea" : "page", url: link?.absoluteString,
            provider: link == nil ? nil : "web", title: link == nil ? text : nil, siteName: nil, thumbnailUrl: nil,
            note: share.note, forId: share.forId, addedById: "f_sam", status: "new", doneById: nil, doneAt: nil,
            createdAt: clock.iso(minutesAgo: 0)
        )
        added.insert(item, at: 0)
        return encode(["duplicate": false])
    }

    func act(on id: String, body: Data?, clock: SRDemoFixtures.DemoClock) -> String? {
        guard let body, let object = try? JSONSerialization.jsonObject(with: body) as? [String: String],
              let action = object["action"].flatMap(FamilyBacklogAction.init(rawValue:)) else { return nil }
        lock.lock(); defer { lock.unlock() }
        switch action {
        case .done: moved[id] = "done"
        case .dismiss: moved[id] = "dismissed"
        case .reopen: moved[id] = "new"
        case .delete: moved[id] = "deleted"
        case .toTask:
            moved[id] = "done"
            moved[id + ":task"] = "yes"
        }
        return "{}"
    }

    func react(on id: String, body: Data?) -> String? {
        guard let body, let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        lock.lock(); defer { lock.unlock() }
        mine[id] = object["emoji"] as? String
        return "{}"
    }

    func digest(_ body: Data?) -> String? {
        guard let body, let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let on = object["on"] as? Bool else { return nil }
        lock.lock(); defer { lock.unlock() }
        digestOn = on
        return on ? #"{"digest":true}"# : #"{"digest":false}"#
    }

    private func encode<T: Encodable>(_ value: T) -> String? {
        (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) }
    }
}
