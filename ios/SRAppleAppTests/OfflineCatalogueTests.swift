import XCTest
@testable import SRAppleApp

/// The whole set of offline games, taken together: twenty-one of them, in three
/// sections, each with an id the wire can carry and a player range the room
/// can seat — and every one of them able to start, show each seat its view,
/// tick along unattended, lose a player and still produce a table, for the
/// smallest and the largest room it allows.
///
/// `OfflineCatalogue` itself pairs each game with a SwiftUI view, so it only
/// compiles where SwiftUI does (Xcode, CI). The roster below names the same
/// games' rules in the same order, so the sweep also runs on Linux in
/// `scripts/offline-check.sh`; on CI the last tests check that the catalogue
/// and this roster agree, and sweep the catalogue's own entries too.
final class OfflineCatalogueTests: XCTestCase {

    /// The catalogue's games, in its order: card, then reaction, then skill.
    private static let roster: [OfflineGameEntry] = [
        OfflineGameEntry(withBot: CrazyEightsRules.self),
        OfflineGameEntry(GoFishRules.self),
        OfflineGameEntry(BlackjackRules.self),
        OfflineGameEntry(CheatRules.self),
        OfflineGameEntry(OldMaidRules.self),
        OfflineGameEntry(KnockoutWhistRules.self),
        OfflineGameEntry(HigherLowerRules.self),
        OfflineGameEntry(QuickDrawRules.self),
        OfflineGameEntry(SnapRules.self),
        OfflineGameEntry(ColourClashRules.self),
        OfflineGameEntry(WhackAMoleRules.self),
        OfflineGameEntry(HotPotatoRules.self),
        OfflineGameEntry(SwipeSaysRules.self),
        OfflineGameEntry(ReflexGridRules.self),
        OfflineGameEntry(OfflineSprintRules.self),
        OfflineGameEntry(withBot: DotsAndBoxesRules.self),
        OfflineGameEntry(MemoryPairsRules.self),
        OfflineGameEntry(withBot: FourInARowRules.self),
        OfflineGameEntry(CodeBreakerRules.self),
        OfflineGameEntry(SteadyHandRules.self),
        OfflineGameEntry(SeaBattleRules.self),
        OfflineGameEntry(CarRaceNearbyRules.self),
    ]

    private static let expectedIds = [
        "crazy-eights", "go-fish", "blackjack", "cheat", "old-maid", "knockout-whist", "higher-lower",
        "quick-draw", "snap", "colour-clash", "whack-a-mole", "hot-potato", "swipe-says", "reflex-grid",
        "maths-sprint", "dots-and-boxes", "memory-pairs", "four-in-a-row", "code-breaker", "steady-hand", "sea-battle",
        "car-race",
    ]

    private static let seeds: [UInt64] = [1, 7, 42, 2026, 0xDEAD_BEEF]

    // MARK: - The list

    func testTheRosterIsTwentyTwoGamesInThreeSections() {
        checkTheList(Self.roster)
    }

    func testEveryGamePassesTheAudit() {
        // The per-game tests run this too; here it guards a game whose own
        // test file went missing.
        for entry in Self.roster {
            XCTAssertEqual(audit(entry.info.id), [], entry.info.id)
        }
    }

    // MARK: - The sweep

    func testEveryGameStartsShowsAndRanksAtItsSmallestAndLargestTable() {
        sweep(Self.roster)
    }

    func testEveryGameRunsThroughTheRoomAtItsLargestTable() throws {
        for entry in Self.roster {
            let info = entry.info
            let host = OfflinePlayer(id: "p1", name: "Player 1")
            var room = OfflineRoom(host: host, roomName: "Sweep", games: Self.roster)
            if info.maxPlayers > 1 {
                for n in 2...info.maxPlayers {
                    try room.join(OfflinePlayer(id: "p\(n)", name: "Player \(n)"), version: OfflineEnvelope.version)
                }
            }
            try room.choose(info.id)
            XCTAssertNil(room.startProblem, info.id)
            try room.start(seed: 99, now: 1_000)
            let first = room.outbox()
            let viewed = Set(first.compactMap { item -> String? in
                if case .view(let packet) = item.message, packet.gameId == info.id { return item.to }
                return nil
            })
            XCTAssertEqual(viewed, Set(room.players.map(\.id)), "\(info.id): every seat is sent a view")

            for step in 1...50 { room.tick(now: 1_000 + Double(step) / 10) }
            _ = room.outbox()
            room.endMatch()
            XCTAssertEqual(room.phase, .finished, info.id)
            XCTAssertEqual(room.standings?.count, info.maxPlayers, "\(info.id): the table lists everyone")
            room.backToLobby()
            XCTAssertEqual(room.phase, .lobby, info.id)
        }
    }

