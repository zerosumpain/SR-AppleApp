import XCTest
@testable import SRAppleApp

/// The live family map's playback: smoothing, dead reckoning, catch-up and
/// the outlier gate (`Family/FamilyLiveMotion.swift`). Linux-run.
final class FamilyLiveMotionTests: XCTestCase {
    /// A walk due north at ~1.4 m/s: one fix every 5 s from t0.
    private func walk(from t0: Double = 1_000, count: Int = 10, every: Double = 5, mps: Double = 1.4) -> [LiveSample] {
        (0..<count).map { i in
            let t = t0 + Double(i) * every
            return LiveSample(t: t, lat: 54.5 + Double(i) * every * mps / LiveGeo.metresPerDegree, lon: -1.55)
        }
    }

    func testInterpolatesBetweenFixesAlongTheLegAndHeadsNorth() throws {
        var track = LiveTrack()
        let points = walk()
        track.merge(points, now: 2_000)
        let mid = try XCTUnwrap(track.position(at: 1_002.5))
        XCTAssertEqual(mid.lat, (points[0].lat + points[1].lat) / 2, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(mid.heading), 0, accuracy: 1)
    }

    func testDeadReckonsPastTheNewestFixThenStops() throws {
        var track = LiveTrack()
        let points = walk()
        track.merge(points, now: 2_000)
        let last = try XCTUnwrap(points.last)
        let soon = try XCTUnwrap(track.position(at: last.t + 5))
        XCTAssertGreaterThan(soon.lat, last.lat, "carried on north")
        let later = try XCTUnwrap(track.position(at: last.t + LiveTrack.extrapolate))
        let muchLater = try XCTUnwrap(track.position(at: last.t + 300))
        XCTAssertEqual(later.lat, muchLater.lat, accuracy: 1e-12, "never further than the extrapolation")
        // v·E/2 metres at most: 1.4 × 15 / 2 = 10.5 m.
        let carried = LiveGeo.metres(last, LiveSample(t: 0, lat: later.lat, lon: later.lon))
        XCTAssertEqual(carried, 10.5, accuracy: 0.5)
    }

    func testAPersonStandingStillIsNotCarriedOn() throws {
        var track = LiveTrack()
        track.merge([LiveSample(t: 0, lat: 54, lon: -1), LiveSample(t: 10, lat: 54, lon: -1)], now: 20)
        let p = try XCTUnwrap(track.position(at: 20))
        XCTAssertEqual(p.lat, 54)
        XCTAssertNil(p.heading)
    }

    func testDropsAGPSJumpButFollowsARealRelocation() {
        var points = walk(count: 6)
        // A spike two kilometres east for one fix, then back on the walk.
        points[3] = LiveSample(t: points[3].t, lat: points[3].lat, lon: -1.52)
        XCTAssertEqual(LiveTrack.withoutJumps(points).count, 5, "the spike is dropped")

        // Woke up 5 km on and stayed there: two fixes agree, so it is real.
        let base = walk(count: 3)
        let moved = [LiveSample(t: 1_015, lat: 54.55, lon: -1.55), LiveSample(t: 1_020, lat: 54.55001, lon: -1.55)]
        XCTAssertEqual(LiveTrack.withoutJumps(base + moved).count, 5)
    }

    func testMergeKeepsTimeOrderOneFixPerInstantAndOnlyTheRecentPath() {
        var track = LiveTrack()
        let points = walk(count: 4)
        track.merge([points[2], points[0]], now: 2_000)
        track.merge([points[1], points[3], points[2]], now: 2_000)
        XCTAssertEqual(track.samples.map(\.t), points.map(\.t))
        track.merge([LiveSample(t: 1_000 + LiveTrack.keep + 100, lat: points[3].lat, lon: -1.55)], now: 2_000)
        XCTAssertEqual(track.samples.count, 1, "older than the kept window behind the newest")
    }

