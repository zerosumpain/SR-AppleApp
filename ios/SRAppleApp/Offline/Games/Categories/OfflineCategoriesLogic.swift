import Foundation

/// Categories with no internet: one letter, a card of eight categories and
/// two minutes to write an answer for each, alone or with up to four phones.
///
/// The site's Categories deals and judges on the server; this deals the same
/// cards (the site's list, below) and judges on the host phone by the site's
/// simple rules, with no word list and no model:
///
/// - an answer scores a point if it starts with the letter — read the site's
///   way, so "The Beatles" is a B and accents do not matter;
/// - with others, an answer somebody else also wrote for that category
///   (spaces and case aside) scores nothing for either of them;
/// - with others, there is then a review: every answer is shown and anyone
///   may veto someone else's. Half the other players still here (rounded up)
///   strike it — with two of you, the other one's veto is enough. The review
///   ends when everybody says Done, or after `reviewSeconds`.
///
/// Alone there is nobody to veto or share with, so every answer with the
/// right letter counts and the score is a personal best to beat. The review
/// still shows the card, judged, until you tap Done.
///
/// While the clock runs a player sees only their own answers and how many
/// slots everyone else has filled.
enum OfflineCategoriesRules: OfflineGameRules {
    static let seconds: Double = 120
    static let countdown: Double = 3
    /// After the clock, how long an answer already in the air may still land.
    static let grace: Double = 1
    static let reviewSeconds: Double = 60
    /// Alone there is nothing to veto; the card stays up until Done, or this.
    static let soloReviewSeconds: Double = 90
    static let cardSize = 8
    /// Longest answer kept, in characters, as on the site.
    static let maxAnswer = 40
    /// Letters plenty of everyday words start with — the site's easy pool.
    static let letters = Array("abcdefghlmnprstw").map { String($0) }

    static let info = OfflineGameInfo(
        id: "categories",
        title: "Categories",
        blurb: "One letter, eight categories, two minutes. Fill every line.",
        category: .skill,
        minPlayers: 1,
        maxPlayers: 5,
        symbol: "list.bullet.rectangle.fill",
        howToPlay: [
            "Everyone gets the same letter and the same card of \(cardSize) categories.",
            "Write one answer for each that starts with the letter: an animal, B — badger.",
            "A point for each answer with the right letter.",
            "With others, the same answer as someone else scores nothing for either of you.",
            "Then everyone reviews the answers: half the others vetoing one strikes it out.",
            "Most points wins. Play alone to beat your best."
        ]
    )

    // MARK: - State

    enum Phase: String, Codable, Equatable {
        /// "3, 2, 1" until `startsAt`; the letter and card are hidden.
        case countdown
        case playing
        /// Time is up: every answer shown, vetoes, Done.
        case review
        case over
    }

    struct State: Codable, Equatable {
        var players: [OfflinePlayer]
        var away: [String] = []
        /// Lower case.
        var letter: String
        var categories: [String]
        /// Each player's answers, one a category; "" is blank.
        var answers: [String: [String]]
        /// Vetoes on an answer, keyed "<owner id>|<index>", in the order made.
        var vetoes: [String: [String]] = [:]
        /// Who has said Done in the review.
        var done: [String] = []
        var phase: Phase = .countdown
        var startsAt: Double
        var endsAt: Double
        var reviewUntil: Double = 0
    }

    enum Action: Codable, Equatable {
        /// My answer for category `index`, written over what was there.
        case answer(index: Int, text: String)
        /// In the review: veto someone else's answer, or take my veto back.
        case veto(owner: String, index: Int, on: Bool)
        /// In the review: I have seen enough.
        case done
    }

    // MARK: - What a player sees

    /// How an answer was judged, from the review on.
    enum Status: String, Codable, Equatable {
        case ok
        case shared
        case wrongLetter
        case struck
        case empty
    }

    struct Answer: Codable, Equatable, Identifiable {
        let owner: String
        let index: Int
        let text: String
        let status: Status
        /// Vetoes against it, and how many strike it (0: nobody can veto).
        let vetoes: Int
        let strikeAt: Int
        /// The player looking has vetoed it.
        let vetoedByMe: Bool

        var id: String { "\(owner)|\(index)" }
        var points: Int { status == .ok ? 1 : 0 }
    }

    struct Row: Codable, Equatable, Identifiable {
        let id: String
        let name: String
        let filled: Int
        /// Points as judged now; 0 until the review.
        let score: Int
        let away: Bool
        let done: Bool
    }

