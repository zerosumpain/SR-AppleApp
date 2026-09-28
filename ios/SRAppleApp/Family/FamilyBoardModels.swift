import Foundation

// The family step board and the family task list: the wire shapes, and every
// rule about them as a pure function.
//
// SHARED with the widget extension (`SRAppleLive`, see watch.yml), so nothing
// here may reach for the app — no `SR`, no `SiteClient`, no `AccessStore`.
// Foundation only.
//
// The contract is SR-Main's `GET /api/native/family/steps` and
// `GET /api/native/family/tasks` (spec: family steps leaderboard + family task
// list, 2026-09-28). Every decoder is lenient: a missing or odd field costs
// that field, never the board — Swift's synthesised `Codable` throws on a
// missing non-optional key.

// MARK: - Where a notification, a widget or a link goes

/// The two family pages. `sr://family/steps` and `sr://family/tasks` open them
/// — from a push (`userInfo.url`, or the category), a Home Screen widget, or
/// any link.
enum FamilyPage: String, Hashable, CaseIterable {
    case steps, tasks

    var url: URL { URL(string: "sr://family/\(rawValue)")! }

    /// `sr://family/steps` → `.steps`. Anything else is not ours.
    static func from(url: URL) -> FamilyPage? {
        guard url.scheme?.lowercased() == "sr", url.host?.lowercased() == "family" else { return nil }
        let name = url.pathComponents.first { $0 != "/" }?.lowercased() ?? ""
        return FamilyPage(rawValue: name)
    }

    /// A notification's payload: `url` first (what the site sends), then the
    /// category — `family-steps` / `family-tasks`, or `family` with a `page`.
    static func from(category: String, userInfo: [AnyHashable: Any]) -> FamilyPage? {
        if let raw = userInfo["url"] as? String, let url = URL(string: raw), let page = from(url: url) {
            return page
        }
        switch category {
        case "family-steps", "steps": return .steps
        case "family-tasks", "tasks": return .tasks
        case "family":
            return (userInfo["page"] as? String).flatMap { FamilyPage(rawValue: $0) }
        default: return nil
        }
    }
}

// MARK: - Steps

/// Today's family step board. One row per person on it; ranks are 1…n with
/// ties sharing a rank; `me` marks the caller.
struct FamilyStepsBoard: Codable, Equatable {
    var day: String
    var updatedAt: String?
    var people: [FamilyStepsPerson]
    var yesterday: FamilyStepsYesterday?

    init(day: String, updatedAt: String? = nil, people: [FamilyStepsPerson], yesterday: FamilyStepsYesterday? = nil) {
        self.day = day
        self.updatedAt = updatedAt
        self.people = people
        self.yesterday = yesterday
    }

    private enum CodingKeys: String, CodingKey { case day, updatedAt, people, yesterday }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = (try? c.decodeIfPresent(String.self, forKey: .day)) ?? ""
        updatedAt = (try? c.decodeIfPresent(String.self, forKey: .updatedAt)) ?? nil
        people = (try? c.decodeIfPresent([FamilyStepsPerson].self, forKey: .people)) ?? []
        yesterday = (try? c.decodeIfPresent(FamilyStepsYesterday.self, forKey: .yesterday)) ?? nil
    }

    var mine: FamilyStepsPerson? { people.first { $0.me } }
}

struct FamilyStepsPerson: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var name: String
    var steps: Int
    var rank: Int
    var me: Bool
    var updatedAt: String?
    /// Set on the phone, never sent: this row shows this iPhone's own Apple
    /// Health count, which was higher than the board's.
    var live = false

    init(id: String, name: String, steps: Int, rank: Int, me: Bool = false, updatedAt: String? = nil, live: Bool = false) {
        self.id = id; self.name = name; self.steps = steps; self.rank = rank
        self.me = me; self.updatedAt = updatedAt; self.live = live
    }

    private enum CodingKeys: String, CodingKey { case id, name, steps, rank, me, updatedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        steps = max(0, (try? c.decodeIfPresent(Int.self, forKey: .steps)) ?? 0)
        rank = (try? c.decodeIfPresent(Int.self, forKey: .rank)) ?? 0
        me = (try? c.decodeIfPresent(Bool.self, forKey: .me)) ?? false
        updatedAt = (try? c.decodeIfPresent(String.self, forKey: .updatedAt)) ?? nil
    }
}

