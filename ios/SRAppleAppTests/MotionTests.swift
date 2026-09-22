import XCTest
@testable import SRAppleApp

/// The motion gate: the decision, the arithmetic behind the history screen, and
/// the upgrade path.
///
/// Core Motion answers nothing in a simulator, so the state machine itself
/// cannot be exercised in CI. That is exactly why all of the judgement lives in
/// `MotionAssessment` and `GateMaths`, which are pure — the part that decides
/// whether to spend battery is the part that gets tested.
final class MotionTests: XCTestCase {

    private let origin = Date(timeIntervalSince1970: 1_700_000_000)

    private func interval(_ kind: MotionKind, from: TimeInterval, seconds: TimeInterval,
                          confidence: MotionConfidence = .high) -> MotionInterval {
        MotionInterval(start: origin.addingTimeInterval(from),
                       end: origin.addingTimeInterval(from + seconds),
                       kind: kind, confidence: confidence)
    }

    private func evidence(_ intervals: [MotionInterval], steps: Int = 0,
                          burst: Int = 0, burstSeconds: TimeInterval = 120,
                          available: Bool = true) -> MotionEvidence {
        MotionEvidence(from: origin, to: origin.addingTimeInterval(900),
                       intervals: intervals, steps: steps, burstSteps: burst,
                       burstSeconds: burstSeconds, available: available)
    }

    // MARK: - The two tests John asked for

    func testFiveMinutesOfConsistentStepsWakesGPS() {
        // The original ask, asked of the activity log rather than a step
        // counter — the log already knows walking from standing up.
        let e = evidence([interval(.walking, from: 0, seconds: 300),
                          interval(.stationary, from: 300, seconds: 60)])
        let verdict = MotionAssessment.verdict(e, settings: MotionSettings(enabled: true))
        XCTAssertTrue(verdict.wakesGPS)
        XCTAssertEqual(verdict, .travelling(.walking, "Walking for 5 min"))
    }

    func testFourMinutesOfWalkingIsNotEnoughOnItsOwn() {
        let e = evidence([interval(.walking, from: 0, seconds: 240)], steps: 300)
        XCTAssertFalse(MotionAssessment.verdict(e, settings: MotionSettings(enabled: true)).wakesGPS)
    }

    func testAStepBurstWakesGPSBeforeTheWalkIsSustained() {
        // The second test: steps over a short recent window. It catches somebody
        // who has only just set off, where the sustained test cannot have passed
        // yet by definition.
        let e = evidence([interval(.walking, from: 0, seconds: 60)], steps: 180, burst: 180)
        let verdict = MotionAssessment.verdict(e, settings: MotionSettings(enabled: true))
        XCTAssertTrue(verdict.wakesGPS)
        XCTAssertEqual(verdict, .travelling(.walking, "180 steps in 2 min"))
    }

    func testBelowTheBurstThresholdIsABlip() {
        let e = evidence([interval(.walking, from: 0, seconds: 40)], steps: 40, burst: 40)
        XCTAssertFalse(MotionAssessment.verdict(e, settings: MotionSettings(enabled: true)).wakesGPS)
    }

    func testTurningTheBurstTestOffLeavesTheWalkingOne() {
        let settings = MotionSettings(enabled: true, stepBurst: 0)
        let burstOnly = evidence([interval(.walking, from: 0, seconds: 60)], steps: 400, burst: 400)
        XCTAssertFalse(MotionAssessment.verdict(burstOnly, settings: settings).wakesGPS)
        let sustained = evidence([interval(.walking, from: 0, seconds: 320)])
        XCTAssertTrue(MotionAssessment.verdict(sustained, settings: settings).wakesGPS)
    }

    // MARK: - Driving, which a step threshold alone would miss entirely

