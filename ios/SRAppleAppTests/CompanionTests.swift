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
    @MainActor func testOutboxSurvivesRestartWithAnchor() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        let first = try Outbox(url: url)
        try await first.change {
            $0.batches.append(UploadBatch(deleted: ["removed-sample"]))
            $0.anchors["sleep"] = Data([1, 2, 3])
        }
        let second = try Outbox(url: url)
        XCTAssertEqual(second.state.batches[0].deleted, ["removed-sample"])
        XCTAssertEqual(second.state.anchors["sleep"], Data([1, 2, 3]))
    }
    // MARK: Sync progress and pause (stale-error / outbox-rewrite fix)

    func testRetryDelayChoosesFiveSecondsOnlyAfterProgress() {
        XCTAssertEqual(retryDelay(madeProgress: true, transient: true), 5)
        XCTAssertEqual(retryDelay(madeProgress: false, transient: true), 60)
        XCTAssertEqual(retryDelay(madeProgress: true, transient: false), 60, "a refusal or breaker trip must not be retried fast")
    }
    func testTransientNetworkFailuresReadAsPausedNotStale() {
        let transient: [URLError.Code] = [
            .timedOut, .networkConnectionLost, .notConnectedToInternet, .cancelled,
            .cannotConnectToHost, .dnsLookupFailed, .backgroundSessionWasDisconnected,
            .internationalRoamingOff, .dataNotAllowed,
        ]
        for code in transient {
            XCTAssertTrue(isTransientUploadFailure(URLError(code)), "\(code) should read as transient")
        }
        XCTAssertFalse(isTransientUploadFailure(URLError(.badServerResponse)), "a real server response is not a network blip")
        XCTAssertFalse(isTransientUploadFailure(CompanionError.message("refused")), "a non-network error never reads as transient")
    }
    @MainActor func testEveryOutboxChangeIsDurableAndKeepsBatchIdentity() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        let outbox = try await Outbox.open(url: url)
        let batch = UploadBatch(deleted: ["accepted"])
        try await outbox.change(persist: false) { $0.batches.append(batch); $0.anchors["sleep"] = Data([9]) }
        let reopened = try await Outbox.open(url: url)
        XCTAssertEqual(reopened.state.batches.first?.id, batch.id)
        XCTAssertEqual(reopened.state.batches.first?.deleted, ["accepted"])
        XCTAssertEqual(reopened.state.anchors["sleep"], Data([9]))
        try await outbox.change { $0.batches.removeAll() }
        XCTAssertTrue(try Outbox(url: url).state.batches.isEmpty)
    }

    @MainActor func testConcurrentOutboxMutationsDoNotLoseEarlierWrites() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        let outbox = try await Outbox.open(url: url)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<20 {
                group.addTask { try await outbox.change { $0.batches.append(UploadBatch(deleted: ["\(index)"])) } }
            }
            try await group.waitForAll()
        }
        let saved = try await Outbox.open(url: url)
        XCTAssertEqual(saved.state.batches.count, 20)
        XCTAssertEqual(Set(saved.state.batches.flatMap(\.deleted)).count, 20)
    }

    @MainActor func testCorruptQueueIsNotSilentlyDiscarded() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        try Data("invalid".utf8).write(to: url)
        XCTAssertThrowsError(try Outbox(url: url))
    }
    @MainActor func testPairingQRValidation() throws {
        let code = String(repeating: "a", count: 43)
        func payload(_ server: String = "https://strangeramblings.com", version: Int = 1, token: String? = nil) throws -> String {
            let object: [String: Any] = ["type": "sr-companion-pair", "version": version, "server": server, "code": token ?? code]
            return String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
        }
        XCTAssertEqual(try PairingPayload.parse(payload()).code, code)
        for server in ["http://example.com", "https://user:pass@example.com", "https://example.com/path", "https://example.com?token=bad"] {
            XCTAssertThrowsError(try PairingPayload.parse(payload(server)))
        }
        XCTAssertThrowsError(try PairingPayload.parse(payload(version: 2)))
        XCTAssertThrowsError(try PairingPayload.parse(payload(token: "short")))
        XCTAssertThrowsError(try PairingPayload.parse("https://example.com"))
        XCTAssertThrowsError(try PairingPayload.parse(String(repeating: "x", count: 2049)))
    }

}
