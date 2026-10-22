import Foundation
import CoreLocation

// Manhunt's wire pieces and the little the phone works out for itself: who
// is where on the map (only what the server chose to send this phone), how
// long until the next ping, whether a fix is fresh enough to send, and the
// sentence for how a hunt ended. The server owns the rules — who may see
// whom, whether a catch is close enough; nothing here decides either.
//
// Decoded whole into `ManhuntState`, read off the same JSON as `GameRoom`
// (`GameRoom.manhunt`), as Chess and Liar's Dice do.
//
// Spec: SR-Main docs/superpowers/specs/2026-10-22-family-games-manhunt.md.

enum ManhuntPhase: String, Equatable {
    case lobby, countdown, headstart, hunt, finished, closed, unknown

    static func from(_ raw: String?) -> ManhuntPhase {
        guard let raw else { return .unknown }
        return ManhuntPhase(rawValue: raw) ?? .unknown
    }

    /// The phases the phone sends its position in. Nowhere else.
    var collectsPositions: Bool { self == .headstart || self == .hunt }
}

enum ManhuntRole: String, Decodable, Equatable {
    case runner, hunter
}

/// One position, as the site sends it.
struct ManhuntFix: Decodable, Equatable {
    let lat: Double
    let lng: Double
    let accuracy: Double
    /// Server epoch ms.
    let at: Double
    /// Outside the play area, by the server's rule.
    let outside: Bool

    init(lat: Double, lng: Double, accuracy: Double = 5, at: Double = 0, outside: Bool = false) {
        self.lat = lat; self.lng = lng; self.accuracy = accuracy; self.at = at; self.outside = outside
    }

    private enum CodingKeys: String, CodingKey { case lat, lng, accuracy, at, outside }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lat = try c.decode(Double.self, forKey: .lat)
        lng = try c.decode(Double.self, forKey: .lng)
        accuracy = (try? c.decodeIfPresent(Double.self, forKey: .accuracy)) ?? 0
        at = (try? c.decodeIfPresent(Double.self, forKey: .at)) ?? 0
        outside = (try? c.decodeIfPresent(Bool.self, forKey: .outside)) ?? false
    }

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}

struct ManhuntArea: Decodable, Equatable {
    let lat: Double
    let lng: Double
    let radiusM: Double

    var centre: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}

/// A player as the game sees them: role and, when this phone may see it, a fix.
struct ManhuntSeat: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let status: String
    let seated: Bool
    let role: ManhuntRole?
    let fix: ManhuntFix?

    private enum CodingKeys: String, CodingKey { case id, name, status, seated, role, fix }

    init(id: String, name: String, status: String = "joined", seated: Bool = true, role: ManhuntRole?, fix: ManhuntFix?) {
        self.id = id; self.name = name; self.status = status; self.seated = seated; self.role = role; self.fix = fix
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Someone"
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "joined"
        seated = (try? c.decodeIfPresent(Bool.self, forKey: .seated)) ?? false
        role = (try? c.decodeIfPresent(ManhuntRole.self, forKey: .role)) ?? nil
        fix = (try? c.decodeIfPresent(ManhuntFix.self, forKey: .fix)) ?? nil
    }
}

/// One ping: the runner's fix (sent to hunters), or each hunter's (sent to the runner).
struct ManhuntPing: Decodable, Equatable {
    struct HunterFix: Decodable, Equatable {
        let id: String
        let fix: ManhuntFix?
    }

    let at: Double
    let runner: ManhuntFix?
    let hunters: [HunterFix]

    private enum CodingKeys: String, CodingKey { case at, runner, hunters }

    init(at: Double, runner: ManhuntFix?, hunters: [HunterFix] = []) {
        self.at = at; self.runner = runner; self.hunters = hunters
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        at = (try? c.decodeIfPresent(Double.self, forKey: .at)) ?? 0
        runner = (try? c.decodeIfPresent(ManhuntFix.self, forKey: .runner)) ?? nil
        hunters = (try? c.decodeIfPresent([HunterFix].self, forKey: .hunters)) ?? []
    }
}

