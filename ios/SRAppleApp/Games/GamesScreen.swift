import SwiftUI
import UIKit

/// The Games tab: invitations waiting, rooms I am in, and a game to start.
///
/// A shelf of games rather than one game's front door. The rooms and invites
/// lead — they are somebody waiting on me. Then the play half: a hero card
/// (the game this phone plays most, else one of the new ones, a different one
/// each day), the three doors (the leaderboard, play nearby, Marbler), the
/// search, the rest of the most played as a strip of small cards, and the
/// games on shelves by kind, each tile in its shelf's colour with the game's
/// own picture drawn on it (John, 2026-10-27: "prettier design like on the
/// home page"). At the foot, the family's ideas for games to come. A tile
/// opens the new-game sheet already set to that game, or — for a game played
/// on this phone — the game itself.
///
/// The filter strip is pinned over the page, not stacked above it, so the
/// page scrolls behind it and the `sr.` bar the way Health's does. Beside the
/// shelves it has two quick filters of its own: the games this phone plays by
/// itself, and the ones played in a room with the family.
struct GamesScreen: View {
    @ObservedObject var store: GamesStore
    @EnvironmentObject private var router: Router
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The game whose tile was tapped; the sheet opens on it.
    @State private var starting: GameKind?
    /// The shelf the strip holds the page to: a category's raw value,
    /// `GamesShelf.favouritesFilter`, one of `GamesPagePlan`'s quick filters,
    /// or nil for every game.
    @State private var filter: String?
    @State private var query = ""
    /// A parent's Close, waiting on the confirmation dialog.
    @State private var closing: GameOpenLobby?
    /// A game tile's height: Home's tile unit, scaling with the text.
    @ScaledMetric(relativeTo: .body) private var tileHeight: CGFloat = 164
    @ScaledMetric(relativeTo: .body) private var doorHeight: CGFloat = 100
    @ScaledMetric(relativeTo: .body) private var heroHeight: CGFloat = 212
    @ScaledMetric(relativeTo: .body) private var shortcutSide: CGFloat = 124

    private static let gap: CGFloat = 14

    /// The games this build offers, in the catalogue's order.
    private var offeredGames: [GameKind] { GameKind.allCases.filter(offered) }

    /// What a search reads for each game: its name, its line and its blurb.
    private var searchText: [String: String] {
        Dictionary(uniqueKeysWithValues: offeredGames.map { ($0.rawValue, "\($0.title) \($0.line) \($0.blurb)") })
    }

    private var favourites: [String] {
        GamesShelf.favourites(offeredGames.map(\.rawValue), usage: store.usage, now: Date())
    }

    /// A quick filter is the page's own, not a shelf `GamesShelf` knows.
    private var quickFilter: Bool {
        filter == GamesPagePlan.phoneFilter || filter == GamesPagePlan.familyFilter
    }

    private var shelves: [GamesShelf.Section] {
        let sections = GamesShelf.sections(games: offeredGames.map(\.rawValue), text: searchText, usage: store.usage,
                                           now: Date(), filter: quickFilter ? nil : filter, query: query)
        // A search looks through every game, whatever the filter.
        guard quickFilter, query.isEmpty else { return sections }
        let onPhone = filter == GamesPagePlan.phoneFilter
        let keep = Set(offeredGames.filter { $0.playsOnPhone == onPhone }.map(\.rawValue))
        return GamesPagePlan.narrow(sections, keep: keep)
    }

    /// The hero card's game, on the unfiltered page only.
    private var spotlight: (kind: GameKind, reason: GamesSpotlightReason)? {
        guard filter == nil, query.isEmpty else { return nil }
        guard let pick = GamesPagePlan.spotlight(games: offeredGames.map(\.rawValue), favourites: favourites,
                                                 usage: store.usage, now: Date()),
              let kind = GameKind(rawValue: pick.game) else { return nil }
        return (kind, pick.reason)
    }

    /// The most played after the hero's, as a strip of small cards.
    private var recentGames: [GameKind] {
        guard filter == nil, query.isEmpty else { return [] }
        let hero = spotlight?.kind.rawValue
        return favourites.filter { $0 != hero }.compactMap(GameKind.init(rawValue:))
    }

