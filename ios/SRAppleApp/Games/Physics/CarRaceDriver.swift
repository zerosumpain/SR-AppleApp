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
    /// Seconds behind the race clock it is drawn at: a recorded ghost is
    /// exact (0); a nearby car is drawn a moment late so there are always two
    /// reports to slide between.
    var delay: Double = 0
    var finished = false
}

/// This phone's car and its race: a display link that reads the steering,
/// drives the rules' physics, counts laps, records the run as a ghost and
/// keeps the other cars moving. Every mode uses it; the screens around it
/// decide who the rivals are and what a finish means.
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

    init(track: CarTrack, laps: Int, slot: Int, name: String, useTilt: Bool, startsAt: Double) {
        self.track = track
        var road = Path()
        if let first = track.points.first {
            road.move(to: CGPoint(x: first.x, y: first.y))
            for p in track.points.dropFirst() { road.addLine(to: CGPoint(x: p.x, y: p.y)) }
            road.closeSubpath()
        }
        self.road = road
        self.laps = laps
        self.name = name
        self.startsAt = startsAt
        scripted = SRDemo.isOn
        self.useTilt = useTilt && !SRDemo.isOn
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

    /// Where `rival` is now.
    func pose(of rival: CarRival) -> (at: CarVec, heading: Double)? {
        rival.ghost.pose(at: raceTime - rival.delay)
    }

    /// My place among the cars on the track, by distance raced (1 is first).
    /// A ghost is placed by how far it had got at this moment of its run.
    var place: Int {
        let mine = counter.raced
        return 1 + rivals.filter { rival in
            if rival.finished { return true }
            return (rival.ghost.raced(at: raceTime - rival.delay) ?? -.infinity) > mine
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
        return true
    }

    private func drive(dt: Double, now: Double) {
        var next = car
        if let hit = CarPhysics.step(&next, input: input(), track: track, dt: dt), hit.impact > 4, now - lastBump > 0.3 {
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
