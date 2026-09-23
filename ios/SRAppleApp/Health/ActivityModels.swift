import Foundation
import CoreLocation

// Activities and segments, as `/api/native/health/*` sends them.
//
// SR-Main projects SR-Health's service objects to this shape, so the numbers
// arrive RAW — metres, seconds, bpm — and the phone formats them. Dates are ISO
// 8601 except `startDateLocal`, which is the string the workout was recorded in
// and must not be re-zoned (an evening run re-read in UTC slides into tomorrow).
//
// Decoding is TOLERANT on purpose. These endpoints are new and a detail screen
// has a dozen optional enrichments; one missing array, or one enrichment the
// server stopped sending, must cost that one section and not the whole screen.
// So every array defaults to empty and every enrichment to nil — only the
// fields a row cannot be drawn without are required.

private extension KeyedDecodingContainer {
    /// An array that may be absent, null or malformed — all three read as empty.
    func list<T: Decodable>(_ key: Key) -> [T] {
        // `try?` flattens the Optional (SE-0230), so this is `[T]?` → `[T]`.
        (try? decodeIfPresent([T].self, forKey: key)) ?? []
    }

    /// An optional that may also be the wrong type — read as nil, not a failure.
    func maybe<T: Decodable>(_ key: Key) -> T? {
        try? decodeIfPresent(T.self, forKey: key)
    }
}

struct ActivityHighlight: Decodable, Hashable {
    let label: String
    let detail: String
}

/// One row of the activities list, and the head of every activity detail.
struct ActivityRow: Decodable, Identifiable, Hashable {
    /// `apple:UUID`, `strava:123` — a colon in it, so it is percent-encoded
    /// before it goes in a path.
    let id: String
    let name: String
    let activityType: String
    let startDate: String
    let startDateLocal: String?
    let distanceM: Double?
    let durationS: Double
    let movingS: Double?
    let elevationGainM: Double?
    let avgHeartrate: Double?
    let paceSPerKm: Double?
    let energyKcal: Double?
    let hasTrack: Bool
    let segmentCount: Int
    let highlight: ActivityHighlight?
    /// `apple`, `companion`, `recorded`, `strava`, `whoop`, `manual` — or a key
    /// this build has not heard of. Nil when the server did not say; the id's
    /// prefix then stands in (see `origin`).
    let source: String?
    /// Origins whose copy of this same outing was folded into this row. In
    /// practice `["companion"]` on an Apple Health workout the SR app's
    /// background tracking also caught. Usually empty.
    let alsoFrom: [String]

    private enum CodingKeys: String, CodingKey {
        case id, name, activityType, startDate, startDateLocal, distanceM, durationS, movingS
        case elevationGainM, avgHeartrate, paceSPerKm, energyKcal, hasTrack, segmentCount, highlight
        case source, alsoFrom
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (c.maybe(.name) as String?) ?? "Activity"
        activityType = (c.maybe(.activityType) as String?) ?? "other"
        startDate = (c.maybe(.startDate) as String?) ?? ""
        startDateLocal = c.maybe(.startDateLocal)
        distanceM = c.maybe(.distanceM)
        durationS = (c.maybe(.durationS) as Double?) ?? 0
        movingS = c.maybe(.movingS)
        elevationGainM = c.maybe(.elevationGainM)
        avgHeartrate = c.maybe(.avgHeartrate)
        paceSPerKm = c.maybe(.paceSPerKm)
        energyKcal = c.maybe(.energyKcal)
        hasTrack = (c.maybe(.hasTrack) as Bool?) ?? false
        segmentCount = (c.maybe(.segmentCount) as Int?) ?? 0
        highlight = c.maybe(.highlight)
        let rawSource = (c.maybe(.source) as String?)?.trimmingCharacters(in: .whitespaces)
        source = rawSource?.isEmpty == false ? rawSource : nil
        alsoFrom = (c.list(.alsoFrom) as [String]).filter { !$0.isEmpty }
    }

    /// The normalised origin key — `source`, or the id's prefix without one.
    var origin: String { ActivityOrigin.key(source, id: id) }

