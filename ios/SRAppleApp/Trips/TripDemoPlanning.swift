import Foundation

// MARK: - Demo: a trip being planned (v8)
//
// `-SRDemo` (and the review demo) holds a second Rome trip, five days from
// now, so every v8 screen has something to show: the planning home with its
// brief (one fact assumed), three quick questions, trip shapes and a dinner
// to choose; a stop to swap; a day to make lighter; the guided start with
// research that ticks through its stages; what changed, and Undo.
//
// The decisions are written in the wire's own shapes (as
// `Fixtures/TripDecisions/decisions-wire.json`) and decoded, so the demo
// runs through the same decoder a real server's answer does. Everything is
// made up: names (Alex, Sam, Robin, Kit), prices, links (example.org). The
// places are public landmarks.
//
// Decisions made in the demo are remembered in memory for the session
// (`DemoDecisions`), so a used proposal does not come back on the next read.

extension TripDemo {
    static let planTripId = "demo-rome-plan"

    /// The planning trip's days: five, starting five days from today.
    static func planDates(now: Date) -> [String] {
        let clock = TripClock(zone)
        let today = clock.localDate(now)
        return (5...9).compactMap { clock.adding(days: $0, to: today) }
    }

    // MARK: Places (public landmarks)

    private static let flat = TripLatLng(lat: 41.8975, lng: 12.4710)
    private static let navona = TripLatLng(lat: 41.8992, lng: 12.4731)
    private static let colosseumP = TripLatLng(lat: 41.8902, lng: 12.4922)
    private static let forum = TripLatLng(lat: 41.8925, lng: 12.4853)
    private static let montiP = TripLatLng(lat: 41.8955, lng: 12.4935)
    private static let capitoline = TripLatLng(lat: 41.8930, lng: 12.4828)
    private static let vatican = TripLatLng(lat: 41.9065, lng: 12.4536)
    private static let pantheonP = TripLatLng(lat: 41.8986, lng: 12.4769)
    private static let treviP = TripLatLng(lat: 41.9009, lng: 12.4833)
    private static let stepsP = TripLatLng(lat: 41.9059, lng: 12.4823)
    private static let campo = TripLatLng(lat: 41.8956, lng: 12.4722)
    private static let trastevere = TripLatLng(lat: 41.8897, lng: 12.4700)
    private static let gianicolo = TripLatLng(lat: 41.8919, lng: 12.4613)
    private static let altemps = TripLatLng(lat: 41.9007, lng: 12.4728)
    private static let massimo = TripLatLng(lat: 41.9014, lng: 12.4977)
    private static let doria = TripLatLng(lat: 41.8980, lng: 12.4815)
    private static let fco = TripLatLng(lat: 41.8003, lng: 12.2389)

    // MARK: The bundle

