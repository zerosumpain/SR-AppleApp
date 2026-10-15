import Foundation

/// Getting ready for a trip (v7, proposal D): when each thing must be booked
/// by — from what the research found it sells out ("about 14 days ahead") —
/// and the evening-before briefing for each day. Worked out from the saved
/// trip; the reminders are scheduled on the phone (`TripReminders`).
///
/// Foundation only: the Linux harness compiles and tests it.
enum TripBookAhead {
    struct Item: Equatable, Identifiable {
        var id: String
        var title: String
        /// The day it is planned on, if it is.
        var visitDate: String?
        /// The last good day to book (visit − sells-out days), if known.
        var bookBy: String?
        var aheadDays: Int?
        var url: String?
        var overdue: Bool
    }

    /// Everything still to book, soonest deadline first: each wish that
    /// needs booking and has no booked booking, and each to-book booking.
    static func items(_ bundle: TripBundle, today: String, clock: TripClock) -> [Item] {
        let booked = Set(bundle.bookings.filter { $0.status == .booked }.compactMap(\.wishId))
        var planned: [String: String] = [:]
        for day in bundle.plan?.plan.days ?? [] {
            for stop in day.stops { if let w = stop.wishId, planned[w] == nil { planned[w] = day.date } }
        }
        var out: [Item] = []
        var seen: Set<String> = []
        for wish in bundle.wishes where !wish.skipped && !wish.suggested && !booked.contains(wish.id) {
            let facts = wish.facts
            let toBook = bundle.bookings.first { $0.wishId == wish.id && $0.status == .toBook }
            guard facts?.bookingRequired == true || toBook != nil else { continue }
            let visit = planned[wish.id] ?? wish.fixedDate ?? toBook?.date
            let ahead = facts?.bookAheadDays.map { Int($0.rounded()) }
            let by = visit.flatMap { v in ahead.flatMap { clock.adding(days: -$0, to: v) } }
            seen.insert(wish.id)
            out.append(Item(
                id: "wish:\(wish.id)", title: wish.title, visitDate: visit, bookBy: by, aheadDays: ahead,
                url: toBook?.url ?? facts?.bookingUrl ?? facts?.officialUrl,
                overdue: by.map { $0 < today } ?? false
            ))
        }
        for b in bundle.bookings where b.status == .toBook && !(b.wishId.map(seen.contains) ?? false) {
            out.append(Item(id: "booking:\(b.id)", title: b.title, visitDate: b.date, bookBy: nil, aheadDays: nil, url: b.url, overdue: false))
        }
        return out.sorted { ($0.bookBy ?? $0.visitDate ?? "9999") < ($1.bookBy ?? $1.visitDate ?? "9999") }
    }
}

enum TripBriefing {
    /// "First: Colosseum at 09:10 · 5 stops · 19° / 12° · Partly cloudy ·
    /// rain likely 15:00–18:00 · sunset 17:11". Said the evening before.
    static func line(day: PlannedDay, weather: TripForecast.Day?, sun: TripSun.Day?) -> String {
        var parts: [String] = []
        let visits = day.stops.filter { $0.kind == .wish }
        if let first = visits.first {
            parts.append("First: \(first.title) at \(clock(first.arriveMin))")
        }
        if visits.count > 1 { parts.append("\(visits.count) stops") }
        if let weather {
            parts.append(TripWeatherWords.line(weather))
            if let rain = TripWeatherWords.rain(weather, fromMin: day.stops.first?.departMin ?? 480, toMin: day.stops.last?.arriveMin ?? 1320) {
                parts.append(rain.prefix(1).lowercased() + rain.dropFirst())
            }
        }
        if let set = sun?.sunsetMin { parts.append("sunset \(clock(set))") }
        return parts.joined(separator: " · ")
    }

    static func clock(_ min: Double) -> String {
        let m = Int(min.rounded())
        return String(format: "%02d:%02d", (m / 60) % 24, m % 60)
    }
}

/// The phone's own trip reminders, as a pure plan (what should be pending).
enum TripReminderPlan {
    static let prefix = "trip-plan:"

    struct Planned: Equatable {
        let id: String
        /// Local date and minute in the trip's zone.
        let date: String
        let minute: Double
        let title: String
        let body: String
        let tripId: String
        /// The day a tap opens.
        let opens: String?
    }

    /// The evening before each day still to come (19:00), and two days before
    /// each booking deadline (09:00) — or the next morning when that is past.
    static func plan(_ bundle: TripBundle, today: String, nowMin: Double, clock: TripClock,
                     weather: TripForecast?, sun: (String) -> TripSun.Day?,
                     words: (String) -> String = { $0 }, nudged: Set<String> = []) -> [Planned] {
        var out: [Planned] = []
        let city = bundle.trip.destination.split(separator: ",").first.map(String.init) ?? bundle.trip.destination
        for day in bundle.plan?.plan.days ?? [] where day.date > today {
            guard let eve = clock.adding(days: -1, to: day.date) else { continue }
            if eve == today && nowMin >= 19 * 60 { continue }
            if eve < today { continue }
            out.append(Planned(
                id: "\(prefix)eve|\(bundle.trip.id)|\(day.date)", date: eve, minute: 19 * 60,
                title: "Tomorrow in \(city)", body: TripBriefing.line(day: day, weather: weather?.day(day.date), sun: sun(day.date)),
                tripId: bundle.trip.id, opens: day.date
            ))
        }
        for item in TripBookAhead.items(bundle, today: today, clock: clock) {
            guard let by = item.bookBy, let visit = item.visitDate, visit >= today else { continue }
            var date = clock.adding(days: -2, to: by) ?? by
            var minute = 9.0 * 60
            let id = "\(prefix)book|\(bundle.trip.id)|\(item.id)"
            if date < today || (date == today && nowMin >= minute) {
                // Late already: tomorrow morning — ONCE (`nudged` remembers it),
                // not every morning until the visit.
                if nudged.contains(id) { continue }
                guard let next = clock.adding(days: 1, to: today) else { continue }
                date = next
                minute = 9 * 60
            }
            out.append(Planned(
                id: id, date: date, minute: minute,
                title: item.overdue ? "Book \(item.title) now" : "Book \(item.title) by \(words(by))",
                body: "It sells out about \(item.aheadDays ?? 0) days ahead, and it's planned for \(words(visit)).",
                tripId: bundle.trip.id, opens: visit
            ))
        }
        return out
    }
}
