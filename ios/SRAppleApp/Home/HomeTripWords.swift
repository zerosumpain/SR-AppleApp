import Foundation

/// How the Trips tile (and the hub's Trips door) says the next trip:
/// "in 5 days", "Rome · Mon 26 – Fri 30 Oct", "2 quick questions" — and, to
/// VoiceOver, all of it in one line: "Rome · in 5 days · 2 quick questions".
///
/// Foundation only: the Linux harness tests it with the trip models.
enum HomeTripWords {
    /// "Rome" from "Rome, Italy": the place, without the country.
    static func place(_ destination: String) -> String {
        let first = destination.split(separator: ",").first.map(String.init) ?? destination
        let trimmed = first.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? destination : trimmed
    }

    /// "Tomorrow", "in 5 days". `days` is from today to the first day, both
    /// in the trip's own zone; nil or below one says "Soon" rather than a
    /// countdown that has already run out.
    static func countdown(days: Int?) -> String {
        guard let days, days >= 1 else { return "Soon" }
        return days == 1 ? "Tomorrow" : "in \(days) days"
    }

    /// "1 quick question", "2 quick questions"; nil for none.
    static func questions(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count == 1 ? "1 quick question" : "\(count) quick questions"
    }

    /// "Mon 26 – Fri 30 Oct", or "Fri 30 Oct – Mon 2 Nov" across a month.
    static func dates(start: String, end: String) -> String? {
        guard let a = day(start), let b = day(end) else { return nil }
        let utc = TimeZone(identifier: "UTC") ?? .current
        func format(_ date: Date, _ pattern: String) -> String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_GB")
            f.timeZone = utc
            f.dateFormat = pattern
            return f.string(from: date)
        }
        if start == end { return format(a, "EEE d MMM") }
        let sameMonth = start.prefix(7) == end.prefix(7)
        return "\(format(a, sameMonth ? "EEE d" : "EEE d MMM")) – \(format(b, "EEE d MMM"))"
    }

    /// "Rome · Mon 26 – Fri 30 Oct" — the tile's caption under the countdown.
    static func caption(destination: String, start: String, end: String) -> String {
        [place(destination), dates(start: start, end: end)].compactMap { $0 }.joined(separator: " · ")
    }

    /// The whole tile in one line, as VoiceOver reads it.
    static func spoken(destination: String, days: Int?, questions count: Int) -> String {
        [place(destination), countdown(days: days), questions(count)].compactMap { $0 }.joined(separator: " · ")
    }

    /// The open questions in a trip, most important first (the server's
    /// order), as the tile counts them.
    static func openQuestions(_ bundle: TripBundle?) -> [TripQuestion] {
        (bundle?.questions ?? []).filter { $0.status == .open }
    }

    private static func day(_ local: String) -> Date? {
        guard let parts = TripClock.components(local) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar.date(from: parts)
    }
}