    /// The strip under the bar: what is waiting (a jump), then the shelves (a
    /// filter that stays lit while it holds), then the leaderboard and the
    /// ideas — the same furniture as Family's places and Health's areas.
    private var chips: [SRChip] {
        var out: [SRChip] = []
        if !store.invites.isEmpty { out.append(SRChip(id: "invites", title: "Invites", icon: "envelope.fill", count: store.invites.count)) }
        if !store.rooms.isEmpty { out.append(SRChip(id: "rooms", title: "Your games", icon: "play.circle.fill", count: store.rooms.count)) }
        out.append(SRChip(id: "all", title: "All games", icon: "square.grid.2x2.fill"))
        if !favourites.isEmpty { out.append(SRChip(id: GamesShelf.favouritesFilter, title: "Most played", icon: "star.fill")) }
        out.append(SRChip(id: GamesPagePlan.phoneFilter, title: "On this phone", icon: "iphone"))
        out.append(SRChip(id: GamesPagePlan.familyFilter, title: "With family", icon: "person.2.fill"))
        for category in GamesShelf.categories(offeredGames.map(\.rawValue)) {
            out.append(SRChip(id: category.rawValue, title: category.chip, icon: category.icon))
        }
        out.append(SRChip(id: "leaderboard", title: "Leaderboard", icon: "trophy.fill"))
        out.append(SRChip(id: "ideas", title: "Ideas", icon: "lightbulb.fill"))
        return out
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: SR.sectionGap) {
                    deliveryNote
                    invitesSection
                    roomsSection
                    openLobbiesSection
                    playHeader
                    heroCard
                    doors
                    searchField
                    recentStrip
                    shelvesSection
                    GameSuggestionsSection()
                        .id("games-ideas")
                }
                .padding(.horizontal, SR.gutter)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .srPinnedStrip {
                SRChipStrip(chips: chips, selected: filter ?? "all", identifier: "games-strip") { chip in
                    choose(chip, proxy: proxy)
                }
            }
        }
        .accessibilityIdentifier("games-screen")
        .srGround(.warm)
        .navigationTitle("Games")
        .navigationBarTitleDisplayMode(.inline)
        .srTabBar()
        .task {
            if store.lobby == nil { await store.load() }
            await store.askForNotificationsIfUndecided()
        }
        .srRefreshable { await store.load() }
        .onAppear { store.setWatching(true) }
        .onDisappear { store.setWatching(false) }
        .overlay(alignment: .bottom) {
            if let message = store.message { SRBanner(text: message) }
        }
        .confirmationDialog(
            closing.map { "Close \($0.hostName)’s \(GameNames.title($0.game)) lobby?" } ?? "Close this lobby?",
            isPresented: Binding(get: { closing != nil }, set: { if !$0 { closing = nil } }),
            titleVisibility: .visible,
            presenting: closing
        ) { lobby in
            Button("Close it for everyone", role: .destructive) {
                Task { _ = await store.closeLobby(lobby.id) }
            }
            Button("Keep it open", role: .cancel) {}
        } message: { lobby in
            Text(Self.closingMessage(lobby))
        }
        .sheet(item: $starting) { kind in
            NewGameSheet(game: kind, players: store.players, busy: store.busy == "new",
                         paces: store.paceChoices(for: kind),
                         playOffline: offline(kind)) { request in
                switch await store.create(request) {
                case .created(let room):
                    starting = nil
                    router.push(GameRoomRef(id: room.id, game: room.game), on: .games)
                    return nil
                case .refused(let sentence):
                    return sentence
                }
            }
        }
    }

    /// The way into a game's offline version, when it has one: the sheet
    /// closes and the game's offline page opens on Games.
    private func offline(_ kind: GameKind) -> (() -> Void)? {
        guard OfflineCatalogue.canPlaySolo(kind.rawValue) || OfflineCatalogue.canPlayNearby(kind.rawValue) else { return nil }
        return {
            starting = nil
            store.recordPlay(kind.rawValue)
            router.push(SoloGameRef(kind: kind.rawValue), on: .games)
        }
    }

    // MARK: - The top

    /// The one honest sentence about delivery — and, while the first read is
    /// out, that it is happening (the shelves below never wait for it).
    private var deliveryNote: some View {
        HStack(spacing: 8) {
            if store.loading && store.lobby == nil {
                ProgressView()
                    .controlSize(.small)
                    .tint(SR.accent)
                    .accessibilityHidden(true)
                Text("Checking for invites…")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            } else {
                Image(systemName: "bell.badge")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SR.inkMuted)
                    .accessibilityHidden(true)
                // No page title: the tab says Games.
                Text("Invites reach phones with the app open.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("games-delivery-note")
            }
        }
    }

    @ViewBuilder
    private var invitesSection: some View {
        if !store.invites.isEmpty {
            section("Invitations", trailing: "\(store.invites.count)", id: "games-invites") {
                ForEach(store.invites) { invite in
                    GameInviteCard(
                        invite: invite,
                        busy: store.busy == invite.roomId,
                        serverNow: { store.serverNow() },
                        join: {
                            Task {
                                if await store.join(invite) {
                                    SRHaptic.ok()
                                    router.push(GameRoomRef(id: invite.roomId, game: invite.game), on: .games)
                                } else {
                                    SRHaptic.bad()
                                }
                            }
                        },
                        decline: { Task { await store.decline(invite) } }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var roomsSection: some View {
        if !store.rooms.isEmpty {
            section("Your games", trailing: yourMovesLabel, id: "games-rooms") {
                // My move first, then the most recently changed — a game
                // played over days comes back here to resume.
                ForEach(store.yourGames) { room in
                    // A Button onto the tab's path, not a NavigationLink: the
                    // link under an interactive glass card never received the
                    // tap in CI; a Button over the same glass does.
                    Button {
                        SRHaptic.tap()
                        router.push(GameRoomRef(id: room.id, game: room.game), on: .games)
                    } label: {
                        GameRoomRow(room: room, serverNow: { store.serverNow() })
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("games-room-\(room.id)")
                }
            }
        }
    }

    @ViewBuilder
    private var openLobbiesSection: some View {
        if store.isParent && !store.openLobbies.isEmpty {
            section("Open lobbies", trailing: "Parent", id: "games-open-lobbies") {
                ForEach(store.openLobbies) { lobby in
                    GameOpenLobbyRow(lobby: lobby, busy: store.busy == lobby.id) { closing = lobby }
                }
            }
        }
    }

    // MARK: - Play

    private var playHeader: some View {
        SRSectionLabel(text: "Play", trailing: playTrailing)
            .id("games-play")
    }

    @ViewBuilder
    private var heroCard: some View {
        if let hero = spotlight {
            Button {
                SRHaptic.tap()
                open(hero.kind)
            } label: {
                GamesHeroCard(kind: hero.kind, kicker: hero.reason.kicker)
                    .frame(height: typeSize.isAccessibilitySize ? nil : heroHeight)
            }
            .buttonStyle(SRPressStyle())
            .accessibilityIdentifier("games-hero")
        }
    }

    /// The rest of the most played, a strip of small cards to swipe along.
    @ViewBuilder
    private var recentStrip: some View {
        let recent = recentGames
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                SRSectionLabel(text: "Most played on this phone", trailing: "\(recent.count)")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(recent) { kind in
                            shortcut(kind)
                        }
                    }
                    .padding(.horizontal, SR.gutter)
                    .padding(.vertical, 10)
                }
                .padding(.horizontal, -SR.gutter)
            }
            .id("games-shelf-favourites")
        }
    }

    private func shortcut(_ kind: GameKind) -> some View {
        Button {
            SRHaptic.tap()
            open(kind)
        } label: {
            // Capped: at the largest text sizes a card the scaled width would
            // be wider than a small phone.
            GamesShortcutTile(kind: kind)
                .frame(width: min(shortcutSide, 220), height: min(shortcutSide, 220) * 0.86)
        }
        .buttonStyle(SRPressStyle())
        .accessibilityIdentifier("games-top-\(kind.rawValue)")
    }

    @ViewBuilder
    private var shelvesSection: some View {
        let sections = shelves
        if sections.isEmpty {
            SREmpty(
                title: emptyTitle,
                icon: query.isEmpty ? "square.grid.2x2" : "magnifyingglass",
                message: query.isEmpty ? "Try another shelf." : "Try another word — a game's name, or what it's like.",
                actionLabel: "Show every game",
                action: {
                    withAnimation(.snappy) {
                        query = ""
                        filter = nil
                    }
                }
            )
            .accessibilityIdentifier("games-shelf-empty")
        } else {
            ForEach(sections) { section in
                shelf(section, idPrefix: "games-new")
            }
        }
    }

    // MARK: - The strip

    private func choose(_ chip: SRChip, proxy: ScrollViewProxy) {
        switch chip.id {
        case "leaderboard":
            router.push(GameLeaderboardRef(), on: .games)
        case "invites", "rooms":
            withAnimation(.snappy) { proxy.scrollTo("games-\(chip.id)", anchor: .top) }
        case "ideas":
            withAnimation(.snappy) { proxy.scrollTo("games-ideas", anchor: .top) }
        default:
            // A shelf: hold the page to it (again on the lit chip lets go),
            // and bring the games up under the strip.
            let next: String? = chip.id == "all" ? nil : chip.id
            withAnimation(.snappy) {
                filter = (next == filter) ? nil : next
                proxy.scrollTo("games-play", anchor: .top)
            }
        }
    }

    private var emptyTitle: String {
        query.isEmpty ? "Nothing on this shelf yet" : "No game matches “\(query)”"
    }

    private static func closingMessage(_ lobby: GameOpenLobby) -> String {
        lobby.players.isEmpty ? "Nobody has joined yet." : "\(GameNames.list(lobby.players)) will be told it was closed."
    }

    private var playTrailing: String? {
        if !query.isEmpty { return nil }
        if filter == GamesShelf.favouritesFilter { return "Most played" }
        if filter == GamesPagePlan.phoneFilter { return "On this phone" }
        if filter == GamesPagePlan.familyFilter { return "With family" }
        if let category = filter.flatMap(GameCategory.init(rawValue:)) { return category.chip }
        return "\(offeredGames.count) games"
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SR.inkMuted)
                .accessibilityHidden(true)
            TextField("Find a game", text: $query)
                .font(SR.Text.body(17))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("games-search")
            if !query.isEmpty {
                Button {
                    SRHaptic.select()
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(SR.inkMuted)
                        .frame(width: SR.tapTarget, height: SR.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear the search")
                .accessibilityIdentifier("games-search-clear")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .frame(minHeight: 52)
        .srGlassCard(.paper)
    }

    // MARK: - The doors

    /// The leaderboard, play nearby and Marbler: three small tiles in a row,
    /// a column at the largest text sizes.
    @ViewBuilder
    private var doors: some View {
        let items = [
            Door(id: "games-leaderboard", title: "Leaderboard", line: "Wins and high scores", icon: "trophy.fill",
                 hue: SR.Hue.alerts) { router.push(GameLeaderboardRef(), on: .games) },
            Door(id: "games-offline", title: "Play nearby", line: "Offline, phone to phone",
                 icon: "dot.radiowaves.left.and.right", hue: SR.Hue.family) { router.push(OfflineGamesRef(), on: .games) },
            Door(id: "games-marbler", title: "Marbler", line: "A marble race on this phone",
                 icon: "circle.grid.cross.fill", hue: SR.Hue.flows) { router.push(MarblerRef(), on: .games) },
        ]
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Self.gap))
            : AnyLayout(HStackLayout(spacing: 10))
        layout {
            ForEach(items) { item in
                Button {
                    SRHaptic.tap()
                    item.open()
                } label: {
                    GameDoorTile(title: item.title, line: item.line, icon: item.icon, hue: item.hue)
                        .frame(height: typeSize.isAccessibilitySize ? nil : doorHeight)
                }
                .buttonStyle(SRPressStyle())
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier(item.id)
            }
        }
    }

    /// One of the three doors.
    private struct Door: Identifiable {
        let id: String
        let title: String
        let line: String
        let icon: String
        let hue: SR.Hue
        let open: () -> Void
    }

    // MARK: - Shelves

    /// One shelf: its badge, name and line, then its games two by two (one a
    /// row at the largest text sizes, where two would cut every name).
    private func shelf(_ section: GamesShelf.Section, idPrefix: String) -> some View {
        let kinds = section.games.compactMap(GameKind.init(rawValue:))
        let perRow = typeSize.isAccessibilitySize ? 1 : 2
        let rows = stride(from: 0, to: kinds.count, by: perRow).map { Array(kinds[$0..<min($0 + perRow, kinds.count)]) }
        let now = Date()
        return VStack(alignment: .leading, spacing: SR.cardGap + 2) {
            GamesShelfHeader(section: section, count: kinds.count)
            VStack(spacing: Self.gap) {
                ForEach(rows, id: \.first) { row in
                    HStack(spacing: Self.gap) {
                        ForEach(row) { kind in
                            tile(kind, idPrefix: idPrefix,
                                 isNew: GamesPagePlan.isNew(kind.rawValue, usage: store.usage, now: now))
                        }
                        // A shelf with an odd count keeps its last tile square.
                        if row.count < perRow { Color.clear.frame(maxWidth: .infinity) }
                    }
                    .frame(height: typeSize.isAccessibilitySize ? nil : tileHeight)
                    // Home's settle-in as a row scrolls on, so the shelf feels
                    // like the same app.
                    .scrollTransition(.interactive, axis: .vertical) { content, phase in
                        content
                            .scaleEffect(phase.isIdentity ? 1 : 0.95)
                            .opacity(phase.isIdentity ? 1 : 0.7)
                    }
                }
            }
        }
        .id("games-shelf-\(section.id)")
    }

    private func tile(_ kind: GameKind, idPrefix: String, isNew: Bool) -> some View {
        Button {
            SRHaptic.tap()
            open(kind)
        } label: {
            GameTile(kind: kind, isNew: isNew)
        }
        .buttonStyle(SRPressStyle())
        // Tap Duel keeps the id it shipped with, so a test looking for a
        // game's tile finds the one on its shelf.
        .accessibilityIdentifier(idPrefix == "games-new" && kind == .tapDuel ? "games-new" : "\(idPrefix)-\(kind.rawValue)")
    }

    /// Where a game's tile goes: the new-game sheet, which starts a room on
    /// the site. Every tap on the shelf comes through here, so this is where a
    /// game played on this phone with no room (the physics games' branch,
    /// `playsOnPhone`) is sent to its own screen instead, and counted as
    /// played (`store.recordPlay`), since no room will ever count it.
    private func open(_ kind: GameKind) {
        // The physics games and the puzzles play on this phone, with no room to start.
        if kind.playsOnPhone {
            store.recordPlay(kind.rawValue)
            router.push(PhysicsGameRef(kind: kind), on: .games)
        } else {
            starting = kind
        }
    }

    /// Hometowns is offered only once the site plays it (its lobby lists the
    /// game's paces): family phones pick up an app build before the server
    /// release, and a county the server refuses to start is a dead tile.
    private func offered(_ kind: GameKind) -> Bool {
        kind != .hometowns || store.lobby?.paces[GameKind.hometowns.rawValue] != nil
    }

    /// "2 waiting on you" beside "Your games", when durable games wait on me.
    private var yourMovesLabel: String? {
        let n = YourGames.myMoves(store.rooms)
        return n == 0 ? nil : "\(n) waiting on you"
    }

    private func section<Content: View>(_ title: String, trailing: String?, id: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: title, trailing: trailing)
            content()
        }
        .id(id)
    }
}

