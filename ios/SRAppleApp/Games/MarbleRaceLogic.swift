import Foundation
import SwiftUI

// Marble Race — a family room around one Marbler race (SR-Main
// `src/lib/games/marble-race.ts`). The site runs no physics: it deals a run
// seed and a start time, and every phone runs that same deterministic race in
// Marbler's web view (`MarblerScreen.swift`), stepped to the room's clock.
// Each phone reports the finish order it saw; the room settles on the order
// most phones agree on. Everyone backs one marble, no two the same; whoever
// backed the best-placed marble wins.

/// Marble Race's side of a room, read from the same JSON as `GameRoom`.
struct MarbleRaceState: Decodable, Equatable {
    struct Course: Codable, Equatable {
        let id: String
        let name: String
        let marbles: Int
        let seconds: Int
    }

    struct Race: Decodable, Equatable {
        let seed: UInt32
        /// Epoch ms of step 0, on the server's clock.
        let startAt: Double
    }

    struct Result: Decodable, Equatable {
        /// Marble indices, first home first. Nil when no phone reported.
        let order: [Int]?
        let disputed: Bool
    }

    struct Seat: Decodable, Equatable {
        let id: String
        let marble: Int?
        let reported: Bool
    }

    /// Marble Race's own phase (the shared `GamePhase` has no picking or racing).
    enum Phase: String {
        case lobby, picking, racing, finished, closed, unknown
    }

    let phase: Phase
    let course: Course
    let race: Race?
    let result: Result?
    let seats: [Seat]

    private enum CodingKeys: String, CodingKey { case phase, course, race, result, players }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = Phase(rawValue: (try? c.decode(String.self, forKey: .phase)) ?? "") ?? .unknown
        course = try c.decode(Course.self, forKey: .course)
        race = (try? c.decodeIfPresent(Race.self, forKey: .race)) ?? nil
        result = (try? c.decodeIfPresent(Result.self, forKey: .result)) ?? nil
        seats = (try? c.decodeIfPresent([Seat].self, forKey: .players)) ?? []
    }

    func marble(of playerId: String) -> Int? { seats.first { $0.id == playerId }?.marble }

    /// Who backs marble `m`, if anyone.
    func backer(of m: Int) -> String? { seats.first { $0.marble == m }?.id }

    /// Where marble `m` finished (1 = first), once the race is settled.
    func place(of m: Int) -> Int? { result?.order?.firstIndex(of: m).map { $0 + 1 } }
}

/// Marbler's marble colours, in index order: marble i wears colour i. A copy
/// of `MARBLE_COLOURS` in Marbler's `src/render/palette.ts` — change both.
enum MarblePalette {
    static let colours: [(name: String, hex: UInt32)] = [
        ("Red", 0xe6194b), ("Blue", 0x4363d8), ("Yellow", 0xffe119), ("Orange", 0xf58231), ("Purple", 0x9b4dca),
        ("Cyan", 0x42d4f4), ("Magenta", 0xf032e6), ("White", 0xf4f4f4), ("Pink", 0xfabed4), ("Teal", 0x469990),
        ("Brown", 0x9a6324), ("Navy", 0x2a3a8c), ("Lime", 0xbfef45), ("Coral", 0xff7f50), ("Lavender", 0xdcbeff),
        ("Olive", 0x8a8a1e), ("Mint", 0xaaffc3), ("Maroon", 0x9e2a3a), ("Gold", 0xd4a017), ("Sky", 0x8fc7ff),
        ("Rose", 0xff6f91), ("Indigo", 0x6a5acd), ("Silver", 0xb0b8c4), ("Apricot", 0xffd8b1), ("Plum", 0x8e4585),
        ("Jade", 0x00a86b), ("Rust", 0xb7410e), ("Steel", 0x5f8ca8), ("Charcoal", 0x5a606c), ("Ocean", 0x1f7a8c),
    ]

    static func name(_ m: Int) -> String { colours[m % colours.count].name }

    static func color(_ m: Int) -> Color {
        let hex = colours[m % colours.count].hex
        return Color(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }

    /// Light enough that a dark mark reads on it.
    static func isLight(_ m: Int) -> Bool {
        let hex = colours[m % colours.count].hex
        let y = 0.299 * Double((hex >> 16) & 0xff) + 0.587 * Double((hex >> 8) & 0xff) + 0.114 * Double(hex & 0xff)
        return y > 150
    }
}

/// Marbler's course pack, read from the public site: what the host can pick.
struct MarblerPack: Decodable {
    struct Entry: Decodable, Identifiable, Hashable {
        let id: String
        let name: String
        let layout: String
        let marbles: Int
        let seconds: Int
    }

    let courses: [Entry]

    static let url = URL(string: "https://strangeramblings.com/projects/marbler/courses/index.json")!

    static func load() async throws -> MarblerPack {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(MarblerPack.self, from: data)
    }

    /// Today's course: the same pick the page makes (one per day, the same for everyone on the date).
    func today(_ date: Date = Date()) -> Entry? {
        guard !courses.isEmpty else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let midnight = utc.date(from: parts) else { return courses.first }
        let day = Int(floor(midnight.timeIntervalSince1970 / 86_400))
        return courses[((day % courses.count) + courses.count) % courses.count]
    }
}

/// What the new-game sheet sends for a Marble Race.
struct MarbleRaceSettings: Equatable {
    var difficulty: GameDifficulty
    var course: MarblerPack.Entry?

    func createBody(invite: [String]) -> CreateGameBody {
        var body = CreateGameBody(game: GameKind.marbleRace.rawValue, difficulty: difficulty.rawValue, invite: invite)
        if let course {
            body.course = MarbleRaceState.Course(id: course.id, name: course.name, marbles: course.marbles, seconds: course.seconds)
        }
        return body
    }
}

/// The race as the page's `marbler.room(…)` takes it, as a JS literal.
enum MarbleRaceBridge {
    struct Room: Encodable {
        let course: String
        let seed: UInt32
        let elapsed: Double
        let backers: [Backer]
        let you: Int?
    }

    struct Backer: Encodable {
        let name: String
        let marble: Int
    }

    /// `elapsed`: seconds since step 0 on the room's clock (negative while counting down).
    static func script(room: GameRoom, state: MarbleRaceState, elapsed: Double) -> String? {
        guard let race = state.race else { return nil }
        let backers = state.seats.compactMap { seat in seat.marble.map { Backer(name: room.name(of: seat.id), marble: $0) } }
        let payload = Room(course: state.course.id, seed: race.seed, elapsed: elapsed, backers: backers, you: state.marble(of: room.meId))
        guard let data = try? JSONEncoder().encode(payload), let json = String(data: data, encoding: .utf8) else { return nil }
        return "room(\(json))"
    }
}
