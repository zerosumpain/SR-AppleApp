import Foundation

// Car Racer+ sessions: a race, a qualifying run or a time trial on one
// circuit. A session owns every car (the player's and the AI's), steps them
// in fixed 1/240 s substeps, knocks them off each other and the walls,
// counts laps and sectors by distance actually driven, polices track
// limits, records the player's lap as a ghost and a speed trace, and ranks
// the field. See the API notes at the top of CarProLogic.swift.

/// What kind of session.
enum CarProSessionKind: String, Codable {
    /// A standing-start race against the AI, outside the career.
    case quickRace
    /// Alone on track from a rolling start, lapping for a best time.
    case timeTrial
    /// Alone on track from a rolling start: timed laps that set the grid.
    case qualifying
    /// A standing-start championship race.
    case championship

    var isRace: Bool { self == .quickRace || self == .championship }
}

/// Someone in a session: a driver and a car.
struct CarProEntrant: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var setup: CarProCarSetup
    /// The AI driving it; nil for the player.
    var driver: CarProDriverProfile?
    /// Livery hue, 0…1.
    var hue: Double
    var number: Int

    var isPlayer: Bool { driver == nil }

    static let playerId = "player"

    static func player(name: String = "You", setup: CarProCarSetup, number: Int = 1) -> CarProEntrant {
        CarProEntrant(id: playerId, name: name, setup: setup, driver: nil, hue: setup.model.hue, number: number)
    }

    static func ai(_ driver: CarProDriverProfile, setup: CarProCarSetup) -> CarProEntrant {
        CarProEntrant(id: driver.id, name: driver.name, setup: setup, driver: driver, hue: driver.hue, number: driver.number)
    }
}

/// How a session is set up.
struct CarProSessionConfig: Equatable {
    var kind: CarProSessionKind
    var trackId: String
    /// Race laps, or timed laps in qualifying; 0 is unlimited (time trial).
    var laps: Int
    /// In grid order, pole first. Exactly one is the player.
    var entrants: [CarProEntrant]
    var assists: CarProAssists
    /// The best lap to race against (time trial and qualifying).
    var ghost: CarProGhost?
    /// Seeds the AI's mistakes.
    var seed: UInt64 = 1
    /// The player's car is driven by the AI throughout (screenshots, tests).
    var autopilot = false

    static func quickRace(track: String, laps: Int, player: CarProEntrant, opponents: [CarProEntrant],
                          assists: CarProAssists, playerSlot: Int? = nil, seed: UInt64 = 1) -> CarProSessionConfig {
        var grid = opponents
        let slot = min(max(0, playerSlot ?? grid.count), grid.count)
        grid.insert(player, at: slot)
        return CarProSessionConfig(kind: .quickRace, trackId: track, laps: max(1, laps), entrants: grid,
                                   assists: assists, seed: seed)
    }

    static func timeTrial(track: String, player: CarProEntrant, assists: CarProAssists,
                          ghost: CarProGhost?) -> CarProSessionConfig {
        CarProSessionConfig(kind: .timeTrial, trackId: track, laps: 0, entrants: [player], assists: assists, ghost: ghost)
    }

    static func qualifying(track: String, player: CarProEntrant, assists: CarProAssists, laps: Int = 2,
                           ghost: CarProGhost? = nil) -> CarProSessionConfig {
        CarProSessionConfig(kind: .qualifying, trackId: track, laps: max(1, laps), entrants: [player],
                            assists: assists, ghost: ghost)
    }
}

/// Where a session is.
enum CarProSessionPhase: Equatable {
    /// The start lights: seconds until they go out.
    case countdown(remaining: Double)
    case racing
    /// The player has taken the flag (or the timed laps are done).
    case finished
}

