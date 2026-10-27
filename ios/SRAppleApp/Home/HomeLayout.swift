import SwiftUI

/// Home: one tile per feature, in an order the reader chooses.
///
/// Today used to be a sky and a handful of cards. Home (Prism, 2026-10-18)
/// is the whole app at a glance — every feature this person may use, each as a
/// tile with its own live picture — and Settings → Home says which of them are
/// on it and in what order. A feature the person cannot use never appears,
/// here or in Settings: access decides what EXISTS, the reader decides what is
/// SHOWN.
///
/// Pulse (2026-10-27): John found Prism "more like an index" than a page
/// with anything on it. So the page now leads with the briefing — the three
/// things worth knowing, ranked across every feature (`HomeBriefing`) — and
/// the tiles that carry data are wide charts with their numbers written on
/// them. The two that only take you somewhere, Ask jkai and Wildmind, shrank
/// to shortcuts at the foot.
///
/// Everything in this file is pure, so each rule is a unit test.
enum HomeTileKind: String, CaseIterable, Identifiable, Codable {
    // `briefing` is last so that `allCases`, which the Colours sheet reads
    // for a hue's symbol, finds Daydream's own tile before it.
    case family, health, steps, tasks, trips, moves, messages, backlog, games, chat, news, daydream, flows, wildmind, briefing

    var id: String { rawValue }

    /// `compact`: a shortcut, two to a short row — a feature with nothing to
    /// chart, kept on Home without taking a tile's room.
    enum Size { case hero, wide, square, compact }

    var size: Size {
        switch self {
        case .family: return .hero
        case .briefing, .health, .steps, .trips, .news, .moves, .messages: return .wide
        case .chat, .wildmind: return .compact
        default: return .square
        }
    }

    var title: String {
        switch self {
        case .family: return "Family"
        case .health: return "Health"
        case .steps: return "Steps"
        case .tasks: return "Tasks"
        case .trips: return "Trips"
        case .moves: return "Coming up"
        case .messages: return "msg family"
        case .backlog: return "Backlog"
        case .games: return "Games"
        case .chat: return "Ask jkai"
        case .news: return "News"
        case .daydream: return "Daydream"
        case .flows: return "Flows"
        case .wildmind: return "Wildmind"
        case .briefing: return "Worth knowing"
        }
    }

    /// What the tile shows, for Settings → Home.
    var blurb: String {
        switch self {
        case .family: return "Everyone around home: how far, which way, who is moving"
        case .health: return "Readiness, your figures against your week, and today's rings"
        case .steps: return "The family step race, everyone's count"
        case .tasks: return "What is left on the task list"
        case .trips: return "Today's stops, or the next trip"
        case .moves: return "Who is due to leave, and when"
        case .messages: return "The newest family message, one-tap lines and the bat phone"
        case .backlog: return "Things saved to watch and read"
        case .games: return "Invites and games in play"
        case .chat: return "A new question for jkai"
        case .news: return "The top stories and how fast each is moving"
        case .daydream: return "What the loop noticed"
        case .flows: return "Workflows running and failing"
        case .wildmind: return "The world it is building"
        case .briefing: return "The three things that matter most right now, from everything below"
        }
    }

    var symbol: String {
        switch self {
        case .family: return "person.2.wave.2.fill"
        case .health: return "heart.fill"
        case .steps: return "figure.walk"
        case .tasks: return "checklist"
        case .trips: return "suitcase.rolling.fill"
        case .moves: return "clock.arrow.2.circlepath"
        case .messages: return "bubble.left.and.text.bubble.right.fill"
        case .backlog: return "tray.full.fill"
        case .games: return "gamecontroller.fill"
        case .chat: return "sparkles"
        case .news: return "newspaper.fill"
        case .daydream: return "cloud.fill"
        case .flows: return "point.3.connected.trianglepath.dotted"
        case .wildmind: return "leaf.fill"
        case .briefing: return "sparkle"
        }
    }

    /// Which of the palette's hues the tile wears. Several tiles share one:
    /// the family's three are all the family's colour.
    var hueKey: SR.HueKey {
        switch self {
        case .family, .moves: return .family
        case .health: return .health
        case .steps: return .steps
        case .tasks: return .tasks
        case .trips: return .trips
        case .messages: return .messages
        case .backlog: return .backlog
        case .games: return .games
        case .chat: return .chat
        case .news: return .news
        case .daydream: return .daydream
        case .flows: return .flows
        case .wildmind: return .wildmind
        // The briefing's lines each wear their own source's hue; its own
        // mark is the loop's colour, the app's colour for "noticed".
        case .briefing: return .daydream
        }
    }

    var hue: SR.Hue { SRPaint.current.hue(hueKey) }

    /// On Home whatever the reader's layout says: msg family holds the bat
    /// phone, which must be on every family phone (John, 2026-10-27).
    var alwaysShown: Bool { self == .messages }

    /// The order a new install gets. The briefing first — what matters,
    /// from everything — then the family, because where everyone is is the
    /// thing the app is opened for, and a line to them (with the bat phone)
    /// straight under it. The squares in pairs; the shortcuts last.
    static let defaultOrder: [HomeTileKind] = [
        .briefing, .family, .messages, .health, .steps, .trips, .moves, .news,
        .tasks, .backlog, .daydream, .flows, .games, .chat, .wildmind,
    ]

