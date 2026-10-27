import SwiftUI

/// Navigation value for the Play nearby page, pushed from the Games page and
/// from More.
struct OfflineGamesRef: Hashable {}

/// Play offline: games for this phone alone or for phones in the same room,
/// with no internet at all.
///
/// Nothing here needs Strange Ramblings. Alone, the phone runs the game and
/// fills any empty seats with computer players. Together, one phone hosts —
/// it runs the game and is the "server" — and up to four more join it over
/// Bluetooth, phone-to-phone Wi-Fi or a shared Wi-Fi or hotspot, all at once,
/// so nobody has to agree which. So it is open to everyone with the app,
/// paired or not, with games access or not. Results wait on the phone and go
/// to the family leaderboard when there is internet again.
///
/// The page is the front door: your name, Play together (host or join), the
/// games you can play alone — the ones played most here first — and the
/// whole shelf. Once a room is open the room takes the whole screen as a
/// cover until somebody leaves.
struct OfflineGamesScreen: View {
    @ObservedObject private var session = OfflineSession.shared
    @ObservedObject private var results = OfflineResultStore.shared
    /// The game whose card was tapped: its how-to-play sheet.
    @State private var reading: OfflineCatalogueItem?
    /// A start chosen in the sheet, made once the sheet has gone — a cover
    /// cannot rise while a sheet is still leaving.
    @State private var pending: OfflinePendingStart?
    @State private var category: OfflineGameCategory?
    @FocusState private var naming: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(
                    kicker: "Play offline",
                    title: "Offline games",
                    strap: "No internet needed. Play alone against the phone, or with up to \(OfflineRoom.capacity - 1) more phones in the room. Results join the leaderboard when you are back online."
                )

                if let problem = session.problem, session.stage == .idle {
                    SRBanner(text: problem, tone: SR.error)
                        .onTapGesture { session.dismissProblem() }
                        .accessibilityIdentifier("offline-problem")
                }