struct FamilyStepsYesterday: Codable, Equatable {
    let leaderName: String
    let steps: Int
}

/// The step board's rules.
enum FamilySteps {
    /// The board's clock: the site resets it on the London day.
    static let boardZone = TimeZone(identifier: "Europe/London")!

    /// "2026-09-28" for `date` in `zone`.
    static func ymd(_ date: Date, in zone: TimeZone = boardZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Whether a board is today's — a widget holding yesterday's says so.
    static func isToday(_ board: FamilyStepsBoard, now: Date = Date()) -> Bool {
        board.day == ymd(now)
    }

    /// Order by steps, most first, and give competition ranks (1, 1, 3). Ties
    /// keep the order they came in, which is the site's "reached it first".
    static func ranked(_ people: [FamilyStepsPerson]) -> [FamilyStepsPerson] {
        let sorted = people.enumerated().sorted { a, b in
            a.element.steps != b.element.steps ? a.element.steps > b.element.steps : a.offset < b.offset
        }.map(\.element)
        var out: [FamilyStepsPerson] = []
        for (index, person) in sorted.enumerated() {
            var next = person
            if let previous = out.last, previous.steps == person.steps {
                next.rank = previous.rank
            } else {
                next.rank = index + 1
            }
            out.append(next)
        }
        return out
    }

    /// The board with this phone's own Apple Health count in the caller's
    /// row, when that is higher than the board's — the board is refreshed
    /// every fifteen minutes, the phone's count is now. Re-ranked, and the row
    /// marked `live`. A lower count changes nothing: the board may have the
    /// Watch's steps the phone has not seen yet.
    static func withLive(_ board: FamilyStepsBoard, liveSteps: Int?) -> FamilyStepsBoard {
        guard let liveSteps, let index = board.people.firstIndex(where: { $0.me }),
              liveSteps > board.people[index].steps else { return board }
        var next = board
        next.people[index].steps = liveSteps
        next.people[index].live = true
        next.people = ranked(next.people)
        return next
    }

    /// 1st, 2nd, 3rd, 4th … 11th, 12th, 13th … 21st.
    static func ordinal(_ n: Int) -> String {
        let tens = (n / 10) % 10
        let suffix: String
        if tens == 1 {
            suffix = "th"
        } else {
            switch n % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }

    /// 12,300 — grouped the British way whatever the phone's region.
    static func figure(_ n: Int) -> String {
        let format = NumberFormatter()
        format.numberStyle = .decimal
        format.locale = Locale(identifier: "en_GB")
        return format.string(from: NSNumber(value: n)) ?? String(n)
    }

    /// Whether somebody else shares the caller's rank.
    static func tied(_ board: FamilyStepsBoard) -> Bool {
        guard let mine = board.mine else { return false }
        return board.people.contains { !$0.me && $0.rank == mine.rank }
    }

    /// "2nd of 5", "Joint 1st of 3", or nil when the caller is not on it.
    static func place(_ board: FamilyStepsBoard) -> String? {
        guard let mine = board.mine else { return nil }
        let place = ordinal(mine.rank)
        return "\(tied(board) ? "Joint \(place)" : place) of \(board.people.count)"
    }

    /// The race, from the caller's seat: "1,900 ahead of Sam", "1,020 behind
    /// Katie", "Level with Sam". Nil alone on the board.
    static func gap(_ board: FamilyStepsBoard) -> String? {
        guard let mine = board.mine, board.people.count > 1 else { return nil }
        let others = board.people.filter { !$0.me }
        if let level = others.first(where: { $0.steps == mine.steps }) {
            return "Level with \(level.name)"
        }
        if mine.rank == 1, let second = others.max(by: { $0.steps < $1.steps }) {
            return "\(figure(mine.steps - second.steps)) ahead of \(second.name)"
        }
        guard let leader = others.max(by: { $0.steps < $1.steps }) else { return nil }
        return "\(figure(leader.steps - mine.steps)) behind \(leader.name)"
    }

    /// The top of the board, for a card or a widget.
    static func top(_ board: FamilyStepsBoard, _ count: Int = 3) -> [FamilyStepsPerson] {
        Array(ranked(board.people).prefix(count))
    }

    /// "Yesterday Sam won with 14,210 steps."
    static func yesterdayLine(_ board: FamilyStepsBoard) -> String? {
        guard let y = board.yesterday, !y.leaderName.isEmpty else { return nil }
        return "Yesterday \(y.leaderName) won with \(figure(y.steps)) steps."
    }
}

// MARK: - Tasks

/// What a finished task earns.
enum FamilyRewardKind: String, CaseIterable, Identifiable, Hashable {
    case cash
    case dayOut = "day_out"
    case gameTime = "game_time"
    case lunchOut = "lunch_out"
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cash: return "Cash"
        case .dayOut: return "Day out"
        case .gameTime: return "Game time"
        case .lunchOut: return "Lunch out"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .cash: return "sterlingsign.circle"
        case .dayOut: return "map"
        case .gameTime: return "gamecontroller"
        case .lunchOut: return "fork.knife"
        case .other: return "gift"
        }
    }
}

