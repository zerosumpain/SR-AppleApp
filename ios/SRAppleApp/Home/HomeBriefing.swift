import Foundation

/// One line of Home's briefing: a figure, what it means, and where it came
/// from — "1,240 steps behind Sam · about 13 min of walking to draw level".
struct HomeInsight: Equatable, Identifiable {
    /// Where the line came from, and so where a tap on it goes.
    enum Source: String, CaseIterable {
        case watch, diary, trip, moves, tasks, readiness, vitals, rings, steps, flows, games, messages, daydream, news, calm
    }

    enum Tone: Equatable { case good, warn, bad, plain }

    let source: Source
    /// Set large: "1,240", "72", "08:10". Nil for a line that is all words.
    let figure: String?
    /// After the figure: "steps behind Sam".
    let text: String
    /// Under it, quieter: "about 13 min of walking to draw level".
    let detail: String?
    let tone: Tone
    /// How hard it should pull the eye, 0…100. Only the ranking reads it.
    let weight: Double
    /// The health figure the line is about, when it is about one: a tap opens
    /// that figure's own chart rather than the whole Health tab.
    var figureKey: String? = nil

    var id: String { source.rawValue }

    /// "1,240 steps behind Sam. About 13 min of walking to draw level."
    var spoken: String {
        let lead = [figure, text].compactMap { $0 }.joined(separator: " ")
        return detail.map { "\(lead). \($0)" } ?? lead
    }
}

/// What Home leads with: the few things worth knowing right now.
///
/// Every tile below says one feature's state. This says which of those states
/// MATTERS, ranked across all of them: a leave-by in twenty minutes outranks a
/// good night's sleep, an overdue task outranks a news count. One line per
/// source at most, three lines in all, each a figure with what it means.
///
/// Foundation only and fed plain values rather than the stores, so every
/// rule is a unit test the Linux harness runs (`scripts/home-check.sh`).
enum HomeBriefing {
    /// What the page knows. Everything is optional: a member's phone has its
    /// rings and the family's boards; the owner's has the site's figures too.
    struct Facts: Equatable {
        var now: Date
        /// The phone's zone, for "leaves 08:10" and the hour of the day.
        var zone: TimeZone = .current
        var readiness: Readiness?
        var vitals: [Vital] = []
        var rings: [Ring] = []
        var steps: [Stepper] = []
        var tasks: Tasks?
        var watch: [Watch] = []
        var moves: [Move] = []
        var diary: [Diary] = []
        var trip: Trip?
        var failingFlows: [String] = []
        var toDecide = 0
        var decideTitle: String?
        var newsUnseen = 0
        var topStory: String?
        var invites: [Invite] = []
        var message: Message?

        init(now: Date, zone: TimeZone = .current) {
            self.now = now
            self.zone = zone
        }
    }

    struct Readiness: Equatable {
        let score: Double
        let label: String
        let recommendation: String
    }

    /// One of /health's figures as Today sends it: the value, and how it sits
    /// against the person's own last seven days.
    struct Vital: Equatable {
        let key: String
        let label: String
        let value: Double
        /// With its unit: "64 ms", "7h 24m".
        let shown: String
        let delta: Double?
        /// "+5 vs 7d", "−18m vs 7d".
        let deltaDisplay: String?
        let improving: Bool?
    }

    struct Ring: Equatable {
        let key: String
        let label: String
        let value: Double
        let goal: Double
        let unit: String

        var fraction: Double { goal > 0 ? value / goal : 0 }
    }

    struct Stepper: Equatable {
        /// First name; the caller's own row says "You" nowhere here.
        let name: String
        let steps: Int
        let me: Bool
    }

    struct Tasks: Equatable {
        var toDo: Int
        var overdue: Int
        var awaiting: Int
        /// A parent confirms what is done and owes the rewards.
        var parent: Bool
        var owedPence: Int
        var overdueTitle: String?
        var nextTitle: String?
        /// "today 18:00", "Fri".
        var nextDue: String?
    }

    /// Something off the family's usual pattern, as the travel desk says it.
    struct Watch: Equatable {
        let title: String
        let detail: String
        /// The desk's `alert`, as against a `watch`.
        let alert: Bool
    }

    /// A family member's next likely move.
    struct Move: Equatable {
        let name: String
        let isSelf: Bool
        let to: String
        let leaveAt: Date
        /// On the way already: `arriveFrom` is when they get there.
        let arriving: Bool
        let arriveFrom: Date?
    }

