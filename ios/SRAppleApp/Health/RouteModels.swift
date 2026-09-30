import Foundation
import CoreLocation

// Planned routes — /health/plan on the phone.
//
// The contract is SR-Main's `$lib/server/native-routes`: SR-Health plans,
// scores and stores; Main turns every point round to `[lat, lng, ele]`. A
// candidate arrives at FULL geometry because saving it sends that geometry
// back, and a saved route arrives at following precision because the phone
// keeps it for walking with no signal.

/// `[lat, lng, elevationM | null]`. Decoded leniently: a malformed point is
/// dropped rather than failing the route (the same rule as an activity's track).
struct RoutePoint: Hashable {
    let lat: Double
    let lng: Double
    let ele: Double?

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }

    /// `[lat, lng, ele]` for a save — the shape Main reads.
    var json: [Double?] { [lat, lng, ele] }

    static func decodeList(_ raw: [[Double?]]) -> [RoutePoint] {
        raw.compactMap { p in
            guard p.count >= 2, let lat = p[0], let lng = p[1],
                  (-90...90).contains(lat), (-180...180).contains(lng) else { return nil }
            return RoutePoint(lat: lat, lng: lng, ele: p.count > 2 ? p[2] : nil)
        }
    }
}

private extension KeyedDecodingContainer {
    func points(_ key: Key) -> [RoutePoint] {
        RoutePoint.decodeList((try? decodeIfPresent([[Double?]].self, forKey: key)) ?? [])
    }
}

/// The six sports Health's planner routes for, in the order the form offers them.
enum RouteSport: String, CaseIterable, Identifiable, Codable {
    case walk, hike, run, trail_run, ride, mtb

    var id: String { rawValue }
    var label: String { Sport.label(rawValue) }
    var icon: String { Sport.icon(rawValue) }
}

// MARK: - Saved routes

struct RouteBounds: Codable, Hashable {
    let n: Double
    let s: Double
    let e: Double
    let w: Double
}

struct PlannedRouteSummary: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let sport: String
    let source: String
    let distanceM: Double
    let ascentM: Double?
    let descentM: Double?
    let durationS: Double?
    let score: Double?
    let createdAt: String?
    let notes: String?
    let bounds: RouteBounds?

    /// "10.0 km · 84 m up · 51 min"
    var summaryLine: String {
        RouteFormat.line(distanceM: distanceM, ascentM: ascentM, durationS: durationS)
    }
}

struct RoutesPage: Decodable {
    let routes: [PlannedRouteSummary]
}

struct RouteWaypoint: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    let icon: String
    let lat: Double
    let lng: Double
    let note: String?
}

struct PlannedRouteDetail: Decodable, Hashable, Identifiable {
    let id: String
    let name: String
    let sport: String
    let source: String
    let distanceM: Double
    let ascentM: Double?
    let descentM: Double?
    let durationS: Double?
    let score: Double?
    let createdAt: String?
    let notes: String?
    let route: [RoutePoint]
    let targetDistanceM: Double?
    let waypoints: [RouteWaypoint]

    private enum CodingKeys: String, CodingKey {
        case id, name, sport, source, distanceM, ascentM, descentM, durationS, score, createdAt, notes
        case route, targetDistanceM, waypoints
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        sport = try c.decode(String.self, forKey: .sport)
        source = (try? c.decodeIfPresent(String.self, forKey: .source)) ?? "planned"
        distanceM = try c.decode(Double.self, forKey: .distanceM)
        ascentM = try? c.decodeIfPresent(Double.self, forKey: .ascentM)
        descentM = try? c.decodeIfPresent(Double.self, forKey: .descentM)
        durationS = try? c.decodeIfPresent(Double.self, forKey: .durationS)
        score = try? c.decodeIfPresent(Double.self, forKey: .score)
        createdAt = try? c.decodeIfPresent(String.self, forKey: .createdAt)
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
        route = c.points(.route)
        targetDistanceM = try? c.decodeIfPresent(Double.self, forKey: .targetDistanceM)
        waypoints = (try? c.decodeIfPresent([RouteWaypoint].self, forKey: .waypoints)) ?? []
    }

    var coordinates: [CLLocationCoordinate2D] { route.map(\.coordinate) }

    var summaryLine: String {
        RouteFormat.line(distanceM: distanceM, ascentM: ascentM, durationS: durationS)
    }
}

// MARK: - Planning

/// What the form asks the planner for. Nil means "Health decides".
struct RoutePlanRequest: Encodable, Equatable {
    var startLat: Double
    var startLng: Double
    var finishLat: Double?
    var finishLng: Double?
    var sport: String
    var targetDistanceM: Double?
    var targetGainPerKm: Double?
    var prefer: String?
    var allowOutAndBack: Bool?
}

