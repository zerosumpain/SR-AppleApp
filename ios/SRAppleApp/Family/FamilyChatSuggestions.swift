import Foundation

// msg family's landing (John, 2026-10-27: "improve the landing screen for
// family chat — make it more interesting and useful"): the family as it is
// now, what came in while you were away, and two or three things worth
// saying at this moment. The rules are here; the view is `FamilyChatLanding`.
//
// Foundation only, beside `FamilyMessageTools`, so every rule is a unit test
// the Linux harness runs (`scripts/home-check.sh`). The view turns the family
// view, the forecast, the step board and the threads into the plain values
// below; nothing here reads a store.

/// Who is around, and what came in since msg family was last open.
enum FamilyChatNow {
    /// One person as the landing reads them, from their household card and
    /// the Orbit's measure of them.
    struct Person: Equatable {
        var subject: String
        /// Their first name, as an "@" names them.
        var name: String
        /// "home", "out", "unknown" (not heard from lately) or "off" (not sharing).
        var status: String
        /// Where the site places them: "School", "Bethesda Terrace". Nil for nowhere named.
        var place: String? = nil
        /// How far from home, when the Orbit could measure it.
        var km: Double? = nil
        /// Home by the Orbit's rule: the site says so, or they are inside its radius.
        var atHome = false
        /// "walking", "active" or "vehicle" while on the move.
        var moving: String? = nil
        var battery: Int? = nil
        var lastSeen: Date? = nil
        /// When the forecast has them arriving home, if it has.
        var homeBy: Date? = nil
    }

    /// What the landing writes under a person's circle.
    struct Status: Equatable {
        /// "Home", "School", "Out · 2.1 km", "Walking", "Not sharing".
        let line: String
        /// A second, smaller fact: "Home ~17:40", "2h ago".
        let detail: String?
        /// The battery, when it is low enough to mark.
        let lowBattery: Int?
        /// Not sharing, or not heard from lately: drawn quieter.
        let quiet: Bool
        /// All of it as a sentence, for VoiceOver.
        let spoken: String
    }

    /// The app's own line for a low battery (`BatteryReading.isLow`).
    static let lowBattery = 20
    /// How far ahead a forecast arrival is worth saying. Further out it is
    /// a routine, not news.
    static let homeByWindow: TimeInterval = 2 * 3600

    /// The status under a person's circle. PURE.
    ///
    /// Where they are comes first, in the fewest words: home; on the move
    /// (they are between places, so a place would be stale); the place the
    /// site names; otherwise how far out. The smaller line under it is when
    /// the forecast has them home, if that is within two hours, or how long
    /// since the site last heard from somebody it has lost.
    static func status(_ p: Person, now: Date, calendar: Calendar = .current) -> Status {
        // Not sharing: nothing else about them is known, and nothing is guessed.
        if p.status == "off" {
            return Status(line: "Not sharing", detail: nil, lowBattery: nil, quiet: true,
                          spoken: "\(p.name), not sharing their location")
        }
        let home = p.atHome || p.status == "home"
        let lost = p.status == "unknown"
        let (line, said) = whereabouts(p, home: home, lost: lost)

        var detail: String?
        var spokenDetail: String?
        if !home, let by = p.homeBy, by > now, by.timeIntervalSince(now) <= homeByWindow {
            detail = "Home ~\(clock(by, calendar: calendar))"
            spokenDetail = "due home about \(clock(by, calendar: calendar))"
        } else if lost, let seen = p.lastSeen {
            detail = ago(seen, now: now)
            spokenDetail = "seen \(ago(seen, now: now))"
        }
        let low = p.battery.flatMap { (0...lowBattery).contains($0) ? $0 : nil }
        let spoken = ([p.name, said, spokenDetail, low.map { "battery \($0)%, low" }] as [String?])
            .compactMap { $0 }.joined(separator: ", ")
        return Status(line: line, detail: detail, lowBattery: low, quiet: lost, spoken: spoken)
    }