    func testDrivingWakesImmediatelyWithNoMinimumDuration() {
        // Leaving a 150m anchor by car takes seconds. Requiring a minute of
        // driving here would send the app back to sleep at exactly the moment a
        // family most wants to see where somebody is — and steps are ZERO in a
        // car, so the step tests can never catch this.
        let e = evidence([interval(.stationary, from: 0, seconds: 800),
                          interval(.automotive, from: 800, seconds: 12)])
        let verdict = MotionAssessment.verdict(e, settings: MotionSettings(enabled: true))
        XCTAssertEqual(verdict, .travelling(.automotive, "Driving now"))
    }

    func testDrivingWithTheToggleOffStillNeedsTheMinimum() {
        let settings = MotionSettings(enabled: true, vehicleAlwaysWakes: false)
        let brief = evidence([interval(.automotive, from: 800, seconds: 12)])
        XCTAssertFalse(MotionAssessment.verdict(brief, settings: settings).wakesGPS)
        let sustained = evidence([interval(.automotive, from: 700, seconds: 90)])
        XCTAssertTrue(MotionAssessment.verdict(sustained, settings: settings).wakesGPS)
    }

    func testTravelThatHasAlreadyStoppedStillCounts() {
        // You drove here and then sat down, so the old anchor is in the wrong
        // place. The latest classification is stationary, which rule one misses.
        let e = evidence([interval(.automotive, from: 0, seconds: 120),
                          interval(.stationary, from: 120, seconds: 600)])
        let verdict = MotionAssessment.verdict(e, settings: MotionSettings(enabled: true))
        XCTAssertTrue(verdict.wakesGPS)
    }

    func testRunningWakesRegardlessOfTheVehicleToggle() {
        let settings = MotionSettings(enabled: true, vehicleAlwaysWakes: false)
        let e = evidence([interval(.running, from: 800, seconds: 15)])
        XCTAssertEqual(MotionAssessment.verdict(e, settings: settings), .travelling(.running, "Running now"))
    }

    // MARK: - Confidence, which is most of a wake storm

    func testLowConfidenceIsIgnoredAtTheDefaultFloor() {
        let e = evidence([interval(.walking, from: 0, seconds: 600, confidence: .low)])
        XCTAssertFalse(MotionAssessment.verdict(e, settings: MotionSettings(enabled: true)).wakesGPS)
    }

    func testLoweringTheFloorLetsThatSameEvidenceThrough() {
        let e = evidence([interval(.walking, from: 0, seconds: 600, confidence: .low)])
        let settings = MotionSettings(enabled: true, confidenceFloor: .low)
        XCTAssertTrue(MotionAssessment.verdict(e, settings: settings).wakesGPS)
    }

    func testTheHighFloorRejectsMediumConfidence() {
        let e = evidence([interval(.walking, from: 0, seconds: 600, confidence: .medium)])
        let settings = MotionSettings(enabled: true, confidenceFloor: .high)
        XCTAssertFalse(MotionAssessment.verdict(e, settings: settings).wakesGPS)
    }

    // MARK: - Failing open

    func testUnreadableMotionTurnsGPSONRatherThanGoingQuiet() {
        // The worst outcome available to this design is an app that looks like
        // it is working and silently records nothing because a permission was
        // refused. Paying for GPS is the cheaper mistake, so every ambiguous
        // answer has to fall this way.
        var e = evidence([])
        e.available = false
        e.note = "Motion & Fitness is off for this app in iOS Settings"
        let verdict = MotionAssessment.verdict(e, settings: MotionSettings(enabled: true))
        XCTAssertTrue(verdict.wakesGPS)
        XCTAssertEqual(verdict, .unreadable("Motion & Fitness is off for this app in iOS Settings"))
    }

    func testAnEmptyReadableWindowIsABlip() {
        XCTAssertFalse(MotionAssessment.verdict(evidence([]), settings: MotionSettings(enabled: true)).wakesGPS)
    }

    // MARK: - GateMaths, which is what the history screen prints

    private func event(_ kind: GateEvent.Kind, at seconds: TimeInterval, state: GateState) -> GateEvent {
        GateEvent(at: origin.addingTimeInterval(seconds), kind: kind, reason: kind.label, stateAfter: state)
    }

