import Foundation

// Liar's Dice's wire pieces and the rules the phone applies itself — which
// bids are legal, the smallest raise, which dice count towards a face — as
// pure values, so each is a unit test. The server rolls, judges every bid and
// settles every call; nothing here decides who loses a die.
//
// The room's Liar's Dice side is decoded whole into `LiarsDiceState`, read off
// the same JSON as `GameRoom` (`GameRoom.liarsDice`), so the shared room model
// carries one field for this game rather than a dozen.

/// Where a Liar's Dice room is. Read from the room's raw `phase`, so the
/// shared `GamePhase` (which every game's screen switches over) needs no new
/// case: `bidding` decodes there as `.unknown`, and here as itself.
enum LiarsDicePhase: String, Equatable {
    case lobby, countdown, bidding, reveal, finished, closed, unknown

    static func from(_ raw: String?) -> LiarsDicePhase {
        guard let raw else { return .unknown }
        // `playing` too, should the site ever name the bidding phase that.
        if raw == "playing" { return .bidding }
        return LiarsDicePhase(rawValue: raw) ?? .unknown
    }
}

/// One bid: "four 3s", by whom. `auto` when the turn clock ran out and the
/// server bid for them.
struct LiarsDiceBid: Decodable, Equatable {
    let playerId: String
    let quantity: Int
    let face: Int
    let auto: Bool

    init(playerId: String, quantity: Int, face: Int, auto: Bool = false) {
        self.playerId = playerId
        self.quantity = quantity
        self.face = face
        self.auto = auto
    }

    private enum CodingKeys: String, CodingKey { case playerId, quantity, face, auto }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playerId = (try? c.decodeIfPresent(String.self, forKey: .playerId)) ?? ""
        quantity = (try? c.decodeIfPresent(Int.self, forKey: .quantity)) ?? 0
        face = min(6, max(1, (try? c.decodeIfPresent(Int.self, forKey: .face)) ?? 1))
        auto = (try? c.decodeIfPresent(Bool.self, forKey: .auto)) ?? false
    }
}

/// One cup, lifted: whose, and what it held.
struct LiarsDiceCup: Decodable, Equatable, Identifiable {
    let playerId: String
    let dice: [Int]

    var id: String { playerId }

    private enum CodingKeys: String, CodingKey { case playerId, dice }

    init(playerId: String, dice: [Int]) {
        self.playerId = playerId
        self.dice = dice
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playerId = (try? c.decodeIfPresent(String.self, forKey: .playerId)) ?? ""
        dice = (try? c.decodeIfPresent([Int].self, forKey: .dice)) ?? []
    }
}

/// A call, settled: the bid called, who called it, what the table held, who
/// lost a die. Every cup at the call, in seat order.
struct LiarsDiceReveal: Decodable, Equatable {
    let bid: LiarsDiceBid
    let challengerId: String
    /// The challenger's clock ran out and the server called for them.
    let auto: Bool
    /// Dice showing the bid's face (plus ones, when wild).
    let count: Int
    let loserId: String
    /// The loser lost their last die.
    let eliminated: Bool
    let dice: [LiarsDiceCup]

    private enum CodingKeys: String, CodingKey { case bid, challengerId, auto, count, loserId, eliminated, dice }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bid = try c.decode(LiarsDiceBid.self, forKey: .bid)
        challengerId = (try? c.decodeIfPresent(String.self, forKey: .challengerId)) ?? ""
        auto = (try? c.decodeIfPresent(Bool.self, forKey: .auto)) ?? false
        count = (try? c.decodeIfPresent(Int.self, forKey: .count)) ?? 0
        loserId = (try? c.decodeIfPresent(String.self, forKey: .loserId)) ?? ""
        eliminated = (try? c.decodeIfPresent(Bool.self, forKey: .eliminated)) ?? false
        dice = (try? c.decodeIfPresent([LiarsDiceCup].self, forKey: .dice)) ?? []
    }

    /// Whether the bid stood: the table held at least what was bid.
    var bidStood: Bool { count >= bid.quantity }
}

