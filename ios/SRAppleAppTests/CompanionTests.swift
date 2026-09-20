import XCTest
@testable import SRAppleApp

final class CompanionTests: XCTestCase {
    func testMovementCadenceAndStationaryReturn() {
        var policy = MovementPolicy()
        let start = Date(timeIntervalSince1970: 100000)
        XCTAssertTrue(policy.shouldRecord(at: start, speed: 0, distance: 0, accuracy: 10))
        XCTAssertFalse(policy.shouldRecord(at: start.addingTimeInterval(599), speed: 0, distance: 0, accuracy: 10))
        XCTAssertTrue(policy.shouldRecord(at: start.addingTimeInterval(600), speed: 0, distance: 0, accuracy: 10))
        XCTAssertTrue(policy.shouldRecord(at: start.addingTimeInterval(601), speed: 1, distance: 40, accuracy: 10))
        XCTAssertFalse(policy.shouldRecord(at: start.addingTimeInterval(620), speed: 1, distance: 40, accuracy: 10))
        XCTAssertTrue(policy.shouldRecord(at: start.addingTimeInterval(631), speed: 1, distance: 40, accuracy: 10))
        XCTAssertTrue(policy.shouldRecord(at: start.addingTimeInterval(811), speed: 0, distance: 0, accuracy: 10))
        XCTAssertFalse(policy.moving)
    }
    func testPoorAccuracyNeverCreatesPoint() {
        var policy = MovementPolicy()
        XCTAssertFalse(policy.shouldRecord(at: Date(), speed: 2, distance: 500, accuracy: 200))
        XCTAssertFalse(policy.moving)
    }
    @MainActor func testSecureServerURL() throws {
        XCTAssertThrowsError(try API.validateURL("http://example.com"))
        XCTAssertThrowsError(try API.validateURL("https://user:password@example.com"))
        XCTAssertThrowsError(try API.validateURL("https://example.com/wrong-path"))
        XCTAssertEqual(try API.validateURL("https://example.com").host, "example.com")
    }
    @MainActor func testOutboxSurvivesRestartWithAnchor() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        let first = try Outbox(url: url)
        try first.change {
            $0.batches.append(UploadBatch(deleted: ["removed-sample"]))
            $0.anchors["sleep"] = Data([1, 2, 3])
        }
        let second = try Outbox(url: url)
        XCTAssertEqual(second.state.batches[0].deleted, ["removed-sample"])
        XCTAssertEqual(second.state.anchors["sleep"], Data([1, 2, 3]))
    }
    @MainActor func testCorruptQueueIsNotSilentlyDiscarded() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        try Data("invalid".utf8).write(to: url)
        XCTAssertThrowsError(try Outbox(url: url))
    }
}