    /// "Apple Health · also SR app" — the quiet provenance line on a row.
    var originLine: String { ActivityOrigin.line(origin, alsoFrom: alsoFrom) }

    /// Moving time where the source measured it, elapsed otherwise.
    var timeS: Double { movingS ?? durationS }

    /// "7.42 km · 41:10 · 5:32 /km" — the three figures a list row has room for.
    var summaryLine: String {
        var parts: [String] = []
        if let distanceM, distanceM > 0 { parts.append("\(TrailFormat.km(distanceM)) km") }
        if timeS > 0 { parts.append(TrailFormat.duration(timeS)) }
        if Sport.isPace(activityType) {
            if let pace = paceSPerKm, pace > 0 { parts.append("\(TrailFormat.pace(pace)) /km") }
        } else if let pace = paceSPerKm, pace > 0 {
            parts.append("\(TrailFormat.speed(paceSPerKm: pace)) km/h")
        }
        if let gain = elevationGainM, gain >= 1, parts.count < 4 { parts.append("↑\(TrailFormat.metres(gain)) m") }
        return parts.joined(separator: " · ")
    }

    var dateLine: String { TrailFormat.date(local: startDateLocal, iso: startDate) }
}

struct ActivitiesPage: Decodable {
    let activities: [ActivityRow]
    let nextBefore: String?

    private enum CodingKeys: String, CodingKey { case activities, nextBefore }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activities = c.list(.activities)
        nextBefore = c.maybe(.nextBefore)
    }
}

// MARK: - One activity

struct ElevationPoint: Decodable, Hashable {
    /// Metres along.
    let d: Double
    /// Metres above sea level.
    let e: Double
}

struct HeartRatePoint: Decodable, Hashable {
    /// Seconds from the start.
    let t: Double
    /// bpm.
    let v: Double
}

struct ActivitySplit: Decodable, Hashable, Identifiable {
    let index: Int
    let distanceM: Double
    let durationS: Double
    let paceSPerKm: Double?
    let elevationGainM: Double?

    var id: Int { index }
}

struct ActivityBounds: Decodable, Hashable {
    let n: Double
    let s: Double
    let e: Double
    let w: Double
}

struct ActivityDetail: Decodable, Hashable {
    /// Everything the list row has — the detail is that row plus more.
    let row: ActivityRow
    let maxHeartrate: Double?
    let avgCadence: Double?
    let elevationLossM: Double?
    let temperatureC: Double?
    let timezone: String?
    /// [lat, lng], downsampled by the server. Empty when there was no track.
    let route: [CLLocationCoordinate2D]
    let bounds: ActivityBounds?
    let elevation: [ElevationPoint]
    let heartRate: [HeartRatePoint]
    let splits: [ActivitySplit]

    private enum CodingKeys: String, CodingKey {
        case maxHeartrate, avgCadence, elevationLossM, temperatureC, timezone
        case route, bounds, elevation, heartRate, splits
    }

    init(from decoder: Decoder) throws {
        row = try ActivityRow(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        maxHeartrate = c.maybe(.maxHeartrate)
        avgCadence = c.maybe(.avgCadence)
        elevationLossM = c.maybe(.elevationLossM)
        temperatureC = c.maybe(.temperatureC)
        timezone = c.maybe(.timezone)
        route = Self.coordinates(c.list(.route))
        bounds = c.maybe(.bounds)
        elevation = c.list(.elevation)
        heartRate = c.list(.heartRate)
        splits = c.list(.splits)
    }

    /// `[lat, lng]` pairs to coordinates, dropping anything that is not a pair
    /// of real numbers rather than drawing a line to 0,0.
    static func coordinates(_ pairs: [[Double]]) -> [CLLocationCoordinate2D] {
        pairs.compactMap { pair in
            guard pair.count >= 2, pair[0].isFinite, pair[1].isFinite,
                  abs(pair[0]) <= 90, abs(pair[1]) <= 180 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
        }
    }

    /// The row decodes `source` from this same object, so it is read once.
    var source: String? { row.source }

    static func == (lhs: ActivityDetail, rhs: ActivityDetail) -> Bool { lhs.row == rhs.row }
    func hash(into hasher: inout Hasher) { hasher.combine(row) }
}

struct HeartRateZone: Decodable, Hashable, Identifiable {
    let zone: Int
    let seconds: Double
    var id: Int { zone }
}

struct ActivityPhysio: Decodable, Hashable {
    let trimp: Double?
    let efficiencyFactor: Double?
    let decouplingPct: Double?
    let hrr60: Double?
    let zones: [HeartRateZone]

