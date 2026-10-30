import Foundation

// Marble races remembered on this phone — the family's Marble Race rooms and
// Marbler on its own each keep a book — plus the little sums the screens
// share: "2nd", the podium's order, and how much of the picking time is left.

/// Races watched to the finish on this phone, and how the marble backed did.
struct MarbleRaceRecordBook: Codable, Equatable {
    var races = 0
    /// Races where the marble backed came first.
    var wins = 0
    /// Races where it came in the top three.
    var podiums = 0
    /// The best place it has come; nil until a race with a place.
    var bestPlace: Int?
    /// Keys of races already counted (family rooms only), oldest first.
    var seen: [String] = []

    static let seenLimit = 40

    /// Count a race once. `key` nil counts it without a check (Marbler on its
    /// own, which calls this once a race). `place` is 1 for first, nil when
    /// the marble backed has no place (none was backed, or no result).
    @discardableResult
    mutating func record(key: String?, place: Int?) -> MarbleRaceRecordNews {
        if let key {
            guard !seen.contains(key) else { return MarbleRaceRecordNews(counted: false, newBest: false) }
            seen.append(key)
            if seen.count > Self.seenLimit { seen.removeFirst(seen.count - Self.seenLimit) }
        }
        races += 1
        guard let place, place >= 1 else { return MarbleRaceRecordNews(counted: true, newBest: false) }
        if place == 1 { wins += 1 }
        if place <= 3 { podiums += 1 }
        let newBest = bestPlace.map { place < $0 } ?? true
        if newBest { bestPlace = place }
        return MarbleRaceRecordNews(counted: true, newBest: newBest)
    }

    /// "5 races · 2 wins · best 1st".
    var line: String {
        let racesText = races == 1 ? "1 race" : "\(races) races"
        let winsText = wins == 1 ? "1 win" : "\(wins) wins"
        let best = bestPlace.map { " · best \(MarbleRaceOrdinal.text($0))" } ?? ""
        return "\(racesText) · \(winsText)\(best)"
    }
}

struct MarbleRaceRecordNews: Equatable {
    let counted: Bool
    let newBest: Bool
}

/// Where a book lives: one small value in UserDefaults, under the game's key.
struct MarbleRaceRecordStore {
    var defaults: UserDefaults = .standard
    var key: String = MarbleRaceRecordStore.roomKey

    /// The family Marble Race rooms.
    static let roomKey = "marblerace.record.v1"
    /// Marbler, on this phone alone.
    static let soloKey = "marbler.record.v1"

    func load() -> MarbleRaceRecordBook {
        guard let data = defaults.data(forKey: key),
              let book = try? JSONDecoder().decode(MarbleRaceRecordBook.self, from: data) else { return MarbleRaceRecordBook() }
        return book
    }

    func save(_ book: MarbleRaceRecordBook) {
        if let data = try? JSONEncoder().encode(book) { defaults.set(data, forKey: key) }
    }
}

enum MarbleRaceOrdinal {
    /// "1st", "2nd", "3rd", "4th", "11th", "22nd".
    static func text(_ n: Int) -> String {
        let tens = n % 100
        if tens >= 11 && tens <= 13 { return "\(n)th" }
        switch n % 10 {
        case 1: return "\(n)st"
        case 2: return "\(n)nd"
        case 3: return "\(n)rd"
        default: return "\(n)th"
        }
    }

    /// "first", "second", "third", else the figure — for VoiceOver.
    static func spoken(_ n: Int) -> String {
        switch n {
        case 1: return "first"
        case 2: return "second"
        case 3: return "third"
        default: return text(n)
        }
    }
}

/// One step of the podium: the place, and the marble standing on it.
struct MarbleRacePodiumStep: Equatable, Identifiable {
    let place: Int
    let marble: Int

    var id: Int { place }
}

enum MarbleRacePodium {
    /// The podium's left-to-right order for the first three home: second,
    /// first, third, as a podium stands. Fewer than three keep the same idea.
    static func standing(_ order: [Int]) -> [MarbleRacePodiumStep] {
        let top = Array(order.prefix(3))
        switch top.count {
        case 0: return []
        case 1: return [MarbleRacePodiumStep(place: 1, marble: top[0])]
        case 2: return [MarbleRacePodiumStep(place: 2, marble: top[1]), MarbleRacePodiumStep(place: 1, marble: top[0])]
        default:
            return [MarbleRacePodiumStep(place: 2, marble: top[1]), MarbleRacePodiumStep(place: 1, marble: top[0]),
                    MarbleRacePodiumStep(place: 3, marble: top[2])]
        }
    }
}

enum MarbleRacePickClock {
    /// How much of the picking time is left, 0...1. `total` is the most seen
    /// since picking began (the phone may open the room part-way through).
    static func fraction(left: Double, total: Double) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, left / total))
    }
}