    // MARK: - The catalogue itself (SwiftUI, so Xcode only)

    func testTheGamesWithABotAreTheOnesThatSayTheyHaveOne() {
        let bots = Self.roster.filter(\.hasBot).map(\.info.id)
        XCTAssertEqual(bots, ["crazy-eights", "dots-and-boxes", "four-in-a-row"])
        // Alone: every one-player game, and every game with a bot.
        let solo = Self.roster.filter { OfflinePlayModes.canPlaySolo($0.info, hasBot: $0.hasBot) }.map(\.info.id)
        XCTAssertEqual(solo, ["crazy-eights", "blackjack", "higher-lower", "reflex-grid", "maths-sprint",
                              "dots-and-boxes", "four-in-a-row", "code-breaker", "steady-hand"])
    }

    #if canImport(SwiftUI)
    func testTheCatalogueListsTheRosterInOrder() {
        XCTAssertEqual(OfflineCatalogue.items.map(\.id), Self.expectedIds)
        checkTheList(OfflineCatalogue.entries)
        XCTAssertEqual(OfflineCatalogue.games(in: .card).count, 7)
        XCTAssertEqual(OfflineCatalogue.games(in: .reaction).count, 7)
        XCTAssertEqual(OfflineCatalogue.games(in: .skill).count, 8)
        for id in Self.expectedIds {
            XCTAssertEqual(OfflineCatalogue.item(id)?.id, id)
        }
    }

    func testEveryCatalogueEngineStartsShowsAndRanks() {
        sweep(OfflineCatalogue.entries)
    }

    /// What the Games page asks: by offline id, or an online game's id.
    func testTheGamesPageCanAskHowAGameCanBePlayed() {
        XCTAssertTrue(OfflineCatalogue.canPlaySolo("maths-sprint"))
        XCTAssertTrue(OfflineCatalogue.canPlaySolo("four-in-a-row"))
        XCTAssertFalse(OfflineCatalogue.canPlaySolo("snap"))
        XCTAssertTrue(OfflineCatalogue.canPlayNearby("snap"))
        XCTAssertFalse(OfflineCatalogue.canPlaySolo("boggle"), "no offline Boggle yet")
        XCTAssertFalse(OfflineCatalogue.canPlayNearby("boggle"))
        XCTAssertEqual(OfflineCatalogue.soloGames.count, 9)
    }
    #endif

    // MARK: - Helpers

    private func checkTheList(_ entries: [OfflineGameEntry], file: StaticString = #filePath, line: UInt = #line) {
        let infos = entries.map(\.info)
        XCTAssertEqual(infos.count, 22, file: file, line: line)
        XCTAssertEqual(infos.map(\.id), Self.expectedIds, file: file, line: line)
        XCTAssertEqual(Set(infos.map(\.id)).count, infos.count, "ids are unique", file: file, line: line)
        XCTAssertEqual(Set(infos.map(\.title)).count, infos.count, "titles are unique", file: file, line: line)
        XCTAssertEqual(infos.filter { $0.category == .card }.count, 7, file: file, line: line)
        XCTAssertEqual(infos.filter { $0.category == .reaction }.count, 7, file: file, line: line)
        XCTAssertEqual(infos.filter { $0.category == .skill }.count, 8, file: file, line: line)
        // Grouped by section, in the order the page shows them.
        let sections = infos.map(\.category)
        XCTAssertEqual(sections, Array(repeating: .card, count: 7) + Array(repeating: .reaction, count: 7)
                       + Array(repeating: .skill, count: 8), file: file, line: line)
        for info in infos {
            XCTAssertTrue(info.minPlayers >= 1 && info.minPlayers <= info.maxPlayers
                          && info.maxPlayers <= OfflineRoom.capacity,
                          "\(info.id): \(info.minPlayers)…\(info.maxPlayers) players", file: file, line: line)
            XCTAssertFalse(info.howToPlay.isEmpty, info.id, file: file, line: line)
        }
    }