    private enum CodingKeys: String, CodingKey { case trimp, efficiencyFactor, decouplingPct, hrr60, zones }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trimp = c.maybe(.trimp)
        efficiencyFactor = c.maybe(.efficiencyFactor)
        decouplingPct = c.maybe(.decouplingPct)
        hrr60 = c.maybe(.hrr60)
        zones = c.list(.zones)
    }
}

/// A segment as ridden or run IN one activity.
struct ActivitySegmentEffort: Decodable, Hashable, Identifiable {
    let segmentId: Int
    let name: String
    let descriptor: String
    let distanceM: Double
    let durationS: Double
    let paceSPerKm: Double?
    let avgHeartrate: Double?
    let rankByTime: Int?
    let rankedByTimeOf: Int
    let effortCount: Int

    var id: Int { segmentId }

    private enum CodingKeys: String, CodingKey {
        case segmentId, name, descriptor, distanceM, durationS, paceSPerKm, avgHeartrate
        case rankByTime, rankedByTimeOf, effortCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        segmentId = try c.decode(Int.self, forKey: .segmentId)
        name = (c.maybe(.name) as String?) ?? "Segment"
        descriptor = (c.maybe(.descriptor) as String?) ?? ""
        distanceM = (c.maybe(.distanceM) as Double?) ?? 0
        durationS = (c.maybe(.durationS) as Double?) ?? 0
        paceSPerKm = c.maybe(.paceSPerKm)
        avgHeartrate = c.maybe(.avgHeartrate)
        rankByTime = c.maybe(.rankByTime)
        rankedByTimeOf = (c.maybe(.rankedByTimeOf) as Int?) ?? 0
        effortCount = (c.maybe(.effortCount) as Int?) ?? 0
    }

    /// "PB", "2nd of 7", or nothing when there is nothing to rank against.
    var rankLine: String? { TrailFormat.rank(rankByTime, of: rankedByTimeOf) }
}

struct ActivityDetailResponse: Decodable {
    let activity: ActivityDetail
    let physio: ActivityPhysio?
    let highlights: [ActivityHighlight]
    let segments: [ActivitySegmentEffort]

    private enum CodingKeys: String, CodingKey { case activity, physio, highlights, segments }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activity = try c.decode(ActivityDetail.self, forKey: .activity)
        physio = c.maybe(.physio)
        highlights = c.list(.highlights)
        segments = c.list(.segments)
    }
}

// MARK: - Segments

struct SegmentForm: Decodable, Hashable {
    /// `improving`, `holding`, `slipping`, `unknown`.
    let direction: String
    /// Recent median time against the earlier one. NEGATIVE IS QUICKER — the
    /// underlying number is a duration.
    let deltaPct: Double?
    let daysSincePb: Int?
    /// Durations, oldest first.
    let spark: [Double]

    private enum CodingKeys: String, CodingKey { case direction, deltaPct, daysSincePb, spark }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        direction = (c.maybe(.direction) as String?) ?? "unknown"
        deltaPct = c.maybe(.deltaPct)
        daysSincePb = c.maybe(.daysSincePb)
        spark = c.list(.spark)
    }

    var improving: Bool { direction == "improving" }
    var known: Bool { direction != "unknown" }
}

