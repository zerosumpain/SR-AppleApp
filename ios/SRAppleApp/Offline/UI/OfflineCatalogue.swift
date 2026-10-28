import SwiftUI

/// Every offline game: one line each, pairing a game's rules with its view.
///
///     OfflineCatalogueItem(QuickDrawRules.self) { QuickDrawView(context: $0) },
///     OfflineCatalogueItem(withBot: FourInARowRules.self) { FourInARowView(context: $0) },
///
/// `withBot:` for a game whose rules have a computer player (`OfflineBotRules`):
/// it can then be played alone, and the host can fill empty seats.
///
/// The rules type gives the card (`info`) and the host's engine
/// (`OfflineGameEntry`); the closure builds the view from an
/// `OfflineGameContext<Rules>` — the decoded `PlayerView`, who I am, the
/// players, the host's clock and `send`. Order within a category is the order
/// here.
enum OfflineCatalogue {
    static let items: [OfflineCatalogueItem] = [
        // Card games.
        OfflineCatalogueItem(withBot: CrazyEightsRules.self) { CrazyEightsView(context: $0) },
        OfflineCatalogueItem(GoFishRules.self) { GoFishView(context: $0) },
        OfflineCatalogueItem(BlackjackRules.self) { BlackjackView(context: $0) },
        OfflineCatalogueItem(CheatRules.self) { CheatView(context: $0) },
        OfflineCatalogueItem(OldMaidRules.self) { OldMaidView(context: $0) },
        OfflineCatalogueItem(KnockoutWhistRules.self) { KnockoutWhistView(context: $0) },
        OfflineCatalogueItem(HigherLowerRules.self) { HigherLowerView(context: $0) },
        OfflineCatalogueItem(withBot: OfflineFireworksRules.self) { OfflineFireworksView(context: $0) },
        // Reaction games.
        OfflineCatalogueItem(QuickDrawRules.self) { QuickDrawView(context: $0) },
        OfflineCatalogueItem(SnapRules.self) { SnapView(context: $0) },
        OfflineCatalogueItem(ColourClashRules.self) { ColourClashView(context: $0) },
        OfflineCatalogueItem(WhackAMoleRules.self) { WhackAMoleView(context: $0) },
        OfflineCatalogueItem(HotPotatoRules.self) { HotPotatoView(context: $0) },
        OfflineCatalogueItem(SwipeSaysRules.self) { SwipeSaysView(context: $0) },
        OfflineCatalogueItem(ReflexGridRules.self) { ReflexGridView(context: $0) },
        // Skill games.
        OfflineCatalogueItem(OfflineSprintRules.self) { OfflineSprintView(context: $0) },
        OfflineCatalogueItem(withBot: DotsAndBoxesRules.self) { DotsAndBoxesView(context: $0) },
        OfflineCatalogueItem(MemoryPairsRules.self) { MemoryPairsView(context: $0) },
        OfflineCatalogueItem(withBot: FourInARowRules.self) { FourInARowView(context: $0) },
        OfflineCatalogueItem(CodeBreakerRules.self) { CodeBreakerView(context: $0) },
        OfflineCatalogueItem(SteadyHandRules.self) { SteadyHandView(context: $0) },
        OfflineCatalogueItem(SeaBattleRules.self) { SeaBattleView(context: $0) },
        OfflineCatalogueItem(CarRaceNearbyRules.self) { CarRaceNearbyView(context: $0) },
        OfflineCatalogueItem(withBot: OfflineChessRules.self) { OfflineChessView(context: $0) },
        OfflineCatalogueItem(withBot: OfflineLiarsDiceRules.self) { OfflineLiarsDiceView(context: $0) },
    ]

    /// What the host's room can start.
    static var entries: [OfflineGameEntry] { items.map(\.entry) }

    static func item(_ id: String) -> OfflineCatalogueItem? {
        items.first { $0.id == id }
    }

    static func games(in category: OfflineGameCategory) -> [OfflineCatalogueItem] {
        items.filter { $0.info.category == category }
    }

    // MARK: - For the Games page

