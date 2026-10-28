import Foundation

// Trips on the Home Screen and the Lock Screen: on a trip day, the next stop
// and when to leave for it; otherwise how long until the next trip. What the
// app leaves on the Keychain shelf (`FamilyShelf`, account `.trips`) and
// every rule about it as a pure function.
//
// SHARED with the widget extension (`SRAppleLive`, see watch.yml), so nothing
// here may reach for the app: no `TripStore`, no `PlannedDay`, no
// `TripClock`. Foundation only, so the Linux harness runs its tests
// (`scripts/home-check.sh`).
//
// The app works out what comes next — `TripStore.progressToTell`, the same
// answer the Lock Screen card (`TripLive`) gives — and leaves the rest of the
// day's plan behind it with real instants, so the widget can move on to the
// following stop by itself as the planned arrivals pass, with no fetch.

// MARK: - What the shelf holds

/// One stop still to come on a trip day.
struct TripsWidgetStop: Codable, Equatable {
    var title: String
    /// When to leave for it. Nil for the day's first stop (the stay).
    var leaveAt: Date?
    /// When the plan arrives there.
    var arriveAt: Date
    /// "walk", "cycle", "drive", "transit", "taxi".
    var legMode: String?
    var legMinutes: Int?
    /// 1-based: "Stop 3 of 7".
    var number: Int
}

struct TripsWidgetSnapshot: Codable, Equatable {
    enum Kind: String, Codable {
        /// A trip day: `stops` holds what is still to come.
        case running
        /// The next trip, not started yet.
        case upcoming
    }

    var kind: Kind
    var tripId: String
    var title: String
    var destination: String?
    /// The trip's own zone, IANA. Every time the widget prints is on the
    /// trip's clock, as the plan is.
    var timeZone: String
    var startDate: String
    var endDate: String
    /// Running: the day it is about, `YYYY-MM-DD`.
    var date: String?
    var stops: [TripsWidgetStop]
    /// Running: how many stops the whole day has.
    var stopCount: Int
    /// Running: the end of the day's plan — the last arrival and half an
    /// hour (`TripLive.isOn`).
    var dayEndsAt: Date?
    var savedAt: Date

    func sameContent(as other: TripsWidgetSnapshot?) -> Bool {
        guard var other else { return false }
        other.savedAt = savedAt
        return other == self
    }
}

// MARK: - Rules

enum TripsWidget {
    /// The most stops a snapshot carries ahead: the medium widget shows the
    /// next and the two after it.
    static let keep = 6

    /// What a widget draws at one moment.
    enum Face: Equatable {
        /// Heading for `stop` next; `after` are the ones following it.
        case next(stop: TripsWidgetStop, after: [TripsWidgetStop])
        /// A trip day with nothing more planned.
        case dayDone
        /// The next trip starts in `days` (0 is today).
        case countdown(days: Int)
        /// Nothing to show: the snapshot has run out. Open the app.
        case none
    }

    /// The face at `now`. A stop whose planned arrival has passed is behind
    /// you, so the widget moves on to the one after it without the app.
    static func face(_ snapshot: TripsWidgetSnapshot?, now: Date) -> Face {
        guard let snapshot else { return .none }
        switch snapshot.kind {
        case .running:
            let ahead = snapshot.stops.filter { $0.arriveAt > now }
            if let first = ahead.first { return .next(stop: first, after: Array(ahead.dropFirst())) }
            if let end = snapshot.dayEndsAt, now <= end { return .dayDone }
            // Still the trip's day on its own clock: nothing more planned.
            if let date = snapshot.date, localDate(now, zone: snapshot.timeZone) == date { return .dayDone }
            return .none
        case .upcoming:
            guard let days = daysUntil(snapshot.startDate, now: now, zone: snapshot.timeZone), days >= 0 else { return .none }
            return .countdown(days: days)
        }
    }

