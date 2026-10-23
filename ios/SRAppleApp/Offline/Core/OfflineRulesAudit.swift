import Foundation

/// The checks every offline game must pass, whatever its rules — run from each
/// game's tests as `XCTAssertEqual(OfflineRulesAudit.problems(MyRules.self), [])`.
///
/// It cannot play a game (it does not know the actions), but it catches the
/// mistakes that otherwise only show on a phone: an id the catalogue cannot
/// use, a player range the room cannot seat, a state or view that does not
/// survive the trip through JSON, a seed that does not reproduce, a table
/// that forgets somebody, a `tick` that changes the state when nothing has
/// happened twice at the same instant.
enum OfflineRulesAudit {
    /// Sentences describing what is wrong; empty when nothing is.
    static func problems<Rules: OfflineGameRules>(_ rules: Rules.Type, seed: UInt64 = 7) -> [String] {
        var out: [String] = []
        let info = Rules.info

        if info.id.range(of: "^[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression) == nil {
            out.append("id '\(info.id)' is not kebab-case")
        }
        if info.title.trimmingCharacters(in: .whitespaces).isEmpty { out.append("title is empty") }
        if info.blurb.trimmingCharacters(in: .whitespaces).isEmpty { out.append("blurb is empty") }
        if info.symbol.isEmpty { out.append("symbol is empty") }
        if info.howToPlay.isEmpty { out.append("howToPlay has no lines") }
        if info.minPlayers < 1 { out.append("minPlayers is below 1") }
        if info.maxPlayers > OfflineRoom.capacity { out.append("maxPlayers is above \(OfflineRoom.capacity)") }
        if info.minPlayers > info.maxPlayers { out.append("minPlayers is above maxPlayers") }
        guard info.minPlayers >= 1, info.minPlayers <= info.maxPlayers, info.maxPlayers <= OfflineRoom.capacity else {
            return out
        }

        for count in info.minPlayers...info.maxPlayers {
            let players = (1...count).map { OfflinePlayer(id: "p\($0)", name: "Player \($0)") }
            let now = 1_000.0

            var rngA = OfflineRNG(seed: seed)
            var rngB = OfflineRNG(seed: seed)
            var state = Rules.start(players: players, now: now, rng: &rngA)
            let again = Rules.start(players: players, now: now, rng: &rngB)
            // Two different matches from one seed means randomness that did
            // not come from `rng` (or a Set/Dictionary order leaking in).
            if state != again || rngA != rngB { out.append("\(count) players: the same seed started two different matches") }

            if let data = try? OfflineCoding.encode(state),
               let back = try? OfflineCoding.decode(Rules.State.self, from: data) {
                if back != state { out.append("\(count) players: State changes on a JSON round trip") }
            } else {
                out.append("\(count) players: State does not encode and decode")
            }

            for id in players.map({ Optional($0.id) }) + [nil] {
                let view = Rules.view(of: state, for: id)
                if let data = try? OfflineCoding.encode(view),
                   let back = try? OfflineCoding.decode(Rules.PlayerView.self, from: data) {
                    if back != view { out.append("\(count) players: PlayerView for \(id ?? "a spectator") changes on a JSON round trip") }
                } else {
                    out.append("\(count) players: PlayerView for \(id ?? "a spectator") does not encode and decode")
                }
            }

            let table = Rules.standings(state)
            if Set(table.map(\.playerId)) != Set(players.map(\.id)) || table.count != players.count {
                out.append("\(count) players: standings do not list each player exactly once")
            }

            // Ten seconds of ticks, then the same instant again: must be a no-op.
            var rng = rngA
            for step in 1...100 { Rules.tick(&state, now: now + Double(step) / 10, rng: &rng) }
            let settled = state
            Rules.tick(&state, now: now + 10, rng: &rng)
            if state != settled { out.append("\(count) players: tick twice at the same time changed the state") }
        }
        return out
    }
}