    /// The status line, and the same said aloud.
    private static func whereabouts(_ p: Person, home: Bool, lost: Bool) -> (line: String, said: String) {
        let named = p.place.flatMap { $0.isEmpty || $0 == "Out" || $0 == "Home" ? nil : $0 }
        if home { return ("Home", "at home") }
        // Somebody the site has lost is not moving now, whatever their last fix said.
        if let moving = p.moving, !lost {
            let verb = moving == "walking" ? "walking" : moving == "vehicle" ? "travelling" : "on the move"
            return (verb.prefix(1).uppercased() + verb.dropFirst(), verb)
        }
        if let named { return (named, lost ? "last seen at \(named)" : "at \(named)") }
        if lost { return ("Not seen lately", "not seen lately") }
        if let km = p.km, km > 0 { return ("Out · \(distance(km))", "out, \(distance(km)) from home") }
        return ("Out", "out")
    }

    /// What came in since msg family was last open: how many lines from
    /// other people, and whose.
    struct Missed: Equatable {
        let count: Int
        /// "3 new since 08:10 — Katie, Fintan".
        let text: String
    }

    /// "3 new since 08:10 — Katie, Fintan". Lines count as the unread badge
    /// on Home and Chat counts them (`FamilyMessageTools.unread`), so the
    /// number that brought somebody here is the number they find. Names in
    /// the order they wrote, three at most. Nil when nothing came in. PURE.
    static func missed(_ threads: [FamilyChatSuggestions.Thread], since: Date?, now: Date,
                       calendar: Calendar = .current) -> Missed? {
        let lines = threads.flatMap(\.lines)
        let count = FamilyMessageTools.unread(lines.map { (at: $0.at, mine: $0.mine) }, since: since)
        guard count > 0 else { return nil }
        let fresh = lines.filter { line in
            guard !line.mine, let at = line.at else { return false }
            return since.map { at > $0 } ?? true
        }.sorted { ($0.at ?? .distantPast) < ($1.at ?? .distantPast) }
        let names = fresh.reduce(into: [String]()) { out, line in if !out.contains(line.from) { out.append(line.from) } }
        let who = names.prefix(3).joined(separator: ", ") + (names.count > 3 ? " +\(names.count - 3)" : "")
        let when = since.map { " since \(sinceWords($0, now: now, calendar: calendar))" } ?? ""
        return Missed(count: count, text: "\(count) new\(when)" + (who.isEmpty ? "" : " — \(who)"))
    }

    // MARK: - Words

    /// "08:10" today, "yesterday 21:40", "Mon 18:20" within the week, "12 Oct" before.
    static func sinceWords(_ date: Date, now: Date, calendar: Calendar) -> String {
        let day = FamilyMessageTools.dayTitle(date, now: now, calendar: calendar)
        let time = clock(date, calendar: calendar)
        switch day {
        case "Today": return time
        case "Yesterday": return "yesterday \(time)"
        default:
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 99
            return days < 7 ? "\(day.prefix(3)) \(time)" : format(date, "d MMM", calendar: calendar)
        }
    }

    /// "400 m", "2.1 km", "14 km".
    static func distance(_ km: Double) -> String {
        if km < 1 { return "\(max(50, Int((km * 1000 / 50).rounded()) * 50)) m" }
        return String(format: km < 10 ? "%.1f km" : "%.0f km", km)
    }

    /// "45m ago", "2h ago", "3d ago".
    static func ago(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 3600 { return "\(max(1, Int(seconds / 60)))m ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h ago" }
        return "\(Int(seconds / 86_400))d ago"
    }

    static func clock(_ date: Date, calendar: Calendar) -> String { format(date, "HH:mm", calendar: calendar) }

    private static func format(_ date: Date, _ pattern: String, calendar: Calendar) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_GB")
        format.timeZone = calendar.timeZone
        format.dateFormat = pattern
        return format.string(from: date)
    }
}

/// Two or three things worth saying right now, each a tap from the box.
enum FamilyChatSuggestions {
    /// A thread as the rules read it.
    struct Thread: Equatable {
        let id: String
        /// The sender's first name.
        let from: String
        let body: String
        let at: Date?
        let mine: Bool
        var replies: [Line] = []