                nameCard
                togetherCard
                if let line = results.statusLine { syncCard(line) }
                soloShelf
                catalogue
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("offline-games-screen")
        .srGround(.warm)
        .navigationTitle("Play offline")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $reading, onDismiss: startPending) { item in
            OfflineHowToSheet(item: item) { start in
                pending = start
                reading = nil
            }
        }
        .fullScreenCover(isPresented: roomShown) {
            OfflineRoomScreen()
        }
    }

    /// The room covers the screen whenever there is one; it closes only by
    /// leaving.
    private var roomShown: Binding<Bool> {
        Binding(
            get: { session.inRoom },
            set: { shown in if !shown && session.inRoom { session.leave() } }
        )
    }

    private func startPending() {
        guard let start = pending else { return }
        pending = nil
        start.run(session)
    }

    // MARK: - Your name

    private var nameCard: some View {
        SRCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("YOUR NAME")
                    .font(SR.Text.label())
                    .tracking(1.2)
                    .foregroundStyle(SR.inkMuted)
                TextField("Your name", text: $session.nickname)
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($naming)
                    .onSubmit { naming = false }
                    .accessibilityIdentifier("offline-nickname")
            }
        }
    }

    // MARK: - Play together

    private var togetherCard: some View {
        SRCard(accented: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: OfflineTransport.auto.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(SR.paper)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(SR.accent))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Play together")
                            .font(SR.Text.display(20))
                            .foregroundStyle(SR.ink)
                        Text("One phone hosts, the others join. Bluetooth or Wi-Fi — whichever is on.")
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { hostButton; joinButton }
                    VStack(spacing: 10) { hostButton; joinButton }
                }
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Self.tips, id: \.self) { tip in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(SR.accent)
                                    .accessibilityHidden(true)
                                Text(tip)
                                    .font(SR.Text.secondary(13))
                                    .foregroundStyle(SR.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("If phones cannot find each other")
                        .font(SR.Text.bodyMedium(14))
                        .foregroundStyle(SR.ink)
                }
                .tint(SR.accent)
                .accessibilityIdentifier("offline-tips")
            }
        }
    }

    private static let tips = [
        "Everyone needs the same version of the app — update together.",
        "Allow Local Network for SR Companion: Settings › Privacy & Security › Local Network.",
        "Turn Bluetooth and Wi-Fi on (Wi-Fi does not need to be joined to anything).",
        "Stay within a few metres, and keep the app open on the host's phone.",
        "Use Test connection in the room to check the link before a fast game.",
    ]

    private var hostButton: some View {
        Button {
            SRHaptic.tap()
            naming = false
            session.host()
        } label: {
            SRButtonLabel(title: "Host a room", icon: "person.3.fill", fill: true)
        }
        .srButton(.prominent)
        .controlSize(.large)
        .accessibilityIdentifier("offline-host")
    }

    private var joinButton: some View {
        Button {
            SRHaptic.tap()
            naming = false
            session.browse()
        } label: {
            SRButtonLabel(title: "Find a room", icon: "magnifyingglass", fill: true)
        }
        .srButton(.regular)
        .controlSize(.large)
        .accessibilityIdentifier("offline-join")
    }

    // MARK: - Sync later

    private func syncCard(_ line: String) -> some View {
        SRCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: results.state == .syncing ? "arrow.triangle.2.circlepath" : "icloud.and.arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SR.accent)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(line)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if results.state != .syncing {
                        Button("Sync now") {
                            SRHaptic.tap()
                            results.syncSoon(force: true)
                        }
                        .font(SR.Text.bodyMedium(14))
                        .tint(SR.accent)
                        .accessibilityIdentifier("offline-sync-now")
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityIdentifier("offline-sync")
    }

    // MARK: - Play alone

    /// Every game that can be played alone, the ones played most here first.
    private var soloItems: [OfflineCatalogueItem] {
        let solo = OfflineCatalogue.soloGames
        let order = results.mostPlayed(limit: solo.count)
        return solo.enumerated().sorted { a, b in
            let x = order.firstIndex(of: a.element.id) ?? Int.max
            let y = order.firstIndex(of: b.element.id) ?? Int.max
            return x == y ? a.offset < b.offset : x < y
        }.map(\.element)
    }

    private var soloShelf: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Play alone", trailing: "\(soloItems.count)")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(soloItems) { item in
                    Button {
                        SRHaptic.tap()
                        naming = false
                        session.playSolo(item.id)
                    } label: {
                        OfflineSoloTile(item: item, tally: results.queue.tallies[item.id])
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("offline-solo-\(item.id)")
                }
            }
        }
    }

    // MARK: - Every game

    private var catalogue: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Every game", trailing: "\(OfflineCatalogue.items.count)")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(nil, title: "All")
                    ForEach(OfflineGameCategory.allCases) { option in
                        filterChip(option, title: option.title)
                    }
                }
            }
            .accessibilityIdentifier("offline-filter")
            ForEach(OfflineGameCategory.allCases.filter { category == nil || category == $0 }) { section in
                let items = OfflineCatalogue.games(in: section)
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: SR.cardGap) {
                        SRSectionLabel(text: section.title, trailing: "\(items.count)")
                        ForEach(items) { item in
                            Button {
                                SRHaptic.tap()
                                reading = item
                            } label: {
                                OfflineGameCard(item: item)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("offline-game-\(item.id)")
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func filterChip(_ option: OfflineGameCategory?, title: String) -> some View {
        let on = category == option
        return Button {
            SRHaptic.select()
            category = option
        } label: {
            Text(title)
                .font(SR.Text.bodyMedium(14))
                .foregroundStyle(on ? SR.paper : SR.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(Capsule().fill(on ? SR.accent : SR.surface))
                .overlay(Capsule().stroke(on ? Color.clear : SR.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A start chosen in the how-to sheet, waiting for the sheet to go.
enum OfflinePendingStart: Equatable {
    case solo(String)
    case host(String)

    @MainActor
    func run(_ session: OfflineSession) {
        switch self {
        case .solo(let game): session.playSolo(game)
        case .host(let game): session.host(game: game)
        }
    }
}

/// A game on the Play alone shelf: its mark, its name, who it is against,
/// and this phone's best.
struct OfflineSoloTile: View {
    let item: OfflineCatalogueItem
    let tally: OfflineTally?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: item.info.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(SR.paper)
                .frame(width: 38, height: 38)
                .background(Circle().fill(OfflineGameCard.fill(item.info.category)))
                .accessibilityHidden(true)
            Text(item.info.title)
                .font(SR.Text.title(16))
                .foregroundStyle(SR.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
            Text(opponent)
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
            if let tally, tally.played > 0 {
                Text(tally.played == 1 ? "Played once" : "Played \(tally.played)×")
                    .font(SR.Text.label())
                    .tracking(1.0)
                    .foregroundStyle(SR.accent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius, interactive: true)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Starts a game on this phone")
        .accessibilityAddTraits(.isButton)
    }

    private var opponent: String {
        switch item.soloBots {
        case 0: return "Just you"
        case 1: return "You v the phone"
        default: return "You v \(item.soloBots) bots"
        }
    }
}

/// One game's card on the shelf: its mark, name, one line, and how it can be
/// played — alone, nearby, how many.
struct OfflineGameCard: View {
    let item: OfflineCatalogueItem

    private var info: OfflineGameInfo { item.info }

    var body: some View {
        SRCard(interactive: true) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: info.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(SR.paper)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(OfflineGameCard.fill(info.category)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.title)
                        .font(SR.Text.display(20))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(info.blurb)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(modes.uppercased())
                        .font(SR.Text.label())
                        .tracking(1.2)
                        .foregroundStyle(SR.accent)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// "Solo · nearby · 2–5 players".
    private var modes: String {
        var parts: [String] = []
        if item.canPlaySolo { parts.append(item.soloBots > 0 ? "Solo v bots" : "Solo") }
        parts.append("Nearby")
        parts.append(info.playersLabel)
        return parts.joined(separator: " · ")
    }

    static func fill(_ category: OfflineGameCategory) -> Color {
        switch category {
        case .card: return SR.accentInk
        case .reaction: return SR.accent
        case .skill: return SR.good
        }
    }
}

/// A game's rules before anyone commits, and the ways to play it.
struct OfflineHowToSheet: View {
    let item: OfflineCatalogueItem
    let start: (OfflinePendingStart) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SR.sectionGap) {
                    SRPageHeader(kicker: "\(item.info.category.title) · \(item.info.playersLabel)",
                                 title: item.info.title, strap: item.info.blurb)
                    OfflineHowToCard(info: item.info)
                    OfflinePlayButtons(item: item, start: start)
                }
                .padding(.horizontal, SR.gutter)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .srGround(.warm)
            .navigationTitle(item.info.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

/// Play alone (when the game allows it) and Host nearby.
struct OfflinePlayButtons: View {
    let item: OfflineCatalogueItem
    let start: (OfflinePendingStart) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if item.canPlaySolo {
                Button {
                    SRHaptic.tap()
                    start(.solo(item.id))
                } label: {
                    SRButtonLabel(title: item.soloBots > 0 ? "Play against the phone" : "Play alone", icon: "person.fill", fill: true)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .accessibilityIdentifier("offline-howto-solo")
            }
            Button {
                SRHaptic.tap()
                start(.host(item.id))
            } label: {
                SRButtonLabel(title: "Host nearby", icon: OfflineTransport.auto.symbol, fill: true)
            }
            .srButton(item.canPlaySolo ? .regular : .prominent)
            .controlSize(.large)
            .accessibilityIdentifier("offline-howto-host-nearby")
            Text(item.canPlaySolo
                 ? "Alone, the phone plays the other seats. Nearby, others join from Find a room."
                 : "Others join from Find a room on their phones.")
                .font(SR.Text.secondary(13))
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The numbered rules of a game, in a card.
struct OfflineHowToCard: View {
    let info: OfflineGameInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "How to play")
            ForEach(Array(info.howToPlay.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)")
                        .font(SR.Text.label(13))
                        .foregroundStyle(SR.accent)
                        .frame(width: 18, alignment: .leading)
                    Text(line)
                        .font(SR.Text.body(15))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
    }
}
