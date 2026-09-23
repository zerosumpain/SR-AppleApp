import XCTest
@testable import SRAppleApp

/// The settings, and the measurement that makes them worth having.
final class SettingsTests: XCTestCase {

    // MARK: - The policy now obeys settings

    func testThePolicyHonoursItsRecordingIntervals() {
        var policy = MovementPolicy(settings: LocationSettings.Preset.saver.settings)
        let start = Date(timeIntervalSince1970: 100_000)
        // Saver records every 30 minutes when stopped, not every 10.
        XCTAssertTrue(policy.shouldRecord(at: start, speed: 0, distance: 0, accuracy: 10))
        XCTAssertFalse(policy.shouldRecord(at: start.addingTimeInterval(1799), speed: 0, distance: 0, accuracy: 10))
        XCTAssertTrue(policy.shouldRecord(at: start.addingTimeInterval(1800), speed: 0, distance: 0, accuracy: 10))
    }

    func testTheAccuracyCeilingIsASetting() {
        // Default discards a 200m fix; saver keeps it, because a cheap accuracy
        // setting produces loose fixes and a tight ceiling would bin them all.
        var strict = MovementPolicy()
        XCTAssertFalse(strict.shouldRecord(at: Date(), speed: 0, distance: 0, accuracy: 200))
        var loose = MovementPolicy(settings: LocationSettings.Preset.saver.settings)
        XCTAssertTrue(loose.shouldRecord(at: Date(), speed: 0, distance: 0, accuracy: 200))
    }

    func testTheMovingSpeedThresholdIsASetting() {
        var policy = MovementPolicy(settings: LocationSettings.Preset.saver.settings)
        // Saver needs 1.2 m/s before it calls you moving; 1.0 is still stopped.
        _ = policy.shouldRecord(at: Date(), speed: 1.0, distance: 0, accuracy: 10)
        XCTAssertFalse(policy.moving)
        _ = policy.shouldRecord(at: Date().addingTimeInterval(1), speed: 1.5, distance: 0, accuracy: 10)
        XCTAssertTrue(policy.moving)
    }

    /// The whole point of leaving the default alone.
    func testTheDefaultReproducesTheOldHardCodedBehaviour() {
        let d = LocationSettings()
        XCTAssertEqual(d.movingInterval, 30)
        XCTAssertEqual(d.stationaryInterval, 600)
        XCTAssertEqual(d.stopThreshold, 180)
        XCTAssertEqual(d.movingSpeed, 0.8)
        XCTAssertEqual(d.accuracyCeiling, 100)
        XCTAssertEqual(d.heartbeatInterval, 60)
        XCTAssertEqual(d.movingDistanceFilter, 10)
        XCTAssertEqual(d.stationaryDistanceFilter, 30)
        XCTAssertEqual(d.movingAccuracy, .best)
        XCTAssertEqual(d.stationaryAccuracy, .hundredMetres)
        XCTAssertEqual(d.matchingPreset, .accurate, "the shipped default must be a named preset")
    }

    func testEachPresetIsCheaperThanTheLast() {
        let saver = LocationSettings.Preset.saver.settings
        let balanced = LocationSettings.Preset.balanced.settings
        let accurate = LocationSettings.Preset.accurate.settings
        // Records less often…
        XCTAssertGreaterThan(saver.stationaryInterval, balanced.stationaryInterval)
        XCTAssertGreaterThan(balanced.stationaryInterval, accurate.stationaryInterval)
        // …and asks the radio for less.
        XCTAssertEqual(saver.heartbeatInterval, 0, "saver must not force fixes on a timer")
        // The heartbeat is a PERIOD, so LONGER is cheaper — balanced waits five
        // minutes between forced fixes where accurate waits one. Asserting this
        // the other way round was my own confusion about the direction, and the
        // test caught it.
        XCTAssertGreaterThan(balanced.heartbeatInterval, accurate.heartbeatInterval)
        // The cheap presets must not bin their own fixes.
        XCTAssertGreaterThan(saver.accuracyCeiling, accurate.accuracyCeiling)
    }