    struct PlayerView: Codable, Equatable {
        let phase: Phase
        let startsAt: Double
        let endsAt: Double
        let reviewUntil: Double
        /// Nil, and the card empty, until the countdown ends.
        let letter: String?
        let categories: [String]
        /// My answers as the host has them; nil for a spectator.
        let mine: [String]?
        let board: [Row]
        /// The review: for each category, every player's answer in seat order.
        let review: [[Answer]]?
        /// More than one player: shared answers score nothing and there are vetoes.
        let together: Bool
    }

    // MARK: - Rules

    static func start(players: [OfflinePlayer], now: Double, rng: inout OfflineRNG) -> State {
        let letter = letters[rng.int(below: letters.count)]
        var pool = card
        // A partial shuffle: the first `cardSize` places are the card.
        for i in 0..<min(cardSize, pool.count) {
            let j = i + rng.int(below: pool.count - i)
            pool.swapAt(i, j)
        }
        let categories = Array(pool.prefix(cardSize))
        var answers: [String: [String]] = [:]
        for player in players { answers[player.id] = Array(repeating: "", count: categories.count) }
        return State(players: players, letter: letter, categories: categories, answers: answers,
                     startsAt: now + countdown, endsAt: now + countdown + seconds)
    }

    static func apply(_ action: Action, by playerId: String, to state: inout State, now: Double, rng: inout OfflineRNG) throws {
        guard var mine = state.answers[playerId] else { throw OfflineRefusal("You are not in this game.") }
        switch action {
        case .answer(let index, let text):
            guard state.phase == .playing, now < state.endsAt + grace else {
                throw OfflineRefusal(state.phase == .countdown ? "Wait for the start." : "Time's up.")
            }
            guard mine.indices.contains(index) else { throw OfflineRefusal("That category isn't on the card.") }
            mine[index] = clean(text)
            state.answers[playerId] = mine
        case .veto(let owner, let index, let on):
            guard state.phase == .review else {
                throw OfflineRefusal(state.phase == .over ? "That game is over." : "Vetoes come after the clock.")
            }
            guard owner != playerId else { throw OfflineRefusal("You can't veto your own answer.") }
            guard let theirs = state.answers[owner] else { throw OfflineRefusal("They are not in this game.") }
            guard theirs.indices.contains(index), !theirs[index].isEmpty else {
                throw OfflineRefusal("There is nothing there to veto.")
            }
            let key = vetoKey(owner, index)
            var by = (state.vetoes[key] ?? []).filter { $0 != playerId }
            if on { by.append(playerId) }
            state.vetoes[key] = by.isEmpty ? nil : by
        case .done:
            guard state.phase == .review else { throw OfflineRefusal("Not yet.") }
            if !state.done.contains(playerId) { state.done.append(playerId) }
            if everyoneDone(state) { state.phase = .over }
        }
    }

    static func tick(_ state: inout State, now: Double, rng: inout OfflineRNG) {
        switch state.phase {
        case .countdown:
            if now >= state.startsAt { state.phase = .playing }
        case .playing:
            if now >= state.endsAt + grace {
                state.phase = .review
                state.reviewUntil = now + (state.players.count > 1 ? reviewSeconds : soloReviewSeconds)
            }
        case .review:
            if now >= state.reviewUntil { state.phase = .over }
        case .over:
            break
        }
    }

    static func playerLeft(_ playerId: String, state: inout State, now: Double, rng: inout OfflineRNG) {
        if !state.away.contains(playerId) { state.away.append(playerId) }
        if state.phase == .review, everyoneDone(state) { state.phase = .over }
    }

    static func view(of state: State, for playerId: String?) -> PlayerView {
        let reviewing = state.phase == .review || state.phase == .over
        let judged = reviewing ? judge(state, for: playerId) : nil
        let board = state.players
            .map { player -> Row in
                let answers = state.answers[player.id] ?? []
                let score = judged.map { cards in cards.reduce(0) { $0 + ($1.first { $0.owner == player.id }?.points ?? 0) } } ?? 0
                return Row(id: player.id, name: player.name, filled: answers.filter { !$0.isEmpty }.count, score: score,
                           away: state.away.contains(player.id), done: state.done.contains(player.id))
            }
            .enumerated()
            .sorted { $0.element.score == $1.element.score ? $0.offset < $1.offset : $0.element.score > $1.element.score }
            .map(\.element)
        let dealt = state.phase != .countdown
        return PlayerView(
            phase: state.phase, startsAt: state.startsAt, endsAt: state.endsAt, reviewUntil: state.reviewUntil,
            letter: dealt ? state.letter : nil,
            categories: dealt ? state.categories : [],
            mine: playerId.flatMap { state.answers[$0] },
            board: board, review: judged, together: state.players.count > 1
        )
    }

    static func isOver(_ state: State) -> Bool { state.phase == .over }