        /// The message and every reply, oldest first.
        var lines: [Line] { [Line(from: from, body: body, at: at, mine: mine)] + replies }
        var lastAt: Date? { lines.compactMap(\.at).max() }
    }

    struct Line: Equatable {
        let from: String
        let body: String
        let at: Date?
        let mine: Bool
    }

    /// One person on today's step board.
    struct Walker: Equatable {
        let name: String
        let steps: Int
        let me: Bool
    }

    struct Suggestion: Equatable, Identifiable {
        enum Action: Equatable {
            /// Words for the box. Nothing is sent until Send.
            case fill(String)
            /// The poll sheet, already written, waiting for Send.
            case poll(question: String, options: [String])
            /// A thread to answer in.
            case open(thread: String)
        }

        /// Which rule made it — steady across refreshes, and the end of its
        /// accessibility identifier.
        let id: String
        let title: String
        /// Why now, in a few words.
        let reason: String
        /// An SF Symbol's name: a string, so the rules stay Foundation-only.
        let symbol: String
        let action: Action
    }

    /// The suggestions, most pressing first: three at most, two while there
    /// is something new to read (the summary of it takes the room). PURE.
    ///
    /// In order:
    /// 1. Somebody waiting on you — see `reply`.
    /// 2. Late in the evening (21:30–01:00) with somebody still out: "Home
    ///    safe, Kit?", or "Everyone home safe?" for more than one.
    /// 3. Somebody out on a low battery (the app's 20%): a nudge to charge.
    /// 4. The time of day — see `starter`.
    /// 5. Today's step leader, once it is worth a word (5,000 steps), unless
    ///    the leader is you.
    /// 6. A chat nobody has written in for a day: say hello.
    ///
    /// `people` is everybody but you. `me` is your first name, for mentions.
    static func make(now: Date, people: [FamilyChatNow.Person], me: String?, threads: [Thread], steps: [Walker],
                     unreadCount: Int, lastActivity: Date?, calendar: Calendar = .current) -> [Suggestion] {
        let candidates: [Suggestion?] = [
            reply(threads, me: me, now: now),
            homeSafe(people, now: now, calendar: calendar),
            battery(people),
            starter(now: now, people: people, threads: threads, calendar: calendar),
            stepLeader(steps),
            quiet(lastActivity: lastActivity, now: now, calendar: calendar),
        ]
        return Array(candidates.compactMap { $0 }.prefix(unreadCount > 0 ? 2 : 3))
    }

    // MARK: - The rules

    /// Somebody waiting on you, the most direct first:
    /// - a line that @mentions you, in the last 12 hours, newer than anything
    ///   you have said in that thread;
    /// - a poll from somebody else in the last day that you have not voted in;
    /// - a question from somebody else that nobody has answered at all, once
    ///   it has had 20 minutes for the first answer (up to 12 hours).
    /// Each opens the thread. One at most: the newest thread wins a tie.
    static func reply(_ threads: [Thread], me: String?, now: Date) -> Suggestion? {
        let recent = threads.sorted { ($0.lastAt ?? .distantPast) > ($1.lastAt ?? .distantPast) }
        func age(_ at: Date?) -> TimeInterval? { at.map { now.timeIntervalSince($0) } }

        if let me, !me.isEmpty {
            for thread in recent {
                let saidLast = thread.lines.filter(\.mine).compactMap(\.at).max() ?? .distantPast
                let asked = thread.lines.last { line in
                    guard !line.mine, let at = line.at, let old = age(at), old >= -300, old <= 12 * 3600 else { return false }
                    return at > saidLast && FamilyMessageTools.mentions(line.body, name: me)
                }
                if let asked {
                    return Suggestion(id: "reply", title: "Reply to \(asked.from)", reason: quote(asked.body),
                                      symbol: "arrowshape.turn.up.left", action: .open(thread: thread.id))
                }
            }
        }
        for thread in recent where !thread.mine {
            guard let poll = FamilyPoll.parse(thread.body), let old = age(thread.at), old <= 24 * 3600 else { continue }
            if !thread.replies.contains(where: { $0.mine && poll.option(of: $0.body) != nil }) {
                return Suggestion(id: "vote", title: "Vote in \(thread.from)'s poll", reason: poll.question,
                                  symbol: "chart.bar", action: .open(thread: thread.id))
            }
        }
        for thread in recent where !thread.mine && thread.replies.isEmpty && thread.body.contains("?") {
            guard FamilyPoll.parse(thread.body) == nil, let old = age(thread.at), old >= 20 * 60, old <= 12 * 3600 else { continue }
            return Suggestion(id: "answer", title: "Answer \(thread.from)", reason: "\(quote(thread.body)) · no replies yet",
                              symbol: "questionmark.bubble", action: .open(thread: thread.id))
        }
        return nil
    }

