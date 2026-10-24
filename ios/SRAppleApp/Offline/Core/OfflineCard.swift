import Foundation

// The playing cards every offline card game shares: one model, one deck, one
// way to write a card down. A card is a plain value — it says nothing about
// whose hand it is in; that is the game's `State`.

/// A French suit.
enum OfflineSuit: String, Codable, CaseIterable, Identifiable {
    case clubs, diamonds, hearts, spades

    var id: String { rawValue }

    /// ♣ ♦ ♥ ♠ — text presentation, so it takes the label's colour.
    var symbol: String {
        switch self {
        case .clubs: return "\u{2663}\u{FE0E}"
        case .diamonds: return "\u{2666}\u{FE0E}"
        case .hearts: return "\u{2665}\u{FE0E}"
        case .spades: return "\u{2660}\u{FE0E}"
        }
    }

    /// C D H S, for compact ids.
    var letter: String {
        switch self {
        case .clubs: return "C"
        case .diamonds: return "D"
        case .hearts: return "H"
        case .spades: return "S"
        }
    }

    var isRed: Bool { self == .diamonds || self == .hearts }

    /// "clubs", for spoken and written sentences.
    var name: String { rawValue }
}

/// One playing card. `rank` is 1 (ace) … 13 (king); `highRank` counts the ace
/// as 14 for games where aces are high.
struct OfflineCard: Codable, Hashable, Identifiable, CustomStringConvertible {
    let suit: OfflineSuit
    /// 1 = ace, 2…10, 11 = jack, 12 = queen, 13 = king.
    let rank: Int

    init(_ rank: Int, _ suit: OfflineSuit) {
        precondition((1...13).contains(rank), "OfflineCard rank must be 1…13")
        self.rank = rank
        self.suit = suit
    }

    /// "AS", "10H", "QD". Unique within ONE deck — with several decks, give
    /// `ForEach` the index as well.
    var id: String { rankText + suit.letter }

    /// "A", "2" … "10", "J", "Q", "K".
    var rankText: String {
        switch rank {
        case 1: return "A"
        case 11: return "J"
        case 12: return "Q"
        case 13: return "K"
        default: return String(rank)
        }
    }

    /// "A♠", "10♥" — what a card face or a log line shows.
    var text: String { rankText + suit.symbol }

    var description: String { text }

    /// "ace of spades", "10 of hearts", for VoiceOver and sentences.
    var name: String {
        let word: String
        switch rank {
        case 1: word = "ace"
        case 11: word = "jack"
        case 12: word = "queen"
        case 13: word = "king"
        default: word = String(rank)
        }
        return "\(word) of \(suit.name)"
    }

    /// The ace as 14: 2 is the lowest, ace the highest.
    var highRank: Int { rank == 1 ? 14 : rank }

    /// 11, 12, 13.
    var isFace: Bool { rank >= 11 }

    var isRed: Bool { suit.isRed }

    /// The 52 cards in a fixed order: clubs A…K, diamonds, hearts, spades.
    static func deck() -> [OfflineCard] {
        OfflineSuit.allCases.flatMap { suit in (1...13).map { OfflineCard($0, suit) } }
    }

    /// `decks` full decks, shuffled with the host's generator.
    static func shuffledDeck(_ rng: inout OfflineRNG, decks: Int = 1) -> [OfflineCard] {
        var cards: [OfflineCard] = []
        for _ in 0..<max(1, decks) { cards += deck() }
        rng.shuffle(&cards)
        return cards
    }

    /// Deal `count` cards to each of `hands` hands, one at a time round the
    /// table, from the top (the END) of `deck`. Stops early if the deck runs out.
    static func deal(_ count: Int, to hands: Int, from deck: inout [OfflineCard]) -> [[OfflineCard]] {
        var out = Array(repeating: [OfflineCard](), count: max(0, hands))
        for _ in 0..<count {
            for hand in 0..<out.count {
                guard let card = deck.popLast() else { return out }
                out[hand].append(card)
            }
        }
        return out
    }

    /// Sorted for a hand: by suit (clubs, diamonds, spades, hearts — colours
    /// alternate), then by rank, aces high when `acesHigh`.
    static func sortedForHand(_ cards: [OfflineCard], acesHigh: Bool = true) -> [OfflineCard] {
        let suitOrder: [OfflineSuit: Int] = [.clubs: 0, .diamonds: 1, .spades: 2, .hearts: 3]
        return cards.sorted { a, b in
            if a.suit != b.suit { return suitOrder[a.suit, default: 0] < suitOrder[b.suit, default: 0] }
            return acesHigh ? a.highRank < b.highRank : a.rank < b.rank
        }
    }
}
