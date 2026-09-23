import Foundation

/// How a raw figure from the trails endpoints reads, in en-GB.
///
/// The server sends metres, seconds and bpm and leaves the words to the phone,
/// so this is the one place those words are decided. They follow SR-Health's
/// own `lib/trails/format.ts` — a pace is "m:ss", a duration drops its hour when
/// it has none, a distance under ten km earns its second decimal place.
enum TrailFormat {

    /// Kilometres from metres, no unit. Two places under 10 km, one under 100,
    /// none above — "7.42", "42.2", "161".
    static func km(_ metres: Double) -> String {
        let km = metres / 1000
        if km >= 100 { return "\(Int(km.rounded()))" }
        return String(format: km < 10 ? "%.2f" : "%.1f", km)
    }

    /// Kilometres from kilometres — the week tile gets its total already summed.
    static func km(fromKm km: Double) -> String { self.km(km * 1000) }

    /// Whole metres, no unit.
    static func metres(_ metres: Double) -> String { "\(Int(metres.rounded()))" }

    /// "1:02:03", or "42:10" when there is no hour.
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// "1h 20m" from minutes — the week's moving total, where seconds are noise.
    static func minutes(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    /// "5:32" per km. Rounded to the second BEFORE splitting, so 5:59.6 reads
    /// 6:00 rather than 5:60.
    static func pace(_ secondsPerKm: Double) -> String {
        guard secondsPerKm.isFinite, secondsPerKm > 0 else { return "—" }
        let total = Int(secondsPerKm.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// km/h, one place, from a pace. A cyclist wants speed; the stored value is
    /// the same number either way.
    static func speed(paceSPerKm: Double) -> String {
        guard paceSPerKm.isFinite, paceSPerKm > 0 else { return "—" }
        return String(format: "%.1f", 3600 / paceSPerKm)
    }

    /// A signed percentage, "−3.2%" / "+1.0%", with a true minus sign.
    static func signedPercent(_ value: Double) -> String {
        let magnitude = String(format: "%.1f", abs(value))
        if magnitude == "0.0" { return "0.0%" }
        return (value < 0 ? "−" : "+") + magnitude + "%"
    }

    /// "PB", "2nd of 7" — or nil with nothing to rank against.
    static func rank(_ rank: Int?, of total: Int) -> String? {
        guard let rank, rank > 0, total > 1 else { return nil }
        if rank == 1 { return "PB" }
        return "\(ordinal(rank)) of \(total)"
    }

    static func ordinal(_ n: Int) -> String {
        let tens = n % 100
        let suffix: String
        if (11...13).contains(tens) {
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

    /// "22 Sep 2026, 07:12" as the workout was lived.
    ///
    /// `startDateLocal` is already in the workout's own offset, so its parts are
    /// READ rather than parsed through a Date — re-interpreting it in the
    /// phone's zone would slide an evening run abroad into the next day. The ISO
    /// instant is the fallback, shown in the phone's zone.
    static func date(local: String?, iso: String) -> String {
        if let local, let parts = localParts(local) {
            return "\(parts.day) \(monthNames[parts.month - 1]) \(parts.year), \(parts.time)"
        }
        guard let date = isoDate(iso) else { return "" }
        return fallbackFormatter.string(from: date)
    }

    /// "22 Sep 2026" from an ISO instant — an effort's day.
    static func day(_ iso: String) -> String {
        guard let date = isoDate(iso) else { return "" }
        return dayFormatter.string(from: date)
    }

    private static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    private static func localParts(_ value: String) -> (year: Int, month: Int, day: Int, time: String)? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 16 else { return nil }
        let chars = Array(trimmed)
        let separator = chars[10]
        guard separator == "T" || separator == " ",
              chars[4] == "-", chars[7] == "-", chars[13] == ":",
              let year = Int(String(chars[0..<4])),
              let month = Int(String(chars[5..<7])),
              let day = Int(String(chars[8..<10])),
              (1...12).contains(month) else { return nil }
        return (year, month, day, String(chars[11..<16]))
    }

    private static let fallbackFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "d MMM yyyy, HH:mm"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "d MMM yyyy"
        return f
    }()
}

/// What an `activityType` is called and drawn as.
///
/// SR-Health stores a normalised key (`run`, `trail_run`, `ride`, `mtb`, `hike`,
/// `walk`, `swim`, `other`); the phone contract's examples say "Running". Both
/// are read, so neither spelling ever arrives as a blank label.
enum Sport {
    static func key(_ type: String) -> String {
        let t = type.lowercased().replacingOccurrences(of: " ", with: "_")
        if t.contains("trail") { return "trail_run" }
        if t.contains("mountain") || t == "mtb" { return "mtb" }
        if t.contains("run") { return "run" }
        if t.contains("cycl") || t.contains("ride") || t.contains("bik") { return "ride" }
        if t.contains("hik") { return "hike" }
        if t.contains("walk") { return "walk" }
        if t.contains("swim") { return "swim" }
        return t.isEmpty ? "other" : t
    }

    static func label(_ type: String) -> String {
        switch key(type) {
        case "run": return "Run"
        case "trail_run": return "Trail run"
        case "ride": return "Ride"
        case "mtb": return "MTB"
        case "hike": return "Hike"
        case "walk": return "Walk"
        case "swim": return "Swim"
        case "other": return "Activity"
        default: return type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func icon(_ type: String) -> String {
        switch key(type) {
        case "run", "trail_run": return "figure.run"
        case "ride": return "figure.outdoor.cycle"
        case "mtb": return "bicycle"
        case "hike": return "figure.hiking"
        case "walk": return "figure.walk"
        case "swim": return "figure.pool.swim"
        default: return "figure.mixed.cardio"
        }
    }

    /// Runners and walkers want pace; cyclists want speed.
    static func isPace(_ type: String) -> Bool {
        ["run", "trail_run", "hike", "walk"].contains(key(type))
    }
}

/// Where a recorded activity came from, in the words the website uses.
///
/// The list now mixes outings from more than one origin — a workout the Watch
/// recorded into Apple Health, and an outing the SR app caught on its own from
/// background location — and they are not equally trustworthy. A captured walk
/// has its type guessed from speed and no elevation at all, so the owner has
/// to be able to tell at a glance which kind of row he is reading.
///
/// The server sends `source`; an older server did not send it on list rows, so
/// the id's prefix (`apple:…`, `companion:…`) stands in when it is missing.
enum ActivityOrigin {
    /// A normalised source key: `apple`, `companion`, `recorded`, `strava`,
    /// `whoop`, `manual`, or whatever unknown key arrived, lowercased.
    static func key(_ source: String?, id: String = "") -> String {
        let trimmed = source?.trimmingCharacters(in: .whitespaces) ?? ""
        let raw: String
        if !trimmed.isEmpty {
            raw = trimmed.lowercased()
        } else if id.contains(":") {
            raw = String(id.split(separator: ":").first ?? "").lowercased()
        } else {
            // No source and no prefix to read it from.
            return ""
        }
        switch raw {
        case "apple", "apple_health", "healthkit", "hae": return "apple"
        default: return raw
        }
    }

    static func label(_ key: String) -> String {
        switch self.key(key) {
        case "apple": return "Apple Health"
        case "companion": return "SR app"
        case "recorded": return "Site recorder"
        case "strava": return "Strava"
        case "whoop": return "WHOOP"
        case "manual": return "Manual"
        case "": return ""
        default: return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func icon(_ key: String) -> String {
        switch self.key(key) {
        case "apple": return "heart.fill"
        case "companion": return "location.fill"
        case "recorded": return "record.circle"
        case "strava": return "arrow.triangle.2.circlepath"
        case "whoop": return "waveform.path.ecg"
        case "manual": return "pencil"
        default: return "tray.and.arrow.down"
        }
    }

    /// One sentence on what this origin means for the figures on the screen.
    static func explanation(_ key: String) -> String? {
        switch self.key(key) {
        case "apple": return "Recorded as a workout by the Watch or phone and sent to the site through Apple Health."
        case "companion": return "Captured in the background by the SR app's movement tracking — no workout was started. The type is inferred from speed, there is no elevation, and the app keeps location for 30 days."
        case "recorded": return "Recorded live with the site's own recorder."
        case "strava": return "Synced from Strava."
        case "whoop": return "Recorded by WHOOP and synced to the site."
        case "manual": return "Entered by hand, so there is no track behind it."
        case "": return nil
        default: return "Sent to the site from \(label(key))."
        }
    }

    /// Why a duplicate of this outing is not in the list, or nil when nothing
    /// was folded into it.
    static func foldedNote(_ key: String, alsoFrom: [String]) -> String? {
        let others = folded(self.key(key), alsoFrom)
        guard !others.isEmpty else { return nil }
        if self.key(key) == "apple", others.contains("companion") {
            return "The SR app also captured this outing; the Apple Health workout is shown instead because the Watch measured it."
        }
        let names = others.map { label($0) }.joined(separator: " and ")
        return "\(names) also recorded this outing; this copy is shown instead."
    }

    /// The quiet line on a list row: "Apple Health", "Apple Health · also SR
    /// app", "SR app · captured". Empty when the origin is unknown entirely.
    static func line(_ key: String, alsoFrom: [String]) -> String {
        let primary = self.key(key)
        guard !primary.isEmpty else { return "" }
        var parts = [label(primary)]
        if primary == "companion" { parts.append("captured") }
        let others = folded(primary, alsoFrom)
        if !others.isEmpty {
            parts.append("also " + others.map { label($0) }.joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }

    /// The other origins folded into a row, normalised, once each, never the
    /// row's own origin again.
    private static func folded(_ primary: String, _ alsoFrom: [String]) -> [String] {
        var seen: [String] = []
        for other in alsoFrom.map({ key($0) }) where !other.isEmpty && other != primary && !seen.contains(other) {
            seen.append(other)
        }
        return seen
    }
}
