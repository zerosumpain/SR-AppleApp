import Foundation

// The Games page's shelf, worked out without a view: which category each game
// sits in, which this phone plays most, what a filter or a search leaves, the
// lobby the banner across every page should offer, and the family's game
// ideas as the site sends them (John, 2026-10-27: "prioritising certain games
// by usage, organise by category and filter").
//
// Foundation only, and keyed by the wire's plain game id rather than
// `GameKind`, so the Linux harness can test it (`scripts/home-check.sh`) and
// a game this file has never heard of — a newer site's, or one added to
// `GameKind` after it — still lands somewhere sensible instead of nowhere.

/// A shelf on the Games page. The order of the cases is the page's order:
/// the quickest to start first, the ones that take an evening (or go
/// outdoors) further down.
enum GameCategory: String, CaseIterable, Identifiable, Codable {
    case quick
    case word
    case party
    case physics
    case strategy
    case outdoor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .word: return "Words & quiz"
        case .party: return "Drawing & party"
        case .strategy: return "Strategy & board"
        case .quick: return "Quick & arcade"
        case .physics: return "Physics"
        case .outdoor: return "Outdoor"
        }
    }

    /// The filter chip's word: a chip is narrow.
    var chip: String {
        switch self {
        case .word: return "Words"
        case .party: return "Party"
        case .strategy: return "Strategy"
        case .quick: return "Quick"
        case .physics: return "Physics"
        case .outdoor: return "Outdoor"
        }
    }

    var icon: String {
        switch self {
        case .word: return "character.book.closed.fill"
        case .party: return "theatermasks.fill"
        case .strategy: return "crown.fill"
        case .quick: return "bolt.fill"
        case .physics: return "scope"
        case .outdoor: return "tree.fill"
        }
    }

    /// One line under the shelf's name.
    var line: String {
        switch self {
        case .word: return "Letters, words and questions."
        case .party: return "Draw, bluff and guess, best with the whole family."
        case .strategy: return "Think ahead. Some last an evening, some for weeks."
        case .quick: return "A minute or two. Fast hands, quick heads."
        case .physics: return "Tilt, roll and race: things that move."
        case .outdoor: return "Off the sofa and out of the door."
        }
    }

    /// The category a game id belongs to. Known ids are listed; an unknown id
    /// that sounds like something that moves (a lander, a kart, a tilt game) is
    /// Physics, and anything else is Quick — the shelf a new game is most
    /// likely to fit, and never a game left off the page.
    static func of(_ game: String) -> GameCategory {
        if let known = known[game] { return known }
        let id = game.lowercased()
        let moving = ["lander", "tilt", "kart", "car", "rally", "race", "drive", "physics", "marble", "ball", "golf", "rocket", "gravity"]
        if moving.contains(where: { id.contains($0) }) { return .physics }
        return .quick
    }

    private static let known: [String: GameCategory] = [
        "wordle-race": .word,
        "anagram-blitz": .word,
        "boggle": .word,
        "categories": .word,
        "quiz-night": .word,
        "one-clue": .word,
        "draw-guess": .party,
        "fake-artist": .party,
        "mission": .party,
        "liars-dice": .party,
        "chess": .strategy,
        "homestead": .strategy,
        "hometowns": .strategy,
        "fireworks": .strategy,
        "pass-the-plate": .strategy,
        "tap-duel": .quick,
        "maths-sprint": .quick,
        "sequence-memory": .quick,
        "marble-race": .physics,
        "manhunt": .outdoor,
    ]
}

/// How often this phone starts or joins each game — `HubUsage`'s fading
/// count, kept under its own key so the hub's order and the shelf's never
/// mix. Counted when a game is started or an invite joined, never on a look.
enum GameUsage {
    static let key = "games-usage"

    static func load(_ defaults: UserDefaults = .standard) -> HubUsage {
        guard let data = defaults.data(forKey: key), let usage = try? JSONDecoder().decode(HubUsage.self, from: data) else {
            return HubUsage()
        }
        return usage
    }

    static func save(_ usage: HubUsage, _ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(usage) { defaults.set(data, forKey: key) }
    }
}

