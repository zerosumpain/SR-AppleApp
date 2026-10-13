import Foundation
import CoreLocation

// MARK: - Demo trip
//
// `-SRDemo` (and the review demo) answers for `/api/native/trips` with one
// trip: a day in Rome, running NOW in Rome's time zone, so the CI screenshot
// of the Day screen shows a morning done, the person at the Pantheon and
// "Leave by … · 12 min walk" for the Trevi Fountain.
//
// The places are public landmarks; everything else is made up — the hotel,
// the booking reference, the prices, and every link (example.org), as the
// rest of the demo fixtures are. Times are generated around the moment of
// the request, so the day always reads as in progress.

extension SRDemoFixtures {
    static func tripsRoute(method: String, parts: [String], body: Data?, clock: DemoClock) -> String? {
        // parts: ["api", "native", "trips", ...]
        switch (method, parts.count) {
        case ("GET", 3):
            return TripDemo.json(TripList(trips: [TripDemo.bundle(now: clock.now).summary]))
        case ("GET", 4) where parts[3] == TripDemo.tripId:
            return TripDemo.json(TripDemo.bundle(now: clock.now))
        case ("POST", 5) where parts[4] == "events":
            let sent = (try? JSONDecoder().decode(TripEventsBody.self, from: body ?? Data()))?.events.map(\.clientId) ?? []
            return TripDemo.json(TripEventsReply(accepted: sent, planVersion: 3))
        case ("POST", 5) where parts[4] == "replan":
            return #"{"options":[]}"#
        default:
            return nil
        }
    }
}

enum TripDemo {
    static let tripId = "demo-rome"
    static let zone = "Europe/Rome"

    /// Where the demo phone is: at the Pantheon.
    static var here: CLLocationCoordinate2D? { CLLocationCoordinate2D(latitude: pantheon.lat, longitude: pantheon.lng) }

    @MainActor
    static func seed(into store: TripStore) {
        let now = Date()
        store.adoptDemo(bundle(now: now), marks: marks(now: now))
    }

    static func json<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Places

    private static let hotel = TripLatLng(lat: 41.8955, lng: 12.4722)
    private static let colosseum = TripLatLng(lat: 41.8902, lng: 12.4922)
    private static let monti = TripLatLng(lat: 41.8955, lng: 12.4935)
    private static let pantheon = TripLatLng(lat: 41.8986, lng: 12.4769)
    private static let trevi = TripLatLng(lat: 41.9009, lng: 12.4833)
    private static let spanishSteps = TripLatLng(lat: 41.9059, lng: 12.4823)
    private static let borghese = TripLatLng(lat: 41.9142, lng: 12.4923)
    private static let castel = TripLatLng(lat: 41.9031, lng: 12.4663)

    /// The anchor: Rome-local minutes now, rounded to five, kept inside a
    /// day so the plan never wraps past midnight.
    private static func anchor(_ now: Date) -> Double {
        let m = TripClock(zone).minutes(now)
        return min(max((m / 5).rounded() * 5, 11 * 60), 20 * 60)
    }

    static func marks(now: Date) -> [String: TripStopMark] {
        let clock = TripClock(zone)
        let date = clock.localDate(now)
        let a = anchor(now)
        func at(_ offset: Double) -> Date? { clock.date(date, minutes: a + offset) }
        return [
            "stay:\(date):start": TripStopMark(arrivedAt: nil, leftAt: at(-172)),
            "w-colosseum": TripStopMark(arrivedAt: at(-148), leftAt: at(-88)),
            "meal:\(date):lunch": TripStopMark(arrivedAt: at(-74), leftAt: at(-32)),
            "w-pantheon": TripStopMark(arrivedAt: at(-18)),
        ]
    }

    // MARK: The bundle

