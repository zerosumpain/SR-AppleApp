import XCTest
@testable import SRAppleApp

final class HealthCatalogueTests: XCTestCase {
    func testTheCatalogueIsBundledAndHasNineGroups() {
        XCTAssertEqual(Set(HealthCatalogue.file.groups.keys), Set(HealthCatalogue.groupOrder))
        XCTAssertEqual(HealthCatalogue.groupOrder.count, 9)
    }

    func testOldPerKindTogglesBecomeGroups() {
        XCTAssertEqual(HealthCatalogue.migrate(["steps", "heart_rate", "resting_heart_rate", "sleep", "workout"]),
                       ["activity", "heart", "sleep", "workouts"])
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
}
