import Foundation
import SwiftUI

/// Another car on the track that this phone does not drive: a ghost of a
/// best run, an earlier driver passing the phone round, or a nearby phone's car.
struct CarRival: Identifiable, Equatable {
    let id: String
    let name: String
    /// Seat, for the colour.
    let seat: Int
    var ghost: CarGhost
    /// A car being driven on another phone right now, heard of a few times a
    /// second: drawn where it should be NOW (carried on from its last report,
    /// `CarGhost.predict`), and solid — my car knocks into it. A recorded
    /// ghost is neither: it is drawn exactly and passes through.
    var live = false
    var finished = false
}

/// This phone's car and its race: a display link that reads the steering,
/// drives the rules' physics, counts laps, records the run as a ghost, keeps
/// the other cars moving and knocks my car off the live ones. Every mode
/// uses it; the screens around it decide who the rivals are and what a
/// finish means.
@MainActor
final class CarRaceDriver: ObservableObject {
    enum Phase: Equatable {
        /// On the grid; the lights go out at `startsAt` (local uptime).
        case grid
        case racing
        case finished
    }

    let track: CarTrack
    /// The track's middle line as a path, built once for the drawing.
    let road: Path
    let laps: Int
    let name: String
    @Published private(set) var phase: Phase = .grid
    @Published private(set) var car: CarState
    @Published private(set) var counter: CarLapCounter
    @Published private(set) var raceTime: Double = 0
    @Published var rivals: [CarRival] = []
    /// The camera's heading, eased behind the car's so a twitch is not a lurch.
    private(set) var cameraHeading: Double
    /// The run as it is driven, for the ghost a best leaves behind.
    private(set) var recording: CarGhost

    /// Steering from the buttons: −1, 0, 1. Ignored when tilt steers.
    var steerHeld: Double = 0
    var brakeHeld = false
    let useTilt: Bool
    let scripted: Bool
    let tilt = PhysicsTilt()
    /// Called once, at the finish line.
    var onFinish: (@MainActor (CarLapCounter, CarGhost) -> Void)?
    /// Called about eight times a second while racing (nearby races report with it).
    var onReport: (@MainActor (CarState, CarLapCounter, Double) -> Void)?

    /// Local uptime the lights go out.
    private(set) var startsAt: Double
    private var ticker: FrameTicker?
    private var lastFrame: Double?
    private var lastReport: Double = -1
    private var lastBump: Double = -1
    private var steer: Double = 0
    /// My car's last bounce off each live rival, for the cooldown.
    private var bumps = CarBumpClock()
    /// How far each live rival is drawn from where it is predicted to be: the
    /// jump a fresh report made, easing away (`hear`).
    private var nudges: [String: CarVec] = [:]

    init(track: CarTrack, laps: Int, slot: Int, name: String, useTilt: Bool, startsAt: Double) {
        self.track = track
        road = CarRaceScene.road(for: track)
        self.laps = laps
        self.name = name
        self.startsAt = startsAt
        scripted = SRDemo.isOn
        // No sensor (or the demo): the arrows steer, whatever was asked for.
        self.useTilt = useTilt && PhysicsTilt.isAvailable
        let grid = track.grid(slot)
        car = CarState(x: grid.at.x, y: grid.at.y, heading: grid.heading)
        cameraHeading = grid.heading
        counter = CarLapCounter(length: track.length, laps: laps, startDistance: track.spot(of: grid.at).distance)
        recording = CarGhost(trackId: track.id, laps: laps, name: name)
    }

    /// Move the start (a nearby race learns the host's countdown).
    func setStart(_ local: Double) {
        guard phase == .grid else { return }
        startsAt = local
    }

    func start() {
        if useTilt { tilt.start() }
        guard ticker == nil, phase != .finished else { return }
        lastFrame = nil
        let ticker = FrameTicker { [weak self] time in
            guard let self else { return false }
            return self.frame(time)
        }
        self.ticker = ticker
        ticker.start()
    }

    func stop() {
        ticker?.stop()
        ticker = nil
        lastFrame = nil
        tilt.stop()
    }

    /// Seconds until the lights go out (0 once racing).
    var countdown: Double { max(0, startsAt - OfflineUptime.now()) }

    /// Where `rival` is drawn now.
    func pose(of rival: CarRival) -> (at: CarVec, heading: Double)? {
        guard rival.live else { return rival.ghost.pose(at: raceTime) }
        guard let body = rival.ghost.predict(at: raceTime) else { return nil }
        return (body.at + (nudges[rival.id] ?? .zero), body.heading)
    }

    /// Whether my car can hit `rival` now: a live car still racing, with
    /// news of it no older than the prediction reaches. One that has gone
    /// quiet on the link is drawn faded and driven through — it would be
    /// unfair to bounce off where a car might no longer be. On the grid a
    /// rival's slot is news enough until the lights go out.
    func isSolid(_ rival: CarRival) -> Bool {
        guard rival.live, !rival.finished, let last = rival.ghost.samples.last else { return false }
        return raceTime - max(last.t, 0) <= CarCollision.horizon
    }