    /// The owner's own diary, with the desk's leave-by.
    struct Diary: Equatable {
        let title: String
        let start: Date
        let leaveBy: Date?
        let place: String?
    }

    struct Trip: Equatable {
        let place: String
        /// Days until it starts; nil while it runs.
        let days: Int?
        let questions: Int
        /// While a trip runs: the next stop, and minutes until leaving for it.
        let nextStop: String?
        let leaveInMinutes: Int?
    }

    struct Invite: Equatable {
        let host: String
        let game: String
    }

    struct Message: Equatable {
        /// "Sam: Back at six" — the store's own line.
        let line: String
        let at: Date
        let mine: Bool
    }

    /// Walking pace, for "about 13 min of walking": a steady walk is a
    /// hundred-odd steps a minute.
    static let stepsPerMinute = 100.0

    // MARK: - The ranking

    /// The lines worth showing, most important first. Never empty: a quiet
    /// day says so rather than leaving a hole at the top of Home. PURE.
    static func rank(_ facts: Facts, limit: Int = 3) -> [HomeInsight] {
        let candidates: [HomeInsight?] = [
            watch(facts), diary(facts), trip(facts), moves(facts), tasks(facts), readiness(facts),
            vitals(facts), rings(facts), steps(facts), flows(facts), games(facts), messages(facts),
            daydream(facts), news(facts),
        ]
        let order = HomeInsight.Source.allCases
        let ranked = candidates.compactMap { $0 }.sorted { a, b in
            a.weight != b.weight ? a.weight > b.weight
                : (order.firstIndex(of: a.source) ?? 0) < (order.firstIndex(of: b.source) ?? 0)
        }
        guard !ranked.isEmpty else {
            return [HomeInsight(source: .calm, figure: nil, text: "All quiet",
                                detail: "Nothing needs you right now", tone: .good, weight: 0)]
        }
        return Array(ranked.prefix(limit))
    }

    // MARK: - The family

    static func watch(_ f: Facts) -> HomeInsight? {
        guard let item = f.watch.first(where: \.alert) ?? f.watch.first else { return nil }
        return HomeInsight(source: .watch, figure: nil, text: item.title, detail: item.detail.isEmpty ? nil : item.detail,
                           tone: item.alert ? .bad : .warn, weight: item.alert ? 96 : 70)
    }

    /// The next thing in the owner's diary that means leaving soon.
    static func diary(_ f: Facts) -> HomeInsight? {
        let soon = f.diary
            .filter { $0.start > f.now && $0.start.timeIntervalSince(f.now) <= 12 * 3600 }
            .sorted { ($0.leaveBy ?? $0.start) < ($1.leaveBy ?? $1.start) }
        for item in soon {
            let starts = "Starts \(clock(item.start, f.zone))" + (item.place.map { " · \($0)" } ?? "")
            if let leave = item.leaveBy {
                let minutes = Int((leave.timeIntervalSince(f.now) / 60).rounded())
                if minutes <= 0 {
                    return HomeInsight(source: .diary, figure: "Now", text: "time to leave for \(item.title)",
                                       detail: starts, tone: .warn, weight: 97)
                }
                if minutes <= 120 {
                    return HomeInsight(source: .diary, figure: clock(leave, f.zone), text: "leave for \(item.title)",
                                       detail: "In \(duration(minutes)) · " + starts.lowercasedFirst,
                                       tone: minutes <= 15 ? .warn : .plain, weight: 92 - Double(minutes) / 4)
                }
            } else if item.start.timeIntervalSince(f.now) <= 3 * 3600 {
                return HomeInsight(source: .diary, figure: clock(item.start, f.zone), text: item.title,
                                   detail: item.place, tone: .plain, weight: 55)
            }
        }
        return nil
    }