    static func planningBundle(now: Date) -> TripBundle {
        let d = planDates(now: now)
        let checked = TripStore.iso(now.addingTimeInterval(-86_400))
        let trip = Trip(
            id: planTripId, createdById: "demo-alex", createdByName: "Alex", title: "Rome with the family", destination: "Rome, Italy",
            timeZone: zone, startDate: d[0], endDate: d[4], pace: .normal, modes: [.walk, .transit, .taxi],
            status: .planned, notes: nil, dayLoads: [d[0]: "light"]
        )
        let stay = TripStay(id: "stay-plan", name: "The demo flat, Parione", address: "Via dell'Esempio 2, Rome", location: flat,
                            fromDate: d[0], toDate: d[4], checkInMin: 15 * 60, checkOutMin: 10 * 60)
        func wish(_ id: String, _ title: String, _ at: TripLatLng, _ minutes: Double, must: Bool = false, locked: Bool = false,
                  booking: Bool = false, ahead: Double? = nil, price: String? = nil) -> TripWish {
            let facts = (booking || price != nil) ? TripFacts(
                openingHoursText: nil, hours: nil, closedDates: [], bookingRequired: booking, bookAheadDays: ahead,
                bookingUrl: booking ? "https://example.org/tickets/\(id)" : nil, officialUrl: nil, priceText: price,
                typicalVisitSec: minutes * 60, summary: nil,
                sources: [TripFacts.Source(url: "https://example.org/guide", title: "A made-up guide")],
                checkedAt: checked, depth: "brief", unknown: []
            ) : nil
            return TripWish(id: id, title: title, place: TripPlace(name: title, location: at, osmId: nil, address: nil),
                            priority: must ? .must : .nice, durationSec: minutes * 60, partOfDay: .any, fixedDate: nil,
                            fixedStartMin: nil, locked: locked, suggested: false, skipped: false, facts: facts, note: nil, sortHint: 0)
        }
        let wishes = [
            wish("p-navona", "Piazza Navona", navona, 40),
            wish("p-colosseum", "Colosseum underground", colosseumP, 120, must: true, booking: true, ahead: 14, price: "€24 each (made up)"),
            wish("p-forum", "Roman Forum", forum, 75),
            wish("p-capitoline", "Capitoline Museums", capitoline, 90, price: "€15 each (made up)"),
            wish("p-vatican", "Vatican tour", vatican, 180, must: true, locked: true),
            wish("p-pantheon", "Pantheon", pantheonP, 40, booking: true, ahead: 1, price: "€5 each (made up)"),
            wish("p-trevi", "Trevi Fountain", treviP, 25),
            wish("p-steps", "Spanish Steps", stepsP, 25),
            wish("p-campo", "Campo de' Fiori market", campo, 50),
            wish("p-trastevere", "Trastevere", trastevere, 90),
            wish("p-gianicolo", "Gianicolo walk", gianicolo, 60),
        ]
        let days = [
            planDay(d[0], [
                ("transport:plan-out:arrive", .transport, nil, "Flight lands at Rome Fiumicino", fco, 690, 720, "morning"),
                ("stay:\(d[0]):bags", .stay, nil, "Drop bags at the flat", flat, 775, 785, "lunch"),
                ("meal:\(d[0]):lunch", .meal, nil, "Lunch", campo, 795, 855, "lunch"),
                ("p-navona", .wish, "p-navona", "Piazza Navona", navona, 1020, 1060, "evening"),
                ("meal:\(d[0]):dinner", .meal, nil, "Dinner", navona, 1170, 1245, "evening"),
                ("stay:\(d[0]):end", .stay, nil, "The demo flat", flat, 1260, 1260, "evening"),
            ]),
            planDay(d[1], [
                ("stay:\(d[1]):start", .stay, nil, "The demo flat", flat, 510, 510, "morning"),
                ("p-colosseum", .wish, "p-colosseum", "Colosseum underground", colosseumP, 540, 660, "morning"),
                ("p-forum", .wish, "p-forum", "Roman Forum", forum, 670, 745, "morning"),
                ("meal:\(d[1]):lunch", .meal, nil, "Lunch in Monti", montiP, 760, 850, "lunch"),
                ("p-capitoline", .wish, "p-capitoline", "Capitoline Museums", capitoline, 900, 990, "afternoon"),
                ("meal:\(d[1]):dinner", .meal, nil, "Dinner", campo, 1150, 1230, "evening"),
                ("stay:\(d[1]):end", .stay, nil, "The demo flat", flat, 1240, 1240, "evening"),
            ]),
            planDay(d[2], [
                ("stay:\(d[2]):start", .stay, nil, "The demo flat", flat, 465, 465, "morning"),
                ("p-vatican", .wish, "p-vatican", "Vatican tour", vatican, 495, 675, "morning"),
                ("meal:\(d[2]):lunch", .meal, nil, "Lunch", vatican, 690, 765, "lunch"),
                ("p-pantheon", .wish, "p-pantheon", "Pantheon", pantheonP, 910, 950, "afternoon"),
                ("p-trevi", .wish, "p-trevi", "Trevi Fountain", treviP, 980, 1005, "afternoon"),
                ("p-steps", .wish, "p-steps", "Spanish Steps", stepsP, 1020, 1045, "afternoon"),
                ("meal:\(d[2]):dinner", .meal, nil, "Dinner", trastevere, 1170, 1245, "evening"),
                ("stay:\(d[2]):end", .stay, nil, "The demo flat", flat, 1260, 1260, "evening"),
            ]),
            planDay(d[3], [
                ("stay:\(d[3]):start", .stay, nil, "The demo flat", flat, 555, 555, "morning"),
                ("p-campo", .wish, "p-campo", "Campo de' Fiori market", campo, 570, 620, "morning"),
                ("meal:\(d[3]):lunch", .meal, nil, "Lunch", trastevere, 750, 820, "lunch"),
                ("p-gianicolo", .wish, "p-gianicolo", "Gianicolo walk", gianicolo, 870, 930, "afternoon"),
                ("p-trastevere", .wish, "p-trastevere", "Trastevere", trastevere, 1050, 1140, "evening"),
                ("meal:\(d[3]):dinner", .meal, nil, "Dinner", trastevere, 1140, 1230, "evening"),
                ("stay:\(d[3]):end", .stay, nil, "The demo flat", flat, 1260, 1260, "evening"),
            ]),
            planDay(d[4], [
                ("stay:\(d[4]):start", .stay, nil, "The demo flat", flat, 420, 420, "morning"),
                ("transport:plan-back:depart", .transport, nil, "Flight from Rome Fiumicino", fco, 520, 640, "morning"),
            ]),
        ]
        let plan = TripPlanVersion(id: "demo-plan-plan-12", version: 12 + DemoDecisions.shared.versionBump, createdAt: checked,
                                   plan: SolvedPlan(days: days, dropped: [], warnings: [], score: 0), changes: [])
        let bookings = [
            TripBooking(id: "pb-vatican", wishId: "p-vatican", title: "Vatican tour", date: d[2], startMin: 495, endMin: 675,
                        reference: "DEMO-VT12", url: "https://example.org/tickets/vatican", documentId: nil, status: .booked),
            TripBooking(id: "pb-pantheon", wishId: "p-pantheon", title: "Pantheon timed entry", date: d[2], startMin: nil, endMin: nil,
                        reference: nil, url: "https://example.org/tickets/pantheon", documentId: nil, status: .toBook),
        ]
        let transport = [
            TransportSegment(id: "plan-out", kind: "flight", direction: "outbound", carrier: "Demo Air", number: "DM 735",
                             from: .init(name: "Newcastle", code: "NCL", location: nil, timeZone: "Europe/London"),
                             to: .init(name: "Rome Fiumicino", code: "FCO", location: fco, timeZone: zone),
                             departDate: d[0], departMin: 455, arriveDate: d[0], arriveMin: 690, confidence: "stated", status: nil,
                             delayMin: nil, bookingRef: "DEMO8R", sources: [], checkedAt: nil),
            TransportSegment(id: "plan-back", kind: "flight", direction: "return", carrier: "Demo Air", number: "DM 736",
                             from: .init(name: "Rome Fiumicino", code: "FCO", location: fco, timeZone: zone),
                             to: .init(name: "Newcastle", code: "NCL", location: nil, timeZone: "Europe/London"),
                             departDate: d[4], departMin: 640, arriveDate: d[4], arriveMin: 765, confidence: "stated", status: nil,
                             delayMin: nil, bookingRef: "DEMO8R", sources: [], checkedAt: nil),
        ]
        var bundle = TripBundle(
            trip: trip, stays: [stay], wishes: wishes, bookings: bookings, plan: plan, matrices: [:],
            etag: "demo-plan-\(DemoDecisions.shared.versionBump)", messages: [], guide: nil, tripMatrix: nil, transport: transport,
            profile: TravellerProfile(travellers: [
                .init(name: "Alex", relation: nil, age: 41, personId: "alex"),
                .init(name: "Sam", relation: "child", age: 9, personId: "sam"),
                .init(name: "Robin", relation: "child", age: 6, personId: "robin"),
                .init(name: "Kit", relation: nil, age: nil, personId: "kit"),
            ]),
            access: SRDemo.isMember ? TripAccess(canEdit: false, canApprove: false, canSuggest: true, role: "member") : .owner
        )
        let wire = decisions(now: now)
        bundle.brief = wire.brief
        bundle.questions = wire.questions
        bundle.answered = wire.answered
        // Rain on the fourth afternoon: the planner proposes a swap for the
        // walk (mockup 6), solved like any other.
        let state = DemoDecisions.shared.snapshot()
        let rain = proposals(.swap(stopId: "p-gianicolo", wishId: "p-gianicolo", date: d[3]), bundle: bundle, now: now)
            .map { p -> TripProposal in
                var p = p
                p.why = "Indoors for the afternoon's rain. " + p.why
                return p
            }
            .filter { !state.proposals.contains($0.id) && !state.groups.contains($0.groupId) }
        bundle.proposals = TripDecisions.canDecide(bundle.can) ? wire.proposals + rain.filter { r in !wire.proposals.contains { $0.groupId == r.groupId } } : []
        bundle.pack = wire.pack
        return bundle
    }