/// What the shelf shows for a filter and a search.
enum GamesShelf {
    /// One shelf: a category, the favourites, or a search's results.
    struct Section: Equatable, Identifiable {
        let id: String
        let title: String
        var line: String? = nil
        let games: [String]
    }

    /// The favourites row's filter id; a category's is its raw value.
    static let favouritesFilter = "top"
    /// How many favourites lead the page.
    static let favouritesCount = 4

    /// The games this phone plays most, most first: only ones played at all.
    static func favourites(_ games: [String], usage: HubUsage, now: Date, limit: Int = favouritesCount) -> [String] {
        Array(usage.ordered(games, now: now).filter { usage.score($0, now: now) > 0 }.prefix(limit))
    }

    /// The shelves for `filter` (nil = everything) and `query`.
    ///
    /// A search looks through every game whatever the filter, as one list —
    /// someone typing a name wants that game, not to remember its shelf.
    /// Otherwise each category is a shelf, its games most played first (ties
    /// in the catalogue's order); the favourites filter is the played games
    /// alone. `text` is what a search reads for each game (its name and lines).
    static func sections(
        games: [String],
        text: [String: String],
        usage: HubUsage,
        now: Date,
        filter: String?,
        query: String
    ) -> [Section] {
        let ordered = usage.ordered(games, now: now)
        let words = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if !words.isEmpty {
            let hits = ordered.filter { id in
                let hay = (text[id] ?? id).lowercased() + " " + GameCategory.of(id).title.lowercased()
                return words.allSatisfy { hay.contains($0) }
            }
            return hits.isEmpty ? [] : [Section(id: "search", title: "Matches", games: hits)]
        }
        if filter == favouritesFilter {
            let top = favourites(games, usage: usage, now: now, limit: games.count)
            return top.isEmpty ? [] : [Section(id: favouritesFilter, title: "Most played", games: top)]
        }
        let wanted = filter.flatMap(GameCategory.init(rawValue:))
        return GameCategory.allCases.compactMap { category in
            if let wanted, wanted != category { return nil }
            let shelf = ordered.filter { GameCategory.of($0) == category }
            return shelf.isEmpty ? nil : Section(id: category.rawValue, title: category.title, line: category.line, games: shelf)
        }
    }

    /// The categories with at least one game, for the filter chips.
    static func categories(_ games: [String]) -> [GameCategory] {
        let present = Set(games.map(GameCategory.of))
        return GameCategory.allCases.filter(present.contains)
    }
}

// MARK: - The lobby banner

/// A lobby the banner across every page could offer: an invite waiting for
/// an answer, or a lobby I am sitting in that has not started.
struct LobbyBannerCandidate: Equatable, Identifiable {
    enum Kind: Equatable {
        case invite
        case waiting
    }

    let roomId: String
    let game: String
    let gameTitle: String
    let hostName: String
    let kind: Kind
    /// The lobby's own clock, server epoch ms; nil when it has none.
    var expiresAt: Double? = nil
    /// I host it (a waiting lobby only).
    var mine: Bool = false

    var id: String { roomId }

    /// What the banner says.
    var line: String {
        switch kind {
        case .invite: return "\(hostName) invited you to \(gameTitle)"
        case .waiting: return mine ? "Your \(gameTitle) lobby is open" : "\(hostName)’s \(gameTitle) is waiting to start"
        }
    }

    /// The banner's button.
    var action: String { kind == .invite ? "Join" : "Open" }
}

enum LobbyBannerPick {
    /// The one lobby to offer: an invite before a lobby I am already in (the
    /// invite is the one that needs an answer), the soonest to close first,
    /// never one dismissed or one whose clock has run out.
    static func pick(_ candidates: [LobbyBannerCandidate], dismissed: Set<String>, serverNow: Double?) -> LobbyBannerCandidate? {
        let live = candidates.filter { c in
            guard !dismissed.contains(c.roomId) else { return false }
            if let end = c.expiresAt, let now = serverNow, end <= now { return false }
            return true
        }
        return live.enumerated().min { a, b in
            let ra = a.element.kind == .invite ? 0 : 1
            let rb = b.element.kind == .invite ? 0 : 1
            if ra != rb { return ra < rb }
            let ea = a.element.expiresAt ?? .infinity
            let eb = b.element.expiresAt ?? .infinity
            if ea != eb { return ea < eb }
            return a.offset < b.offset
        }?.element
    }