    /// Whether a game — by its offline id, or the id of an online game with
    /// an offline twin (`OfflinePlayModes.offlineTwin`) — can be played on
    /// this phone alone, with no internet.
    static func canPlaySolo(_ kind: String) -> Bool {
        guard let item = item(OfflinePlayModes.offlineId(for: kind)) else { return false }
        return item.canPlaySolo
    }

    /// Whether a game can be played with phones nearby, with no internet.
    static func canPlayNearby(_ kind: String) -> Bool {
        guard let item = item(OfflinePlayModes.offlineId(for: kind)) else { return false }
        return OfflinePlayModes.canPlayNearby(item.info)
    }

    /// Every game that can be played alone, in catalogue order.
    static var soloGames: [OfflineCatalogueItem] { items.filter(\.canPlaySolo) }
}

/// Navigation value for one game played alone, offline: its rules, and Play.
/// `kind` is an offline game id, or an online game's id with an offline twin.
struct SoloGameRef: Hashable {
    let kind: String
}

/// What the room screen hands a catalogue item to build a game's view: plain
/// values, before the item decodes them into its own rules' types.
struct OfflineScreenInput {
    let data: Data
    let me: String
    let players: [OfflinePlayer]
    let isHost: Bool
    let clock: OfflineHostClock
    let refusal: String?
    let send: (Data) -> Void
}

/// One game in the catalogue: its rules (type-erased for the room) and how
/// to draw it.
struct OfflineCatalogueItem: Identifiable {
    let entry: OfflineGameEntry
    /// Main-actor: it builds SwiftUI views.
    private let make: @MainActor (OfflineScreenInput) -> AnyView?

    var id: String { entry.info.id }
    var info: OfflineGameInfo { entry.info }
    /// It can be played alone: a one-player game, or one with a bot.
    var canPlaySolo: Bool { OfflinePlayModes.canPlaySolo(entry.info, hasBot: entry.hasBot) }
    /// Computer players a solo game seats.
    var soloBots: Int { OfflinePlayModes.soloBots(entry.info, hasBot: entry.hasBot) ?? 0 }

    // Not specialised or inlined, like `OfflineGameEntry.init`: twenty games
    // specialised into `items`' one initializer stalled the Release build.
    @inline(never)
    @_semantics("optimize.sil.specialize.generic.never")
    init<Rules: OfflineGameRules, Screen: View>(_ rules: Rules.Type,
                                                 @ViewBuilder screen: @escaping @MainActor (OfflineGameContext<Rules>) -> Screen) {
        self.init(entry: OfflineGameEntry(rules), screen: screen)
    }

    /// A game with a computer player: the same, with the bot's entry. A
    /// label of its own rather than an overload, so twenty-odd lines of the
    /// catalogue never make the type checker choose between two.
    @inline(never)
    @_semantics("optimize.sil.specialize.generic.never")
    init<Rules: OfflineBotRules, Screen: View>(withBot rules: Rules.Type,
                                                @ViewBuilder screen: @escaping @MainActor (OfflineGameContext<Rules>) -> Screen) {
        self.init(entry: OfflineGameEntry(withBot: rules), screen: screen)
    }

    @inline(never)
    @_semantics("optimize.sil.specialize.generic.never")
    private init<Rules: OfflineGameRules, Screen: View>(entry: OfflineGameEntry,
                                                         screen: @escaping @MainActor (OfflineGameContext<Rules>) -> Screen) {
        self.entry = entry
        make = { input in
            guard let view = try? OfflineCoding.decode(Rules.PlayerView.self, from: input.data) else { return nil }
            let send = input.send
            let context = OfflineGameContext<Rules>(
                view: view, me: input.me, players: input.players, isHost: input.isHost,
                clock: input.clock, refusal: input.refusal,
                send: { action in
                    if let data = try? OfflineCoding.encode(action) { send(data) }
                }
            )
            return AnyView(screen(context))
        }
    }

    /// The game's view for this input, or nil if the bytes are not this
    /// game's view (a packet from another version of the app).
    @MainActor
    func screen(_ input: OfflineScreenInput) -> AnyView? { make(input) }
}
