import Foundation
import CoreLocation

/// Where the household is, as SR-Main decided this person may see it.
///
/// Built and scoped on the site (`$lib/home/presence/app-view.ts`) and filed on
/// the companion server for this person alone — the phone asks for "my view"
/// and there is no parameter that could name anyone else's. What a card leaves
/// out is left out on the server: `today` is nil for somebody whose day is not
/// yours to see, and a person not sharing has no position, battery or time.
struct HouseholdView: Codable, Equatable {
    let generatedAt: String
    /// "owner", "household", or "none" — a household member outside the
    /// Family Circle, who gets no people, only the places to watch.
    let viewer: String
    var people: [FamilyPerson]
    /// Places whose leaving switches this phone to close tracking.
    var watch: [WatchedPlace]? = nil
    /// What this person may use in the app, from the owner's access groups on
    /// the site — and, for a member who asked, a one-time site pairing code.
    /// Nil from a site older than access groups, which `AccessPolicy` reads as
    /// "unknown". See `AccessStore`.
    var access: ViewAccess? = nil
    /// The OWNER's view only: everybody else's view, for "view as" in
    /// Settings. The site decides who gets these; the phone only offers them.
    var previewAs: [ViewPreview]? = nil

    /// Whether there is anybody to show — a "none" view is only a watch list.
    var showsHousehold: Bool { viewer != "none" }
}

/// Another app user's view, as the site filed it for them — for the owner to
/// see the app as that person sees it. Carries no pairing code.
struct ViewPreview: Codable, Equatable, Identifiable {
    let email: String
    let name: String
    let view: HouseholdView

    var id: String { email }
}

struct HouseholdViewResponse: Codable {
    let view: HouseholdView?
    let updated: String?
}

struct FamilyPerson: Codable, Equatable, Identifiable {
    let subject: String
    let name: String
    /// This card is the person looking. `self` on the wire — renamed here,
    /// because `person.self` is Swift's postfix self and never the field.
    let isSelf: Bool
    /// "home", "out", "unknown" or "off" (not sharing).
    let status: String
    /// The site's own line for the card: "At School · seen 3m ago".
    let line: String
    var batteryPct: Int?
    var lastSeenAt: String?
    var position: Position?
    /// On the move right now, or nil. Absent from a site older than it.
    var moving: Moving? = nil
    let today: Today?
    /// The days before today, newest first — only where `today` is shown.
    /// Absent from a site older than it.
    var days: [Day]? = nil

    var id: String { subject }

    enum CodingKeys: String, CodingKey {
        case subject, name, status, line, batteryPct, lastSeenAt, position, moving, today, days
        case isSelf = "self"
    }

    /// How somebody is moving, from their last ten minutes of fixes on the
    /// site. A speed band, never a claim about the vehicle.
    struct Moving: Codable, Equatable {
        /// "walking", "active" (running or cycling — GPS cannot tell), "vehicle".
        let mode: String
        let speedKmh: Double
        let since: String

        /// "walking", "on the move", "travelling" — said, not asserted.
        var verb: String {
            switch mode {
            case "walking": return "walking"
            case "vehicle": return "travelling"
            default: return "on the move"
            }
        }

        var symbol: String {
            switch mode {
            case "walking": return "figure.walk"
            case "vehicle": return "car.fill"
            default: return "figure.run"
            }
        }
    }

    struct Position: Codable, Equatable {
        let lat: Double
        let lon: Double
        let at: String
        var accuracy: Double? = nil

        var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    }

    struct Today: Codable, Equatable {
        let firstOut: String?
        let minutesOut: Int
        let distanceKm: Double
        let stops: [String]
        /// `[lat, lon, epoch seconds]`.
        let trail: [[Double]]
    }

    /// One whole day before today: the figures without the line.
    struct Day: Codable, Equatable, Identifiable {
        /// "2026-09-26", the local date.
        let date: String
        let firstOut: String?
        let minutesOut: Int
        let distanceKm: Double
        let stops: [String]

        var id: String { date }
    }

    var initial: String { String(name.prefix(1)).uppercased() }
    var sharing: Bool { status != "off" }

    /// "Sam is walking" — the first half of the moving line. The place is the
    /// phone's to add (`PlaceNamer`), so it is not in here.
    var movingLead: String? {
        guard let moving else { return nil }
        return "\(isSelf ? "You are" : "\(name) is") \(moving.verb)"
    }
}

extension FamilyPerson.Today {
    /// Where the line may be drawn: split wherever two fixes are further apart
    /// than the server's own gap (ten minutes). Joining across a gap draws a
    /// journey nobody took, through whatever lay between the two ends.
    func segments(gap: TimeInterval = 600) -> [[CLLocationCoordinate2D]] {
        var out: [[CLLocationCoordinate2D]] = []
        var current: [CLLocationCoordinate2D] = []
        var last: Double?
        for point in trail where point.count >= 3 {
            if let last, point[2] - last > gap, !current.isEmpty {
                out.append(current)
                current = []
            }
            current.append(CLLocationCoordinate2D(latitude: point[0], longitude: point[1]))
            last = point[2]
        }
        if !current.isEmpty { out.append(current) }
        return out.filter { $0.count > 1 }
    }

