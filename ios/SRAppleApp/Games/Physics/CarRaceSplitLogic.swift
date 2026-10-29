import Foundation

// Car Race on a split screen: two to four cars on one phone at the same time,
// each player with their own part of the screen and their own camera,
// steering by holding their own side of it — tilt cannot steer two cars.
//
// Unlike a nearby race, every car lives in this one simulation, so the cars
// hit each other exactly: each pair that touches is pushed apart and bounced
// both at once (`CarCollision.pair`). The screen hands `step` what each player
// is holding once a frame and draws what comes back; `CarSplitLayout` says
// where each player's part of the screen is and which side a finger is on.

/// What a split-screen player is holding: their left side, their right, both
/// or neither, and the boost strip between them.
struct CarSplitHold: Equatable {
    var left = false
    var right = false
    var boost = false

    /// Left steers left, right steers right, both together is the brake, the
    /// middle boosts, and the throttle is down the rest of the time. The
    /// steering is what is wanted, before easing.
    var input: CarInput {
        switch (left, right) {
        case (true, true): return CarInput(throttle: -1, steer: 0)
        case (true, false): return CarInput(throttle: 1, steer: -1, boost: boost)
        case (false, true): return CarInput(throttle: 1, steer: 1, boost: boost)
        case (false, false): return CarInput(throttle: 1, steer: 0, boost: boost)
        }
    }
}

/// What happened in one frame of a split-screen race, for the haptics.
struct CarSplitEvents: Equatable {
    /// The hardest knock, against a wall or another car, m/s.
    var hardest: Double = 0
    /// Seats that completed a lap (not their last).
    var lapped: [Int] = []
    /// Seats that crossed the line for the last time.
    var finished: [Int] = []
}

/// A split-screen race: every car, its laps and the run it leaves behind.
struct CarSplitRace: Equatable {
    struct Racer: Equatable, Identifiable {
        /// The seat: the grid slot, the colour and the player's part of the screen.
        let id: Int
        let name: String
        var car: CarState
        var laps: CarLapCounter
        /// The run, recorded as a ghost: a best set here is raced in a time trial.
        var ghost: CarGhost
        /// The steering, eased towards what is held: a tap is a nudge, not a swerve.
        var steer: Double = 0
    }

    /// After the first car home, the rest have this long.
    static let finishGrace: Double = 30
    /// No race runs longer than this, whatever happens: room for five slow
    /// laps of the longest track.
    static let longest: Double = 600
    /// A car home drives on at no more than this, m/s, out of everyone's way.
    static let cruise: Double = 14

    let track: CarTrack
    let laps: Int
    private(set) var racers: [Racer]
    /// Race seconds the race ends, finished or not.
    private(set) var endsAt: Double = CarSplitRace.longest
    private(set) var over = false

    init(track: CarTrack, laps: Int, names: [String]) {
        self.track = track
        self.laps = max(1, laps)
        racers = names.prefix(4).enumerated().map { seat, name in
            let grid = track.grid(seat)
            return Racer(id: seat, name: name, car: CarState(x: grid.at.x, y: grid.at.y, heading: grid.heading),
                         laps: CarLapCounter(length: track.length, laps: laps, startDistance: track.spot(of: grid.at).distance),
                         ghost: CarGhost(trackId: track.id, laps: max(1, laps), name: name))
        }
    }

    /// The lane a demo pilot keeps to, metres right of the middle line: the
    /// side of the grid its car starts on.
    static func lane(_ seat: Int, on track: CarTrack) -> Double {
        (seat % 2 == 0 ? -1.0 : 1.0) * track.width * 0.2
    }

    /// Drive every car `dt` seconds, ending `time` race seconds in: `holds`
    /// by seat (or the demo's pilots when `autopilot`), then cars against
    /// cars, then laps. The step is cut into the physics' own small steps so
    /// two cars closing fast cannot jump through each other between frames.
    @discardableResult
    mutating func step(holds: [CarSplitHold], autopilot: Bool, dt: Double, time: Double) -> CarSplitEvents {
        var events = CarSplitEvents()
        guard !over, dt > 0 else { return events }
        let dt = min(dt, 0.25)
        var inputs: [CarInput] = []
        for index in racers.indices {
            let racer = racers[index]
            if racer.laps.finished || autopilot {
                var input = CarAutopilot.input(for: racer.car, on: track, lane: Self.lane(racer.id, on: track))
                if racer.laps.finished {
                    input.throttle = racer.car.speed > Self.cruise ? -0.4 : min(input.throttle, 0.3)
                    input.boost = false
                }
                inputs.append(input)
            } else {
                let held = index < holds.count ? holds[index] : CarSplitHold()
                var input = held.input
                racers[index].steer += (input.steer - racer.steer) * min(1, dt * 11)
                input.steer = racers[index].steer
                inputs.append(input)
            }
        }

        var left = dt
        while left > 1e-9 {
            let h = min(left, CarPhysics.maxStep)
            for index in racers.indices {
                if let hit = CarPhysics.step(&racers[index].car, input: inputs[index], track: track, dt: h) {
                    events.hardest = max(events.hardest, hit.impact)
                }
            }
            // A car home is out of the race: it drives through the others.
            for i in racers.indices where !racers[i].laps.finished {
                for j in racers.indices where j > i && !racers[j].laps.finished {
                    var a = racers[i].car, b = racers[j].car
                    if let bump = CarCollision.pair(&a, &b) { events.hardest = max(events.hardest, bump.impact) }
                    racers[i].car = a
                    racers[j].car = b
                }
            }
            left -= h
        }

        var home = racers.filter { $0.laps.finished }.count
        // In place, not copied out and back: a copy would copy the whole
        // recorded run each time a sample is added.
        for index in racers.indices where !racers[index].laps.finished {
            let before = racers[index].laps.splits.count
            let car = racers[index].car
            racers[index].laps.update(distance: track.spot(of: car.position).distance, time: time)
            racers[index].ghost.record(car, raced: racers[index].laps.raced, at: time)
            if racers[index].laps.finished {
                racers[index].ghost.time = racers[index].laps.finishTime
                events.finished.append(racers[index].id)
                home += 1
                // The first home starts the clock on everyone else.
                if home == 1 { endsAt = min(endsAt, time + Self.finishGrace) }
            } else if racers[index].laps.splits.count > before {
                events.lapped.append(racers[index].id)
            }
        }
        if home == racers.count || time >= endsAt { over = true }
        return events
    }

