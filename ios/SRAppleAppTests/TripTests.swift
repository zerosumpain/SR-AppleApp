import XCTest
@testable import SRAppleApp

/// The trip companion's contracts: the Live Activity's shape (SR-Main
/// `docs/superpowers/specs/2026-10-13-trips.md`, "Live Activity"), the wire
/// shapes the phone sends, and the pure logic the Day screen stands on.
final class TripTests: XCTestCase {

    // MARK: Live Activity

    /// The contract's ContentState, verbatim: epoch SECONDS, not
    /// ActivityKit's 2001-based dates. A key that drifts drops the update.
    func testTheContractsContentStateDecodes() throws {
        let json = #"{"nextTitle":"Pantheon","leaveAt":1792152000,"legMode":"walk","legMinutes":12,"arriveAt":1792152720,"stopIndex":3,"stopCount":8}"#
        let state = try JSONDecoder().decode(TripAttributes.ContentState.self, from: Data(json.utf8))
        XCTAssertEqual(state.nextTitle, "Pantheon")
        XCTAssertEqual(state.leave, Date(timeIntervalSince1970: 1_792_152_000))
        XCTAssertEqual(state.arrive.timeIntervalSince(state.leave), 720)
        XCTAssertEqual(state.legLine, "12 min walk")
        XCTAssertEqual(state.stopLine, "Stop 4 of 8")
        XCTAssertEqual(state.symbol, "figure.walk")
        XCTAssertEqual(state.leaveLine(now: Date(timeIntervalSince1970: 1_792_152_000 - 8 * 60 - 5)), "leave in 8 min")
        XCTAssertEqual(state.leaveLine(now: Date(timeIntervalSince1970: 1_792_152_030)), "leave now")
    }

    func testTheContractsAttributesDecode() throws {
        let json = #"{"tripId":"trip-rome","title":"Rome in October"}"#
        let attributes = try JSONDecoder().decode(TripAttributes.self, from: Data(json.utf8))
        XCTAssertEqual(attributes.tripId, "trip-rome")
        XCTAssertEqual(attributes.title, "Rome in October")
    }

    func testTransitSaysSo() throws {
        let json = #"{"nextTitle":"Vatican Museums","leaveAt":0,"legMode":"transit","legMinutes":25,"arriveAt":1500,"stopIndex":0,"stopCount":2}"#
        let state = try JSONDecoder().decode(TripAttributes.ContentState.self, from: Data(json.utf8))
        XCTAssertEqual(state.legLine, "25 min by transit")
        XCTAssertEqual(state.symbol, "tram.fill")
    }

    /// What the app puts on the Lock Screen at the Pantheon: the next stop,
    /// the plan's leave time and the leg, in epoch seconds.
    func testTheCardIsBuiltFromWhereYouAre() throws {
        let clock = TripClock("Europe/Rome")
        let day = Self.day()
        let marks = ["stay:2026-10-27:start": TripStopMark(leftAt: clock.date("2026-10-27", minutes: 540))]
        let progress = TripProgress.of(day: day, marks: marks, nowMin: 600, clock: clock)
        let state = try XCTUnwrap(TripLive.state(day: day, progress: progress, clock: clock))
        XCTAssertEqual(state.nextTitle, "Pantheon")
        XCTAssertEqual(state.legMinutes, 12)
        XCTAssertEqual(state.stopIndex, 1)
        XCTAssertEqual(state.stopCount, 3)
        XCTAssertEqual(state.arriveAt, try XCTUnwrap(clock.date("2026-10-27", minutes: 560)).timeIntervalSince1970)
    }

    // MARK: Where you are in the day

    func testNoMarksMeansAtTheStayAndNeverBehind() {
        let p = TripProgress.of(day: Self.day(), marks: [:], nowMin: 900, clock: TripClock("Europe/Rome"))
        XCTAssertEqual(p.phase, .at(0))
        XCTAssertEqual(p.next, 1)
        XCTAssertEqual(p.behindMin, 0, "silence is not evidence of lateness")
    }