    /// What a player is told when a parent closed the lobby they were in.
    static func closedLine(by name: String?, game: String) -> String {
        guard let name, !name.isEmpty else { return "The \(game) lobby was closed." }
        return "\(name) closed the \(game) lobby."
    }
}

// MARK: - Wire shapes the shelf owns

/// A lobby not yet started, anybody's — what a parent may close
/// (`lobby.openLobbies`, sent to a parent only).
struct GameOpenLobby: Decodable, Equatable, Identifiable {
    let id: String
    let game: String
    let hostName: String
    let players: [String]
    let invited: [String]
    let expiresAt: Double?
    let mine: Bool

    private enum CodingKeys: String, CodingKey { case id, game, hostName, players, invited, expiresAt, mine }

    init(id: String, game: String, hostName: String, players: [String] = [], invited: [String] = [],
         expiresAt: Double? = nil, mine: Bool = false) {
        self.id = id; self.game = game; self.hostName = hostName; self.players = players
        self.invited = invited; self.expiresAt = expiresAt; self.mine = mine
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        game = (try? c.decodeIfPresent(String.self, forKey: .game)) ?? "tap-duel"
        hostName = (try? c.decodeIfPresent(String.self, forKey: .hostName)) ?? "Someone"
        players = (try? c.decodeIfPresent([String].self, forKey: .players)) ?? []
        invited = (try? c.decodeIfPresent([String].self, forKey: .invited)) ?? []
        expiresAt = (try? c.decodeIfPresent(Double.self, forKey: .expiresAt)) ?? nil
        mine = (try? c.decodeIfPresent(Bool.self, forKey: .mine)) ?? false
    }
}

/// One game the family would like to see one day (`/api/native/games/suggestions`).
struct GameSuggestion: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let note: String
    let by: String
    /// Epoch ms.
    let at: Double
    let votes: Int
    let voted: Bool
    let mine: Bool

    private enum CodingKeys: String, CodingKey { case id, name, note, by, at, votes, voted, mine }

    init(id: String, name: String, note: String = "", by: String, at: Double = 0, votes: Int = 1,
         voted: Bool = false, mine: Bool = false) {
        self.id = id; self.name = name; self.note = note; self.by = by; self.at = at
        self.votes = votes; self.voted = voted; self.mine = mine
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        by = (try? c.decodeIfPresent(String.self, forKey: .by)) ?? "Someone"
        at = (try? c.decodeIfPresent(Double.self, forKey: .at)) ?? 0
        votes = max(0, (try? c.decodeIfPresent(Int.self, forKey: .votes)) ?? 0)
        voted = (try? c.decodeIfPresent(Bool.self, forKey: .voted)) ?? false
        mine = (try? c.decodeIfPresent(Bool.self, forKey: .mine)) ?? false
    }

    /// "Sam · 3 want it".
    var byline: String {
        votes <= 1 ? "Suggested by \(by)" : "Suggested by \(by) · \(votes) want it"
    }
}

/// The answer to every suggestions call: the list after it.
struct GameSuggestionList: Decodable, Equatable {
    let suggestions: [GameSuggestion]
    let parent: Bool

    private enum CodingKeys: String, CodingKey { case suggestions, parent }

    init(suggestions: [GameSuggestion], parent: Bool = false) {
        self.suggestions = suggestions
        self.parent = parent
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        suggestions = (try? c.decodeIfPresent([GameSuggestion].self, forKey: .suggestions)) ?? []
        parent = (try? c.decodeIfPresent(Bool.self, forKey: .parent)) ?? false
    }
}

/// A new idea as the form holds it, checked the way the site checks it so
/// the button is only live when the site would take it.
struct GameSuggestionDraft: Equatable {
    var name = ""
    var note = ""

    static let maxName = 60
    static let maxNote = 280

    var cleanName: String { Self.tidy(name, max: Self.maxName) }
    var cleanNote: String { Self.tidy(note, max: Self.maxNote) }
    var isReady: Bool { cleanName.count >= 2 }

    static func tidy(_ value: String, max: Int) -> String {
        let folded = value.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        return String(folded.prefix(max)).trimmingCharacters(in: .whitespaces)
    }
}