    /// Whole days from today to `date`, both on the trip's clock.
    static func daysUntil(_ date: String, now: Date, zone: String) -> Int? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .current
        guard let start = components(date).flatMap({ calendar.date(from: $0) }) else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: start).day
    }

    /// "Today", "Tomorrow", "In 12 days".
    static func countdown(_ days: Int) -> String {
        switch days {
        case ..<1: return "Today"
        case 1: return "Tomorrow"
        default: return "In \(days) days"
        }
    }

    /// "14:05", on the trip's clock.
    static func time(_ date: Date, zone: String) -> String {
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_GB")
        out.timeZone = TimeZone(identifier: zone) ?? .current
        out.dateFormat = "HH:mm"
        return out.string(from: date)
    }

    /// "Leave by 14:05"; "Leave now" for two minutes; "Due 14:20" once on
    /// the way; "Arrive 10:30" for a stop with no leg before it. Said the
    /// same way at any distance: the widget's own timer counts the minutes
    /// down.
    static func leave(_ stop: TripsWidgetStop, now: Date, zone: String) -> String {
        guard let leaveAt = stop.leaveAt else { return "Arrive \(time(stop.arriveAt, zone: zone))" }
        if leaveAt <= now { return now.timeIntervalSince(leaveAt) < 120 ? "Leave now" : "Due \(time(stop.arriveAt, zone: zone))" }
        return "Leave by \(time(leaveAt, zone: zone))"
    }

    /// "12 min walk", "25 min by transit".
    static func leg(_ stop: TripsWidgetStop) -> String? {
        guard let mode = stop.legMode, let minutes = stop.legMinutes else { return nil }
        let how: String
        switch mode {
        case "walk": how = "walk"
        case "cycle": how = "cycle"
        case "drive": how = "drive"
        case "transit": how = "by transit"
        case "taxi": how = "by taxi"
        default: how = mode
        }
        return "\(max(1, minutes)) min \(how)"
    }

    static func symbol(_ mode: String?) -> String {
        switch mode {
        case "walk": return "figure.walk"
        case "cycle": return "bicycle"
        case "drive": return "car.fill"
        case "transit": return "tram.fill"
        case "taxi": return "car.side.fill"
        default: return "mappin.and.ellipse"
        }
    }

    /// "Day 3 of 7". Nil outside the trip.
    static func dayLine(_ snapshot: TripsWidgetSnapshot) -> String? {
        guard let date = snapshot.date,
              let day = days(from: snapshot.startDate, to: date),
              let total = days(from: snapshot.startDate, to: snapshot.endDate) else { return nil }
        return "Day \(day + 1) of \(total + 1)"
    }

    /// "3–10 Nov", "28 Oct – 2 Nov", for a trip that has not started.
    static func range(_ start: String, _ end: String) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let a = components(start).flatMap({ calendar.date(from: $0) }),
              let b = components(end).flatMap({ calendar.date(from: $0) }) else { return start }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_GB")
        out.timeZone = calendar.timeZone
        out.dateFormat = "d MMM"
        if start == end { return out.string(from: a) }
        let sameMonth = calendar.component(.month, from: a) == calendar.component(.month, from: b)
        if sameMonth {
            return "\(calendar.component(.day, from: a))–\(out.string(from: b))"
        }
        return "\(out.string(from: a)) – \(out.string(from: b))"
    }

    /// When the face changes on its own: each planned departure (the timer
    /// starts) and arrival (the next stop moves up), the day's end, and the
    /// next midnights on the trip's clock (the countdown ticks). Sorted,
    /// from `now`, and always reaching at least an hour ahead so a
    /// timeline that asks again at its end does not ask at once.
    static func timeline(_ snapshot: TripsWidgetSnapshot?, now: Date, limit: Int = 24) -> [Date] {
        var dates: Set<Date> = [now]
        if let snapshot {
            for stop in snapshot.stops {
                if let leave = stop.leaveAt { dates.insert(leave) }
                dates.insert(stop.arriveAt)
            }
            if let end = snapshot.dayEndsAt { dates.insert(end) }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: snapshot.timeZone) ?? .current
            if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
                dates.insert(midnight)
            }
        }
        var out = dates.filter { $0 >= now }.sorted()
        if let last = out.last, last < now.addingTimeInterval(3600) { out.append(now.addingTimeInterval(6 * 3600)) }
        return Array(out.prefix(max(limit, 2)))
    }

    /// Where a tap goes: the day running (`sr://trips/<id>/<date>`), else the
    /// trip, else the list — `TripLink`'s own shapes.
    static func url(_ snapshot: TripsWidgetSnapshot?) -> URL {
        guard let snapshot else { return URL(string: "sr://trips")! }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/%?#")
        let id = snapshot.tripId.addingPercentEncoding(withAllowedCharacters: allowed) ?? snapshot.tripId
        if snapshot.kind == .running, let date = snapshot.date, let url = URL(string: "sr://trips/\(id)/\(date)") {
            return url
        }
        return URL(string: "sr://trips/\(id)") ?? URL(string: "sr://trips")!
    }

    // MARK: Dates

    static func localDate(_ date: Date, zone: String) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .current
        let d = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", d.year ?? 0, d.month ?? 0, d.day ?? 0)
    }

    static func days(from a: String, to b: String) -> Int? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let x = components(a).flatMap({ calendar.date(from: $0) }),
              let y = components(b).flatMap({ calendar.date(from: $0) }) else { return nil }
        return calendar.dateComponents([.day], from: x, to: y).day
    }

    static func components(_ date: String) -> DateComponents? {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return DateComponents(year: parts[0], month: parts[1], day: parts[2])
    }
}

// MARK: - Samples

/// A made-up trip for the widget's placeholder and the gallery.
enum TripsWidgetSamples {
    static func running(now: Date = Date()) -> TripsWidgetSnapshot {
        let zone = TimeZone.current.identifier
        func at(_ minutes: Double) -> Date { now.addingTimeInterval(minutes * 60) }
        let today = TripsWidget.localDate(now, zone: zone)
        return TripsWidgetSnapshot(
            kind: .running, tripId: "sample", title: "Rome", destination: "Rome, Italy", timeZone: zone,
            startDate: today, endDate: today, date: today,
            stops: [
                TripsWidgetStop(title: "Pantheon", leaveAt: at(18), arriveAt: at(30), legMode: "walk", legMinutes: 12, number: 3),
                TripsWidgetStop(title: "Lunch at Da Enzo", leaveAt: at(95), arriveAt: at(110), legMode: "transit", legMinutes: 15, number: 4),
                TripsWidgetStop(title: "Villa Borghese", leaveAt: at(190), arriveAt: at(215), legMode: "walk", legMinutes: 25, number: 5),
            ],
            stopCount: 7, dayEndsAt: at(400), savedAt: now
        )
    }

    static func upcoming(now: Date = Date()) -> TripsWidgetSnapshot {
        let zone = TimeZone.current.identifier
        let start = TripsWidget.localDate(now.addingTimeInterval(12 * 86_400), zone: zone)
        let end = TripsWidget.localDate(now.addingTimeInterval(17 * 86_400), zone: zone)
        return TripsWidgetSnapshot(
            kind: .upcoming, tripId: "sample", title: "Lisbon", destination: "Lisbon, Portugal", timeZone: zone,
            startDate: start, endDate: end, date: nil, stops: [], stopCount: 0, dayEndsAt: nil, savedAt: now
        )
    }
}
