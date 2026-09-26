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

    /// Whether there is a measurement here at all.
    ///
    /// Zero is MISSING in this data, not a reading — a day with no HRV sample
    /// arrives as 0, and "0 ms" is a confident statement about a heart that did
    /// not report. The server renders those as an em dash.
    var measured: Bool { display != "—" && !display.isEmpty }

    /// What the value reads as with its unit attached. Percent and hours are
    /// already in the rendered string; everything else needs its unit.
    ///
    /// A missing figure takes NO unit. "— bpm" and "—%" both read as a unit
    /// with a value that failed to render, which is the opposite of what an
    /// em dash is there to say.
    var displayWithUnit: String {
        guard measured else { return "—" }
        switch unit {
        case "%": return "\(display)%"
        case "h": return display
        default: return "\(display) \(unit)"
        }
    }
}

struct HealthReadiness: Decodable, Hashable {
    /// One part of the composite, as /health's hub sends it. Optional on the
    /// summary and on Today — where it is present, Today reads Recovery from it
    /// when the figures do not carry one.
    struct Factor: Decodable, Hashable {
        let key: String
        let label: String
        let score: Double
    }

    let score: Double
    let label: String
    let recommendation: String
    let factors: [Factor]

    enum CodingKeys: String, CodingKey { case score, label, recommendation, factors }

    init(score: Double, label: String, recommendation: String, factors: [Factor] = []) {
        self.score = score
        self.label = label
        self.recommendation = recommendation
        self.factors = factors
    }

    /// The three fields as strictly as before; `factors` lossily, because a
    /// Today payload that throws is a blank first screen.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        score = try c.decode(Double.self, forKey: .score)
        label = try c.decode(String.self, forKey: .label)
        recommendation = try c.decode(String.self, forKey: .recommendation)
        factors = c.lossy(Factor.self, .factors)
    }
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