/// Something that happened during a step, for haptics, sounds and banners.
/// Racer indexes are into `CarProSession.racers`.
enum CarProEvent: Equatable {
    /// A start light came on (1…5).
    case light(Int)
    case lightsOut
    case gearChange(gear: Int)
    case wallHit(racer: Int, impact: Double)
    case contact(racer: Int, other: Int, impact: Double)
    /// A sector done; `delta` is against the racer's best of that sector.
    case sector(racer: Int, sector: Int, time: Double, delta: Double?)
    case lap(racer: Int, lap: Int, time: Double, valid: Bool, personalBest: Bool)
    /// All four wheels off the track for a stretch.
    case trackLimits(racer: Int, strikes: Int)
    case penalty(racer: Int, seconds: Double)
    /// The player's place changed.
    case position(from: Int, to: Int)
    case finished(racer: Int, position: Int)
}

/// One lap's speed trace against distance, for the telemetry chart.
struct CarProTelemetry: Codable, Equatable {
    static let binSize = 10.0
    var lapTime: Double = 0
    /// m/s in each 10 m of the lap.
    var speeds: [Double] = []
    /// 0…1 pedals in each bin.
    var throttle: [Double] = []
    var brake: [Double] = []

    mutating func note(distance: Double, speed: Double, throttle t: Double, brake b: Double) {
        let bin = max(0, Int(distance / Self.binSize))
        guard bin < 2000 else { return }
        while speeds.count <= bin {
            speeds.append(speeds.last ?? speed)
            throttle.append(t)
            brake.append(b)
        }
        speeds[bin] = speed
        throttle[bin] = t
        brake[bin] = b
    }
}

/// A recorded lap to race against: the player's best on a track in a model.
struct CarProGhost: Codable, Equatable {
    struct Sample: Codable, Equatable {
        /// Seconds into the lap.
        var t: Double
        var x: Double
        var y: Double
        var heading: Double
        /// Metres into the lap.
        var d: Double
    }

    var trackId: String
    var model: CarProCarModel
    var lapTime: Double
    var samples: [Sample] = []

    static let interval = 1.0 / 15

    mutating func record(t: Double, at p: CarProVec, heading: Double, distance: Double) {
        if let last = samples.last, t - last.t < Self.interval - 1e-9 { return }
        samples.append(Sample(t: t, x: p.x, y: p.y, heading: heading, d: distance))
    }

    /// Where the ghost was `t` seconds into its lap.
    func pose(at t: Double) -> (position: CarProVec, heading: Double)? {
        guard let first = samples.first, let last = samples.last else { return nil }
        if t <= first.t { return (CarProVec(x: first.x, y: first.y), first.heading) }
        if t >= last.t { return (CarProVec(x: last.x, y: last.y), last.heading) }
        var lo = 0, hi = samples.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if samples[mid].t <= t { lo = mid } else { hi = mid }
        }
        let a = samples[lo], b = samples[hi]
        let f = b.t > a.t ? (t - a.t) / (b.t - a.t) : 0
        let turn = CarProMath.wrap(b.heading - a.heading)
        return (CarProVec(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f), a.heading + turn * f)
    }

    /// When the ghost had come `distance` metres into its lap.
    func time(atDistance distance: Double) -> Double? {
        guard samples.count > 1 else { return nil }
        guard let index = samples.firstIndex(where: { $0.d >= distance }) else { return nil }
        guard index > 0 else { return samples[0].t }
        let a = samples[index - 1], b = samples[index]
        let f = b.d > a.d ? (distance - a.d) / (b.d - a.d) : 0
        return a.t + (b.t - a.t) * f
    }
}