    static func standings(_ state: State) -> [OfflineStanding] {
        let judged = judge(state, for: nil)
        return OfflineStanding.ranked(state.players, score: { player in
            judged.reduce(0) { $0 + ($1.first { $0.owner == player.id }?.points ?? 0) }
        }, detail: { player in
            let filled = (state.answers[player.id] ?? []).filter { !$0.isEmpty }.count
            var parts = ["\(filled) of \(state.categories.count) answered"]
            if state.away.contains(player.id) { parts.append("left") }
            return parts.joined(separator: " · ")
        })
    }

    // MARK: - Judging

    /// Every answer, by category then seat, judged as things stand. Empty
    /// and wrong-letter come first (a veto cannot make them worse), then
    /// struck, then shared; what is left is a point.
    static func judge(_ state: State, for viewer: String?) -> [[Answer]] {
        let together = state.players.count > 1
        return state.categories.indices.map { index in
            // How many players wrote each answer here, with the right letter.
            var tally: [String: Int] = [:]
            for player in state.players {
                let text = slot(state.answers[player.id], index)
                if !text.isEmpty, startsWith(text, letter: state.letter) { tally[sameKey(text), default: 0] += 1 }
            }
            return state.players.map { player in
                let text = slot(state.answers[player.id], index)
                let bar = strikeAt(state, owner: player.id)
                let against = vetoes(state, owner: player.id, index: index)
                let status: Status
                if text.isEmpty {
                    status = .empty
                } else if !startsWith(text, letter: state.letter) {
                    status = .wrongLetter
                } else if bar > 0, against.count >= bar {
                    status = .struck
                } else if together, (tally[sameKey(text)] ?? 0) > 1 {
                    status = .shared
                } else {
                    status = .ok
                }
                return Answer(owner: player.id, index: index, text: text, status: status, vetoes: against.count,
                              strikeAt: bar, vetoedByMe: viewer.map { against.contains($0) } ?? false)
            }
        }
    }

    /// How many vetoes strike one of `owner`'s answers: half the other
    /// players still here, rounded up. Alone, 0 — nobody can.
    static func strikeAt(_ state: State, owner: String) -> Int {
        let others = state.players.filter { $0.id != owner && !state.away.contains($0.id) }.count
        return (others + 1) / 2
    }

    /// The vetoes on an answer that still count — from players still here.
    static func vetoes(_ state: State, owner: String, index: Int) -> [String] {
        (state.vetoes[vetoKey(owner, index)] ?? []).filter { !state.away.contains($0) }
    }

    static func vetoKey(_ owner: String, _ index: Int) -> String { "\(owner)|\(index)" }

    /// One player's answer for a category, "" when there is none.
    private static func slot(_ answers: [String]?, _ index: Int) -> String {
        guard let answers, answers.indices.contains(index) else { return "" }
        return answers[index]
    }

    private static func everyoneDone(_ state: State) -> Bool {
        state.players.allSatisfy { state.done.contains($0.id) || state.away.contains($0.id) }
    }

    // MARK: - Reading answers

    /// What is kept of an answer: control characters and runs of space made
    /// one space, trimmed, and cut to `maxAnswer` characters.
    static func clean(_ text: String) -> String {
        var out = ""
        var space = false
        for character in text {
            if character.isWhitespace || character.unicodeScalars.allSatisfy({ $0.properties.generalCategory == .control }) {
                space = !out.isEmpty
                continue
            }
            if space { out.append(" ") }
            space = false
            out.append(character)
            if out.count >= maxAnswer { break }
        }
        return out
    }

    /// An answer as the checks read it, the site's way: lower case, accents
    /// off, apostrophes gone, everything else not a–z or 0–9 a single space,
    /// and a leading "a", "an" or "the" dropped — "The Beatles" is a B. A
    /// bare article is left as it is.
    static func normalise(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
        var words: [String] = []
        var current = ""
        for scalar in folded.unicodeScalars {
            if scalar == "'" || scalar == "\u{2019}" { continue }
            if (97...122).contains(scalar.value) || (48...57).contains(scalar.value) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }
        if words.count > 1, ["a", "an", "the"].contains(words[0]) { words.removeFirst() }
        return words.joined(separator: " ")
    }

    static func startsWith(_ text: String, letter: String) -> Bool {
        guard let first = normalise(text).first, let wanted = letter.lowercased().first else { return false }
        return first == wanted
    }

    /// What two answers must share to be "the same answer": spaces don't count.
    static func sameKey(_ text: String) -> String {
        normalise(text).replacingOccurrences(of: " ", with: "")
    }

    // MARK: - The cards