/// A player at the table, as Liar's Dice sees them. Name and status are the
/// shared `GamePlayer`'s.
struct LiarsDiceSeat: Decodable, Equatable, Identifiable {
    let id: String
    /// Sat down when play started.
    let seated: Bool
    let diceCount: Int
    /// Lost their last die, or left mid-game.
    let out: Bool
    /// Mine always; everyone's once finished; nil for another player's cup.
    let dice: [Int]?

    private enum CodingKeys: String, CodingKey { case id, seated, diceCount, out, dice }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        seated = (try? c.decodeIfPresent(Bool.self, forKey: .seated)) ?? false
        diceCount = max(0, (try? c.decodeIfPresent(Int.self, forKey: .diceCount)) ?? 0)
        out = (try? c.decodeIfPresent(Bool.self, forKey: .out)) ?? false
        dice = (try? c.decodeIfPresent([Int].self, forKey: .dice)) ?? nil
    }
}

/// A row of the final table: the winner first, then the last out, and on.
struct LiarsDiceStanding: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let place: Int
    /// Dice left at the end — the winner's, else 0.
    let dice: Int
    /// The round they went out in; nil for the winner.
    let outRound: Int?
    /// They left rather than lost their dice.
    let left: Bool

    private enum CodingKeys: String, CodingKey { case id, name, place, dice, outRound, left }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Player"
        place = (try? c.decodeIfPresent(Int.self, forKey: .place)) ?? 0
        dice = (try? c.decodeIfPresent(Int.self, forKey: .dice)) ?? 0
        outRound = (try? c.decodeIfPresent(Int.self, forKey: .outRound)) ?? nil
        left = (try? c.decodeIfPresent(Bool.self, forKey: .left)) ?? false
    }
}

/// The room's Liar's Dice side, decoded from the same JSON as `GameRoom`.
/// Lenient throughout: a lobby from the create call carries none of it.
struct LiarsDiceState: Decodable, Equatable {
    let phase: LiarsDicePhase
    /// Dice each player started with: 3 or 5.
    let dicePerPlayer: Int
    /// Ones count as any face (medium, hard), and nobody bids on them.
    let wildOnes: Bool
    /// The rule in a sentence, from the server.
    let rule: String?
    /// The lowest face that may be bid: 2 when ones are wild, else 1.
    let minFace: Int
    /// How long a turn lasts.
    let turnMs: Double
    let round: Int
    let starterId: String?
    /// Whose turn it is while bidding.
    let turnId: String?
    /// Dice in play across the table.
    let totalDice: Int
    /// The standing bid; nil before anyone has bid this round.
    let bid: LiarsDiceBid?
    /// This round's bids, oldest first — the table talk.
    let bids: [LiarsDiceBid]
    let seats: [LiarsDiceSeat]
    /// The last call, shown through the reveal (and at the finish).
    let reveal: LiarsDiceReveal?
    let standings: [LiarsDiceStanding]?

    private enum CodingKeys: String, CodingKey {
        case phase, dicePerPlayer, wildOnes, rule, minFace, turnMs, round, starterId, turnId, totalDice
        case bid, bids, players, reveal, standings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = LiarsDicePhase.from((try? c.decodeIfPresent(String.self, forKey: .phase)) ?? nil)
        dicePerPlayer = (try? c.decodeIfPresent(Int.self, forKey: .dicePerPlayer)) ?? 5
        wildOnes = (try? c.decodeIfPresent(Bool.self, forKey: .wildOnes)) ?? true
        rule = (try? c.decodeIfPresent(String.self, forKey: .rule)) ?? nil
        minFace = min(6, max(1, (try? c.decodeIfPresent(Int.self, forKey: .minFace)) ?? (wildOnes ? 2 : 1)))
        turnMs = (try? c.decodeIfPresent(Double.self, forKey: .turnMs)) ?? 45_000
        round = (try? c.decodeIfPresent(Int.self, forKey: .round)) ?? 0
        starterId = (try? c.decodeIfPresent(String.self, forKey: .starterId)) ?? nil
        turnId = (try? c.decodeIfPresent(String.self, forKey: .turnId)) ?? nil
        totalDice = (try? c.decodeIfPresent(Int.self, forKey: .totalDice)) ?? 0
        bid = (try? c.decodeIfPresent(LiarsDiceBid.self, forKey: .bid)) ?? nil
        bids = (try? c.decodeIfPresent([LiarsDiceBid].self, forKey: .bids)) ?? []
        seats = (try? c.decodeIfPresent([LiarsDiceSeat].self, forKey: .players)) ?? []
        reveal = (try? c.decodeIfPresent(LiarsDiceReveal.self, forKey: .reveal)) ?? nil
        standings = (try? c.decodeIfPresent([LiarsDiceStanding].self, forKey: .standings)) ?? nil
    }