extension GameCategory {
    /// The shelf's colour, from the reader's palette: Home's tiles' gradients,
    /// so the games read as part of the same app.
    var hue: SR.Hue {
        switch self {
        case .word: return SR.Hue.news
        case .party: return SR.Hue.daydream
        case .strategy: return SR.Hue.trips
        case .quick: return SR.Hue.games
        case .physics: return SR.Hue.flows
        case .puzzle: return SR.Hue.wildmind
        case .outdoor: return SR.Hue.steps
        }
    }
}

/// A shelf's heading: its colour and icon, its name and line, and how many.
struct GamesShelfHeader: View {
    let section: GamesShelf.Section
    let count: Int

    private var category: GameCategory? { GameCategory(rawValue: section.id) }

    var body: some View {
        let hue: SR.Hue = category?.hue ?? SR.Hue.games
        let icon: String = category?.icon ?? (section.id == "search" ? "magnifyingglass" : "star.fill")
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(hue.onFill)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hue.gradient))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(SR.Text.title(19))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let line = section.line {
                    Text(line)
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Text("\(count)")
                .font(SR.Text.mono(13))
                .foregroundStyle(SR.inkSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(hue.wash))
                .accessibilityLabel(count == 1 ? "1 game" : "\(count) games")
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One game's tile on a shelf: Home's vivid tile — its shelf's gradient with
/// a sheen, light type, a soft coloured shadow — with the game's own picture
/// drawn behind its mark, name and line, and a chip saying how it is played.
struct GameTile: View {
    let kind: GameKind
    /// One of the new games, not yet played here: a NEW badge.
    var isNew: Bool = false

    private var category: GameCategory { GameCategory.of(kind.rawValue) }

    var body: some View {
        let hue = category.hue
        let shape = RoundedRectangle(cornerRadius: HomeTileFrame<EmptyView>.corner, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: kind.icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(hue.base)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(hue.onFill.opacity(0.94)))
                    .shadow(color: Color.black.opacity(0.12), radius: 3, y: 1)
                    .accessibilityHidden(true)
                Spacer(minLength: 4)
                badge(hue)
            }
            Spacer(minLength: 0)
            Text(kind.title)
                .font(SR.Text.display(20))
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
            Text(kind.line)
                .font(SR.Text.secondary(13))
                .opacity(0.92)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(hue.onFill)
        .background { GamesTileBackdrop(game: kind.rawValue, hue: hue, symbolSide: 84) }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
        .shadow(color: hue.base.opacity(0.26), radius: 12, y: 5)
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityHint(kind.playsOnPhone ? "Opens the game" : "Sets up a new game")
        .accessibilityAddTraits(.isButton)
    }

    private var spoken: String {
        let how = GamesPagePlan.playersLine(kind.rawValue, onPhone: kind.playsOnPhone)
        return "\(kind.title)\(isNew ? ", new" : ""). \(kind.line) \(how)."
    }

    /// NEW, or how it is played: the phone on its own, or a room of 2–5.
    @ViewBuilder
    private func badge(_ hue: SR.Hue) -> some View {
        if isNew {
            Text("NEW")
                .font(SR.Text.label(12))
                .tracking(1.2)
                .foregroundStyle(hue.base)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(hue.onFill))
        } else {
            HStack(spacing: 4) {
                Image(systemName: kind.playsOnPhone ? "iphone" : "person.2.fill")
                    .font(.system(size: 10, weight: .bold))
                if !kind.playsOnPhone {
                    Text(GamesPagePlan.playersChip(kind.rawValue, onPhone: false))
                        .font(SR.Text.label(12))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(hue.onFill.opacity(0.22)))
        }
    }
}