    static func bundle(now: Date) -> TripBundle {
        let clock = TripClock(zone)
        let today = clock.localDate(now)
        let start = clock.adding(days: -1, to: today) ?? today
        let end = clock.adding(days: 1, to: today) ?? today
        let a = anchor(now)
        let checked = TripStore.iso(now.addingTimeInterval(-2 * 86_400))

        let trip = Trip(
            id: tripId, ownerEmail: "alex@example.com", title: "Rome long weekend", destination: "Rome, Italy",
            timeZone: zone, startDate: start, endDate: end, pace: .normal, modes: [.walk, .transit],
            status: .active, notes: nil
        )
        let stay = TripStay(
            id: "stay-demo", name: "The demo hotel", address: "Via dell'Esempio 1, Rome", location: hotel,
            fromDate: start, toDate: end, checkInMin: 15 * 60, checkOutMin: 11 * 60
        )
        let wishes = [
            wish("w-colosseum", "Colosseum", colosseum, .must, 60, locked: true,
                 facts: facts("Mo-Su 08:30-19:00", open: 510, close: 1140, booking: true, price: "€18 (made up)",
                              summary: "The amphitheatre. Timed entry; the queue without a ticket is long.", checked: checked)),
            wish("w-pantheon", "Pantheon", pantheon, .must, 30,
                 facts: facts("Mo-Su 09:00-19:00", open: 540, close: 1140, booking: false, price: "€5 (made up)",
                              summary: "The domed temple, later a church. Quickest early or late in the day.", checked: checked)),
            wish("w-trevi", "Trevi Fountain", trevi, .nice, 20,
                 facts: facts("24/7", open: 0, close: 1440, booking: false, price: "Free",
                              summary: "Busy at every hour; a coin over the shoulder is the custom.", checked: checked)),
            wish("w-steps", "Spanish Steps", spanishSteps, .nice, 20, facts: nil),
            wish("w-borghese", "Villa Borghese gardens", borghese, .nice, 60, facts: nil),
            wish("w-castel", "Castel Sant'Angelo", castel, .nice, 90, facts: nil),
        ]
        let bookings = [
            TripBooking(id: "b-colosseum", wishId: "w-colosseum", title: "Colosseum timed entry", date: today,
                        startMin: a - 150, endMin: nil, reference: "DEMO-4821", url: "https://example.org/tickets/colosseum",
                        documentId: nil, status: .booked),
            TripBooking(id: "b-borghese", wishId: nil, title: "Borghese Gallery", date: end, startMin: nil, endMin: nil,
                        reference: nil, url: "https://example.org/tickets/borghese", documentId: nil, status: .toBook),
        ]

        func stop(_ id: String, _ kind: StopKind, _ wishId: String?, _ title: String, _ at: TripLatLng, _ arrive: Double, _ depart: Double,
                  locked: Bool = false, booking: String? = nil, warnings: [String] = []) -> PlannedStop {
            PlannedStop(id: id, kind: kind, wishId: wishId, title: title, location: at, arriveMin: a + arrive, departMin: a + depart,
                        waitSec: 0, locked: locked, bookingId: booking, warnings: warnings)
        }
        let stops = [
            stop("stay:\(today):start", .stay, nil, "The demo hotel", hotel, -172, -172),
            stop("w-colosseum", .wish, "w-colosseum", "Colosseum", colosseum, -150, -90, locked: true, booking: "b-colosseum"),
            stop("meal:\(today):lunch", .meal, nil, "Lunch", monti, -75, -30),
            stop("w-pantheon", .wish, "w-pantheon", "Pantheon", pantheon, -20, 8),
            stop("w-trevi", .wish, "w-trevi", "Trevi Fountain", trevi, 20, 45),
            stop("w-steps", .wish, "w-steps", "Spanish Steps", spanishSteps, 55, 80),
            stop("w-borghese", .wish, "w-borghese", "Villa Borghese gardens", borghese, 95, 155,
                 warnings: ["Gardens close at dusk — the later part may be in the dark"]),
            stop("stay:\(today):end", .stay, nil, "The demo hotel", hotel, 180, 180),
        ]
        let modes: [TravelMode] = [.transit, .walk, .walk, .walk, .walk, .walk, .transit]
        let legs: [PlannedLeg] = (0..<(stops.count - 1)).map { i in
            let from = stops[i], to = stops[i + 1]
            let metres = distance(from.location ?? hotel, to.location ?? hotel)
            let seconds = (to.arriveMin - from.departMin) * 60
            return PlannedLeg(
                fromStopId: from.id, toStopId: to.id, mode: modes[i], durationSec: max(60, seconds),
                distanceM: metres.rounded(), estimated: false,
                line: line(from.location ?? hotel, to.location ?? hotel)
            )
        }
        let day = PlannedDay(date: today, stayId: stay.id, stops: stops, legs: legs, warnings: [])
        let plan = TripPlanVersion(
            id: "demo-plan-3", version: 3, createdAt: checked,
            plan: SolvedPlan(days: [day], dropped: [DroppedWish(wishId: "w-castel", reason: "Did not fit; no other day had room")], warnings: [], score: 0),
            changes: []
        )
        return TripBundle(
            trip: trip, stays: [stay], wishes: wishes, bookings: bookings, plan: plan,
            matrices: [today: matrix(wishes: wishes, stay: stay)], etag: "demo-3"
        )
    }