struct FamilyReward: Codable, Hashable {
    var kind: String
    var pence: Int?
    var note: String?
    var paidAt: String?

    init(kind: String, pence: Int? = nil, note: String? = nil, paidAt: String? = nil) {
        self.kind = kind; self.pence = pence; self.note = note; self.paidAt = paidAt
    }

    private enum CodingKeys: String, CodingKey { case kind, pence, note, paidAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "other"
        pence = (try? c.decodeIfPresent(Int.self, forKey: .pence)) ?? nil
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? nil
        paidAt = (try? c.decodeIfPresent(String.self, forKey: .paidAt)) ?? nil
    }

    var kindValue: FamilyRewardKind? { FamilyRewardKind(rawValue: kind) }

    /// "£5", "Day out", "Day out · £10", "Game time · an hour on Saturday".
    var label: String {
        let money = pence.flatMap { $0 > 0 ? FamilyTaskRules.money($0) : nil }
        if kindValue == .cash {
            return [money ?? "Cash", note].compactMap { $0 }.joined(separator: " · ")
        }
        let name = kindValue?.label ?? "Reward"
        return [name, money, note].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var paid: Bool { paidAt != nil }
}

struct FamilyTask: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var notes: String?
    /// "YYYY-MM-DD".
    var deadline: String?
    var assignee: String?
    var createdBy: String
    /// `open`, `done` (awaiting a parent), `confirmed`, `deleted`.
    var status: String
    var doneBy: String?
    var doneAt: String?
    var sentBackNote: String?
    var confirmedBy: String?
    var confirmedAt: String?
    var reward: FamilyReward?
    var createdAt: String

    init(id: String, title: String, notes: String? = nil, deadline: String? = nil, assignee: String? = nil,
         createdBy: String, status: String = "open", doneBy: String? = nil, doneAt: String? = nil,
         sentBackNote: String? = nil, confirmedBy: String? = nil, confirmedAt: String? = nil,
         reward: FamilyReward? = nil, createdAt: String = "") {
        self.id = id; self.title = title; self.notes = notes; self.deadline = deadline
        self.assignee = assignee; self.createdBy = createdBy; self.status = status
        self.doneBy = doneBy; self.doneAt = doneAt; self.sentBackNote = sentBackNote
        self.confirmedBy = confirmedBy; self.confirmedAt = confirmedAt
        self.reward = reward; self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, notes, deadline, assignee, createdBy, status, doneBy, doneAt
        case sentBackNote, confirmedBy, confirmedAt, reward, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil }
        id = text(.id) ?? UUID().uuidString
        title = text(.title) ?? ""
        notes = text(.notes)
        deadline = text(.deadline)
        assignee = text(.assignee)
        createdBy = text(.createdBy) ?? ""
        status = text(.status) ?? "open"
        doneBy = text(.doneBy)
        doneAt = text(.doneAt)
        sentBackNote = text(.sentBackNote)
        confirmedBy = text(.confirmedBy)
        confirmedAt = text(.confirmedAt)
        reward = (try? c.decodeIfPresent(FamilyReward.self, forKey: .reward)) ?? nil
        createdAt = text(.createdAt) ?? ""
    }

    var isOpen: Bool { status == "open" }
    /// Marked done, waiting for a parent to confirm or send it back.
    var isAwaiting: Bool { status == "done" }
    var isConfirmed: Bool { status == "confirmed" }
}

struct FamilyTaskPerson: Codable, Hashable, Identifiable {
    let id: String
    let name: String
}

