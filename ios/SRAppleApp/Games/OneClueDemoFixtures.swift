import Foundation

// MARK: - Demo One Clue
//
// `-SRDemo` rooms for One Clue, kept beside the game rather than in
// `GamesDemoFixtures.swift` so that file only routes to them. Synthetic
// throughout. Three rooms, all medium, Alex, Sam and Robin (Kim in the
// finished one):
// - writing: card 4 of 10, Sam guessing, Alex giving a clue for "lighthouse"
//   (Robin has written one, Alex has not), team on 2;
// - guessing: card 6, Alex guessing, two clues survived and two were
//   cancelled — the wire carries only the survivors and the count, exactly as
//   the site sends a guesser;
// - finished: seven out of ten, every card listed.

extension SRDemoFixtures {
    static let demoOneClueRoom = "g_demo_oneclue"
    static let demoOneClueGuessRoom = "g_demo_oneclue_guess"
    static let demoOneClueDoneRoom = "g_demo_oneclue_done"

    /// One Clue's three rooms, for the lobby list. Left out of the store shots, as Chess's are.
    static let oneClueLobbyRows = #"""
    {"id": "g_demo_oneclue", "game": "one-clue", "phase": "clues", "hostName": "Alex"},
                       {"id": "g_demo_oneclue_guess", "game": "one-clue", "phase": "guess", "hostName": "Sam"},
                       {"id": "g_demo_oneclue_done", "game": "one-clue", "phase": "finished", "hostName": "Alex"},
    """#

    /// The room for one of One Clue's demo ids, or nil for any other id.
    static func oneClueDemoRoom(id: String, clock: DemoClock) -> String? {
        switch id {
        case demoOneClueRoom: return oneClueRoom(.clues, clock: clock)
        case demoOneClueGuessRoom: return oneClueRoom(.guess, clock: clock)
        case demoOneClueDoneRoom: return oneClueRoom(.finished, clock: clock)
        default: return nil
        }
    }

    /// Cards already over: `won` of the first `count`, with one discarded after a wrong guess.
    private static func oneClueCards(_ count: Int) -> String {
        let deck: [(String, String, String, [(String, String, String)])] = [
            ("castle", "p_alex", "correct", [("p_sam", "Knight", "ok"), ("p_robin", "Moat", "ok")]),
            ("thunder", "p_sam", "passed", [("p_alex", "Storm", "duplicate"), ("p_robin", "storms", "duplicate")]),
            ("pilot", "p_robin", "correct", [("p_alex", "Cockpit", "ok"), ("p_sam", "Plane", "ok")]),
            ("fox", "p_alex", "wrong", [("p_sam", "Sly", "ok"), ("p_robin", "Orange", "ok")]),
            ("violin", "", "discarded", []),
            ("glove", "p_sam", "correct", [("p_alex", "Hand", "ok"), ("p_robin", "Mitten", "vetoed")]),
            ("compass", "p_robin", "correct", [("p_alex", "North", "ok"), ("p_sam", "Needle", "ok")]),
            ("parade", "p_alex", "correct", [("p_sam", "March", "ok"), ("p_robin", "Floats", "ok")]),
            ("igloo", "p_sam", "correct", [("p_alex", "Ice", "ok"), ("p_robin", "Arctic", "vetoed")]),
            ("statue", "p_robin", "correct", [("p_alex", "Stone", "ok"), ("p_sam", "Still", "ok")]),
        ]
        return deck.prefix(count).enumerated().map { index, card in
            let clues = card.3.map { "{\"playerId\": \(s($0.0)), \"text\": \(s($0.1)), \"status\": \(s($0.2))}" }
                .joined(separator: ", ")
            let guesser = card.1.isEmpty ? "null" : s(card.1)
            let guess = card.2 == "wrong" ? s("wolf") : card.2 == "correct" ? s(card.0) : "null"
            return "{\"index\": \(index), \"word\": \(s(card.0)), \"guesserId\": \(guesser), \"outcome\": \(s(card.2)), "
                + "\"guess\": \(guess), \"tookBack\": false, \"clues\": [\(clues)]}"
        }.joined(separator: ", ")
    }

    private static func oneClueRoom(_ phase: OneCluePhase, clock: DemoClock) -> String {
        let now = clock.now
        func player(_ id: String, _ name: String, host: Bool, role: String?, submitted: Bool = false) -> String {
            "{\"id\": \(s(id)), \"name\": \(s(name)), \"status\": \"joined\", \"isHost\": \(host), "
                + "\"role\": \(role.map { s($0) } ?? "null"), \"submitted\": \(submitted), \"done\": false}"
        }
        let common = """
        "game": "one-clue", "difficulty": "medium", "cardCount": 10, "minPlayers": 3, "maxPlayers": 7,
         "clueMs": 75000, "reviewMs": 30000, "guessMs": 60000, "revealMs": 12000, "maxClue": 30, "maxGuess": 40,
         "startedAt": \(ms(now.addingTimeInterval(-300))), "winnerIds": []
        """
        switch phase {
        case .guess:
            // Card 6 (index 5): Alex guesses "glove". Only the survivors, and the count.
            return """
            {"id": \(s(demoOneClueGuessRoom)), \(common), "phase": "guess", "hostId": "p_sam", "meId": "p_alex",
             "phaseEndsAt": \(ms(now.addingTimeInterval(48))), "score": 2, "cardIndex": 5, "guesserId": "p_alex",
             "role": "guesser", "word": null, "myClue": null,
             "clues": [{"playerId": "p_sam", "text": "Hand", "status": "ok", "vetoes": 0, "strikeAt": 0, "vetoed": false},
                       {"playerId": "p_robin", "text": "Winter", "status": "ok", "vetoes": 0, "strikeAt": 0, "vetoed": false}],
             "cancelledCount": 2, "guess": null, "outcome": null, "tookBack": false,
             "cards": [\(oneClueCards(5))],
             "players": [\(player("p_sam", "Sam", host: true, role: "clue")),
                         \(player("p_alex", "Alex", host: false, role: "guesser")),
                         \(player("p_robin", "Robin", host: false, role: "clue")),
                         \(player("p_kim", "Kim", host: false, role: "clue")),
                         \(player("p_jo", "Jo", host: false, role: "clue"))],
             "standings": null, "verdict": null, "serverNow": \(ms(now))}
            """
        case .finished:
            return """
            {"id": \(s(demoOneClueDoneRoom)), \(common), "phase": "finished", "hostId": "p_alex", "meId": "p_alex",
             "phaseEndsAt": \(ms(now.addingTimeInterval(540))), "score": 7, "cardIndex": null, "guesserId": null,
             "role": null, "word": null, "myClue": null, "clues": null, "cancelledCount": null,
             "guess": null, "outcome": null, "tookBack": false,
             "cards": [\(oneClueCards(10))],
             "players": [\(player("p_alex", "Alex", host: true, role: nil)),
                         \(player("p_sam", "Sam", host: false, role: nil)),
                         \(player("p_robin", "Robin", host: false, role: nil))],
             "standings": [{"id": "p_robin", "name": "Robin", "score": 7, "guessed": 3, "clues": 6},
                           {"id": "p_sam", "name": "Sam", "score": 7, "guessed": 2, "clues": 8},
                           {"id": "p_alex", "name": "Alex", "score": 7, "guessed": 2, "clues": 8}],
             "verdict": "A good game.", "serverNow": \(ms(now))}
            """
        default:
            // Card 4 (index 3) of a fresh deal: Sam guesses, Alex writes for "lighthouse".
            return """
            {"id": \(s(demoOneClueRoom)), \(common), "phase": "clues", "hostId": "p_alex", "meId": "p_alex",
             "phaseEndsAt": \(ms(now.addingTimeInterval(52))), "score": 2, "cardIndex": 3, "guesserId": "p_sam",
             "role": "clue", "word": "lighthouse", "myClue": "", "clues": null, "cancelledCount": null,
             "guess": null, "outcome": null, "tookBack": false,
             "cards": [\(oneClueCards(3))],
             "players": [\(player("p_alex", "Alex", host: true, role: "clue")),
                         \(player("p_sam", "Sam", host: false, role: "guesser")),
                         \(player("p_robin", "Robin", host: false, role: "clue", submitted: true))],
             "standings": null, "verdict": null, "serverNow": \(ms(now))}
            """
        }
    }
}
