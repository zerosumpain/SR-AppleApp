import Foundation

// The trip planner's shapes, as the phone receives and sends them.
//
// A mirror of SR-Main `src/lib/trips/model.ts` and the wire contract in
// `docs/superpowers/specs/2026-10-13-trips.md`. Property names ARE the JSON
// keys (camelCase, no CodingKeys renames), so a drift on either side shows up
// as a failed decode in `TripTests`, not as a field that is silently empty.
//
// Every number is a `Double`, as it is in TypeScript. The solver port
// (`TripReplan.swift`) has to give the server's answers to the minute, and
// doing its arithmetic on the same kind of number is the cheapest way to make
// that true. Display code rounds.
//
// Times: plan times are LOCAL minutes after midnight in the trip's
// `timeZone`, dates are `YYYY-MM-DD` in that zone, instants are ISO 8601.
// `TripClock` turns them into `Date`s.
//
// This file imports Foundation only: the Linux harness compiles it with the
// solver port to replay the shared cases.

/// A point. Always `{lat,lng}` on the wire — never an unlabelled pair.
struct TripLatLng: Codable, Hashable {
    var lat: Double
    var lng: Double
}

/// `taxi` (v2) is a drive leg the person does not drive: drive-matrix time
/// plus `pickupSec`, with guidance on how to get one in that city.
///
/// A mode this version does not know (a later server's) decodes as
/// `unknown` instead of failing the whole bundle — a trip stays readable
/// offline whatever the server adds. Shown as a plain leg; never re-sent.
enum TravelMode: String, Codable, Hashable {
    case walk, cycle, drive, transit, taxi
    case unknown

    /// `TRAVEL_MODES`: the canonical order the solver walks modes in.
    static let canonical: [TravelMode] = [.walk, .cycle, .drive, .transit, .taxi]
    /// `TAXI_PICKUP_SEC`.
    static let taxiPickupSec = 8.0 * 60

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TravelMode(rawValue: raw) ?? .unknown
    }
}

enum TripPace: String, Codable, Hashable {
    case relaxed, normal, packed
}

/// `PACE_RULES` from the model, verbatim.
struct TripPaceRules: Equatable {
    struct Meal: Equatable {
        let fromMin: Double
        let toMin: Double
        let durationSec: Double
    }

    let dayStartMin: Double
    let dayEndMin: Double
    let bufferSec: Double
    let walkLimitSec: Double
    let lunch: Meal
    let dinner: Meal?

    static func of(_ pace: TripPace) -> TripPaceRules {
        switch pace {
        case .relaxed:
            return TripPaceRules(
                dayStartMin: 9 * 60 + 30, dayEndMin: 18 * 60 + 30, bufferSec: 15 * 60, walkLimitSec: 15 * 60,
                lunch: Meal(fromMin: 12 * 60, toMin: 14 * 60 + 30, durationSec: 75 * 60), dinner: nil
            )
        case .normal:
            return TripPaceRules(
                dayStartMin: 9 * 60, dayEndMin: 19 * 60, bufferSec: 10 * 60, walkLimitSec: 25 * 60,
                lunch: Meal(fromMin: 12 * 60, toMin: 14 * 60 + 30, durationSec: 60 * 60), dinner: nil
            )
        case .packed:
            return TripPaceRules(
                dayStartMin: 8 * 60, dayEndMin: 21 * 60, bufferSec: 5 * 60, walkLimitSec: 35 * 60,
                lunch: Meal(fromMin: 12 * 60, toMin: 15 * 60, durationSec: 45 * 60),
                dinner: Meal(fromMin: 19 * 60, toMin: 21 * 60, durationSec: 75 * 60)
            )
        }
    }
}

enum TripStatus: String, Codable, Hashable {
    case draft, planned, active, done
}

enum TripPriority: String, Codable, Hashable {
    case must, nice
}

enum PartOfDay: String, Codable, Hashable {
    case morning, afternoon, evening, any
}

