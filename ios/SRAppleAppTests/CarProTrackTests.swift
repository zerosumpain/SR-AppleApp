import XCTest
@testable import SRAppleApp

/// Car Racer+ circuits, racing lines, speed profiles and the AI driving them.
final class CarProTrackTests: XCTestCase {
    // MARK: - Circuits

    func testEightCircuitsWithCharacter() {
        let all = CarProCircuits.all
        XCTAssertGreaterThanOrEqual(all.count, 8)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        XCTAssertEqual(Set(all.map(\.name)).count, all.count)
        XCTAssertEqual(Set(all.map(\.theme)), Set(CarProTrackTheme.allCases), "every kind of circuit is there")
        for track in all {
            XCTAssertEqual(CarProCircuits.track(track.id)?.id, track.id)
            XCTAssertGreaterThan(track.length, 800, track.id)
            XCTAssertGreaterThanOrEqual(track.corners.count, 3, track.id)
            XCTAssertEqual(Set(track.corners.map(\.name)).count, track.corners.count, "\(track.id) corner names")
            for corner in track.corners { XCTAssertTrue((0..<track.length).contains(corner.distance)) }
            XCTAssertEqual(track.sectorStarts.count, 2)
            XCTAssertLessThan(0, track.sectorStarts[0])
            XCTAssertLessThan(track.sectorStarts[0], track.sectorStarts[1])
            XCTAssertLessThan(track.sectorStarts[1], track.length)
            XCTAssertFalse(track.line.isEmpty)
        }
        XCTAssertNil(CarProCircuits.track("nowhere"))
        let ring = CarProCircuits.track("nordwald")!
        XCTAssertEqual(ring.length, all.map(\.length).max()!, "the ring is the long one")
        XCTAssertGreaterThan(ring.length, 4_000)
        XCTAssertTrue(CarProCircuits.track("thunder-bowl")!.samples.contains { abs($0.bank) > 0.15 }, "banked")
        XCTAssertTrue(CarProCircuits.track("quarry-rx")!.samples.contains { $0.surface == .dirt }, "mixed surface")
        XCTAssertTrue(CarProCircuits.track("neon-harbour")!.theme.isNight)
        let street = CarProCircuits.track("old-town")!
        XCTAssertLessThan(street.samples.map { max($0.runoffLeft, $0.runoffRight) }.max()!, 3, "walls close")
    }

    func testEveryCircuitNeverCrossesItselfAndHasRunOff() {
        for track in CarProCircuits.all {
            XCTAssertEqual(track.crossings(), 0, track.id)
            XCTAssertGreaterThan(track.tightestGap(), 3, "\(track.id): two stretches of tarmac touch")
            var kerbs = 0, gravel = 0
            for (i, s) in track.samples.enumerated() {
                XCTAssertGreaterThan(s.runoffLeft, 0.5, "\(track.id) sample \(i) has run-off on the left")
                XCTAssertGreaterThan(s.runoffRight, 0.5, "\(track.id) sample \(i) has run-off on the right")
                if s.kerbLeft || s.kerbRight { kerbs += 1 }
                if s.gravelLeft || s.gravelRight { gravel += 1 }
                // Beside the tarmac is grass or gravel, never more tarmac.
                let beyond = s.halfWidth + CarProTrack.kerbWidth + 0.5
                XCTAssertFalse(track.surface(sample: i, offset: beyond).isTrack, "\(track.id) \(i)")
                XCTAssertFalse(track.surface(sample: i, offset: -beyond).isTrack, "\(track.id) \(i)")
                XCTAssertTrue(track.surface(sample: i, offset: 0).isTrack)
                // The racing line stays on the tarmac.
                XCTAssertLessThan(abs(s.lineOffset), s.halfWidth - 1, "\(track.id) line at \(i)")
            }
            XCTAssertGreaterThan(kerbs, track.corners.count * 3, "\(track.id): kerbs on the apexes")
            // The drawing helpers: runs cover exactly the kerbed samples, polylines every sample asked for.
            let n = track.samples.count
            let kerbRuns = track.runs { $0.kerbLeft }
            XCTAssertEqual(kerbRuns.reduce(0) { $0 + $1.count }, track.samples.filter(\.kerbLeft).count, track.id)
            for run in kerbRuns { for i in run { XCTAssertTrue(track.samples[i % n].kerbLeft) } }
            XCTAssertEqual(track.points(every: 4) { $0.wallLeft }.count, (n + 3) / 4)
            XCTAssertEqual(track.runs { _ in true }, [0...(n - 1)])
            XCTAssertEqual(track.runs { _ in false }, [])
            if track.id != "old-town" && track.id != "thunder-bowl" {
                XCTAssertGreaterThan(gravel, 20, "\(track.id): gravel traps")
            }
            // The grid sits on the tarmac, behind the line, everyone apart.
            var slots: [CarProVec] = []
            for slot in 0..<8 {
                let g = track.grid(slot)
                let spot = track.locate(g.position, hint: track.index(at: g.distance))
                XCTAssertLessThan(abs(spot.offset), track.samples[spot.index].halfWidth - 1, track.id)
                XCTAssertGreaterThan(spot.distance, track.length / 2, "\(track.id) slot \(slot) is behind the line")
                for other in slots { XCTAssertGreaterThan(other.distance(to: g.position), 4) }
                slots.append(g.position)
            }
        }
    }

