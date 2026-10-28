import Foundation

// "Family now" on the Home Screen and the Lock Screen: who is home, who is
// out, who is on the move, and how much battery they have left — what the
// app leaves on the Keychain shelf (`FamilyShelf`, account `.familyNow`) and
// every rule about it as a pure function.
//
// SHARED with the widget extension (`SRAppleLive`, see watch.yml), so nothing
// here may reach for the app: no `HouseholdView`, no `FamilyPerson`, no
// `SR`. Foundation only, so the Linux harness runs its tests
// (`scripts/home-check.sh`).
//
// Privacy-minimal on purpose. The household view carries positions, trails
// and whole days; the shelf gets a first name, the household's initials, a
// colour slot, the place the site named, a distance from home rounded to
// what a glance needs, a battery level and when they were last heard from.
// No coordinates, no subjects, no trails. The widget cannot fetch the view
// itself — it comes over the companion pairing, whose credential never
// leaves the app — so it is exactly as fresh as the app's last read.

// MARK: - What the shelf holds

/// Where somebody is, as the widget says it.
enum FamilyNowState: String, Codable, Equatable {
    case home
    case out
    /// On the move right now (the site's `moving`): walking, travelling.
    case moving
    /// Sharing, but not heard from lately.
    case unseen
    /// Not sharing their location.
    case off
}

/// One person on the widget.
struct FamilyNowPerson: Codable, Equatable, Identifiable {
    /// Their circle's letters, unique across the household
    /// (`HouseholdView.initials`), which is also what keeps rows apart.
    var initials: String
    /// First name only.
    var name: String
    var isSelf: Bool
    var state: FamilyNowState
    /// "walking", "active" or "vehicle" while `moving`; nil otherwise.
    var mode: String?
    /// The place the site named: "Home", "School". Nil for nowhere named.
    var place: String?
    /// From home, when the app knows where home is. Rounded to 0.1 km.
    var km: Double?
    var battery: Int?
    /// When the site last heard from them.
    var seenAt: Date?
    /// Their colour's slot in the palette's people (`SR.PersonHue`): the
    /// widget paints it in the reader's palette, so a palette change
    /// repaints the circles without another snapshot.
    var hue: Int

    var id: String { initials }
}

/// What the app leaves on the shelf each time it reads a family view that
/// changed.
struct FamilyNowSnapshot: Codable, Equatable {
    var people: [FamilyNowPerson]
    var savedAt: Date

    /// Equal but for when it was saved — so an unchanged view costs neither
    /// a Keychain write nor a widget reload.
    func sameContent(as other: FamilyNowSnapshot?) -> Bool {
        guard var other else { return false }
        other.savedAt = savedAt
        return other == self
    }
}

// MARK: - Rules

enum FamilyNow {
    /// The most people the shelf keeps: the medium widget shows four, the
    /// small one's ring holds eight.
    static let keep = 8

    /// One person as the app reads them, before the rules: the site's own
    /// words (`status` is "home", "out", "unknown" or "off").
    struct Input: Equatable {
        var name: String
        var initials: String
        var isSelf: Bool
        var status: String
        var movingMode: String?
        var place: String?
        var km: Double?
        var battery: Int?
        var lastSeenAt: String?
        var hue: Int

        init(name: String, initials: String, isSelf: Bool = false, status: String, movingMode: String? = nil,
             place: String? = nil, km: Double? = nil, battery: Int? = nil, lastSeenAt: String? = nil, hue: Int = 0) {
            self.name = name
            self.initials = initials
            self.isSelf = isSelf
            self.status = status
            self.movingMode = movingMode
            self.place = place
            self.km = km
            self.battery = battery
            self.lastSeenAt = lastSeenAt
            self.hue = hue
        }
    }

    /// The shelf's snapshot of a household. PURE.
    static func snapshot(_ people: [Input], now: Date = Date(), keep: Int = FamilyNow.keep) -> FamilyNowSnapshot {
        let made = people.map { input -> FamilyNowPerson in
            let state = state(status: input.status, moving: input.movingMode != nil)
            // Nothing about where somebody is when they are not sharing: the
            // site sends no position, and the shelf keeps no old one.
            let sharing = state != .off
            return FamilyNowPerson(
                initials: input.initials.isEmpty ? "?" : input.initials,
                name: firstName(input.name),
                isSelf: input.isSelf,
                state: state,
                mode: state == .moving ? input.movingMode : nil,
                place: sharing ? input.place : nil,
                km: sharing ? input.km.map { ($0 * 10).rounded() / 10 } : nil,
                battery: sharing ? input.battery.map { min(max($0, 0), 100) } : nil,
                seenAt: sharing ? input.lastSeenAt.flatMap(date) : nil,
                hue: max(input.hue, 0)
            )
        }
        return FamilyNowSnapshot(people: Array(ordered(made).prefix(max(keep, 0))), savedAt: now)
    }

