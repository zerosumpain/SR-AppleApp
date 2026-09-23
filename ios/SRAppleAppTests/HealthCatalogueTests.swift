import XCTest
import HealthKit
@testable import SRAppleApp

final class HealthCatalogueTests: XCTestCase {
    func testTheCatalogueIsBundledAndHasNineGroups() {
        XCTAssertEqual(Set(HealthCatalogue.file.groups.keys), Set(HealthCatalogue.groupOrder))
        XCTAssertEqual(HealthCatalogue.groupOrder.count, 9)
    }

    func testOldPerKindTogglesBecomeGroups() {
        XCTAssertEqual(HealthCatalogue.migrate(["steps", "heart_rate", "resting_heart_rate", "sleep", "workout"]),
                       ["activity", "heart", "workouts", "sleep"])
        XCTAssertEqual(HealthCatalogue.migrate(["heart", "vitals"]), ["heart", "vitals"], "already-migrated state is left alone")
        XCTAssertEqual(HealthCatalogue.migrate([]), [])
    }

    func testBoundsComeFromTheCatalogue() {
        let base = HealthRecord(id: "x", kind: "oxygen_saturation", start: "2026-09-23T01:00:00Z", end: "2026-09-23T01:00:00Z", value: 97, unit: "%", source: "Watch")
        XCTAssertTrue(HealthCatalogue.accepts(base))
        var fraction = base; fraction.value = 0.97
        XCTAssertFalse(HealthCatalogue.accepts(fraction), "a 0–1 fraction must never be sent as a percentage")
        var wrongUnit = base; wrongUnit.unit = "bpm"
        XCTAssertFalse(HealthCatalogue.accepts(wrongUnit))
        var unknown = base; unknown.kind = "blood_glucose"
        XCTAssertFalse(HealthCatalogue.accepts(unknown))
    }

    func testEveryCatalogueKindHasAReading() {
        for kind in HealthCatalogue.file.kinds.keys {
            XCTAssertNotNil(HealthReadings.reading(for: kind), "no HealthKit reading for \(kind)")
        }
    }

    func testEverySeriesMetricTheWorkoutPassSendsIsCatalogued() {
        for s in HealthReadings.workoutSeries {
            XCTAssertNotNil(HealthCatalogue.file.series[s.metric], s.metric)
        }
    }

    func testWorkoutNamesMatchWhatTheWebhookStored() {
        // /health already holds 2,312 workouts named by Health Auto Export; the
        // switch rewrites the last 30 days of them, so the names must not change.
        XCTAssertEqual(HealthReadings.name(for: .walking, indoor: false), "Outdoor Walk")
        XCTAssertEqual(HealthReadings.name(for: .running, indoor: true), "Indoor Run")
        XCTAssertEqual(HealthReadings.name(for: .cycling, indoor: false), "Outdoor Cycling")
        XCTAssertEqual(HealthReadings.name(for: .highIntensityIntervalTraining, indoor: false), "High Intensity Interval Training")
        XCTAssertEqual(HealthReadings.name(for: .archery, indoor: false), "Other")
    }

    func testRoutesAreChunkedByTwoThousandWithStableIds() {
        let t0 = 1_758_600_000.0
        let points: [[Double?]] = (0..<4500).map { [t0 + Double($0), 51.5, -0.1, nil, 3, 5] }
        let chunks = HealthBatching.chunks(kind: "workout_route", workout: "W1", metric: nil, unit: nil, points: points, source: "Watch", size: 2000)
        XCTAssertEqual(chunks.map(\.id), ["route:W1:0", "route:W1:1", "route:W1:2"])
        XCTAssertEqual(chunks.map { $0.points?.count }, [2000, 2000, 500])
        XCTAssertEqual(chunks[1].start, timestamp(Date(timeIntervalSince1970: t0 + 2000)))
    }

    func testChunksTravelAloneAndPlainRecordsTravelInFourHundreds() {
        let plain = (0..<900).map { HealthRecord(id: "h\($0)", kind: "heart_rate", start: "2026-09-23T01:00:00Z", end: "2026-09-23T01:00:00Z", value: 60, unit: "bpm", source: "W") }
        let chunk = HealthBatching.chunks(kind: "workout_series", workout: "W1", metric: "power", unit: "W", points: [[1_758_600_000, 250]], source: "W", size: 5000)
        let batches = HealthBatching.batches(plain + chunk)
        XCTAssertEqual(batches.map(\.health.count), [400, 400, 100, 1])
    }

    func testVo2UnitIsBuiltNotParsed() {
        XCTAssertTrue(HKQuantityType.quantityType(forIdentifier: .vo2Max)!.is(compatibleWith: HealthReadings.vo2Unit))
        XCTAssertEqual(HKQuantity(unit: HealthReadings.vo2Unit, doubleValue: 45).doubleValue(for: HealthReadings.vo2Unit), 45)
    }
    func testFreshStateStartsAtTheCurrentCatalogueVersion() throws {
        XCTAssertEqual(PersistedState().catalogueVersion, PersistedState.currentCatalogueVersion)
        XCTAssertEqual(try JSONDecoder().decode(PersistedState.self, from: Data("{}".utf8)).catalogueVersion, 0,
                       "a state file from before the catalogue must still migrate")
    }

    @MainActor func testRePairingDoesNotRerunTheMigration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = try Outbox(url: directory.appendingPathComponent("state.json"))
        try outbox.clear()
        XCTAssertEqual(outbox.state.catalogueVersion, PersistedState.currentCatalogueVersion)
    }

    func testARecordEndingInTheFutureIsRefused() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var r = HealthRecord(id: "x", kind: "heart_rate", start: timestamp(now), end: timestamp(now.addingTimeInterval(240)), value: 60, unit: "bpm", source: "Watch")
        XCTAssertTrue(HealthCatalogue.accepts(r, now: now), "under five minutes ahead is clock skew, and the server allows it")
        r.end = timestamp(now.addingTimeInterval(360))
        XCTAssertFalse(HealthCatalogue.accepts(r, now: now))
        r.end = timestamp(now.addingTimeInterval(-60))
        XCTAssertFalse(HealthCatalogue.accepts(r, now: now), "an end before the start is refused too")
    }

    func testRoutePointsKeepToTheServersBounds() {
        let ok = HealthBatching.routePoint(epoch: 1_790_000_000.4, latitude: 51.5, longitude: -0.1, altitude: 30, speed: 3, accuracy: 5)
        XCTAssertEqual(ok, [1_790_000_000, 51.5, -0.1, 30, 3, 5])
        let wild = HealthBatching.routePoint(epoch: 1_790_000_000, latitude: 51.5, longitude: -0.1, altitude: 12_000, speed: 500, accuracy: 20_000)
        XCTAssertEqual(wild, [1_790_000_000, 51.5, -0.1, nil, nil, nil], "a wild altitude, speed or accuracy is dropped, not the point")
        XCTAssertNil(HealthBatching.routePoint(epoch: 1_790_000_000, latitude: 91, longitude: 0, altitude: nil, speed: nil, accuracy: nil))
        XCTAssertNil(HealthBatching.routePoint(epoch: 1_790_000_000, latitude: 0, longitude: .nan, altitude: nil, speed: nil, accuracy: nil))
        XCTAssertNil(HealthBatching.seriesPoint(epoch: 1_790_000_000, value: .infinity))
        XCTAssertNil(HealthBatching.seriesPoint(epoch: 1_790_000_000, value: 2e6))
        XCTAssertEqual(HealthBatching.seriesPoint(epoch: 1_790_000_000, value: 142), [1_790_000_000, 142])
    }
}