    /// The soonest move somebody is due to make in the next four hours.
    static func moves(_ f: Facts) -> HomeInsight? {
        let due = f.moves
            .filter { $0.leaveAt > f.now.addingTimeInterval(-600) && $0.leaveAt.timeIntervalSince(f.now) <= 4 * 3600 }
            .sorted { $0.leaveAt < $1.leaveAt }
        guard let move = due.first else { return nil }
        let who = move.isSelf ? "You" : move.name
        let minutes = Int((move.leaveAt.timeIntervalSince(f.now) / 60).rounded())
        if move.arriving {
            let at = move.arriveFrom ?? move.leaveAt
            return HomeInsight(source: .moves, figure: clock(at, f.zone), text: "\(who) \(move.isSelf ? "arrive" : "arrives") at \(move.to)",
                               detail: "On the way now", tone: .plain, weight: 76)
        }
        if minutes <= 0 {
            return HomeInsight(source: .moves, figure: "Due", text: "\(who) to leave for \(move.to)",
                               detail: "Usually \(clock(move.leaveAt, f.zone))", tone: .warn, weight: 72)
        }
        return HomeInsight(source: .moves, figure: clock(move.leaveAt, f.zone),
                           text: "\(who) \(move.isSelf ? "leave" : "leaves") for \(move.to)",
                           detail: "In \(duration(minutes))", tone: .plain, weight: max(45, 82 - Double(minutes) / 4))
    }

    static func trip(_ f: Facts) -> HomeInsight? {
        guard let trip = f.trip else { return nil }
        if trip.days == nil {
            guard let stop = trip.nextStop else { return nil }
            if let leave = trip.leaveInMinutes {
                if leave <= 0 {
                    return HomeInsight(source: .trip, figure: "Now", text: "time to go to \(stop)",
                                       detail: trip.place, tone: .warn, weight: 95)
                }
                if leave <= 90 {
                    return HomeInsight(source: .trip, figure: "\(leave) min", text: "until you leave for \(stop)",
                                       detail: trip.place, tone: .plain, weight: 93 - Double(leave) / 3)
                }
            }
            return HomeInsight(source: .trip, figure: nil, text: "Next: \(stop)", detail: trip.place, tone: .plain, weight: 50)
        }
        guard let days = trip.days, days >= 1, days <= 30 else { return nil }
        let asked = trip.questions > 0
            ? "\(trip.questions) quick question\(trip.questions == 1 ? "" : "s") to answer" : nil
        let weight = 40 + (days <= 3 ? 20 : days <= 7 ? 10 : 0) + (asked == nil ? 0 : 15)
        return HomeInsight(source: .trip, figure: days == 1 ? "1 day" : "\(days) days", text: "until \(trip.place)",
                           detail: asked, tone: .plain, weight: Double(weight))
    }

    // MARK: - The boards

    static func tasks(_ f: Facts) -> HomeInsight? {
        guard let t = f.tasks else { return nil }
        if t.overdue > 0 {
            return HomeInsight(source: .tasks, figure: "\(t.overdue)", text: t.overdue == 1 ? "task overdue" : "tasks overdue",
                               detail: t.overdueTitle, tone: .bad, weight: 86)
        }
        if t.parent && t.awaiting > 0 {
            return HomeInsight(source: .tasks, figure: "\(t.awaiting)", text: "done, waiting for you to confirm",
                               detail: nil, tone: .warn, weight: 68)
        }
        if t.toDo > 0 {
            let next = t.nextTitle.map { title in "Next: \(title)" + (t.nextDue.map { " · \($0)" } ?? "") }
            let dueToday = t.nextDue?.lowercased().hasPrefix("today") ?? false
            return HomeInsight(source: .tasks, figure: "\(t.toDo)", text: t.toDo == 1 ? "task to do" : "tasks to do",
                               detail: next, tone: .plain, weight: dueToday ? 56 : 44)
        }
        if t.parent && t.owedPence > 0 {
            return HomeInsight(source: .tasks, figure: money(t.owedPence), text: "owed in rewards",
                               detail: nil, tone: .plain, weight: 38)
        }
        return nil
    }

    /// The race from the caller's seat, with how long a walk would close it.
    static func steps(_ f: Facts) -> HomeInsight? {
        guard let mine = f.steps.first(where: \.me) else { return nil }
        let others = f.steps.filter { !$0.me }
        guard let leader = others.max(by: { $0.steps < $1.steps }) else {
            return HomeInsight(source: .steps, figure: grouped(mine.steps), text: "steps today",
                               detail: nil, tone: .plain, weight: 26)
        }
        let place = (f.steps.filter { $0.steps > mine.steps }.count) + 1
        if leader.steps == mine.steps {
            return HomeInsight(source: .steps, figure: "Level", text: "with \(leader.name) on steps",
                               detail: "\(grouped(mine.steps)) each", tone: .plain, weight: 52)
        }
        if mine.steps > leader.steps {
            let gap = mine.steps - leader.steps
            return HomeInsight(source: .steps, figure: "1st", text: "on steps, \(grouped(gap)) ahead of \(leader.name)",
                               detail: "\(grouped(mine.steps)) today", tone: .good, weight: gap < 500 ? 58 : 46)
        }
        let gap = leader.steps - mine.steps
        let minutes = max(1, Int((Double(gap) / stepsPerMinute).rounded(.up)))
        let detail = minutes <= 90
            ? "About \(duration(minutes)) of walking to draw level"
            : "\(ordinal(place)) of \(f.steps.count) · \(grouped(mine.steps)) so far"
        return HomeInsight(source: .steps, figure: grouped(gap), text: "steps behind \(leader.name)",
                           detail: detail, tone: .plain, weight: gap <= 3000 ? 62 : 42)
    }

