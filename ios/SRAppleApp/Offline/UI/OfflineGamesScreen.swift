import SwiftUI

/// Navigation value for the Play nearby page, pushed from the Games page and
/// from More.
struct OfflineGamesRef: Hashable {}

/// Play nearby: games for phones in the same room, with no internet at all.
///
/// Nothing here talks to Strange Ramblings. One phone hosts — it runs the
/// game and is the "server" — and up to four more join it over Bluetooth
/// (MultipeerConnectivity) or the host's Wi-Fi or Personal Hotspot. So it is
/// open to everyone with the app, paired or not, with games access or not.
///
/// The page is the front door: your name, Host, Join, and the shelf of games.
/// Once a room is open (hosting, or looking for one to join) the room takes
/// the whole screen as a cover until somebody leaves.
struct OfflineGamesScreen: View {
    @ObservedObject private var session = OfflineSession.shared
    /// The game whose card was tapped: its how-to-play sheet.
    @State private var reading: OfflineCatalogueItem?
    /// "Host this game" from the sheet, started once the sheet has gone —
    /// a cover cannot rise while a sheet is still leaving.
    @State private var pendingHost: OfflinePendingHost?
    @FocusState private var naming: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(
                    kicker: "Play nearby",
                    title: "Offline games",
                    strap: "No internet needed. One phone hosts and runs the game; up to \(OfflineRoom.capacity) play, over Bluetooth or the host's Wi-Fi or hotspot."
                )

                nameCard
                hostCard
                joinCard

                ForEach(OfflineGameCategory.allCases) { category in
                    let items = OfflineCatalogue.games(in: category)
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: SR.cardGap) {
                            SRSectionLabel(text: category.title, trailing: "\(items.count)")
                            ForEach(items) { item in
                                Button {
                                    SRHaptic.tap()
                                    reading = item
                                } label: {
                                    OfflineGameCard(info: item.info)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("offline-game-\(item.id)")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("offline-games-screen")
        .srGround(.warm)
        .navigationTitle("Play nearby")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $reading, onDismiss: startPendingHost) { item in
            OfflineHowToSheet(item: item) { transport in
                pendingHost = OfflinePendingHost(transport: transport, game: item.id)
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

    private func startPendingHost() {
        guard let pending = pendingHost else { return }
        pendingHost = nil
        session.host(via: pending.transport, game: pending.game)
    }

    // MARK: - Cards

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

    private var hostCard: some View {
        SRCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Host a game")
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                    Text("Your phone runs the game and the others join it. Keep the app open while you play.")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(OfflineTransport.allCases) { transport in
                    Button {
                        SRHaptic.tap()
                        naming = false
                        session.host(via: transport)
                    } label: {
                        OfflineTransportRow(transport: transport)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("offline-host-\(transport.rawValue)")
                }
            }
        }
    }

    private var joinCard: some View {
        SRCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Join a game")
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                    Text("Find a room somebody nearby has opened.")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    SRHaptic.tap()
                    naming = false
                    session.browse(via: .nearby)
                } label: {
                    SRButtonLabel(title: "Find a room", icon: "magnifyingglass", fill: true)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .accessibilityIdentifier("offline-join")
            }
        }
    }
}

/// "Host this game" from the how-to-play sheet, waiting for the sheet to go.
struct OfflinePendingHost: Equatable {
    let transport: OfflineTransport
    let game: String
}

/// One way to connect, as a tappable row: icon, name, one sentence.
struct OfflineTransportRow: View {
    let transport: OfflineTransport

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transport.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SR.paper)
                .frame(width: 40, height: 40)
                .background(Circle().fill(transport == .nearby ? SR.accent : SR.accentInk))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(transport.title)
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.ink)
                Text(transport.detail)
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SR.inkGhost)
                .accessibilityHidden(true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius, interactive: true)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// One game's card on the shelf: its mark, name, one line, how many play.
struct OfflineGameCard: View {
    let info: OfflineGameInfo

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
                    Text(info.playersLabel.uppercased())
                        .font(SR.Text.label())
                        .tracking(1.2)
                        .foregroundStyle(SR.accent)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    static func fill(_ category: OfflineGameCategory) -> Color {
        switch category {
        case .card: return SR.accentInk
        case .reaction: return SR.accent
        case .skill: return SR.good
        }
    }
}

/// A game's rules before anyone commits, and the way to host it.
struct OfflineHowToSheet: View {
    let item: OfflineCatalogueItem
    let host: (OfflineTransport) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SR.sectionGap) {
                    SRPageHeader(kicker: "\(item.info.category.title) · \(item.info.playersLabel)",
                                 title: item.info.title, strap: item.info.blurb)
                    OfflineHowToCard(info: item.info)
                    VStack(spacing: 10) {
                        Button {
                            SRHaptic.tap()
                            host(.nearby)
                        } label: {
                            SRButtonLabel(title: "Host nearby", icon: OfflineTransport.nearby.symbol, fill: true)
                        }
                        .srButton(.prominent)
                        .controlSize(.large)
                        .accessibilityIdentifier("offline-howto-host-nearby")
                        Button {
                            SRHaptic.tap()
                            host(.hotspot)
                        } label: {
                            SRButtonLabel(title: "Host on Wi-Fi", icon: OfflineTransport.hotspot.symbol, fill: true)
                        }
                        .srButton(.regular)
                        .controlSize(.large)
                        .accessibilityIdentifier("offline-howto-host-hotspot")
                    }
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
