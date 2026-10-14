import XCTest
@testable import SRAppleApp

/// The phone's port of the trip solver (`Trips/TripReplan.swift`) against
/// SR-Main's own answers. `Fixtures/TripCases/*.json` are copied verbatim
/// from SR-Main `src/lib/trips/solver/fixtures/cases/` (feat/trips-solver,
/// 978c4818): each holds the solver's input and the output the TypeScript
/// gave. Every case must come back identical — same stops, same minutes,
/// same legs, same warnings, same labels, same order.
///
/// Compared as canonical JSON (sorted keys), which is exactly what the
/// server's `JSON.parse(JSON.stringify(...))` comparison sees.
final class TripReplanTests: XCTestCase {

    private struct Input: Decodable {
        let trip: Trip
        let stays: [TripStay]
        let wishes: [TripWish]
        let bookings: [TripBooking]
        let matrix: TravelMatrix
        let day: PlannedDay
        let nowMin: Double?
        let position: TripLatLng?
        let atStopId: String?
        let doneStopIds: [String]?
        let fromIndex: Int?
        let startMin: Double?
        let transport: [TransportSegment]?

        var context: TripReplan.Context {
            TripReplan.Context(trip: trip, stays: stays, wishes: wishes, bookings: bookings, matrix: matrix, transport: transport ?? [])
        }
    }

    private struct Case<Expected: Decodable>: Decodable {
        let name: String
        let fn: String
        let input: Input
        let expected: Expected
    }

    private struct Head: Decodable { let fn: String }

