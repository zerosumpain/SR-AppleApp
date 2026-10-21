import Foundation

// v8 (2026-10-21): the planner's decisions, worked out for the screen.
//
// Everything the question, proposal and "What changed" cards say — which
// questions show and in what order, how a proposal's trade-offs read, what
// two alternatives differ in, a plan difference as before → after per day,
// a start job's progress lines — and how the phone's copy of a trip changes
// when one is decided. The cards only draw what this says.
//
// Foundation only: the Linux harness compiles this with `TripModels.swift`,
// `TripDecisionModels.swift` and `TripClock.swift` and runs the same
// assertions as `TripDecisionTests`.

/// Where a trip is: what leads its page.
enum TripPhase: String, Hashable {
    case before, during, after

    static func of(start: String, end: String, today: String) -> TripPhase {
        if today < start { return .before }
        if today > end { return .after }
        return .during
    }
}

enum TripDecisions {
    // MARK: Who may do what

    /// Editors (the creator, parents) accept and answer; members vote and suggest.
    static func canDecide(_ access: TripAccess) -> Bool { access.canEdit || access.canApprove }

    /// True when the server speaks v8 (it sent the decision fields at all).
    static func speaksV8(_ bundle: TripBundle) -> Bool {
        bundle.proposals != nil || bundle.questions != nil || bundle.brief != nil
    }

    // MARK: Questions

    /// The open questions to show, most important first, at most three. A
    /// member sees only those put to the family (they vote; a parent decides).
    static func openQuestions(_ questions: [TripQuestion]?, access: TripAccess, limit: Int = 3) -> [TripQuestion] {
        let editor = canDecide(access)
        return (questions ?? [])
            .filter { $0.status == .open && (editor || $0.audience == "family") }
            .sorted { a, b in
                if a.impact != b.impact { return a.impact > b.impact }
                switch (a.deadline, b.deadline) {
                case let (x?, y?) where x != y: return x < y
                case (.some, nil): return true
                case (nil, .some): return false
                default: return a.createdAt < b.createdAt
                }
            }
            .prefix(limit)
            .map { $0 }
    }

    /// "1 of 3".
    static func counter(_ index: Int, of count: Int) -> String { "\(index + 1) of \(count)" }

    /// "3 quick questions", "1 quick question".
    static func questionsHeading(_ count: Int) -> String {
        count == 1 ? "1 quick question" : "\(count) quick questions"
    }

    /// "If you skip: carry on, with a long lunch."
    static func ifSkipped(_ q: TripQuestion) -> String? {
        let said = q.ifSkipped.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !said.isEmpty else { return q.defaultAnswer.map { "If you skip: \($0.label.lowercased())." } }
        let first = said.prefix(1).lowercased() + said.dropFirst()
        return "If you skip: " + first + (said.hasSuffix(".") ? "" : ".")
    }

    /// "Answer by Thu 15 Oct" (urgent within three days), "Answer today",
    /// "Was due Thu 15 Oct".
    static func deadline(_ q: TripQuestion, today: String, zone: TimeZone) -> (text: String, urgent: Bool)? {
        guard let by = q.deadline else { return nil }
        if by < today { return ("Was due \(TripFormat.day(by, zone: zone))", true) }
        if by == today { return ("Answer today", true) }
        let days = TripClock(zone.identifier).days(from: today, to: by) ?? 99
        return ("Answer by \(TripFormat.day(by, zone: zone))", days <= 3)
    }

    /// "Votes: Back to the flat — Sam · Carry on — John". Nil with none.
    static func votesLine(_ q: TripQuestion) -> String? {
        let parts = q.answers.compactMap { a -> String? in
            guard let names = q.votes[a.id], !names.isEmpty else { return nil }
            return "\(a.label) — \(names.joined(separator: ", "))"
        }
        return parts.isEmpty ? nil : "Votes: " + parts.joined(separator: " · ")
    }

