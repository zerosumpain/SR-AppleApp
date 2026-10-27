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
    // `briefing` comes after `daydream` so that `allCases`, which the Colours
    // sheet reads for a hue's symbol, finds Daydream's own tile first; the
    // tiles added since (2026-10-27) come after every tile whose hue they
    // borrow, for the same reason.
    case family, health, steps, tasks, trips, moves, messages, backlog, games, chat, news, daydream, flows, wildmind, briefing
    case batPhone, diary, travel, captures

    var id: String { rawValue }

    /// Kept for what read one size per tile: the size a new install gets.
    var size: HomeSize { defaultSize }

    /// What a new install gets. Squares are 2×2, shortcuts 2×1, wide tiles
    /// 4×2 and the Orbit 4×4 (see `HomeSize`).
    var defaultSize: HomeSize {
        switch self {
        case .family: return .hero
        // Games and Flows are wide so that, being adaptive, they open out
        // when something waits and fold to a square when nothing does.
        case .briefing, .health, .steps, .trips, .news, .moves, .messages, .diary, .games, .flows: return .wide
        case .chat, .wildmind, .batPhone, .travel, .captures: return .compact
        default: return .square
        }
    }

    /// Every size the tile can be drawn at, smallest first: what the size
    /// button in Arrange goes round. The Orbit needs its room; the briefing
    /// is a list of lines and is wide, or large for twice as many.
    var sizes: [HomeSize] {
        switch self {
        case .family: return [.hero]
        case .briefing: return [.wide, .hero]
        case .health, .steps, .trips, .moves, .messages, .news, .diary, .tasks, .backlog, .games, .daydream, .flows:
            return [.square, .wide]
        case .chat: return [.compact, .square, .wide]
        case .wildmind, .batPhone, .travel, .captures: return [.compact, .square]
        }
    }

    /// Folds to a square when it has nothing to show, and opens out when it
    /// has (John, 2026-10-27: a calendar with no events is 2×2, with one 4×2).
    var adaptive: Bool {
        switch self {
        case .diary, .trips, .moves, .games, .flows: return true
        default: return false
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
        case .batPhone: return "Bat phone"
        case .diary: return "Today's diary"
        case .travel: return "Travel kit"
        case .captures: return "Captures"
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
        case .messages: return "The newest family message and one-tap lines"
        case .backlog: return "Things saved to watch and read"
        case .games: return "Invites and games in play"
        case .chat: return "A new question for jkai"
        case .news: return "The top stories and how fast each is moving"
        case .daydream: return "What the loop noticed"
        case .flows: return "Workflows running and failing"
        case .wildmind: return "The world it is building"
        case .briefing: return "The things that matter most right now, from everything below"
        case .batPhone: return "Two taps tell the family you need them, in msg family"
        case .diary: return "What is left of today, and when to leave for it"
        case .travel: return "Translate, read a sign, phrases, money and the way back"
        case .captures: return "Record a thought, and what is waiting to be decided"
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
        case .batPhone: return "light.beacon.max.fill"
        case .diary: return "calendar"
        case .travel: return "airplane"
        case .captures: return "waveform.badge.mic"
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
        case .batPhone: return .messages
        case .diary, .travel: return .trips
        case .captures: return .chat
        }
    }

    var hue: SR.Hue { SRPaint.current.hue(hueKey) }

    /// On Home whatever the reader's layout says: the bat phone must be on
    /// every family phone (John, 2026-10-27). It has a tile of its own now,
    /// so msg family can be taken off like any other.
    var alwaysShown: Bool { self == .batPhone }

    /// The order a new install gets. The briefing first — what matters,
    /// from everything — then the family, because where everyone is is the
    /// thing the app is opened for, the bat phone and a line to them
    /// straight under it, and the day's diary. The squares in pairs; the
    /// shortcuts last.
    static let defaultOrder: [HomeTileKind] = [
        .briefing, .family, .batPhone, .messages, .diary, .health, .steps, .trips, .moves, .news,
        .tasks, .backlog, .daydream, .flows, .games, .captures, .travel, .chat, .wildmind,
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
            // The bat phone messages the family, so it is wherever msg family is.
            case .batPhone: return boards
            // The diary is the owner's calendar, read through the family's
            // travel desk: null on anyone else's phone.
            case .diary: return boards && access.owner
            // Runs on the phone: everyone's, as it is in More.
            case .travel: return true
            case .captures: return ownerSite
            }
        }
    }
}

/// The reader's choice: an order, a set left off, and a size for any tile
/// that has more than one. Stored as JSON in one `@AppStorage` string, so
/// every view that draws Home reads one value.
///
/// Tiles this person may not have are kept in the stored order (access can
/// come back), but never drawn and never listed. A tile the app gains later
/// — a new feature, or a grant — lands where the default order puts it and
/// SHOWN: a feature is on Home until the reader takes it off.
struct HomeLayout: Codable, Equatable {
    var order: [HomeTileKind] = []
    var hidden: Set<HomeTileKind> = []
    /// The reader's size for a tile; a tile not named here is its default.
    var sizes: [HomeTileKind: HomeSize] = [:]

    static let key = "home-layout"

    init(order: [HomeTileKind] = [], hidden: Set<HomeTileKind> = [], sizes: [HomeTileKind: HomeSize] = [:]) {
        self.order = order
        self.hidden = hidden
        self.sizes = sizes
    }