    private func caseFiles() -> [URL] {
        let bundle = Bundle(for: TripReplanTests.self)
        // At the bundle root (how xcodegen copies a source folder's
        // resources) or, should that change, under TripCases/.
        let all = (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            + (bundle.urls(forResourcesWithExtension: "json", subdirectory: "TripCases") ?? [])
        var seen = Set<String>()
        return all
            .filter { let n = $0.lastPathComponent; return n.hasPrefix("replan-") || n.hasPrefix("retime-") }
            .filter { seen.insert($0.lastPathComponent).inserted }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func canonical<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    func testEverySharedCaseIsBundled() {
        XCTAssertEqual(caseFiles().count, 14, "the fourteen replan/retime cases from SR-Main should all be in the test bundle")
        XCTAssertEqual(tripCaseFiles().count, 6, "and the six replanTrip cases")
        // The solve-*.json cases (four at 978c4818) are solveTrip's — server-side, not ported
        // (fitDay and day assignment stay on the site). Bundled, not replayed.
    }

    // MARK: replanTrip cases (server-side)
    //
    // `replanTrip` is not ported — it needs `solveTrip`. These check the
    // parts of its answers the phone's port DOES produce: every carry-on
    // option's today is `replanDay`'s best (taxi legs included), and a
    // pull-forward's today is `pullForwardCandidates` + `pullForwardDay`.

    private struct TripInput: Decodable {
        let trip: Trip
        let stays: [TripStay]
        let wishes: [TripWish]
        let bookings: [TripBooking]
        let matrix: TravelMatrix
        let day: PlannedDay
        let nowMin: Double
        let position: TripLatLng?
        let atStopId: String?
        let doneStopIds: [String]
        let observation: Observation?
        let plannedDays: [PlannedDay]
        let transport: [TransportSegment]?
    }

    private struct TripCase: Decodable {
        let name: String
        let input: TripInput
        let expected: [TripReplanOption]
    }

    private func tripCaseFiles() -> [URL] {
        let bundle = Bundle(for: TripReplanTests.self)
        let all = (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            + (bundle.urls(forResourcesWithExtension: "json", subdirectory: "TripCases") ?? [])
        var seen = Set<String>()
        return all.filter { $0.lastPathComponent.hasPrefix("trip-") && seen.insert($0.lastPathComponent).inserted }
    }

    func testTheTripCasesAgreeWhereThePortReaches() throws {
        for url in tripCaseFiles() {
            let c = try JSONDecoder().decode(TripCase.self, from: Data(contentsOf: url))
            let i = c.input
            let context = TripReplan.Context(trip: i.trip, stays: i.stays, wishes: i.wishes, bookings: i.bookings, matrix: i.matrix,
                                             transport: i.transport ?? [])
            let input = TripReplan.Input(context: context, day: i.day, nowMin: i.nowMin, position: i.position,
                                         atStopId: i.atStopId, doneStopIds: i.doneStopIds)
            if let carry = c.expected.first(where: { $0.kind == "carry-on" }) {
                let best = try XCTUnwrap(TripReplan.replanDay(input).first, c.name)
                XCTAssertEqual(try canonical(best.day), try canonical(carry.days[0]), "\(c.name): carry-on today")
                XCTAssertEqual(best.dropped, carry.dropped, c.name)
            }
            if let pull = c.expected.first(where: { $0.kind == "pull-forward" }), let obs = i.observation {
                let pulledId = pull.moved.first { $0.to == i.day.date }?.wishId ?? obs.stopId ?? ""
                let without = pull.moved.filter { $0.from == i.day.date }.map(\.wishId)
                var here = input
                if obs.kind == .outOfOrder {
                    here.position = obs.place?.location ?? i.position
                } else {
                    let place = try XCTUnwrap(obs.place?.location)
                    let later = i.plannedDays.filter { $0.date > i.day.date }
                    let first = TripReplan.pullForwardCandidates(i.wishes, i.bookings, today: i.day.date, laterDays: later, position: place).first
                    XCTAssertEqual(first?.wishId, pulledId, "\(c.name): candidate")
                    if TripReplan.situation(input).at < 0 { here.position = place }
                }
                let got = TripReplan.pullForwardDay(here, wishIds: [pulledId], without: without)
                XCTAssertEqual(try canonical(got.day), try canonical(pull.days[0]), "\(c.name): pull-forward today")
            }
        }
    }

    /// v2.1: a light day ends 90 min earlier; a lunch-replacing wish must
    /// start inside the lunch window.
    func testLightDaysAndMealReplacingWishes() {
        let rules = TripReplan.solverRules(.normal)
        XCTAssertEqual(TripReplan.dayFrame(rules, ["2026-10-27": "light"], "2026-10-27", nil).dayEndMin, rules.dayEndMin - 90)
        XCTAssertEqual(TripReplan.dayFrame(rules, ["2026-10-27": "full"], "2026-10-27", nil).dayEndMin, rules.dayEndMin)
        XCTAssertEqual(TripReplan.dayFrame(rules, ["2026-10-27": "sideways"], "2026-10-27", nil).load, "normal")
        var wish = TripWish(id: "w", title: "Trattoria", place: nil, priority: .nice, durationSec: 3600, partOfDay: .evening,
                            fixedDate: nil, fixedStartMin: nil, locked: false, suggested: false, skipped: false,
                            facts: nil, note: nil, sortHint: 0)
        wish.replacesMeal = "lunch"
        // Lunch 12:00–14:30 for 60 min: start by 13:30, may run to 14:30.
        XCTAssertEqual(TripReplan.wishWindows(wish, "2026-10-27", rules), [TripOpenRange(openMin: 720, closeMin: 870)])
        wish.replacesMeal = "dinner"
        XCTAssertEqual(TripReplan.wishWindows(wish, "2026-10-27", rules), [TripOpenRange(openMin: 1140, closeMin: 1275)],
                       "v4 dinner for the normal pace: 19:00–21:30 for 75 min")
        XCTAssertEqual(TripReplan.wishItem(wish, "2026-10-27", [], rules).partOfDay, .any)
    }

    /// v4 (rules.ts): three meals every pace; back at the stay after dinner,
    /// sightseeing still done by the pace's old day end.
    func testEveryPacePlansThreeMeals() {
        let normal = TripReplan.solverRules(.normal)
        XCTAssertEqual(normal.breakfast.fromMin, 450)
        XCTAssertEqual(normal.dinner.fromMin, 1140)
        XCTAssertEqual(normal.activeEndMin, 19 * 60)
        XCTAssertEqual(normal.dayEndMin, 21 * 60 + 30 + 60)
        let relaxed = TripReplan.solverRules(.relaxed)
        XCTAssertEqual(relaxed.dinner.durationSec, 90 * 60)
        let packed = TripReplan.solverRules(.packed)
        XCTAssertEqual(packed.dinner, TripPaceRules.of(.packed).dinner, "packed keeps its own dinner")
        XCTAssertEqual(packed.dayEndMin, TripPaceRules.of(.packed).dayEndMin)
    }

    /// v4 (stages.ts): stages follow the meals and never go backwards.
    func testStageOfIsTheSolvers() {
        func st(_ id: String, _ kind: StopKind, _ at: Double, wish: String? = nil) -> PlannedStop {
            PlannedStop(id: id, kind: kind, wishId: wish, title: id, location: nil, arriveMin: at, departMin: at + 30,
                        waitSec: 0, locked: false, bookingId: nil, warnings: [])
        }
        let stops = [
            st("stay:d:start", .stay, 500), st("meal:d:breakfast", .meal, 510), st("cafe", .wish, 700, wish: "cafe"),
            st("pan", .wish, 840, wish: "pan"), st("stay:d:rest", .stay, 1080), st("meal:d:dinner", .meal, 1140),
        ]
        let stages = TripReplan.stageOf(stops) { TripReplan.mealOfStop($0, ["cafe": "lunch"]) }
        XCTAssertEqual(stages, [.morning, .morning, .lunch, .afternoon, .afternoon, .evening])
        let noMeals = [st("a", .wish, 600), st("b", .wish, 760), st("c", .wish, 700), st("d", .wish, 1100)]
        XCTAssertEqual(TripReplan.stageOf(noMeals) { _ in nil }, [.morning, .afternoon, .afternoon, .evening],
                       "c is early but stages never go backwards")
    }

    func testTaxiIsTheDriveRowPlusPickUp() {
        let matrix = TravelMatrix(points: ["a", "b"], seconds: ["drive": [[0, 600], [600, 0]]], metres: ["drive": [[0, 4000], [4000, 0]]], estimated: ["drive": false])
        XCTAssertEqual(TripReplan.modeSeconds(matrix, .taxi, 0, 1)?.seconds, 600 + 8 * 60)
        XCTAssertEqual(TripReplan.modeSeconds(matrix, .taxi, 0, 1)?.metres, 4000)
        XCTAssertNil(TripReplan.modeSeconds(matrix, .transit, 0, 1))
        let a = TripLatLng(lat: 41.89, lng: 12.47), b = TripLatLng(lat: 41.91, lng: 12.49)
        XCTAssertEqual(TripReplan.estimateLeg(a, b, .taxi).seconds - TripReplan.estimateLeg(a, b, .drive).seconds, 480, accuracy: 1)
    }

    func testEverySharedCaseReplaysIdentically() throws {
        let files = caseFiles()
        XCTAssertFalse(files.isEmpty)
        for url in files {
            let data = try Data(contentsOf: url)
            let fn = try JSONDecoder().decode(Head.self, from: data).fn
            switch fn {
            case "retimeDay":
                let c = try JSONDecoder().decode(Case<PlannedDay>.self, from: data)
                let got = TripReplan.retimeDay(
                    c.input.day, fromIndex: try XCTUnwrap(c.input.fromIndex),
                    startMin: try XCTUnwrap(c.input.startMin), context: c.input.context
                )
                XCTAssertEqual(try canonical(got), try canonical(c.expected), c.name)
            case "replanDay":
                let c = try JSONDecoder().decode(Case<[ReplanOption]>.self, from: data)
                let got = TripReplan.replanDay(TripReplan.Input(
                    context: c.input.context, day: c.input.day, nowMin: try XCTUnwrap(c.input.nowMin),
                    position: c.input.position, atStopId: c.input.atStopId, doneStopIds: c.input.doneStopIds ?? []
                ))
                XCTAssertEqual(got.map(\.label), c.expected.map(\.label), c.name)
                XCTAssertEqual(try canonical(got), try canonical(c.expected), c.name)
            default:
                XCTFail("\(url.lastPathComponent): unknown fn \(fn)")
            }
        }
    }

    // MARK: JavaScript semantics the port depends on

    /// The bug c1100734 fixed: no option may move a booked or locked stop.
    func testNoOptionMovesALockedStop() throws {
        for url in caseFiles() where url.lastPathComponent.hasPrefix("replan-") {
            let c = try JSONDecoder().decode(Case<[ReplanOption]>.self, from: Data(contentsOf: url))
            let got = TripReplan.replanDay(TripReplan.Input(
                context: c.input.context, day: c.input.day, nowMin: try XCTUnwrap(c.input.nowMin),
                position: c.input.position, atStopId: c.input.atStopId, doneStopIds: c.input.doneStopIds ?? []
            ))
            for option in got {
                for stop in option.day.stops where stop.locked && stop.id != c.input.atStopId {
                    guard let planned = c.input.day.stops.first(where: { $0.id == stop.id }) else { continue }
                    XCTAssertEqual(stop.arriveMin, planned.arriveMin, "\(c.name): \(option.label) moved \(stop.title)")
                    XCTAssertEqual(stop.departMin, planned.departMin, "\(c.name): \(option.label) moved \(stop.title)")
                }
            }
        }
    }

    func testRoundingIsJavaScripts() {
        XCTAssertEqual(js.round(2.5), 3)
        XCTAssertEqual(js.round(-2.5), -2)
        XCTAssertEqual(js.round(-2.6), -3)
        XCTAssertEqual(js.ceil(0.01), 1)
    }

    func testTiesBreakOnCodeUnits() {
        XCTAssertLessThan(js.compare("B", "a"), 0, "upper case sorts before lower, as in JavaScript")
        XCTAssertLessThan(js.compare("a-b", "a:b"), 0)
        XCTAssertEqual(js.compare("x", "x"), 0)
    }

    func testSortIsStable() {
        let items = [(1, "a"), (0, "b"), (1, "c"), (0, "d")]
        let sorted = js.sorted(items) { Double($0.0 - $1.0) }
        XCTAssertEqual(sorted.map(\.1), ["b", "d", "a", "c"])
    }

    func testOpeningHoursFallbackParses() {
        let hours = TripHours.parse("Mo-Fr 09:00-12:00,14:00-18:00; Sa 10:00-14:00")
        XCTAssertEqual(hours?["1"], [TripOpenRange(openMin: 540, closeMin: 720), TripOpenRange(openMin: 840, closeMin: 1080)])
        XCTAssertEqual(hours?["6"], [TripOpenRange(openMin: 600, closeMin: 840)])
        XCTAssertEqual(hours?["7"], [])
        XCTAssertNil(TripHours.parse("Jan-Mar Mo 09:00-12:00"))
        XCTAssertEqual(TripHours.parse("24/7")?["3"], [TripOpenRange(openMin: 0, closeMin: 1440)])
    }

    func testWeekdaysAreTheSolvers() {
        XCTAssertEqual(TripReplan.isoWeekday("2026-10-27"), 2) // a Tuesday
        XCTAssertEqual(TripReplan.dayLabel("2026-10-27"), "Tue 27 Oct")
        XCTAssertEqual(TripReplan.fmtMin(1450), "00:10")
    }
}
