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
            return #"{"options":[],"tripOptions":[],"narrative":null}"#
        case ("POST", 5) where parts[4] == "converse":
            let said = (try? JSONDecoder().decode(ConverseBody.self, from: body ?? Data()))?.text ?? ""
            return TripDemo.json(TripDemo.converse(said))
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
            "w-pantheon": SRDemo.isOffPlanShot
                ? TripStopMark(arrivedAt: at(-18), leftAt: at(-14))
                : TripStopMark(arrivedAt: at(-18)),
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
            timeZone: zone, startDate: start, endDate: end, pace: .normal, modes: [.walk, .transit, .taxi],
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
        let modes: [TravelMode] = [.transit, .walk, .walk, .walk, .walk, .taxi, .transit]
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
        var guided = legs
        guided[3].guidance = walkGuidance(checked)
        guided[5].guidance = taxiGuidance(checked)
        guided[6].guidance = transitGuidance(a + 155, checked)
        guided[0].guidance = transitGuidance(a - 172, checked)
        let day = PlannedDay(date: today, stayId: stay.id, stops: stops, legs: guided, warnings: [])
        let plan = TripPlanVersion(
            id: "demo-plan-3", version: 3, createdAt: checked,
            plan: SolvedPlan(days: [day], dropped: [DroppedWish(wishId: "w-castel", reason: "Did not fit; no other day had room")], warnings: [], score: 0),
            changes: []
        )
        var withGuides = wishes
        withGuides[1].guide = StopGuide(
            summary: "Free to look in from the portico; inside needs a timed ticket. The dome's oculus is open to the sky.",
            tips: ["Shoulders and knees covered", "Queue moves fastest in the first hour", "Look straight up from the centre of the floor"],
            links: [GuideLink(label: "Tickets (made up)", url: "https://example.org/tickets/pantheon")],
            generatedAt: checked
        )
        withGuides[2].guide = StopGuide(
            summary: "Busy at every hour. The steps on the right-hand side are usually quieter.",
            tips: ["A coin over the left shoulder, with the right hand", "Mind your pockets in the crowd"],
            links: [], generatedAt: checked
        )
        let matrixAll = matrix(wishes: wishes, stay: stay)
        return TripBundle(
            trip: trip, stays: [stay], wishes: withGuides, bookings: bookings, plan: plan,
            matrices: [today: matrixAll], etag: "demo-3",
            messages: messages(now: now), guide: tripGuide(checked), tripMatrix: matrixAll
        )
    }

    // MARK: Guidance and the conversation (all made up)

    private static func walkGuidance(_ at: String) -> LegGuidance {
        LegGuidance(
            summary: "12 min walk via Via del Seminario", steps: [
                "Leave Piazza della Rotonda by the north-east corner",
                "Via del Seminario to Piazza di Sant'Ignazio",
                "Via delle Muratte to the fountain",
            ],
            transit: nil, booking: nil, tips: ["Flat all the way; cobbles in places"], costText: nil,
            source: "mixed", generatedAt: at
        )
    }

    private static func taxiGuidance(_ at: String) -> LegGuidance {
        LegGuidance(
            summary: "8 min by taxi from the rank at Piazza di Spagna", steps: [],
            transit: nil,
            booking: LegGuidance.Booking(
                how: "There is a taxi rank at the foot of the Spanish Steps. Only take the white licensed cars; a city app can book one too.",
                links: [GuideLink(label: "Taxi app (made up)", url: "https://example.org/taxi")], phone: nil
            ),
            tips: ["Fares inside the walls are fixed-ish; ask before you set off"], costText: "About €10–12 (made up)",
            source: "model", generatedAt: at
        )
    }

    private static func transitGuidance(_ from: Double, _ at: String) -> LegGuidance {
        LegGuidance(
            summary: "Bus 64 back to the hotel, 6 stops", steps: [],
            transit: [LegGuidance.Transit(line: "64", vehicle: "bus", fromStop: "Demo stop A", toStop: "Demo stop B",
                                          stops: 6, departuresMin: [from + 4, from + 12, from + 20])],
            booking: nil, tips: ["Validate the ticket on board"], costText: "€1.50 (made up)",
            source: "router", generatedAt: at
        )
    }

    private static func tripGuide(_ at: String) -> TripGuide {
        TripGuide(
            gettingAround: "The centre is walkable; buses fill the gaps and taxis wait at the big squares.",
            taxi: LegGuidance.Booking(how: "White licensed cars only, from a rank or an app.", links: [GuideLink(label: "Taxi app (made up)", url: "https://example.org/taxi")], phone: nil),
            transitTickets: "Buy a 100-minute ticket at a tabacchi before boarding (made up)",
            tips: ["Most churches ask for covered shoulders and knees"], generatedAt: at
        )
    }

    private static func messages(now: Date) -> [TripMessage] {
        func m(_ id: String, _ role: TripMessage.Role, _ text: String, ops: Int = 0, ago: Double) -> TripMessage {
            TripMessage(id: id, role: role, text: text, ops: Array(repeating: .object(["op": .string("updateWish")]), count: ops),
                        planVersion: ops > 0 ? 3 : nil, surface: "phone", createdAt: TripStore.iso(now.addingTimeInterval(-ago * 60)))
        }
        return [
            m("demo-msg-1", .user, "Can we fit the Trevi Fountain in after the Pantheon today?", ago: 300),
            m("demo-msg-2", .assistant, "Yes — it's a 12 minute walk from the Pantheon, so it slots in straight after. I've moved the Spanish Steps to follow it and kept your Colosseum slot where it is.", ops: 2, ago: 299),
            m("demo-msg-3", .user, "And a taxi up to the Borghese gardens rather than the walk?", ago: 120),
            m("demo-msg-4", .assistant, "Done: a taxi from the rank at the Spanish Steps, about 8 minutes. The gardens close at dusk, so the end of the visit may be in the dark.", ops: 1, ago: 119),
        ]
    }

    static func converse(_ said: String) -> ConverseResult {
        ConverseResult(
            reply: "In the demo nothing changes, but on a real trip I would re-plan the rest of today around that.",
            applied: [], rejected: [],
            quickReplies: ["Make the rest of today lighter", "What's near here?"],
            planVersion: nil, changes: []
        )
    }

    /// `-SRDemoOffPlan`: a coffee off the plan after the Pantheon, with the
    /// planner's view and three ways on.
    @MainActor
    static func seedOffPlan(into offPlan: TripOffPlan) {
        guard SRDemo.isOffPlanShot else { return }
        let now = Date()
        let clock = TripClock(zone)
        let date = clock.localDate(now)
        let a = anchor(now)
        let b = bundle(now: now)
        guard let today = b.day(date) else { return }
        let context = TripReplan.Context(trip: b.trip, stays: b.stays, wishes: b.wishes, bookings: b.bookings, matrix: b.matrices[date]!)
        let trevi = today.index(of: "w-trevi") ?? 4
        let stay = TripReplan.retimeDay(today, fromIndex: trevi, startMin: a + 20, context: context)
        var lighter = today
        lighter.stops.removeAll { $0.id == "w-steps" }
        let dropped = TripReplan.retimeDay(lighter, fromIndex: trevi, startMin: a + 5, context: context)
        let observation = Observation(
            kind: .unplannedStop, place: Observation.Place(name: "a café on Via della Palombella", location: TripLatLng(lat: 41.8979, lng: 12.4762)),
            sinceMin: a - 14, motion: "stationary", stopId: nil
        )
        offPlan.adoptDemo(
            TripOffPlan.Prompt(
                id: "demo-offplan", tripId: tripId, date: date, observation: observation,
                headline: TripOffPlanRules.headline(observation, day: today, nowMin: a), slotAtRisk: false
            ),
            narrative: "Looks like a coffee stop. The Trevi Fountain is 10 minutes away and nothing after it is booked, so there's room to sit a while.",
            choices: [
                .trip(TripReplanOption(id: "carry-on", label: "Carry on to the Trevi Fountain now", kind: "carry-on", days: [today], dropped: [], moved: [],
                                       explanation: "Leave in the next few minutes and the afternoon runs as planned.")),
                .trip(TripReplanOption(id: "stay-here", label: "Stay 20 min more, push the rest back", kind: "stay-here", days: [stay], dropped: [], moved: [],
                                       explanation: "Everything after shifts later; back at the hotel a little after planned.")),
                .trip(TripReplanOption(id: "drop:w-steps", label: "Stay, and drop the Spanish Steps", kind: "resolve-rest", days: [dropped], dropped: ["w-steps"], moved: [],
                                       explanation: "Keeps the evening the same; the Steps can go on another day.")),
            ]
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