    private typealias StopRow = (id: String, kind: StopKind, wishId: String?, title: String, at: TripLatLng, arrive: Double, depart: Double, stage: String)

    private static func planDay(_ date: String, _ rows: [StopRow]) -> PlannedDay {
        let stops = rows.map { r in
            PlannedStop(id: r.id, kind: r.kind, wishId: r.wishId, title: r.title, location: r.at, arriveMin: r.arrive, departMin: r.depart,
                        waitSec: 0, locked: r.id == "p-vatican", bookingId: r.id == "p-vatican" ? "pb-vatican" : nil, warnings: [], stage: r.stage)
        }
        let legs: [PlannedLeg] = stops.count < 2 ? [] : (0..<(stops.count - 1)).map { i in
            let a = stops[i].location ?? flat, b = stops[i + 1].location ?? flat
            let far = metres(a, b) > 4000
            return PlannedLeg(fromStopId: stops[i].id, toStopId: stops[i + 1].id, mode: far ? .taxi : .walk,
                              durationSec: max(120, metres(a, b) / (far ? 8 : 1.3)), distanceM: metres(a, b).rounded(),
                              estimated: true, line: nil)
        }
        return PlannedDay(date: date, stayId: "stay-plan", stops: stops, legs: legs, warnings: [])
    }

