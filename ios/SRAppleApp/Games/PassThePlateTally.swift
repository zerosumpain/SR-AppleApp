import Foundation

/// The cards on somebody's Pass the Plate table, grouped for the eye: one
/// chip per kind with a count, and — when the level shows hints — how far the
/// sets have got (a pancake pair, a whole pizza) and what the popcorn, pies
/// and strawberries are worth so far.
///
/// Display only: the server scores every round, and its `roundSoFar` is the
/// figure that counts. Self-contained (plain strings and numbers in, not the
/// wire types) so it is a unit test on its own.
enum PassThePlateTally {
    /// One card on a table, as far as grouping needs.
    struct Card: Equatable {
        let kind: String
        /// pair | triple | sliding | majority | pie | multiplier | takeTwo | dessert
        let family: String
        /// Berries on the card, or a pie's points.
        let value: Int
        /// A pie a gravy jug doubled.
        let boosted: Bool
        /// A gravy jug a pie has used.
        let spent: Bool

        init(kind: String, family: String, value: Int = 0, boosted: Bool = false, spent: Bool = false) {
            self.kind = kind
            self.family = family
            self.value = value
            self.boosted = boosted
            self.spent = spent
        }
    }

    /// One chip: a kind (strawberries and pies each grouped as one).
    struct Group: Equatable, Identifiable {
        /// The group's key: the kind, or "berries" / "pies".
        let key: String
        /// A kind to draw the chip with (the first card's).
        let sample: String
        let family: String
        let count: Int
        /// What the group is worth or holds, when that is a number: berries
        /// counted, pie points (doubled where boosted), popcorn's score, gravy
        /// jugs still waiting for a pie.
        let figure: Int?
        /// Cards a set needs: 2 for pancakes, 3 for pizza.
        let setSize: Int?

        var id: String { key }

        /// Sets finished.
        var sets: Int { setSize.map { count / $0 } ?? 0 }
        /// Cards towards the next set, 0 up to `setSize - 1`.
        var towardsNext: Int { setSize.map { count % $0 } ?? 0 }
    }

    /// Popcorn's sliding score: 1, 3, 6, 10, 14, then 18 for six or more.
    static func popcorn(_ count: Int) -> Int {
        let ladder = [0, 1, 3, 6, 10, 14, 18]
        return ladder[min(max(0, count), ladder.count - 1)]
    }

    /// The table's chips, in the order each group first appeared.
    static func groups(_ cards: [Card]) -> [Group] {
        var order: [String] = []
        var members: [String: [Card]] = [:]
        for card in cards {
            let key = groupKey(card)
            if members[key] == nil {
                order.append(key)
                members[key] = []
            }
            members[key]?.append(card)
        }
        return order.compactMap { key in
            guard let list = members[key], let first = list.first else { return nil }
            return Group(key: key, sample: first.kind, family: first.family, count: list.count,
                         figure: figure(list, family: first.family), setSize: setSize(first.family))
        }
    }

    private static func groupKey(_ card: Card) -> String {
        switch card.family {
        case "majority": return "berries"
        case "pie": return "pies"
        default: return card.kind
        }
    }

    private static func setSize(_ family: String) -> Int? {
        switch family {
        case "pair": return 2
        case "triple": return 3
        default: return nil
        }
    }

    private static func figure(_ cards: [Card], family: String) -> Int? {
        switch family {
        case "majority": return cards.reduce(0) { $0 + max(1, $1.value) }
        case "pie": return cards.reduce(0) { $0 + $1.value * ($1.boosted ? 2 : 1) }
        case "sliding": return popcorn(cards.count)
        case "multiplier": return cards.filter { !$0.spent }.count
        default: return nil
        }
    }

    /// The chip's caption: "1 of 2 for a pair", "2 pizzas", "7 points",
    /// "5 berries"; nil when there is nothing to add to the count.
    static func caption(_ group: Group) -> String? {
        switch group.family {
        case "pair":
            let done = group.sets == 1 ? "1 pair" : "\(group.sets) pairs"
            if group.towardsNext == 0 { return done }
            return group.sets > 0 ? "\(done), 1 of 2" : "1 of 2 for a pair"
        case "triple":
            let done = group.sets == 1 ? "1 whole pizza" : "\(group.sets) whole pizzas"
            if group.towardsNext == 0 { return done }
            let part = "\(group.towardsNext) of 3"
            return group.sets > 0 ? "\(done), \(part)" : "\(part) for a pizza"
        case "sliding":
            return group.figure.map { $0 == 1 ? "1 point" : "\($0) points" }
        case "pie":
            return group.figure.map { $0 == 1 ? "1 point" : "\($0) points" }
        case "majority":
            return group.figure.map { $0 == 1 ? "1 berry" : "\($0) berries" }
        case "multiplier":
            guard let waiting = group.figure else { return nil }
            return waiting > 0 ? "next pie doubles" : "used"
        default:
            return nil
        }
    }
}