    func testLocatingAPointFindsItsSpotFromAnyHint() {
        let track = CarProCircuits.track("kestrel-hill")!
        for i in stride(from: 0, to: track.samples.count, by: 37) {
            let s = track.samples[i]
            let p = s.point(2.5)
            let near = track.locate(p, hint: i)
            let far = track.locate(p, hint: i + track.samples.count / 2)
            XCTAssertEqual(near.offset, 2.5, accuracy: 0.3)
            XCTAssertEqual(near.distance, far.distance, accuracy: 0.01)
            XCTAssertEqual(track.gap(from: s.distance, to: near.distance), 0, accuracy: track.spacing)
        }
    }

    func testRacingLineIsSmootherThanTheCentreAndBrakingBoardsLeadIntoCorners() {
        for track in CarProCircuits.all {
            let centre = track.samples.reduce(0) { $0 + $1.curvature * $1.curvature }
            let line = track.samples.reduce(0) { $0 + $1.lineCurvature * $1.lineCurvature }
            XCTAssertLessThan(line, centre * 0.95, "\(track.id): the line straightens the bends")
            XCTAssertLessThan(track.samples.map { abs($0.lineCurvature) }.max()!,
                              track.samples.map { abs($0.curvature) }.max()!, "\(track.id): and eases the tightest")
            let profile = CarProSpeedProfile(track: track,
                                             performance: CarProPerformance(params: CarProCarSetup(model: .touring).params))
            XCTAssertFalse(profile.brakeMarkers.isEmpty, track.id)
            for marker in profile.brakeMarkers {
                XCTAssertGreaterThan(marker.entrySpeed, marker.apexSpeed + 6)
            }
            XCTAssertGreaterThan(profile.lapTime, track.length / 90)
            XCTAssertLessThan(profile.lapTime, track.length / 12)
        }
    }

    func testFasterCarsPlanFasterLapsAndGripCostsTime() {
        let track = CarProCircuits.track("brackenfield")!
        let times = CarProCarModel.allCases.map {
            CarProSpeedProfile(track: track, performance: CarProPerformance(params: CarProCarSetup(model: $0).params)).lapTime
        }
        XCTAssertLessThan(times.last!, times.first! * 0.85, "a prototype laps far quicker than a hatch")
        let hatch = CarProCarSetup(model: .hatch).params
        let slow = CarProSpeedProfile(track: track, performance: CarProPerformance(params: hatch, grip: 0.7)).lapTime
        XCTAssertGreaterThan(slow, times[0])
    }

    // MARK: - The AI

    /// `laps` flying laps by an AI alone, from a rolling start.
    private func lap(_ trackId: String, _ model: CarProCarModel, skill: Double, laps: Int)
        -> (times: [Double], walls: Int, offTrackShare: Double, estimate: Double) {
        let driver = CarProDriverProfile(id: "test", name: "Test", skill: skill, aggression: 0.5, number: 7, hue: 0.5)
        let entrant = CarProEntrant.ai(driver, setup: CarProCarSetup(model: model))
        var config = CarProSessionConfig.timeTrial(track: trackId, player: entrant, assists: .ai, ghost: nil)
        config.autopilot = true
        var session = CarProSession(config: config)
        var walls = 0, off = 0, frames = 0
        while session.player.lapsDone < laps && session.time < Double(laps) * 400 {
            session.step(dt: 1.0 / 30, input: CarProInput())
            frames += 1
            for event in session.events { if case .wallHit = event { walls += 1 } }
            if session.player.vehicle.offTrack { off += 1 }
        }
        return (session.player.lapTimes, walls, Double(off) / Double(max(frames, 1)), session.player.profile.lapTime)
    }

    func testAnAICarLapsEveryCircuitCleanlyAtAPlausiblePace() {
        for track in CarProCircuits.all {
            let run = lap(track.id, .hatch, skill: 1, laps: 3)
            XCTAssertEqual(run.times.count, 3, "\(track.id): three laps")
            XCTAssertEqual(run.walls, 0, "\(track.id): never into the wall")
            XCTAssertLessThan(run.offTrackShare, 0.01, "\(track.id): stays on the track")
            for t in run.times {
                let average = track.length / t
                XCTAssertGreaterThan(average, 18, "\(track.id) average speed")
                XCTAssertLessThan(average, 55, "\(track.id) average speed")
                XCTAssertEqual(t, run.estimate * CarProQualifying.realism / 0.96, accuracy: run.estimate * 0.08,
                               "\(track.id): lapped close to its plan")
            }
        }
    }

    func testFasterCarsLapFasterAndBetterDriversToo() {
        for trackId in ["saltcliff", "neon-harbour"] {
            let hatch = lap(trackId, .hatch, skill: 1, laps: 1).times
            let gt = lap(trackId, .gt, skill: 1, laps: 1).times
            let prototype = lap(trackId, .prototype, skill: 1, laps: 1).times
            XCTAssertEqual(hatch.count, 1)
            XCTAssertLessThan(gt[0], hatch[0], trackId)
            XCTAssertLessThan(prototype[0], gt[0], trackId)
        }
        let rookie = lap("kestrel-hill", .touring, skill: 0.1, laps: 1)
        let ace = lap("kestrel-hill", .touring, skill: 1, laps: 1)
        XCTAssertGreaterThan(rookie.times[0], ace.times[0] * 1.03, "a weaker driver is slower")
        XCTAssertEqual(rookie.walls, 0)
    }
}