    /// What VoiceOver says for an answer chip.
    static func spoken(_ answer: QuestionAnswer, in q: TripQuestion, voting: Bool) -> String {
        var out = (voting ? "Vote for " : "Answer: ") + answer.label
        if answer.id == q.defaultAnswerId && q.appliedDefault { out += ". The plan assumes this now" }
        if let summary = answer.summary { out += ". " + summary }
        return out
    }

    // MARK: Proposals

    struct ProposalGroup: Hashable, Identifiable {
        var id: String
        var kind: ProposalKind
        var heading: String
        var proposals: [TripProposal]
    }

    /// Open proposals as groups of alternatives, in the order the server gave
    /// them — trip shapes first, since choosing one replaces the rest.
    static func groups(_ proposals: [TripProposal]?, bundle: TripBundle?, zone: TimeZone) -> [ProposalGroup] {
        var order: [String] = []
        var byGroup: [String: [TripProposal]] = [:]
        for p in proposals ?? [] where p.status == .open {
            if byGroup[p.groupId] == nil { order.append(p.groupId) }
            byGroup[p.groupId, default: []].append(p)
        }
        let groups = order.compactMap { id -> ProposalGroup? in
            guard let list = byGroup[id], let first = list.first else { return nil }
            return ProposalGroup(id: id, kind: first.kind, heading: heading(first, count: list.count, bundle: bundle, zone: zone), proposals: list)
        }
        return groups.filter { $0.kind == .shape } + groups.filter { $0.kind != .shape }
    }

    /// "3 ways to do the trip", "Instead of Capitoline Museums", "For Tue 27 Oct, afternoon".
    static func heading(_ p: TripProposal, count: Int, bundle: TripBundle?, zone: TimeZone) -> String {
        let day = p.scope.date.map { TripFormat.day($0, zone: zone) }
        let stage = p.scope.stage.flatMap(stageLabel)
        switch p.kind {
        case .shape:
            return count == 1 ? "A way to do the trip" : "\(count) ways to do the trip"
        case .swap:
            if let title = replacedTitle(p, bundle: bundle) { return "Instead of \(title)" }
            return day.map { "Swaps for \($0)" } ?? "Swaps"
        case .fill:
            return "For " + ([day, stage?.lowercased()].compactMap { $0 }.joined(separator: ", ")).ifEmpty("a free slot")
        case .day:
            return day.map { "Other versions of \($0)" } ?? "Another version of the day"
        case .fix:
            return "To put right"
        case .change:
            return "A change to approve"
        case .replan:
            return "Ways to carry on"
        case .unknown:
            return "Ideas"
        }
    }

    /// The stop a swap replaces, by name.
    static func replacedTitle(_ p: TripProposal, bundle: TripBundle?) -> String? {
        if let removed = p.diff.changes.first(where: { $0.kind == "removed" || $0.kind == "dropped" }) { return removed.title }
        if let wish = bundle?.wish(p.scope.wishId) { return wish.title }
        if let stopId = p.scope.stopId, let bundle {
            for day in bundle.plan?.plan.days ?? [] { if let s = day.stops.first(where: { $0.id == stopId }) { return s.title } }
        }
        return nil
    }

    static func stageLabel(_ raw: String) -> String? {
        switch raw {
        case "morning": return "Morning"
        case "lunch": return "Lunch"
        case "afternoon": return "Afternoon"
        case "evening": return "Evening"
        default: return nil
        }
    }

    /// The proposed version of one day — the ghost on the day's map.
    static func previewDay(_ p: TripProposal, date: String) -> PlannedDay? {
        p.preview.first { $0.date == date }
    }

    /// The day a proposal is about: its scope's, else the first it changes.
    static func focusDate(_ p: TripProposal) -> String? {
        p.scope.date ?? p.preview.first?.date ?? p.diff.dates.first
    }

    // MARK: Trade-offs

    enum Tone: String, Hashable { case plain, good, warn }

