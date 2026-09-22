import Foundation

/// One figure from /health, with the frame that makes it mean something.
///
/// /health's own methodology, ported: a header figure is a number with no
/// frame. So a figure carries its unit, the window it covers, and the movement
/// against whatever that window implies — and `improving`, which is the only
/// field the phone cannot work out for itself. A resting heart rate going down
/// is the body recovering; HRV going down is not. The server decides that per
/// metric and the view colours what it is told.
struct HealthFigure: Decodable, Identifiable, Hashable {
    let key: String
    let label: String
    let value: Double
    let unit: String
    let display: String
    let delta: Double?
    let deltaDisplay: String?
    let direction: String?
    let improving: Bool?
    let caption: String
    /// Oldest to newest. Absent on the Today card, which draws tiles and has no
    /// room for a sparkline per tile.
    var series: [Double]?

    var id: String { key }

    /// What the value reads as with its unit attached. Percent and hours are
    /// already in the rendered string; everything else needs its unit.
    var displayWithUnit: String {
        switch unit {
        case "%": return "\(display)%"
        case "h": return display
        default: return "\(display) \(unit)"
        }
    }
}

struct HealthReadiness: Decodable, Hashable {
    let score: Double
    let label: String
    let recommendation: String
}

struct HealthWeek: Decodable, Hashable {
    let activities: Int
    let distanceKm: Double
    let durationMinutes: Int
    let elevationM: Int
    let avgRecovery: Int
    let avgSleep: Int
}

struct HealthRecordHighlight: Decodable, Hashable, Identifiable {
    let label: String
    let display: String
    let date: String?

    var id: String { label }
}

struct HealthSummary: Decodable {
    let generatedAt: String
    /// With no real day in the window the whole series is a demonstration. The
    /// screen says so rather than presenting it as measurement — the same rule
    /// the web page follows, and the reason this field travels at all.
    let isMock: Bool
    let strap: String
    let readiness: HealthReadiness?
    let figures: [HealthFigure]
    let week: HealthWeek?
    let records: [HealthRecordHighlight]
    let fingerprint: String
}