    /// For each game, each seed, and its smallest and largest table: start,
    /// read every seat's view and the spectator's, tick a minute and a half
    /// with nobody touching anything, drop the last guest, tick again — and
    /// at every stop the views must be JSON objects and the table must list
    /// each starting player exactly once, best first.
    private func sweep(_ entries: [OfflineGameEntry], file: StaticString = #filePath, line: UInt = #line) {
        for entry in entries {
            let info = entry.info
            for count in Array(Set([info.minPlayers, info.maxPlayers])).sorted() {
                let players = (1...count).map { OfflinePlayer(id: "p\($0)", name: "Player \($0)") }
                for seed in Self.seeds {
                    let label = "\(info.id), \(count) players, seed \(seed)"
                    var now = 1_000.0
                    var match = entry.begin(players, seed, now)
                    XCTAssertEqual(match.players, players, label, file: file, line: line)
                    checkViewsAndTable(match, players: players, label: "\(label), at the start", file: file, line: line)

                    for step in 1...900 {
                        now = 1_000 + Double(step) / 10
                        match.tick(now: now)
                        if step % 150 == 0 {
                            checkViewsAndTable(match, players: players, label: "\(label), after \(step / 10) s", file: file, line: line)
                        }
                    }

                    if count > 1 {
                        match.playerLeft(players[count - 1].id, now: now)
                        checkViewsAndTable(match, players: players, label: "\(label), after a drop", file: file, line: line)
                        for step in 1...300 { match.tick(now: now + Double(step) / 10) }
                        checkViewsAndTable(match, players: players, label: "\(label), after the drop settles", file: file, line: line)
                    }
                }
            }
        }
    }

    private func checkViewsAndTable(_ match: any OfflineMatch, players: [OfflinePlayer], label: String,
                                    file: StaticString, line: UInt) {
        for id in players.map({ Optional($0.id) }) + [nil] {
            let data = match.viewData(for: id)
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            XCTAssertNotNil(object, "\(label): view for \(id ?? "a spectator") is a JSON object", file: file, line: line)
        }
        let table = match.standings
        XCTAssertEqual(table.count, players.count, "\(label): standings list everyone", file: file, line: line)
        XCTAssertEqual(Set(table.map(\.playerId)), Set(players.map(\.id)), "\(label): standings list each player once",
                       file: file, line: line)
        XCTAssertEqual(table.first?.rank, 1, "\(label): someone is first", file: file, line: line)
        for (index, standing) in table.enumerated() {
            XCTAssertTrue(standing.rank >= 1 && standing.rank <= index + 1, "\(label): rank \(standing.rank) at row \(index + 1)",
                          file: file, line: line)
            if index > 0 {
                XCTAssertTrue(table[index - 1].rank <= standing.rank, "\(label): ranks run best first", file: file, line: line)
            }
        }
    }

    /// `OfflineRulesAudit` needs the concrete rules type; the roster has
    /// erased it, so look it up by id.
    private func audit(_ id: String) -> [String] {
        switch id {
        case "crazy-eights": return OfflineRulesAudit.problems(CrazyEightsRules.self)
        case "go-fish": return OfflineRulesAudit.problems(GoFishRules.self)
        case "blackjack": return OfflineRulesAudit.problems(BlackjackRules.self)
        case "cheat": return OfflineRulesAudit.problems(CheatRules.self)
        case "old-maid": return OfflineRulesAudit.problems(OldMaidRules.self)
        case "knockout-whist": return OfflineRulesAudit.problems(KnockoutWhistRules.self)
        case "higher-lower": return OfflineRulesAudit.problems(HigherLowerRules.self)
        case "quick-draw": return OfflineRulesAudit.problems(QuickDrawRules.self)
        case "snap": return OfflineRulesAudit.problems(SnapRules.self)
        case "colour-clash": return OfflineRulesAudit.problems(ColourClashRules.self)
        case "whack-a-mole": return OfflineRulesAudit.problems(WhackAMoleRules.self)
        case "hot-potato": return OfflineRulesAudit.problems(HotPotatoRules.self)
        case "swipe-says": return OfflineRulesAudit.problems(SwipeSaysRules.self)
        case "reflex-grid": return OfflineRulesAudit.problems(ReflexGridRules.self)
        case "maths-sprint": return OfflineRulesAudit.problems(OfflineSprintRules.self)
        case "dots-and-boxes": return OfflineRulesAudit.problems(DotsAndBoxesRules.self)
        case "memory-pairs": return OfflineRulesAudit.problems(MemoryPairsRules.self)
        case "four-in-a-row": return OfflineRulesAudit.problems(FourInARowRules.self)
        case "code-breaker": return OfflineRulesAudit.problems(CodeBreakerRules.self)
        case "steady-hand": return OfflineRulesAudit.problems(SteadyHandRules.self)
        case "sea-battle": return OfflineRulesAudit.problems(SeaBattleRules.self)
        case "car-race": return OfflineRulesAudit.problems(CarRaceNearbyRules.self)
        default: return ["no rules type for '\(id)'"]
        }
    }
}
