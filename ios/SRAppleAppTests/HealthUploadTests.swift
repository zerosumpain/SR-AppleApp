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

    /// One flush, applying `UploadRound` the way `Companion.flush` does.
    /// `refuse` answers a batch with the server's reason, or nil to accept it.
    private func flush(_ queue: inout [UploadBatch], refuse: (UploadBatch) -> String?) -> (sent: [String], dropped: [String], stopped: Bool) {
        func ids(_ b: UploadBatch) -> [String] { b.health.map(\.id) + b.deleted }
        var round = UploadRound(), sent: [String] = [], dropped: [String] = [], requests = 0
        while let batch = round.next(in: queue) {
            requests += 1
            if requests > 1000 { XCTFail("a flush must end"); break }
            if let reason = refuse(batch) {
                switch round.refused(batch, reason: reason) {
                case .split:
                    let index = queue.firstIndex(where: { $0.id == batch.id })!
                    queue.replaceSubrange(index...index, with: HealthBatching.split(batch))
                case .drop:
                    dropped += ids(batch); queue.removeAll { $0.id == batch.id }
                case .hold:
                    break
                case .stop:
                    return (sent, dropped, true)
                }
            } else {
                sent += ids(batch); queue.removeAll { $0.id == batch.id }
                let evidenced = round.accepted()
                dropped += queue.filter { evidenced.contains($0.id) }.flatMap { ids($0) }
                queue.removeAll { evidenced.contains($0.id) }
            }
        }
        return (sent, dropped, false)
    }

    private func count(_ queue: [UploadBatch]) -> Int { queue.reduce(0) { $0 + $1.health.count + $1.locations.count + $1.deleted.count } }

    func testASystemicRefusalKeepsEverything() {
        // Catalogue ahead of the server: it refuses everything.
        let plain = (0..<400).map { bucket("h\($0)", Double($0)) }
        var queue = [UploadBatch(health: plain), UploadBatch(health: [bucket("route:W:0", nil, kind: "workout_route")]), UploadBatch(deleted: ["gone"])]
        for _ in 0..<20 {
            let result = flush(&queue) { _ in "Unknown health category" }
            XCTAssertTrue(result.dropped.isEmpty, "nothing is dropped while the server accepts nothing")
            XCTAssertTrue(result.sent.isEmpty)
        }
        XCTAssertEqual(count(queue), 402, "every record, the chunk and the deletion are all still queued")
        XCTAssertTrue(queue.contains { $0.deleted == ["gone"] })
    }

    func testALoneRecordIsDroppedOnlyOnceTheServerAcceptsAnother() {
        let bad: (UploadBatch) -> String? = { $0.health.contains { $0.id == "bad" } ? "Invalid heart_rate" : nil }
        var alone = [UploadBatch(health: [bucket("bad", 1)])]
        let first = flush(&alone, refuse: bad)
        XCTAssertTrue(first.dropped.isEmpty, "the first refusal of a flush proves nothing")
        XCTAssertFalse(first.stopped)
        XCTAssertEqual(count(alone), 1, "kept for the next flush")

        var queue = [UploadBatch(health: [bucket("bad", 1)]), UploadBatch(health: [bucket("good", 2)])]
        let second = flush(&queue, refuse: bad)
        XCTAssertEqual(second.sent, ["good"], "a held record does not block the batches behind it")
        XCTAssertEqual(second.dropped, ["bad"], "dropped once the server accepted another in the same flush")
        XCTAssertTrue(queue.isEmpty)
    }

    func testABadRecordIsIsolatedAcrossFlushesWithoutLosingOthers() {
        for badIndex in [0, 137, 399] {
            let records = (0..<400).map { bucket("h\($0)", Double($0)) }
            let badID = "h\(badIndex)"
            var queue = [UploadBatch(health: records)], sent: [String] = [], dropped: [String] = [], flushes = 0
            while !queue.isEmpty && flushes < 12 {
                flushes += 1
                let result = flush(&queue) { $0.health.contains { $0.id == badID } ? "Invalid step_count" : nil }
                sent += result.sent; dropped += result.dropped
            }
            XCTAssertTrue(queue.isEmpty, "bad record at \(badIndex): the queue drains")
            XCTAssertEqual(dropped, [badID])
            XCTAssertEqual(sent, records.map(\.id).filter { $0 != badID }, "every other record goes, in order")
        }
    }

    func testTheBreakerTripsAtThreeRefusalsInARow() {
        let two = UploadBatch(health: [bucket("a", 1), bucket("b", 2)])
        var round = UploadRound()
        XCTAssertEqual(round.refused(two, reason: "Invalid step_count"), .split)
        XCTAssertEqual(round.refused(two, reason: "Invalid step_count"), .split)
        XCTAssertEqual(round.refused(two, reason: "Invalid step_count"), .stop)
        var reset = UploadRound()
        _ = reset.refused(two, reason: "Invalid step_count"); _ = reset.refused(two, reason: "Invalid step_count")
        _ = reset.accepted()
        XCTAssertEqual(reset.refused(two, reason: "Invalid step_count"), .split, "an acceptance resets the count")
    }

    func testInvalidJSONAndAProxysPageNeverDrop() {
        var round = UploadRound()
        _ = round.accepted()
        XCTAssertEqual(round.refused(UploadBatch(health: [bucket("a", 1)]), reason: HealthBatching.invalidJSON), .stop)
        var proxied = UploadRound()
        _ = proxied.accepted()
        XCTAssertEqual(proxied.refused(UploadBatch(health: [bucket("a", 1)]), reason: uploadFallbackMessage), .stop)
        var merit = UploadRound()
        _ = merit.accepted()
        XCTAssertEqual(merit.refused(UploadBatch(health: [bucket("a", 1)]), reason: "Invalid step_count"), .drop)
    }

    func testADeletionIsNeverDropped() {
        var round = UploadRound()
        _ = round.accepted()
        let deletion = UploadBatch(deleted: ["x"])
        XCTAssertEqual(round.refused(deletion, reason: "Invalid deletion IDs"), .hold)
        XCTAssertTrue(round.accepted().isEmpty, "a held deletion never becomes droppable")
        XCTAssertNil(round.next(in: [deletion]), "held for this flush only; the queue keeps it")
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