/// One car in a session and its race so far.
struct CarProRacer: Identifiable {
    let entrant: CarProEntrant
    let params: CarProVehicleParams
    /// How fast this car can lap here: the AI's plan, the braking boards.
    let profile: CarProSpeedProfile
    var vehicle: CarProVehicle
    /// Drives AI cars, and the player's after the flag.
    var ai: CarProAI
    /// What the car was asked for this substep.
    var input = CarProInput()
    /// Metres round from the start line (negative on the grid behind it).
    var raced: Double
    var lapsDone = 0
    /// Session time the lap in progress began; nil before timing starts (rolling starts).
    var lapStart: Double?
    var lapTimes: [Double] = []
    var lastLap: Double?
    var bestLap: Double?
    /// No track-limits strike on this lap yet.
    var lapValid = true
    var sector = 0
    var sectorStart: Double?
    /// The lap in progress's sector times so far.
    var sectorTimes: [Double] = []
    var bestSectors: [Double?] = [nil, nil, nil]
    var strikes = 0
    /// Seconds added to the finish time.
    var penalty: Double = 0
    /// Metres made with all four wheels off the track, this excursion.
    var offRun: Double = 0
    var finishTime: Double?
    /// 1-based, updated every step.
    var position = 1
    /// Seconds after lights out before the AI moves off.
    var reaction: Double = 0
    var lastDistance: Double

    var id: String { entrant.id }
    var finished: Bool { finishTime != nil }
    /// The lap being driven, 1-based.
    var lap: Int { lapsDone + 1 }
    /// Metres into the current lap.
    func lapDistance(length: Double) -> Double { raced - Double(lapsDone) * length }
}

/// The numbers a HUD shows for the player.
struct CarProHUD: Equatable {
    var speed: Double
    var gear: String
    var rpm: Double
    var redline: Double
    var limiter: Double
    /// 0…1 lights across the top of the rev bar, all lit at the shift point.
    var shiftLight: Double
    var lap: Int
    /// 0 for unlimited.
    var laps: Int
    var position: Int
    var cars: Int
    var lapTime: Double?
    var lastLap: Double?
    var bestLap: Double?
    /// Against the ghost (or the best lap's pace) at this point in the lap.
    var delta: Double?
    var sector: Int
    var lapValid: Bool
    var strikes: Int
    var penalty: Double
    var tyreTemperatures: [Double]
    var tyreWear: [Double]
    /// −1 cold, 0 in the window, 1 hot, per tyre.
    var tyreState: [Int]
    var tractionActive: Bool
    var absActive: Bool
    var revCut: Bool
    /// Seconds to the car ahead and behind (nil when there is none).
    var gapAhead: Double?
    var gapBehind: Double?
    var nextCorner: String?
}

/// A driver's result.
struct CarProResult: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var isPlayer: Bool
    var model: CarProCarModel
    var position: Int
    var laps: Int
    /// Race time with penalties; nil for a driver who did not finish.
    var time: Double?
    var bestLap: Double?
    var penalty: Double
    /// The time is worked out from the car's pace, not driven (the player
    /// took the flag first).
    var estimated: Bool
}

/// A race, a qualifying run or a time trial.
struct CarProSession {
    let config: CarProSessionConfig
    let track: CarProTrack
    private(set) var racers: [CarProRacer]
    let playerIndex: Int
    private(set) var phase: CarProSessionPhase
    /// Seconds since the lights went out (or since a rolling start began).
    private(set) var time: Double = 0
    /// What happened during the last `step`.
    private(set) var events: [CarProEvent] = []
    /// The best lap's ghost: the config's, replaced by a better lap.
    private(set) var bestGhost: CarProGhost?
    /// Set when the session's driving produced a new best ghost.
    private(set) var newGhost = false
    private(set) var lastTelemetry: CarProTelemetry?
    private(set) var bestTelemetry: CarProTelemetry?
    private var recording: CarProGhost
    private var telemetry = CarProTelemetry()
    private var clock = CarProStepClock()
    private var substeps = 0
    private var traffic: [CarProTraffic] = []
    private var leaderFinished = false
    private var finishOrder = 0
    private var countdownTotal: Double
    /// The AI drives the player's car too (autopilot, or a field with no player).
    private let aiDrivesPlayer: Bool

