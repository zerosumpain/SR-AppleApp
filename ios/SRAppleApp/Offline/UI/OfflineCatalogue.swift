import SwiftUI

/// Every offline game: one line each, pairing a game's rules with its view.
///
///     OfflineCatalogueItem(QuickDrawRules.self) { QuickDrawView(context: $0) },
///
/// The rules type gives the card (`info`) and the host's engine
/// (`OfflineGameEntry`); the closure builds the view from an
/// `OfflineGameContext<Rules>` — the decoded `PlayerView`, who I am, the
/// players, the host's clock and `send`. Order within a category is the order
/// here.
enum OfflineCatalogue {
    static let items: [OfflineCatalogueItem] = [
        // Card games.
        OfflineCatalogueItem(CrazyEightsRules.self) { CrazyEightsView(context: $0) },
        OfflineCatalogueItem(GoFishRules.self) { GoFishView(context: $0) },
        OfflineCatalogueItem(BlackjackRules.self) { BlackjackView(context: $0) },
        OfflineCatalogueItem(CheatRules.self) { CheatView(context: $0) },
        OfflineCatalogueItem(OldMaidRules.self) { OldMaidView(context: $0) },
        OfflineCatalogueItem(KnockoutWhistRules.self) { KnockoutWhistView(context: $0) },
        OfflineCatalogueItem(HigherLowerRules.self) { HigherLowerView(context: $0) },
        // Reaction games.
        OfflineCatalogueItem(QuickDrawRules.self) { QuickDrawView(context: $0) },
        OfflineCatalogueItem(SnapRules.self) { SnapView(context: $0) },
        OfflineCatalogueItem(ColourClashRules.self) { ColourClashView(context: $0) },
        OfflineCatalogueItem(WhackAMoleRules.self) { WhackAMoleView(context: $0) },
        OfflineCatalogueItem(HotPotatoRules.self) { HotPotatoView(context: $0) },
        OfflineCatalogueItem(SwipeSaysRules.self) { SwipeSaysView(context: $0) },
        OfflineCatalogueItem(ReflexGridRules.self) { ReflexGridView(context: $0) },
        // Skill games.
        OfflineCatalogueItem(DotsAndBoxesRules.self) { DotsAndBoxesView(context: $0) },
        OfflineCatalogueItem(MemoryPairsRules.self) { MemoryPairsView(context: $0) },
        OfflineCatalogueItem(FourInARowRules.self) { FourInARowView(context: $0) },
        OfflineCatalogueItem(CodeBreakerRules.self) { CodeBreakerView(context: $0) },
        OfflineCatalogueItem(SteadyHandRules.self) { SteadyHandView(context: $0) },
        OfflineCatalogueItem(SeaBattleRules.self) { SeaBattleView(context: $0) },
    ]

    /// What the host's room can start.
    static var entries: [OfflineGameEntry] { items.map(\.entry) }

    static func item(_ id: String) -> OfflineCatalogueItem? {
        items.first { $0.id == id }
    }

    static func games(in category: OfflineGameCategory) -> [OfflineCatalogueItem] {
        items.filter { $0.info.category == category }
    }
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

    init<Rules: OfflineGameRules, Screen: View>(_ rules: Rules.Type,
                                                 @ViewBuilder screen: @escaping @MainActor (OfflineGameContext<Rules>) -> Screen) {
        entry = OfflineGameEntry(rules)
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