/// Just enough JSON to carry the scorer's breakdown through unread: the phone
/// shows its `notes` and hands the rest back on save, so the saved route keeps it.
indirect enum AnyJSON: Codable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AnyJSON])
    case object([String: AnyJSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([AnyJSON].self) { self = .array(a) }
        else { self = .object(try c.decode([String: AnyJSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

struct RouteCandidate: Decodable, Identifiable, Hashable {
    let rank: Int
    let score: Double
    let notes: [String]
    let distanceM: Double
    let durationS: Double
    let ascentM: Double?
    let descentM: Double?
    let route: [RoutePoint]
    let breakdown: AnyJSON?

    var id: Int { rank }
    var coordinates: [CLLocationCoordinate2D] { route.map(\.coordinate) }

    private enum CodingKeys: String, CodingKey {
        case rank, score, notes, distanceM, durationS, ascentM, descentM, route, breakdown
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rank = try c.decode(Int.self, forKey: .rank)
        score = (try? c.decode(Double.self, forKey: .score)) ?? 0
        notes = (try? c.decodeIfPresent([String].self, forKey: .notes)) ?? []
        distanceM = try c.decode(Double.self, forKey: .distanceM)
        durationS = (try? c.decode(Double.self, forKey: .durationS)) ?? 0
        ascentM = try? c.decodeIfPresent(Double.self, forKey: .ascentM)
        descentM = try? c.decodeIfPresent(Double.self, forKey: .descentM)
        route = c.points(.route)
        breakdown = try? c.decodeIfPresent(AnyJSON.self, forKey: .breakdown)
    }

    var summaryLine: String {
        RouteFormat.line(distanceM: distanceM, ascentM: ascentM, durationS: durationS)
    }
}

struct RoutePlan: Decodable {
    let candidates: [RouteCandidate]
    let targetDistanceM: Double
    let targetSource: String
    let rationale: [String]
}

struct RouteSuggestion: Decodable {
    let configured: Bool
    let distanceM: Double
    let rationale: [String]
}

struct RouteInterpretation: Decodable {
    struct Place: Decodable, Hashable {
        let lat: Double
        let lng: Double
        let label: String
    }

    struct Parsed: Decodable {
        let sport: String?
        let mode: String?
        let targetKm: Double?
        let climbPerKm: Double?
        let prefer: String?
        let allowOutAndBack: Bool?
    }

    let parsed: Parsed
    let start: Place?
    let finish: Place?
    let interpretation: [String]
}

/// A save: a candidate or a discovered route, named.
struct RouteSaveRequest: Encodable {
    let name: String
    let sport: String
    let route: [[Double?]]
    let distanceM: Double
    let ascentM: Double?
    let descentM: Double?
    let durationS: Double?
    let score: Double?
    let scoreBreakdown: AnyJSON?
    let targetDistanceM: Double?
    let source: String
}

struct RouteSaved: Decodable {
    let id: String
}

// MARK: - Published routes nearby

struct DiscoveredRoute: Decodable, Identifiable, Hashable {
    let osmId: Int
    let name: String
    let network: String?
    let distanceKm: Double?
    let `operator`: String?
    let ref: String?

    var id: Int { osmId }
}

struct DiscoveredPage: Decodable {
    let routes: [DiscoveredRoute]
}

struct DiscoveredDetail: Decodable {
    struct Difficulty: Decodable {
        let band: String
        let estimatedTimeS: Double
    }

    let osmId: Int
    let name: String
    let distanceM: Double
    let ascentM: Double?
    let difficulty: Difficulty?
    let route: [RoutePoint]

    private enum CodingKeys: String, CodingKey { case osmId, name, distanceM, ascentM, difficulty, route }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        osmId = try c.decode(Int.self, forKey: .osmId)
        name = try c.decode(String.self, forKey: .name)
        distanceM = try c.decode(Double.self, forKey: .distanceM)
        ascentM = try? c.decodeIfPresent(Double.self, forKey: .ascentM)
        difficulty = try? c.decodeIfPresent(Difficulty.self, forKey: .difficulty)
        route = c.points(.route)
    }
}

// MARK: - Navigation

/// Pushed onto the Health stack; the name paints the title before the detail lands.
struct RouteRef: Hashable {
    let id: String
    let name: String
}

// MARK: - Format

enum RouteFormat {
    static func line(distanceM: Double, ascentM: Double?, durationS: Double?) -> String {
        var parts = ["\(TrailFormat.km(distanceM)) km"]
        if let up = ascentM, up >= 1 { parts.append("\(TrailFormat.metres(up)) m up") }
        if let t = durationS, t > 0 { parts.append(TrailFormat.duration(t)) }
        return parts.joined(separator: " · ")
    }

    /// Health's 0–1 loop-quality score as the web shows it.
    static func score(_ value: Double) -> String { "\(Int((value * 100).rounded()))" }
}