struct ManhuntClaim: Decodable, Equatable {
    let hunterId: String
    let deadline: Double
    let quiet: Bool
}

struct ManhuntResult: Decodable, Equatable {
    /// caught | time | runner-left | hunters-left
    let outcome: String
    let catcherId: String?
    let confirmed: Bool

    private enum CodingKeys: String, CodingKey { case outcome, catcherId, confirmed }

    init(outcome: String, catcherId: String?, confirmed: Bool = false) {
        self.outcome = outcome; self.catcherId = catcherId; self.confirmed = confirmed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        outcome = (try? c.decodeIfPresent(String.self, forKey: .outcome)) ?? ""
        catcherId = (try? c.decodeIfPresent(String.self, forKey: .catcherId)) ?? nil
        confirmed = (try? c.decodeIfPresent(Bool.self, forKey: .confirmed)) ?? false
    }
}

struct ManhuntStanding: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let place: Int
    let role: ManhuntRole?
    /// won | team | lost
    let result: String
    let left: Bool

    private enum CodingKeys: String, CodingKey { case id, name, place, role, result, left }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Someone"
        place = (try? c.decodeIfPresent(Int.self, forKey: .place)) ?? 0
        role = (try? c.decodeIfPresent(ManhuntRole.self, forKey: .role)) ?? nil
        result = (try? c.decodeIfPresent(String.self, forKey: .result)) ?? "lost"
        left = (try? c.decodeIfPresent(Bool.self, forKey: .left)) ?? false
    }
}

/// Manhunt's whole side of a room.
struct ManhuntState: Decodable, Equatable {
    let phase: ManhuntPhase
    let myRole: ManhuntRole?
    let area: ManhuntArea?
    let radius: Double
    let minutes: Int
    let rule: String?
    let pingMs: Double
    let headStartMs: Double
    let catchM: Double
    let claimMs: Double
    let outsideLiveMs: Double
    let fixMinGapMs: Double
    let runnerPick: String?
    let runnerId: String?
    let startedAt: Double?
    let huntStartedAt: Double?
    let endsAt: Double?
    let nextPingAt: Double?
    let phaseEndsAt: Double?
    let runnerLiveUntil: Double?
    let runnerQuiet: Bool
    let claim: ManhuntClaim?
    let catchCooldownUntil: Double?
    let pings: [ManhuntPing]
    let seats: [ManhuntSeat]
    let result: ManhuntResult?
    let standings: [ManhuntStanding]?

    private enum CodingKeys: String, CodingKey {
        case phase, myRole, area, radius, minutes, rule, pingMs, headStartMs, catchM, claimMs, outsideLiveMs, fixMinGapMs
        case runnerPick, runnerId, startedAt, huntStartedAt, endsAt, nextPingAt, phaseEndsAt, runnerLiveUntil, runnerQuiet
        case claim, catchCooldownUntil, pings, players, result, standings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func opt<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? {
            (try? c.decodeIfPresent(type, forKey: key)) ?? nil
        }
        phase = ManhuntPhase.from(opt(String.self, .phase))
        myRole = opt(ManhuntRole.self, .myRole)
        area = opt(ManhuntArea.self, .area)
        radius = opt(Double.self, .radius) ?? 500
        minutes = opt(Int.self, .minutes) ?? 30
        rule = opt(String.self, .rule)
        pingMs = opt(Double.self, .pingMs) ?? 180_000
        headStartMs = opt(Double.self, .headStartMs) ?? 120_000
        catchM = opt(Double.self, .catchM) ?? 25
        claimMs = opt(Double.self, .claimMs) ?? 20_000
        outsideLiveMs = opt(Double.self, .outsideLiveMs) ?? 30_000
        fixMinGapMs = opt(Double.self, .fixMinGapMs) ?? 3_000
        runnerPick = opt(String.self, .runnerPick)
        runnerId = opt(String.self, .runnerId)
        startedAt = opt(Double.self, .startedAt)
        huntStartedAt = opt(Double.self, .huntStartedAt)
        endsAt = opt(Double.self, .endsAt)
        nextPingAt = opt(Double.self, .nextPingAt)
        phaseEndsAt = opt(Double.self, .phaseEndsAt)
        runnerLiveUntil = opt(Double.self, .runnerLiveUntil)
        runnerQuiet = opt(Bool.self, .runnerQuiet) ?? false
        claim = opt(ManhuntClaim.self, .claim)
        catchCooldownUntil = opt(Double.self, .catchCooldownUntil)
        pings = opt([ManhuntPing].self, .pings) ?? []
        seats = opt([ManhuntSeat].self, .players) ?? []
        result = opt(ManhuntResult.self, .result)
        standings = opt([ManhuntStanding].self, .standings)
    }

