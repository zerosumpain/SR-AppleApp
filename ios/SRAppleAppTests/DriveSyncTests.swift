import XCTest
@testable import SRAppleApp

/// Photo sync's rules (`DriveSyncLogic.swift`). What these hold: "in Drive"
/// is only what Drive proved it holds, nothing refused is sent again, the
/// window stays small, and the screen never says "up to date" while
/// anything is still to go.
final class DriveSyncTests: XCTestCase {

    private func job(_ id: String, asset: String?, state: DriveUploadJob.State, attempts: Int = 1) -> DriveUploadJob {
        var j = DriveUploadJob(id: id, space: .mine, folder: "", filename: "IMG_\(id).HEIC", mimeType: "image/heic",
                               sizeBytes: 10, sha256: String(repeating: "a", count: 64), takenAt: nil, staged: "\(id).heic",
                               assetId: asset, createdAt: Date(timeIntervalSince1970: 0))
        j.state = state
        j.attempts = attempts
        return j
    }

    // MARK: - The window

    func testOnlySyncsOwnLiveJobsFillTheWindow() {
        let jobs = [
            job("1", asset: "A", state: .sending),
            job("2", asset: "B", state: .waiting),
            job("3", asset: nil, state: .sending), // a picked file, not sync's
            job("4", asset: "C", state: .failed("busy"), attempts: 1), // retries itself
            job("5", asset: "D", state: .failed("busy"), attempts: 3), // given up: Try again's
            job("6", asset: "E", state: .stored(fileId: "f", duplicate: false, safe: true)),
        ]
        XCTAssertEqual(DriveSync.inFlight(jobs).map(\.id), ["1", "2", "4"])
        XCTAssertEqual(DriveSync.room(jobs), DriveSync.window - 3)
        // Off screen the line is longer, so each wake leaves more to send.
        XCTAssertEqual(DriveSync.room(jobs, window: DriveSync.windowSize(onScreen: false)), DriveSync.backgroundWindow - 3)
        XCTAssertEqual(DriveSync.windowSize(onScreen: true), DriveSync.window)
        XCTAssertGreaterThan(DriveSync.backgroundWindow, DriveSync.window)
        XCTAssertLessThan(DriveSync.wakeBudget, 30)
    }

    func testAGivenUpFailureIsNotSentAgainBySyncButARefusalIsNotQueued() {
        let jobs = [
            job("1", asset: "A", state: .failed("busy"), attempts: 3),
            job("2", asset: "B", state: .refused("Too big")),
            job("3", asset: "C", state: .stored(fileId: "f", duplicate: true, safe: true)),
        ]
        XCTAssertEqual(DriveSync.queued(jobs), ["A"])
        XCTAssertEqual(DriveSync.refusals(jobs), ["B": "Too big"])
    }

    // MARK: - What goes next

    func testNextTakesTheNewestUnknownInOrder() {
        let library = ["n1", "n2", "n3", "n4", "n5"]
        XCTAssertEqual(DriveSync.next(library: library, known: ["n1", "n3"], later: ["n4"], limit: 2), ["n2", "n5"])
        XCTAssertEqual(DriveSync.next(library: library, known: [], later: [], limit: 0), [])
    }

    func testTheComparisonAddsUp() {
        let counts = DriveSync.counts(library: ["a", "b", "c", "d", "e"], inDrive: ["a", "b", "gone-from-phone"],
                                      sending: ["c"], skipped: ["d"])
        XCTAssertEqual(counts, DriveSyncCounts(library: 5, inDrive: 2, sending: 1, skipped: 1))
        XCTAssertEqual(counts.notYet, 1)
    }

    // MARK: - What the screen says

    func testNeverUpToDateWhileAnythingIsLeft() {
        let done = DriveSyncCounts(library: 3, inDrive: 3)
        XCTAssertEqual(DriveSync.status(pause: .none, counts: done, working: nil), "Up to date. Everything here is in Drive.")
        XCTAssertEqual(DriveSync.status(pause: .none, counts: DriveSyncCounts(library: 3, inDrive: 2, sending: 1), working: nil),
                       "Sending the last 1")
        XCTAssertEqual(DriveSync.status(pause: .none, counts: DriveSyncCounts(library: 9, inDrive: 2, sending: 2), working: nil),
                       "Sending 2 · 5 to go")
        XCTAssertEqual(DriveSync.status(pause: .cellular, counts: done, working: "Checking Drive…"), "Waiting for Wi-Fi.")
    }

    func testThePauseOrder() {
        func pause(on: Bool = true, paired: Bool = true, access: Bool = true, wifiOnly: Bool = true,
                   expensive: Bool = false, constrained: Bool = false, lowPower: Bool = false) -> DriveSyncPause {
            DriveSyncPause.of(on: on, demo: false, paired: paired, viewingAs: false, access: access, wifiOnly: wifiOnly,
                              expensive: expensive, constrained: constrained, lowPower: lowPower)
        }
        XCTAssertEqual(pause(on: false, paired: false), .off)
        XCTAssertEqual(pause(paired: false), .unpaired)
        XCTAssertEqual(pause(access: false), .noAccess)
        XCTAssertEqual(pause(expensive: true), .cellular)
        XCTAssertEqual(pause(wifiOnly: false, expensive: true), .none)
        XCTAssertEqual(pause(expensive: true, constrained: true), .lowData)
        XCTAssertEqual(pause(lowPower: true), .lowPower)
        XCTAssertEqual(pause(), .none)
    }

    // MARK: - Drive's answer

    func testOnlyASameSizeHitCountsAsInDrive() throws {
        let sha = String(repeating: "b", count: 64)
        let body = """
        {"have":[{"sha256":"\(sha)","file":{"id":"f1","name":"Photo.heic","path":"Incoming photos/Photo.heic","mimeType":"image/heic","sizeBytes":10,"createdAt":"x","updatedAt":"x","mine":true,"addedBy":null,"canDelete":true}}],"unchecked":4}
        """
        let reply = try JSONDecoder().decode(DriveHaveReply.self, from: Data(body.utf8))
        XCTAssertEqual(reply.file(sha256: sha.uppercased(), size: 10)?.id, "f1")
        XCTAssertNil(reply.file(sha256: sha, size: 11))
        XCTAssertEqual(reply.unchecked, 4)
    }

    func testAKnownPhotoIsWrittenDownOnceAndIsRemovable() {
        var ledger = DriveMoveLedger()
        ledger = ledger.recordingKnown(assetId: "A", fileId: "f1", space: .mine)
        ledger = ledger.recordingKnown(assetId: "A", fileId: "f2", space: .mine)
        ledger = ledger.recordingKnown(assetId: "", fileId: "f3", space: .mine)
        XCTAssertEqual(ledger.entries.map(\.fileId), ["f1"])
        XCTAssertEqual(ledger.removable.map(\.assetId), ["A"])
        XCTAssertEqual(ledger.assetIds, ["A"])
    }

    func testSettingsStartOffAndKeep() {
        let defaults = UserDefaults(suiteName: "drive-sync-test-\(UUID().uuidString)")!
        XCTAssertFalse(DriveSyncSettings.load(defaults).on)
        var s = DriveSyncSettings()
        s.on = true
        s.videos = false
        s.save(defaults)
        XCTAssertEqual(DriveSyncSettings.load(defaults), s)
    }
}