struct Trip: Codable, Hashable, Identifiable {
    var id: String
    var ownerEmail: String
    var title: String
    var destination: String
    /// IANA zone, e.g. `Europe/Rome`. Every local time in the trip is in it.
    var timeZone: String
    var startDate: String
    var endDate: String
    var pace: TripPace
    var modes: [TravelMode]
    var status: TripStatus
    var notes: String?
    /// v2.1: how full each day should be, by local date: "light", "normal"
    /// or "full" (missing = normal). Strings, so a new load never fails a
    /// bundle; `TripReplan` reads unknown values as normal.
    var dayLoads: [String: String]? = nil
}

/// Accommodation for a run of nights. Each day starts and ends here.
struct TripStay: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var address: String?
    var location: TripLatLng
    var fromDate: String
    var toDate: String
    var checkInMin: Double?
    var checkOutMin: Double?
}

/// One open window on a weekday: local `[openMin, closeMin)`.
struct TripOpenRange: Codable, Hashable {
    var openMin: Double
    var closeMin: Double
}

/// A researched fact sheet. Every field may be unknown; every sheet names
/// its sources and when it was checked.
struct TripFacts: Codable, Hashable {
    struct Source: Codable, Hashable {
        var url: String
        var title: String?
    }

    var openingHoursText: String?
    /// ISO weekday "1" (Mon) … "7" (Sun). A missing key is unknown, `[]` closed.
    var hours: [String: [TripOpenRange]]?
    var closedDates: [String]
    var bookingRequired: Bool?
    var bookAheadDays: Double?
    var bookingUrl: String?
    var officialUrl: String?
    var priceText: String?
    var typicalVisitSec: Double?
    var summary: String?
    var sources: [Source]
    var checkedAt: String?
    /// "brief", "deep" or "manual".
    var depth: String
    var unknown: [String]
}

struct TripPlace: Codable, Hashable {
    var name: String
    var location: TripLatLng
    var osmId: String?
    var address: String?
}

struct TripWish: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var place: TripPlace?
    var priority: TripPriority
    var durationSec: Double?
    var partOfDay: PartOfDay
    var fixedDate: String?
    var fixedStartMin: Double?
    var locked: Bool
    var suggested: Bool
    var skipped: Bool
    var facts: TripFacts?
    var note: String?
    var sortHint: Double
    /// v2: what to know when you're there.
    var guide: StopGuide? = nil
    /// v2.1: this wish IS that day's "lunch" or "dinner".
    var replacesMeal: String? = nil
}

enum BookingStatus: String, Codable, Hashable {
    case toBook = "to-book"
    case booked
    case cancelled
}

struct TripBooking: Codable, Hashable, Identifiable {
    var id: String
    var wishId: String?
    var title: String
    var date: String?
    var startMin: Double?
    var endMin: Double?
    var reference: String?
    var url: String?
    var documentId: String?
    var status: BookingStatus
}

// MARK: - The solved plan

/// `transport` is v3's arrival/departure point (an airport, a station);
/// a kind this version does not know decodes as `unknown`, so a newer
/// server's stop never fails a saved trip.
enum StopKind: String, Codable, Hashable {
    case wish, meal, stay, transport
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = StopKind(rawValue: raw) ?? .unknown
    }
}

struct PlannedStop: Codable, Hashable, Identifiable {
    /// The wish id, `meal:<date>:lunch`, `stay:<date>:start|end`.
    var id: String
    var kind: StopKind
    var wishId: String?
    var title: String
    var location: TripLatLng?
    var arriveMin: Double
    var departMin: Double
    /// Waiting before it opens, seconds.
    var waitSec: Double
    var locked: Bool
    var bookingId: String?
    var warnings: [String]
}

struct PlannedLeg: Codable, Hashable {
    var fromStopId: String
    var toStopId: String
    var mode: TravelMode
    var durationSec: Double
    var distanceM: Double?
    /// A distance × factor guess, not a routed answer.
    var estimated: Bool
    /// Simplified line for drawing, ≤ 300 points. Null until routed.
    var line: [TripLatLng]?
    /// v2: how to actually do this leg. Null until guidance is generated.
    var guidance: LegGuidance? = nil
}

struct PlannedDay: Codable, Hashable, Identifiable {
    var date: String
    var stayId: String?
    var stops: [PlannedStop]
    /// `legs[i]` joins `stops[i]` → `stops[i+1]`.
    var legs: [PlannedLeg]
    var warnings: [String]

