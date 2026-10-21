import Foundation

// "Share → SR → Add to a trip" (v8, plan §5.2): a web page, a place or a
// booking line shared from another app becomes one turn of the trip's
// planning conversation, and the v8 planner turns it into a proposal or a
// question on the trip.
//
// SHARED with the share extension (`SRAppleShare`, see watch.yml), like
// `FamilyBacklogShared.swift`: Foundation only, nothing of the app's. The
// extension reads the trips list itself — thinly, these fields and no more —
// with the site credential the app leaves on the Keychain shelf. That shelf
// holds it exactly while this person may see the family's pages (the owner,
// or the family, over the site), which is the same rule Trips has, so "Add
// to a trip" is offered to precisely the people who can open the trips.

/// A trip a share can go to: one row of `GET /api/native/trips`, read thinly.
struct TripShareTarget: Decodable, Equatable, Identifiable {
    let id: String
    let title: String
    let destination: String
    let timeZone: String
    let startDate: String
    let endDate: String
    /// draft, planned, active, done. Kept as text: a status this build does
    /// not know must not hide a trip.
    let status: String?
}

struct TripShareList: Decodable {
    let trips: [TripShareTarget]
}

/// `POST /api/native/trips/:id/converse` — started as a job (`async`) and
/// left to run: the planner's answer lands on the trip, not in the sheet.
struct TripShareTurn: Encodable, Equatable {
    let text: String
    let async: Bool
}

enum TripShare {
    /// The longest turn sent: a shared page's text can be a whole article.
    static let maxText = 1200

    /// Trips still to come or running now, in their own time zones — the
    /// ones a share can still change — soonest first. A finished trip is not
    /// offered.
    static func targets(_ trips: [TripShareTarget], now: Date) -> [TripShareTarget] {
        trips
            .filter { $0.status != "done" && $0.endDate >= localDate(now, zone: $0.timeZone) }
            .sorted { ($0.startDate, $0.title) < ($1.startDate, $1.title) }
    }

    /// "Rome long weekend · 26–30 Oct" — a trip in the picker.
    static func label(_ trip: TripShareTarget) -> String {
        guard let dates = range(trip.startDate, trip.endDate) else { return trip.title }
        return "\(trip.title) · \(dates)"
    }

    /// What the planner is told: the page's title (or the shared words) and
    /// the link, then the person's own note. Nil when there is nothing.
    static func turn(url: URL?, text: String?, note: String?) -> String? {
        var words = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let link = url?.absoluteString
        if let link, words.contains(link) { words = words.replacingOccurrences(of: link, with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
        var parts = [words, link ?? ""].filter { !$0.isEmpty }
        if parts.isEmpty { return nil }
        if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty { parts.append("— \(note)") }
        let joined = parts.joined(separator: " ")
        return joined.count > maxText ? String(joined.prefix(maxText)) : joined
    }

    /// `YYYY-MM-DD` now, in a trip's own zone.
    static func localDate(_ now: Date, zone identifier: String) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier) ?? .current
        let d = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", d.year ?? 0, d.month ?? 0, d.day ?? 0)
    }

    /// "26–30 Oct", "30 Oct – 2 Nov", "26 Oct".
    static func range(_ start: String, _ end: String) -> String? {
        guard let a = parts(start), let b = parts(end) else { return nil }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        guard (1...12).contains(a.month), (1...12).contains(b.month) else { return nil }
        if start == end { return "\(a.day) \(months[a.month - 1])" }
        if a.year == b.year && a.month == b.month { return "\(a.day)–\(b.day) \(months[b.month - 1])" }
        return "\(a.day) \(months[a.month - 1]) – \(b.day) \(months[b.month - 1])"
    }

    private static func parts(_ local: String) -> (year: Int, month: Int, day: Int)? {
        let p = local.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return (p[0], p[1], p[2])
    }
}