struct FamilyTaskMe: Codable, Equatable {
    var id: String
    var parent: Bool

    private enum CodingKeys: String, CodingKey { case id, parent }

    init(id: String, parent: Bool) { self.id = id; self.parent = parent }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        parent = (try? c.decodeIfPresent(Bool.self, forKey: .parent)) ?? false
    }
}

struct FamilyOwed: Codable, Equatable {
    var totalPence: Int
    var items: [FamilyTask]

    private enum CodingKeys: String, CodingKey { case totalPence, items }

    init(totalPence: Int, items: [FamilyTask]) { self.totalPence = totalPence; self.items = items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalPence = (try? c.decodeIfPresent(Int.self, forKey: .totalPence)) ?? 0
        items = (try? c.decodeIfPresent([FamilyTask].self, forKey: .items)) ?? []
    }
}

/// `GET /api/native/family/tasks`.
struct FamilyTasksBoard: Codable, Equatable {
    var me: FamilyTaskMe
    var people: [FamilyTaskPerson]
    var open: [FamilyTask]
    var completed: [FamilyTask]
    var owed: FamilyOwed

    init(me: FamilyTaskMe, people: [FamilyTaskPerson], open: [FamilyTask], completed: [FamilyTask], owed: FamilyOwed) {
        self.me = me; self.people = people; self.open = open; self.completed = completed; self.owed = owed
    }

    private enum CodingKeys: String, CodingKey { case me, people, open, completed, owed }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        me = (try? c.decodeIfPresent(FamilyTaskMe.self, forKey: .me)) ?? FamilyTaskMe(id: "", parent: false)
        people = (try? c.decodeIfPresent([FamilyTaskPerson].self, forKey: .people)) ?? []
        open = (try? c.decodeIfPresent([FamilyTask].self, forKey: .open)) ?? []
        completed = (try? c.decodeIfPresent([FamilyTask].self, forKey: .completed)) ?? []
        owed = (try? c.decodeIfPresent(FamilyOwed.self, forKey: .owed)) ?? FamilyOwed(totalPence: 0, items: [])
    }
}

/// `PATCH /api/native/family/tasks/[id]` — `{ action, note? }`.
enum FamilyTaskAction: String, CaseIterable, Hashable {
    case done, undo, confirm
    case sendBack = "send_back"
    case paid, delete

    var label: String {
        switch self {
        case .done: return "Done"
        case .undo: return "Not done"
        case .confirm: return "Confirm"
        case .sendBack: return "Send back"
        case .paid: return "Mark paid"
        case .delete: return "Delete"
        }
    }

    var icon: String {
        switch self {
        case .done: return "checkmark"
        case .undo: return "arrow.uturn.backward"
        case .confirm: return "checkmark.seal"
        case .sendBack: return "arrow.uturn.left"
        case .paid: return "sterlingsign"
        case .delete: return "trash"
        }
    }
}

struct FamilyTaskActionBody: Encodable, Equatable {
    let action: String
    var note: String? = nil
}

struct FamilyTaskRewardBody: Encodable, Equatable {
    let kind: String
    var pence: Int? = nil
    var note: String? = nil
}

/// `POST /api/native/family/tasks`. Nil fields are left out of the JSON.
struct FamilyTaskCreateBody: Encodable, Equatable {
    let title: String
    var notes: String? = nil
    var deadline: String? = nil
    var assigneeId: String? = nil
    var reward: FamilyTaskRewardBody? = nil
}

/// The add sheet's fields, and the rules the site will hold them to — said
/// here first so the sheet can say them before a round trip does.
struct FamilyTaskDraft: Equatable {
    var title = ""
    var notes = ""
    var hasDeadline = false
    var deadline = Date()
    /// Nil = anyone.
    var assigneeId: String? = nil
    var hasReward = false
    var kind: FamilyRewardKind = .cash
    var pounds = ""
    var rewardNote = ""