    struct Chip: Hashable, Identifiable {
        var id: String
        var text: String
        /// An SF Symbol name.
        var symbol: String
        var tone: Tone
    }

    /// The trade-off chips, in a fixed order: does it fit, walking, early
    /// starts, booking, cost, indoors, children, less visited.
    static func chips(_ p: TripProposal, currencySymbol: String) -> [Chip] {
        let t = p.tradeoffs
        var out: [Chip] = []
        if !t.fits { out.append(Chip(id: "fits", text: "Doesn't fit as asked", symbol: "exclamationmark.triangle", tone: .warn)) }
        if let w = t.walkMin, abs(w) >= 1 {
            let m = Int(abs(w).rounded())
            out.append(w < 0
                ? Chip(id: "walk", text: "\(m) min less walking", symbol: "figure.walk", tone: .good)
                : Chip(id: "walk", text: "\(m) min more walking", symbol: "figure.walk", tone: .plain))
        }
        if let km = t.walkKmPerDay {
            out.append(Chip(id: "km", text: "\(oneDecimal(km)) km a day", symbol: "figure.walk", tone: .plain))
        }
        if let e = t.earlyStarts {
            let n = Int(e.rounded())
            out.append(n == 0
                ? Chip(id: "early", text: "No early starts", symbol: "sunrise", tone: .good)
                : Chip(id: "early", text: n == 1 ? "1 early start" : "\(n) early starts", symbol: "sunrise", tone: .plain))
        }
        if let b = t.toBook, b >= 1 {
            let n = Int(b.rounded())
            out.append(Chip(id: "book", text: "\(n) to book", symbol: "ticket", tone: .plain))
        }
        if let cost = t.costText, !cost.isEmpty {
            out.append(Chip(id: "cost", text: cost, symbol: currencySymbol, tone: .plain))
        }
        if let indoor = t.indoor {
            out.append(Chip(id: "indoor", text: indoor ? "Indoors" : "Outdoors", symbol: indoor ? "house" : "sun.max", tone: .plain))
        }
        if let kids = t.kidFriendly {
            out.append(Chip(id: "kids", text: kids ? "Good for children" : "Better for adults",
                            symbol: kids ? "figure.and.child.holdinghands" : "person.2", tone: .plain))
        }
        if t.lessVisited { out.append(Chip(id: "quiet", text: "Less visited", symbol: "leaf", tone: .good)) }
        return out
    }

    /// "Pushes out Trevi Fountain and Spanish Steps".
    static func pushesOut(_ p: TripProposal) -> String? {
        let out = p.tradeoffs.pushesOut
        guard !out.isEmpty else { return nil }
        return "Pushes out " + list(out)
    }

    /// "Moves Pantheon to Thu 29 Oct".
    static func moves(_ p: TripProposal, zone: TimeZone) -> [String] {
        p.tradeoffs.moves.map { "Moves \($0.title) to \(TripFormat.day($0.to, zone: zone))" }
    }

    // MARK: Compare

    struct CompareRow: Hashable, Identifiable {
        var id: String
        var label: String
        var left: String
        var right: String
        /// 0 = the left is better, 1 = the right; nil when neither is, or it is a matter of taste.
        var better: Int? = nil
        var differs: Bool { left != right }
    }