    static let countdownLength = 3.6
    static let runUp = 160.0

    init(config original: CarProSessionConfig) {
        // A session always has a car in it.
        var config = original
        if config.entrants.isEmpty { config.entrants = [.player(setup: CarProCarSetup(model: .hatch))] }
        self.config = config
        let track = CarProCircuits.track(config.trackId) ?? CarProCircuits.all[0]
        self.track = track
        playerIndex = config.entrants.firstIndex { $0.isPlayer } ?? 0
        var racers: [CarProRacer] = []
        let rolling = !config.kind.isRace
        for (slot, entrant) in config.entrants.enumerated() {
            let params = entrant.setup.params
            let profile = CarProSpeedProfile(track: track, performance: CarProPerformance(params: params))
            var position: CarProVec, heading: Double, distance: Double, speed: Double = 0
            if rolling {
                distance = track.length - Self.runUp
                let i = track.index(at: distance)
                let s = track.samples[i]
                position = s.linePoint
                heading = s.direction
                speed = profile.speeds[i] * 0.7
            } else {
                let g = track.grid(slot)
                position = g.position
                heading = g.heading
                distance = g.distance
            }
            var vehicle = CarProVehicle(params: params, position: position, heading: heading, speed: speed)
            vehicle.trackIndex = track.index(at: distance)
            vehicle.trackDistance = distance
            let driver = entrant.driver ?? CarProDriverProfile(id: entrant.id, name: entrant.name, skill: 0.85,
                                                               aggression: 0.2, number: entrant.number, hue: entrant.hue)
            let ai = CarProAI(profile: driver, seed: config.seed &+ UInt64(slot) &* 7919)
            var racer = CarProRacer(entrant: entrant, params: params, profile: profile, vehicle: vehicle, ai: ai,
                                    raced: distance - track.length, lastDistance: distance)
            racer.position = slot + 1
            racer.reaction = 0.18 + 0.3 * (1 - driver.skill) + 0.05 * Double(slot % 3)
            if !rolling { racer.lapStart = 0; racer.sectorStart = 0 }
            racers.append(racer)
        }
        self.racers = racers
        aiDrivesPlayer = config.autopilot || !config.entrants.contains(where: { $0.isPlayer })
        countdownTotal = config.kind.isRace ? Self.countdownLength : 0
        phase = config.kind.isRace ? .countdown(remaining: Self.countdownLength) : .racing
        bestGhost = config.ghost
        recording = CarProGhost(trackId: track.id, model: config.entrants[playerIndex].setup.model, lapTime: 0)
        traffic = Array(repeating: CarProTraffic(distance: 0, offset: 0, speed: 0), count: racers.count)
    }

    var player: CarProRacer { racers[playerIndex] }

    /// The start lights lit, 0…5 (0 once they are out).
    var lightsLit: Int {
        guard case let .countdown(remaining) = phase else { return 0 }
        let elapsed = countdownTotal - remaining
        return min(5, Int(elapsed / (countdownTotal / 6)) + 1)
    }

    // MARK: - Stepping

    /// Advances the session by `dt` seconds of frame with the player's
    /// `input` (shift taps are spent on the first substep).
    mutating func step(dt: Double, input: CarProInput) {
        events.removeAll(keepingCapacity: true)
        let n = clock.substeps(for: dt)
        var current = input
        for _ in 0..<n {
            substep(current)
            current = current.held
        }
    }

    /// The player gives up: the session ends now and they are not classified.
    mutating func retire() {
        guard phase != .finished else { return }
        phase = .finished
        events.append(.finished(racer: playerIndex, position: racers.count))
    }