    /// News of a car driven on another phone: its latest position joins its
    /// trail. What this phone had predicted for it and what it now knows
    /// rarely agree exactly, so the difference is kept as a nudge on the
    /// drawing that eases away over a few frames — the car glides to the
    /// truth instead of jumping. Collisions use the truth.
    func hear(_ sample: CarGhost.Sample, from id: String, name: String, seat: Int, finished: Bool) {
        guard let index = rivals.firstIndex(where: { $0.id == id }) else {
            var ghost = CarGhost(trackId: track.id, laps: laps, name: name)
            ghost.append(sample)
            rivals.append(CarRival(id: id, name: name, seat: seat, ghost: ghost, live: true, finished: finished))
            return
        }
        var rival = rivals[index]
        let latest = rival.ghost.samples.last?.t
        let before = rival.ghost.predict(at: raceTime)
        rival.ghost.append(sample)
        rival.finished = finished
        if rival.ghost.samples.last?.t != latest, let before, let after = rival.ghost.predict(at: raceTime) {
            let nudge = (nudges[id] ?? .zero) + (before.at - after.at)
            // A jump that big is news (a lost link come back), not noise: show it.
            nudges[id] = nudge.length > 6 ? .zero : nudge
        }
        if rival != rivals[index] { rivals[index] = rival }
    }

    /// My place among the cars on the track, by distance raced (1 is first).
    /// A ghost is placed by how far it had got at this moment of its run.
    var place: Int {
        let mine = counter.raced
        return 1 + rivals.filter { rival in
            if rival.finished { return true }
            return (rival.ghost.raced(at: raceTime) ?? -.infinity) > mine
        }.count
    }

    /// Seconds behind (positive) or ahead of a recorded ghost at this point of the track.
    func gap(to rival: CarRival) -> Double? {
        guard phase == .racing, counter.raced > 0, let then = rival.ghost.time(atRaced: counter.raced) else { return nil }
        return raceTime - then
    }

    // MARK: - The frame

    private func frame(_ time: Double) -> Bool {
        let dt = lastFrame.map { min(max(0, time - $0), 1.0 / 20) } ?? 0
        lastFrame = time
        let now = OfflineUptime.now()
        switch phase {
        case .grid:
            raceTime = now - startsAt
            if now >= startsAt {
                phase = .racing
                SRHaptic.tap()
            }
        case .racing:
            raceTime = now - startsAt
            drive(dt: dt, now: now)
        case .finished:
            raceTime = now - startsAt
        }
        cameraHeading = Self.ease(cameraHeading, towards: car.heading, by: min(1, dt * 6))
        if !nudges.isEmpty {
            let keep = exp(-dt * 8)
            nudges = nudges.mapValues { $0 * keep }
        }
        return true
    }

    private func drive(dt: Double, now: Double) {
        var next = car
        let wall = CarPhysics.step(&next, input: input(), track: track, dt: dt)?.impact ?? 0
        let knock = collide(&next)?.impact ?? 0
        if max(wall, knock) > 4, now - lastBump > 0.3 {
            lastBump = now
            SRHaptic.tap()
        }
        car = next
        var laps = counter
        let before = laps.splits.count
        laps.update(distance: track.spot(of: next.position).distance, time: raceTime)
        if laps.splits.count > before, !laps.finished { SRHaptic.select() }
        counter = laps
        recording.record(next, raced: laps.raced, at: raceTime)
        if raceTime - lastReport >= 0.12 {
            lastReport = raceTime
            onReport?(next, laps, raceTime)
        }
        if laps.finished {
            phase = .finished
            recording.time = laps.finishTime
            SRHaptic.ok()
            tilt.stop()
            onFinish?(laps, recording)
        }
    }

    /// My car against every solid rival where it is predicted to be now: my
    /// half of each knock, on my car only (`CarCollision.collide`).
    private func collide(_ car: inout CarState) -> CarBump? {
        let others: [(id: String, body: CarBody)] = rivals.compactMap { rival in
            guard isSolid(rival), let body = rival.ghost.predict(at: raceTime) else { return nil }
            return (id: rival.id, body: body)
        }
        guard !others.isEmpty else { return nil }
        return CarCollision.collide(&car, with: others, clock: &bumps, at: raceTime)
    }

    private func input() -> CarInput {
        if scripted { return CarAutopilot.input(for: car, on: track) }
        let wanted: Double
        if useTilt {
            // A fifth of a g is full lock; a sliver either side of level is straight.
            let raw = tilt.lean() ?? 0
            let live = abs(raw) < 0.025 ? 0 : raw
            wanted = min(max(live / 0.2, -1), 1)
        } else {
            wanted = steerHeld
        }
        // Buttons are all or nothing: ease them so a tap is a nudge, not a swerve.
        steer += (wanted - steer) * (useTilt ? 0.5 : 0.18)
        return CarInput(throttle: brakeHeld ? -1 : 1, steer: steer)
    }

    private static func ease(_ angle: Double, towards target: Double, by share: Double) -> Double {
        var turn = target - angle
        while turn > .pi { turn -= 2 * .pi }
        while turn < -.pi { turn += 2 * .pi }
        return angle + turn * share
    }
}
