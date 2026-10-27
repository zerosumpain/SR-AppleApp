import Foundation

/// Car Race phone to phone, over "Play nearby": two to four cars on the same
/// track, no internet.
///
/// Each phone drives its OWN car: the physics runs on the phone at the
/// display's rate, because a car steered through a round trip to the host
/// would feel like driving through treacle. The host is the referee of time
/// and the noticeboard: it counts everyone down to the same start, takes each
/// phone's position (about eight times a second) and hands everyone the
/// latest of everybody's, and takes each finish time. Cars pass through each
/// other — they are ghosts to one another — so a slow link can never cause a
/// crash that one phone saw and another did not.
///
/// Every time a phone sends is RACE SECONDS: host-clock seconds since
/// `startsAt`, worked out with the clock the room hands every guest.
enum CarRaceNearbyRules: OfflineGameRules {
    static let laps = 3
    /// The countdown before the lights go out, seconds.
    static let countdown: Double = 5
    /// After the first car finishes, the rest have this long.
    static let finishGrace: Double = 30
    /// No race runs longer than this, whatever happens.
    static let longest: Double = 360
    /// A finish time a phone's clock may be ahead of the host's by.
    static let clockSlack: Double = 1.5
    /// Faster than this, all race, is not driving: m/s.
    static let fastest: Double = 60

    static let info = OfflineGameInfo(
        id: "car-race",
        title: "Car Race",
        blurb: "Tilt to steer a little racing car round the track. Three laps, first home wins.",
        category: .skill,
        minPlayers: 2,
        maxPlayers: 4,
        symbol: "car.fill",
        howToPlay: [
            "Hold your phone like a steering wheel and tilt it to steer.",
            "The car accelerates by itself; hold Brake for the bends, and to drift.",
            "Three laps. The lap only counts going the right way round.",
            "Cars pass through each other, so nobody can be knocked off.",
            "First home wins. Everyone else has \(Int(finishGrace)) seconds to finish."
        ]
    )

    // MARK: - State

    enum Phase: String, Codable, Equatable {
        case countdown, racing, over
    }