    func seat(_ id: String) -> LiarsDiceSeat? { seats.first { $0.id == id } }
}

// MARK: - The table the host picks

/// Dice each — Liar's Dice's own choice on the new-game sheet.
struct LiarsDiceSettings: Equatable {
    static let diceCounts = [3, 5]

    var difficulty: GameDifficulty
    var dice: Int = 5

    func createBody(invite: [String]) -> CreateGameBody {
        CreateGameBody(game: GameKind.liarsDice.rawValue, difficulty: difficulty.rawValue, invite: invite, dice: dice)
    }

    /// One line under the picker.
    static func line(dice: Int) -> String {
        dice <= 3
            ? "Three dice each: a quick game, and every die lost hurts."
            : "Five dice each, the classic table."
    }

    /// "5 dice each · ones wild", for the lobby.
    static func about(_ state: LiarsDiceState?) -> String {
        let dice = state?.dicePerPlayer ?? 5
        let wild = state?.wildOnes ?? true
        return "\(dice) dice each · \(wild ? "ones wild" : "no wilds")"
    }
}

// MARK: - The rules

enum LiarsDiceRules {
    static let faces = 6

    /// Faces that may be bid: 2–6 when ones are wild, else 1–6.
    static func biddableFaces(wild: Bool) -> ClosedRange<Int> { (wild ? 2 : 1)...faces }

    /// Why a bid is not allowed, or nil if it is — the server's sentences, so
    /// the phone can say them before sending. Strictly higher than the
    /// standing bid: more dice (any face), or as many dice of a higher face.
    static func problem(quantity: Int, face: Int, standing: LiarsDiceBid?, total: Int, wild: Bool) -> String? {
        if face < 1 || face > faces { return "Pick a face from 1 to 6." }
        if wild && face == 1 { return "Ones are wild — bid on 2 to 6." }
        if quantity < 1 { return "Bid at least one die." }
        if quantity > total { return "There are only \(total) dice in play." }
        if let standing, !(quantity > standing.quantity || (quantity == standing.quantity && face > standing.face)) {
            return "Bid more dice, or the same number of a higher face."
        }
        return nil
    }

    static func isLegal(quantity: Int, face: Int, standing: LiarsDiceBid?, total: Int, wild: Bool) -> Bool {
        problem(quantity: quantity, face: face, standing: standing, total: total, wild: wild) == nil
    }

    /// The fewest dice any legal bid can name, or nil when no bid is left and
    /// the only move is "liar".
    static func minQuantity(standing: LiarsDiceBid?, total: Int, wild: Bool) -> Int? {
        let lowest: Int
        if let standing {
            lowest = standing.face < faces ? standing.quantity : standing.quantity + 1
        } else {
            lowest = 1
        }
        let q = max(1, lowest)
        return q <= total ? q : nil
    }

    /// The faces that make a legal bid of `quantity`, lowest first.
    static func legalFaces(quantity: Int, standing: LiarsDiceBid?, total: Int, wild: Bool) -> [Int] {
        biddableFaces(wild: wild).filter {
            isLegal(quantity: quantity, face: $0, standing: standing, total: total, wild: wild)
        }
    }