    /// Two alternatives side by side, a row per thing either one says.
    /// The card highlights the rows that differ; the rest read quietly.
    static func compare(_ a: TripProposal, _ b: TripProposal, zone: TimeZone) -> [CompareRow] {
        var rows: [CompareRow] = []
        func row(_ id: String, _ label: String, _ f: (TripProposal) -> String?, none: String = "—") {
            let l = f(a), r = f(b)
            guard l != nil || r != nil else { return }
            rows.append(CompareRow(id: id, label: label, left: l ?? none, right: r ?? none))
        }
        row("when", "When") { $0.tradeoffs.fitText }
        row("walk", "Walking") { p in
            p.tradeoffs.walkMin.map { w in
                let m = Int(abs(w).rounded())
                return m == 0 ? "No change" : (w < 0 ? "\(m) min less" : "\(m) min more")
            }
        }
        row("km", "Walking a day") { $0.tradeoffs.walkKmPerDay.map { "\(oneDecimal($0)) km" } }
        row("early", "Early starts") { $0.tradeoffs.earlyStarts.map { $0 < 0.5 ? "None" : "\(Int($0.rounded()))" } }
        row("book", "To book") { $0.tradeoffs.toBook.map { $0 < 0.5 ? "Nothing" : "\(Int($0.rounded()))" } }
        row("cost", "Cost", { $0.tradeoffs.costText }, none: "Not known")
        row("indoor", "Indoors") { $0.tradeoffs.indoor.map { $0 ? "Indoors" : "Outdoors" } }
        row("kids", "Children") { $0.tradeoffs.kidFriendly.map { $0 ? "Good for children" : "Better for adults" } }
        row("quiet", "Crowds") { $0.tradeoffs.lessVisited ? "Less visited" : "Well known" }
        row("out", "Pushes out", { $0.tradeoffs.pushesOut.isEmpty ? nil : list($0.tradeoffs.pushesOut) }, none: "Nothing")
        row("moves", "Moves") { p in
            p.tradeoffs.moves.isEmpty ? nil : p.tradeoffs.moves.map { "\($0.title) to \(TripFormat.day($0.to, zone: zone))" }.joined(separator: "; ")
        }
        row("leaves", "Leaves out", { $0.shape.map { $0.leavesOut.isEmpty ? "Nothing" : list($0.leavesOut) } }, none: "Nothing")
        row("fits", "Fits") { $0.tradeoffs.fits ? "As asked" : "Not quite" }
        // A tick on the better side, where "better" is not a matter of taste:
        // less walking, fewer early starts and bookings, nothing pushed out.
        func lower(_ f: (TripProposal) -> Double?) -> Int? {
            guard let l = f(a), let r = f(b), l != r else { return nil }
            return l < r ? 0 : 1
        }
        for i in rows.indices where rows[i].differs {
            switch rows[i].id {
            case "walk": rows[i].better = lower { $0.tradeoffs.walkMin }
            case "km": rows[i].better = lower { $0.tradeoffs.walkKmPerDay }
            case "early": rows[i].better = lower { $0.tradeoffs.earlyStarts }
            case "book": rows[i].better = lower { $0.tradeoffs.toBook }
            case "out": rows[i].better = lower { Double($0.tradeoffs.pushesOut.count) }
            case "fits": rows[i].better = a.tradeoffs.fits ? 0 : 1
            default: break
            }
        }
        return rows
    }

    // MARK: What changed

    struct ChangeLine: Hashable, Identifiable {
        var id: String
        /// added, removed, moved, retimed, dropped (or "line" for a plain sentence).
        var kind: String
        var title: String
        var before: String?
        var after: String?
        var spoken: String
    }

    struct ChangeDay: Hashable, Identifiable {
        var id: String
        var date: String?
        var title: String
        var lines: [ChangeLine]
    }

    /// A plan difference, per day: what each stop was before and is after.
    /// A difference with no structured changes reads as its plain lines.
    static func changeDays(_ diff: PlanDiff, zone: TimeZone) -> [ChangeDay] {
        guard !diff.changes.isEmpty else {
            guard !diff.lines.isEmpty else { return [] }
            return [ChangeDay(id: "lines", date: nil, title: "What changed",
                              lines: diff.lines.enumerated().map { i, l in
                                  ChangeLine(id: "line-\(i)", kind: "line", title: l, before: nil, after: nil, spoken: l)
                              })]
        }
        var order: [String] = diff.dates
        var byDate: [String: [ChangeLine]] = [:]
        for (i, c) in diff.changes.enumerated() {
            let key = c.date ?? c.fromDate ?? ""
            if !order.contains(key) { order.append(key) }
            byDate[key, default: []].append(line(c, index: i, zone: zone))
        }
        return order.compactMap { key in
            guard let lines = byDate[key], !lines.isEmpty else { return nil }
            return ChangeDay(id: key.isEmpty ? "trip" : key, date: key.isEmpty ? nil : key,
                             title: key.isEmpty ? "Across the trip" : TripFormat.day(key, zone: zone), lines: lines)
        }
    }