    func seat(_ id: String) -> ManhuntSeat? { seats.first { $0.id == id } }

    /// Everyone in the hunt with a role.
    var inHunt: [ManhuntSeat] { seats.filter { $0.seated && $0.status == "joined" && $0.role != nil } }

    var hunters: [ManhuntSeat] { inHunt.filter { $0.role == .hunter } }

    var lastPing: ManhuntPing? { pings.last }

    /// What the map draws for me: the circle, then every mark the server sent.
    func marks(meId: String) -> [ManhuntMark] {
        var out: [ManhuntMark] = []
        for seat in inHunt {
            guard let fix = seat.fix else { continue }
            let kind: ManhuntMark.Kind = seat.id == meId ? .me : (seat.role == .runner ? .runnerLive : .hunter)
            out.append(ManhuntMark(id: seat.id, name: seat.name, kind: kind, fix: fix))
        }
        if let ping = lastPing {
            if let runnerFix = ping.runner, let runnerId, myRole == .hunter {
                out.append(ManhuntMark(id: "ping-\(runnerId)", name: name(of: runnerId), kind: .runnerPing, fix: runnerFix))
            }
            if myRole == .runner {
                for hunter in ping.hunters {
                    guard let fix = hunter.fix else { continue }
                    out.append(ManhuntMark(id: "ping-\(hunter.id)", name: name(of: hunter.id), kind: .hunterPing, fix: fix))
                }
            }
        }
        return out
    }

    func name(of id: String) -> String { seat(id)?.name ?? standings?.first { $0.id == id }?.name ?? "Someone" }

    /// The sentence for how it ended.
    func outcomeLine(name: (String) -> String) -> String? {
        guard let result else { return nil }
        let runnerName = runnerId.map(name) ?? "The runner"
        return ManhuntRules.outcomeLine(result.outcome, runner: runnerName,
                                        catcher: result.catcherId.map(name), confirmed: result.confirmed)
    }
}

/// One dot on the map.
struct ManhuntMark: Equatable, Identifiable {
    enum Kind: String, Equatable {
        /// Me, wherever I am.
        case me
        /// Another hunter, live (only ever on a hunter's phone).
        case hunter
        /// The runner, live while outside the circle (a hunter's phone).
        case runnerLive
        /// The runner at the last ping (a hunter's phone).
        case runnerPing
        /// A hunter at the last ping (the runner's phone).
        case hunterPing
    }

    let id: String
    let name: String
    let kind: Kind
    let fix: ManhuntFix
}

// MARK: - The new-game sheet

struct ManhuntSettings: Equatable {
    static let radii: [Int] = [250, 500, 1_000, 2_000]
    static let lengths: [Int] = [15, 30, 45, 60]
    static let defaultRadius = 500
    static let defaultMinutes = 30

    var difficulty: GameDifficulty
    var radius: Int = ManhuntSettings.defaultRadius
    var minutes: Int = ManhuntSettings.defaultMinutes

    /// The centre is not sent here: the lobby sends where the host's phone is
    /// (`area`), so a sheet opened indoors does not fix the circle on a guess.
    func createBody(invite: [String]) -> CreateGameBody {
        CreateGameBody(game: GameKind.manhunt.rawValue, difficulty: difficulty.rawValue, invite: invite,
                       radius: radius, minutes: minutes)
    }