    /// The site's status and whether they are on the move, as one state.
    /// Moving wins over "out" and "home": a phone leaving the drive is still
    /// "home" on the site for a minute.
    static func state(status: String, moving: Bool) -> FamilyNowState {
        if status == "off" { return .off }
        if moving { return .moving }
        switch status {
        case "home": return .home
        case "out": return .out
        default: return .unseen
        }
    }

    /// You first, then whoever is moving, out, home, not seen, not sharing —
    /// the site's order within each. A glance wants what is happening.
    static func ordered(_ people: [FamilyNowPerson]) -> [FamilyNowPerson] {
        func rank(_ p: FamilyNowPerson) -> Int {
            if p.isSelf { return 0 }
            switch p.state {
            case .moving: return 1
            case .out: return 2
            case .home: return 3
            case .unseen: return 4
            case .off: return 5
            }
        }
        return people.enumerated().sorted { a, b in
            let x = rank(a.element), y = rank(b.element)
            return x == y ? a.offset < b.offset : x < y
        }.map(\.element)
    }

    static func count(_ snapshot: FamilyNowSnapshot, _ state: FamilyNowState) -> Int {
        snapshot.people.filter { $0.state == state }.count
    }

    /// "3 home · 1 out · 1 moving" — only what somebody is. "Nobody yet" for
    /// an empty household.
    static func counts(_ snapshot: FamilyNowSnapshot) -> String {
        let words: [(FamilyNowState, String)] = [(.home, "home"), (.out, "out"), (.moving, "moving")]
        let parts = words.compactMap { state, word -> String? in
            let n = count(snapshot, state)
            return n > 0 ? "\(n) \(word)" : nil
        }
        if parts.isEmpty { return snapshot.people.isEmpty ? "Nobody yet" : "Nobody placed" }
        return parts.joined(separator: " · ")
    }

    /// "walking", "on the move", "travelling" — the site's band, said.
    static func verb(_ mode: String?) -> String {
        switch mode {
        case "walking": return "Walking"
        case "vehicle": return "Travelling"
        default: return "On the move"
        }
    }

    static func symbol(_ person: FamilyNowPerson) -> String {
        switch person.state {
        case .home: return "house.fill"
        case .out: return "mappin"
        case .moving:
            switch person.mode {
            case "walking": return "figure.walk"
            case "vehicle": return "car.fill"
            default: return "figure.run"
            }
        case .unseen: return "questionmark"
        case .off: return "location.slash"
        }
    }

    /// "350 m", "2.4 km", "12 km" from home. Nil for nothing to say: no
    /// distance, or so close it is home.
    static func distance(_ km: Double?) -> String? {
        guard let km, km >= 0.1 else { return nil }
        if km < 1 { return "\(Int((km * 1000 / 50).rounded()) * 50) m" }
        return km < 10 ? String(format: "%.1f km", km) : String(format: "%.0f km", km)
    }

    /// The row's line: "Home", "School · 2.4 km", "Walking · 1.2 km from
    /// home", "Last at the Park", "Not sharing".
    static func line(_ person: FamilyNowPerson) -> String {
        let away = distance(person.km)
        switch person.state {
        case .home:
            return "Home"
        case .out:
            let place = person.place.flatMap { $0 == "Home" ? nil : $0 }
            if let place, let away { return "\(place) · \(away)" }
            if let place { return place }
            return away.map { "\($0) from home" } ?? "Out"
        case .moving:
            let lead = verb(person.mode)
            return away.map { "\(lead) · \($0) from home" } ?? lead
        case .unseen:
            if let place = person.place { return place == "Home" ? "Last at home" : "Last at \(place)" }
            return "Not seen lately"
        case .off:
            return "Not sharing"
        }
    }

    /// How old the last word from them is: "now", "5m", "2h", "Mon".
    static func seen(_ person: FamilyNowPerson, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard person.state != .off, let at = person.seenAt else { return nil }
        return FamilyMessagesWidget.when(at, now: now, calendar: calendar)
    }