    static func line(_ c: PlanChange, index: Int, zone: TimeZone) -> ChangeLine {
        let from = c.fromMin.map(TripFormat.time)
        let to = c.toMin.map(TripFormat.time)
        let id = "\(index)-\(c.kind)-\(c.wishId ?? c.title)"
        switch c.kind {
        case "added":
            return ChangeLine(id: id, kind: c.kind, title: c.title, before: nil, after: to ?? "Added",
                              spoken: "\(c.title) added" + (to.map { " at \($0)" } ?? ""))
        case "removed":
            return ChangeLine(id: id, kind: c.kind, title: c.title, before: from ?? "Planned", after: "Removed",
                              spoken: "\(c.title) removed" + (from.map { ", was at \($0)" } ?? ""))
        case "moved":
            let was = [c.fromDate.map { TripFormat.day($0, zone: zone) }, from].compactMap { $0 }.joined(separator: " ")
            let now = [c.date.map { TripFormat.day($0, zone: zone) }, to].compactMap { $0 }.joined(separator: " ")
            return ChangeLine(id: id, kind: c.kind, title: c.title, before: was.ifEmpty("Before"), after: now.ifEmpty("Moved"),
                              spoken: "\(c.title) moved" + (now.isEmpty ? "" : " to \(now)"))
        case "retimed":
            return ChangeLine(id: id, kind: c.kind, title: c.title, before: from, after: to,
                              spoken: "\(c.title) now " + (to.map { "at \($0)" } ?? "at another time") + (from.map { ", was \($0)" } ?? ""))
        case "dropped":
            let why = c.reason.map { "Left out — \($0)" } ?? "Left out"
            return ChangeLine(id: id, kind: c.kind, title: c.title, before: from ?? "Planned", after: why,
                              spoken: "\(c.title) left out" + (c.reason.map { ": \($0)" } ?? ""))
        default:
            return ChangeLine(id: id, kind: c.kind, title: c.title, before: from, after: to, spoken: c.title)
        }
    }

    /// "850 m less walking", "1.2 km more walking"; nil under 50 m.
    static func walkDelta(_ metres: Double?) -> String? {
        guard let m = metres, abs(m) >= 50 else { return nil }
        let size = abs(m) < 1000 ? "\(Int((abs(m) / 10).rounded()) * 10) m" : "\(oneDecimal(abs(m) / 1000)) km"
        return size + (m < 0 ? " less walking" : " more walking")
    }

    /// The toast's line: "2 changes on Tue 27 Oct", "3 changes", "Nothing moved".
    static func summary(_ diff: PlanDiff, zone: TimeZone) -> String {
        let n = diff.changes.isEmpty ? diff.lines.count : diff.changes.count
        guard n > 0 else { return "Nothing moved" }
        let what = n == 1 ? "1 change" : "\(n) changes"
        let dates = Set(diff.changes.compactMap { $0.date ?? $0.fromDate } + diff.dates)
        if dates.count == 1, let only = dates.first { return "\(what) · \(TripFormat.day(only, zone: zone))" }
        return what
    }

    /// "Undo this", "Undo these 3" — Undo says what it undoes.
    static func undoLabel(_ diff: PlanDiff) -> String {
        let n = diff.changes.isEmpty ? diff.lines.count : diff.changes.count
        return n <= 1 ? "Undo this" : "Undo these \(n)"
    }