struct SegmentRow: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let descriptor: String
    let activityType: String
    let distanceM: Double
    let elevationGainM: Double
    let gradientPct: Double
    /// `climb`, `descent`, `rolling`, `flat`.
    let terrain: String
    let effortCount: Int
    let lastEffortAt: String?
    let bestDurationS: Double?
    let bestPaceSPerKm: Double?
    let form: SegmentForm?

    private enum CodingKeys: String, CodingKey {
        case id, name, descriptor, activityType, distanceM, elevationGainM, gradientPct
        case terrain, effortCount, lastEffortAt, bestDurationS, bestPaceSPerKm, form
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = (c.maybe(.name) as String?) ?? "Segment"
        descriptor = (c.maybe(.descriptor) as String?) ?? ""
        activityType = (c.maybe(.activityType) as String?) ?? "other"
        distanceM = (c.maybe(.distanceM) as Double?) ?? 0
        elevationGainM = (c.maybe(.elevationGainM) as Double?) ?? 0
        gradientPct = (c.maybe(.gradientPct) as Double?) ?? 0
        terrain = (c.maybe(.terrain) as String?) ?? "flat"
        effortCount = (c.maybe(.effortCount) as Int?) ?? 0
        lastEffortAt = c.maybe(.lastEffortAt)
        bestDurationS = c.maybe(.bestDurationS)
        bestPaceSPerKm = c.maybe(.bestPaceSPerKm)
        form = c.maybe(.form)
    }

    var terrainIcon: String {
        switch terrain {
        case "climb": return "arrow.up.right"
        case "descent": return "arrow.down.right"
        case "rolling": return "water.waves"
        default: return "arrow.right"
        }
    }
}

struct SegmentsPage: Decodable {
    let segments: [SegmentRow]

    private enum CodingKeys: String, CodingKey { case segments }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        segments = c.list(.segments)
    }
}

struct SegmentConditions: Decodable, Hashable {
    let meanC: Double?
    let quickestC: Double?
    let slowestC: Double?
}

struct SegmentDetail: Decodable, Hashable {
    let row: SegmentRow
    let route: [CLLocationCoordinate2D]
    let elevationLossM: Double?
    let conditions: SegmentConditions?

    private enum CodingKeys: String, CodingKey { case route, elevationLossM, conditions }

    init(from decoder: Decoder) throws {
        row = try SegmentRow(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        route = ActivityDetail.coordinates(c.list(.route))
        elevationLossM = c.maybe(.elevationLossM)
        conditions = c.maybe(.conditions)
    }

    static func == (lhs: SegmentDetail, rhs: SegmentDetail) -> Bool { lhs.row == rhs.row }
    func hash(into hasher: inout Hasher) { hasher.combine(row) }
}

struct SegmentEffort: Decodable, Hashable, Identifiable {
    let id: Int
    let activityId: String
    let activityName: String
    let activityType: String
    let startedAt: String
    let durationS: Double
    let paceSPerKm: Double?
    let avgHeartrate: Double?
    let efficiencyFactor: Double?
    let isBest: Bool

    private enum CodingKeys: String, CodingKey {
        case id, activityId, activityName, activityType, startedAt, durationS
        case paceSPerKm, avgHeartrate, efficiencyFactor, isBest
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        activityId = (c.maybe(.activityId) as String?) ?? ""
        activityName = (c.maybe(.activityName) as String?) ?? "Activity"
        activityType = (c.maybe(.activityType) as String?) ?? "other"
        startedAt = (c.maybe(.startedAt) as String?) ?? ""
        durationS = (c.maybe(.durationS) as Double?) ?? 0
        paceSPerKm = c.maybe(.paceSPerKm)
        avgHeartrate = c.maybe(.avgHeartrate)
        efficiencyFactor = c.maybe(.efficiencyFactor)
        isBest = (c.maybe(.isBest) as Bool?) ?? false
    }
}

struct SegmentDetailResponse: Decodable {
    let segment: SegmentDetail
    let efforts: [SegmentEffort]

    private enum CodingKeys: String, CodingKey { case segment, efforts }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        segment = try c.decode(SegmentDetail.self, forKey: .segment)
        efforts = c.list(.efforts)
    }
}

// MARK: - Routes on the Health stack

/// Small values, so a pushed screen is cheap to hold in a `NavigationPath` and
/// the title can paint before the detail arrives.
struct ActivityRef: Hashable {
    let id: String
    let name: String
}

struct SegmentRef: Hashable {
    let id: Int
    let name: String
}

enum HealthRoute: Hashable {
    case activities
    case segments
}
