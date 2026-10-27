import Foundation

// The family backlog in the app: links, videos and ideas anyone in the
// family shared ("Share → SR", or + on the page), for the family to watch,
// read or do together. Wire shapes and the share path are in
// FamilyBacklogShared.swift, which the share extension compiles too.

/// The page's filter chips.
enum FamilyBacklogShelf: String, CaseIterable, Identifiable {
    case all = "All", watch = "Watch", read = "Read", ideas = "Ideas", done = "Done"
    var id: String { rawValue }

    func items(_ board: FamilyBacklogBoard) -> [FamilyBacklogItem] {
        switch self {
        case .all: return board.items
        case .watch: return board.items.filter { $0.kind == "video" }
        case .read: return board.items.filter { $0.kind == "page" }
        case .ideas: return board.items.filter { $0.kind == "idea" }
        case .done: return board.finished
        }
    }

    var empty: String {
        switch self {
        case .all: return "Nothing on the list. Share a link, a video or an idea to SR from any app, or add one with +."
        case .watch: return "No videos waiting. Share one from YouTube or TikTok with Share → SR."
        case .read: return "No pages waiting."
        case .ideas: return "No ideas yet. Add one with +."
        case .done: return "Nothing done in the last 30 days."
        }
    }
}

enum FamilyBacklogRules {
    /// "Sam · 2d", "You · 5m", with "for Kit" when it was meant for someone.
    static func byline(_ item: FamilyBacklogItem, _ board: FamilyBacklogBoard, now: Date = Date()) -> String {
        let name = { (id: String) -> String in
            id == board.me.id ? "You" : board.people.first { $0.id == id }?.name ?? "Someone"
        }
        var parts = ["\(name(item.addedById)) · \(FamilyMessages.when(item.createdAt, now: now))"]
        if let forId = item.forId {
            parts.append(forId == board.me.id ? "for you" : "for \(name(forId))")
        }
        if item.status != "new", let by = item.doneById {
            parts.append(item.status == "dismissed" ? "\(name(by)) passed" : "\(name(by)) did it")
        }
        return parts.joined(separator: " · ")
    }

    /// Whoever shared it, or a parent, may delete it — as the site decides.
    static func mayDelete(_ item: FamilyBacklogItem, _ board: FamilyBacklogBoard) -> Bool {
        board.me.parent || item.addedById == board.me.id
    }

    /// Things shared for this person that are still waiting.
    static func forMe(_ board: FamilyBacklogBoard) -> Int {
        board.items.filter { $0.forId == board.me.id }.count
    }

    /// What More's card says under its title.
    static func status(_ board: FamilyBacklogBoard) -> String? {
        let mine = forMe(board)
        if mine > 0 { return "\(mine) for you" }
        return board.items.isEmpty ? nil : "\(board.items.count) on the list"
    }

    /// Tonight's pick: a video if there is one, else anything on the list;
    /// never the one just shown while there is another to show.
    static func pick(_ board: FamilyBacklogBoard, avoiding last: String? = nil) -> FamilyBacklogItem? {
        let videos = board.items.filter { $0.kind == "video" }
        let pool = videos.isEmpty ? board.items : videos
        let fresh = pool.count > 1 ? pool.filter { $0.id != last } : pool
        return fresh.randomElement()
    }

    /// The emoji this person chose on an item, if any.
    static func myReaction(_ item: FamilyBacklogItem, _ board: FamilyBacklogBoard) -> String? {
        item.reactions?.first { $0.by.contains(board.me.id) }?.emoji
    }

    /// Who chose an emoji, by name, for its accessibility label.
    static func names(_ reaction: FamilyBacklogReaction, _ board: FamilyBacklogBoard) -> String {
        reaction.by.map { id in id == board.me.id ? "you" : board.people.first { $0.id == id }?.name ?? "someone" }
            .joined(separator: ", ")
    }

    /// Today's card: what is for you, then how many are waiting.
    static func todayLine(_ board: FamilyBacklogBoard) -> (forYou: Int, waiting: Int, newest: [FamilyBacklogItem]) {
        (forMe(board), board.items.count, Array(board.items.prefix(2)))
    }

    /// What "Play all on TV" takes from a shelf: things with a link, in list
    /// order. Pages come too — the sheet offers them to mirror — but ideas
    /// have nothing to show.
    static func castable(_ items: [FamilyBacklogItem]) -> [FamilyBacklogItem] {
        items.filter { $0.url != nil && $0.kind != "idea" }
    }

    static func symbol(_ item: FamilyBacklogItem) -> String {
        switch (item.kind, item.provider) {
        case ("idea", _): return "lightbulb"
        case ("video", "tiktok"): return "music.note"
        case ("video", _): return "play.rectangle"
        default: return "doc.richtext"
        }
    }
}

/// One "Play on TV" sheet's worth of items.
struct BacklogCastList: Identifiable {
    let id = UUID()
    let items: [FamilyBacklogItem]
}

// MARK: - Store

@MainActor
final class FamilyBacklogStore: ObservableObject {
    static let shared = FamilyBacklogStore()