    static func radiusLabel(_ m: Int) -> String { ManhuntRules.distance(Double(m)) }

    static func line(radius: Int, minutes: Int) -> String {
        "Anywhere within \(radiusLabel(radius)) of where you stand, for \(minutes) minutes. Three to eight players: one runs, the rest hunt."
    }
}

// MARK: - What the phone works out

enum ManhuntRules {
    /// "250 m", "1 km", "1.5 km".
    static func distance(_ m: Double) -> String {
        guard m.isFinite else { return "–" }
        if m >= 1_000 {
            let km = (m / 100).rounded() / 10
            return km == km.rounded() ? "\(Int(km)) km" : "\(km) km"
        }
        return "\(Int(m.rounded())) m"
    }

    /// "4:05", "0:09". Never negative, never NaN.
    static func clock(_ ms: Double) -> String {
        guard ms.isFinite else { return "0:00" }
        let total = max(0, Int((ms / 1000).rounded(.down)))
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    /// Time left until `until`, from server time `now`.
    static func left(until: Double?, now: Double?) -> Double? {
        guard let until, let now, until.isFinite, now.isFinite else { return nil }
        return max(0, until - now)
    }

    /// Metres between two points (haversine) — for the phone's own "you are outside" line.
    static func metres(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let r = 6_371_000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLng = (b.longitude - a.longitude) * .pi / 180
        let h = pow(sin(dLat / 2), 2) + cos(a.latitude * .pi / 180) * cos(b.latitude * .pi / 180) * pow(sin(dLng / 2), 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }

    /// A closed ring of points round `centre`, for the map's boundary.
    static func circle(centre: CLLocationCoordinate2D, radiusM: Double, points: Int = 72) -> [CLLocationCoordinate2D] {
        guard radiusM.isFinite, radiusM > 0, points >= 3 else { return [] }
        let latStep = radiusM / 111_195
        let lngStep = radiusM / (111_195 * max(0.01, cos(centre.latitude * .pi / 180)))
        var ring = (0..<points).map { i -> CLLocationCoordinate2D in
            let t = Double(i) / Double(points) * 2 * .pi
            return CLLocationCoordinate2D(latitude: centre.latitude + latStep * sin(t), longitude: centre.longitude + lngStep * cos(t))
        }
        ring.append(ring[0])
        return ring
    }

    /// Whether a new fix is worth sending: real, sharp enough to mean
    /// something, newer than the last one sent, and not sooner than the
    /// server's gap (it would only be ignored).
    static func shouldSend(accuracy: Double, ageSeconds: Double, sinceLastSentMs: Double?, minGapMs: Double) -> Bool {
        guard accuracy.isFinite, accuracy >= 0, accuracy <= 200 else { return false }
        guard ageSeconds.isFinite, ageSeconds <= 30 else { return false }
        if let since = sinceLastSentMs, since.isFinite, since < minGapMs { return false }
        return true
    }

    static func outcomeLine(_ outcome: String, runner: String, catcher: String?, confirmed: Bool) -> String {
        switch outcome {
        case "caught":
            let by = catcher ?? "A hunter"
            let whom = runner == "You" ? "you" : runner
            return confirmed ? "\(by) caught \(whom)." : "\(by) caught \(whom) — the catch stood after 20 seconds."
        case "time": return "Time's up — \(runner) got away."
        case "runner-left": return "\(runner) left the game — the hunters win it."
        case "hunters-left": return "Every hunter left — \(runner) \(runner == "You" ? "win" : "wins") it."
        default: return "Game over."
        }
    }

    /// The headline while hunting, for my role.
    static func headline(role: ManhuntRole?, live: Bool, claimByMe: Bool, claimOnMe: Bool) -> String {
        if claimOnMe { return "Caught? Own up!" }
        if claimByMe { return "Catch claimed" }
        switch role {
        case .runner?: return live ? "They can see you!" : "Stay hidden"
        case .hunter?: return live ? "The runner is showing" : "Hunt them down"
        case nil: return "Watching"
        }
    }
}