    func testThePlayheadRunsBehindRealTimeAndWaitsAtTheEndOfTheData() {
        var head = LivePlayhead.start(now: 100, newest: 95)
        XCTAssertEqual(head.at, 100 - LivePlayhead.lag)
        head.advance(now: 101, newest: 100)
        XCTAssertEqual(head.at, 101 - LivePlayhead.lag, accuracy: 1e-9)

        // A dead patch: no fix after t = 100. The playhead goes no further
        // than the dead reckoning past it, however long the silence.
        var wall = 101.0
        while wall < 300 { wall += 0.5; head.advance(now: wall, newest: 100) }
        XCTAssertEqual(head.at, 100 + LiveTrack.extrapolate, accuracy: 1e-9)
        XCTAssertFalse(head.catchingUp)

        // The queued route lands: the playhead is far behind it and replays
        // it quickly, then settles back to the lag.
        head.advance(now: wall + 0.1, newest: wall - 1)
        XCTAssertTrue(head.catchingUp)
        var frames = 0
        while head.catchingUp && frames < 400 {
            wall += 0.1
            head.advance(now: wall, newest: wall - 1)
            frames += 1
        }
        XCTAssertLessThan(Double(frames) * 0.1, 8, "the backlog replays in seconds, not minutes")
        for _ in 0..<200 { wall += 0.1; head.advance(now: wall, newest: wall - 1) }
        XCTAssertEqual(head.at, wall - LivePlayhead.lag, accuracy: 1, "back to the lag, not stuck late")
    }

    func testAPlayheadResumesWhereTheMapLastDrewOnlyIfThatIsRecent() {
        XCTAssertEqual(LivePlayhead.start(now: 1_000, newest: 999, resumeFrom: 900).at, 900, "replays the late route")
        XCTAssertEqual(LivePlayhead.start(now: 1_000, newest: 999, resumeFrom: 10).at, 1_000 - LivePlayhead.lag, "too old to replay")
    }

    func testThinningDropsJitterAndTheDuplicatePinButKeepsTheNewest() {
        let still = (0..<30).map { i in LiveSample(t: Double(i), lat: 54.5 + Double(i % 3) * 2 / LiveGeo.metresPerDegree, lon: -1.55) }
        let thinned = LiveTrack.thinned(still)
        XCTAssertLessThan(thinned.count, 6, "2 m of jitter at 1 Hz is a few fixes, not thirty")
        XCTAssertEqual(thinned.last, still.last)
        let pin = LiveSample(t: 100.4, lat: 54.5, lon: -1.55)
        XCTAssertEqual(LiveTrack.thinned([LiveSample(t: 100, lat: 54.5, lon: -1.55), pin]), [pin])

        var track = LiveTrack()
        track.merge(still, now: 40)
        XCTAssertFalse(track.isMoving(now: 31), "jitter in one spot is not moving")
    }

    func testTheSmootherEasesASmallCorrectionAndSnapsABigOne() {
        var s = LiveSmoother(lat: 54, lon: -1)
        let near = (lat: 54 + 20 / LiveGeo.metresPerDegree, lon: -1.0)
        s.step(toward: near, dt: 0.1)
        XCTAssertGreaterThan(s.lat, 54)
        XCTAssertLessThan(s.lat, near.lat)
        let before = s.lat
        s.step(toward: near, dt: 0)
        XCTAssertEqual(s.lat, before, "no time passed: another map drew this frame")
        s.step(toward: (55, -1), dt: 0.1)
        XCTAssertEqual(s.lat, 55)
    }

    func testOnlyAMovingRecentTrackIsAnimatedAndItsFrameGlides() throws {
        var state = FamilyLiveState()
        let points = walk(from: 1_000, count: 12)
        let now = try XCTUnwrap(points.last).t + 3
        state.ingest(subject: "sam", samples: points, now: now)
        state.ingest(subject: "still", samples: [LiveSample(t: now - 10, lat: 54, lon: -1), LiveSample(t: now - 5, lat: 54, lon: -1)], now: now)
        state.ingest(subject: "old", samples: walk(from: 0, count: 5), now: now)
        XCTAssertTrue(state.animating(now: now))
        XCTAssertFalse(state.isLive("still", now: now))
        XCTAssertFalse(state.isLive("old", now: now))

        var lats: [Double] = []
        for k in 0..<20 {
            let frames = state.frame(now: now + Double(k) * 0.1)
            XCTAssertNil(frames["still"])
            lats.append(try XCTUnwrap(frames["sam"]).lat)
        }
        XCTAssertEqual(lats, lats.sorted(), "heading north, never backwards")
        XCTAssertGreaterThan(Set(lats).count, 10, "moves on every frame, not in hops")
        XCTAssertGreaterThan(try XCTUnwrap(state.frame(now: now + 2).values.first).tail.count, 2)
    }
}