    /// Lenient: an unknown tile or size in the stored JSON (a build that had
    /// one this build does not) is dropped, never a thrown decode that loses
    /// the rest.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawOrder = (try? c.decodeIfPresent([String].self, forKey: .order)) ?? nil
        let rawHidden = (try? c.decodeIfPresent([String].self, forKey: .hidden)) ?? nil
        let rawSizes = (try? c.decodeIfPresent([String: String].self, forKey: .sizes)) ?? nil
        order = (rawOrder ?? []).compactMap(HomeTileKind.init(rawValue:))
        hidden = Set((rawHidden ?? []).compactMap(HomeTileKind.init(rawValue:)))
        var known: [HomeTileKind: HomeSize] = [:]
        for (tile, size) in rawSizes ?? [:] {
            if let kind = HomeTileKind(rawValue: tile), let value = HomeSize(rawValue: size) { known[kind] = value }
        }
        sizes = known
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(order.map(\.rawValue), forKey: .order)
        try c.encode(hidden.map(\.rawValue).sorted(), forKey: .hidden)
        if !sizes.isEmpty {
            try c.encode(Dictionary(uniqueKeysWithValues: sizes.map { ($0.key.rawValue, $0.value.rawValue) }), forKey: .sizes)
        }
    }

    private enum CodingKeys: String, CodingKey { case order, hidden, sizes }

    static func decode(_ raw: String) -> HomeLayout {
        guard let data = raw.data(using: .utf8), let layout = try? JSONDecoder().decode(HomeLayout.self, from: data) else {
            return HomeLayout()
        }
        return layout
    }

    var raw: String {
        let encoder = JSONEncoder()
        // Sorted, so an unchanged layout is the same string and a write of it
        // redraws nothing.
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
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

    /// What Arrange offers to add: this person's tiles that are off. PURE.
    func addable(_ available: [HomeTileKind]) -> [HomeTileKind] {
        arranged(available).filter { !shows($0) }
    }

    func shows(_ kind: HomeTileKind) -> Bool { kind.alwaysShown || !hidden.contains(kind) }

    mutating func set(_ kind: HomeTileKind, shown: Bool) {
        if shown || kind.alwaysShown { hidden.remove(kind) } else { hidden.insert(kind) }
    }

    /// The reader's size for `kind`, kept to the sizes it has. PURE.
    func size(of kind: HomeTileKind) -> HomeSize {
        guard let chosen = sizes[kind], kind.sizes.contains(chosen) else { return kind.defaultSize }
        return chosen
    }

    /// Choosing the default forgets the choice, so a later change to the
    /// default reaches this reader too.
    mutating func set(_ kind: HomeTileKind, size: HomeSize) {
        guard kind.sizes.contains(size) else { return }
        sizes[kind] = size == kind.defaultSize ? nil : size
    }

    /// A drag in Settings → Home, over the arranged list.
    mutating func move(_ available: [HomeTileKind], from source: IndexSet, to destination: Int) {
        var list = arranged(available)
        list.move(fromOffsets: source, toOffset: destination)
        // Keep the tiles this person cannot see where they were, after the rest.
        order = list + order.filter { !list.contains($0) }
    }

    /// A tile dropped on another in Arrange: it takes that tile's place,
    /// and that tile and everything after it move down one. PURE.
    mutating func move(_ kind: HomeTileKind, before target: HomeTileKind, available: [HomeTileKind]) {
        guard kind != target else { return }
        var list = arranged(available)
        guard let from = list.firstIndex(of: kind), list.contains(target) else { return }
        list.remove(at: from)
        let to = list.firstIndex(of: target) ?? list.count
        // Dragged down the page, it lands after the tile it was dropped on.
        list.insert(kind, at: from <= to ? min(to + 1, list.count) : to)
        order = list + order.filter { !list.contains($0) }
    }

    /// Move up or down one place among the tiles that are SHOWN — what
    /// VoiceOver's "Move up" and "Move down" do in Arrange. PURE.
    mutating func nudge(_ kind: HomeTileKind, by step: Int, available: [HomeTileKind]) {
        let shown = visible(available)
        guard let at = shown.firstIndex(of: kind) else { return }
        let target = at + step
        guard shown.indices.contains(target) else { return }
        var list = arranged(available)
        guard let from = list.firstIndex(of: kind), let to = list.firstIndex(of: shown[target]) else { return }
        list.remove(at: from)
        list.insert(kind, at: to)
        order = list + order.filter { !list.contains($0) }
    }

    mutating func reset() { self = HomeLayout() }
}

/// How tiles sit on the page: see `HomeSizing.pack` — wide tiles and the Orbit
/// take a row, squares go two to a row (or beside two stacked shortcuts), and
/// a square left alone stays a square. At the accessibility text sizes
/// everything is one column. PURE.
enum HomeRows {
    typealias Row = HomePackedRow<HomeTileKind>

    static func pack(_ kinds: [HomeTileKind], sizes: [HomeTileKind: HomeSize] = [:], folded: Bool = false) -> [Row] {
        HomeSizing.pack(kinds.map { (id: $0, size: sizes[$0] ?? $0.defaultSize) }, folded: folded)
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
