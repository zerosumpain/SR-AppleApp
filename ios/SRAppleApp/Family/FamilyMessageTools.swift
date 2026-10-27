import Foundation

// msg family's tools (2026-10-27): what was added on top of the plain thread
// — unread lines, polls, @mentions, day headings, search, "where I am",
// reminders, quick messages and the length counter. All of it lives on this
// phone over the site's existing message contract: a poll is a message whose
// words read as a poll to an older phone too, a vote is a reply, and what has
// been read, pinned or drafted is remembered here.
//
// Foundation only, so every rule is a unit test the Linux harness runs
// (`scripts/home-check.sh`).

/// A poll, written into a message's own words so an older phone and the
/// notification read it as plain text:
///
///     📊 Dinner tonight?
///     1️⃣ Pizza
///     2️⃣ Pasta
///
/// A vote is a reply of one marker. A person's newest vote is the one that
/// counts, so changing your mind is one more reply (the old one is taken back
/// too, but a tally never double-counts if it was not).
struct FamilyPoll: Equatable {
    let question: String
    let options: [String]

    static let mark = "📊"
    static let markers = ["1️⃣", "2️⃣", "3️⃣", "4️⃣"]
    static let maxOptions = 4

    /// A poll the composer can send: a question and two to four options,
    /// blank options dropped. Nil when there is not one yet.
    static func make(question: String, options: [String]) -> FamilyPoll? {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let o = options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !q.isEmpty, (2...maxOptions).contains(o.count) else { return nil }
        return FamilyPoll(question: q, options: o)
    }

    /// What is sent.
    var body: String {
        ([Self.mark + " " + question] + options.enumerated().map { "\(Self.markers[$0.offset]) \($0.element)" })
            .joined(separator: "\n")
    }

    /// The poll in a message's words, or nil for an ordinary message.
    static func parse(_ body: String) -> FamilyPoll? {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = lines.first, first.hasPrefix(mark) else { return nil }
        let question = first.dropFirst(mark.count).trimmingCharacters(in: .whitespaces)
        var options: [String] = []
        for (index, line) in lines.dropFirst().enumerated() {
            guard index < markers.count, line.hasPrefix(markers[index]) else { return nil }
            options.append(line.dropFirst(markers[index].count).trimmingCharacters(in: .whitespaces))
        }
        guard !question.isEmpty, (2...maxOptions).contains(options.count) else { return nil }
        return FamilyPoll(question: question, options: options)
    }

    /// Which option a reply votes for, if it is a vote.
    func option(of reply: String) -> Int? {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = Self.markers.firstIndex(of: trimmed), index < options.count else { return nil }
        return index
    }

    struct Vote: Equatable {
        /// Who: their id, or their name when an older site sent no id.
        let voter: String
        let name: String
        let body: String
        let at: Date?
        let mine: Bool
    }

    struct Count: Equatable, Identifiable {
        let option: Int
        let label: String
        let names: [String]
        let mine: Bool
        var id: Int { option }
        var votes: Int { names.count }
    }

    /// One count per option, each person's newest vote only. PURE.
    func tally(_ votes: [Vote]) -> [Count] {
        var latest: [String: (option: Int, at: Date, name: String, mine: Bool)] = [:]
        for (index, vote) in votes.enumerated() {
            guard let option = option(of: vote.body) else { continue }
            // Undated votes keep their order: the later in the list, the newer.
            let at = vote.at ?? Date(timeIntervalSince1970: Double(index))
            if let held = latest[vote.voter], held.at > at { continue }
            latest[vote.voter] = (option, at, vote.name, vote.mine)
        }
        return options.enumerated().map { index, label in
            let mine = latest.values.contains { $0.option == index && $0.mine }
            let names = latest.values.filter { $0.option == index }.sorted { $0.at < $1.at }.map(\.name)
            return Count(option: index, label: label, names: names, mine: mine)
        }
    }
}

enum FamilyMessageTools {
    // MARK: - Unread

    /// Lines from other people newer than `since` — what has come in since this
    /// phone last had msg family open. Everything counts when it never has. PURE.
    static func unread(_ items: [(at: Date?, mine: Bool)], since: Date?) -> Int {
        items.filter { item in
            guard !item.mine, let at = item.at else { return false }
            return since.map { at > $0 } ?? true
        }.count
    }

    // MARK: - Mentions