    /// "15:10–16:25, 12 min walk in" → the time ("15:10–16:25") and the rest.
    static func fitParts(_ fitText: String?) -> (time: String?, rest: String?) {
        guard let fit = fitText?.trimmingCharacters(in: .whitespaces), !fit.isEmpty else { return (nil, nil) }
        let head = fit.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let looksLikeTime = head[0].range(of: #"^\d{1,2}:\d{2}(\s*[–-]\s*\d{1,2}:\d{2})?$"#, options: .regularExpression) != nil
        guard looksLikeTime else { return (nil, fit) }
        return (head[0], head.count > 1 && !head[1].isEmpty ? head[1] : nil)
    }

    /// "Wed 28 Oct", or with a booking deadline "Tue 27 Oct · book soon": the
    /// question card's eyebrow.
    static func eyebrow(_ q: TripQuestion, today: String, zone: TimeZone) -> String? {
        let day = q.affects.dates.first.map { TripFormat.day($0, zone: zone) }
        guard let due = deadline(q, today: today, zone: zone) else { return day }
        let soon = due.urgent ? "book soon" : nil
        return [day, soon].compactMap { $0 }.joined(separator: " · ").ifEmpty(due.text)
    }

    // MARK: Currency

    /// The money symbol that follows the trip: the cost text's own symbol,
    /// else the destination's (by its time zone). No euro for Edinburgh.
    static func currencySymbol(timeZone: String, costText: String? = nil) -> String {
        if let cost = costText {
            if cost.contains("£") { return "sterlingsign.circle" }
            if cost.contains("€") { return "eurosign.circle" }
            if cost.contains("¥") { return "yensign.circle" }
            if cost.contains("CHF") { return "francsign.circle" }
            if cost.contains("$") { return "dollarsign.circle" }
        }
        let sterling: Set<String> = ["Europe/London", "Europe/Belfast", "Europe/Jersey", "Europe/Guernsey", "Europe/Isle_of_Man", "Europe/Gibraltar", "Atlantic/Stanley"]
        let euro: Set<String> = [
            "Europe/Rome", "Europe/Paris", "Europe/Berlin", "Europe/Madrid", "Europe/Lisbon", "Europe/Dublin", "Europe/Amsterdam",
            "Europe/Brussels", "Europe/Vienna", "Europe/Athens", "Europe/Helsinki", "Europe/Luxembourg", "Europe/Malta",
            "Europe/Monaco", "Europe/Vatican", "Europe/San_Marino", "Europe/Andorra", "Europe/Bratislava", "Europe/Ljubljana",
            "Europe/Tallinn", "Europe/Riga", "Europe/Vilnius", "Europe/Zagreb", "Europe/Busingen", "Asia/Nicosia", "Europe/Nicosia",
            "Atlantic/Madeira", "Atlantic/Canary", "Atlantic/Azores", "Europe/Podgorica",
        ]
        if sterling.contains(timeZone) { return "sterlingsign.circle" }
        if euro.contains(timeZone) { return "eurosign.circle" }
        if timeZone == "Europe/Zurich" { return "francsign.circle" }
        if timeZone == "Asia/Tokyo" { return "yensign.circle" }
        if timeZone == "Asia/Kolkata" { return "indianrupeesign.circle" }
        if timeZone.hasPrefix("America/") || timeZone.hasPrefix("Australia/") || timeZone == "Pacific/Auckland" || timeZone == "Pacific/Honolulu" {
            return "dollarsign.circle"
        }
        return "banknote"
    }

    // MARK: Starting a trip

    /// A start job's progress card: a line per stage, ticked as it is done.
    struct StartProgress: Hashable {
        struct Line: Hashable, Identifiable {
            var id: String
            var label: String
            var detail: String?
            var state: JobStageState
        }

        var lines: [Line]
        var done: Int
        var total: Int
        var finished: Bool
        var failed: String?
        var cancelled: Bool
        /// The stage being worked on, in plain words.
        var current: String?

        /// "2 of 5 done".
        var count: String { "\(done) of \(total) done" }
        var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
    }

    static func progress(_ job: StagedJob?) -> StartProgress {
        let stages = job?.stages ?? []
        let lines = stages.map { StartProgress.Line(id: $0.key, label: $0.label, detail: $0.detail, state: $0.state) }
        let done = stages.filter { $0.state == .done || $0.state == .skipped }.count
        let failedStage = stages.first { $0.state == .failed }
        let status = job?.status ?? "running"
        return StartProgress(
            lines: lines, done: done, total: stages.count,
            finished: status == "done",
            failed: status == "failed" ? (job?.error ?? failedStage?.detail ?? "The planner couldn't finish that — try again.") : nil,
            cancelled: status == "cancelled",
            current: stages.first { $0.state == .running }?.label
        )
    }

    /// The symbol for a stage's line.
    static func symbol(_ state: JobStageState) -> String {
        switch state {
        case .done: return "checkmark.circle.fill"
        case .running: return "circle.dotted"
        case .failed: return "xmark.circle"
        case .skipped: return "minus.circle"
        case .waiting, .unknown: return "circle"
        }
    }

    // MARK: Converse

    /// What to say when the conversation has nothing to follow up: before
    /// the trip, planning; on the day, the day; members, advice.
    static func starters(phase: TripPhase, canEdit: Bool) -> [String] {
        guard canEdit else {
            return ["What's good near here for kids?", "Is there time for an ice cream this afternoon?", "What should I pack for tomorrow?"]
        }
        switch phase {
        case .before, .after:
            return ["What are we missing?", "Make day 2 rainy-day proof", "Find a dinner near the stay"]
        case .during:
            return ["We're running about 20 minutes late", "Skip the next stop", "Swap the next two", "Make the rest of today lighter"]
        }
    }

    // MARK: Swapping a stop

    /// A stop that can be swapped: a planned visit, not locked or booked.
    static func canSwap(_ stop: PlannedStop, bundle: TripBundle) -> Bool {
        guard stop.kind == .wish, !stop.locked, canDecide(bundle.can), speaksV8(bundle) else { return false }
        return bundle.booking(for: stop)?.status != .booked
    }

    // MARK: Helpers

    static func oneDecimal(_ v: Double) -> String {
        let tenths = Int((v * 10).rounded())
        return "\(tenths / 10).\(abs(tenths % 10))"
    }

    /// "A", "A and B", "A, B and C".
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + (items.last ?? "")
        }
    }
}