    /// One car as the host last heard of it.
    struct Racer: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        let seat: Int
        var x: Double
        var y: Double
        var heading: Double
        /// Metres driven round since the start line.
        var raced: Double = 0
        var lap: Int = 1
        /// Race seconds of the last position taken.
        var at: Double = -1
        /// Race seconds at the finish.
        var finish: Double?
        var bestLap: Double?
        var away = false
    }

    struct State: Codable, Equatable {
        var trackId: String
        var laps: Int
        var phase: Phase = .countdown
        /// Host clock: the lights go out.
        var startsAt: Double
        /// Host clock: the race ends now, finished or not.
        var endsAt: Double
        var racers: [Racer]
    }

    enum Action: Codable, Equatable {
        /// Where my car is, `at` race seconds.
        case position(x: Double, y: Double, heading: Double, raced: Double, lap: Int, at: Double)
        /// I crossed the line for the last time `time` race seconds in.
        case finish(time: Double, bestLap: Double?)
    }

    struct PlayerView: Codable, Equatable {
        let trackId: String
        let laps: Int
        let phase: Phase
        let startsAt: Double
        let endsAt: Double
        let racers: [Racer]
    }

    // MARK: - Rules

    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State {
        let track = rng.pick(CarTrack.all) ?? .paddock
        let racers = players.enumerated().map { seat, player -> Racer in
            let slot = track.grid(seat)
            return Racer(id: player.id, name: player.name, seat: seat, x: slot.at.x, y: slot.at.y, heading: slot.heading)
        }
        let startsAt = now + countdown
        return State(trackId: track.id, laps: laps, startsAt: startsAt, endsAt: startsAt + longest, racers: racers)
    }

    static func apply(_ action: Action, by playerId: String, to state: inout State, now: Double, rng: inout OfflineRNG) throws {
        guard let index = state.racers.firstIndex(where: { $0.id == playerId }) else {
            throw OfflineRefusal("You are not in this race.")
        }
        guard state.phase != .over else { throw OfflineRefusal("The race is over.") }
        let raceNow = now - state.startsAt
        switch action {
        case let .position(x, y, heading, raced, lap, at):
            // Late or early news is dropped quietly: positions are a stream,
            // and a stale one is simply not the latest.
            guard state.racers[index].finish == nil, at > state.racers[index].at, at <= raceNow + clockSlack else { return }
            guard [x, y, heading, raced].allSatisfy({ $0.isFinite }) else { return }
            state.racers[index].x = x
            state.racers[index].y = y
            state.racers[index].heading = heading
            state.racers[index].raced = raced
            state.racers[index].lap = max(1, min(lap, state.laps))
            state.racers[index].at = at
            state.racers[index].away = false
        case let .finish(time, bestLap):
            guard state.phase == .racing else { throw OfflineRefusal("The race has not started yet.") }
            guard state.racers[index].finish == nil else { return }
            let length = CarTrack.named(state.trackId)?.length ?? 0
            let quickest = length * Double(state.laps) / fastest
            guard time.isFinite, time >= quickest, time <= raceNow + clockSlack else {
                throw OfflineRefusal("That finish time doesn't add up.")
            }
            state.racers[index].finish = time
            state.racers[index].bestLap = bestLap.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            state.racers[index].lap = state.laps
            state.racers[index].raced = max(state.racers[index].raced, length * Double(state.laps))
            // The first home starts the clock on everyone else.
            if state.racers.filter({ $0.finish != nil }).count == 1 {
                state.endsAt = min(state.endsAt, now + finishGrace)
            }
            settle(&state)
        }
    }

    static func tick(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        if state.phase == .countdown, now >= state.startsAt { state.phase = .racing }
        if state.phase == .racing, now >= state.endsAt { state.phase = .over }
        settle(&state)
    }

    static func view(of state: State, for playerId: String?) -> PlayerView {
        PlayerView(trackId: state.trackId, laps: state.laps, phase: state.phase,
                   startsAt: state.startsAt, endsAt: state.endsAt, racers: state.racers)
    }

    static func isOver(_ state: State) -> Bool { state.phase == .over }

    /// Finishers by time, then everyone else by how far they got.
    static func standings(_ state: State) -> [OfflineStanding] {
        let order = state.racers.sorted { a, b in
            switch (a.finish, b.finish) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil) where a.raced != b.raced: return a.raced > b.raced
            default: return a.seat < b.seat
            }
        }
        var out: [OfflineStanding] = []
        for (index, racer) in order.enumerated() {
            let tied = index > 0 && racer.finish != nil && racer.finish == order[index - 1].finish
            let rank = tied ? out[index - 1].rank : index + 1
            let laps = racer.finish != nil ? state.laps : max(0, racer.lap - 1)
            var detail: String
            if let finish = racer.finish {
                detail = CarRaceFormat.time(finish)
                if let best = racer.bestLap { detail += " · best lap \(CarRaceFormat.time(best))" }
            } else {
                detail = racer.away ? "Left the race" : "Did not finish · lap \(racer.lap)"
            }
            out.append(OfflineStanding(playerId: racer.id, name: racer.name, rank: rank, score: laps, detail: detail))
        }
        return out
    }

    static func playerLeft(_ playerId: String, state: inout State, now: Double, rng: inout OfflineRNG) {
        guard let index = state.racers.firstIndex(where: { $0.id == playerId }) else { return }
        state.racers[index].away = true
        settle(&state)
    }

    /// Over once nobody still racing is left on the track.
    private static func settle(_ state: inout State) {
        guard state.phase == .racing else { return }
        if state.racers.allSatisfy({ $0.finish != nil || $0.away }) { state.phase = .over }
    }
}