    var id: String { date }
}

struct DroppedWish: Codable, Hashable {
    var wishId: String
    var reason: String
}

/// Travel times between every point a day can visit, by mode. `points[i]` is
/// a wish id or `stay:<stayId>`; `seconds[mode][i][j]` is i → j, null when
/// that mode has no route.
struct TravelMatrix: Codable, Hashable {
    var points: [String]
    var seconds: [String: [[Double?]]]
    var metres: [String: [[Double?]]]
    var estimated: [String: Bool]
}

struct SolvedPlan: Codable, Hashable {
    var days: [PlannedDay]
    var dropped: [DroppedWish]
    var warnings: [String]
    var score: Double
}

/// The plan as the phone receives it: the versioned envelope around it.
struct TripPlanVersion: Codable, Hashable {
    var id: String
    var version: Int
    var createdAt: String
    var plan: SolvedPlan
    var changes: [String]
}

// MARK: - The wire

/// `GET /api/native/trips` → `{ trips: TripSummary[] }`.
struct TripSummary: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var destination: String
    var timeZone: String
    var startDate: String
    var endDate: String
    var status: TripStatus
    var planVersion: Int?
    var updatedAt: String
}

struct TripList: Codable {
    var trips: [TripSummary]
}

/// `GET /api/native/trips/:id`.
struct TripBundle: Codable, Hashable {
    var trip: Trip
    var stays: [TripStay]
    var wishes: [TripWish]
    var bookings: [TripBooking]
    var plan: TripPlanVersion?
    /// Per day: that day's stops and its stay only.
    var matrices: [String: TravelMatrix]
    var etag: String
    /// v2: the planning conversation, last 50 (absent from a v1 server).
    var messages: [TripMessage]? = nil
    /// v2: city-level know-how.
    var guide: TripGuide? = nil
    /// v2: every point of the trip, for an offline pull-forward.
    var tripMatrix: TravelMatrix? = nil
    /// v3: flights and trains there and back. The site has not fixed the
    /// field's name yet, so both likely names are read; `segments` is the one to use.
    var transport: [TransportSegment]? = nil
    var transportSegments: [TransportSegment]? = nil
    /// v3: what the planner already knows about the people travelling.
    var profile: TravellerProfile? = nil

    var segments: [TransportSegment] { transport ?? transportSegments ?? [] }
}

enum TripEventKind: String, Codable, Hashable {
    case arrived
    case left
    case skipped
    case delayed
    case optionApplied = "option-applied"
    case stopAdded = "stop-added"
}

/// Something that happened on the day, minted on the phone. `clientId` is
/// the idempotency key: a retry after a lost reply records nothing twice.
struct TripEvent: Codable, Hashable, Identifiable {
    var clientId: String
    var kind: TripEventKind
    var stopId: String?
    var wishId: String?
    /// ISO 8601, the phone's clock.
    var at: String
    var detail: [String: TripJSON]?

    var id: String { clientId }
}

/// `POST /api/native/trips/:id/events`.
struct TripEventsBody: Codable {
    var events: [TripEvent]
    var basePlanVersion: Int
}

struct TripEventsReply: Codable {
    var accepted: [String]
    var planVersion: Int
}

/// `POST /api/native/trips/:id/replan`.
struct TripReplanBody: Codable {
    var date: String
    var nowMin: Double
    var position: TripLatLng?
    var atStopId: String?
    var doneStopIds: [String]
    /// v2: "day" (default) or "trip".
    var scope: String? = nil
    /// v2: what the phone saw.
    var observation: Observation? = nil
}

struct ReplanOption: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, Hashable { case shift, drop, swap, reorder }

    var id: String
    var label: String
    var kind: Kind
    var day: PlannedDay
    var dropped: [String]
    var endsLaterMin: Double
}

struct TripReplanReply: Codable {
    var options: [ReplanOption]
    /// v2, scope "trip".
    var tripOptions: [TripReplanOption]? = nil
    /// v2: what is happening and what the planner would do.
    var narrative: String? = nil
}

// MARK: - Free-form JSON