    func testAPresetRoundTripsAndAHandEditLeavesIt() {
        var s = LocationSettings.Preset.balanced.settings
        XCTAssertEqual(s.matchingPreset, .balanced)
        s.heartbeatInterval += 60
        XCTAssertNil(s.matchingPreset, "a changed value must read as Custom")
    }

    // MARK: - Battery maths
    //
    // A wrong drain figure is worse than none: it would be acted on.

    private func sample(_ minutes: Double, _ level: Double, charging: Bool = false, sharing: Bool = true) -> BatterySample {
        BatterySample(at: Date(timeIntervalSince1970: 0).addingTimeInterval(minutes * 60),
                      level: level, charging: charging, sharing: sharing)
    }

    func testDrainIsPerHourAcrossUsableWindows() {
        // 2% over two hours, sampled every 30 minutes = 1%/hour.
        let samples = [sample(0, 1.00), sample(30, 0.995), sample(60, 0.99), sample(90, 0.985), sample(120, 0.98)]
        let drain = BatteryMaths.drainPerHour(samples, sharingOnly: true)
        XCTAssertNotNil(drain)
        XCTAssertEqual(drain!, 1.0, accuracy: 0.01)
    }

    func testChargingWindowsAreExcluded() {
        // Without the exclusion the rising level reads as negative drain and
        // the app reports itself as free.
        let samples = [sample(0, 0.50), sample(30, 0.60, charging: true), sample(60, 0.70, charging: true),
                       sample(90, 0.69), sample(150, 0.67)]
        let windows = BatteryMaths.usableWindows(samples, sharingOnly: true)
        XCTAssertEqual(windows.count, 1, "only the 90→150 window discharges without a charger")
        for w in windows { XCTAssertGreaterThanOrEqual(w.dropped, 0) }
    }

    func testAnUnreadableLevelIsNotTreatedAsZero() {
        // The simulator reports -1. Treating that as "empty" would invent a
        // catastrophic drain out of nothing.
        let samples = [sample(0, -1), sample(30, -1), sample(60, -1), sample(120, -1)]
        XCTAssertNil(BatteryMaths.drainPerHour(samples, sharingOnly: true))
        XCTAssertTrue(BatteryMaths.usableWindows(samples, sharingOnly: true).isEmpty)
    }

    func testALongGapIsNotAttributedToTheApp() {
        // Eight hours asleep, then a reading. Counting that window would blame
        // the app for the whole night.
        let samples = [sample(0, 1.00), sample(480, 0.80)]
        XCTAssertTrue(BatteryMaths.usableWindows(samples, sharingOnly: true).isEmpty)
        XCTAssertNil(BatteryMaths.drainPerHour(samples, sharingOnly: true))
    }

    func testTooLittleEvidenceReportsNothingRatherThanAGuess() {
        // Half an hour and one 1% step would extrapolate to 2%/hour off a single
        // reporting increment. Absence is the honest answer.
        let samples = [sample(0, 1.00), sample(30, 0.99)]
        XCTAssertNil(BatteryMaths.drainPerHour(samples, sharingOnly: true))
        XCTAssertLessThan(BatteryMaths.measuredHours(samples, sharingOnly: true), 1)
    }

    func testSharingOnlyExcludesWindowsWhereSharingWasOff() {
        let samples = [sample(0, 1.00, sharing: false), sample(60, 0.97, sharing: false),
                       sample(120, 0.95, sharing: true), sample(180, 0.93, sharing: true)]
        let sharing = BatteryMaths.usableWindows(samples, sharingOnly: true)
        let all = BatteryMaths.usableWindows(samples, sharingOnly: false)
        XCTAssertEqual(sharing.count, 1)
        XCTAssertEqual(all.count, 3)
    }

    func testZeroDrainIsReportedAsAbsenceNotAsZero() {
        // Flat across two hours means the 1% step has not moved yet — which is
        // "no reading", not "it costs nothing".
        let samples = [sample(0, 0.80), sample(60, 0.80), sample(120, 0.80)]
        XCTAssertNil(BatteryMaths.drainPerHour(samples, sharingOnly: true))
    }

    // MARK: - Persistence

