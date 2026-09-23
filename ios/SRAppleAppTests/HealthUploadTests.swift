import XCTest
import HealthKit
@testable import SRAppleApp

/// The queue rules: re-read buckets travel only when they change, a queued
/// bucket is replaced rather than duplicated, and a refused batch can never
/// hold the uploads behind it.
final class HealthUploadTests: XCTestCase {
    private func bucket(_ id: String, _ value: Double?, kind: String = "step_count") -> HealthRecord {
        HealthRecord(id: id, kind: kind, start: "2026-09-23T01:00:00Z", end: "2026-09-23T02:00:00Z", value: value, unit: "count", source: "HealthKit hourly statistics")
    }

    // MARK: I-1

    func testOnlyBucketsWhoseValueMovedAreQueuedAgain() {
        let first = HealthBatching.changed([bucket("a", 10), bucket("b", 20)], since: [:])
        XCTAssertEqual(first.changed.map(\.id), ["a", "b"], "nothing sent yet: everything goes")
        let again = HealthBatching.changed([bucket("a", 10), bucket("b", 25), bucket("c", 5)], since: first.sent)
        XCTAssertEqual(again.changed.map(\.id), ["b", "c"], "an unchanged bucket is not queued again")
        XCTAssertEqual(again.sent, ["a": 10, "b": 25, "c": 5])
        let idle = HealthBatching.changed([bucket("a", 10), bucket("b", 25), bucket("c", 5)], since: again.sent)
        XCTAssertTrue(idle.changed.isEmpty, "an idle wake queues nothing")
    }

    func testTheSentMapHoldsOnlyTheBucketsReadNow() {
        let old = ["2026-09-20T01": 3.0, "a": 10]
        let next = HealthBatching.changed([bucket("a", 10)], since: old)
        XCTAssertEqual(next.sent, ["a": 10], "a bucket outside the re-read window falls out")
        XCTAssertTrue(next.changed.isEmpty)
    }

    func testARecordWithoutAValueIsAlwaysSent() {
        XCTAssertEqual(HealthBatching.changed([bucket("a", nil)], since: [:]).changed.map(\.id), ["a"])
    }

    func testAQueuedBucketIsReplacedNotDuplicated() {
        let location = LocationRecord(recorded: "2026-09-23T01:00:00Z", latitude: 51.5, longitude: -0.1, accuracy: 5, speed: 0, moving: false)
        let queued = [UploadBatch(health: [bucket("a", 10), bucket("b", 20)]),
                      UploadBatch(health: [bucket("c", 1)]),
                      UploadBatch(locations: [location])]
        let next = HealthBatching.queue([bucket("a", 12), bucket("c", 2)], into: queued)
        let ids = next.flatMap { $0.health.map(\.id) }
        XCTAssertEqual(ids, ["b", "a", "c"], "the old copies go; the new ones are appended")
        XCTAssertEqual(next.flatMap(\.health).first { $0.id == "a" }?.value, 12)
        XCTAssertEqual(next.count, 3, "the batch left empty is removed; the location batch stays")
        XCTAssertEqual(next[1].locations.count, 1)
        XCTAssertEqual(HealthBatching.queue([], into: queued).count, 3, "nothing to add changes nothing")
    }

    @MainActor func testHourlySentPersistsAndOldStateDecodesWithoutIt() throws {
        XCTAssertEqual(try JSONDecoder().decode(PersistedState.self, from: Data("{}".utf8)).hourlySent, [:])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        let outbox = try Outbox(url: url)
        try outbox.change { $0.hourlySent["step_count"] = ["step_count-2026-09-23T14": 812] }
        XCTAssertEqual(try Outbox(url: url).state.hourlySent["step_count"], ["step_count-2026-09-23T14": 812])
    }

    // MARK: I-4

    func testOnly400And413AreRefusals() {
        XCTAssertTrue(HealthBatching.isRefusal(status: 400))
        XCTAssertTrue(HealthBatching.isRefusal(status: 413))
        for status in [0, 401, 409, 429, 500, 502, 503] {
            XCTAssertFalse(HealthBatching.isRefusal(status: status), "\(status) waits and retries")
        }
    }