    /// The name being typed after an "@" at the end of the draft — "Sa" in
    /// "Pick up @Sa" — or nil when the draft is not mid-mention.
    static func mentionQuery(_ draft: String) -> String? {
        guard let at = draft.lastIndex(of: "@") else { return nil }
        // An "@" inside a word ("me@home") is not a mention.
        if at > draft.startIndex, let before = draft[..<at].last, !before.isWhitespace { return nil }
        let query = String(draft[draft.index(after: at)...])
        guard !query.contains(where: \.isWhitespace), query.count <= 20 else { return nil }
        return query
    }

    /// The names an "@" could mean, those starting with what was typed first. PURE.
    static func mentionCandidates(_ query: String, names: [String]) -> [String] {
        let q = query.lowercased()
        let unique = names.reduce(into: [String]()) { out, name in if !out.contains(name) { out.append(name) } }
        let starts = unique.filter { $0.lowercased().hasPrefix(q) }
        let contains = unique.filter { !$0.lowercased().hasPrefix(q) && $0.lowercased().contains(q) }
        return Array((starts + contains).prefix(6))
    }

    /// The draft with the half-typed mention finished: "Pick up @Sa" → "Pick up @Sam ".
    static func complete(_ draft: String, with name: String) -> String {
        guard let at = draft.lastIndex(of: "@") else { return draft }
        return String(draft[...at]) + name + " "
    }

    /// Whether `body` mentions `name` ("@Sam", any case, not "@Samantha").
    static func mentions(_ body: String, name: String) -> Bool {
        guard !name.isEmpty else { return false }
        let lower = body.lowercased(), target = "@" + name.lowercased()
        var search = lower.startIndex..<lower.endIndex
        while let found = lower.range(of: target, range: search) {
            let after = found.upperBound
            if after == lower.endIndex || !(lower[after].isLetter || lower[after].isNumber) { return true }
            search = after..<lower.endIndex
        }
        return false
    }

    // MARK: - Days

    /// "Today", "Yesterday", "Monday" within the week, "Mon 26 Oct" before it.
    static func dayTitle(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_GB")
        format.timeZone = calendar.timeZone
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 99
        format.dateFormat = days < 7 ? "EEEE" : "EEE d MMM"
        return format.string(from: date)
    }

    // MARK: - Search

    /// Whether every word of the query is somewhere in the texts, ignoring
    /// case and accents. An empty query matches everything. PURE.
    static func matches(_ query: String, in texts: [String]) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return true }
        let haystack = texts.joined(separator: " ")
        return words.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    // MARK: - Where I am

    /// "I'm at home", "I'm at School", "I'm 3.2 km from home" — nil when this
    /// phone has no place to say.
    static func whereIAm(atHome: Bool, place: String?, km: Double?) -> String? {
        if atHome { return "I'm at home" }
        if let place, !place.isEmpty { return "I'm at \(place)" }
        guard let km, km > 0 else { return nil }
        return km < 1 ? "I'm \(Int((km * 1000 / 50).rounded()) * 50) m from home" : String(format: "I'm %.1f km from home", km)
    }

    // MARK: - Quick messages

    /// One tap puts one in the box; nothing is sent until Send.
    static let quick = ["On my way", "Running late", "Home in 10", "Dinner's ready", "Who's in tonight?", "Love you x"]

    // MARK: - The counter

    /// How many characters are left, once it is worth saying: within the last
    /// hundred, or over (negative). Nil otherwise.
    static func remaining(_ draft: String, max: Int = 500) -> Int? {
        let left = max - draft.trimmingCharacters(in: .whitespacesAndNewlines).count
        return left <= 100 ? left : nil
    }

    // MARK: - Reminders

    enum Remind: String, CaseIterable, Identifiable {
        case hour, evening, morning
        var id: String { rawValue }
        var title: String {
            switch self {
            case .hour: return "In an hour"
            case .evening: return "This evening"
            case .morning: return "Tomorrow morning"
            }
        }
    }

    /// When a reminder goes off: an hour from now; 18:00 today (tomorrow's
    /// once today's has gone); 08:00 tomorrow. PURE.
    static func remindAt(_ choice: Remind, now: Date, calendar: Calendar = .current) -> Date {
        switch choice {
        case .hour:
            return now.addingTimeInterval(3600)
        case .evening:
            let six = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now) ?? now.addingTimeInterval(3600)
            return six > now.addingTimeInterval(15 * 60) ? six : calendar.date(byAdding: .day, value: 1, to: six) ?? six
        case .morning:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        }
    }
}
