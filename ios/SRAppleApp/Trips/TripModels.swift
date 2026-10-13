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

enum TravelMode: String, Codable, CaseIterable, Hashable {
    case walk, cycle, drive, transit
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

enum StopKind: String, Codable, Hashable {
    case wish, meal, stay
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
        case fromStopId, toStopId, mode, durationSec, distanceM, estimated, line
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
    private enum Keys: String, CodingKey { case date, nowMin, position, atStopId, doneStopIds }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(date, forKey: .date)
        try c.encode(nowMin, forKey: .nowMin)
        try c.encode(position, forKey: .position)
        try c.encode(atStopId, forKey: .atStopId)
        try c.encode(doneStopIds, forKey: .doneStopIds)
    }
}