    private mutating func substep(_ playerInput: CarProInput) {
        let h = CarProPhysics.dt
        substeps += 1

        // The lights.
        if case let .countdown(remaining) = phase {
            let before = lightsLit
            let next = remaining - h
            if next <= 0 {
                phase = .racing
                time = 0
                events.append(.lightsOut)
            } else {
                phase = .countdown(remaining: next)
                if lightsLit != before { events.append(.light(lightsLit)) }
            }
            for i in racers.indices {
                let input = i == playerIndex && !aiDrivesPlayer ? playerInput : CarProInput()
                racers[i].input = input
                CarProPhysics.step(&racers[i].vehicle, params: racers[i].params, input: input,
                                   assists: assists(for: i), track: track, held: true)
            }
            return
        }
        time += h

        // The AI decides twice per display frame (120 Hz), from the field as it is.
        let think = substeps % 2 == 0
        if think {
            for i in racers.indices {
                let v = racers[i].vehicle
                traffic[i] = CarProTraffic(distance: v.trackDistance, offset: v.trackOffset, speed: v.forwardSpeed)
            }
        }
        for i in racers.indices {
            var input: CarProInput
            let driving = i != playerIndex || aiDrivesPlayer || phase == .finished || racers[i].finished
            if driving {
                if think {
                    if time < racers[i].reaction && config.kind.isRace {
                        racers[i].input = CarProInput()
                    } else {
                        racers[i].input = racers[i].ai.drive(racers[i].vehicle, params: racers[i].params, track: track,
                                                             profile: racers[i].profile, traffic: traffic, skip: i,
                                                             dt: h * 2)
                        if racers[i].finished || (i == playerIndex && phase == .finished) {
                            // The slowing-down lap.
                            racers[i].input.throttle *= 0.45
                        }
                    }
                }
                input = racers[i].input
            } else {
                input = playerInput
                racers[i].input = input
            }
            let result = CarProPhysics.step(&racers[i].vehicle, params: racers[i].params, input: input,
                                            assists: assists(for: i), track: track)
            if result.wallImpact > 1 { events.append(.wallHit(racer: i, impact: result.wallImpact)) }
            if result.shifted && i == playerIndex { events.append(.gearChange(gear: racers[i].vehicle.gear)) }
        }
        collide()
        for i in racers.indices { progress(i) }
        if substeps % 12 == 0 { rank() }
        recordPlayer()
    }

    private func assists(for i: Int) -> CarProAssists {
        if i == playerIndex && !aiDrivesPlayer && phase != .finished { return config.assists }
        return .ai
    }

    /// Cars that touch: pushed apart and bounced, the lighter one more.
    private mutating func collide() {
        let n = racers.count
        guard n > 1 else { return }
        for a in 0..<(n - 1) {
            for b in (a + 1)..<n {
                let pa = racers[a].vehicle.position, pb = racers[b].vehicle.position
                let reach = (racers[a].params.length + racers[b].params.length) / 2 + 0.5
                guard (pa - pb).lengthSquared < reach * reach else { continue }
                var first = racers[a].vehicle, second = racers[b].vehicle
                let impact = CarProCollision.pair(&first, racers[a].params, &second, racers[b].params)
                racers[a].vehicle = first
                racers[b].vehicle = second
                if let impact, impact > 0.8 { events.append(.contact(racer: a, other: b, impact: impact)) }
            }
        }
    }