    /// Late in the evening, whoever is still out. Somebody the site has lost
    /// (not heard from lately) somewhere other than home counts as out: that
    /// is exactly when you would ask.
    static func homeSafe(_ people: [FamilyChatNow.Person], now: Date, calendar: Calendar) -> Suggestion? {
        guard lateEvening(now, calendar: calendar) else { return nil }
        let out = people.filter(isOut).map(\.name)
        guard let first = out.first else { return nil }
        if out.count == 1 {
            return Suggestion(id: "home-safe", title: "Home safe, \(first)?", reason: "\(first) is still out",
                              symbol: "house", action: .fill("@\(first) are you home safe?"))
        }
        return Suggestion(id: "home-safe", title: "Everyone home safe?", reason: "\(list(out)) are still out",
                          symbol: "house", action: .fill("Everyone home safe?"))
    }

    /// The lowest battery among people out, at or under the app's low line.
    /// At home a phone can be charged without being told.
    static func battery(_ people: [FamilyChatNow.Person]) -> Suggestion? {
        let low = people.filter(isOut)
            .compactMap { p -> (person: FamilyChatNow.Person, pct: Int)? in
                guard let pct = p.battery, pct >= 0, pct <= FamilyChatNow.lowBattery else { return nil }
                return (p, pct)
            }
            .min { $0.pct < $1.pct }
        guard let person = low?.person, let pct = low?.pct else { return nil }
        let place = person.place.flatMap { $0.isEmpty || $0 == "Out" ? nil : " at \($0)" } ?? ""
        return Suggestion(id: "battery", title: "\(person.name)'s battery is low", reason: "\(pct)%\(place)",
                          symbol: "battery.25percent",
                          action: .fill("@\(person.name) your battery's on \(pct)% — charge up if you can 🔋"))
    }

    /// The time of day:
    /// - Friday 12:00–15:00 and Saturday 07:00–11:00: "Plans for the weekend?"
    /// - otherwise 06:30–09:30: "Anything on today?"
    /// - 12:00–15:00: "Who's in tonight?"
    /// - 15:00–18:30: "Dinner tonight?" as a poll, unless dinner has already
    ///   come up today — then the family is on it.
    /// - 21:30–midnight, with everybody home: "Night all".
    static func starter(now: Date, people: [FamilyChatNow.Person], threads: [Thread], calendar: Calendar) -> Suggestion? {
        let parts = calendar.dateComponents([.hour, .minute, .weekday], from: now)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        // Gregorian weekdays: 1 is Sunday, 6 Friday, 7 Saturday.
        let weekday = parts.weekday ?? 0
        func between(_ from: Int, _ to: Int) -> Bool { minute >= from && minute < to }

        if (weekday == 6 && between(12 * 60, 15 * 60)) || (weekday == 7 && between(7 * 60, 11 * 60)) {
            return Suggestion(id: "weekend", title: "Plans for the weekend?", reason: weekday == 6 ? "It's Friday" : "It's Saturday",
                              symbol: "calendar", action: .fill("Plans for the weekend?"))
        }
        if between(6 * 60 + 30, 9 * 60 + 30) {
            return Suggestion(id: "today", title: "Anything on today?", reason: "Plans for the day",
                              symbol: "sun.max", action: .fill("Anything on today?"))
        }
        if between(12 * 60, 15 * 60) {
            return Suggestion(id: "tonight", title: "Who's in tonight?", reason: "Plan the evening",
                              symbol: "person.3", action: .fill("Who's in tonight?"))
        }
        if between(15 * 60, 18 * 60 + 30) {
            guard !dinnerTalk(threads, now: now, calendar: calendar) else { return nil }
            return Suggestion(id: "dinner", title: "Dinner tonight?", reason: "Ask as a poll before teatime",
                              symbol: "fork.knife",
                              action: .poll(question: "Dinner tonight?", options: ["I'm in", "Late — save me some", "Not tonight"]))
        }
        if minute >= 21 * 60 + 30, !people.contains(where: isOut) {
            return Suggestion(id: "night", title: "Night all 🌙", reason: "Everyone's home",
                              symbol: "moon.stars", action: .fill("Night all 🌙"))
        }
        return nil
    }