    func testARefusedBatchIsHalvedUntilOnlyTheBadRecordIsDropped() {
        let records = (0..<400).map { bucket("h\($0)", Double($0)) }
        var queue = [UploadBatch(health: records)]
        var sent: [String] = [], dropped: [String] = [], requests = 0
        while let batch = queue.first {
            requests += 1
            XCTAssertLessThan(requests, 100, "halving must end")
            if requests >= 100 { break }
            if batch.health.contains(where: { $0.id == "h137" }) {
                let halves = HealthBatching.split(batch)
                if halves.isEmpty { dropped += batch.health.map(\.id) }
                queue.replaceSubrange(0...0, with: halves)
            } else {
                sent += batch.health.map(\.id)
                queue.removeFirst()
            }
        }
        XCTAssertEqual(dropped, ["h137"])
        XCTAssertEqual(sent, records.map(\.id).filter { $0 != "h137" }, "every other record goes, in order")
        XCTAssertLessThan(requests, 30)
    }

    func testSplitCoversHealthLocationsAndDeletions() {
        let location = LocationRecord(recorded: "2026-09-23T01:00:00Z", latitude: 51.5, longitude: -0.1, accuracy: 5, speed: 0, moving: false)
        let halves = HealthBatching.split(UploadBatch(health: [bucket("a", 1)], locations: [location], deleted: ["x", "y"]))
        XCTAssertEqual(halves.count, 2)
        XCTAssertEqual(halves[0].health.map(\.id), ["a"]); XCTAssertEqual(halves[0].locations.count, 1); XCTAssertEqual(halves[0].deleted, [])
        XCTAssertEqual(halves[1].health.count, 0); XCTAssertEqual(halves[1].locations.count, 0); XCTAssertEqual(halves[1].deleted, ["x", "y"])
        let odd = HealthBatching.split(UploadBatch(health: [bucket("a", 1)], deleted: ["x"]))
        XCTAssertEqual(odd.map { $0.health.count + $0.deleted.count }, [1, 1], "both halves non-empty")
        XCTAssertTrue(HealthBatching.split(UploadBatch(deleted: ["x"])).isEmpty, "a lone refused record is dropped")
        XCTAssertTrue(HealthBatching.split(UploadBatch()).isEmpty)
    }

    // MARK: Minors

    func testNonFiniteWorkoutFiguresAreCleared() throws {
        var w = HealthRecord(id: "W", kind: "workout", start: "2026-09-23T01:00:00Z", end: "2026-09-23T02:00:00Z", value: 3600, unit: "seconds", source: "Watch")
        w.distance = Double.nan; w.energy = 420; w.elevation = Double.infinity; w.mets = -Double.infinity
        w.temperature = 12; w.humidity = Double.nan; w.effort = Double.nan
        let clean = HealthBatching.finiteWorkoutFields(w)
        XCTAssertNil(clean.distance); XCTAssertNil(clean.elevation); XCTAssertNil(clean.mets)
        XCTAssertNil(clean.humidity); XCTAssertNil(clean.effort)
        XCTAssertEqual(clean.energy, 420); XCTAssertEqual(clean.temperature, 12)
        XCTAssertThrowsError(try JSONEncoder().encode(w), "why: a NaN makes the encoder throw")
        XCTAssertNoThrow(try JSONEncoder().encode(clean))
    }

    func testFailuresAreSummarisedWithAFullQueueFirst() {
        XCTAssertNil(HealthBatching.failureSummary([:]))
        XCTAssertEqual(HealthBatching.failureSummary(["vo2_max": "Authorization not determined"]),
                       "Could not read vo2_max from Apple Health: Authorization not determined")
        XCTAssertEqual(HealthBatching.failureSummary(["heart_rate": "x", "step_count": outboxFullMessage]), outboxFullMessage)
        XCTAssertEqual(HealthBatching.failureSummary(["b": "second", "a": "first"]), "Could not read 2 health kinds from Apple Health: first")
    }

    func testMoreWorkoutsGetApplesNames() {
        XCTAssertEqual(HealthReadings.name(for: .downhillSkiing, indoor: false), "Downhill Skiing")
        XCTAssertEqual(HealthReadings.name(for: .snowboarding, indoor: false), "Snowboarding")
        XCTAssertEqual(HealthReadings.name(for: .skatingSports, indoor: false), "Skating")
        XCTAssertEqual(HealthReadings.name(for: .sailing, indoor: false), "Sailing")
        XCTAssertEqual(HealthReadings.name(for: .wheelchairWalkPace, indoor: false), "Wheelchair Walk Pace")
        XCTAssertEqual(HealthReadings.name(for: .wheelchairRunPace, indoor: false), "Wheelchair Run Pace")
        XCTAssertEqual(HealthReadings.name(for: .swimming, indoor: false), "Pool Swim", "existing names unchanged")
        XCTAssertEqual(HealthReadings.name(for: .stairClimbing, indoor: false), "Stair Climbing")
    }
}