    /// Laps, sectors and track limits for racer `i`.
    private mutating func progress(_ i: Int) {
        let L = track.length
        var r = racers[i]
        let d = r.vehicle.trackDistance
        let moved = track.gap(from: r.lastDistance, to: d)
        r.lastDistance = d
        r.raced += moved

        // Rolling starts: the clock starts at the line.
        if r.lapStart == nil && r.raced >= 0 {
            r.lapStart = time
            r.sectorStart = time
            r.sector = 0
            if i == playerIndex { startRecording() }
        }

        // Track limits: a stretch made with every wheel off the track.
        if r.vehicle.offTrack {
            if moved > 0 { r.offRun += moved }
        } else if r.offRun > 0 {
            if r.offRun > 12 && r.lapStart != nil && !r.finished {
                r.strikes += 1
                r.lapValid = false
                events.append(.trackLimits(racer: i, strikes: r.strikes))
                if config.kind.isRace && r.strikes % 3 == 0 {
                    r.penalty += 5
                    events.append(.penalty(racer: i, seconds: 5))
                }
            }
            r.offRun = 0
        }

        guard let lapStart = r.lapStart, !r.finished else { racers[i] = r; return }
        let into = r.raced - Double(r.lapsDone) * L

        // Sectors 1 → 2 → 3.
        if r.sector < 2 && into >= track.sectorStarts[r.sector] && into < L {
            let started = r.sectorStart ?? lapStart
            let t = time - started
            let best = r.bestSectors[r.sector]
            r.sectorTimes.append(t)
            events.append(.sector(racer: i, sector: r.sector, time: t, delta: best.map { t - $0 }))
            if r.lapValid && t < (best ?? .infinity) { r.bestSectors[r.sector] = t }
            r.sector += 1
            r.sectorStart = time
        }

        // The line.
        if into >= L {
            let lapTime = time - lapStart
            let valid = r.lapValid
            let s3 = time - (r.sectorStart ?? lapStart)
            if valid && s3 < (r.bestSectors[2] ?? .infinity) { r.bestSectors[2] = s3 }
            r.lapsDone += 1
            r.lapTimes.append(lapTime)
            r.lastLap = lapTime
            let personalBest = valid && lapTime < (r.bestLap ?? .infinity)
            if personalBest { r.bestLap = lapTime }
            events.append(.lap(racer: i, lap: r.lapsDone, time: lapTime, valid: valid, personalBest: personalBest))
            r.lapStart = time
            r.sectorStart = time
            r.sector = 0
            r.sectorTimes = []
            r.lapValid = true
            if i == playerIndex { finishLap(time: lapTime, valid: valid) }

            // The flag.
            if config.kind.isRace && (r.lapsDone >= config.laps || leaderFinished) {
                r.finishTime = time
                leaderFinished = true
                finishOrder += 1
                racers[i] = r
                rank()
                events.append(.finished(racer: i, position: racers[i].position))
                if i == playerIndex { phase = .finished }
                return
            }
            if config.kind == .qualifying && i == playerIndex && r.lapsDone >= config.laps {
                r.finishTime = time
                racers[i] = r
                phase = .finished
                events.append(.finished(racer: i, position: 1))
                return
            }
        }
        racers[i] = r
    }

    /// Places: the finished by finishing order, then by laps and metres raced.
    private mutating func rank() {
        let order = racers.indices.sorted { a, b in
            let ra = racers[a], rb = racers[b]
            switch (ra.finishTime, rb.finishTime) {
            case let (x?, y?):
                if ra.lapsDone != rb.lapsDone { return ra.lapsDone > rb.lapsDone }
                if x != y { return x < y }
                return a < b
            case (.some, nil): return true
            case (nil, .some): return false
            default:
                if ra.raced != rb.raced { return ra.raced > rb.raced }
                return a < b
            }
        }
        let before = racers[playerIndex].position
        for (place, index) in order.enumerated() { racers[index].position = place + 1 }
        let after = racers[playerIndex].position
        if after != before && phase == .racing && config.kind.isRace {
            events.append(.position(from: before, to: after))
        }
    }

    // MARK: - The player's lap: ghost and telemetry

    private mutating func startRecording() {
        recording = CarProGhost(trackId: track.id, model: player.entrant.setup.model, lapTime: 0)
        telemetry = CarProTelemetry()
    }

    private mutating func recordPlayer() {
        let p = racers[playerIndex]
        guard let start = p.lapStart, phase != .finished else { return }
        let t = time - start
        let into = p.lapDistance(length: track.length)
        recording.record(t: t, at: p.vehicle.position, heading: p.vehicle.heading, distance: into)
        if substeps % 8 == 0 {
            telemetry.note(distance: into, speed: p.vehicle.speed, throttle: p.vehicle.throttle, brake: p.vehicle.brake)
        }
    }

