import Foundation

/// Liar's Dice for two to five phones, or for one phone and the computer.
///
/// The site's rules (`src/lib/games/liars-dice.ts`), played on the host:
/// everyone rolls five dice under a cup and sees only their own. In turn,
/// players bid on how many dice across the WHOLE table show one face — "four
/// 3s" — each bid higher than the last: more dice, or as many of a higher
/// face. Ones are wild: they count as every face, and nobody bids on them.
/// Instead of bidding, a player may call the last bid a lie. Every cup is
/// lifted: if the table holds at least what was bid, the caller loses a
/// die; if not, the bidder does. The loser opens the next round (or, out of
/// dice, the next player still in). The last player with dice wins.
///
/// A turn lasts a minute; a player who lets it run out has the smallest
/// raise bid for them (or, with no raise left, the bid called). A player who
/// leaves loses their dice and is out. Dice are rolled with the host's
/// seeded generator, and each phone is sent only its own dice until the
/// cups are lifted.
enum OfflineLiarsDiceRules: OfflineGameRules {
    static let dicePerPlayer = 5
    static let faces = 6
    /// The lowest face that may be bid: ones are wild.
    static let lowestFace = 2
    /// Seconds a turn lasts before the host bids for the player.
    static let turnSeconds: Double = 60
    /// How long the cups stay lifted after a call.
    static let revealSeconds: Double = 6
    /// How long the last reveal stays up before the standings.
    static let resultPause: Double = 5

    static let info = OfflineGameInfo(
        id: "liars-dice",
        title: "Liar's Dice",
        blurb: "Hidden dice, bold bids: call the liar before you are caught out.",
        category: .skill,
        minPlayers: 2,
        maxPlayers: 5,
        symbol: "dice.fill",
        howToPlay: [
            "Everyone rolls five dice and sees only their own.",
            "Bid how many dice on the whole table show a face: \u{201C}four 3s\u{201D}. Ones are wild and count as any face.",
            "Each bid must be higher: more dice, or as many of a higher face.",
            "Or call \u{201C}Liar!\u{201D}: every cup is lifted, and whoever was wrong loses a die.",
            "The last player with dice wins.",
            "You have \(Int(turnSeconds)) seconds a turn, or the smallest raise is bid for you."
        ],
        soloOpponents: 3
    )

    // MARK: - State

    enum Phase: String, Codable, Equatable {
        /// Bids go round the table.
        case bidding
        /// A call: every cup is up until `revealUntil`.
        case reveal
        /// One player has dice left; the last reveal shows until `resultUntil`.
        case done
        /// The room shows the standings.
        case over
    }

    struct Bid: Codable, Equatable {
        let playerId: String
        let quantity: Int
        let face: Int
        /// The turn ran out and the host bid for them.
        let auto: Bool
    }

    /// One player's dice, lifted.
    struct Cup: Codable, Equatable, Identifiable {
        let playerId: String
        let dice: [Int]

        var id: String { playerId }
    }

    /// A call, settled.
    struct Reveal: Codable, Equatable {
        let bid: Bid
        let challengerId: String
        /// The challenger's turn ran out and the host called for them.
        let auto: Bool
        /// Dice showing the bid's face, ones included.
        let count: Int
        let loserId: String
        /// The loser lost their last die.
        let eliminated: Bool
        /// Every cup at the call, seat order.
        let cups: [Cup]

        var bidStood: Bool { count >= bid.quantity }
    }

    struct State: Codable, Equatable {
        var players: [OfflinePlayer]
        /// Dice each player has left.
        var counts: [String: Int]
        /// This round's roll, each cup sorted.
        var dice: [String: [Int]] = [:]
        /// Players who left the room (their dice went with them).
        var left: [String] = []
        /// Players out of the game, first out first.
        var outOrder: [String] = []
        /// The round each player went out in.
        var outRound: [String: Int] = [:]
        var round = 1
        var phase: Phase = .bidding
        /// Whose bid it is while bidding.
        var turn: String?
        /// Goes up with every bid, call and new round: a late action meant
        /// for an earlier turn is refused, not misapplied.
        var turnNumber = 1
        var turnEndsAt: Double
        /// This round's bids, oldest first; the last is the one standing.
        var bids: [Bid] = []
        var reveal: Reveal?
        var revealUntil: Double = 0
        var resultUntil: Double = 0
        /// Calls each player got right.
        var goodCalls: [String: Int] = [:]
    }

    enum Action: Codable, Equatable {
        /// Bid `quantity` dice showing `face` (2…6), on turn `turn`.
        case bid(turn: Int, quantity: Int, face: Int)
        /// Call the standing bid a lie, on turn `turn`.
        case liar(turn: Int)
    }