    @Published private(set) var board: FamilyBacklogBoard?
    @Published private(set) var loading = false
    @Published private(set) var loaded = false
    /// The items with an action on its way, and "new" while one is being
    /// added. One per item, not one for the list: a second item's swipe or
    /// reaction was dropped without a word while the first was still saving.
    @Published private(set) var busy: Set<String> = []
    @Published var message: String?
    /// Asked to read while a read was running: that one goes round again, so
    /// an action that lands during another's reload is still shown.
    private var loadAgain = false

    func load() async {
        guard SiteClient.shared.isPaired else { return }
        guard !loading else { loadAgain = true; return }
        loading = true
        defer { loading = false; loaded = true }
        await drainQueue()
        repeat {
            loadAgain = false
            do {
                let fetched: FamilyBacklogBoard = try await SiteClient.shared.send("api/native/family/backlog")
                board = fetched
                message = nil
            } catch is CancellationError {
                return
            } catch {
                if (error as? URLError)?.code == .cancelled { return }
                if let failure = error as? SiteError, failure.status == 401 || failure.status == 403 { board = nil }
                message = board == nil ? Self.sentence(for: error) : nil
            }
        } while loadAgain
    }

    /// Add a link or an idea from the page. Nil when it went; otherwise the
    /// sentence for the sheet.
    func add(_ share: FamilyBacklogShare) async -> String? {
        guard !busy.contains("new") else { return "Saving already…" }
        busy.insert("new")
        defer { busy.remove("new") }
        do {
            try await SiteClient.shared.post("api/native/family/backlog", body: try JSONEncoder().encode(share))
            SRHaptic.ok()
            await load()
            return nil
        } catch {
            return Self.sentence(for: error)
        }
    }

    @discardableResult
    func act(_ action: FamilyBacklogAction, on item: FamilyBacklogItem) async -> Bool {
        guard !busy.contains(item.id) else { return false }
        busy.insert(item.id)
        defer { busy.remove(item.id) }
        do {
            let body = try JSONEncoder().encode(["action": action.rawValue])
            try await SiteClient.shared.call("api/native/family/backlog/\(item.id)", method: "PATCH", body: body)
            if action == .delete { SRHaptic.tap() } else { SRHaptic.ok() }
            message = nil
            await load()
            // It is on the task list now; the list should say so when opened.
            if action == .toTask { await FamilyTasksStore.shared.load() }
            return true
        } catch {
            SRHaptic.bad()
            message = Self.sentence(for: error)
            await load()
            return false
        }
    }

    /// An emoji on an item — the same one again takes it back.
    func react(_ emoji: String, on item: FamilyBacklogItem) async {
        guard !busy.contains(item.id), let board else { return }
        busy.insert(item.id)
        defer { busy.remove(item.id) }
        let mine = FamilyBacklogRules.myReaction(item, board)
        let body: [String: String?] = ["emoji": mine == emoji ? nil : emoji]
        do {
            try await SiteClient.shared.post("api/native/family/backlog/\(item.id)/reaction", body: try JSONEncoder().encode(body))
            SRHaptic.tap()
            await load()
        } catch {
            SRHaptic.bad()
            message = Self.sentence(for: error)
        }
    }

    /// The evening round-up, on or off. False when the site refused. Moved
    /// at once and put back if refused, as the switch promises: set only
    /// once the site answered, it sprang back under the thumb first.
    @discardableResult
    func setDigest(_ on: Bool) async -> Bool {
        let was = board?.digest
        board?.digest = on
        do {
            try await SiteClient.shared.call("api/native/family/backlog/digest", method: "PUT", body: try JSONEncoder().encode(["on": on]))
            message = nil
            return true
        } catch {
            board?.digest = was ?? !on
            message = Self.sentence(for: error)
            return false
        }
    }

    /// Send what the share extension kept because it could not reach the
    /// site. Kept again only if the site still cannot be reached; a share
    /// the site refused is dropped — sending it again would be refused again.
    func drainQueue() async {
        guard !SRDemo.isOn, AccessStore.shared.viewingAs == nil else { return }
        let pending = FamilyBacklogQueue.all()
        guard !pending.isEmpty else { return }
        var left: [FamilyBacklogQueue.Pending] = []
        for entry in pending {
            if case .unreachable = await FamilyBacklogPost.send(entry.share) { left.append(entry) }
        }
        FamilyBacklogQueue.replace(left)
    }

    func reset() {
        board = nil
        loaded = false
        message = nil
    }

    static func sentence(for error: Error) -> String {
        switch error as? SiteError {
        case .status(let code, let text)?:
            switch code {
            case 403 where AccessStore.shared.viewingAs != nil: return "View as is look-only."
            case 403: return text.isEmpty ? "The backlog is for the family." : text
            case 404: return "That has gone from the list."
            case 409: return "Someone got there first — the list is up to date now."
            default: return text
            }
        case .invalid(let text, _)?:
            return text
        default:
            return error.localizedDescription
        }
    }
}