/// `TripEvent.detail` is `Record<string, unknown>`: whatever the event needs
/// (`seconds` for a delay, the whole new `day` for an applied option). Kept
/// as JSON, so a day goes up exactly as the solver shaped it.
indirect enum TripJSON: Codable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([TripJSON])
    case object([String: TripJSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([TripJSON].self) { self = .array(v) }
        else { self = .object(try c.decode([String: TripJSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    /// Any Encodable value, as JSON — a `PlannedDay` for `option-applied`.
    static func from<T: Encodable>(_ value: T) -> TripJSON? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(TripJSON.self, from: data)
    }

    /// Back to a typed value — the `day` of an event read back off disk.
    func decode<T: Decodable>(_ type: T.Type) -> T? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    var number: Double? {
        if case .number(let v) = self { return v }
        return nil
    }

    var string: String? {
        if case .string(let v) = self { return v }
        return nil
    }
}

// MARK: - Conveniences

extension TripBundle {
    func day(_ date: String) -> PlannedDay? { plan?.plan.days.first { $0.date == date } }
    func wish(_ id: String?) -> TripWish? { id.flatMap { id in wishes.first { $0.id == id } } }
    func booking(_ id: String?) -> TripBooking? { id.flatMap { id in bookings.first { $0.id == id } } }
    func stay(_ id: String?) -> TripStay? { id.flatMap { id in stays.first { $0.id == id } } }

    /// The booking for a stop: named on the stop, or a booked one for its wish.
    func booking(for stop: PlannedStop) -> TripBooking? {
        if let b = booking(stop.bookingId) { return b }
        guard let wishId = stop.wishId else { return nil }
        return bookings.first { $0.wishId == wishId && $0.status == .booked }
    }

    var summary: TripSummary {
        TripSummary(
            id: trip.id, title: trip.title, destination: trip.destination, timeZone: trip.timeZone,
            startDate: trip.startDate, endDate: trip.endDate, status: trip.status,
            planVersion: plan?.version, updatedAt: plan?.createdAt ?? ""
        )
    }
}

extension PlannedDay {
    /// The leg that leaves `stops[index]`, if there is one.
    func leg(after index: Int) -> PlannedLeg? { index >= 0 && index < legs.count ? legs[index] : nil }

    /// The leg that arrives at `stops[index]`.
    func leg(before index: Int) -> PlannedLeg? { index > 0 && index - 1 < legs.count ? legs[index - 1] : nil }

    func index(of stopId: String?) -> Int? { stopId.flatMap { id in stops.firstIndex { $0.id == id } } }
}

// MARK: - Explicit nulls on the way up
//
// The synthesised encoder LEAVES OUT a nil optional. The contract types those
// fields `string | null`, and a validator written as `.nullable()` refuses a
// missing key where it accepts a null. Everything the phone sends — an event,
// a replan request, a day inside `option-applied` — therefore writes its
// nulls out.

extension PlannedStop {
    private enum Keys: String, CodingKey {
        case id, kind, wishId, title, location, arriveMin, departMin, waitSec, locked, bookingId, warnings
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(wishId, forKey: .wishId)
        try c.encode(title, forKey: .title)
        try c.encode(location, forKey: .location)
        try c.encode(arriveMin, forKey: .arriveMin)
        try c.encode(departMin, forKey: .departMin)
        try c.encode(waitSec, forKey: .waitSec)
        try c.encode(locked, forKey: .locked)
        try c.encode(bookingId, forKey: .bookingId)
        try c.encode(warnings, forKey: .warnings)
    }
}

extension PlannedLeg {
    private enum Keys: String, CodingKey {
        case fromStopId, toStopId, mode, durationSec, distanceM, estimated, line, guidance
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(fromStopId, forKey: .fromStopId)
        try c.encode(toStopId, forKey: .toStopId)
        try c.encode(mode, forKey: .mode)
        try c.encode(durationSec, forKey: .durationSec)
        try c.encode(distanceM, forKey: .distanceM)
        try c.encode(estimated, forKey: .estimated)
        try c.encode(line, forKey: .line)
        // Optional in the contract (`guidance?:`): left out rather than null.
        try c.encodeIfPresent(guidance, forKey: .guidance)
    }
}

extension PlannedDay {
    private enum Keys: String, CodingKey { case date, stayId, stops, legs, warnings }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(date, forKey: .date)
        try c.encode(stayId, forKey: .stayId)
        try c.encode(stops, forKey: .stops)
        try c.encode(legs, forKey: .legs)
        try c.encode(warnings, forKey: .warnings)
    }
}

extension TripEvent {
    private enum Keys: String, CodingKey { case clientId, kind, stopId, wishId, at, detail }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(clientId, forKey: .clientId)
        try c.encode(kind, forKey: .kind)
        try c.encode(stopId, forKey: .stopId)
        try c.encode(wishId, forKey: .wishId)
        try c.encode(at, forKey: .at)
        try c.encode(detail, forKey: .detail)
    }
}

extension TripReplanBody {
    private enum Keys: String, CodingKey { case date, nowMin, position, atStopId, doneStopIds, scope, observation }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(date, forKey: .date)
        try c.encode(nowMin, forKey: .nowMin)
        try c.encode(position, forKey: .position)
        try c.encode(atStopId, forKey: .atStopId)
        try c.encode(doneStopIds, forKey: .doneStopIds)
        // `scope?:` and `observation?:` are optional, not nullable.
        try c.encodeIfPresent(scope, forKey: .scope)
        try c.encodeIfPresent(observation, forKey: .observation)
    }
}

// MARK: - v2: guidance, the planning conversation, going off-plan

/// A link the phone can open: a URL, `tel:`, or an app's universal link.
struct GuideLink: Codable, Hashable {
    var label: String
    var url: String
}

/// How to do one leg, for someone standing at the start of it.
struct LegGuidance: Codable, Hashable {
    struct Transit: Codable, Hashable {
        var line: String
        /// "bus", "tram", "metro", "train", "ferry" or "other". A String, so
        /// a new vehicle never fails the bundle.
        var vehicle: String
        var fromStop: String
        var toStop: String
        var stops: Double?
        /// Local minutes of the next few departures, when known.
        var departuresMin: [Double]
    }

    struct Booking: Codable, Hashable {
        var how: String
        var links: [GuideLink]
        var phone: String?
    }

    var summary: String
    var steps: [String]
    var transit: [Transit]?
    var booking: Booking?
    var tips: [String]
    var costText: String?
    /// "router", "model" or "mixed".
    var source: String
    var generatedAt: String
}

/// What to know at a stop: entry, tickets, dress code, what not to miss.
struct StopGuide: Codable, Hashable {
    var summary: String
    var tips: [String]
    var links: [GuideLink]
    var generatedAt: String
}

/// City-level know-how, made once per trip.
struct TripGuide: Codable, Hashable {
    var gettingAround: String
    var taxi: LegGuidance.Booking?
    var transitTickets: String?
    var tips: [String]
    var generatedAt: String
}

/// One turn of the planning conversation.
struct TripMessage: Codable, Hashable, Identifiable {
    enum Role: String, Codable, Hashable { case user, assistant, event }

    var id: String
    var role: Role
    var text: String
    /// `TripOp`s, kept as JSON: the phone only shows them.
    var ops: [TripJSON]
    var planVersion: Int?
    /// "site" or "phone".
    var surface: String
    var createdAt: String
    /// v3: what the planner looked up for this reply.
    var research: [ResearchStep]? = nil
}

/// `POST /api/native/trips/:id/converse` → one turn's answer.
struct ConverseResult: Codable, Hashable {
    struct Rejected: Codable, Hashable {
        var op: TripJSON
        var reason: String
    }

    var reply: String
    var applied: [TripJSON]
    var rejected: [Rejected]
    var quickReplies: [String]
    var planVersion: Int?
    var changes: [String]
    /// v3: what the planner looked up this turn.
    var research: [ResearchStep]? = nil
}

struct ConverseBody: Codable {
    var text: String
}

enum OffPlanKind: String, Codable, Hashable {
    case behind
    case offRoute = "off-route"
    case unplannedStop = "unplanned-stop"
    case outOfOrder = "out-of-order"
    case idle
}

/// What the phone saw that made it think the person is off the plan.
struct Observation: Codable, Hashable {
    struct Place: Codable, Hashable {
        var name: String?
        var location: TripLatLng
    }

    var kind: OffPlanKind
    var place: Place?
    /// Local minute the condition started.
    var sinceMin: Double
    /// "walking", "cycling", "automotive", "stationary" or "unknown".
    var motion: String
    var stopId: String?

    private enum Keys: String, CodingKey { case kind, place, sinceMin, motion, stopId }

    init(kind: OffPlanKind, place: Place?, sinceMin: Double, motion: String, stopId: String?) {
        self.kind = kind
        self.place = place
        self.sinceMin = sinceMin
        self.motion = motion
        self.stopId = stopId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        kind = try c.decode(OffPlanKind.self, forKey: .kind)
        place = try c.decodeIfPresent(Place.self, forKey: .place)
        sinceMin = try c.decode(Double.self, forKey: .sinceMin)
        motion = try c.decode(String.self, forKey: .motion)
        stopId = try c.decodeIfPresent(String.self, forKey: .stopId)
    }

    /// Nullable fields go up as null.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(place, forKey: .place)
        try c.encode(sinceMin, forKey: .sinceMin)
        try c.encode(motion, forKey: .motion)
        try c.encode(stopId, forKey: .stopId)
    }
}