    static func messages(_ f: Facts) -> HomeInsight? {
        guard let m = f.message, !m.mine else { return nil }
        let minutes = Int((f.now.timeIntervalSince(m.at) / 60).rounded())
        guard minutes >= 0, minutes <= 180 else { return nil }
        return HomeInsight(source: .messages, figure: nil, text: m.line,
                           detail: minutes < 1 ? "Just now" : "\(duration(minutes)) ago",
                           tone: .plain, weight: max(40, 60 - Double(minutes) / 6))
    }

    static func games(_ f: Facts) -> HomeInsight? {
        guard let first = f.invites.first else { return nil }
        let n = f.invites.count
        return HomeInsight(source: .games, figure: "\(n)", text: n == 1 ? "game invite" : "game invites",
                           detail: "\(first.host) wants to play \(first.game)", tone: .plain, weight: 66)
    }

    // MARK: - Health

    /// Readiness only when it says something: a low morning, or a high one.
    static func readiness(_ f: Facts) -> HomeInsight? {
        guard let r = f.readiness else { return nil }
        let score = Int(r.score.rounded())
        let advice = firstSentence(r.recommendation)
        if score < 40 {
            return HomeInsight(source: .readiness, figure: "\(score)", text: "readiness · \(r.label.lowercased())",
                               detail: advice, tone: .bad, weight: 84, figureKey: nil)
        }
        if score >= 80 {
            return HomeInsight(source: .readiness, figure: "\(score)", text: "readiness · \(r.label.lowercased())",
                               detail: advice, tone: .good, weight: 60, figureKey: nil)
        }
        return nil
    }

    /// The figure that moved furthest from the person's own week, as a share
    /// of where the week sat. Under 4% is noise and says nothing.
    static func vitals(_ f: Facts) -> HomeInsight? {
        var best: (vital: Vital, share: Double, delta: Double)?
        for vital in f.vitals where vital.value > 0 {
            guard let delta = vital.delta, delta != 0 else { continue }
            let baseline = vital.value - delta
            guard baseline != 0 else { continue }
            let share = abs(delta) / abs(baseline)
            if share >= 0.04, share > (best?.share ?? 0) { best = (vital, share, delta) }
        }
        guard let best else { return nil }
        let size = magnitude(best.vital.deltaDisplay) ?? trimmed(abs(best.delta))
        let side = best.delta > 0 ? "above" : "below"
        let tone: HomeInsight.Tone = best.vital.improving == true ? .good : best.vital.improving == false ? .warn : .plain
        // Never past an imminent departure: 71 at most, 75 for a slip.
        let weight = 50 + min(best.share, 0.3) * 70 + (best.vital.improving == false ? 4 : 0)
        return HomeInsight(source: .vitals, figure: best.vital.shown, text: "\(best.vital.label), \(size) \(side) your week",
                           detail: best.vital.improving == true ? "Going the right way" : best.vital.improving == false ? "Worth watching" : nil,
                           tone: tone, weight: weight, figureKey: best.vital.key)
    }

