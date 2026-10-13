import Foundation

/// Local dates and minutes in a trip's own time zone.
///
/// A trip to Rome is planned in Rome time whatever zone the phone is set to:
/// a plan that says 14:20 means 14:20 on the Pantheon's clock. Every
/// conversion between a plan time and a real instant goes through here, with
/// the trip's IANA zone, never `TimeZone.current`.
///
/// Foundation only: the Linux harness compiles it with the solver port.
struct TripClock {
    let zone: TimeZone

    init(_ identifier: String) {
        zone = TimeZone(identifier: identifier) ?? .current
    }

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c
    }

    /// `YYYY-MM-DD` for an instant, in the trip's zone.
    func localDate(_ date: Date) -> String {
        let d = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", d.year ?? 0, d.month ?? 0, d.day ?? 0)
    }

    /// Minutes after local midnight, fractional.
    func minutes(_ date: Date) -> Double {
        let start = calendar.startOfDay(for: date)
        return date.timeIntervalSince(start) / 60
    }

    /// The instant a plan time names. Across a clock change the calendar
    /// resolves the hour as the trip's own clocks would.
    func date(_ localDate: String, minutes: Double) -> Date? {
        guard let midnight = Self.components(localDate).flatMap({ calendar.date(from: $0) }) else { return nil }
        let whole = Int(minutes.rounded(.down))
        let hm = DateComponents(hour: whole / 60, minute: whole % 60, second: Int(((minutes - Double(whole)) * 60).rounded()))
        return calendar.date(byAdding: hm, to: midnight)
    }

    /// ISO weekday, 1 (Mon) … 7 (Sun), of a local date — the key of `TripFacts.hours`.
    func isoWeekday(_ localDate: String) -> Int? {
        guard let midnight = Self.components(localDate).flatMap({ calendar.date(from: $0) }) else { return nil }
        let w = calendar.component(.weekday, from: midnight) // 1 = Sunday
        return w == 1 ? 7 : w - 1
    }

    static func components(_ localDate: String) -> DateComponents? {
        let parts = localDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 0)
    }

    /// Whether `date` (local) lies in `[start, end]`. ISO dates sort as strings.
    static func within(_ date: String, _ start: String, _ end: String) -> Bool {
        start <= date && date <= end
    }

    /// The next local date, `YYYY-MM-DD`.
    func adding(days: Int, to start: String) -> String? {
        guard let midnight = Self.components(start).flatMap({ calendar.date(from: $0) }),
              let next = calendar.date(byAdding: .day, value: days, to: midnight) else { return nil }
        return self.localDate(next)
    }

    /// Days from `a` to `b`, both local dates.
    func days(from a: String, to b: String) -> Int? {
        guard let da = Self.components(a).flatMap({ calendar.date(from: $0) }),
              let db = Self.components(b).flatMap({ calendar.date(from: $0) }) else { return nil }
        return calendar.dateComponents([.day], from: da, to: db).day
    }
}

/// How plan figures are said: "14:20", "12 min", "1 h 05".
enum TripFormat {
    /// "14:20" from local minutes. Past midnight wraps ("00:30"), as a clock would.
    static func time(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        let wrapped = ((m % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", wrapped / 60, wrapped % 60)
    }

    /// "12 min", "1 h", "1 h 05".
    static func duration(minutes: Double) -> String {
        let m = max(0, Int(minutes.rounded()))
        if m < 60 { return "\(m) min" }
        return m % 60 == 0 ? "\(m / 60) h" : String(format: "%d h %02d", m / 60, m % 60)
    }

    static func duration(seconds: Double) -> String { duration(minutes: seconds / 60) }

    static func mode(_ mode: TravelMode) -> String {
        switch mode {
        case .walk: return "walk"
        case .cycle: return "cycle"
        case .drive: return "drive"
        case .transit: return "by transit"
        }
    }

    /// "12 min walk", "25 min by transit".
    static func leg(_ leg: PlannedLeg) -> String {
        "\(duration(seconds: leg.durationSec)) \(mode(leg.mode))"
    }

    static func symbol(_ mode: TravelMode) -> String {
        switch mode {
        case .walk: return "figure.walk"
        case .cycle: return "bicycle"
        case .drive: return "car.fill"
        case .transit: return "tram.fill"
        }
    }

    /// "Tue 14 Oct" for a local date, in en-GB.
    static func day(_ localDate: String, zone: TimeZone) -> String {
        guard let parts = TripClock.components(localDate) else { return localDate }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard let date = calendar.date(from: parts) else { return localDate }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = zone
        f.dateFormat = "EEE d MMM"
        return f.string(from: date)
    }

    /// "14–17 Oct" or "30 Oct – 2 Nov".
    static func range(_ start: String, _ end: String, zone: TimeZone) -> String {
        guard let a = TripClock.components(start), let b = TripClock.components(end) else { return "\(start) – \(end)" }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let am = months[max(0, min(11, (a.month ?? 1) - 1))], bm = months[max(0, min(11, (b.month ?? 1) - 1))]
        if start == end { return "\(a.day ?? 0) \(am)" }
        if a.month == b.month && a.year == b.year { return "\(a.day ?? 0)–\(b.day ?? 0) \(bm)" }
        return "\(a.day ?? 0) \(am) – \(b.day ?? 0) \(bm)"
    }
}