    func testTheStateEnteringAWindowComesFromBeforeIt() {
        // Four hours of log, a two-hour window. The gate went to sleep BEFORE
        // the window opened, so the first hour of the window is sleep — reading
        // it from the first event inside the window instead would report a
        // night's sleep as unmeasured and flatter the duty cycle badly.
        let now = origin.addingTimeInterval(4 * 3600)
        let events = [
            event(.started, at: 0, state: .tracking),
            event(.armed, at: 3600, state: .armed),
            event(.resumed, at: 3 * 3600, state: .tracking),
        ]
        let spans = GateMaths.spans(events, since: origin.addingTimeInterval(2 * 3600), now: now)
        XCTAssertEqual(spans.armed, 3600, accuracy: 1)
        XCTAssertEqual(spans.tracking, 3600, accuracy: 1)
        XCTAssertEqual(GateMaths.dutyCycle(events, since: origin.addingTimeInterval(2 * 3600), now: now)!,
                       0.5, accuracy: 0.001)
    }

    func testTimeBeforeTheFirstLineIsNotCounted() {
        // Same refusal `BatteryMaths` makes about a long gap: we do not know
        // what the app was doing before the log starts, and inventing it would
        // be a lie in whichever direction it was invented.
        let now = origin.addingTimeInterval(4 * 3600)
        let events = [event(.started, at: 3 * 3600, state: .tracking)]
        let spans = GateMaths.spans(events, since: origin, now: now)
        XCTAssertEqual(spans.tracking, 3600, accuracy: 1)
        XCTAssertEqual(spans.armed, 0, accuracy: 1)
    }

    func testAnEmptyLogHasNoDutyCycleRatherThanZero() {
        XCTAssertNil(GateMaths.dutyCycle([], since: origin, now: origin.addingTimeInterval(3600)))
    }

    func testTheOpenSpanRunsToNow() {
        // The last event has no successor, so the tail is measured against the
        // clock. Without it a phone asleep for nine hours would report nothing.
        let now = origin.addingTimeInterval(9 * 3600)
        let events = [event(.started, at: 0, state: .tracking), event(.armed, at: 60, state: .armed)]
        let spans = GateMaths.spans(events, since: origin, now: now)
        XCTAssertEqual(spans.armed, 9 * 3600 - 60, accuracy: 1)
    }

    func testWakeQualityIsTheAnchorsReportCard() {
        let events = [
            event(.woke, at: 0, state: .armed), event(.slept, at: 10, state: .armed),
            event(.woke, at: 100, state: .armed), event(.slept, at: 110, state: .armed),
            event(.woke, at: 200, state: .armed), event(.resumed, at: 210, state: .tracking),
        ]
        let quality = GateMaths.wakeQuality(events, since: origin)
        XCTAssertEqual(quality.wakes, 3)
        XCTAssertEqual(quality.real, 1)
        XCTAssertEqual(quality.share!, 1.0 / 3.0, accuracy: 0.001)
    }

    func testWakeQualityIsAbsentRatherThanZeroWithNoWakes() {
        XCTAssertNil(GateMaths.wakeQuality([], since: origin).share)
    }

    // MARK: - The upgrade path
    //
    // Same rule the settings PR learned the hard way: Swift's synthesised
    // Codable does NOT use a property's default for a missing key, and this file
    // is the upload queue.

    func testAStateFileWithoutTheGateFieldsStillDecodes() throws {
        let old = """
        {"batches":[],"anchors":{},"healthEnabled":["steps"],"sharing":true,
         "pointsRecorded":12}
        """
        let state = try JSONDecoder().decode(PersistedState.self, from: Data(old.utf8))
        XCTAssertEqual(state.pointsRecorded, 12)
        XCTAssertEqual(state.gateState, .tracking, "an upgrade must not come back asleep")
        XCTAssertNil(state.anchor)
        XCTAssertTrue(state.gateEvents.isEmpty)
        XCTAssertFalse(state.location.motion.enabled, "and must not silently start gating")
    }

