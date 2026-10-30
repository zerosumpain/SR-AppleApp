import Foundation

// Homestead's moments over the island, as words and sets: what a roll paid
// out, what a point means, my turn coming round, and which pieces have just
// appeared on the board. Foundation only, so each is a unit test
// (HomesteadMomentsTests); the screen draws them — the toast over the island
// in HomesteadScreen, the gold glow and the pop in HomesteadBoardView.
//
// None of this is a ruling. The server pays the resources and counts the
// points; these only say, from the room as sent, what just happened.

enum HomesteadMoments {
    /// A toast's two lines.
    struct Line: Equatable {
        let title: String
        let detail: String?
    }

    // MARK: - The dice

    /// The hexes the dice now showing pay out on: their number, and not the
    /// fox's hex. None on a 7, or before anyone has rolled.
    static func paying(_ state: HomesteadState) -> [HomesteadHex] {
        guard let dice = state.dice, dice.total != 7 else { return [] }
        return state.board.hexes.filter { $0.token == dice.total && $0.id != state.fox }
    }

    /// What those hexes make, once each, in the resources' own order.
    static func payingResources(_ state: HomesteadState) -> [HomesteadResource] {
        let made = Set(paying(state).compactMap(\.resource))
        return HomesteadResource.allCases.filter { made.contains($0) }
    }

    /// "You rolled 8" / "Grain and timber for everyone beside an 8." — or the
    /// fox's line on a 7. Nil before a roll.
    static func roll(_ state: HomesteadState, name: (String) -> String) -> Line? {
        guard let dice = state.dice else { return nil }
        let who = dice.by.map(name) ?? "Someone"
        let title = "\(who) rolled \(dice.total)"
        if dice.total == 7 { return Line(title: title, detail: "The fox is on the move!") }
        let made = payingResources(state).map(\.rawValue)
        guard !made.isEmpty else { return Line(title: title, detail: "Nothing pays out this time.") }
        let list = GameNamesList.join(made)
        let capital = String(list.prefix(1)).uppercased() + String(list.dropFirst())
        return Line(title: title, detail: "\(capital) for everyone beside \(article(dice.total)) \(dice.total).")
    }

    /// "an 8", "an 11", "a 6".
    static func article(_ n: Int) -> String {
        n == 8 || n == 11 || n == 18 ? "an" : "a"
    }

    // MARK: - Points and turns

    /// "+1 point" / "6 of 10: 4 to go." when my points went up; nil otherwise
    /// (first sight of the room, a point lost, or no change).
    static func points(from old: Int?, to new: Int?, target: Int) -> Line? {
        guard let old, let new, new > old else { return nil }
        let gained = new - old
        let left = max(0, target - new)
        let detail = left == 0 ? "That's the target!" : "\(new) of \(target): \(left) to go."
        return Line(title: gained == 1 ? "+1 point" : "+\(gained) points", detail: detail)
    }

    /// What to do first, when my turn comes round.
    static func turnDetail(_ step: HomesteadStep?) -> String? {
        switch step {
        case .roll?: return "Roll the dice to start."
        case .setup?: return "Place your piece on a lit spot."
        case .fox?: return "Move the fox to a lit hex."
        case .roads?: return "Place your free roads."
        default: return nil
        }
    }

    // MARK: - New pieces

    /// Every piece on the board as one key: a cottage that becomes a town is
    /// a new key.
    static func pieceKeys(_ state: HomesteadState) -> Set<String> {
        var keys = Set<String>()
        for b in state.buildings { keys.insert("b|\(b.at)|\(b.piece.rawValue)") }
        for r in state.roads { keys.insert("r|\(r.at)") }
        return keys
    }

    /// The pieces that have just appeared, or nil when there is nothing to
    /// show: none new, or more than `limit` at once (the room being re-read,
    /// not a move).
    static func fresh(previous: Set<String>, now: Set<String>, limit: Int = 4) -> Set<String>? {
        let added = now.subtracting(previous)
        guard !added.isEmpty, added.count <= limit else { return nil }
        return added
    }

    /// A key's kind and spot: ("r", edge id) or ("b", corner id).
    static func spot(of key: String) -> (road: Bool, id: String)? {
        let parts = key.split(separator: "|").map(String.init)
        guard parts.count >= 2, parts[0] == "r" || parts[0] == "b" else { return nil }
        return (parts[0] == "r", parts[1])
    }

    // MARK: - The finish

    static func ordinal(_ n: Int) -> String {
        switch n {
        case 1: return "first"
        case 2: return "second"
        case 3: return "third"
        case 4: return "fourth"
        case 5: return "fifth"
        default: return "\(n)th"
        }
    }

    /// Points as a share of the target, 0…1.
    static func share(_ points: Int, of target: Int) -> Double {
        min(1, max(0, Double(points) / Double(max(1, target))))
    }
}