    static let titleLimit = 120
    static let notesLimit = 1000
    static let rewardNoteLimit = 80
    /// £1,000, in pence.
    static let penceLimit = 100_000

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The sentence that stops Save, or nil when it can go.
    var problem: String? {
        if trimmedTitle.isEmpty { return "Give the task a title." }
        if trimmedTitle.count > Self.titleLimit { return "Keep the title under \(Self.titleLimit) characters." }
        if notes.count > Self.notesLimit { return "Keep the notes under \(Self.notesLimit) characters." }
        guard hasReward else { return nil }
        let typed = pounds.trimmingCharacters(in: .whitespaces)
        let pence = FamilyTaskRules.pence(from: typed)
        if !typed.isEmpty && pence == nil { return "That amount isn't a sum of money." }
        if kind == .cash && (pence ?? 0) <= 0 { return "A cash reward needs an amount." }
        if let pence, pence > Self.penceLimit { return "Rewards stop at £1,000." }
        if rewardNote.count > Self.rewardNoteLimit { return "Keep the reward note under \(Self.rewardNoteLimit) characters." }
        return nil
    }

    /// The request, or nil while `problem` stands.
    func body(calendar: Calendar = .current) -> FamilyTaskCreateBody? {
        guard problem == nil else { return nil }
        let notes = self.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        var body = FamilyTaskCreateBody(title: trimmedTitle)
        body.notes = notes.isEmpty ? nil : notes
        body.deadline = hasDeadline ? FamilyTaskRules.ymd(deadline, calendar: calendar) : nil
        body.assigneeId = assigneeId
        if hasReward {
            let pence = FamilyTaskRules.pence(from: pounds.trimmingCharacters(in: .whitespaces))
            let note = rewardNote.trimmingCharacters(in: .whitespacesAndNewlines)
            body.reward = FamilyTaskRewardBody(
                kind: kind.rawValue,
                pence: (pence ?? 0) > 0 ? pence : nil,
                note: note.isEmpty ? nil : note
            )
        }
        return body
    }
}

/// Everything the task list decides, as pure functions.
enum FamilyTaskRules {
    /// What this person may do to this task, in the order the row offers it.
    /// The site is the judge (403 / 409); this only keeps the app from
    /// offering what it would refuse.
    static func actions(for task: FamilyTask, me: FamilyTaskMe) -> [FamilyTaskAction] {
        let mine = task.createdBy == me.id
        switch task.status {
        case "open":
            var out: [FamilyTaskAction] = [.done]
            if mine || me.parent { out.append(.delete) }
            return out
        case "done":
            var out: [FamilyTaskAction] = []
            if me.parent { out += [.confirm, .sendBack] }
            if task.doneBy == me.id || me.parent { out.append(.undo) }
            if mine || me.parent { out.append(.delete) }
            return out
        case "confirmed":
            if me.parent, let reward = task.reward, !reward.paid { return [.paid] }
            return []
        default:
            return []
        }
    }

    /// "You", the person's name, or nil for nobody.
    static func name(_ id: String?, in board: FamilyTasksBoard) -> String? {
        guard let id, !id.isEmpty else { return nil }
        if id == board.me.id { return "You" }
        return board.people.first { $0.id == id }?.name ?? "Someone"
    }

    /// Done and waiting on a parent.
    static func awaiting(_ board: FamilyTasksBoard) -> [FamilyTask] {
        board.open.filter(\.isAwaiting)
    }

    /// Still to do (not yet marked done).
    static func toDo(_ board: FamilyTasksBoard) -> [FamilyTask] {
        board.open.filter(\.isOpen)
    }

    /// Owed rewards, one group per person who earned them, most owed first.
    struct OwedGroup: Identifiable, Equatable {
        let id: String
        let name: String
        let items: [FamilyTask]
        var pence: Int { items.reduce(0) { $0 + ($1.reward?.pence ?? 0) } }
    }

    static func owedGroups(_ board: FamilyTasksBoard) -> [OwedGroup] {
        var order: [String] = []
        var byPerson: [String: [FamilyTask]] = [:]
        for task in board.owed.items {
            let who = task.doneBy ?? task.assignee ?? ""
            if byPerson[who] == nil { order.append(who) }
            byPerson[who, default: []].append(task)
        }
        return order.map { who in
            OwedGroup(id: who, name: name(who, in: board) ?? "Someone", items: byPerson[who] ?? [])
        }
        .sorted { a, b in a.pence != b.pence ? a.pence > b.pence : a.name < b.name }
    }

    /// Owed rewards with no money in them: "Day out", "Game time".
    static func owedOther(_ board: FamilyTasksBoard) -> [FamilyTask] {
        board.owed.items.filter { ($0.reward?.pence ?? 0) == 0 }
    }