/// The big card at the head of the games: the one this phone plays most, or
/// one of the new ones, with its picture large and one button's worth of
/// invitation to play it.
struct GamesHeroCard: View {
    let kind: GameKind
    let kicker: String

    var body: some View {
        let hue = GameCategory.of(kind.rawValue).hue
        let shape = RoundedRectangle(cornerRadius: SR.Glass.radius + 4, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            Text(kicker.uppercased())
                .font(SR.Text.label(12))
                .tracking(SR.kickerTracking)
                .opacity(0.9)
            Spacer(minLength: 0)
            Text(kind.title)
                .font(SR.Text.hero(32))
                .tracking(-0.5)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            Text(kind.line)
                .font(SR.Text.secondary(15))
                .opacity(0.94)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 40)
            playCapsule(hue)
                .padding(.top, 6)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(hue.onFill)
        .background { GamesTileBackdrop(game: kind.rawValue, hue: hue, symbolSide: 150) }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
        .shadow(color: hue.base.opacity(0.32), radius: 18, y: 8)
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kicker). \(kind.title). \(kind.line)")
        .accessibilityHint(kind.playsOnPhone ? "Opens the game" : "Sets up a new game")
        .accessibilityAddTraits(.isButton)
    }

    private func playCapsule(_ hue: SR.Hue) -> some View {
        HStack(spacing: 8) {
            Image(systemName: kind.playsOnPhone ? "play.fill" : "person.2.fill")
                .font(.system(size: 14, weight: .bold))
            Text(kind.playsOnPhone ? "Play now" : "Set up a game")
                .font(SR.Text.title(16))
                .lineLimit(1)
        }
        .foregroundStyle(hue.base)
        .padding(.horizontal, 20)
        .frame(minHeight: 50)
        .background(Capsule().fill(hue.onFill))
        .shadow(color: Color.black.opacity(0.14), radius: 6, y: 3)
    }
}

/// A small card on the most-played strip: the game's colour, mark and name.
struct GamesShortcutTile: View {
    let kind: GameKind

    var body: some View {
        let hue = GameCategory.of(kind.rawValue).hue
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: kind.icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(hue.base)
                .frame(width: 34, height: 34)
                .background(Circle().fill(hue.onFill.opacity(0.94)))
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            Text(kind.title)
                .font(SR.Text.title(16))
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(hue.onFill)
        .background { GamesTileBackdrop(game: kind.rawValue, hue: hue, symbolSide: 64) }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
        .shadow(color: hue.base.opacity(0.24), radius: 8, y: 4)
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.title)
        .accessibilityHint(kind.playsOnPhone ? "Opens the game" : "Sets up a new game")
        .accessibilityAddTraits(.isButton)
    }
}

/// A small tile for a place to go — the leaderboard, play nearby, Marbler.
struct GameDoorTile: View {
    let title: String
    let line: String
    let icon: String
    let hue: SR.Hue

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(hue.onFill)
                .frame(width: 34, height: 34)
                .background(Circle().fill(hue.gradient))
                .shadow(color: hue.base.opacity(0.3), radius: 4, y: 2)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            Text(title)
                .font(SR.Text.title(15))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(line)
                .font(SR.Text.secondary(12))
                .foregroundStyle(SR.inkMuted)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            // A wash of the door's colour under the glass, so the three read
            // as three places rather than three grey panels.
            LinearGradient(colors: [hue.wash, Color.clear], startPoint: .top, endPoint: .bottom)
                .clipShape(shape)
        }
        .srGlass(.paper, in: shape, interactive: true)
        .contentShape(shape)
    }
}

/// A lobby not yet started, on a parent's list: whose, who is in, who is
/// asked — and Close.
struct GameOpenLobbyRow: View {
    let lobby: GameOpenLobby
    let busy: Bool
    let close: () -> Void