    /// "2h 05m", "40m", "—".
    var timeOut: String { FamilyFigures.duration(minutesOut) }

    var distance: String { FamilyFigures.distance(distanceKm) }
}

extension FamilyPerson.Day {
    var timeOut: String { FamilyFigures.duration(minutesOut) }
    var distance: String { FamilyFigures.distance(distanceKm) }

    /// "Sat 26 Sep" — or "Yesterday".
    func label(now: Date = Date(), calendar: Calendar = .current) -> String {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = calendar.timeZone
        parser.dateFormat = "yyyy-MM-dd"
        guard let day = parser.date(from: date) else { return date }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

/// The figure formats a day and a week share.
enum FamilyFigures {
    /// "2h 05m", "40m", "—".
    static func duration(_ minutes: Int) -> String {
        guard minutes > 0 else { return "—" }
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h)h \(String(format: "%02d", m))m" : "\(m)m"
    }

    static func distance(_ km: Double) -> String {
        km > 0 ? String(format: km < 10 ? "%.1f km" : "%.0f km", km) : "—"
    }
}

/// How a battery level reads. Low is a fact worth colour; the rest is not.
enum BatteryReading {
    static func symbol(_ pct: Int) -> String {
        switch pct {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    static func isLow(_ pct: Int) -> Bool { pct <= 20 }
}

extension HouseholdView {
    /// Everyone with a pin, for the map.
    var placed: [FamilyPerson] { people.filter { $0.position != nil } }

    /// Whoever is on the move now, the summary's first lines.
    var moving: [FamilyPerson] { people.filter { $0.moving != nil && $0.position != nil } }

    /// "3 home · 1 out" — the counts under the mini-map. Only statuses somebody
    /// actually has are named.
    var summary: String {
        let counts = [("home", "home"), ("out", "out"), ("unknown", "not seen lately"), ("off", "not sharing")]
            .compactMap { key, word -> String? in
                let n = people.filter { $0.status == key }.count
                return n > 0 ? "\(n) \(word)" : nil
            }
        return counts.isEmpty ? "Nobody yet" : counts.joined(separator: " · ")
    }
}

// MARK: - Where everyone is, as places

/// A place and whoever is at it: one group on Today.
///
/// Today used to draw a map. A map is a picture of pins you have to read, and
/// what a glance wants is the sentence the pins add up to — Robin and Sam are
/// home, Alex is at the terrace — so Today groups people by where they are and
/// leaves the map to the Family tab.
struct FamilyPlace: Equatable, Identifiable {
    let name: String
    let isHome: Bool
    var people: [FamilyPerson]

    var id: String { name }
    /// Every one of them on the move: the group is a journey, not a place.
    var isMoving: Bool { !people.isEmpty && people.allSatisfy { $0.moving != nil } }
}

extension FamilyPerson {
    /// Where the site says this person is, from the first half of its line:
    /// "At School · seen 6m ago" → "School", "Bethesda Terrace · seen 2m ago"
    /// → "Bethesda Terrace". Home is "Home" whatever the line says. Nil for a
    /// line that names nowhere.
    var placeName: String? {
        if status == "home" { return "Home" }
        let parts = line.components(separatedBy: " · ")
        guard parts.count > 1 else { return nil }
        var head = parts[0].trimmingCharacters(in: .whitespaces)
        for prefix in ["At ", "Last at ", "Near ", "near "] where head.hasPrefix(prefix) {
            head = String(head.dropFirst(prefix.count))
        }
        guard !head.isEmpty else { return nil }
        return head.lowercased() == "home" ? "Home" : head
    }

    /// The second half of the line, as a sentence: "Seen 6m ago".
    var seenLine: String? {
        let parts = line.components(separatedBy: " · ")
        guard parts.count > 1 else { return nil }
        let tail = parts.dropFirst().joined(separator: " · ").trimmingCharacters(in: .whitespaces)
        guard let first = tail.first else { return nil }
        return String(first).uppercased() + String(tail.dropFirst())
    }
}

extension HouseholdView {
    /// Everyone sharing and seen lately, grouped by where they are. PURE.
    ///
    /// First by the place the site names — "Home", "School" — which is the
    /// site's call, made against its own saved places. Then two groups the
    /// site named differently are merged when someone in one stands within
    /// `radius` of someone in the other, so two people at the same café are
    /// one group even if only one of them has been matched to a saved place.
    ///
    /// Two things never merge by distance: Home, which is the site's answer
    /// and not a guess (a neighbour's garden is not home), and anybody on the
    /// move, who is passing a place rather than at it.
    ///
    /// You first, then home, then the bigger groups.
    func places(radius: CLLocationDistance = 150) -> [FamilyPlace] {
        let present = people.filter { $0.status == "home" || $0.status == "out" }
        var groups: [FamilyPlace] = []
        for person in present {
            let name = person.placeName ?? "Out"
            if let index = groups.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) {
                groups[index].people.append(person)
            } else {
                groups.append(FamilyPlace(name: name, isHome: person.status == "home", people: [person]))
            }
        }

        func mergeable(_ group: FamilyPlace) -> Bool { !group.isHome && !group.people.contains { $0.moving != nil } }
        func near(_ a: FamilyPlace, _ b: FamilyPlace) -> Bool {
            for p in a.people {
                for q in b.people {
                    guard let x = p.position, let y = q.position else { continue }
                    let d = CLLocation(latitude: x.lat, longitude: x.lon)
                        .distance(from: CLLocation(latitude: y.lat, longitude: y.lon))
                    if d <= radius { return true }
                }
            }
            return false
        }

        var merged = true
        while merged {
            merged = false
            search: for i in groups.indices where mergeable(groups[i]) {
                for j in groups.indices where j > i && mergeable(groups[j]) && near(groups[i], groups[j]) {
                    // The site's saved place wins — its line says "At School"
                    // where an unmatched spot only names the street — then
                    // anything over "Out", then the first group's.
                    func saved(_ g: FamilyPlace) -> Bool { g.people.contains { $0.line.hasPrefix("At ") } }
                    let keep: String
                    if saved(groups[j]) && !saved(groups[i]) { keep = groups[j].name }
                    else if groups[i].name == "Out" { keep = groups[j].name }
                    else { keep = groups[i].name }
                    groups[i] = FamilyPlace(name: keep, isHome: false, people: groups[i].people + groups[j].people)
                    groups.remove(at: j)
                    merged = true
                    break search
                }
            }
        }

        for index in groups.indices {
            groups[index].people.sort { a, b in a.isSelf && !b.isSelf }
        }
        return groups.enumerated().sorted { a, b in
            let (x, y) = (a.element, b.element)
            let xSelf = x.people.contains { $0.isSelf }, ySelf = y.people.contains { $0.isSelf }
            if xSelf != ySelf { return xSelf }
            if x.isHome != y.isHome { return x.isHome }
            if x.people.count != y.people.count { return x.people.count > y.people.count }
            return a.offset < b.offset
        }.map { $0.element }
    }

    /// Whoever is left out of `places`, in words: "Kit was last at The
    /// Reservoir, 2h ago.", "Pat isn't sharing their location."
    var absentLines: [String] {
        var lines: [String] = []
        for person in people where person.status == "unknown" {
            if let place = person.placeName, let seen = person.seenLine {
                let when: String = seen.prefix(1).lowercased() + String(seen.dropFirst())
                lines.append("\(person.name) was last at \(place), \(when).")
            } else {
                lines.append("\(person.name) hasn't been seen lately.")
            }
        }
        let hidden = people.filter { $0.status == "off" }.map(\.name)
        switch hidden.count {
        case 0: break
        case 1: lines.append("\(hidden[0]) isn't sharing their location.")
        default: lines.append("\(hidden.dropLast().joined(separator: ", ")) and \(hidden.last ?? "") aren't sharing their location.")
        }
        return lines
    }
}

// MARK: - Initials that tell people apart

extension HouseholdView {
    /// Each person's initials, unique across the household. PURE.
    ///
    /// First letter of the first name and of the surname — "John Kelly" is JK,
    /// "Karen Kelly" KK. A family shares a surname, so two first names with the
    /// same letter collide, and the later one takes more of its first name
    /// until it is unique: "Jennifer Kelly" becomes JeK. You keep the plain
    /// form, then the site's order decides, so the same household always
    /// reads the same. A one-word name is its first letter ("Alex" → A).
    var initials: [String: String] {
        func words(_ name: String) -> [String] {
            name.split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init)
        }
        func code(_ name: String, letters: Int) -> String {
            let w = words(name)
            guard let first = w.first else { return "?" }
            let head = String(first.prefix(letters))
            let lead: String = head.prefix(1).uppercased() + head.dropFirst().lowercased()
            let tail: String = w.count > 1 ? (w.last?.prefix(1).uppercased() ?? "") : ""
            return lead + tail
        }
        let ordered = people.filter { $0.isSelf } + people.filter { !$0.isSelf }
        var taken: Set<String> = []
        var out: [String: String] = [:]
        for person in ordered {
            let most = max(1, words(person.name).first?.count ?? 1)
            var letters = 1
            var candidate = code(person.name, letters: letters)
            while taken.contains(candidate) && letters < most {
                letters += 1
                candidate = code(person.name, letters: letters)
            }
            taken.insert(candidate)
            out[person.subject] = candidate
        }
        return out
    }
}

struct LiveFamilyResponse: Decodable {
    let revision: String
    let positions: [Fix]
    struct Fix: Decodable {
        let subject: String
        let position: FamilyPerson.Position
        let moving: Bool
        let speed: Double
        let battery: Int?
    }
}