    /// The Move ring: how much is left, pressed harder late in the day when
    /// it is within reach.
    static func rings(_ f: Facts) -> HomeInsight? {
        guard let move = f.rings.first(where: { $0.key == "move" }), move.goal > 0 else { return nil }
        let percent = Int((move.fraction * 100).rounded())
        let others = f.rings.filter { $0.key != "move" && $0.goal > 0 }
        if move.fraction >= 1 {
            if !others.isEmpty, others.allSatisfy({ $0.fraction >= 1 }) {
                return HomeInsight(source: .rings, figure: "\(others.count + 1)", text: "rings closed today",
                                   detail: "Move at \(percent)%", tone: .good, weight: 58)
            }
            let open = others.first { $0.fraction < 1 }.map { ringLeft($0) }
            return HomeInsight(source: .rings, figure: "\(percent)%", text: "Move ring closed",
                               detail: open, tone: .good, weight: 46)
        }
        let left = max(1, Int((move.goal - move.value).rounded()))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = f.zone
        let hour = calendar.component(.hour, from: f.now)
        let weight: Double = hour >= 15 && percent >= 50 ? 72 : percent >= 80 ? 66 : 36
        let exercise = others.first { $0.key == "exercise" }.map { " · Exercise \(Int($0.value.rounded()))/\(Int($0.goal.rounded())) \($0.unit)" } ?? ""
        return HomeInsight(source: .rings, figure: "\(left) \(move.unit)", text: "to close your Move ring",
                           detail: "\(percent)% there" + exercise, tone: .plain, weight: weight)
    }

    // MARK: - The owner's site

    static func flows(_ f: Facts) -> HomeInsight? {
        guard !f.failingFlows.isEmpty else { return nil }
        let n = f.failingFlows.count
        return HomeInsight(source: .flows, figure: "\(n)", text: n == 1 ? "flow failing" : "flows failing",
                           detail: f.failingFlows.prefix(2).joined(separator: ", "), tone: .bad, weight: 80)
    }

    static func daydream(_ f: Facts) -> HomeInsight? {
        guard f.toDecide > 0 else { return nil }
        return HomeInsight(source: .daydream, figure: "\(f.toDecide)", text: "to decide in Daydream",
                           detail: f.decideTitle, tone: .plain, weight: 46)
    }

    static func news(_ f: Facts) -> HomeInsight? {
        guard f.newsUnseen > 0 else { return nil }
        return HomeInsight(source: .news, figure: "\(f.newsUnseen)", text: "new on the news desk",
                           detail: f.topStory, tone: .plain, weight: 24)
    }

    // MARK: - Words

    /// "08:10" in the phone's zone. Twenty-four hour: the app's clocks are.
    static func clock(_ date: Date, _ zone: TimeZone) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_GB_POSIX")
        format.timeZone = zone
        format.dateFormat = "HH:mm"
        return format.string(from: date)
    }

    /// "25 min", "1 h", "1 h 10 min".
    static func duration(_ minutes: Int) -> String {
        let m = max(0, minutes)
        if m < 60 { return "\(m) min" }
        let h = m / 60, rest = m % 60
        return rest == 0 ? "\(h) h" : "\(h) h \(rest) min"
    }

    /// 12,300 — grouped the British way, whatever the phone's region.
    static func grouped(_ n: Int) -> String {
        let digits = String(abs(n))
        var out = ""
        for (index, char) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { out.append(",") }
            out.append(char)
        }
        return n < 0 ? "-" + out : out
    }

    /// "£2.50".
    static func money(_ pence: Int) -> String {
        String(format: "£%d.%02d", pence / 100, pence % 100)
    }

    static func ordinal(_ n: Int) -> String {
        let tens = (n / 10) % 10
        if tens == 1 { return "\(n)th" }
        switch n % 10 {
        case 1: return "\(n)st"
        case 2: return "\(n)nd"
        case 3: return "\(n)rd"
        default: return "\(n)th"
        }
    }

    /// "+18m vs 7d" → "18m"; "−2 vs 7d" → "2". Nil when there is nothing
    /// left once the sign and the window are gone.
    static func magnitude(_ deltaDisplay: String?) -> String? {
        guard var text = deltaDisplay else { return nil }
        if let range = text.range(of: " vs ") { text = String(text[..<range.lowerBound]) }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "+-−±— ").union(.whitespaces))
        return text.isEmpty ? nil : text
    }

    /// 5 → "5", 0.3 → "0.3".
    static func trimmed(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    static func firstSentence(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let end = trimmed.firstIndex(where: { ".!?".contains($0) }) {
            return String(trimmed[...end])
        }
        return trimmed
    }

    /// "Exercise 12 min to go".
    static func ringLeft(_ ring: Ring) -> String {
        "\(ring.label) \(max(1, Int((ring.goal - ring.value).rounded()))) \(ring.unit) to go"
    }
}

private extension String {
    /// "Starts 14:00" → "starts 14:00".
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