    var body: some View {
        SRCard {
            HStack(spacing: 12) {
                GameArtBadge(game: lobby.game, side: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(role: .destructive) {
                    SRHaptic.tap()
                    close()
                } label: {
                    if busy {
                        ProgressView().tint(SR.accent)
                    } else {
                        SRButtonLabel(title: "Close", icon: "xmark.octagon")
                    }
                }
                .srButton(.regular)
                .controlSize(.large)
                .disabled(busy)
                .accessibilityLabel("Close \(lobby.hostName)’s \(GameNames.title(lobby.game)) lobby")
                .accessibilityIdentifier("games-close-\(lobby.id)")
            }
            .frame(minHeight: SR.tapTarget)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("games-open-lobby-\(lobby.id)")
    }

    private var title: String {
        let game = GameNames.title(lobby.game)
        return lobby.mine ? "\(game) · you’re in it" : "\(lobby.hostName)’s \(game)"
    }

    /// "Sam and Robin in · Kit asked".
    private var detail: String {
        var parts: [String] = []
        parts.append(lobby.players.isEmpty ? "Nobody in yet" : "\(GameNames.list(lobby.players)) in")
        if !lobby.invited.isEmpty { parts.append("\(GameNames.list(lobby.invited)) asked") }
        return parts.joined(separator: " · ")
    }
}

/// An invitation: the game's badge, who asked, how hard, who else, how long
/// it stays open — and Join or Decline, big enough for a thumb.
struct GameInviteCard: View {
    let invite: GameInvite
    let busy: Bool
    /// The server's clock, for "Closes in 2:41".
    var serverNow: () -> Double? = { nil }
    let join: () -> Void
    let decline: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        SRCard(accented: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    GameArtBadge(game: invite.game, side: 54)
                    heading
                }
                closes
                buttons
            }
        }
        .accessibilityIdentifier("games-invite-\(invite.roomId)")
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(invite.hostName) invited you".uppercased())
                .font(SR.Text.label())
                .tracking(1.2)
                .foregroundStyle(SR.accent)
                .fixedSize(horizontal: false, vertical: true)
            Text(GameNames.title(invite.game))
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let about = invite.about {
                Text(about)
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.accentInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("games-invite-about-\(invite.roomId)")
            }
            Text("\(GameDifficulty.label(for: invite.difficulty)) · \(GameNames.list(invite.players))")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Not combined: the quiz's "about" line keeps its own id for the tests.
    }

    /// How long the lobby stays open, ticking: the deadline is minutes.
    @ViewBuilder
    private var closes: some View {
        if let end = invite.expiresAt {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                if let now = serverNow() {
                    let left = Int(((end - now) / 1000).rounded(.down))
                    Label(GamesPagePlan.closesLine(secondsLeft: left), systemImage: "timer")
                        .font(SR.Text.mono())
                        .foregroundStyle(left < 30 ? SR.accent : SR.inkMuted)
                        .monospacedDigit()
                }
            }
        }
    }

    private var buttons: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            Button {
                SRHaptic.tap()
                join()
            } label: {
                Group {
                    if busy {
                        ProgressView().tint(SR.cream)
                    } else {
                        SRButtonLabel(title: "Join", icon: "play.fill", fill: true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityLabel("Join \(GameNames.title(invite.game))")
            .accessibilityIdentifier("games-invite-join-\(invite.roomId)")
            Button {
                SRHaptic.select()
                decline()
            } label: {
                SRButtonLabel(title: "Decline", fill: true)
                    .frame(minHeight: 44)
            }
            .srButton(.regular)
            .controlSize(.large)
            .accessibilityIdentifier("games-invite-decline-\(invite.roomId)")
        }
        .disabled(busy)
    }
}

/// A room I am in, to go back to: the game's badge, whose it is or whose move,
/// and where it has got to.
struct GameRoomRow: View {
    let room: GameRoomSummary
    /// The server's clock, for a durable game's "21 h left".
    var serverNow: () -> Double? = { nil }

    var body: some View {
        SRCard(accented: room.myTurn, interactive: true) {
            HStack(spacing: 12) {
                GameArtBadge(game: room.game, side: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(GameNames.title(room.game))
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    status
                }
                Spacer(minLength: 8)
                SRGlassChip(text: phaseLabel, icon: phaseIcon, tone: phaseTone)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SR.inkMuted)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: SR.tapTarget)
        }
        .background {
            // My move: the row glows faintly in the game's colour, so it is
            // found before it is read.
            if room.myTurn {
                RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                    .fill(GamesArt.hue(room.game).wash)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Resume")
    }

    @ViewBuilder
    private var status: some View {
        if room.durable {
            // Ticks once a minute: the deadline is hours, not seconds.
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                Text(YourGames.status(room, atServer: serverNow()) ?? "Hosted by \(room.hostName)")
                    .font(room.myTurn ? SR.Text.bodyMedium(15) : SR.Text.secondary())
                    .foregroundStyle(room.myTurn ? SR.accentInk : SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("games-room-status-\(room.id)")
            }
            if room.pace == .async {
                Text(YourGames.paceLine(room))
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text("Hosted by \(room.hostName)")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
        }
    }

    private var phaseLabel: String {
        switch room.phase {
        case .lobby: return "Lobby"
        case .countdown, .armed, .result, .playing, .question, .reveal, .show, .input, .review: return "Playing"
        case .finished: return "Finished"
        case .closed: return "Closed"
        case .unknown: return "Open"
        }
    }

    private var phaseIcon: String {
        switch room.phase {
        case .lobby: return "hourglass"
        case .countdown, .armed, .result, .playing, .question, .reveal, .show, .input, .review: return "play.fill"
        case .finished: return "flag.checkered"
        case .closed: return "xmark"
        case .unknown: return "circle.fill"
        }
    }

    private var phaseTone: Color {
        switch room.phase {
        case .lobby, .unknown: return SR.accentInk
        case .countdown, .armed, .result, .playing, .question, .reveal, .show, .input, .review: return SR.good
        case .finished, .closed: return SR.inkSecondary
        }
    }
}

/// How hard, who to invite, Start — for the game whose tile was tapped.
struct NewGameSheet: View {
    let game: GameKind
    let players: [GamePerson]
    let busy: Bool
    /// The paces this game offers (`lobby.paces`); empty = live only, no picker.
    var paces: [GamePace] = []
    /// The game's offline version — alone, against the phone, or with
    /// phones nearby — when it has one. Nil hides the way in.
    var playOffline: (() -> Void)? = nil
    /// Creates the room. Nil when it did (the sheet is then closed by its
    /// owner); otherwise the server's sentence, shown above Start.
    let start: (CreateGameBody) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var difficulty: GameDifficulty = .easy
    @State private var invited: Set<String> = []
    @State private var working = false
    // Quiz Night.
    @State private var topic = ""
    @State private var audience: QuizAudience = .family
    @State private var quizMode: QuizMode = .general
    @State private var gcseSubject: GcseSubject?
    @State private var gcseBoard: GcseBoard = .aqa
    // Boggle.
    @State private var boggleSize = 4
    @State private var boggleSeconds = 120
    @State private var boggleScoring: BoggleScoring = .classic
    // Categories.
    @State private var categoriesCount = CategoriesSettings.defaultCount
    @State private var categoriesSeconds = CategoriesSettings.defaultSeconds
    // Liar's Dice.
    @State private var liarsDice = 5
    // Odd Artist Out.
    @State private var fakeRounds = 3
    // Homestead: the island size, as an index of `HomesteadSettings.islands`.
    @State private var homesteadIsland = 0
    // Hometowns: the county's name, rivalry, Regional Day hour and mishaps.
    @State private var county = HometownsCountySetup()
    // Draw & Guess.
    @State private var drawTurns = 1
    @State private var drawSeconds = 80
    // Marble Race: Marbler's course pack, read from the site, and the pick.
    @State private var marblePack: MarblerPack?
    @State private var marbleCourse: MarblerPack.Entry?
    @State private var marblePackError: String?
    // Manhunt.
    @State private var manhuntRadius = ManhuntSettings.defaultRadius
    @State private var manhuntMinutes = ManhuntSettings.defaultMinutes
    /// Play now or over days, for a durable game that offers both.
    @State private var paceSettings = GamePaceSettings()
    /// Why the last Start was refused.
    @State private var refusal: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SR.sectionGap) {
                    // The game was picked on its card, so the sheet does not
                    // offer the whole shelf again: it sets this game up — its
                    // picture, its name, and how it is played.
                    NewGameBanner(game: game)
                    SRPageHeader(kicker: "New game", title: game.title, strap: game.line)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("games-game-\(game.rawValue)")
                    NewGameHowTo(game: game)

                    // No signal, or nobody online: the same game on this phone.
                    if let playOffline {
                        Button {
                            SRHaptic.tap()
                            playOffline()
                        } label: {
                            SRRow(title: "Play offline", subtitle: "Alone, against the phone, or with phones nearby — results sync later",
                                  icon: "wifi.slash")
                                .padding(12)
                                .srGlassCard(.paper)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("games-play-offline")
                    }

                    // A county is always played over days: there is no pace to pick.
                    if !paces.isEmpty && game != .hometowns {
                        paceSection
                    }

                    if game == .quizNight {
                        quizSettings
                    }

                    if game == .boggle {
                        boggleSettings
                    }

                    if game == .categories {
                        categoriesSettings
                    }

                    if game == .liarsDice {
                        liarsDiceSettings
                    }

                    if game == .drawGuess {
                        drawGuessSettings
                    }

                    if game == .marbleRace {
                        marbleRaceSettings
                    }

                    if game == .fakeArtist {
                        fakeArtistSettings
                    }

                    if game == .manhunt {
                        manhuntSettings
                    }

                    if game == .homestead {
                        homesteadSettings
                    }

                    if game == .hometowns {
                        countySettings
                    }

                    // Marble Race's course sets how hard it is, and a county has
                    // its rivalry instead: no level to pick.
                    if game != .marbleRace && game != .hometowns {
                        VStack(alignment: .leading, spacing: SR.cardGap) {
                            SRSectionLabel(text: "Difficulty")
                            ForEach(GameDifficulty.allCases) { level in
                                choice(
                                    title: gcse ? "\(level.label) · \(GcseBand.label(level))" : level.label,
                                    line: gcse ? GcseBand.line(level, tiered: gcseSubject?.tiered ?? true) : level.line(for: game),
                                    selected: difficulty == level,
                                    id: "games-difficulty-\(level.rawValue)"
                                ) { difficulty = level }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: SR.cardGap) {
                        SRSectionLabel(text: game == .chess ? "Opponent" : "Players",
                                       trailing: invited.isEmpty ? sheetTrailing : "\(invited.count + 1)")
                        if players.isEmpty {
                            Text(sheetNobody)
                                .font(SR.Text.secondary())
                                .foregroundStyle(SR.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ForEach(players) { person in
                                choice(
                                    title: person.name,
                                    line: nil,
                                    selected: invited.contains(person.id),
                                    multi: game != .chess,
                                    id: "games-player-\(person.id)"
                                ) {
                                    if game == .chess {
                                        // Chess is for two: a pick replaces the last one.
                                        invited = invited.contains(person.id) ? [] : [person.id]
                                    } else {
                                        invited.formSymmetricDifference([person.id])
                                    }
                                }
                            }
                            Text(sheetPick)
                                .font(SR.Text.mono())
                                .foregroundStyle(SR.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                }
                .padding(.horizontal, SR.gutter)
                .padding(.vertical, 12)
            }
            // Start rides at the foot of the sheet, always in reach: the
            // settings above it can run to three screens on a small phone.
            .safeAreaInset(edge: .bottom, spacing: 0) { startBar }
            .srGround(.warm)
            .navigationTitle("New game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("games-new-cancel")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    /// Why the last Start was refused, then Start — pinned under the settings.
    private var startBar: some View {
        VStack(spacing: 10) {
            if let refusal {
                Label(refusal, systemImage: "exclamationmark.circle")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("games-new-refusal")
            }
            Button {
                SRHaptic.tap()
                begin()
            } label: {
                Group {
                    if working {
                        ProgressView().tint(SR.cream)
                    } else {
                        SRButtonLabel(title: invited.isEmpty ? "Open the lobby" : "Invite and open the lobby",
                                      icon: "arrow.right", fill: true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .disabled(working || busy)
            .accessibilityLabel(invited.isEmpty ? "Open the lobby" : "Invite and open the lobby")
            .accessibilityIdentifier("games-start")
        }
        .padding(.horizontal, SR.gutter)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .overlay(alignment: .top) { Rectangle().fill(SR.divider).frame(height: 0.5) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// Start: check what the phone can, then ask the site for the room.
    private func begin() {
        if gcse, gcseSubject == nil {
            refusal = "Pick a subject for the GCSE quiz."
            SRHaptic.bad()
            return
        }
        working = true
        refusal = nil
        let payload = request
        Task {
            if let sentence = await start(payload) {
                refusal = sentence
                SRHaptic.bad()
                UIAccessibility.post(notification: .announcement, argument: sentence)
            } else {
                // The lobby is open: the sheet closes on its way there.
                SRHaptic.ok()
            }
            working = false
        }
    }

    /// What Start sends: the game's own body, with the pace when it offers one.
    private var request: CreateGameBody {
        paces.isEmpty || game == .hometowns ? gameRequest : paceSettings.apply(to: gameRequest)
    }

    /// Play now, or over days with hours a turn — a durable game's pace.
    private var paceSection: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Pace")
            ForEach(paces) { pace in
                choice(
                    title: pace.label,
                    line: pace.line,
                    selected: paceSettings.pace == pace,
                    id: "games-pace-\(pace.rawValue)"
                ) { paceSettings.pace = pace }
            }
            if paceSettings.pace == .async {
                segments(
                    title: "Time for a turn",
                    options: GamePace.deadlineHours.map { (value: $0, label: GamePace.hoursLabel($0)) },
                    selected: $paceSettings.deadlineHours,
                    id: "games-pace-hours"
                )
            }
            Text(paceSettings.line)
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("games-pace-line")
        }
    }

    /// The game's own create body.
    private var gameRequest: CreateGameBody {
        let invite = players.filter { invited.contains($0.id) }.map(\.id)
        if game == .quizNight {
            return QuizNightSettings(difficulty: difficulty, topic: topic, audience: audience,
                                     mode: quizMode, subject: gcseSubject, board: gcseBoard).createBody(invite: invite)
        }
        if game == .boggle {
            return BoggleSettings(difficulty: difficulty, size: boggleSize, seconds: boggleSeconds, scoring: boggleScoring)
                .createBody(invite: invite)
        }
        if game == .categories {
            return CategoriesSettings(difficulty: difficulty, count: categoriesCount, seconds: categoriesSeconds)
                .createBody(invite: invite)
        }
        if game == .liarsDice {
            return LiarsDiceSettings(difficulty: difficulty, dice: liarsDice).createBody(invite: invite)
        }
        if game == .drawGuess {
            return DrawGuessSettings(difficulty: difficulty, turnsEach: drawTurns, seconds: drawSeconds)
                .createBody(invite: invite)
        }
        if game == .marbleRace {
            return MarbleRaceSettings(difficulty: difficulty, course: marbleCourse).createBody(invite: invite)
        }
        if game == .mission {
            return MissionSettings(difficulty: difficulty).createBody(invite: invite)
        }
        if game == .fakeArtist {
            return FakeArtistSettings(difficulty: difficulty, rounds: fakeRounds).createBody(invite: invite)
        }
        if game == .manhunt {
            return ManhuntSettings(difficulty: difficulty, radius: manhuntRadius, minutes: manhuntMinutes)
                .createBody(invite: invite)
        }
        if game == .homestead {
            return HomesteadSettings(difficulty: difficulty, island: HomesteadSettings.island(at: homesteadIsland))
                .createBody(invite: invite)
        }
        if game == .hometowns {
            var create = CreateGameBody(game: game.rawValue, difficulty: GameDifficulty.easy.rawValue, invite: invite)
            var setup = county
            setup.name = setup.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if setup.name.count < 2 { setup.name = HometownsCountySetup().name }
            create.county = setup
            return create
        }
        return CreateGameBody(game: game.rawValue, difficulty: difficulty.rawValue, invite: invite)
    }

    /// The Players label with nobody invited yet: how many this game needs.
    private var sheetTrailing: String {
        switch game {
        case .chess: return "Pick one"
        case .mission: return "Invite 4+"
        case .oneClue: return "Three or more"
        case .fakeArtist: return "Invite 3+"
        case .passThePlate: return "Invite 1+"
        case .fireworks: return FireworksRules.sheetTrailing
        case .manhunt: return "Invite 2+"
        case .homestead: return "Invite 2+"
        case .hometowns: return "Solo or up to 6"
        default: return "Solo"
        }
    }

    /// The line when nobody else in the family has a phone paired yet.
    private var sheetNobody: String {
        switch game {
        case .chess:
            return "Nobody else in the family can play yet, and chess needs two. The lobby can wait for somebody to pair a phone."
        case .mission:
            return "Nobody else in the family can play yet, and Secret Mission needs at least four others. The lobby can wait for people to pair phones."
        case .oneClue:
            return "Nobody else in the family can play yet, and One Clue needs three. The lobby can wait for people to pair a phone."
        case .fakeArtist:
            return "Nobody else in the family can play yet, and Odd Artist Out needs at least three others. The lobby can wait for people to pair phones."
        case .passThePlate:
            return "Nobody else in the family can play yet, and Pass the Plate needs two to five. The lobby can wait for somebody to pair a phone."
        case .fireworks:
            return FireworksRules.sheetNobody
        case .manhunt:
            return "Nobody else in the family can play yet, and Manhunt needs a runner and two hunters. The lobby can wait for people to pair phones."
        case .homestead:
            return "Nobody else in the family can play yet, and Homestead needs three. The lobby can wait for people to pair phones."
        case .hometowns:
            return "Nobody else in the family can play yet, so this is a county of one — a real game. Invite people later from the lobby."
        default:
            return "Nobody else in the family can play yet, so this is a solo game."
        }
    }

    /// The line under the list of people to invite.
    private var sheetPick: String {
        switch game {
        case .chess:
            return "Chess is for two: pick the one person to play. The lobby waits for them to join; invites reach phones with the app open."
        case .mission:
            return "Secret Mission needs five to ten people in one room: invite at least four. The lobby waits for them to join."
        case .oneClue:
            return "One Clue is for three to seven: invite at least two. The lobby waits for them to join, and you can ask more in from there."
        case .fakeArtist:
            return "Odd Artist Out is for four to ten: invite at least three. The lobby waits for them to join, and you can ask more in from there."
        case .passThePlate:
            return "Pass the Plate is for two to five: invite at least one. The lobby waits for them to join, and you can ask more in from there."
        case .fireworks:
            return FireworksRules.sheetPick
        case .manhunt:
            return "Manhunt is for three to eight, outdoors: invite at least two. The lobby waits for them to join, and you can ask more in from there."
        case .homestead:
            return "Homestead is for three to five: invite at least two. Play in one sitting, or over days a turn at a time. The lobby waits for them to join."
        case .hometowns:
            return "A county is for one to six mayors, one town each. Only a parent can start it. The lobby waits for whoever you invite; you can start on your own."
        default:
            return "Nothing starts yet: the lobby waits for people to join, and you can ask more in from there. Invites reach phones with the app open."
        }
    }

    /// The play area and the clock — Manhunt's game. The circle is centred in
    /// the lobby, on where the host's phone is then.
    private var manhuntSettings: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Play area")
            segments(
                title: "Radius",
                options: ManhuntSettings.radii.map { (value: $0, label: ManhuntSettings.radiusLabel($0)) },
                selected: $manhuntRadius,
                id: "games-manhunt-radius"
            )
            segments(
                title: "Length",
                options: ManhuntSettings.lengths.map { (value: $0, label: "\($0) min") },
                selected: $manhuntMinutes,
                id: "games-manhunt-minutes"
            )
            Text(ManhuntSettings.line(radius: manhuntRadius, minutes: manhuntMinutes))
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("games-manhunt-line")
            Text("Only a parent can host. Positions are shared only during the game, only with the players, and are never kept.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("games-manhunt-privacy")
        }
    }

    /// The course — Marble Race's race. Today's course unless the host picks another.
    private var marbleRaceSettings: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Course")
            if let pack = marblePack {
                Picker("Course", selection: $marbleCourse) {
                    ForEach(pack.courses) { course in
                        Text(course.id == pack.today()?.id ? "\(course.name) · today" : course.name)
                            .tag(Optional(course))
                    }
                }
                .pickerStyle(.menu)
                .tint(SR.accent)
                .accessibilityIdentifier("games-marblerace-course")
                if let course = marbleCourse {
                    Text("\(course.layout.capitalized) · \(course.marbles) marbles · about \(max(1, Int((Double(course.seconds) / 60).rounded()))) min")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                }
            } else if let error = marblePackError {
                Text("Couldn't load Marbler's courses (\(error)); Start races the first one.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ProgressView().tint(SR.accent)
            }
            Text("Everyone backs a different marble, then the same race plays on every phone.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("games-marblerace-line")
        }
        .task {
            guard marblePack == nil else { return }
            do {
                let pack = try await MarblerPack.load()
                marblePack = pack
                marbleCourse = marbleCourse ?? pack.today()
            } catch {
                marblePackError = error.localizedDescription
            }
        }
    }

    /// Rounds — Odd Artist Out's game. It needs four, so the line says so.
    private var fakeArtistSettings: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Game")
            segments(
                title: "Rounds",
                options: FakeArtistSettings.roundChoices.map { (value: $0, label: FakeArtistSettings.roundsLabel($0)) },
                selected: $fakeRounds,
                id: "games-fakeartist-rounds"
            )
            Text("Four to ten players. A new fake every round; one line each, twice round, then everyone votes.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("games-fakeartist-line")
        }
    }

    /// Times round and the clock — Draw & Guess's game.
    private var drawGuessSettings: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Game")
            segments(
                title: "Turns",
                options: DrawGuessSettings.turns.map { (value: $0, label: DrawGuessSettings.turnsLabel($0)) },
                selected: $drawTurns,
                id: "games-drawguess-turns"
            )
            segments(
                title: "Time to draw",
                options: DrawGuessSettings.times.map { (value: $0, label: DrawGuessSettings.timeLabel($0)) },
                selected: $drawSeconds,
                id: "games-drawguess-time"
            )
            Text("Two to five players. Everyone draws in turn while the others guess.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("games-drawguess-line")
        }
    }

    /// Card size and clock — Categories' round.
    private var categoriesSettings: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Round")
            segments(
                title: "Categories",
                options: CategoriesSettings.counts.map { (value: $0, label: "\($0)") },
                selected: $categoriesCount,
                id: "games-categories-count"
            )
            segments(
                title: "Time",
                options: CategoriesSettings.times.map { (value: $0, label: BoggleSettings.timeLabel($0)) },
                selected: $categoriesSeconds,
                id: "games-categories-time"
            )
            Text(CategoriesSettings.line(count: categoriesCount, seconds: categoriesSeconds))
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("games-categories-line")
        }
    }

    /// Grid, clock and scoring — Boggle's round.
    private var boggleSettings: some View {
        VStack(alignment: .leading, spacing: SR.sectionGap) {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                SRSectionLabel(text: "Round")
                segments(
                    title: "Grid",
                    options: BoggleSettings.sizes.map { (value: $0, label: BoggleSettings.sizeLabel($0)) },
                    selected: $boggleSize,
                    id: "games-boggle-size"
                )
                segments(
                    title: "Time",
                    options: BoggleSettings.times.map { (value: $0, label: BoggleSettings.timeLabel($0)) },
                    selected: $boggleSeconds,
                    id: "games-boggle-time"
                )
                Text(BoggleSettings.line(size: boggleSize, seconds: boggleSeconds))
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("games-boggle-line")
            }

            VStack(alignment: .leading, spacing: SR.cardGap) {
                SRSectionLabel(text: "Scoring")
                ForEach(BoggleScoring.allCases) { rule in
                    choice(
                        title: rule.label,
                        line: rule.line,
                        selected: boggleScoring == rule,
                        id: "games-boggle-scoring-\(rule.rawValue)"
                    ) { boggleScoring = rule }
                }
            }
        }
    }

    /// Dice each — Liar's Dice's table. It needs two players, so it says so.
    private var liarsDiceSettings: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Table")
            segments(
                title: "Dice each",
                options: LiarsDiceSettings.diceCounts.map { (value: $0, label: "\($0)") },
                selected: $liarsDice,
                id: "games-liars-dice"
            )
            Text(LiarsDiceSettings.line(dice: liarsDice) + " Two to five players: invite at least one.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("games-liars-line")
        }
    }

    /// Homestead: which island, and that it needs three.
    private var homesteadSettings: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Island")
            segments(
                title: "Size",
                options: HomesteadSettings.islands.enumerated().map { (value: $0.offset, label: $0.element.label) },
                selected: $homesteadIsland,
                id: "games-homestead-island"
            )
            Text(HomesteadSettings.line(island: HomesteadSettings.island(at: homesteadIsland)))
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("games-homestead-line")
        }
    }

    /// The county — Hometowns' game: its name, how hard the towns compete for
    /// newcomers, when the Regional Day settles up, and whether mishaps happen.
    private var countySettings: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "County")
            TextField("County name", text: $county.name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .font(SR.Text.body())
                .padding(12)
                .srGlassCard(.paper, radius: SR.Glass.innerRadius)
                .onChange(of: county.name) { _, name in if name.count > 30 { county.name = String(name.prefix(30)) } }
                .accessibilityIdentifier("games-hometowns-name")
            Picker("Rivalry", selection: $county.rivalry) {
                Text("Friendly").tag("friendly")
                Text("Spirited").tag("spirited")
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("games-hometowns-rivalry")
            HStack {
                Text("REGIONAL DAY")
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.inkSecondary)
                Spacer(minLength: 8)
                Picker("Regional Day", selection: $county.regionalHour) {
                    ForEach(HometownsCountySetup.hours, id: \.self) { Text(HometownsCountySetup.hourLabel($0)).tag($0) }
                }
                .pickerStyle(.menu)
                .tint(SR.accentInk)
                .accessibilityIdentifier("games-hometowns-hour")
            }
            Toggle(isOn: Binding(get: { county.mishaps == "mild" }, set: { county.mishaps = $0 ? "mild" : "off" })) {
                Text("Mild mishaps (a burst pipe, a power cut)")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
            }
            .tint(SR.accent)
            .accessibilityIdentifier("games-hometowns-mishaps")
            Text(county.line)
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("games-hometowns-line")
        }
    }

    /// A labelled segmented picker, sized for a thumb.
    private func segments(title: String, options: [(value: Int, label: String)], selected: Binding<Int>,
                          id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(SR.Text.label())
                .tracking(SR.kickerTracking)
                .foregroundStyle(SR.inkSecondary)
            Picker(title, selection: selected) {
                ForEach(options.indices, id: \.self) { index in
                    Text(options[index].label).tag(options[index].value)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selected.wrappedValue) { _, _ in SRHaptic.select() }
            .accessibilityIdentifier(id)
        }
    }

    /// A Quiz Night set up as GCSE revision.
    private var gcse: Bool { game == .quizNight && quizMode == .gcse }

    /// Any topic for an audience, or GCSE revision — Quiz Night's own questions.
    private var quizSettings: some View {
        VStack(alignment: .leading, spacing: SR.sectionGap) {
            VStack(alignment: .leading, spacing: 6) {
                Picker("Kind of quiz", selection: $quizMode) {
                    ForEach(QuizMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: quizMode) { _, _ in
                    SRHaptic.select()
                    // "Dinosaurs" is not a Biology topic: each kind starts blank.
                    topic = ""
                    refusal = nil
                }
                .accessibilityIdentifier("games-quiz-mode")
                if gcse {
                    Text("Exam-style questions modelled on past papers, pitched at a grade band. The answers come with the working or the mark-scheme reason, and the end of the game lists what to revise.")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if gcse {
                gcseSettings
            } else {
                generalQuizSettings
            }
        }
    }

    /// Subject, exam board, and a topic inside the subject.
    private var gcseSettings: some View {
        VStack(alignment: .leading, spacing: SR.sectionGap) {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                SRSectionLabel(text: "Subject", trailing: gcseSubject == nil ? "Pick one" : nil)
                DaydreamWrap(spacing: 8) {
                    ForEach(GcseSubject.all) { subject in
                        chip(subject.label, selected: gcseSubject == subject, id: "games-gcse-subject-\(subject.id)") {
                            if gcseSubject != subject {
                                gcseSubject = subject
                                // A topic belongs to its subject.
                                topic = ""
                            }
                            refusal = nil
                        }
                    }
                }
            }

            segments(title: "Exam board",
                     options: GcseBoard.allCases.enumerated().map { (value: $0.offset, label: $0.element.label) },
                     selected: Binding(
                        get: { GcseBoard.allCases.firstIndex(of: gcseBoard) ?? 0 },
                        set: { gcseBoard = GcseBoard.allCases[$0] }
                     ),
                     id: "games-gcse-board")

            if let subject = gcseSubject {
                VStack(alignment: .leading, spacing: SR.cardGap) {
                    SRSectionLabel(text: "Topic", trailing: topic.isEmpty ? "Whole subject" : nil)
                    DaydreamWrap(spacing: 8) {
                        chip("Whole subject", selected: topic.isEmpty, id: "games-gcse-topic-all") { topic = "" }
                        ForEach(subject.topics, id: \.self) { heading in
                            chip(heading, selected: topic == heading, id: "games-gcse-topic-\(heading)") {
                                topic = topic == heading ? "" : heading
                            }
                        }
                    }
                    topicField(placeholder: "Or type one: e.g. osmosis, quadratics, Lady Macbeth")
                }
            }
        }
    }

    /// One tappable choice in a wrapping row.
    private func chip(_ title: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button {
            SRHaptic.select()
            action()
        } label: {
            Text(title)
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(selected ? SR.ink : SR.inkSecondary)
                .padding(.horizontal, 14)
                .frame(minHeight: SR.tapTarget)
                .srGlassCard(selected ? .paper : .clear, radius: SR.Glass.innerRadius + 4, interactive: true)
                .overlay {
                    RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous)
                        .strokeBorder(selected ? SR.accent : .clear, lineWidth: 1.5)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    /// The topic text field, capped at the server's limit.
    private func topicField(placeholder: String) -> some View {
        TextField(placeholder, text: $topic)
            .font(SR.Text.body(17))
            .foregroundStyle(SR.ink)
            .textInputAutocapitalization(.sentences)
            .autocorrectionDisabled(false)
            .submitLabel(.done)
            .padding(.horizontal, SR.cardPadding)
            .frame(minHeight: SR.tapTarget + 8)
            .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
            .onChange(of: topic) { _, typed in
                let capped = QuizNightSettings.limit(typed)
                if capped != typed { topic = capped }
                refusal = nil
            }
            .accessibilityLabel("Topic")
            .accessibilityHint("Optional. \(placeholder)")
            .accessibilityIdentifier("games-quiz-topic")
    }

    /// Topic and audience — a quiz on anything.
    private var generalQuizSettings: some View {
        VStack(alignment: .leading, spacing: SR.sectionGap) {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                SRSectionLabel(text: "Topic", trailing: "\(topic.count)/\(QuizNightSettings.topicLimit)")
                TextField("Leave blank and jkai picks", text: $topic)
                    .font(SR.Text.body(17))
                    .foregroundStyle(SR.ink)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
                    .submitLabel(.done)
                    .padding(.horizontal, SR.cardPadding)
                    .frame(minHeight: SR.tapTarget + 8)
                    .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
                    .onChange(of: topic) { _, typed in
                        let capped = QuizNightSettings.limit(typed)
                        if capped != typed { topic = capped }
                        refusal = nil
                    }
                    .accessibilityLabel("Topic")
                    .accessibilityHint("Optional. Leave blank and jkai picks.")
                    .accessibilityIdentifier("games-quiz-topic")
                Text("Anything: the solar system, 90s pop, dinosaurs. Leave it blank for a surprise.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: SR.cardGap) {
                SRSectionLabel(text: "Audience")
                ForEach(QuizAudience.allCases) { level in
                    choice(
                        title: level.label,
                        line: level.line,
                        selected: audience == level,
                        id: "games-audience-\(level.rawValue)"
                    ) { audience = level }
                }
            }
        }
    }

    private func choice(title: String, line: String?, selected: Bool, multi: Bool = false, id: String,
                        action: @escaping () -> Void) -> some View {
        Button {
            SRHaptic.select()
            action()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected
                      ? (multi ? "checkmark.square.fill" : "largecircle.fill.circle")
                      : (multi ? "square" : "circle"))
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(selected ? SR.accent : SR.inkGhost)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                    if let line {
                        Text(line)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, SR.rowPadding)
            .frame(maxWidth: .infinity, minHeight: SR.tapTarget, alignment: .leading)
            .srGlassCard(selected ? .paper : .clear, radius: SR.Glass.innerRadius + 4, interactive: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// The new-game sheet's picture: the game's tile, wide.
struct NewGameBanner: View {
    let game: GameKind

    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 120

    var body: some View {
        let hue = GameCategory.of(game.rawValue).hue
        let shape = RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
        HStack(spacing: 14) {
            Image(systemName: game.icon)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(hue.base)
                .frame(width: 60, height: 60)
                .background(Circle().fill(hue.onFill.opacity(0.94)))
                .shadow(color: Color.black.opacity(0.14), radius: 5, y: 2)
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
        .background { GamesTileBackdrop(game: game.rawValue, hue: hue, symbolSide: 120) }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
        .shadow(color: hue.base.opacity(0.26), radius: 12, y: 5)
        .accessibilityHidden(true)
    }
}

/// How the game is played, in the family's words, and who it is for — what
/// the shelf's tile had no room to say.
struct NewGameHowTo: View {
    let game: GameKind

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "book.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SR.accent)
                    .accessibilityHidden(true)
                Text("HOW TO PLAY")
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.inkSecondary)
                Spacer(minLength: 8)
                SRGlassChip(text: GamesPagePlan.playersChip(game.rawValue, onPhone: game.playsOnPhone),
                            icon: "person.2.fill", tone: SR.accentInk)
                    .accessibilityHidden(true)
            }
            Text(game.blurb)
                .font(SR.Text.body(16))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(GamesPagePlan.playersLine(game.rawValue, onPhone: game.playsOnPhone))
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("games-how-to-play")
    }
}
