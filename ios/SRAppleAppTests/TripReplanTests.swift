import XCTest
@testable import SRAppleApp

/// The phone's port of the trip solver (`Trips/TripReplan.swift`) against
/// SR-Main's own answers. `Fixtures/TripCases/*.json` are copied verbatim
/// from SR-Main `src/lib/trips/solver/fixtures/cases/` (feat/trips-solver,
/// c1100734): each holds the solver's input and the output the TypeScript
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

        var context: TripReplan.Context {
            TripReplan.Context(trip: trip, stays: stays, wishes: wishes, bookings: bookings, matrix: matrix)
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
        XCTAssertEqual(caseFiles().count, 11, "the eleven shared cases from SR-Main should all be in the test bundle")
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