    /// Today's leader on the step board, by name and count.
    static func stepLeader(_ steps: [Walker]) -> Suggestion? {
        // `max(by:)` keeps the first of a tie: the board's own "got there first".
        guard let top = steps.max(by: { $0.steps < $1.steps }), !top.me, top.steps >= 5000 else { return nil }
        let count = grouped(top.steps)
        return Suggestion(id: "steps", title: "Well done \(top.name) — \(count) steps", reason: "Top of today's step board",
                          symbol: "figure.walk", action: .fill("Well done \(top.name) — \(count) steps today! 👟"))
    }

    /// Nobody has written for a day, or ever.
    static func quiet(lastActivity: Date?, now: Date, calendar: Calendar) -> Suggestion? {
        guard let last = lastActivity else {
            return Suggestion(id: "hello", title: "Say hello", reason: "No messages yet",
                              symbol: "hand.wave", action: .fill("Hi all 👋"))
        }
        guard now.timeIntervalSince(last) >= 86_400 else { return nil }
        let day = FamilyMessageTools.dayTitle(last, now: now, calendar: calendar)
        return Suggestion(id: "hello", title: "Say hello", reason: "Quiet since \(day == "Yesterday" ? "yesterday" : day)",
                          symbol: "hand.wave", action: .fill("Hi all 👋 How's everyone doing?"))
    }

    // MARK: - Pieces

    /// Out, by the household's own word, or lost somewhere other than home.
    static func isOut(_ p: FamilyChatNow.Person) -> Bool {
        guard !p.atHome, p.status != "home", p.status != "off" else { return false }
        if p.status == "out" { return true }
        return p.status == "unknown" && (p.place.map { !$0.isEmpty && $0 != "Home" } ?? false)
    }

    /// 21:30 to 01:00.
    static func lateEvening(_ now: Date, calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return minute >= 21 * 60 + 30 || minute < 60
    }

    /// Whether anybody has said a dinner word today — in a message, a reply or a poll.
    static func dinnerTalk(_ threads: [Thread], now: Date, calendar: Calendar) -> Bool {
        let words: Set<String> = ["dinner", "tea", "teatime", "supper", "takeaway", "pizza", "chippy"]
        return threads.flatMap(\.lines).contains { line in
            guard let at = line.at, calendar.isDate(at, inSameDayAs: now) else { return false }
            return line.body.lowercased().split(whereSeparator: { !$0.isLetter }).contains { words.contains(String($0)) }
        }
    }

    /// "Kit", "Kit and Sam", "Kit, Sam and Alex".
    static func list(_ names: [String]) -> String {
        guard names.count > 1, let last = names.last else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }

    /// A message's words on one line, in quotes, cut to fit a card.
    static func quote(_ body: String, limit: Int = 44) -> String {
        let flat = body.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return "\u{201C}" + (flat.count > limit ? String(flat.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…" : flat) + "\u{201D}"
    }

    /// "11,204".
    static func grouped(_ n: Int) -> String {
        let format = NumberFormatter()
        format.locale = Locale(identifier: "en_GB")
        format.numberStyle = .decimal
        return format.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