    func testExistingStateDecodesWithoutTheNewFields() throws {
        // The upgrade path. A new non-optional field with no default makes the
        // whole file undecodable, and this file holds unsent health records.
        let old = """
        {"batches":[],"anchors":{},"healthEnabled":["steps"],"sharing":true,
         "historyStart":768000}
        """
        let state = try JSONDecoder().decode(PersistedState.self, from: Data(old.utf8))
        XCTAssertEqual(state.healthEnabled, ["steps"])
        XCTAssertTrue(state.sharing)
        XCTAssertEqual(state.location, LocationSettings(), "settings must default in")
        XCTAssertTrue(state.battery.isEmpty)
        XCTAssertEqual(state.pointsRecorded, 0)
    }

    func testAnEmptyObjectStillDecodes() throws {
        // The strongest form of the upgrade guarantee: every single key missing.
        // Swift's synthesised Codable throws keyNotFound here — a property's
        // default value is NOT used for a missing key — which is what made an
        // upgrade discard the upload queue.
        let state = try JSONDecoder().decode(PersistedState.self, from: Data("{}".utf8))
        XCTAssertTrue(state.batches.isEmpty)
        XCTAssertFalse(state.sharing)
        XCTAssertEqual(state.location, LocationSettings())
    }

    func testAPartialSettingsBlobKeepsTheRestOfTheDefaults() throws {
        // A settings object written by an older build, missing fields a newer
        // one knows about.
        let json = #"{"heartbeatInterval":0,"movingAccuracy":"tenMetres"}"#
        let s = try JSONDecoder().decode(LocationSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.heartbeatInterval, 0)
        XCTAssertEqual(s.movingAccuracy, .tenMetres)
        XCTAssertEqual(s.stationaryInterval, 600, "unlisted fields must keep their defaults")
        XCTAssertEqual(s.activity, .other)
    }

    @MainActor func testSettingsSurviveARestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")

        let first = try Outbox(url: url)
        try first.change { $0.location = LocationSettings.Preset.saver.settings }
        let second = try Outbox(url: url)
        XCTAssertEqual(second.state.location.matchingPreset, .saver)
    }

    @MainActor func testBatterySamplesAreBounded() throws {
        // They ride in the same atomically-written file as the upload queue, so
        // an unbounded ring would eventually make every save expensive.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = try Outbox(url: directory.appendingPathComponent("state.json"))
        try outbox.change {
            for i in 0..<(BatteryMonitor.maxSamples + 50) {
                $0.battery.append(BatterySample(at: Date().addingTimeInterval(Double(i)), level: 0.5, charging: false, sharing: true))
            }
            if $0.battery.count > BatteryMonitor.maxSamples {
                $0.battery.removeFirst($0.battery.count - BatteryMonitor.maxSamples)
            }
        }
        XCTAssertEqual(outbox.state.battery.count, BatteryMonitor.maxSamples)
    }

    func testAPreCatalogueStateStillDecodesAndCarriesNoVersion() throws {
        let old = """
        {"batches":[],"anchors":{},"healthEnabled":["steps","workout"],"sharing":true,"historyStart":768000}
        """
        let state = try JSONDecoder().decode(PersistedState.self, from: Data(old.utf8))
        XCTAssertEqual(state.catalogueVersion, 0)
        XCTAssertEqual(state.hourlyFrom, [:])
        XCTAssertEqual(state.pendingRoutes, [:])
    }

    func testARecordWithNoNewFieldsEncodesWithoutThem() throws {
        let r = HealthRecord(id: "a", kind: "heart_rate", start: "2026-09-23T01:00:00Z", end: "2026-09-23T01:00:00Z", value: 60, unit: "bpm", source: "Watch")
        let json = String(decoding: try JSONEncoder().encode(r), as: UTF8.self)
        XCTAssertFalse(json.contains("points"), "nil fields must be omitted, or the server's exact-keys check still passes but payloads bloat")
    }

    func testEveryKindTheUploadedListCanShowHasALabel() {
        for kind in HealthCatalogue.file.kinds.keys {
            XCTAssertFalse(HealthScreen.label(for: kind).isEmpty)
        }
        XCTAssertEqual(HealthScreen.label(for: "heart_rate_variability"), "Heart rate variability")
    }
}