/// A whole-trip re-plan from now: today and every later day.
struct TripReplanOption: Codable, Hashable, Identifiable {
    struct Moved: Codable, Hashable {
        var wishId: String
        var from: String?
        var to: String
    }

    var id: String
    var label: String
    /// "carry-on", "resolve-rest", "pull-forward" or "stay-here".
    var kind: String
    var days: [PlannedDay]
    var dropped: [String]
    var moved: [Moved]
    var explanation: String
}

// MARK: - v3: getting there and back, what the planner knows, its research

/// A source the planner or the research cited.
struct TripSource: Codable, Hashable {
    var url: String
    var title: String?
}

/// A flight, train or similar to, from or between places on the trip.
struct TransportSegment: Codable, Hashable, Identifiable {
    struct End: Codable, Hashable {
        var name: String
        /// "NCL", "FCO".
        var code: String?
        var location: TripLatLng?
        var timeZone: String
    }

    var id: String
    /// "flight", "train", "coach", "ferry" or "car".
    var kind: String
    /// "outbound", "return" or "internal".
    var direction: String
    var carrier: String?
    /// "LS1235".
    var number: String?
    var from: End
    var to: End
    /// Local to `from.timeZone`.
    var departDate: String
    var departMin: Double
    /// Local to `to.timeZone`.
    var arriveDate: String
    var arriveMin: Double
    /// "stated", "researched" or "live".
    var confidence: String
    /// "scheduled", "delayed", "departed", "landed" or "cancelled".
    var status: String?
    var delayMin: Double?
    var bookingRef: String?
    var sources: [TripSource]
    var checkedAt: String?

    /// `TRANSPORT_LEADS`: leaving the terminal, and arriving before departure.
    var leads: (exitMin: Double, checkInLeadMin: Double) {
        switch kind {
        case "flight": return (40, 120)
        case "train": return (10, 20)
        case "coach": return (10, 15)
        case "ferry": return (30, 60)
        default: return (0, 0)
        }
    }
}

/// What the planner already knows about the people travelling: from the
/// owner's memory, knowledge search and the family roster. Every item says
/// where it came from.
struct TravellerProfile: Codable, Hashable {
    struct Traveller: Codable, Hashable {
        var name: String
        var relation: String?
        var notes: [String]
    }

    struct Known: Codable, Hashable {
        var text: String
        /// "memory", "knowledge", "family" or "conversation".
        var source: String
        var ref: String?
    }

    var travellers: [Traveller]
    var preferences: [Known]
    var constraints: [Known]
    var history: [String]
    var gatheredAt: String
}

/// One thing the planner looked up during a turn.
struct ResearchStep: Codable, Hashable {
    var tool: String
    /// "Looked up LS1235 Newcastle → Rome on 27 Oct".
    var summary: String
    var sources: [TripSource]
}