    private mutating func finishLap(time lapTime: Double, valid: Bool) {
        telemetry.lapTime = lapTime
        lastTelemetry = telemetry
        recording.lapTime = lapTime
        if valid && lapTime < (bestGhost?.lapTime ?? .infinity) {
            bestGhost = recording
            bestTelemetry = telemetry
            newGhost = true
        } else if valid && bestTelemetry == nil {
            bestTelemetry = telemetry
        }
        startRecording()
    }

    // MARK: - Reading

    /// Where the best lap's ghost is now, at the player's lap time.
    var ghostPose: (position: CarProVec, heading: Double)? {
        guard let ghost = bestGhost, let start = player.lapStart, phase != .finished else { return nil }
        return ghost.pose(at: time - start)
    }

    /// Seconds up (negative) or down on the best lap at this point of the lap.
    var deltaToBest: Double? {
        guard let ghost = bestGhost, let start = player.lapStart else { return nil }
        let into = player.lapDistance(length: track.length)
        guard into > 20, let then = ghost.time(atDistance: into) else { return nil }
        return (time - start) - then
    }

    var hud: CarProHUD {
        let p = player
        let v = p.vehicle
        let params = p.params
        let shiftStart = params.redline - 1400
        let tyres = v.wheels
        let compound = params.compound
        let states = tyres.map { w -> Int in
            if w.temperature < compound.optimalTemperature - compound.window * 0.6 { return -1 }
            if w.temperature > compound.optimalTemperature + compound.window * 0.6 { return 1 }
            return 0
        }
        var ahead: Double?, behind: Double?
        for other in racers where other.id != p.id {
            let gap = other.raced - p.raced
            let speed = max(8, v.speed)
            if other.position == p.position - 1 { ahead = gap / speed }
            if other.position == p.position + 1 { behind = -gap / speed }
        }
        let lapTime = p.lapStart.map { time - $0 }
        return CarProHUD(speed: v.speed, gear: v.gearLabel, rpm: v.rpm, redline: params.redline,
                         limiter: params.limiter,
                         shiftLight: CarProMath.clamp((v.rpm - shiftStart) / 1400, 0, 1),
                         lap: config.laps > 0 ? min(p.lap, config.laps) : p.lap, laps: config.laps,
                         position: p.position,
                         cars: racers.count, lapTime: phase == .finished ? p.lastLap : lapTime,
                         lastLap: p.lastLap, bestLap: p.bestLap, delta: deltaToBest, sector: p.sector,
                         lapValid: p.lapValid, strikes: p.strikes, penalty: p.penalty,
                         tyreTemperatures: tyres.map(\.temperature), tyreWear: tyres.map(\.wear),
                         tyreState: states, tractionActive: v.tractionActive, absActive: v.absActive,
                         revCut: v.revCut, gapAhead: ahead, gapBehind: behind,
                         nextCorner: track.corner(ahead: v.trackDistance)?.name)
    }

    /// The braking boards for the player's car.
    var brakeMarkers: [CarProBrakeMarker] { player.profile.brakeMarkers }