    /// More than two hours since the site heard from them: their circle is
    /// drawn faded, as the Orbit's edge says it (`FamilyPerson.Freshness`).
    static func isStale(_ person: FamilyNowPerson, now: Date = Date()) -> Bool {
        guard person.state != .off else { return true }
        guard let at = person.seenAt else { return person.state == .unseen }
        return now.timeIntervalSince(at) >= 2 * 3600
    }

    /// Low is a fact worth colour; the rest is not (`BatteryReading`).
    static func isLow(_ battery: Int?) -> Bool { (battery ?? 100) <= 20 }

    static func batterySymbol(_ pct: Int) -> String {
        switch pct {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    /// "You", or their first name.
    static func who(_ person: FamilyNowPerson) -> String { person.isSelf ? "You" : person.name }

    /// One person, read out: "Robin, walking, 1.2 km from home, battery 18
    /// percent, low, seen 5m ago".
    static func spoken(_ person: FamilyNowPerson, now: Date = Date()) -> String {
        var parts = [who(person), line(person)]
        if let battery = person.battery {
            parts.append("battery \(battery) percent" + (isLow(battery) ? ", low" : ""))
        }
        if let seen = seen(person, now: now) { parts.append(seen == "now" ? "seen just now" : "seen \(seen) ago") }
        return parts.joined(separator: ", ")
    }

    static func firstName(_ name: String) -> String {
        name.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? name
    }

    /// The site's timestamps: ISO 8601, with or without fractions.
    static func date(_ iso: String) -> Date? { FamilyMessagesWidget.date(iso) }
}

// MARK: - Links

/// Where the glance widgets lead in the app, beyond the pages that already
/// have a link of their own (`FamilyPage`, `TripLink`, `BatPhoneURL`).
/// `sr://family` is the Family tab; `sr://games` the Games tab, and
/// `sr://games/<room>?game=<kind>` one room in it; `sr://health` the Health
/// tab. PURE.
enum GlanceLink: Equatable {
    case family
    case games(room: String?, game: String?)
    case health

    static let familyURL = URL(string: "sr://family")!
    static let gamesURL = URL(string: "sr://games")!
    static let healthURL = URL(string: "sr://health")!

    static func gameURL(room: String, game: String?) -> URL {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/%?#")
        var parts = URLComponents()
        parts.scheme = "sr"
        parts.host = "games"
        parts.percentEncodedPath = "/" + (room.addingPercentEncoding(withAllowedCharacters: allowed) ?? room)
        if let game, !game.isEmpty { parts.queryItems = [URLQueryItem(name: "game", value: game)] }
        return parts.url ?? gamesURL
    }

    /// Nil for anything that is not one of these. `sr://family/<page>` is
    /// `FamilyPage`'s: only the bare tab is matched here.
    static func from(url: URL) -> GlanceLink? {
        guard url.scheme?.lowercased() == "sr" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        switch url.host?.lowercased() {
        case "family":
            return parts.isEmpty ? .family : nil
        case "health":
            return .health
        case "games":
            let game = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "game" }?.value
            return .games(room: parts.first, game: (game?.isEmpty ?? true) ? nil : game)
        default:
            return nil
        }
    }
}

// MARK: - Samples

/// A made-up family for the widget's placeholder and the gallery. The repo
/// is public: made-up names only.
enum FamilyNowWidgetSamples {
    static func snapshot(now: Date = Date()) -> FamilyNowSnapshot {
        func ago(_ minutes: Double) -> String {
            ISO8601DateFormatter().string(from: now.addingTimeInterval(-minutes * 60))
        }
        return FamilyNow.snapshot([
            .init(name: "You", initials: "Yo", isSelf: true, status: "home", battery: 64, lastSeenAt: ago(1), hue: 0),
            .init(name: "Robin", initials: "Ro", status: "out", movingMode: "walking", km: 1.2, battery: 18, lastSeenAt: ago(2), hue: 1),
            .init(name: "Kit", initials: "Ki", status: "out", place: "School", km: 2.4, battery: 71, lastSeenAt: ago(6), hue: 2),
            .init(name: "Sam", initials: "Sa", status: "home", place: "Home", battery: 92, lastSeenAt: ago(14), hue: 3),
            .init(name: "Alex", initials: "Al", status: "unknown", place: "The Park", lastSeenAt: ago(190), hue: 4),
        ], now: now)
    }
}