    func testArrivingLateIsBehind() throws {
        let clock = TripClock("Europe/Rome")
        let marks = [
            "stay:2026-10-27:start": TripStopMark(leftAt: clock.date("2026-10-27", minutes: 548)),
            "pantheon": TripStopMark(arrivedAt: clock.date("2026-10-27", minutes: 585)),
        ]
        let p = TripProgress.of(day: Self.day(), marks: marks, nowMin: 590, clock: clock)
        XCTAssertEqual(p.phase, .at(1))
        XCTAssertEqual(p.behindMin, 25)
        XCTAssertTrue(p.showsBehind)
        XCTAssertEqual(p.atStopId, "pantheon")
        XCTAssertEqual(p.doneStopIds, ["stay:2026-10-27:start"])
    }

    // MARK: The wire

    /// `string | null` fields go up as null, not missing.
    func testAnEventWritesItsNulls() throws {
        let event = TripEvent(clientId: "c1", kind: .optionApplied, stopId: nil, wishId: nil, at: "2026-10-27T10:00:00.000Z",
                              detail: ["day": try XCTUnwrap(TripJSON.from(Self.day()))])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any])
        XCTAssertEqual(object["kind"] as? String, "option-applied")
        XCTAssertTrue(object["stopId"] is NSNull)
        let day = try XCTUnwrap((object["detail"] as? [String: Any])?["day"] as? [String: Any])
        let stops = try XCTUnwrap(day["stops"] as? [[String: Any]])
        XCTAssertTrue(stops[0]["bookingId"] is NSNull)
        XCTAssertEqual(event.detail?["day"]?.decode(PlannedDay.self), Self.day())
    }

    func testAReplanRequestWritesItsNulls() throws {
        let body = TripReplanBody(date: "2026-10-27", nowMin: 600, position: nil, atStopId: nil, doneStopIds: [])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        XCTAssertTrue(object["position"] is NSNull)
        XCTAssertTrue(object["atStopId"] is NSNull)
    }

    func testTripIdsAreEscapedInPaths() {
        XCTAssertEqual(TripsAPI.path("trip-rome"), "api/native/trips/trip-rome")
        XCTAssertEqual(TripsAPI.path("a/b"), "api/native/trips/a%2Fb")
    }

    /// The demo's Rome trip is a valid bundle, and its day is running now.
    func testTheDemoTripDecodesAndRunsToday() throws {
        let base = "https://strangeramblings.com/"
        let list = try JSONDecoder().decode(TripList.self, from:
            SRDemoFixtures.reply(method: "GET", url: URL(string: base + "api/native/trips")!, body: nil).body)
        XCTAssertEqual(list.trips.map(\.id), [TripDemo.tripId])
        let bundle = try JSONDecoder().decode(TripBundle.self, from:
            SRDemoFixtures.reply(method: "GET", url: URL(string: base + "api/native/trips/\(TripDemo.tripId)")!, body: nil).body)
        let today = TripClock(bundle.trip.timeZone).localDate(Date())
        let day = try XCTUnwrap(bundle.day(today))
        XCTAssertEqual(day.legs.count, day.stops.count - 1)
        XCTAssertNotNil(bundle.matrices[today])
    }

    // MARK: Regions

    func testTheRegionBudgetLeavesTheCollectorsPlaces() {
        XCTAssertEqual(TripArrivals.budget(reserved: 1, foreignNow: 0), 15)
        XCTAssertEqual(TripArrivals.budget(reserved: 16, foreignNow: 3), 4)
        XCTAssertEqual(TripArrivals.budget(reserved: 1, foreignNow: 19), 1)
        XCTAssertEqual(TripArrivals.budget(reserved: 21, foreignNow: 0), 0)
    }

    func testRegionIdentifiersRoundTrip() throws {
        let id = TripArrivals.identifier(trip: "trip-rome", date: "2026-10-27", stop: "stay:2026-10-27:end")
        let key = try XCTUnwrap(TripArrivals.parse(id))
        XCTAssertEqual(key.trip, "trip-rome")
        XCTAssertEqual(key.stop, "stay:2026-10-27:end")
        XCTAssertNil(TripArrivals.parse("sr.watch.home"))
    }

    // MARK: Words

    func testLongWaitsAreFreeTime() {
        var stop = Self.day().stops[1]
        stop.waitSec = 20 * 60
        XCTAssertEqual(TripWords.wait(stop), "Wait 20 min before it starts")
        stop.waitSec = 70 * 60
        XCTAssertEqual(TripWords.wait(stop), "Free time · 1 h 10 first")
        stop.waitSec = 0
        XCTAssertNil(TripWords.wait(stop))
    }

    /// A locked stop not reached by its start plus the solver's 30-minute
    /// grace is a missed slot, in the solver's words; a day's own warning is
    /// shown as it is.
    func testMissedSlotsAreSaid() {
        var day = Self.day()
        day.stops[1].locked = true
        let clock = TripClock("Europe/Rome")
        let progress = TripProgress.of(day: day, marks: [:], nowMin: 600, clock: clock)
        XCTAssertEqual(TripWords.missedSlots(day: day, progress: progress, nowMin: 589), [])
        XCTAssertEqual(TripWords.missedSlots(day: day, progress: progress, nowMin: 600), ["Missed your 09:20 Pantheon slot"])
        day.warnings = ["Missed your 09:30 Colosseum slot", "Back at the stay 19:40 — later than 19:00"]
        XCTAssertEqual(TripWords.missedSlots(day: day, progress: nil, nowMin: nil), ["Missed your 09:30 Colosseum slot"])
    }

    func testTimesAreLocalAndWrap() {
        XCTAssertEqual(TripFormat.time(860), "14:20")
        XCTAssertEqual(TripFormat.time(1450), "00:10")
        XCTAssertEqual(TripFormat.duration(minutes: 65), "1 h 05")
        let clock = TripClock("Europe/Rome")
        XCTAssertEqual(clock.date("2026-10-27", minutes: 860).map(clock.localDate), "2026-10-27")
        XCTAssertEqual(clock.date("2026-10-27", minutes: 860).map(clock.minutes), 860)
    }

    // MARK: v2

    /// A mode a later server adds must not fail the whole bundle offline.
    func testAnUnknownModeDecodesSafely() throws {
        let json = #"{"fromStopId":"a","toStopId":"b","mode":"hovercraft","durationSec":60,"distanceM":null,"estimated":true,"line":null}"#
        let leg = try JSONDecoder().decode(PlannedLeg.self, from: Data(json.utf8))
        XCTAssertEqual(leg.mode, .unknown)
        XCTAssertNil(leg.guidance)
        let taxi = try JSONDecoder().decode(PlannedLeg.self, from: Data(json.replacingOccurrences(of: "hovercraft", with: "taxi").utf8))
        XCTAssertEqual(taxi.mode, .taxi)
        XCTAssertEqual(TripFormat.leg(taxi), "1 min by taxi")
    }

    /// The contract's v2 shapes, verbatim.
    func testV2ShapesDecode() throws {
        let guidance = #"{"summary":"Bus 64 from Largo Argentina, 4 stops","steps":[],"transit":[{"line":"64","vehicle":"bus","fromStop":"Largo Argentina","toStop":"San Pietro","stops":4,"departuresMin":[862,874]}],"booking":null,"tips":["Validate on board"],"costText":"€1.50","source":"router","generatedAt":"2026-10-27T10:00:00.000Z"}"#
        let g = try JSONDecoder().decode(LegGuidance.self, from: Data(guidance.utf8))
        XCTAssertEqual(g.transit?.first?.departuresMin, [862, 874])
        let converse = #"{"reply":"Done.","applied":[{"op":"removeWish","id":"w1"}],"rejected":[{"op":{"op":"research","wishIds":[],"depth":"brief"},"reason":"nothing to research"}],"quickReplies":["Anything else?"],"planVersion":4,"changes":["Dropped the Steps"]}"#
        let c = try JSONDecoder().decode(ConverseResult.self, from: Data(converse.utf8))
        XCTAssertEqual(c.planVersion, 4)
        XCTAssertEqual(c.rejected.first?.reason, "nothing to research")
        let option = #"{"id":"pull-forward:w2","label":"Fit in X now","kind":"pull-forward","days":[],"dropped":[],"moved":[{"wishId":"w2","from":"2026-10-28","to":"2026-10-27"}],"explanation":"Close by."}"#
        XCTAssertEqual(try JSONDecoder().decode(TripReplanOption.self, from: Data(option.utf8)).moved.first?.from, "2026-10-28")
    }

    /// `scope` and `observation` are optional (left out), the observation's
    /// own nullable fields are null.
    func testATripReplanRequestEncodes() throws {
        var body = TripReplanBody(date: "2026-10-27", nowMin: 600, position: nil, atStopId: nil, doneStopIds: [])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        XCTAssertNil(object["scope"])
        XCTAssertNil(object["observation"])
        body.scope = "trip"
        body.observation = Observation(kind: .unplannedStop, place: nil, sinceMin: 590, motion: "stationary", stopId: nil)
        object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
        XCTAssertEqual(object["scope"] as? String, "trip")
        let observation = try XCTUnwrap(object["observation"] as? [String: Any])
        XCTAssertEqual(observation["kind"] as? String, "unplanned-stop")
        XCTAssertTrue(observation["place"] is NSNull)
    }

    /// Only https, http and tel links from model-written guidance open.
    func testGuideLinksAreFiltered() {
        XCTAssertNotNil(TripLinkButtons.safeURL("https://example.org/taxi"))
        XCTAssertNotNil(TripLinkButtons.safeURL("tel:+390600000"))
        XCTAssertNil(TripLinkButtons.safeURL("javascript:alert(1)"))
        XCTAssertNil(TripLinkButtons.safeURL("sms:123"))
    }

    // MARK: v3

    func testV3ShapesDecode() throws {
        let segment = #"{"id":"t1","kind":"flight","direction":"outbound","carrier":"Jet2","number":"LS1235","from":{"name":"Newcastle","code":"NCL","location":null,"timeZone":"Europe/London"},"to":{"name":"Rome Fiumicino","code":"FCO","location":{"lat":41.8,"lng":12.24},"timeZone":"Europe/Rome"},"departDate":"2026-10-27","departMin":455,"arriveDate":"2026-10-27","arriveMin":685,"confidence":"researched","status":null,"delayMin":null,"bookingRef":"ABC123","sources":[{"url":"https://example.org/f","title":null}],"checkedAt":null}"#
        let t = try JSONDecoder().decode(TransportSegment.self, from: Data(segment.utf8))
        XCTAssertEqual(t.number, "LS1235")
        XCTAssertEqual(t.leads.exitMin, 40)
        // v5: only travellers reach the phone; anything else is dropped on decode.
        let profile = #"{"travellers":[{"name":"Sam","relation":"child","age":9,"personId":"p2"}],"preferences":[{"text":"Prefers walking","source":"memory","ref":"m1"}]}"#
        let decoded = try JSONDecoder().decode(TravellerProfile.self, from: Data(profile.utf8))
        XCTAssertEqual(decoded.travellers.first?.age, 9)
        let reencoded = String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)
        XCTAssertFalse(reencoded.contains("Prefers walking"), "a memory must not survive onto the phone's disk")
        let converse = #"{"reply":"Lands 11:25.","applied":[],"rejected":[],"quickReplies":[],"planVersion":null,"changes":[],"research":[{"tool":"flight_lookup","summary":"Looked up LS1235","sources":[]}]}"#
        XCTAssertEqual(try JSONDecoder().decode(ConverseResult.self, from: Data(converse.utf8)).research?.first?.tool, "flight_lookup")
    }

    /// The profile is stored on the trip; read from there or beside it.
    func testTheProfileIsReadFromTheTrip() throws {
        var bundle = TripDemo.bundle(now: Date())
        let profile = try XCTUnwrap(bundle.profile)
        bundle.profile = nil
        XCTAssertNil(bundle.knownProfile)
        bundle.trip.profile = profile
        let data = try JSONEncoder().encode(bundle)
        XCTAssertEqual(try JSONDecoder().decode(TripBundle.self, from: data).knownProfile, profile)
    }

    /// A stop kind a later server adds (or v3's `transport`) never fails a day.
    func testNewStopKindsDecode() throws {
        let stop = #"{"id":"transport:t1:to","kind":"transport","wishId":null,"title":"Rome Fiumicino","location":null,"arriveMin":685,"departMin":725,"waitSec":0,"locked":false,"bookingId":null,"warnings":[]}"#
        XCTAssertEqual(try JSONDecoder().decode(PlannedStop.self, from: Data(stop.utf8)).kind, .transport)
        let odd = stop.replacingOccurrences(of: "\"transport\"", with: "\"teleport\"")
        XCTAssertEqual(try JSONDecoder().decode(PlannedStop.self, from: Data(odd.utf8)).kind, .unknown)
    }

    /// The demo's arrival day: the flight lands, bags are dropped, lunch.
    func testTheDemoArrivalDay() throws {
        let bundle = TripDemo.bundle(now: Date())
        let first = try XCTUnwrap(bundle.plan?.plan.days.first)
        XCTAssertEqual(first.stops.first?.kind, .transport)
        XCTAssertTrue(first.stops.contains(where: TripWords.isDropBags))
        XCTAssertEqual(bundle.segments.first?.arriveDate, first.date)
        XCTAssertEqual(bundle.trip.dayLoads?[first.date], "light")
        XCTAssertNotNil(bundle.profile)
    }

    // MARK: v5 family trips

    /// An older bundle (no `access`) was the owner's: everything allowed.
    func testAccessDefaultsToTheOwner() throws {
        var bundle = TripDemo.bundle(now: Date())
        bundle.access = nil
        XCTAssertTrue(bundle.can.canEdit && bundle.can.canApprove)
        let member = #"{"canEdit":false,"canApprove":false,"canSuggest":true,"role":"member"}"#
        bundle.access = try JSONDecoder().decode(TripAccess.self, from: Data(member.utf8))
        XCTAssertFalse(bundle.can.canEdit)
        XCTAssertTrue(bundle.can.canSuggest)
    }

    /// v5: the creator's email is not on the wire; a trip decodes without it.
    func testATripDecodesWithoutAnOwnerEmail() throws {
        let json = #"{"id":"t1","createdById":"p1","createdByName":"Alex","title":"Rome","destination":"Rome","timeZone":"Europe/Rome","startDate":"2026-10-27","endDate":"2026-10-30","pace":"normal","modes":["walk"],"status":"planned","notes":null}"#
        let trip = try JSONDecoder().decode(Trip.self, from: Data(json.utf8))
        XCTAssertEqual(trip.createdByName, "Alex")
        let back = String(decoding: try JSONEncoder().encode(trip), as: UTF8.self)
        XCTAssertFalse(back.contains("ownerEmail"))
    }

    func testASuggestionDecodes() throws {
        let json = #"{"id":"s1","tripId":"t1","byId":"p2","byName":"Sam","date":"2026-10-28","stage":"afternoon","wish":{"title":"Gelato","placeQuery":"gelateria","priority":"nice","durationMin":20,"partOfDay":"afternoon","fixedDate":"2026-10-28","fixedStartMin":null,"note":null},"note":null,"fitText":"Fits","status":"pending","decidedById":null,"decidedAt":null,"createdAt":"2026-10-14T10:00:00.000Z"}"#
        let s = try JSONDecoder().decode(TripSuggestion.self, from: Data(json.utf8))
        XCTAssertTrue(s.pending)
        XCTAssertEqual(s.wish.durationMin, 20)
    }

    /// A draft's `string | null` fields go up as null.
    func testAWishDraftWritesItsNulls() throws {
        let draft = WishDraft(title: "Gelato", placeQuery: nil, priority: "nice", durationMin: nil, partOfDay: "any",
                              fixedDate: nil, fixedStartMin: nil, note: nil)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
        XCTAssertTrue(object["placeQuery"] is NSNull)
        XCTAssertNil(object["replacesMeal"], "optional, so left out")
    }

    // MARK: v6 jobs

    /// An idea says where it came from; the map's fallback is tagged.
    func testIdeasSayWhereTheyCameFrom() throws {
        let json = #"{"ideas":[{"title":"Bar del Fico","why":"Close","fit":"Fits","wish":{"title":"Bar del Fico","placeQuery":null,"priority":"nice","durationMin":30,"partOfDay":"any","fixedDate":null,"fixedStartMin":null,"note":null},"verdict":{"fits":true,"pushesOut":[]},"source":"nearby"}],"rejected":[{"title":"Too far","reason":"40 min away"}],"note":null,"research":[]}"#
        let reply = try JSONDecoder().decode(TripIdeasReply.self, from: Data(json.utf8))
        XCTAssertTrue(reply.ideas[0].nearby)
        XCTAssertEqual(reply.rejected?.first?.reason, "40 min away")
    }

    /// Jobs are keyed per slot, per trip's conversation, and for a new trip.
    func testJobKeys() {
        XCTAssertEqual(TripJobs.ideasKey("t1", "2026-10-28", .lunch), "ideas|t1|2026-10-28|lunch")
        XCTAssertEqual(TripJobs.converseKey("t1"), "converse|t1")
        XCTAssertNotEqual(TripJobs.ideasKey("t1", "2026-10-28", .lunch), TripJobs.ideasKey("t1", "2026-10-28", .evening))
    }

    func testFullnessBands() {
        XCTAssertEqual(TripFullness.band(5), "empty")
        XCTAssertEqual(TripFullness.band(49), "light")
        XCTAssertEqual(TripFullness.band(84), "balanced")
        XCTAssertEqual(TripFullness.band(100), "full")
        XCTAssertEqual(TripFullness.band(101), "overfull")
        let bundle = TripDemo.bundle(now: Date())
        let today = TripClock(bundle.trip.timeZone).localDate(Date())
        let day = bundle.day(today)!
        XCTAssertEqual(TripFullness.of(day, bundle: bundle).pct, 54, "the server's figure, for the server's day")
        var moved = day
        moved.stops.removeAll { $0.kind == .wish }
        XCTAssertEqual(TripFullness.of(moved, bundle: bundle).band, "empty", "a phone-made day is measured here")
    }

    func testTravellersAreNamesAndAges() {
        XCTAssertEqual(TripTravellersRow.line(.init(name: "Sam", relation: "child", age: 9, personId: nil)), "Sam, 9")
        XCTAssertEqual(TripTravellersRow.line(.init(name: "Alex", relation: nil)), "Alex")
    }

    // MARK: v4 stages

    /// The solver's stages win; without them, its `stageOf` decides.
    func testStagesFollowTheMealsAndTheClock() {
        func st(_ id: String, _ kind: StopKind, _ at: Double, stage: String? = nil) -> PlannedStop {
            PlannedStop(id: id, kind: kind, wishId: kind == .wish ? id : nil, title: id, location: nil, arriveMin: at,
                        departMin: at + 30, waitSec: 0, locked: false, bookingId: nil, warnings: [], stage: stage)
        }
        var day = PlannedDay(date: "d", stayId: "s", stops: [
            st("stay:d:start", .stay, 540), st("col", .wish, 560), st("meal:d:lunch", .meal, 760),
            st("pan", .wish, 840), st("meal:d:dinner", .meal, 1150), st("stay:d:end", .stay, 1260),
        ], legs: [], warnings: [])
        XCTAssertEqual(TripStages.stages(day, wishes: []), [.morning, .morning, .lunch, .afternoon, .evening, .evening])
        // The solver's stages win when every stop has one.
        for i in day.stops.indices { day.stops[i].stage = "evening" }
        XCTAssertEqual(TripStages.stages(day, wishes: []), Array(repeating: .evening, count: 6))
        day.stops[3].stage = "teatime"
        XCTAssertEqual(TripStages.stages(day, wishes: [])[3], .afternoon, "an unknown stage: the whole day falls back to stageOf")
        XCTAssertEqual(TripStages.groups(day, wishes: []).map(\.stage), DayStage.allCases)
        XCTAssertEqual(TripStages.brief(day, [0, 1]), "col")
    }

    func testAStageEncodesOnlyWhenSet() throws {
        var stop = Self.day().stops[1]
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(stop)) as? [String: Any])
        XCTAssertNil(object["stage"])
        stop.stage = "lunch"
        object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(stop)) as? [String: Any])
        XCTAssertEqual(object["stage"] as? String, "lunch")
    }

    // MARK: Off the plan

    func testIdleAndBehindNeedEvidence() throws {
        let clock = TripClock("Europe/Rome")
        let day = Self.day()
        let quiet = TripProgress.of(day: day, marks: [:], nowMin: 700, clock: clock)
        XCTAssertTrue(TripOffPlanRules.detect(day: day, marks: [:], progress: quiet, nowMin: 700, fixes: [], dwell: nil, clock: clock).isEmpty,
                      "nothing recorded and no fix: no prompt")
        let marks = [
            "stay:2026-10-27:start": TripStopMark(leftAt: clock.date("2026-10-27", minutes: 548)),
            "pantheon": TripStopMark(arrivedAt: clock.date("2026-10-27", minutes: 560)),
        ]
        let at = TripProgress.of(day: day, marks: marks, nowMin: 630, clock: clock)
        let kinds = TripOffPlanRules.detect(day: day, marks: marks, progress: at, nowMin: 630, fixes: [], dwell: nil, clock: clock)
            .map(\.observation.kind)
        XCTAssertEqual(Set(kinds), [.behind, .idle])
    }

    func testAnUnplannedStopIsFarFromEveryStop() {
        let clock = TripClock("Europe/Rome")
        let day = Self.day()
        let p = TripProgress.of(day: day, marks: [:], nowMin: 600, clock: clock)
        let far = TripOffPlanRules.Dwell(at: TripLatLng(lat: 41.91, lng: 12.50), sinceMin: 585)
        let near = TripOffPlanRules.Dwell(at: TripLatLng(lat: 41.8987, lng: 12.4769), sinceMin: 585)
        XCTAssertEqual(TripOffPlanRules.detect(day: day, marks: [:], progress: p, nowMin: 600, fixes: [], dwell: far, clock: clock)
            .map(\.observation.kind), [.unplannedStop])
        XCTAssertTrue(TripOffPlanRules.detect(day: day, marks: [:], progress: p, nowMin: 600, fixes: [], dwell: near, clock: clock).isEmpty)
        XCTAssertTrue(TripOffPlanRules.detect(day: day, marks: [:], progress: p, nowMin: 590, fixes: [], dwell: far, clock: clock).isEmpty,
                      "under twelve minutes is a pause, not a stop")
    }

    func testDistanceToALeg() {
        let line = [TripLatLng(lat: 41.9, lng: 12.48), TripLatLng(lat: 41.9, lng: 12.49)]
        XCTAssertLessThan(TripOffPlanRules.distanceToLine(TripLatLng(lat: 41.9, lng: 12.485), line), 1)
        XCTAssertEqual(TripOffPlanRules.distanceToLine(TripLatLng(lat: 41.9036, lng: 12.485), line), 400, accuracy: 10)
    }

    // MARK: Fixture

    private static func day() -> PlannedDay {
        func stop(_ id: String, _ kind: StopKind, _ a: Double, _ d: Double) -> PlannedStop {
            PlannedStop(id: id, kind: kind, wishId: kind == .wish ? id : nil, title: id == "pantheon" ? "Pantheon" : id,
                        location: TripLatLng(lat: 41.8986, lng: 12.4769), arriveMin: a, departMin: d, waitSec: 0,
                        locked: false, bookingId: nil, warnings: [])
        }
        let leg = PlannedLeg(fromStopId: "", toStopId: "", mode: .walk, durationSec: 720, distanceM: 900, estimated: false, line: nil)
        return PlannedDay(
            date: "2026-10-27", stayId: "campo",
            stops: [stop("stay:2026-10-27:start", .stay, 540, 548), stop("pantheon", .wish, 560, 605), stop("stay:2026-10-27:end", .stay, 640, 640)],
            legs: [leg, leg], warnings: []
        )
    }
}