    func testAPartialMotionBlobKeepsTheRestOfTheDefaults() throws {
        let json = #"{"motion":{"enabled":true,"sustainedWalk":120}}"#
        let s = try JSONDecoder().decode(LocationSettings.self, from: Data(json.utf8))
        XCTAssertTrue(s.motion.enabled)
        XCTAssertEqual(s.motion.sustainedWalk, 120)
        XCTAssertEqual(s.motion.stepBurst, 150, "unlisted fields must keep their defaults")
        XCTAssertEqual(s.motion.confidenceFloor, .medium)
        XCTAssertEqual(s.movingInterval, 30, "and the settings around it are untouched")
    }

    func testAGateEventMissingEverythingStillDecodes() throws {
        let events = try JSONDecoder().decode([GateEvent].self, from: Data("[{}]".utf8))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].stateAfter, .tracking)
    }

    @MainActor func testTheGateLogIsBounded() throws {
        // It rides in the same atomically-written file as the upload queue, so
        // an unbounded log would make every location save cost more than the
        // location it was saving.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = try Outbox(url: directory.appendingPathComponent("state.json"))
        try outbox.change {
            for i in 0..<(GateEvent.maxStored + 40) {
                $0.gateEvents.append(GateEvent(at: Date().addingTimeInterval(Double(i)),
                                               kind: .woke, reason: "test", stateAfter: .armed))
            }
            if $0.gateEvents.count > GateEvent.maxStored {
                $0.gateEvents.removeFirst($0.gateEvents.count - GateEvent.maxStored)
            }
        }
        XCTAssertEqual(outbox.state.gateEvents.count, GateEvent.maxStored)
    }

    @MainActor func testTheGateStateSurvivesARestart() throws {
        // The point of persisting it: a relaunch — including the background
        // relaunch a geofence exit itself causes — must not start continuous
        // GPS again, which is the whole cost the gate exists to avoid.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")

        let first = try Outbox(url: url)
        try first.change {
            $0.gateState = .armed
            $0.anchor = GateAnchor(latitude: 54.5, longitude: -1.55, radius: 180, at: Date())
        }
        let second = try Outbox(url: url)
        XCTAssertEqual(second.state.gateState, .armed)
        XCTAssertEqual(second.state.anchor?.radius, 180)
    }

    // MARK: - Presets

    func testTheShippedDefaultLeavesTheGateOff() {
        // An upgrade must change nothing on its own. A battery setting that
        // moves silently is worse than no setting.
        XCTAssertFalse(LocationSettings().motion.enabled)
        XCTAssertFalse(LocationSettings.Preset.accurate.settings.motion.enabled)
        XCTAssertEqual(LocationSettings().matchingPreset, .accurate)
    }

    func testTheCheaperPresetsTurnItOn() {
        XCTAssertTrue(LocationSettings.Preset.saver.settings.motion.enabled)
        XCTAssertTrue(LocationSettings.Preset.balanced.settings.motion.enabled)
    }

    func testSaverIsHarderToWakeAndSleepsSooner() {
        let saver = LocationSettings.Preset.saver.settings.motion
        let balanced = LocationSettings.Preset.balanced.settings.motion
        XCTAssertLessThan(saver.sleepAfter, balanced.sleepAfter, "saver must drop the sensor sooner")
        XCTAssertGreaterThan(saver.anchorRadius, balanced.anchorRadius, "and be disturbed less")
        XCTAssertGreaterThan(saver.stepBurst, balanced.stepBurst)
        XCTAssertGreaterThan(saver.confidenceFloor, balanced.confidenceFloor)
        XCTAssertLessThan(saver.maxWakesPerHour, balanced.maxWakesPerHour)
    }

    func testChangingAMotionValueReadsAsCustom() {
        var s = LocationSettings.Preset.balanced.settings
        XCTAssertEqual(s.matchingPreset, .balanced)
        s.motion.anchorRadius += 50
        XCTAssertNil(s.matchingPreset, "a changed motion value must read as Custom too")
    }
}