    // MARK: - What a player sees

    struct Seat: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        let dice: Int
        let out: Bool
        let left: Bool
    }

    struct PlayerView: Codable, Equatable {
        let phase: Phase
        let round: Int
        let turnPlayer: String?
        let turnNumber: Int
        let turnEndsAt: Double
        /// Dice in play across the table.
        let totalDice: Int
        let bids: [Bid]
        /// My dice this round; empty for a spectator or a player who is out.
        let myDice: [Int]
        let seats: [Seat]
        /// The last call, while the cups are up and after the game.
        let reveal: Reveal?
        let winner: String?
    }

    // MARK: - Rules

    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State {
        var counts: [String: Int] = [:]
        for player in players { counts[player.id] = dicePerPlayer }
        var state = State(players: players, counts: counts, turnEndsAt: now + turnSeconds)
        let starter = players.isEmpty ? nil : players[rng.int(below: players.count)].id
        roll(&state, starter: starter, now: now, rng: &rng)
        return state
    }

    static func apply(_ action: Action, by playerId: String, to state: inout State, now: Double, rng: inout OfflineRNG) throws {
        guard state.players.contains(where: { $0.id == playerId }) else { throw OfflineRefusal("You are not in this game.") }
        switch state.phase {
        case .bidding: break
        case .reveal: throw OfflineRefusal("The cups are up — wait for the next roll.")
        case .done, .over: throw OfflineRefusal("The game is over.")
        }
        guard (state.counts[playerId] ?? 0) > 0, !state.left.contains(playerId) else {
            throw OfflineRefusal("You are out of dice.")
        }
        switch action {
        case .bid(let turn, let quantity, let face):
            try checkTurn(turn, playerId, state)
            if let problem = problem(quantity: quantity, face: face, standing: state.bids.last, total: totalDice(state)) {
                throw OfflineRefusal(problem)
            }
            placeBid(Bid(playerId: playerId, quantity: quantity, face: face, auto: false), in: &state, now: now)
        case .liar(let turn):
            try checkTurn(turn, playerId, state)
            guard state.bids.last != nil else { throw OfflineRefusal("Nobody has bid yet — open the bidding.") }
            call(by: playerId, auto: false, in: &state, now: now)
        }
    }

    static func tick(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        switch state.phase {
        case .bidding:
            guard now >= state.turnEndsAt else { return }
            guard let turn = state.turn, isAlive(turn, state) else {
                state.turn = next(after: state.turn, in: state)
                state.turnNumber += 1
                state.turnEndsAt = now + turnSeconds
                return
            }
            if let bid = autoBid(state) {
                placeBid(Bid(playerId: turn, quantity: bid.quantity, face: bid.face, auto: true), in: &state, now: now)
            } else {
                call(by: turn, auto: true, in: &state, now: now)
            }
        case .reveal:
            guard now >= state.revealUntil else { return }
            if alive(state).count <= 1 {
                state.phase = .done
                state.resultUntil = now + resultPause
                return
            }
            // The loser opens the next round; out of dice, the next player in.
            let loser = state.reveal?.loserId
            let starter = loser.flatMap { isAlive($0, state) ? $0 : next(after: $0, in: state) }
            state.round += 1
            roll(&state, starter: starter, now: now, rng: &rng)
        case .done:
            if now >= state.resultUntil { state.phase = .over }
        case .over:
            break
        }
    }

    static func playerLeft(_ playerId: String, state: inout State, now: Double, rng: inout OfflineRNG) {
        guard state.players.contains(where: { $0.id == playerId }), !state.left.contains(playerId) else { return }
        state.left.append(playerId)
        let hadDice = (state.counts[playerId] ?? 0) > 0
        state.counts[playerId] = 0
        state.dice[playerId] = []
        if hadDice {
            state.outOrder.append(playerId)
            state.outRound[playerId] = state.round
        }
        guard state.phase == .bidding else { return }
        if alive(state).count <= 1 {
            state.phase = .done
            state.turn = nil
            state.resultUntil = now + resultPause
            return
        }
        if state.turn == playerId {
            state.turn = next(after: playerId, in: state)
            state.turnNumber += 1
            state.turnEndsAt = now + turnSeconds
        }
    }

    static func view(of state: State, for playerId: String?) -> PlayerView {
        let seats = state.players.map { player in
            Seat(id: player.id, name: player.name, dice: state.counts[player.id] ?? 0,
                 out: (state.counts[player.id] ?? 0) == 0, left: state.left.contains(player.id))
        }
        let mine = playerId.flatMap { state.dice[$0] } ?? []
        let showReveal = state.phase == .reveal || state.phase == .done || state.phase == .over
        return PlayerView(
            phase: state.phase,
            round: state.round,
            turnPlayer: state.phase == .bidding ? state.turn : nil,
            turnNumber: state.turnNumber,
            turnEndsAt: state.turnEndsAt,
            totalDice: totalDice(state),
            bids: state.bids,
            myDice: mine,
            seats: seats,
            reveal: showReveal ? state.reveal : nil,
            winner: winner(state)
        )
    }

    static func isOver(_ state: State) -> Bool { state.phase == .over }

    static func standings(_ state: State) -> [OfflineStanding] {
        let out = state.outOrder
        return OfflineStanding.ranked(state.players, score: { player in
            // Players outlasted: everyone out, for those still in; for the
            // rest, those who went out before them.
            if let index = out.firstIndex(of: player.id) { return index }
            return out.count
        }, detail: { player in
            var parts: [String] = []
            let dice = state.counts[player.id] ?? 0
            if let round = state.outRound[player.id] {
                parts.append(state.left.contains(player.id) ? "left in round \(round)" : "out in round \(round)")
            } else if winner(state) == player.id {
                parts.append(dice == 1 ? "won with 1 die left" : "won with \(dice) dice left")
            } else {
                parts.append(dice == 1 ? "1 die left" : "\(dice) dice left")
            }
            let calls = state.goodCalls[player.id] ?? 0
            if calls > 0 { parts.append(calls == 1 ? "1 good call" : "\(calls) good calls") }
            return parts.joined(separator: " · ")
        })
    }

    // MARK: - Bids

    /// Why a bid is not allowed, or nil if it is. Strictly higher than the
    /// standing bid: more dice (any face), or as many dice of a higher face.
    static func problem(quantity: Int, face: Int, standing: Bid?, total: Int) -> String? {
        if face < 1 || face > faces { return "Pick a face from 2 to 6." }
        if face == 1 { return "Ones are wild — bid on 2 to 6." }
        if quantity < 1 { return "Bid at least one die." }
        if quantity > total { return "There are only \(total) dice in play." }
        if let standing, !(quantity > standing.quantity || (quantity == standing.quantity && face > standing.face)) {
            return "Bid more dice, or the same number of a higher face."
        }
        return nil
    }

    /// Where the bid picker starts: one more of the standing face, else as
    /// many of a higher face; before any bid, one of `preferred`. Nil when
    /// nothing is left but "liar".
    static func startingBid(standing: Bid?, total: Int, preferred: Int? = nil) -> (quantity: Int, face: Int)? {
        guard total > 0 else { return nil }
        guard let standing else {
            return (1, min(faces, max(lowestFace, preferred ?? lowestFace)))
        }
        if standing.quantity + 1 <= total { return (standing.quantity + 1, standing.face) }
        if standing.face < faces, standing.quantity <= total { return (standing.quantity, standing.face + 1) }
        return nil
    }

    /// Whether a die counts towards a bid on `face`: that face, or a one.
    static func counts(_ die: Int, towards face: Int) -> Bool { die == face || die == 1 }

    /// Dice in `cup` that count towards `face`.
    static func matching(_ cup: [Int], face: Int) -> Int { cup.filter { counts($0, towards: face) }.count }

    /// My most common face, counting ones (never ones itself; ties go high).
    static func favouriteFace(_ dice: [Int]) -> Int {
        var best = (face: faces, n: -1)
        for face in stride(from: faces, through: lowestFace, by: -1) {
            let n = matching(dice, face: face)
            if n > best.n { best = (face, n) }
        }
        return best.face
    }

    private static let numbers = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
                                  "ten", "eleven", "twelve"]

    /// "one 4", "three 6s"; past twelve the number stays a figure ("14 5s").
    static func bidText(quantity: Int, face: Int) -> String {
        let n = quantity >= 0 && quantity < numbers.count ? numbers[quantity] : "\(quantity)"
        return quantity == 1 ? "\(n) \(face)" : "\(n) \(face)s"
    }

    /// The reveal in a sentence, names from `name` ("You" for me): "Sam
    /// called Robin's four 3s. There were three — Robin loses a die."
    static func revealLine(_ reveal: Reveal, name: (String) -> String) -> String {
        let caller = name(reveal.challengerId)
        let bidder = name(reveal.bid.playerId)
        let bid = bidText(quantity: reveal.bid.quantity, face: reveal.bid.face)
        let there = reveal.count == 1 ? "There was 1" : "There were \(reveal.count)"
        let loser = name(reveal.loserId)
        let loses = loser == "You" ? "You lose" : "\(loser) loses"
        let what = reveal.eliminated ? "\(loses) \(loser == "You" ? "your" : "their") last die" : "\(loses) a die"
        let timed = reveal.auto ? " (time ran out)" : ""
        let possessive = bidder == "You" ? "your" : "\(bidder)\u{2019}s"
        return "\(caller) called \(possessive) \(bid)\(timed). \(there) — \(what)."
    }

    // MARK: - The table

    static func isAlive(_ id: String, _ state: State) -> Bool {
        (state.counts[id] ?? 0) > 0 && !state.left.contains(id)
    }

    /// Players with dice, seat order.
    static func alive(_ state: State) -> [OfflinePlayer] {
        state.players.filter { isAlive($0.id, state) }
    }

    static func totalDice(_ state: State) -> Int {
        alive(state).reduce(0) { $0 + (state.counts[$1.id] ?? 0) }
    }

    /// The one player with dice left, once only one has.
    static func winner(_ state: State) -> String? {
        let left = alive(state)
        return left.count == 1 ? left[0].id : nil
    }

    /// The next player with dice after `id` round the table (`id` itself
    /// when nobody else has any); the first in seat order for nil.
    static func next(after id: String?, in state: State) -> String? {
        let seats = state.players
        let at = id.flatMap { id in seats.firstIndex { $0.id == id } } ?? -1
        guard !seats.isEmpty else { return nil }
        for step in 1...seats.count {
            let candidate = seats[(at + step + seats.count) % seats.count].id
            if isAlive(candidate, state) { return candidate }
        }
        return nil
    }

    // MARK: - Helpers

    private static func checkTurn(_ turn: Int, _ playerId: String, _ state: State) throws {
        guard turn == state.turnNumber else { throw OfflineRefusal("That was for an earlier turn.") }
        guard state.turn == playerId else {
            let name = state.players.first { $0.id == state.turn }?.name ?? "somebody else"
            throw OfflineRefusal("It's \(name)'s turn.")
        }
    }

    /// Roll every cup still in play and hand the first bid to `starter`
    /// (or the next player in).
    private static func roll(_ state: inout State, starter: String?, now: Double, rng: inout OfflineRNG) {
        var dice: [String: [Int]] = [:]
        for player in state.players {
            let n = isAlive(player.id, state) ? (state.counts[player.id] ?? 0) : 0
            dice[player.id] = (0..<n).map { _ in rng.int(in: 1...faces) }.sorted()
        }
        state.dice = dice
        state.phase = .bidding
        state.bids = []
        state.reveal = nil
        state.turn = starter.flatMap { isAlive($0, state) ? $0 : next(after: $0, in: state) } ?? next(after: nil, in: state)
        state.turnNumber += 1
        state.turnEndsAt = now + turnSeconds
    }

    private static func placeBid(_ bid: Bid, in state: inout State, now: Double) {
        state.bids.append(bid)
        state.turn = next(after: bid.playerId, in: state)
        state.turnNumber += 1
        state.turnEndsAt = now + turnSeconds
    }

    /// What the host bids for a timed-out turn, as the site does: before any
    /// bid, one of the player's own most common face; after one, one more
    /// of the same face — or nil, a call, when the table has no more dice.
    private static func autoBid(_ state: State) -> (quantity: Int, face: Int)? {
        let total = totalDice(state)
        guard let standing = state.bids.last else {
            let mine = state.turn.flatMap { state.dice[$0] } ?? []
            return (1, mine.isEmpty ? lowestFace : favouriteFace(mine))
        }
        return standing.quantity + 1 <= total ? (standing.quantity + 1, standing.face) : nil
    }

    /// Lift every cup on the standing bid: whoever was wrong loses a die.
    private static func call(by challenger: String, auto: Bool, in state: inout State, now: Double) {
        guard let bid = state.bids.last else { return }
        let cups = alive(state).map { Cup(playerId: $0.id, dice: state.dice[$0.id] ?? []) }
        let count = cups.reduce(0) { $0 + matching($1.dice, face: bid.face) }
        let loser = count >= bid.quantity ? challenger : bid.playerId
        let winner = loser == challenger ? bid.playerId : challenger
        if winner == challenger { state.goodCalls[challenger, default: 0] += 1 }
        var eliminated = false
        // A bidder who has since left has nothing left to lose.
        if isAlive(loser, state) {
            let left = (state.counts[loser] ?? 0) - 1
            state.counts[loser] = left
            if left == 0 {
                eliminated = true
                state.outOrder.append(loser)
                state.outRound[loser] = state.round
            }
        }
        state.reveal = Reveal(bid: bid, challengerId: challenger, auto: auto, count: count, loserId: loser,
                              eliminated: eliminated, cups: cups)
        state.phase = .reveal
        state.turn = nil
        state.turnNumber += 1
        state.revealUntil = now + revealSeconds
    }
}