    /// The smallest raise, as the picker's starting point: one more of the
    /// same face; or, before any bid, one of `preferred` (else the lowest
    /// biddable face). Nil when nothing is left but "liar".
    static func startingBid(standing: LiarsDiceBid?, total: Int, wild: Bool, preferred: Int? = nil)
        -> (quantity: Int, face: Int)? {
        guard total > 0 else { return nil }
        if let standing {
            if isLegal(quantity: standing.quantity + 1, face: standing.face, standing: standing, total: total, wild: wild) {
                return (standing.quantity + 1, standing.face)
            }
            guard let q = minQuantity(standing: standing, total: total, wild: wild),
                  let f = legalFaces(quantity: q, standing: standing, total: total, wild: wild).first else { return nil }
            return (q, f)
        }
        let range = biddableFaces(wild: wild)
        let face = preferred.map { min(range.upperBound, max(range.lowerBound, $0)) } ?? range.lowerBound
        return (1, face)
    }

    /// Move the picker's face to a legal one for `quantity`: keep it if it is,
    /// else the nearest legal face above it, else the lowest legal one.
    static func fitFace(_ face: Int, quantity: Int, standing: LiarsDiceBid?, total: Int, wild: Bool) -> Int? {
        let legal = legalFaces(quantity: quantity, standing: standing, total: total, wild: wild)
        if legal.contains(face) { return face }
        return legal.first { $0 > face } ?? legal.first
    }

    /// Whether a die counts towards a bid on `face`: that face, or a one when wild.
    static func counts(_ die: Int, towards face: Int, wild: Bool) -> Bool {
        die == face || (wild && die == 1)
    }

    /// The dice counting towards `face` across these cups.
    static func tally(_ cups: [[Int]], face: Int, wild: Bool) -> Int {
        cups.reduce(0) { sum, cup in sum + cup.filter { counts($0, towards: face, wild: wild) }.count }
    }

    /// My most common face, for a hint beside the picker (never ones; ties go high).
    static func mostCommonFace(_ dice: [Int], wild: Bool) -> Int? {
        guard !dice.isEmpty else { return nil }
        var best: (face: Int, n: Int)?
        for face in stride(from: faces, through: 2, by: -1) {
            let n = dice.filter { counts($0, towards: face, wild: wild) }.count
            if n > (best?.n ?? 0) { best = (face, n) }
        }
        return best?.face
    }

    private static let numbers = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
                                  "ten", "eleven", "twelve"]

    /// "one 4", "three 6s"; past twelve the number stays a figure ("14 5s").
    static func bidText(quantity: Int, face: Int) -> String {
        let n = quantity < numbers.count ? numbers[quantity] : "\(quantity)"
        return quantity == 1 ? "\(n) \(face)" : "\(n) \(face)s"
    }

    /// The fraction of the turn left, 0…1 (1 when the clock is unknown).
    static func turnLeft(endsAt: Double?, turnMs: Double, now: Double?) -> Double {
        guard let endsAt, let now, turnMs > 0 else { return 1 }
        return min(1, max(0, (endsAt - now) / turnMs))
    }

    /// The reveal in a sentence: "Sam called Robin's four 3s. There were three
    /// — Robin loses a die." Names are the caller's (`you` for me).
    static func revealLine(_ reveal: LiarsDiceReveal, name: (String) -> String) -> String {
        let caller = name(reveal.challengerId)
        let bidder = name(reveal.bid.playerId)
        let bid = bidText(quantity: reveal.bid.quantity, face: reveal.bid.face)
        let there = reveal.count == 1 ? "There was 1" : "There were \(reveal.count)"
        let loser = name(reveal.loserId)
        let loses = loser == "You" ? "You lose" : "\(loser) loses"
        let what = reveal.eliminated ? "\(loses) \(loser == "You" ? "your" : "their") last die" : "\(loses) a die"
        let timed = reveal.auto ? " (timed out)" : ""
        let possessive = bidder == "You" ? "your" : "\(bidder)’s"
        return "\(caller) called \(possessive) \(bid)\(timed). \(there) — \(what)."
    }
}