    /// The classification. Drivers still running when the player took the
    /// flag are given the time their pace would have brought them home in.
    var results: [CarProResult] {
        let L = track.length
        var rows: [CarProResult] = racers.map { r in
            var t = r.finishTime.map { $0 + r.penalty }
            var estimated = false
            var laps = r.lapsDone
            if t == nil && config.kind.isRace && !(r.entrant.isPlayer && phase == .finished && !r.finished) {
                let target = Double(config.laps) * L
                let remaining = max(0, target - r.raced)
                let pace = r.bestLap.map { L / $0 } ?? max(10, r.profile.performance.topSpeed * 0.45)
                t = time + remaining / max(5, pace) + r.penalty
                estimated = true
                laps = config.laps
            }
            if config.kind.isRace == false { t = r.bestLap }
            return CarProResult(id: r.id, name: r.entrant.name, isPlayer: r.entrant.isPlayer, model: r.entrant.setup.model,
                                position: 0, laps: laps, time: t, bestLap: r.bestLap, penalty: r.penalty,
                                estimated: estimated)
        }
        rows.sort { a, b in
            if a.laps != b.laps && a.time != nil && b.time != nil { return a.laps > b.laps }
            switch (a.time, b.time) {
            case let (x?, y?): return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.name < b.name
            }
        }
        for i in rows.indices { rows[i].position = i + 1 }
        return rows
    }
}

/// Cars touching: the player's box against the other's nose and tail
/// circles (as in Car Race), pushed apart and bounced with some restitution,
/// each car taking the share its weight earns. Damage-free, but it costs speed.
enum CarProCollision {
    static let restitution = 0.35

    /// The other car's nose and tail circles' centres and radius.
    private static func circles(_ v: CarProVehicle, _ p: CarProVehicleParams) -> (CarProVec, CarProVec, Double) {
        let radius = p.width / 2
        let along = v.forward * (p.length / 2 - radius)
        return (v.position + along, v.position - along, radius)
    }

    /// Box (`a`) against circle: the push that moves the box out.
    private static func box(_ v: CarProVehicle, _ p: CarProVehicleParams, circle: CarProVec, radius: Double)
        -> (normal: CarProVec, depth: Double)? {
        let forward = v.forward, right = v.right
        let d = circle - v.position
        let lx = d.dot(forward), ly = d.dot(right)
        let hl = p.length / 2, hw = p.width / 2
        let qx = CarProMath.clamp(lx, -hl, hl), qy = CarProMath.clamp(ly, -hw, hw)
        let gap = CarProVec(x: lx - qx, y: ly - qy)
        let distance = gap.length
        if distance > 1e-9 {
            guard distance < radius else { return nil }
            let local = gap * (-1 / distance)
            return (forward * local.x + right * local.y, radius - distance)
        }
        let overX = hl - abs(lx), overY = hw - abs(ly)
        if overX < overY { return (forward * (lx > 0 ? -1 : 1), overX + radius) }
        return (right * (ly > 0 ? -1 : 1), overY + radius)
    }

    /// Two cars: separated and bounced. Returns the closing speed, or nil.
    @discardableResult
    static func pair(_ a: inout CarProVehicle, _ pa: CarProVehicleParams,
                     _ b: inout CarProVehicle, _ pb: CarProVehicleParams) -> Double? {
        let (nose, tail, radius) = circles(b, pb)
        var deepest: (normal: CarProVec, depth: Double)?
        for c in [nose, tail] {
            if let hit = box(a, pa, circle: c, radius: radius), hit.depth > (deepest?.depth ?? 1e-6) { deepest = hit }
        }
        guard let hit = deepest else { return nil }
        let total = pa.mass + pb.mass
        let shareA = pb.mass / total, shareB = pa.mass / total
        a.position = a.position + hit.normal * (hit.depth * shareA)
        b.position = b.position - hit.normal * (hit.depth * shareB)
        let va = a.velocity, vb = b.velocity
        let closing = (va - vb).dot(hit.normal)
        guard closing < 0 else { return nil }
        let impulse = -(1 + restitution) * closing
        set(&a, velocity: va + hit.normal * (impulse * shareA))
        set(&b, velocity: vb - hit.normal * (impulse * shareB))
        a.yawRate *= 0.85
        b.yawRate *= 0.85
        return -closing
    }

    private static func set(_ v: inout CarProVehicle, velocity: CarProVec) {
        v.forwardSpeed = velocity.dot(v.forward)
        v.lateralSpeed = velocity.dot(v.right)
    }
}