    /// "£5", "£5.50", "£1,000".
    static func money(_ pence: Int) -> String {
        let pounds = pence / 100
        let rest = abs(pence % 100)
        let whole = FamilySteps.figure(pounds)
        return rest == 0 ? "£\(whole)" : "£\(whole).\(String(format: "%02d", rest))"
    }

    /// "5", "5.5", "£5.50", "5,50" → pence. Nil for anything that is not an
    /// amount; nil for empty.
    static func pence(from text: String) -> Int? {
        var cleaned = text.trimmingCharacters(in: .whitespaces)
        if cleaned.hasPrefix("£") { cleaned.removeFirst() }
        cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return nil }
        let pieces = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count <= 2, pieces.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return nil }
        guard let whole = Int(pieces[0].isEmpty ? "0" : String(pieces[0])) else { return nil }
        var fraction = 0
        if pieces.count == 2 {
            let digits = String(pieces[1])
            guard digits.count <= 2 else { return nil }
            fraction = Int(digits.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0
        }
        guard whole <= 1_000_000 else { return nil }
        return whole * 100 + fraction
    }

    /// "2026-09-28" in `calendar`'s zone.
    static func ymd(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(ymd: String, calendar: Calendar = .current) -> Date? {
        let parts = ymd.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// A deadline, said relative to today: "Due today", "Due tomorrow",
    /// "Overdue · Mon 22 Sep", "Due Fri 3 Oct".
    static func deadline(_ ymd: String, now: Date = Date(), calendar: Calendar = .current) -> (text: String, overdue: Bool)? {
        guard let due = date(ymd: ymd, calendar: calendar) else { return nil }
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: due)).day ?? 0
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_GB")
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        format.dateFormat = "EEE d MMM"
        switch days {
        case ..<0: return ("Overdue · \(format.string(from: due))", true)
        case 0: return ("Due today", false)
        case 1: return ("Due tomorrow", false)
        default: return ("Due \(format.string(from: due))", false)
        }
    }
}

/// What a card or a widget says about the task list: counts, the money, and
/// the next few things to do. Small enough to keep in the Keychain.
struct FamilyTasksSummary: Codable, Equatable {
    struct Line: Codable, Equatable, Identifiable {
        let id: String
        let title: String
        let due: String?
        let overdue: Bool
        let reward: String?
    }

    /// Open, not yet done.
    var toDo: Int
    /// Done and waiting for a parent. A parent is who can act on these.
    var awaiting: Int
    var parent: Bool
    var owedPence: Int
    /// Owed rewards with no £ in them.
    var owedOther: Int
    var next: [Line]

    static func make(_ board: FamilyTasksBoard, now: Date = Date(), calendar: Calendar = .current, limit: Int = 3) -> FamilyTasksSummary {
        let toDo = FamilyTaskRules.toDo(board)
        // Mine first, then anyone's, then other people's; soonest deadline
        // first within each — the site's order already is deadline-first.
        let rank: (FamilyTask) -> Int = { task in
            if task.assignee == board.me.id { return 0 }
            if task.assignee == nil { return 1 }
            return 2
        }
        let ordered = toDo.enumerated().sorted { a, b in
            let ra = rank(a.element), rb = rank(b.element)
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
        let lines = ordered.prefix(limit).map { task -> Line in
            let due = task.deadline.flatMap { FamilyTaskRules.deadline($0, now: now, calendar: calendar) }
            return Line(id: task.id, title: task.title, due: due?.text, overdue: due?.overdue ?? false, reward: task.reward?.label)
        }
        return FamilyTasksSummary(
            toDo: toDo.count,
            awaiting: FamilyTaskRules.awaiting(board).count,
            parent: board.me.parent,
            owedPence: board.owed.totalPence,
            owedOther: FamilyTaskRules.owedOther(board).count,
            next: Array(lines)
        )
    }

    /// "£15 owed", "£15 + 2 treats owed", "2 treats owed", or nil.
    var owedLine: String? {
        let treats = owedOther == 1 ? "1 treat" : "\(owedOther) treats"
        switch (owedPence > 0, owedOther > 0) {
        case (true, true): return "\(FamilyTaskRules.money(owedPence)) + \(treats) owed"
        case (true, false): return "\(FamilyTaskRules.money(owedPence)) owed"
        case (false, true): return "\(treats) owed"
        default: return nil
        }
    }
}