    private static func metres(_ a: TripLatLng, _ b: TripLatLng) -> Double {
        let r = 6_371_000.0, dLat = (b.lat - a.lat) * .pi / 180, dLng = (b.lng - a.lng) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(a.lat * .pi / 180) * cos(b.lat * .pi / 180) * sin(dLng / 2) * sin(dLng / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }

    // MARK: Decisions, in the wire's shapes

    /// The brief, questions, proposals and pack, decoded from JSON written as
    /// the server writes it — with the session's decisions taken out.
    static func decisions(now: Date) -> DecisionsWire {
        let d = planDates(now: now)
        let clock = TripClock(zone)
        let today = clock.localDate(now)
        let colosseumDue = clock.adding(days: -14, to: d[1]) ?? today
        var json = decisionsTemplate
        for (i, date) in d.enumerated() { json = json.replacingOccurrences(of: "{D\(i)}", with: date) }
        json = json.replacingOccurrences(of: "{DUE}", with: colosseumDue)
        json = json.replacingOccurrences(of: "{RANGE}", with: TripFormat.range(d[0], d[4], zone: clock.zone))
        json = json.replacingOccurrences(of: "{NOW}", with: TripStore.iso(now))
        guard var wire = try? JSONDecoder().decode(DecisionsWire.self, from: Data(json.utf8)) else {
            return DecisionsWire(brief: TripBrief(items: [], assumed: 0, missing: []), questions: [], answered: [], proposals: [],
                                 pack: PackSummary(status: "none", stage: nil, builtAt: nil, refreshedAt: nil,
                                                   counts: .init(places: 0, food: 0, toBook: 0, lessVisited: 0, rainy: 0),
                                                   calendar: [], neighbourhoods: [], highlights: []))
        }
        let state = DemoDecisions.shared.snapshot()
        wire.proposals = wire.proposals.filter { p in
            !state.proposals.contains(p.id) && !state.groups.contains(p.groupId)
                && !(p.kind == .shape && state.groups.contains("shapes:demo"))
        } + state.extra.filter { p in
            !state.proposals.contains(p.id) && !state.groups.contains(p.groupId) && d.contains(p.scope.date ?? "")
        }
        wire.questions = wire.questions.compactMap { q in
            guard let answer = state.answers[q.id] else { return q }
            if answer.hasPrefix("vote:") {
                var voted = q
                voted.votes[String(answer.dropFirst(5)), default: []].append(SRDemo.isMember ? "Sam" : "Alex")
                return voted
            }
            return nil
        }
        wire.brief.items = wire.brief.items.map { item in
            var i = item
            if state.confirmed.contains(item.key) { i.origin = .you }
            return i
        }
        wire.brief.assumed = wire.brief.items.filter(\.isAssumed).count
        return wire
    }

    private static let decisionsTemplate = #"""
    {
      "brief": {
        "items": [
          { "key": "destination", "kind": "destination", "label": "Rome", "detail": "Rome, Italy · Europe/Rome", "origin": "you", "note": null, "ref": null, "editable": true },
          { "key": "dates", "kind": "dates", "label": "{RANGE}", "detail": "Five days", "origin": "you", "note": null, "ref": null, "editable": true },
          { "key": "travellers", "kind": "travellers", "label": "Alex, Sam + 2", "detail": "Alex, Sam (9), Robin (6), Kit", "origin": "notes", "note": null, "ref": null, "editable": true },
          { "key": "pace", "kind": "pace", "label": "Normal pace", "detail": null, "origin": "you", "note": null, "ref": null, "editable": true },
          { "key": "stay:stay-plan", "kind": "stay", "label": "Stay: Parione", "detail": "A flat near Piazza Navona, four nights", "origin": "notes", "note": null, "ref": null, "editable": true },
          { "key": "transport:plan-out", "kind": "transport", "label": "NCL 07:35 → FCO", "detail": "Lands 11:30", "origin": "notes", "note": null, "ref": null, "editable": false },
          { "key": "meal-times", "kind": "assumption", "label": "Dinner around 19:30", "detail": "Assumed from the pace; change it if you eat later", "origin": "assumed", "note": "Assumed: normal pace", "ref": null, "editable": true }
        ],
        "assumed": 1,
        "missing": []
      },
      "questions": [
        {
          "id": "dq-after-vatican", "key": "after-vatican-{D2}", "origin": "tie",
          "prompt": "After the Vatican tour on Wednesday — rest or carry on?",
          "why": "Changes Wednesday afternoon (3 stops)",
          "answers": [
            { "id": "a0", "label": "Back to the flat", "ops": [], "brief": null, "remember": null, "summary": "Wednesday afternoon: a rest at the flat, Trevi moves to Thursday", "changes": 3 },
            { "id": "a1", "label": "Carry on", "ops": [], "brief": null, "remember": null, "summary": null, "changes": 0 }
          ],
          "defaultAnswerId": "a1", "appliedDefault": true, "ifSkipped": "Carry on, with a long lunch.",
          "affects": { "dates": ["{D2}"], "stops": 3 }, "impact": 3, "audience": "owner", "deadline": null,
          "status": "open", "answerId": null, "answeredByName": null, "votes": {}, "basedOnVersion": 12,
          "createdAt": "{NOW}", "answeredAt": null
        },
        {
          "id": "dq-colosseum", "key": "book-colosseum-underground", "origin": "research",
          "prompt": "Colosseum underground needs a timed ticket, about 14 days ahead. Include it?",
          "why": "Changes Tuesday morning (2 stops)",
          "answers": [
            { "id": "a0", "label": "Yes, I'll book", "ops": [], "brief": null, "remember": null, "summary": "Tuesday morning: the underground tour at 09:00", "changes": 2 },
            { "id": "a1", "label": "Standard ticket", "ops": [], "brief": null, "remember": null, "summary": null, "changes": 0 },
            { "id": "a2", "label": "Skip the Colosseum", "ops": [], "brief": null, "remember": null, "summary": "Tuesday morning: Palazzo Massimo instead", "changes": 2 }
          ],
          "defaultAnswerId": "a1", "appliedDefault": true, "ifSkipped": "Standard ticket, no timed slot.",
          "affects": { "dates": ["{D1}"], "stops": 2 }, "impact": 2, "audience": "family", "deadline": "{DUE}",
          "status": "open", "answerId": null, "answeredByName": null, "votes": { "a0": ["Sam"] }, "basedOnVersion": 12,
          "createdAt": "{NOW}", "answeredAt": null
        },
        {
          "id": "dq-evenings", "key": "evening-food", "origin": "planner",
          "prompt": "Most evenings: trattoria, pizza, or a mix?",
          "why": "Changes where dinner is on four evenings",
          "answers": [
            { "id": "a0", "label": "Trattoria", "ops": [], "brief": null, "remember": "We like a proper trattoria in the evening", "summary": "Four dinners at trattorias near the day's last stop", "changes": 4 },
            { "id": "a1", "label": "Pizza", "ops": [], "brief": null, "remember": null, "summary": "Four pizzerias, earlier and quicker", "changes": 4 },
            { "id": "a2", "label": "A mix", "ops": [], "brief": null, "remember": null, "summary": null, "changes": 0 }
          ],
          "defaultAnswerId": "a2", "appliedDefault": true, "ifSkipped": "A mix, close to wherever the day ends.",
          "affects": { "dates": ["{D0}", "{D1}", "{D2}", "{D3}"], "stops": 4 }, "impact": 1, "audience": "family", "deadline": null,
          "status": "open", "answerId": null, "answeredByName": null, "votes": {}, "basedOnVersion": 12,
          "createdAt": "{NOW}", "answeredAt": null
        }
      ],
      "answered": [],
      "proposals": [
        {
          "id": "dp-shape-ancient", "groupId": "shapes:demo", "kind": "shape",
          "title": "Ancient Rome first, slow afternoons",
          "why": "The big ancient sites in the cool of the morning, then gentle afternoons near the flat.",
          "scope": { "date": null, "stage": null, "stopId": null, "wishId": null }, "ops": [],
          "diff": { "lines": ["First plan."], "changes": [], "dates": [], "walkDeltaM": null, "dropped": [] },
          "tradeoffs": { "fits": true, "fitText": null, "walkMin": null, "walkKmPerDay": 6.1, "earlyStarts": 2, "toBook": 2, "costText": null, "indoor": null, "kidFriendly": true, "lessVisited": true, "pushesOut": [], "moves": [] },
          "evidence": [], "place": null, "image": null, "packPlaceId": null,
          "shape": { "headline": "Ancient Rome first, slow afternoons", "days": [
            { "date": "{D0}", "line": "Land 11:30, Navona at dusk" },
            { "date": "{D1}", "line": "Colosseum early, lunch in Monti" },
            { "date": "{D2}", "line": "Vatican tour, then the Pantheon" },
            { "date": "{D3}", "line": "Market morning, Trastevere night" },
            { "date": "{D4}", "line": "Leave 07:40 for the 10:40 flight" } ], "leavesOut": ["Borghese Gallery"] },
          "preview": [], "basedOnVersion": 12, "status": "open", "reason": null, "createdAt": "{NOW}", "decidedAt": null
        },
        {
          "id": "dp-shape-three", "groupId": "shapes:demo", "kind": "shape",
          "title": "The big three on separate mornings",
          "why": "Colosseum, Vatican and Borghese each get a fresh morning; afternoons stay flexible.",
          "scope": { "date": null, "stage": null, "stopId": null, "wishId": null }, "ops": [],
          "diff": { "lines": ["First plan."], "changes": [], "dates": [], "walkDeltaM": null, "dropped": [] },
          "tradeoffs": { "fits": true, "fitText": null, "walkMin": null, "walkKmPerDay": 8.0, "earlyStarts": 3, "toBook": 3, "costText": null, "indoor": null, "kidFriendly": true, "lessVisited": false, "pushesOut": [], "moves": [] },
          "evidence": [], "place": null, "image": null, "packPlaceId": null,
          "shape": { "headline": "The big three on separate mornings", "days": [
            { "date": "{D0}", "line": "Land 11:30, a walk to the Pantheon" },
            { "date": "{D1}", "line": "Colosseum and the Forum" },
            { "date": "{D2}", "line": "Vatican tour, Castel Sant'Angelo" },
            { "date": "{D3}", "line": "Borghese Gallery, the gardens" },
            { "date": "{D4}", "line": "Leave 07:40 for the 10:40 flight" } ], "leavesOut": ["Trastevere evening"] },
          "preview": [], "basedOnVersion": 12, "status": "open", "reason": null, "createdAt": "{NOW}", "decidedAt": null
        },
        {
          "id": "dp-shape-hoods", "groupId": "shapes:demo", "kind": "shape",
          "title": "Neighbourhood days",
          "why": "A part of the city a day, on foot, with no early starts.",
          "scope": { "date": null, "stage": null, "stopId": null, "wishId": null }, "ops": [],
          "diff": { "lines": ["First plan."], "changes": [], "dates": [], "walkDeltaM": null, "dropped": [] },
          "tradeoffs": { "fits": true, "fitText": null, "walkMin": null, "walkKmPerDay": 5.2, "earlyStarts": 0, "toBook": 1, "costText": null, "indoor": null, "kidFriendly": true, "lessVisited": true, "pushesOut": [], "moves": [] },
          "evidence": [], "place": null, "image": null, "packPlaceId": null,
          "shape": { "headline": "Neighbourhood days", "days": [
            { "date": "{D0}", "line": "Land 11:30, Parione and Navona" },
            { "date": "{D1}", "line": "Monti and the Colosseum from outside" },
            { "date": "{D2}", "line": "Vatican tour, Prati for lunch" },
            { "date": "{D3}", "line": "Trastevere and the Gianicolo" },
            { "date": "{D4}", "line": "Leave 07:40 for the 10:40 flight" } ], "leavesOut": ["Roman Forum", "Capitoline Museums"] },
          "preview": [], "basedOnVersion": 12, "status": "open", "reason": null, "createdAt": "{NOW}", "decidedAt": null
        },
        {
          "id": "dp-dinner-1", "groupId": "fill:{D0}:evening", "kind": "fill",
          "title": "Da Francesco (made up)",
          "why": "Roman classics two minutes from Piazza Navona, and happy with children.",
          "scope": { "date": "{D0}", "stage": "evening", "stopId": "meal:{D0}:dinner", "wishId": null }, "ops": [],
          "diff": { "lines": ["Dinner at Da Francesco on the first evening."], "changes": [
            { "kind": "added", "wishId": null, "title": "Da Francesco", "date": "{D0}", "fromDate": null, "fromMin": null, "toMin": 1170, "reason": null } ],
            "dates": ["{D0}"], "walkDeltaM": 120, "dropped": [] },
          "tradeoffs": { "fits": true, "fitText": "19:30–20:45, 3 min walk in", "walkMin": 2, "walkKmPerDay": null, "earlyStarts": null, "toBook": 0, "costText": "€€ (made up)", "indoor": true, "kidFriendly": true, "lessVisited": false, "pushesOut": [], "moves": [] },
          "evidence": [ { "url": "https://example.org/places/da-francesco", "title": "A made-up listing" } ],
          "place": { "name": "Da Francesco (made up)", "location": { "lat": 41.8985, "lng": 12.4712 } }, "image": null, "packPlaceId": null,
          "shape": null, "preview": [], "basedOnVersion": 12, "status": "open", "reason": null, "createdAt": "{NOW}", "decidedAt": null
        },
        {
          "id": "dp-dinner-2", "groupId": "fill:{D0}:evening", "kind": "fill",
          "title": "Pizzeria Finta (made up)",
          "why": "Quick pizza on a quiet square — easy after a travel day.",
          "scope": { "date": "{D0}", "stage": "evening", "stopId": "meal:{D0}:dinner", "wishId": null }, "ops": [],
          "diff": { "lines": ["Dinner at Pizzeria Finta on the first evening."], "changes": [
            { "kind": "added", "wishId": null, "title": "Pizzeria Finta", "date": "{D0}", "fromDate": null, "fromMin": null, "toMin": 1140, "reason": null } ],
            "dates": ["{D0}"], "walkDeltaM": 400, "dropped": [] },
          "tradeoffs": { "fits": true, "fitText": "19:00–20:00, 8 min walk in", "walkMin": 6, "walkKmPerDay": null, "earlyStarts": null, "toBook": 0, "costText": "€ (made up)", "indoor": false, "kidFriendly": true, "lessVisited": true, "pushesOut": [], "moves": [] },
          "evidence": [], "place": { "name": "Pizzeria Finta (made up)", "location": { "lat": 41.8962, "lng": 12.4741 } }, "image": null, "packPlaceId": null,
          "shape": null, "preview": [], "basedOnVersion": 12, "status": "open", "reason": null, "createdAt": "{NOW}", "decidedAt": null
        }
      ],
      "pack": {
        "status": "ready", "stage": null, "builtAt": "{NOW}", "refreshedAt": null,
        "counts": { "places": 38, "food": 14, "toBook": 3, "lessVisited": 9, "rainy": 11 },
        "calendar": [ { "date": "{D3}", "kind": "weather", "text": "Rain likely in the afternoon", "placeId": null, "sources": [] } ],
        "neighbourhoods": [ { "name": "Parione", "line": "Baroque squares and cafés around Piazza Navona", "places": ["Piazza Navona"] } ],
        "highlights": ["Found 38 places", "14 places to eat near where you'll be", "3 need booking — Colosseum underground about 14 days ahead", "Rain likely on the fourth afternoon"]
      }
    }
    """#

    // MARK: Swaps, fills and a day's versions, made on request

    private struct Candidate {
        let id: String
        let title: String
        let why: String
        let at: TripLatLng
        let cost: String
        let indoor: Bool
        let kids: Bool
        let quiet: Bool
    }

    private static let candidates = [
        Candidate(id: "altemps", title: "Palazzo Altemps", why: "Ancient sculpture in a quiet palace by the flat — indoors, and rarely busy.",
                  at: altemps, cost: "€10 adults (made up)", indoor: true, kids: true, quiet: true),
        Candidate(id: "massimo", title: "Palazzo Massimo", why: "The best Roman mosaics and frescoes in the city, with room to breathe.",
                  at: massimo, cost: "€12 adults (made up)", indoor: true, kids: true, quiet: true),
        Candidate(id: "doria", title: "Galleria Doria Pamphilj", why: "A family palace of paintings, with an audio guide the children like.",
                  at: doria, cost: "€16 adults (made up)", indoor: true, kids: false, quiet: true),
        Candidate(id: "capitoline", title: "Capitoline Museums", why: "The she-wolf and Marcus Aurelius, and a terrace over the Forum.",
                  at: capitoline, cost: "€15 adults (made up)", indoor: true, kids: true, quiet: false),
    ]

    /// `POST …/proposals`: a group of three for a stop (or a slot, or a
    /// nudge), each with its day solved — the ghost the map draws.
    static func proposals(_ request: ProposalRequest, bundle: TripBundle, now: Date) -> [TripProposal] {
        let created = TripStore.iso(now)
        if request.kind == "shapes" {
            return decisions(now: now).proposals.filter { $0.kind == .shape }
        }
        if request.kind == "day" {
            return dayVersions(request, bundle: bundle, created: created)
        }
        let date = request.target.date ?? bundle.trip.startDate
        guard let day = bundle.day(date) else { return [] }
        let stopId = request.target.stopId
        let index = stopId.flatMap(day.index(of:)) ?? day.stops.firstIndex { $0.kind == .wish } ?? 0
        guard index < day.stops.count else { return [] }
        let stop = day.stops[index]
        let nudge = request.nudge
        var pool = candidates.filter { $0.title != stop.title }
        switch nudge {
        case .closer?, .lessWalking?:
            pool.sort { metres($0.at, stop.location ?? flat) < metres($1.at, stop.location ?? flat) }
        case .cheaper?:
            pool.sort { $0.cost < $1.cost }
        case .quieter?:
            pool = pool.filter(\.quiet) + pool.filter { !$0.quiet }
        default:
            break
        }
        let groupId = "swap:\(date):\(stop.id)" + (nudge.map { ":\($0.rawValue)" } ?? "")
        let before = index > 0 ? day.stops[index - 1] : nil
        return pool.prefix(3).enumerated().map { i, c in
            var preview = day
            var moved = stop
            moved.id = "demo-\(c.id)"
            moved.wishId = nil
            moved.title = c.title
            moved.location = c.at
            preview.stops[index] = moved
            if index > 0, index - 1 < preview.legs.count {
                preview.legs[index - 1].toStopId = moved.id
                preview.legs[index - 1].line = nil
            }
            if index < preview.legs.count { preview.legs[index].fromStopId = moved.id }
            let walkIn = before.flatMap { $0.location }.map { Int((metres($0, c.at) / 80).rounded()) } ?? 10
            let was = before.flatMap { $0.location }.map { Int((metres($0, stop.location ?? flat) / 80).rounded()) } ?? 10
            return TripProposal(
                id: "dp-\(groupId)-\(c.id)", groupId: groupId, kind: request.kind == "fill" ? .fill : .swap, title: c.title, why: c.why,
                scope: ProposalScope(date: date, stage: stop.stage, stopId: stop.id, wishId: stop.wishId), ops: [],
                diff: PlanDiff(
                    lines: ["\(c.title) added on \(TripFormat.day(date, zone: TripClock(zone).zone)) at \(TripFormat.time(stop.arriveMin)).",
                            "\(stop.title) is no longer planned."],
                    changes: [
                        PlanChange(kind: "added", wishId: nil, title: c.title, date: date, fromDate: nil, fromMin: nil, toMin: stop.arriveMin, reason: nil),
                        PlanChange(kind: "removed", wishId: stop.wishId, title: stop.title, date: nil, fromDate: date, fromMin: stop.arriveMin, toMin: nil, reason: nil),
                    ],
                    dates: [date], walkDeltaM: Double((walkIn - was) * 80), dropped: []
                ),
                tradeoffs: ProposalTradeoffs(
                    fits: true, fitText: "\(TripFormat.time(stop.arriveMin))–\(TripFormat.time(stop.departMin)), \(walkIn) min walk in",
                    walkMin: Double(walkIn - was), walkKmPerDay: nil, earlyStarts: nil, toBook: 0, costText: c.cost, indoor: c.indoor,
                    kidFriendly: c.kids, lessVisited: c.quiet, pushesOut: i == 2 ? ["Dinner to 20:15"] : [], moves: []
                ),
                evidence: [WireSource(url: "https://example.org/places/\(c.id)", title: "A made-up guide")],
                place: ProposalPlace(name: c.title, location: c.at), image: nil, packPlaceId: "demo-pack-\(c.id)", shape: nil,
                preview: [preview], basedOnVersion: bundle.plan?.version, status: .open, reason: nil, createdAt: created, decidedAt: nil
            )
        }
    }

    /// A lighter day, a rainy-day version, or this day swapped with another.
    private static func dayVersions(_ request: ProposalRequest, bundle: TripBundle, created: String) -> [TripProposal] {
        guard let date = request.target.date, let day = bundle.day(date) else { return [] }
        let zone = TripClock(TripDemo.zone).zone
        let visits = day.stops.indices.filter { day.stops[$0].kind == .wish && !day.stops[$0].locked }
        var preview = day
        var title = "A lighter \(TripFormat.day(date, zone: zone))"
        var why = "One stop fewer, and a long break in the afternoon."
        var changes: [PlanChange] = []
        switch request.variant {
        case .rainy?:
            title = "\(TripFormat.day(date, zone: zone)), rain or shine"
            why = "Outdoor stops swapped for indoor ones near the same streets."
            for i in visits.prefix(1) {
                let c = candidates[0]
                changes.append(PlanChange(kind: "removed", wishId: day.stops[i].wishId, title: day.stops[i].title, date: nil, fromDate: date,
                                          fromMin: day.stops[i].arriveMin, toMin: nil, reason: nil))
                changes.append(PlanChange(kind: "added", wishId: nil, title: c.title, date: date, fromDate: nil, fromMin: nil,
                                          toMin: day.stops[i].arriveMin, reason: nil))
                preview.stops[i].title = c.title
                preview.stops[i].location = c.at
            }
        case .swapDays?:
            let other = request.withDate ?? date
            title = "Swap \(TripFormat.day(date, zone: zone)) with \(TripFormat.day(other, zone: zone))"
            why = "The two days change places; booked and locked stops stay put."
            for i in visits {
                changes.append(PlanChange(kind: "moved", wishId: day.stops[i].wishId, title: day.stops[i].title, date: other, fromDate: date,
                                          fromMin: day.stops[i].arriveMin, toMin: day.stops[i].arriveMin, reason: nil))
            }
        default:
            if let last = visits.last {
                changes.append(PlanChange(kind: "moved", wishId: day.stops[last].wishId, title: day.stops[last].title,
                                          date: bundle.trip.endDate, fromDate: date, fromMin: day.stops[last].arriveMin, toMin: 600, reason: nil))
                preview.stops.remove(at: last)
                preview.legs = Array(preview.legs.prefix(max(0, preview.stops.count - 1)))
            }
        }
        let p = TripProposal(
            id: "dp-day-\(date)-\(request.variant?.rawValue ?? "lighter")", groupId: "day:\(date):\(request.variant?.rawValue ?? "lighter")",
            kind: .day, title: title, why: why, scope: ProposalScope(date: date, stage: nil, stopId: nil, wishId: nil), ops: [],
            diff: PlanDiff(lines: changes.map(\.title), changes: changes, dates: [date], walkDeltaM: -900, dropped: []),
            tradeoffs: ProposalTradeoffs(fits: true, fitText: nil, walkMin: -11, walkKmPerDay: nil, earlyStarts: nil, toBook: nil, costText: nil,
                                         indoor: request.variant == .rainy ? true : nil, kidFriendly: nil, lessVisited: false,
                                         pushesOut: [], moves: []),
            evidence: [], place: nil, image: nil, packPlaceId: nil, shape: nil, preview: [preview],
            basedOnVersion: bundle.plan?.version, status: .open, reason: nil, createdAt: created, decidedAt: nil
        )
        return [p]
    }

    // MARK: Answers

    /// What answering a demo question does: the after-Vatican answer moves
    /// three stops (mockup 8); the others change the plan in words only.
    static func answered(_ qid: String, action: String, answerId: String?, now: Date) -> DecisionResult {
        let wire = decisions(now: now)
        let d = planDates(now: now)
        var q = wire.questions.first { $0.id == qid }
        let version = 12 + DemoDecisions.shared.versionBump
        let chosen = action == "decide" ? q?.defaultAnswerId : answerId
        if action == "vote" {
            q?.votes[answerId ?? "a0", default: []].append(SRDemo.isMember ? "Sam" : "Alex")
            return DecisionResult(proposal: nil, question: q, planVersion: nil, changes: nil, diff: nil, undo: nil, remember: nil, stale: nil)
        }
        q?.status = action == "skip" ? .skipped : .answered
        q?.answerId = action == "skip" ? nil : chosen
        q?.answeredByName = "Alex"
        q?.answeredAt = TripStore.iso(now)
        var diff = PlanDiff.empty
        if qid == "dq-after-vatican" && chosen == "a0" {
            diff = PlanDiff(lines: ["Pantheon now 16:00.", "Trevi Fountain moves to the next day.", "A long lunch added."], changes: [
                PlanChange(kind: "retimed", wishId: "p-pantheon", title: "Pantheon", date: d[2], fromDate: d[2], fromMin: 910, toMin: 960, reason: nil),
                PlanChange(kind: "moved", wishId: "p-trevi", title: "Trevi Fountain", date: d[3], fromDate: d[2], fromMin: 980, toMin: 960, reason: nil),
                PlanChange(kind: "added", wishId: nil, title: "Long lunch at Da Francesco", date: d[2], fromDate: nil, fromMin: nil, toMin: 765, reason: nil),
            ], dates: [d[2]], walkDeltaM: -1200, dropped: [])
        } else if let a = q?.answers.first(where: { $0.id == chosen }), let summary = a.summary {
            diff = PlanDiff(lines: [summary], changes: [], dates: q?.affects.dates ?? [], walkDeltaM: nil, dropped: [])
        }
        let remember = q?.answers.first { $0.id == chosen }?.remember
        return DecisionResult(proposal: nil, question: q, planVersion: diff.lines.isEmpty ? nil : version + 1,
                              changes: diff.lines, diff: diff, undo: diff.lines.isEmpty ? nil : UndoPoint(toVersion: version),
                              remember: remember, stale: nil)
    }

    /// The running demo trip speaks v8 too (a stop can be swapped on the
    /// day): no questions, and only the alternatives asked for this session.
    static func withDecisions(_ bundle: TripBundle) -> TripBundle {
        var b = bundle
        let dates = Set((b.plan?.plan.days ?? []).map(\.date))
        let state = DemoDecisions.shared.snapshot()
        b.questions = []
        b.answered = []
        b.proposals = state.extra.filter { p in
            dates.contains(p.scope.date ?? "") && !state.proposals.contains(p.id) && !state.groups.contains(p.groupId)
        }
        return b
    }

    // MARK: The guided start, as a job

    /// `POST /api/native/trips {start}`: a job whose stages tick over about
    /// ten seconds, then the planning trip opens on its shapes.
    static func startJob(now: Date) -> StagedJob {
        job(id: "demo-start-\(Int(now.timeIntervalSince1970))", now: now)
    }

    static func job(id: String, now: Date) -> StagedJob {
        let started = Double(id.split(separator: "-").last.flatMap { Int($0) } ?? Int(now.timeIntervalSince1970))
        let elapsed = now.timeIntervalSince1970 - started
        if DemoDecisions.shared.isCancelled(id) {
            return StagedJob(id: id, kind: "start", status: "cancelled", tripId: planTripId, startedAt: TripStore.iso(Date(timeIntervalSince1970: started)),
                             finishedAt: TripStore.iso(now), result: nil, error: nil, stages: [])
        }
        let d = planDates(now: now)
        let range = TripFormat.range(d[0], d[4], zone: TripClock(zone).zone)
        let steps: [(String, String, String)] = [
            ("brief", "Setting up the trip", "Rome, \(range), 5 travellers"),
            ("places", "Finding places", "Found 38 places, 9 of them less visited"),
            ("food", "Finding places to eat", "14 near where you'll be"),
            ("booking", "Checking what needs booking", "3 need booking — Colosseum underground about 14 days ahead"),
            ("hours", "Checking opening hours on your dates", "Rain likely on the fourth afternoon"),
            ("shapes", "Drafting three ways to do it", "Three plans, each checked"),
        ]
        let stages = steps.enumerated().map { i, s -> JobStage in
            let doneAt = Double(i + 1) * 1.8
            let state: JobStageState = elapsed >= doneAt ? .done : (elapsed >= doneAt - 1.8 ? .running : .waiting)
            return JobStage(key: s.0, label: s.1, state: state, detail: state == .done ? s.2 : (state == .running && i == 4 ? "21 of 38" : nil))
        }
        let done = stages.allSatisfy { $0.state == .done }
        return StagedJob(
            id: id, kind: "start", status: done ? "done" : "running", tripId: planTripId,
            startedAt: TripStore.iso(Date(timeIntervalSince1970: started)), finishedAt: done ? TripStore.iso(now) : nil,
            result: .object(["id": .string(planTripId)]), error: nil, stages: stages
        )
    }

    static let notes: [NoteFact] = [
        NoteFact(id: "note:transport:demo", kind: "transport", label: "Flights NCL 07:35 → FCO, back 10:40", detail: "Booking email",
                 ops: [], ref: nil),
        NoteFact(id: "note:stay:demo", kind: "stay", label: "A flat in Parione, near Piazza Navona", detail: "Booking email",
                 ops: [], ref: nil),
    ]

    static func versions(now: Date) -> [TripVersionRow] {
        let v = 12 + DemoDecisions.shared.versionBump
        return (0..<min(4, v)).map { i in
            TripVersionRow(version: v - i, source: i == 0 ? "answer" : "planner",
                           createdAt: TripStore.iso(now.addingTimeInterval(Double(-3600 * (i + 1)))),
                           changes: i == 0 ? ["The latest plan."] : ["Version \(v - i) of the plan (made up)."], restorable: i < 3)
        }
    }
}

/// What the demo session has decided, in memory only. The demo's fixture
/// replies are built per request on whatever thread the URL loading runs,
/// so this is locked.
final class DemoDecisions: @unchecked Sendable {
    static let shared = DemoDecisions()

    struct Snapshot {
        var proposals: Set<String>
        var groups: Set<String>
        var answers: [String: String]
        var confirmed: Set<String>
        var extra: [TripProposal]
    }

    private let lock = NSLock()
    private var proposals: Set<String> = []
    private var groups: Set<String> = []
    private var answers: [String: String] = [:]
    private var confirmed: Set<String> = []
    private var cancelled: Set<String> = []
    /// Groups asked for on request (swaps, a day's versions), kept so a
    /// re-read shows them, as the server would.
    private var extra: [TripProposal] = []
    /// Each thing decided, last first, for Undo.
    private var undoStack: [(kind: String, id: String)] = []
    private var bump = 0

    var versionBump: Int { lock.lock(); defer { lock.unlock() }; return bump }

    func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return Snapshot(proposals: proposals, groups: groups, answers: answers, confirmed: confirmed, extra: extra)
    }

    func keep(_ group: [TripProposal]) {
        lock.lock(); defer { lock.unlock() }
        let ids = Set(group.map(\.groupId))
        extra.removeAll { ids.contains($0.groupId) }
        extra.append(contentsOf: group)
    }

    func extraProposal(_ id: String) -> TripProposal? {
        lock.lock(); defer { lock.unlock() }
        return extra.first { $0.id == id }
    }

    func accept(_ p: TripProposal) {
        lock.lock(); defer { lock.unlock() }
        groups.insert(p.groupId)
        undoStack.insert(("group", p.groupId), at: 0)
        bump += 1
    }

    func reject(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        proposals.insert(id)
    }

    func answer(_ qid: String, _ value: String) {
        lock.lock(); defer { lock.unlock() }
        answers[qid] = value
        if !value.hasPrefix("vote:") {
            undoStack.insert(("question", qid), at: 0)
            bump += 1
        }
    }

    func confirm(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        confirmed.insert(key)
    }

    func cancel(_ jobId: String) {
        lock.lock(); defer { lock.unlock() }
        cancelled.insert(jobId)
    }

    func isCancelled(_ jobId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled.contains(jobId)
    }

    /// Undo the latest decision: its card comes back.
    @discardableResult
    func undo() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let last = undoStack.first else { return false }
        undoStack.removeFirst()
        if last.kind == "group" { groups.remove(last.id) } else { answers[last.id] = nil }
        bump += 1
        return true
    }
}