// MARK: - The guided start, as typed

/// What the guided start has gathered: where, when, who, pace, the notes
/// confirmed and anything typed. Dates are the phone's calendar days.
struct TripStartDraft: Equatable {
    var destination = ""
    var startDate: Date
    var endDate: Date
    var travellers: [TripStart.Traveller] = []
    /// relaxed, normal, packed.
    var pace = "normal"
    var confirmNotes: Set<String> = []
    var text = ""

    static let longestTripDays = 30

    init(startDate: Date, endDate: Date) {
        self.startDate = startDate
        self.endDate = endDate
    }

    static func localDate(_ date: Date, zone: TimeZone) -> String { TripClock(zone.identifier).localDate(date) }

    /// What stops the start, said plainly. Empty when it can go.
    func problems(zone: TimeZone) -> [String] {
        var out: [String] = []
        if destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append("Say where you're going.") }
        let a = Self.localDate(startDate, zone: zone), b = Self.localDate(endDate, zone: zone)
        if b < a { out.append("The trip ends before it starts.") }
        if let days = TripClock(zone.identifier).days(from: a, to: b), days + 1 > Self.longestTripDays {
            out.append("A trip can be up to \(Self.longestTripDays) days.")
        }
        return out
    }

    func start(zone: TimeZone, notes: [NoteFact] = []) -> TripStart {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only notes still on offer: a ticked one from an earlier search is not sent.
        let offered = Set(notes.map(\.id))
        return TripStart(
            destination: destination.trimmingCharacters(in: .whitespacesAndNewlines),
            startDate: Self.localDate(startDate, zone: zone),
            endDate: Self.localDate(endDate, zone: zone),
            travellers: travellers,
            pace: pace,
            confirmNotes: confirmNotes.filter { offered.contains($0) }.sorted(),
            text: typed.isEmpty ? nil : typed
        )
    }

    /// The same start as one sentence — for a server too old for the guided
    /// start, which still makes a trip from its opening message.
    func sentence(zone: TimeZone) -> String {
        let s = start(zone: zone)
        var out = "\(s.destination), \(TripFormat.range(s.startDate, s.endDate, zone: zone))"
        if !travellers.isEmpty {
            out += ", with " + TripDecisions.list(travellers.map { t in t.age.map { "\(t.name) (\(Int($0)))" } ?? t.name })
        }
        out += ", \(pace) pace."
        if let typed = s.text { out += " " + typed }
        return out
    }
}

