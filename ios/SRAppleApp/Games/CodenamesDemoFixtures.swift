import Foundation

// MARK: - Demo Codenames
//
// `-SRDemo` rooms for Codenames. Synthetic throughout. Four players (Alex,
// Sam, Robin, Jo) on one fixed board of 25 words and one fixed key:
//
//  - a lobby of Alex's with two teams' worth: Alex on red asking to give the
//    clues, Jo on red, Sam on blue and Robin anywhere;
//  - Alex as red's spymaster, four turns in, with the clue to give — the key
//    tinting every card, nine turned over so far;
//  - Alex as a blue operative, with Robin's "WINTER 2" up and one card
//    already turned on it — a grid of plain words and a few colours;
//  - a finished game red won, the whole key shown.
//
// The key is a FIXTURE: a phone is only ever sent it as a spymaster, and the
// operative room below leaves it out, as the server does.

extension SRDemoFixtures {

    static let demoCodenamesLobbyRoom = "g_demo_codenames_lobby"
    static let demoCodenamesSpyRoom = "g_demo_codenames_spy"
    static let demoCodenamesGuessRoom = "g_demo_codenames_guess"
    static let demoCodenamesDoneRoom = "g_demo_codenames_done"

    /// The rooms for the lobby's "Your games", left out of the store shots as
    /// Azul's are.
    static let codenamesLobbyRows = #"""
    {"id": "g_demo_codenames_lobby", "game": "codenames", "phase": "lobby", "hostName": "Alex"},
                       {"id": "g_demo_codenames_spy", "game": "codenames", "phase": "clue", "hostName": "Alex"},
                       {"id": "g_demo_codenames_guess", "game": "codenames", "phase": "guess", "hostName": "Robin"},
                       {"id": "g_demo_codenames_done", "game": "codenames", "phase": "finished", "hostName": "Sam"},
    """#

    /// The room for `id`, or nil when it is not one of Codenames'.
    static func codenamesRoom(id: String, clock: DemoClock) -> String? {
        switch id {
        case demoCodenamesLobbyRoom: return codenamesLobby(clock: clock)
        case demoCodenamesSpyRoom: return codenamesSpymaster(clock: clock)
        case demoCodenamesGuessRoom: return codenamesOperative(clock: clock)
        case demoCodenamesDoneRoom: return codenamesDone(clock: clock)
        default: return nil
        }
    }

    private static let codenamesWords = [
        "anchor", "bakery", "cable", "comet", "crown", "dragon", "engine", "feather", "glacier", "harbour",
        "jungle", "kettle", "lantern", "marble", "needle", "orbit", "piano", "quarry", "rocket", "saddle",
        "thunder", "tunnel", "violin", "walnut", "yacht",
    ]

    /// Red starts: nine red, eight blue, seven bystanders and the assassin (crown).
    private static let codenamesKey = [
        "red", "blue", "neutral", "red", "assassin", "blue", "red", "neutral", "blue", "red",
        "neutral", "blue", "red", "blue", "neutral", "red", "blue", "neutral", "red", "blue",
        "red", "neutral", "blue", "neutral", "red",
    ]

    /// The grid, a card's kind only once it is turned over (`turned`: card → who, which turn).
    private static func codenamesCards(_ turned: [Int: (by: String, turn: Int)]) -> String {
        "[" + codenamesWords.enumerated().map { i, word in
            if let touch = turned[i] {
                return "{\"i\": \(i), \"word\": \(s(word)), \"kind\": \(s(codenamesKey[i])), \"by\": \(s(touch.by)), \"turn\": \(touch.turn)}"
            }
            return "{\"i\": \(i), \"word\": \(s(word)), \"kind\": null, \"by\": null, \"turn\": null}"
        }.joined(separator: ", ") + "]"
    }

    private static var codenamesKeyJSON: String { "[" + codenamesKey.map { s($0) }.joined(separator: ", ") + "]" }

    private struct CodenamesDemoClue {
        let team: String
        let by: String
        let word: String
        let count: Int
        let cards: [(i: Int, by: String)]
    }

    private static func clueJSON(_ clue: CodenamesDemoClue, at: Date, guessesLeft: Int? = nil) -> String {
        let cards = clue.cards.map { String($0.i) }.joined(separator: ", ")
        let left = guessesLeft.map { ", \"guessesLeft\": \($0)" } ?? ""
        return "{\"team\": \(s(clue.team)), \"by\": \(s(clue.by)), \"word\": \(s(clue.word)), \"count\": \(clue.count), "
            + "\"cards\": [\(cards)], \"at\": \(ms(at))\(left)}"
    }

    /// Every card turned on these clues, with its turn.
    private static func touches(_ clues: [CodenamesDemoClue]) -> [Int: (by: String, turn: Int)] {
        var out: [Int: (by: String, turn: Int)] = [:]
        for (turn, clue) in clues.enumerated() {
            for card in clue.cards { out[card.i] = (by: card.by, turn: turn + 1) }
        }
        return out
    }

    private static func agentsLeft(_ team: String, _ turned: [Int: (by: String, turn: Int)]) -> Int {
        codenamesKey.enumerated().filter { $0.element == team && turned[$0.offset] == nil }.count
    }

    private static func codenamesTeams(_ turned: [Int: (by: String, turn: Int)], red: String, blue: String) -> String {
        "[{\"team\": \"red\", \"agents\": 9, \"left\": \(agentsLeft("red", turned)), \"spymasterId\": \(s(red))}, "
            + "{\"team\": \"blue\", \"agents\": 8, \"left\": \(agentsLeft("blue", turned)), \"spymasterId\": \(s(blue))}]"
    }

    private static func codenamesPlayer(_ id: String, _ name: String, host: Bool, team: String?, spymaster: Bool,
                                        status: String = "joined") -> String {
        "{\"id\": \(s(id)), \"name\": \(s(name)), \"status\": \(s(status)), \"isHost\": \(host), "
            + "\"team\": \(team.map { s($0) } ?? "null"), \"spymaster\": \(spymaster), \"sawInvite\": true}"
    }

    static func codenamesLobby(clock: DemoClock) -> String {
        let now = clock.now
        let players = [
            codenamesPlayer("p_alex", "Alex", host: true, team: "red", spymaster: true),
            codenamesPlayer("p_sam", "Sam", host: false, team: "blue", spymaster: false),
            codenamesPlayer("p_robin", "Robin", host: false, team: nil, spymaster: false),
            codenamesPlayer("p_jo", "Jo", host: false, team: "red", spymaster: false),
        ].joined(separator: ", ")
        return """
        {"id": \(s(demoCodenamesLobbyRoom)), "game": "codenames", "difficulty": "medium", "phase": "lobby",
         "hostId": "p_alex", "meId": "p_alex", "mode": "teams", "clueMs": 150000, "guessMs": 150000,
         "startedAt": null, "phaseEndsAt": \(ms(now.addingTimeInterval(160))), "starting": "red", "turnTeam": "red", "turns": 0,
         "cards": [], "key": null, "clue": null, "clues": [],
         "teams": [{"team": "red", "agents": 0, "left": 0, "spymasterId": null}, {"team": "blue", "agents": 0, "left": 0, "spymasterId": null}],
         "last": null, "canGuess": false, "canClue": false,
         "players": [\(players)],
         "result": null, "standings": null, "winnerIds": [], "serverNow": \(ms(now))}
        """
    }

    /// Alex gives red's clues: turn 5, red to go, the key on the phone.
    static func codenamesSpymaster(clock: DemoClock) -> String {
        let now = clock.now
        let clues = [
            CodenamesDemoClue(team: "red", by: "p_alex", word: "SEA", count: 2, cards: [(0, "p_sam"), (9, "p_sam")]),
            CodenamesDemoClue(team: "blue", by: "p_robin", word: "MUSIC", count: 2, cards: [(16, "p_jo"), (22, "p_jo"), (2, "p_jo")]),
            CodenamesDemoClue(team: "red", by: "p_alex", word: "SPACE", count: 2, cards: [(3, "p_sam"), (8, "p_sam")]),
            CodenamesDemoClue(team: "blue", by: "p_robin", word: "KITCHEN", count: 2, cards: [(11, "p_jo"), (23, "p_jo")]),
        ]
        let turned = touches(clues)
        let history = clues.enumerated().map { n, clue in clueJSON(clue, at: now.addingTimeInterval(Double(n - 4) * 120)) }
        let players = [
            codenamesPlayer("p_alex", "Alex", host: true, team: "red", spymaster: true),
            codenamesPlayer("p_sam", "Sam", host: false, team: "red", spymaster: false),
            codenamesPlayer("p_robin", "Robin", host: false, team: "blue", spymaster: true),
            codenamesPlayer("p_jo", "Jo", host: false, team: "blue", spymaster: false),
        ].joined(separator: ", ")
        return """
        {"id": \(s(demoCodenamesSpyRoom)), "game": "codenames", "difficulty": "medium", "phase": "clue",
         "hostId": "p_alex", "meId": "p_alex", "mode": "teams", "clueMs": 150000, "guessMs": 150000,
         "startedAt": \(ms(now.addingTimeInterval(-540))), "phaseEndsAt": \(ms(now.addingTimeInterval(118))),
         "starting": "red", "turnTeam": "red", "turns": 5,
         "cards": \(codenamesCards(turned)), "key": \(codenamesKeyJSON),
         "clue": null, "clues": [\(history.joined(separator: ", "))],
         "teams": \(codenamesTeams(turned, red: "p_alex", blue: "p_robin")),
         "last": {"card": 23, "kind": "neutral", "team": "blue", "by": "p_jo", "at": \(ms(now.addingTimeInterval(-32)))},
         "canGuess": false, "canClue": true,
         "players": [\(players)],
         "result": null, "standings": null, "winnerIds": [], "serverNow": \(ms(now))}
        """
    }

    /// Alex guesses for blue on Robin's "WINTER 2", one card already turned on it.
    static func codenamesOperative(clock: DemoClock) -> String {
        let now = clock.now
        let clues = [
            CodenamesDemoClue(team: "red", by: "p_sam", word: "SEA", count: 2, cards: [(0, "p_jo"), (9, "p_jo")]),
            CodenamesDemoClue(team: "blue", by: "p_robin", word: "MUSIC", count: 2, cards: [(16, "p_alex"), (22, "p_alex"), (2, "p_alex")]),
            CodenamesDemoClue(team: "red", by: "p_sam", word: "SPACE", count: 3, cards: [(3, "p_jo"), (18, "p_jo"), (15, "p_jo"), (13, "p_jo")]),
            CodenamesDemoClue(team: "blue", by: "p_robin", word: "WINTER", count: 2, cards: [(8, "p_alex")]),
        ]
        let turned = touches(clues)
        let history = clues.enumerated().map { n, clue in clueJSON(clue, at: now.addingTimeInterval(Double(n - 4) * 120)) }
        let players = [
            codenamesPlayer("p_robin", "Robin", host: true, team: "blue", spymaster: true),
            codenamesPlayer("p_alex", "Alex", host: false, team: "blue", spymaster: false),
            codenamesPlayer("p_sam", "Sam", host: false, team: "red", spymaster: true),
            codenamesPlayer("p_jo", "Jo", host: false, team: "red", spymaster: false),
        ].joined(separator: ", ")
        return """
        {"id": \(s(demoCodenamesGuessRoom)), "game": "codenames", "difficulty": "medium", "phase": "guess",
         "hostId": "p_robin", "meId": "p_alex", "mode": "teams", "clueMs": 150000, "guessMs": 150000,
         "startedAt": \(ms(now.addingTimeInterval(-600))), "phaseEndsAt": \(ms(now.addingTimeInterval(96))),
         "starting": "red", "turnTeam": "blue", "turns": 4,
         "cards": \(codenamesCards(turned)), "key": null,
         "clue": \(clueJSON(clues[3], at: now.addingTimeInterval(-40), guessesLeft: 2)),
         "clues": [\(history.dropLast().joined(separator: ", ")), \(clueJSON(clues[3], at: now.addingTimeInterval(-40)))],
         "teams": \(codenamesTeams(turned, red: "p_sam", blue: "p_robin")),
         "last": {"card": 8, "kind": "blue", "team": "blue", "by": "p_alex", "at": \(ms(now.addingTimeInterval(-12)))},
         "canGuess": true, "canClue": false,
         "players": [\(players)],
         "result": null, "standings": null, "winnerIds": [], "serverNow": \(ms(now))}
        """
    }

    /// Red found all nine; Alex was on red. The whole key is everyone's now.
    static func codenamesDone(clock: DemoClock) -> String {
        let now = clock.now
        let clues = [
            CodenamesDemoClue(team: "red", by: "p_sam", word: "SEA", count: 2, cards: [(0, "p_alex"), (9, "p_alex")]),
            CodenamesDemoClue(team: "blue", by: "p_robin", word: "MUSIC", count: 2, cards: [(16, "p_jo"), (22, "p_jo"), (2, "p_jo")]),
            CodenamesDemoClue(team: "red", by: "p_sam", word: "SPACE", count: 3, cards: [(3, "p_alex"), (18, "p_alex"), (15, "p_alex")]),
            CodenamesDemoClue(team: "blue", by: "p_robin", word: "WINTER", count: 2, cards: [(8, "p_jo"), (7, "p_jo")]),
            CodenamesDemoClue(team: "red", by: "p_sam", word: "LIGHT", count: 3, cards: [(12, "p_alex"), (20, "p_alex"), (6, "p_alex")]),
            CodenamesDemoClue(team: "blue", by: "p_robin", word: "BREAD", count: 1, cards: [(1, "p_jo"), (10, "p_jo")]),
            CodenamesDemoClue(team: "red", by: "p_sam", word: "BOAT", count: 1, cards: [(24, "p_alex")]),
        ]
        let turned = touches(clues)
        let history = clues.enumerated().map { n, clue in clueJSON(clue, at: now.addingTimeInterval(Double(n - 7) * 110)) }
        let players = [
            codenamesPlayer("p_sam", "Sam", host: true, team: "red", spymaster: true),
            codenamesPlayer("p_alex", "Alex", host: false, team: "red", spymaster: false),
            codenamesPlayer("p_robin", "Robin", host: false, team: "blue", spymaster: true),
            codenamesPlayer("p_jo", "Jo", host: false, team: "blue", spymaster: false),
        ].joined(separator: ", ")
        let blueFound = 8 - agentsLeft("blue", turned)
        return """
        {"id": \(s(demoCodenamesDoneRoom)), "game": "codenames", "difficulty": "easy", "phase": "finished",
         "hostId": "p_sam", "meId": "p_alex", "mode": "teams", "clueMs": 300000, "guessMs": 300000,
         "startedAt": \(ms(now.addingTimeInterval(-1500))), "phaseEndsAt": \(ms(now.addingTimeInterval(500))),
         "starting": "red", "turnTeam": "red", "turns": 7,
         "cards": \(codenamesCards(turned)), "key": \(codenamesKeyJSON),
         "clue": null, "clues": [\(history.joined(separator: ", "))],
         "teams": \(codenamesTeams(turned, red: "p_sam", blue: "p_robin")),
         "last": {"card": 24, "kind": "red", "team": "red", "by": "p_alex", "at": \(ms(now.addingTimeInterval(-20)))},
         "canGuess": false, "canClue": false,
         "players": [\(players)],
         "result": {"winner": "red", "reason": "agents"},
         "standings": [
           {"id": "p_sam", "name": "Sam", "team": "red", "spymaster": true, "score": 9, "place": 1, "result": "won"},
           {"id": "p_alex", "name": "Alex", "team": "red", "spymaster": false, "score": 9, "place": 1, "result": "won"},
           {"id": "p_robin", "name": "Robin", "team": "blue", "spymaster": true, "score": \(blueFound), "place": 2, "result": "lost"},
           {"id": "p_jo", "name": "Jo", "team": "blue", "spymaster": false, "score": \(blueFound), "place": 2, "result": "lost"}],
         "winnerIds": ["p_sam", "p_alex"], "serverNow": \(ms(now))}
        """
    }
}