    private static func wish(_ id: String, _ title: String, _ at: TripLatLng, _ priority: TripPriority, _ minutes: Double,
                             locked: Bool = false, facts: TripFacts?) -> TripWish {
        TripWish(
            id: id, title: title, place: TripPlace(name: title, location: at, osmId: nil, address: nil),
            priority: priority, durationSec: minutes * 60, partOfDay: .any, fixedDate: nil, fixedStartMin: nil,
            locked: locked, suggested: false, skipped: false, facts: facts, note: nil, sortHint: 0
        )
    }

    private static func facts(_ text: String, open: Double, close: Double, booking: Bool, price: String, summary: String, checked: String) -> TripFacts {
        let week = Dictionary(uniqueKeysWithValues: (1...7).map { (String($0), [TripOpenRange(openMin: open, closeMin: close)]) })
        return TripFacts(
            openingHoursText: text, hours: week, closedDates: [], bookingRequired: booking,
            bookAheadDays: booking ? 7 : nil, bookingUrl: booking ? "https://example.org/tickets" : nil,
            officialUrl: "https://example.org/", priceText: price, typicalVisitSec: nil, summary: summary,
            sources: [TripFacts.Source(url: "https://example.org/guide", title: "A made-up guide")],
            checkedAt: checked, depth: "brief", unknown: []
        )
    }

    /// Walk at 1.3 m/s on 1.3× the straight line; transit at three times
    /// that plus five minutes of waiting. Enough for the demo's re-plans.
    private static func matrix(wishes: [TripWish], stay: TripStay) -> TravelMatrix {
        let points = wishes.map(\.id) + ["stay:\(stay.id)"]
        let places = wishes.map { $0.place?.location ?? stay.location } + [stay.location]
        func grid(_ f: (Double) -> Double) -> [[Double?]] {
            places.map { a in places.map { b -> Double? in f(distance(a, b) * 1.3).rounded() } }
        }
        return TravelMatrix(
            points: points,
            seconds: ["walk": grid { $0 / 1.3 }, "transit": grid { $0 / 3.9 + 300 }],
            metres: ["walk": grid { $0 }, "transit": grid { $0 }],
            estimated: ["walk": true, "transit": true]
        )
    }

    private static func distance(_ a: TripLatLng, _ b: TripLatLng) -> Double {
        CLLocation(latitude: a.lat, longitude: a.lng).distance(from: CLLocation(latitude: b.lat, longitude: b.lng))
    }

    /// Twelve points from a to b with a gentle bend — a drawn line, and
    /// enough points for the follow screen's demo walk.
    private static func line(_ a: TripLatLng, _ b: TripLatLng) -> [TripLatLng] {
        (0...11).map { i in
            let t = Double(i) / 11
            let bend = sin(t * .pi) * 0.0006
            return TripLatLng(lat: a.lat + (b.lat - a.lat) * t + bend, lng: a.lng + (b.lng - a.lng) * t - bend)
        }
    }
}