// MARK: - The latest change, with its undo

/// What the last decision did to a trip — kept on the phone so its card and
/// its Undo survive the sheet closing and the app being closed.
struct TripChangeRecord: Codable, Hashable, Identifiable {
    var id: String
    var tripId: String
    /// "Used Palazzo Altemps", "Answered: Carry on", "Undone".
    var title: String
    var diff: PlanDiff
    var lines: [String]
    /// Where Undo goes back to; nil for an undo itself.
    var undoTo: Int?
    var planVersion: Int?
    var at: Date
    /// A lasting preference the answer offered to remember.
    var remember: String?

    static func of(_ result: DecisionResult, tripId: String, title: String, at: Date = Date()) -> TripChangeRecord {
        TripChangeRecord(
            id: UUID().uuidString.lowercased(), tripId: tripId, title: title,
            diff: result.diff ?? PlanDiff(lines: result.changes ?? [], changes: [], dates: [], walkDeltaM: nil, dropped: []),
            lines: result.changes ?? [], undoTo: result.undo?.toVersion, planVersion: result.planVersion, at: at,
            remember: result.remember
        )
    }
}

// MARK: - The phone's copy, after a decision

/// How a trip's decision fields change on the phone the moment the server
/// answers, before the re-read bundle confirms it — so a card goes away at
/// once and nothing reappears while the plan is fetched.
extension TripBundle {
    /// A proposal taken: its group is settled (the rest superseded), and a
    /// shape settles every shape.
    mutating func settle(accepted p: TripProposal) {
        proposals = proposals?.filter { other in
            other.groupId != p.groupId && !(p.kind == .shape && other.kind == .shape)
        }
    }

    /// A proposal turned down: only it goes.
    mutating func settle(rejected p: TripProposal) {
        proposals = proposals?.filter { $0.id != p.id }
    }

    /// The plan moved on: the re-checked proposal replaces the one shown.
    mutating func replace(_ p: TripProposal) {
        guard var list = proposals else { proposals = [p]; return }
        if let i = list.firstIndex(where: { $0.id == p.id }) { list[i] = p } else { list.append(p) }
        proposals = list
    }

    /// A new group of alternatives: it replaces any open group of the same id.
    mutating func merge(group: [TripProposal]) {
        guard let first = group.first else { return }
        let ids = Set(group.map(\.groupId))
        var list = (proposals ?? []).filter { !ids.contains($0.groupId) }
        if first.kind == .shape { list.insert(contentsOf: group, at: 0) } else { list.append(contentsOf: group) }
        proposals = list
    }

    /// A question answered (or skipped, or decided): out of the open ones,
    /// into the answered. A vote only updates it — it stays open.
    mutating func settle(question q: TripQuestion) {
        if q.status == .open {
            questions = questions.map { list in list.map { $0.id == q.id ? q : $0 } }
            return
        }
        questions = questions?.filter { $0.id != q.id }
        if q.status == .answered {
            answered = [q] + (answered ?? []).filter { $0.id != q.id }
        }
    }
}

private extension String {
    func ifEmpty(_ other: String) -> String { isEmpty ? other : self }
}