    /// Every tile this person may have, in the default order. PURE.
    ///
    /// The same gates every tab and card already obeys: the family's boards
    /// need family AND the site credential (they live on the site); the
    /// owner's loop, desk and workflows need the owner's site lane.
    static func available(access: AppAccess, sitePaired: Bool) -> [HomeTileKind] {
        let boards = AccessPolicy.familyBoards(access, sitePaired: sitePaired)
        let ownerSite = access.owner && sitePaired
        return defaultOrder.filter { kind in
            switch kind {
            case .briefing: return true
            case .family: return AccessPolicy.allows(.family, access)
            case .health: return true
            case .steps, .tasks, .moves, .messages, .backlog: return boards
            case .trips: return sitePaired && (access.owner || access.family)
            case .games: return AccessPolicy.allows(.games, access)
            case .chat: return access.chat && sitePaired
            case .news, .daydream, .flows, .wildmind: return ownerSite
            }
        }
    }
}

/// The reader's choice: an order and a set left off. Stored as JSON in one
/// `@AppStorage` string, so every view that draws Home reads one value.
///
/// Tiles this person may not have are kept in the stored order (access can
/// come back), but never drawn and never listed. A tile the app gains later
/// — a new feature, or a grant — lands where the default order puts it and
/// SHOWN: a feature is on Home until the reader takes it off.
struct HomeLayout: Codable, Equatable {
    var order: [HomeTileKind] = []
    var hidden: Set<HomeTileKind> = []

    static let key = "home-layout"

    init(order: [HomeTileKind] = [], hidden: Set<HomeTileKind> = []) {
        self.order = order
        self.hidden = hidden
    }

    /// Lenient: an unknown tile in the stored JSON (a build that had one this
    /// build does not) is dropped, never a thrown decode that loses the rest.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawOrder = (try? c.decodeIfPresent([String].self, forKey: .order)) ?? nil
        let rawHidden = (try? c.decodeIfPresent([String].self, forKey: .hidden)) ?? nil
        order = (rawOrder ?? []).compactMap(HomeTileKind.init(rawValue:))
        hidden = Set((rawHidden ?? []).compactMap(HomeTileKind.init(rawValue:)))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(order.map(\.rawValue), forKey: .order)
        try c.encode(hidden.map(\.rawValue).sorted(), forKey: .hidden)
    }

    private enum CodingKeys: String, CodingKey { case order, hidden }

    static func decode(_ raw: String) -> HomeLayout {
        guard let data = raw.data(using: .utf8), let layout = try? JSONDecoder().decode(HomeLayout.self, from: data) else {
            return HomeLayout()
        }
        return layout
    }

    var raw: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// Every tile this person may have, in the reader's order — shown or not.
    /// What Settings → Home lists. PURE.
    func arranged(_ available: [HomeTileKind]) -> [HomeTileKind] {
        let known = order.filter(available.contains)
        var out = known
        // Newcomers slot in after the tile that precedes them by default, so
        // a new feature lands near its family rather than at the bottom.
        for kind in available where !out.contains(kind) {
            let defaults = HomeTileKind.defaultOrder
            let before = defaults.prefix(while: { $0 != kind }).last(where: out.contains)
            if let before, let at = out.firstIndex(of: before) {
                out.insert(kind, at: at + 1)
            } else {
                out.insert(kind, at: 0)
            }
        }
        return out
    }

    /// What Home draws. PURE.
    func visible(_ available: [HomeTileKind]) -> [HomeTileKind] {
        arranged(available).filter(shows)
    }

    func shows(_ kind: HomeTileKind) -> Bool { kind.alwaysShown || !hidden.contains(kind) }

    mutating func set(_ kind: HomeTileKind, shown: Bool) {
        if shown || kind.alwaysShown { hidden.remove(kind) } else { hidden.insert(kind) }
    }

    /// A drag in Settings → Home, over the arranged list.
    mutating func move(_ available: [HomeTileKind], from source: IndexSet, to destination: Int) {
        var list = arranged(available)
        list.move(fromOffsets: source, toOffset: destination)
        // Keep the tiles this person cannot see where they were, after the rest.
        order = list + order.filter { !list.contains($0) }
    }

    mutating func reset() { self = HomeLayout() }
}

/// How tiles sit on the page: heroes and wide tiles take a row, squares go two
/// to a row, and so do shortcuts — a square beside a square, a shortcut beside
/// a shortcut, never one of each (they are different heights). One left alone
/// — the last, or one before something it cannot pair with — takes the whole
/// row rather than leaving a hole beside it. At the accessibility text sizes
/// everything is one column. PURE.
enum HomeRows {
    enum Row: Equatable, Identifiable {
        case full(HomeTileKind)
        case pair(HomeTileKind, HomeTileKind)

        var id: String {
            switch self {
            case .full(let a): return a.rawValue
            case .pair(let a, let b): return a.rawValue + "+" + b.rawValue
            }
        }
    }

    static func pack(_ kinds: [HomeTileKind], folded: Bool = false) -> [Row] {
        if folded { return kinds.map(Row.full) }
        var rows: [Row] = []
        var waiting: HomeTileKind?
        for kind in kinds {
            if kind.size == .square || kind.size == .compact {
                if let first = waiting, first.size == kind.size {
                    rows.append(.pair(first, kind))
                    waiting = nil
                } else {
                    if let first = waiting { rows.append(.full(first)) }
                    waiting = kind
                }
            } else {
                if let first = waiting { rows.append(.full(first)); waiting = nil }
                rows.append(.full(kind))
            }
        }
        if let last = waiting { rows.append(.full(last)) }
        return rows
    }
}

/// The page switches ("Show on Home") on Steps, Tasks and Backlog, over the
/// same stored layout as Settings → Home.
struct HomeShowsBinding {
    static func binding(_ kind: HomeTileKind, raw: Binding<String>) -> Binding<Bool> {
        Binding(
            get: { HomeLayout.decode(raw.wrappedValue).shows(kind) },
            set: { shown in
                var layout = HomeLayout.decode(raw.wrappedValue)
                layout.set(kind, shown: shown)
                raw.wrappedValue = layout.raw
            }
        )
    }
}