    /// The site's categories (SR-Main src/lib/games/words/categories.ts):
    /// curated for a family table — every one something a child could answer —
    /// and distinct, so two near-twins never land on one card.
    static let card: [String] = [
        // Living things
        "An animal",
        "A bird",
        "A fish or sea creature",
        "An insect or bug",
        "A pet",
        "A farm animal",
        "A zoo animal",
        "A dog breed",
        "A dinosaur",
        "A flower",
        "A tree",
        "A plant",
        "Something with wings",
        "Something with four legs",
        "Something that lives in water",
        "Something with a shell",
        // Food and drink
        "A food",
        "A fruit",
        "A vegetable",
        "A drink",
        "A dessert",
        "A breakfast food",
        "A sandwich filling",
        "A pizza topping",
        "A snack",
        "A sweet or chocolate",
        "A flavour of ice cream",
        "Something you bake",
        "Something on a picnic",
        "Something in a lunchbox",
        "A cheese",
        "A kind of bread or cake",
        "A food from another country",
        "A soup",
        "Something sour",
        "Something spicy",
        "Something sweet",
        // People and names
        "A girl's name",
        "A boy's name",
        "A name for a pet",
        "A famous person",
        "A cartoon character",
        "A superhero",
        "A villain",
        "A character from a book",
        "A job",
        "Someone who wears a uniform",
        "A family member",
        "A king or queen",
        "A footballer",
        "A singer or band",
        "A fairy-tale character",
        // Places
        "A country",
        "A city",
        "A capital city",
        "A place in the UK",
        "A river",
        "A mountain or mountain range",
        "An island",
        "A place in a town",
        "A shop",
        "A holiday destination",
        "Somewhere you go on a school trip",
        "A room in a house",
        "Something at the beach",
        "Something at the park",
        "Something at a zoo",
        "Something at a funfair",
        "Something in a supermarket",
        "Something in space",
        "Something at a wedding",
        // Things around us
        "Something in a kitchen",
        "Something in a bathroom",
        "Something in a bedroom",
        "Something in a classroom",
        "Something in a garden",
        "Something in a toolbox",
        "Something in a pencil case",
        "Something in a school bag",
        "Something in your pocket",
        "Something in a fridge",
        "Something in a car",
        "Something on a farm",
        "Something in a hospital",
        "Something in a castle",
        "Something in the sky",
        "Something in the sea",
        "Something in a forest",
        "Furniture",
        "A kitchen gadget",
        "A tool",
        "A toy",
        "A board game or card game",
        "A video game",
        "A musical instrument",
        "A vehicle",
        "Something with wheels",
        "Something with buttons",
        "Something with a screen",
        "Something that needs batteries",
        "Something made of wood",
        "Something made of metal",
        "Something made of glass",
        "Something made of paper",
        "Something you plug in",
        // Describing things
        "Something cold",
        "Something hot",
        "Something round",
        "Something square",
        "Something soft",
        "Something hard",
        "Something sticky",
        "Something smelly",
        "Something loud",
        "Something quiet",
        "Something tiny",
        "Something huge",
        "Something heavy",
        "Something light",
        "Something fast",
        "Something slow",
        "Something red",
        "Something green",
        "Something blue",
        "Something yellow",
        "Something white",
        "Something shiny",
        "Something that bounces",
        "Something that grows",
        "Something that floats",
        "Something that melts",
        "Something that breaks",
        "Something you can fold",
        "Something that makes you laugh",
        "Something scary",
        "Something that comes in pairs",
        "Something with a tail",
        "Something with stripes",
        "Something with spots",
        // Doing things
        "A sport",
        "A game played outside",
        "A hobby",
        "A dance",
        "A way to travel",
        "Something you do at school",
        "Something you do at the weekend",
        "Something you do in the morning",
        "Something you do on holiday",
        "Something you can throw",
        "Something you can catch",
        "Something you can climb",
        "Something you wear",
        "Something you wear on your feet",
        "Something you wear on your head",
        "Something you wear in winter",
        "Something you take on holiday",
        "Something you collect",
        "Something you give as a present",
        "A reason to be late",
        "An excuse for not doing homework",
        "A word you say when you're happy",
        // Words and ideas
        "A colour",
        "A shape",
        "A number word",
        "A month or day of the week",
        "A school subject",
        "A language",
        "A word with double letters",
        "A word ending in -ing",
        "A thing you shout",
        "A kind of weather",
        "A season or holiday",
        "Something at a birthday party",
        "Something at Christmas",
        "Something at Halloween",
        "A film",
        "A TV show",
        "A song",
        "A book",
        "A website or app",
        "A brand",
        "A car maker",
        "Something in a library",
        "A body part",
        "An emotion",
        "Something in a museum",
        "A magic word or spell",
    ]
}
