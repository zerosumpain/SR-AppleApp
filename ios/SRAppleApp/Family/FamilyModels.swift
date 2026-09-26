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
    /// "owner" or "household".
    let viewer: String
    let people: [FamilyPerson]
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
    let batteryPct: Int?
    let lastSeenAt: String?
    let position: Position?
    let today: Today?

    var id: String { subject }

    enum CodingKeys: String, CodingKey {
        case subject, name, status, line, batteryPct, lastSeenAt, position, today
        case isSelf = "self"
    }

    struct Position: Codable, Equatable {
        let lat: Double
        let lon: Double
        let at: String

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

    var initial: String { String(name.prefix(1)).uppercased() }
    var sharing: Bool { status != "off" }
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
    var timeOut: String {
        guard minutesOut > 0 else { return "—" }
        let h = minutesOut / 60, m = minutesOut % 60
        return h > 0 ? "\(h)h \(String(format: "%02d", m))m" : "\(m)m"
    }

    var distance: String {
        distanceKm > 0 ? String(format: distanceKm < 10 ? "%.1f km" : "%.0f km", distanceKm) : "—"
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
