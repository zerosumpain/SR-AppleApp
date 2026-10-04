import XCTest
import CoreLocation
@testable import SRAppleApp

/// Landgrab on the steps page and its map: the wire contract (the spec's own
/// shapes, decoded as SR-Main will send them, and decoded again with fields
/// missing, null and odd), the ranking and the words, London weeks, and the
/// `[lat, lon]` → map coordinate conversion. Coordinates are Central Park,
/// New York — synthetic, as everywhere in this public repository.
final class LandgrabTests: XCTestCase {

    // MARK: - The wire

    private let weeksJSON = #"""
    { "updatedAt": "2026-10-03T13:05:00.000Z",
      "weeks": [
        { "start": "2026-09-28", "end": "2026-10-04", "current": true,
          "people": [
            { "id": "f_l", "name": "Lee", "me": false, "won": 41, "taken": 12, "lost": 3, "net": 38, "held": 211, "rank": 1, "colour": "#c2410c" },
            { "id": "f_j", "name": "John", "me": true, "won": 9, "taken": 9, "lost": 12, "net": -3, "held": 140, "rank": 2, "colour": "#1d4ed8" },
            { "id": "f_m", "name": "Mo", "won": null, "colour": "not a colour", "somethingNew": [1, 2] } ] },
        { "start": "2026-09-21", "end": "2026-09-27", "current": false,
          "people": [ { "id": "f_l", "name": "Lee", "won": 10, "lost": 0, "net": 10 },
                      { "id": "f_j", "name": "John", "me": true, "won": 22, "lost": 1, "net": 21 } ] },
        { "end": "2026-09-20", "people": [] },
        "not a week" ] }
    """#

    private let changesJSON = #"""
    { "week": { "start": "2026-09-28", "end": "2026-10-04", "current": true },
      "bounds": { "minLat": 40.775, "minLon": -73.975, "maxLat": 40.79, "maxLon": -73.955 },
      "people": [ { "id": "f_l", "name": "Lee", "colour": "#c2410c" }, { "id": "f_j", "name": "John", "colour": null } ],
      "hexes": [
        { "id": 0, "polygon": [[40.7800,-73.9660],[40.7802,-73.9655],[40.7806,-73.9655],[40.7808,-73.9660],[40.7806,-73.9665],[40.7802,-73.9665]], "owner": "f_l", "previous": "f_j" },
        { "id": 1, "polygon": [[40.7810,-73.9660],[40.7812,-73.9655],[40.7816,-73.9655],[40.7818,-73.9660],[40.7816,-73.9665],[40.7812,-73.9665]], "owner": "f_l", "previous": null },
        { "id": 2, "polygon": [[40.7820,-73.9660],[91,0],[40.7826,-73.9655],[40.7828,-73.9660]], "owner": "f_j" },
        { "id": 3, "polygon": [[40.7,-73.9]], "owner": "f_j" },
        { "polygon": [] } ],
      "changes": [
        { "id": "workout:abc", "personId": "f_l", "at": "2026-10-03T08:12:00Z", "won": 2, "taken": 1,
          "from": [ { "id": "f_j", "hexes": 1 }, { "id": null, "hexes": 1 } ], "hexIds": [0, 1, 99],
          "activity": { "kind": "workout", "type": "walk", "startedAt": "2026-10-03T08:12:00Z", "endedAt": null,
                        "distanceM": 3412.4, "durationS": 2400, "loop": true,
                        "trace": [[40.7795,-73.9668],[40.7805,-73.9660],[40.7815,-73.9658],"bad",[40.7820,-73.9655]] } },
        { "id": "unattributed:x", "at": null, "won": 1, "from": [ { "hexes": 1 } ], "hexIds": [2], "activity": null },
        { "id": "trail:y", "subject": "f_j", "won": 0, "hexIds": [], "activity": { "kind": "trail", "type": "skate", "loop": "yes" } } ] }
    """#

    private func board() throws -> LandgrabBoard {
        try JSONDecoder().decode(LandgrabBoard.self, from: Data(weeksJSON.utf8))
    }

    private func changes() throws -> LandgrabChanges {
        try JSONDecoder().decode(LandgrabChanges.self, from: Data(changesJSON.utf8))
    }

    private let names = ["f_l": "Lee", "f_j": "John"]
    private var namer: (String?) -> String { { [names] in $0.flatMap { names[$0] } ?? "someone" } }

    func testTheWeeklyBoardDecodesAsTheSpecSendsIt() throws {
        let board = try board()
        XCTAssertEqual(board.updatedAt, "2026-10-03T13:05:00.000Z")
        // A week with no Monday and a week that is not an object are dropped;
        // the rest of the board stands.
        XCTAssertEqual(board.weeks.map(\.start), ["2026-09-28", "2026-09-21"])
        let week = try XCTUnwrap(Landgrab.currentWeek(board))
        XCTAssertTrue(week.current)
        XCTAssertEqual(week.people.first?.colour, "#c2410c")
        XCTAssertEqual(week.people[1].net, -3)
        XCTAssertTrue(week.people[1].me)
    }

    func testMissingNullAndOddFieldsCostOnlyThemselves() throws {
        let mo = try board().weeks[0].people[2]
        XCTAssertEqual(mo.won, 0)
        XCTAssertEqual(mo.net, 0)
        XCTAssertFalse(mo.me)
        XCTAssertNil(LandgrabColour.parse(mo.colour))

        // A missing net is worked out, not taken as nought.
        let derived = try JSONDecoder().decode(LandgrabPerson.self, from: Data(#"{"id":"x","won":5,"lost":2}"#.utf8))
        XCTAssertEqual(derived.net, 3)
        // Numbers as strings or floats, an id as a number, `me` as 1.
        let odd = try JSONDecoder().decode(LandgrabPerson.self, from: Data(#"{"id":7,"won":"5","lost":2.0,"me":1}"#.utf8))
        XCTAssertEqual(odd.id, "7")
        XCTAssertEqual(odd.won, 5)
        XCTAssertEqual(odd.lost, 2)
        XCTAssertTrue(odd.me)

        let empty = try JSONDecoder().decode(LandgrabBoard.self, from: Data("{}".utf8))
        XCTAssertTrue(empty.weeks.isEmpty)
        let junk = try JSONDecoder().decode(LandgrabChanges.self, from: Data(#"{"hexes":null,"changes":"x","week":7}"#.utf8))
        XCTAssertTrue(junk.hexes.isEmpty)
        XCTAssertTrue(junk.changes.isEmpty)
        XCTAssertEqual(junk.week.start, "")
    }

    func testTheChangesDecodeAndBadShapesAreDropped() throws {
        let changes = try changes()
        XCTAssertEqual(changes.week.start, "2026-09-28")
        XCTAssertEqual(changes.bounds?.maxLat, 40.79)
        XCTAssertFalse(changes.truncated)
        // Hex 3 has one corner and the last has no id: gone. Hex 2's corner at
        // latitude 91 is off the globe: dropped, leaving a triangle.
        XCTAssertEqual(changes.hexes.map(\.id), [0, 1, 2])
        XCTAssertEqual(changes.hexes[2].polygon.count, 3)
        XCTAssertNil(changes.hexes[1].previous)

        let walk = changes.changes[0]
        XCTAssertEqual(walk.personId, "f_l")
        XCTAssertEqual(walk.activity?.typeValue, .walk)
        XCTAssertEqual(walk.activity?.loop, true)
        XCTAssertEqual(walk.activity?.trace.count, 4, "the bad trace point is dropped")

        // No person on the change: it is the owner of its hexes.
        XCTAssertEqual(changes.changes[1].personId, "f_j")
        XCTAssertNil(changes.changes[1].activity)
        XCTAssertNil(changes.changes[1].from.first?.id, "unclaimed ground has a null id")

        // `subject` is still read, an unknown type is no type, and a loop
        // that is not a boolean is no loop.
        let trail = changes.changes[2]
        XCTAssertEqual(trail.personId, "f_j")
        XCTAssertNil(trail.activity?.typeValue)
        XCTAssertEqual(trail.activity?.loop, false)
    }

    // MARK: - Visibility

    func testTheSectionHidesWithNoBoardOrNobodyOnIt() throws {
        XCTAssertTrue(Landgrab.shows(try board()))
        XCTAssertFalse(Landgrab.shows(nil))
        XCTAssertFalse(Landgrab.shows(LandgrabBoard(weeks: [])))
        XCTAssertFalse(Landgrab.shows(LandgrabBoard(weeks: [LandgrabWeek(start: "2026-09-28", end: "2026-10-04", current: true, people: [])])))
    }

    @MainActor func testNotFamilyAndNotThereHideTheSectionButAnOutageDoesNot() {
        XCTAssertTrue(LandgrabStore.hides(SiteError.status(403, "NOT_FAMILY")))
        XCTAssertTrue(LandgrabStore.hides(SiteError.status(404, "")))
        XCTAssertTrue(LandgrabStore.hides(SiteError.expired))
        XCTAssertFalse(LandgrabStore.hides(SiteError.status(502, "landgrab unavailable")))
        XCTAssertFalse(LandgrabStore.hides(URLError(.notConnectedToInternet)))
    }

    // MARK: - Ranking and figures

    func testRankingIsNetThenWonThenNameWithSharedRanks() {
        let ranked = Landgrab.ranked([
            LandgrabPerson(id: "a", name: "Sam", won: 10, lost: 0),
            LandgrabPerson(id: "b", name: "alex", won: 10, lost: 0),
            LandgrabPerson(id: "c", name: "Pat", won: 20, lost: 10),
            LandgrabPerson(id: "d", name: "Kit", won: 2, lost: 5),
        ])
        XCTAssertEqual(ranked.map(\.id), ["c", "b", "a", "d"])
        XCTAssertEqual(ranked.map(\.rank), [1, 2, 2, 4])
        XCTAssertTrue(Landgrab.tied(ranked[1], in: ranked))
        XCTAssertFalse(Landgrab.tied(ranked[0], in: ranked))
    }

    func testFigures() {
        XCTAssertEqual(Landgrab.signed(38), "+38")
        XCTAssertEqual(Landgrab.signed(-3), "\u{2212}3")
        XCTAssertEqual(Landgrab.signed(0), "0")
        XCTAssertEqual(Landgrab.signed(1_234), "+1,234")
        XCTAssertEqual(Landgrab.hexes(1), "1 hex")
        XCTAssertEqual(Landgrab.hexes(18), "18 hexes")
        XCTAssertEqual(Landgrab.distance(3_412.4), "3.4 km")
        XCTAssertEqual(Landgrab.distance(850), "850 m")
        XCTAssertEqual(Landgrab.distance(123_456), "123 km")
        XCTAssertNil(Landgrab.distance(nil))
        XCTAssertNil(Landgrab.distance(0))
    }

    func testTheRowIsSaidInFull() {
        let kit = LandgrabPerson(id: "d", name: "Kit", won: 2, lost: 5, rank: 4)
        XCTAssertEqual(Landgrab.spoken(kit), "4th, Kit, won 2 hexes, lost 5, net minus 3")
        let me = LandgrabPerson(id: "m", name: "John", me: true, won: 1, lost: 0, rank: 1)
        XCTAssertEqual(Landgrab.spoken(me, tied: true), "Joint 1st, you, won 1 hex, lost 0, net plus 1")
    }

    func testLastWeeksLeader() throws {
        XCTAssertEqual(Landgrab.lastWeekLine(try board()), "Last week: you won most ground.")
        let tie = LandgrabBoard(weeks: [
            LandgrabWeek(start: "2026-09-28", end: "2026-10-04", current: true, people: []),
            LandgrabWeek(start: "2026-09-21", end: "2026-09-27", people: [
                LandgrabPerson(id: "a", name: "Lee", won: 5), LandgrabPerson(id: "b", name: "Sam", won: 5),
            ]),
        ])
        XCTAssertEqual(Landgrab.lastWeekLine(tie), "Last week: Lee and Sam won the same ground.")
        let idle = LandgrabBoard(weeks: [
            LandgrabWeek(start: "2026-09-28", end: "2026-10-04", current: true, people: []),
            LandgrabWeek(start: "2026-09-21", end: "2026-09-27", people: [LandgrabPerson(id: "a", name: "Lee")]),
        ])
        XCTAssertNil(Landgrab.lastWeekLine(idle))
        XCTAssertNil(Landgrab.lastWeekLine(LandgrabBoard(weeks: [tie.weeks[0]])))
    }

    // MARK: - Weeks (London Mondays)

    private func at(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    func testWeeksStartOnTheLondonMonday() {
        // 23:30 BST on Sunday 4 October is still the week of 28 September…
        XCTAssertEqual(Landgrab.monday(of: at("2026-10-04T22:30:00Z")), "2026-09-28")
        // …and 00:30 BST on Monday 5 October (23:30 UTC on the 4th) is the next.
        XCTAssertEqual(Landgrab.monday(of: at("2026-10-04T23:30:00Z")), "2026-10-05")
        // In GMT, after the clocks go back on 25 October.
        XCTAssertEqual(Landgrab.monday(of: at("2026-10-26T00:30:00Z")), "2026-10-26")
        XCTAssertEqual(Landgrab.monday(of: at("2026-11-02T00:10:00Z")), "2026-11-02")
    }

    func testWeekLabels() {
        let now = at("2026-10-03T12:00:00Z")
        XCTAssertEqual(Landgrab.weekLabel(start: "2026-09-28", current: false, now: now), "This week")
        XCTAssertEqual(Landgrab.weekLabel(start: "2026-09-14", current: true, now: now), "This week")
        XCTAssertEqual(Landgrab.weekLabel(start: "2026-09-21", current: false, now: now), "Last week")
        XCTAssertEqual(Landgrab.weekLabel(start: "2026-09-14", current: false, now: now), "Week of 14 Sep")
        // Across the clocks going back.
        XCTAssertEqual(Landgrab.weekLabel(start: "2026-10-19", current: false, now: at("2026-10-26T00:30:00Z")), "Last week")
        XCTAssertEqual(Landgrab.weekRange(start: "2026-09-28", end: "2026-10-04"), "28 Sep – 4 Oct")
        XCTAssertEqual(Landgrab.weekRange(start: "2026-09-28", end: ""), "28 Sep – 4 Oct")
        XCTAssertNil(Landgrab.weekRange(start: "soon", end: ""))
        XCTAssertEqual(Landgrab.phrase("Week of 14 Sep"), "in the week of 14 Sep")
        XCTAssertEqual(Landgrab.phrase("This week"), "this week")
    }

    // MARK: - Changes, in words

    func testActivityLabels() throws {
        let changes = try changes()
        XCTAssertEqual(Landgrab.activityLabel(changes.changes[0], name: "Lee", me: false), "Lee's walk")
        XCTAssertEqual(Landgrab.activityLabel(changes.changes[0], name: "John", me: true), "Your walk")
        XCTAssertEqual(Landgrab.activityLabel(changes.changes[1], name: "John", me: false), "Ground that changed hands")
        XCTAssertEqual(Landgrab.activityLabel(changes.changes[2], name: "John", me: false), "John's journey")
        let ride = LandgrabChange(id: "r", personId: "f_j", won: 3, activity: LandgrabActivity(type: "RIDE"))
        XCTAssertEqual(Landgrab.activityLabel(ride, name: "John", me: false), "John's ride")
    }

    func testTheChangeLineAndItsVoiceOverLabel() throws {
        let walk = try changes().changes[0]
        XCTAssertEqual(Landgrab.shortTime("2026-10-03T08:12:00Z"), "Sat 09:12", "London, BST")
        XCTAssertEqual(Landgrab.shortTime("2026-10-03T08:12:00.250Z"), "Sat 09:12")
        XCTAssertEqual(Landgrab.spokenTime("2026-12-05T08:12:00Z"), "Saturday 08:12", "London, GMT")
        XCTAssertEqual(Landgrab.changeLine(walk, label: "Lee's walk", name: namer),
                       "Lee's walk · Sat 09:12 · 3.4 km · won 2 hexes, 1 from John")
        XCTAssertEqual(Landgrab.spokenChange(walk, label: "Lee's walk", name: namer),
                       "Lee's walk, Saturday 09:12, 3.4 kilometres, closed a loop. Won 2 hexes: 1 from John, 1 nobody held.")
    }

    func testTheListIsNewestFirstWithUnexplainedGroundLast() throws {
        XCTAssertEqual(Landgrab.ordered(try changes().changes).map(\.id), ["workout:abc", "trail:y", "unattributed:x"])
    }

    func testTheMapSummary() throws {
        XCTAssertEqual(Landgrab.mapSummary(try changes(), weekLabel: "This week", name: namer),
                       "Map. 3 hexes changed hands this week, in 3 changes. Lee won the most, 2.")
        let quiet = LandgrabChanges(week: LandgrabWeekRange(start: "2026-09-14", end: "2026-09-20"), people: [], hexes: [], changes: [])
        XCTAssertEqual(Landgrab.mapSummary(quiet, weekLabel: "Week of 14 Sep", name: namer),
                       "Map. No ground changed hands in the week of 14 Sep.")
    }

    // MARK: - Colour

    func testColoursParseFallBackAndPickLegibleText() {
        XCTAssertEqual(LandgrabColour.parse("#c41"), LandgrabColour.parse("cc4411"))
        XCTAssertNil(LandgrabColour.parse("#zzzzzz"))
        XCTAssertNil(LandgrabColour.parse(""))
        XCTAssertNil(LandgrabColour.parse(nil))
        // The same person gets the same fallback on every launch.
        XCTAssertEqual(LandgrabColour.resolve(nil, id: "f_j"), LandgrabColour.resolve("nonsense", id: "f_j"))
        // Ink on a pale yellow, cream on a deep blue.
        XCTAssertTrue(LandgrabColour.writesInInk(on: LandgrabColour.parse("#fde047")!))
        XCTAssertFalse(LandgrabColour.writesInInk(on: LandgrabColour.parse("#1d4ed8")!))
        XCTAssertEqual(LandgrabRGB(hex: 0xFFFFFF).contrast(with: LandgrabRGB(hex: 0)), 21, accuracy: 0.01)
    }

    // MARK: - The map, worked out once

    func testThePlanHoldsEveryChangesHexesTraceAndRegion() throws {
        let plan = LandgrabMapPlan(try changes())
        XCTAssertEqual(plan.shapes.count, 3)
        XCTAssertEqual(plan.shapes[0].colour, LandgrabColour.parse("#c2410c"))
        XCTAssertEqual(plan.shapes[2].colour, LandgrabColour.resolve(nil, id: "f_j"), "John sent no colour")
        XCTAssertEqual(plan.hexesByChange["workout:abc"], [0, 1], "an unknown hex id is dropped")
        XCTAssertEqual(plan.traces["workout:abc"]?.count, 4)
        let region = try XCTUnwrap(plan.changeRegions["workout:abc"])
        XCTAssertEqual(region.centreLat, 40.78065, accuracy: 0.001)
        XCTAssertEqual(region.centreLon, -73.96615, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(region.latSpan, 0.004, "never tighter than the floor")
        XCTAssertNotNil(plan.weekRegion)
        XCTAssertNil(plan.changeRegions["trail:y"], "nothing to fit")
    }

    func testWireCoordinatesAreLatitudeFirst() throws {
        let layer = LandgrabMapLayer(LandgrabMapPlan(try changes()))
        let corner = try XCTUnwrap(layer.hexes.first?.coordinates.first)
        XCTAssertEqual(corner.latitude, 40.7800, accuracy: 1e-9)
        XCTAssertEqual(corner.longitude, -73.9660, accuracy: 1e-9)
        XCTAssertEqual(layer.hexes.first?.coordinates.count, 6)
        let trace = try XCTUnwrap(layer.traces["workout:abc"])
        XCTAssertEqual(trace.first?.latitude ?? 0, 40.7795, accuracy: 1e-9)
        XCTAssertEqual(trace.first?.longitude ?? 0, -73.9668, accuracy: 1e-9)
        let region = try XCTUnwrap(layer.changeRegions["workout:abc"])
        XCTAssertTrue(CLLocationCoordinate2DIsValid(region.center))
        XCTAssertEqual(region.center.latitude, 40.78065, accuracy: 0.001)
    }

    // MARK: - The demo answers decode, and agree with each other

    func testTheDemoBoardAndMapDecodeAndAgree() throws {
        let clock = SRDemoFixtures.DemoClock(now: at("2026-10-03T12:00:00Z"))
        let weeksText = try XCTUnwrap(SRDemoFixtures.route(method: "GET", path: "/api/native/family/landgrab",
                                                          query: ["weeks": "6"], body: nil, clock: clock))
        let board = try JSONDecoder().decode(LandgrabBoard.self, from: Data(weeksText.utf8))
        XCTAssertEqual(board.weeks.count, 6)
        XCTAssertEqual(board.weeks.first?.start, "2026-09-28")
        XCTAssertTrue(Landgrab.shows(board))

        let mapText = try XCTUnwrap(SRDemoFixtures.route(method: "GET", path: "/api/native/family/landgrab/changes",
                                                        query: ["week": "2026-09-28"], body: nil, clock: clock))
        let changes = try JSONDecoder().decode(LandgrabChanges.self, from: Data(mapText.utf8))
        XCTAssertEqual(changes.changes.count, 4)
        XCTAssertTrue((100...4_000).contains(changes.hexes.count))
        // The board's "won" is counted from the map's hexes.
        for person in board.weeks[0].people {
            XCTAssertEqual(changes.hexes.filter { $0.owner == person.id }.count, person.won, person.name)
        }
        // Everything inside Central Park.
        let points = changes.hexes.flatMap(\.polygon) + changes.changes.flatMap { $0.activity?.trace ?? [] }
        XCTAssertTrue(points.allSatisfy { (40.764...40.801).contains($0.lat) && (-73.982 ... -73.947).contains($0.lon) })

        let quietText = try XCTUnwrap(SRDemoFixtures.route(method: "GET", path: "/api/native/family/landgrab/changes",
                                                          query: ["week": "2026-09-14"], body: nil, clock: clock))
        let quiet = try JSONDecoder().decode(LandgrabChanges.self, from: Data(quietText.utf8))
        XCTAssertTrue(quiet.changes.isEmpty, "the third week back is the quiet one")
        XCTAssertNil(SRDemoFixtures.route(method: "GET", path: "/api/native/family/landgrab/changes",
                                          query: ["week": "2020-01-06"], body: nil, clock: clock))
    }
}