    /// End the race now: whoever is not home did not finish.
    mutating func stop() { over = true }

    /// Put seat `seat`'s car somewhere else, as it is: how a test lines up a knock.
    mutating func move(_ seat: Int, to car: CarState) {
        guard let index = racers.firstIndex(where: { $0.id == seat }) else { return }
        racers[index].car = car
    }

    /// Finishers by time, then everyone else by how far they got.
    var order: [Racer] {
        racers.sorted { a, b in
            switch (a.laps.finishTime, b.laps.finishTime) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil) where a.laps.raced != b.laps.raced: return a.laps.raced > b.laps.raced
            default: return a.id < b.id
            }
        }
    }

    /// Where seat `seat` is running (1 is first).
    func place(of seat: Int) -> Int {
        (order.firstIndex { $0.id == seat } ?? 0) + 1
    }

    /// The table: the entry ids are seats, for the colours.
    var entries: [CarRaceEntry] {
        order.map { CarRaceEntry(id: "\($0.id)", name: $0.name, time: $0.laps.finishTime, bestLap: $0.laps.bestLap) }
    }
}

/// One player's part of a split screen, in points from the top left.
struct CarSplitPane: Equatable {
    let seat: Int
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    /// Drawn upside down, for a player across the table at the far end.
    let turned: Bool

    func contains(_ p: CarVec) -> Bool {
        p.x >= x && p.x < x + width && p.y >= y && p.y < y + height
    }
}

/// Where each player's part of the screen is, and which of their sides a
/// finger is on: the outer `steerShare` of each side steers, and the strip
/// down the middle between them boosts.
///
/// Upright (taller than wide), the screen is cut across: two players get the
/// bottom and top halves; three get the bottom two quarters and the whole top
/// half; four get a quarter each. With `facing` — the phone flat on a table
/// between players sitting opposite — the top row is turned round to face the
/// far end. Wider than tall, two or three players sit side by side in
/// columns and four in quarters, all the right way up.
enum CarSplitLayout {
    /// How much of a part's width each steering side takes; the rest, down
    /// the middle, is the boost.
    static let steerShare = 0.36

    static func panes(players: Int, width: Double, height: Double, facing: Bool) -> [CarSplitPane] {
        let n = min(max(players, 1), 4)
        let w = max(0, width), h = max(0, height)
        func pane(_ seat: Int, _ x: Double, _ y: Double, _ pw: Double, _ ph: Double, turned: Bool = false) -> CarSplitPane {
            CarSplitPane(seat: seat, x: x, y: y, width: pw, height: ph, turned: turned)
        }
        if n == 1 { return [pane(0, 0, 0, w, h)] }
        if w > h {
            if n <= 3 {
                let pw = w / Double(n)
                return (0..<n).map { pane($0, Double($0) * pw, 0, pw, h) }
            }
            return [pane(0, 0, h / 2, w / 2, h / 2), pane(1, w / 2, h / 2, w / 2, h / 2),
                    pane(2, 0, 0, w / 2, h / 2), pane(3, w / 2, 0, w / 2, h / 2)]
        }
        let half = h / 2
        switch n {
        case 2:
            return [pane(0, 0, half, w, half), pane(1, 0, 0, w, half, turned: facing)]
        case 3:
            return [pane(0, 0, half, w / 2, half), pane(1, w / 2, half, w / 2, half),
                    pane(2, 0, 0, w, half, turned: facing)]
        default:
            // Turned round, the top-right quarter is on the far players' left.
            let (far2, far3) = facing ? (w / 2, 0.0) : (0.0, w / 2)
            return [pane(0, 0, half, w / 2, half), pane(1, w / 2, half, w / 2, half),
                    pane(2, far2, 0, w / 2, half, turned: facing), pane(3, far3, 0, w / 2, half, turned: facing)]
        }
    }

    /// What every player is holding, by seat, from where the fingers are: a
    /// finger in a player's part counts on their left or right side (or the
    /// boost between) as THEY see it, so a turned pane's sides are swapped on
    /// the screen.
    static func holds(touches: [CarVec], panes: [CarSplitPane], players: Int) -> [CarSplitHold] {
        var out = Array(repeating: CarSplitHold(), count: max(0, players))
        for touch in touches {
            guard let pane = panes.first(where: { $0.contains(touch) }), pane.seat < out.count else { continue }
            var across = pane.width > 0 ? (touch.x - pane.x) / pane.width : 0.5
            if pane.turned { across = 1 - across }
            if across < steerShare {
                out[pane.seat].left = true
            } else if across >= 1 - steerShare {
                out[pane.seat].right = true
            } else {
                out[pane.seat].boost = true
            }
        }
        return out
    }
}
