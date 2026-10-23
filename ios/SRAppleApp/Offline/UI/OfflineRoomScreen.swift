import SwiftUI
import UIKit

/// The room, over the whole screen: finding one to join, the lobby, the game
/// itself, the standings, and the page that says the room has closed.
///
/// A cover rather than a pushed page: no tab bar to tap by mistake mid-game,
/// and it stays put while the room lives. The one way out is the button at
/// the top left — Cancel, Leave, or (for the host) Close, which ends the room
/// for everyone, so it asks first.
struct OfflineRoomScreen: View {
    @ObservedObject private var session = OfflineSession.shared
    @State private var confirmingLeave = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(leaveLabel) {
                            if needsConfirming { confirmingLeave = true } else { session.leave() }
                        }
                        .accessibilityIdentifier("offline-leave")
                    }
                }
                .confirmationDialog(confirmTitle, isPresented: $confirmingLeave, titleVisibility: .visible) {
                    Button(session.isHost ? "Close the room" : "Leave", role: .destructive) { session.leave() }
                    Button("Stay", role: .cancel) {}
                }
        }
        .overlay(alignment: .bottom) {
            if let text = session.refusal ?? session.problem {
                SRBanner(text: text, tone: SR.error)
                    .onTapGesture { session.dismissProblem() }
                    .accessibilityIdentifier("offline-banner")
            }
        }
        .animation(SRMotion.settle, value: session.refusal ?? session.problem)
        // A phone that dims and locks mid-game drops out of the room.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .accessibilityIdentifier("offline-room")
    }

    @ViewBuilder
    private var content: some View {
        switch session.stage {
        case .idle:
            Color.clear
        case .browsing:
            OfflineJoinView(session: session)
        case .connecting(let name):
            OfflineConnectingView(name: name) { session.cancelJoin() }
        case .room:
            if let lobby = session.lobby {
                switch lobby.phase {
                case .lobby: OfflineLobbyView(session: session, lobby: lobby)
                case .playing: OfflinePlayingView(session: session, lobby: lobby)
                case .finished: OfflineFinishedView(session: session, lobby: lobby)
                }
            } else {
                OfflineConnectingView(name: nil, cancel: nil)
            }
        case .ended(let reason):
            SREmpty(title: "The room has closed", icon: "wifi.slash", message: reason,
                    actionLabel: "Done", action: { session.leave() })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .srPaper()
        }
    }

    private var title: String {
        switch session.stage {
        case .idle, .ended: return "Play nearby"
        case .browsing: return "Join a game"
        case .connecting: return "Joining"
        case .room:
            switch session.lobby?.phase {
            case .playing?: return session.chosen?.info.title ?? "Playing"
            case .finished?: return "Results"
            default: return "Lobby"
            }
        }
    }

    private var leaveLabel: String {
        switch session.stage {
        case .browsing, .connecting: return "Cancel"
        case .ended, .idle: return "Done"
        case .room: return session.isHost ? "Close" : "Leave"
        }
    }

    /// Ask before ending something other people are in.
    private var needsConfirming: Bool {
        guard session.stage == .room, let lobby = session.lobby else { return false }
        if session.isHost { return lobby.players.count > 1 }
        return lobby.phase == .playing
    }

    private var confirmTitle: String {
        session.isHost ? "Close the room for everyone?" : "Leave this game?"
    }
}

// MARK: - Finding a room

struct OfflineJoinView: View {
    @ObservedObject var session: OfflineSession
    @State private var address = ""
    @FocusState private var typing: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Join a game", title: "Find a room",
                             strap: "The host opens a room first; pick the same kind of connection they chose.")

                VStack(alignment: .leading, spacing: 10) {
                    Picker("Connection", selection: transport) {
                        ForEach(OfflineTransport.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("offline-join-transport")
                    Text(session.transport.detail)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: SR.cardGap) {
                    SRSectionLabel(text: "Rooms", trailing: session.found.isEmpty ? nil : "\(session.found.count)")
                    if session.found.isEmpty {
                        searching
                    } else {
                        ForEach(session.found) { host in
                            Button {
                                SRHaptic.tap()
                                typing = false
                                session.join(host)
                            } label: {
                                SRCard(interactive: true) {
                                    HStack(spacing: 12) {
                                        Image(systemName: session.transport.symbol)
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(SR.accent)
                                            .frame(width: 28)
                                            .accessibilityHidden(true)
                                        Text(host.name)
                                            .font(SR.Text.title())
                                            .foregroundStyle(SR.ink)
                                            .lineLimit(2)
                                        Spacer(minLength: 8)
                                        Text("JOIN")
                                            .font(SR.Text.label())
                                            .tracking(1.2)
                                            .foregroundStyle(SR.accent)
                                    }
                                    .frame(minHeight: SR.tapTarget)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(.isButton)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("offline-room-\(host.name)")
                        }
                    }
                }

                if session.transport == .hotspot {
                    addressCard
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .srGround(.warm)
    }

    private var transport: Binding<OfflineTransport> {
        Binding(get: { session.transport }, set: { next in
            if next != session.transport { session.browse(via: next) }
        })
    }

    /// Looking, and — after a few quiet seconds — what usually explains a
    /// list that stays empty.
    private var searching: some View {
        SRCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ProgressView().tint(SR.accent)
                    Text("Looking for rooms…")
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(SR.ink)
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let since = session.browsingSince, context.date.timeIntervalSince(since) > 8 {
                        Text(quietHint)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var quietHint: String {
        switch session.transport {
        case .nearby:
            return "Nothing yet. Check the host chose Nearby, that Bluetooth is on for both of you, and that Local Network is allowed for SR Companion (Settings › Privacy & Security › Local Network)."
        case .hotspot:
            return "Nothing yet. Check you are on the host's Wi-Fi or Personal Hotspot, and that Local Network is allowed for SR Companion (Settings › Privacy & Security › Local Network). Or type the address on the host's screen below."
        }
    }

    private var addressCard: some View {
        SRCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Or type the host's address")
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.ink)
                Text("It is on the host's lobby — on a hotspot, usually 172.20.10.1.")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("172.20.10.1", text: $address)
                    .font(SR.Text.title())
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.join)
                    .focused($typing)
                    .onSubmit(joinAddress)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .srGlassCard(.paper, radius: SR.Glass.innerRadius)
                    .accessibilityIdentifier("offline-address")
                Button(action: joinAddress) {
                    SRButtonLabel(title: "Join", icon: "arrow.right", fill: true)
                }
                .srButton(.regular)
                .controlSize(.large)
                .disabled(OfflineAddress.parse(address) == nil)
                .accessibilityIdentifier("offline-address-join")
            }
        }
    }

    private func joinAddress() {
        guard OfflineAddress.parse(address) != nil else { return }
        typing = false
        SRHaptic.tap()
        session.join(address: address)
    }
}

/// "Joining Sam's game…", with a way back.
struct OfflineConnectingView: View {
    let name: String?
    let cancel: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            ProgressView().tint(SR.accent).controlSize(.large)
            Text(name.map { "Joining \($0)…" } ?? "Waiting for the host…")
                .font(SR.Text.title())
                .foregroundStyle(SR.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let cancel {
                Button("Back to the list", action: cancel)
                    .font(SR.Text.bodyMedium(15))
                    .tint(SR.accent)
            }
        }
        .padding(SR.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .srGround(.warm)
    }
}

// MARK: - The lobby

struct OfflineLobbyView: View {
    @ObservedObject var session: OfflineSession
    let lobby: OfflineLobby

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: session.isHost ? "You are hosting" : "Hosted by \(session.hostName)",
                             title: lobby.roomName)
                if session.isHost { connectionCard }
                players
                if session.isHost {
                    startCard
                    picker
                } else {
                    waiting
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("offline-lobby")
    }

    // How others get in.
    private var connectionCard: some View {
        SRCard {
            VStack(alignment: .leading, spacing: 8) {
                Label(session.transport.title, systemImage: session.transport.symbol)
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.ink)
                switch session.transport {
                case .nearby:
                    Text("Others tap Find a room under Play nearby, choose Nearby and pick \(lobby.roomName). Stay within a few metres.")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                case .hotspot:
                    Text("Others join the same Wi-Fi — or your Personal Hotspot in their Wi-Fi settings — then choose Wi-Fi or hotspot. If the room does not appear, they can type:")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    if session.addresses.isEmpty {
                        Text("Waiting for a network…")
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                    } else {
                        ForEach(session.addresses, id: \.self) { address in
                            Text(address)
                                .font(SR.Text.figure(24))
                                .foregroundStyle(SR.accent)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .textSelection(.enabled)
                                .accessibilityIdentifier("offline-address-\(address)")
                        }
                    }
                }
            }
        }
    }

    private var players: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Players", trailing: "\(lobby.players.count) of \(OfflineRoom.capacity)")
            VStack(spacing: 0) {
                ForEach(Array(lobby.players.enumerated()), id: \.element.id) { index, player in
                    if index > 0 { Divider().overlay(SR.divider) }
                    HStack(spacing: 12) {
                        OfflineInitial(name: player.name, size: 32, tone: OfflineSeatColour.of(index))
                        Text(player.name + (player.id == session.playerId ? " (you)" : ""))
                            .font(SR.Text.title())
                            .foregroundStyle(player.present ? SR.ink : SR.inkMuted)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if player.id == lobby.hostId {
                            SRGlassChip(text: "Host", tone: SR.accent)
                        } else if !player.present {
                            SRGlassChip(text: "Away", tone: SR.error)
                        }
                    }
                    .frame(minHeight: SR.tapTarget)
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
            .accessibilityIdentifier("offline-players")
        }
    }

    /// The chosen game and Start — above the list, so Start is never a
    /// scroll away.
    private var startCard: some View {
        SRCard(accented: session.startProblem == nil) {
            VStack(alignment: .leading, spacing: 12) {
                if let chosen = session.chosen {
                    HStack(spacing: 12) {
                        Image(systemName: chosen.info.symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(SR.paper)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(OfflineGameCard.fill(chosen.info.category)))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chosen.info.title)
                                .font(SR.Text.display(20))
                                .foregroundStyle(SR.ink)
                            Text(chosen.info.playersLabel)
                                .font(SR.Text.mono())
                                .foregroundStyle(SR.inkMuted)
                        }
                    }
                } else {
                    Text("Pick a game below.")
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                }
                Button {
                    SRHaptic.ok()
                    session.start()
                } label: {
                    SRButtonLabel(title: "Start", icon: "play.fill", fill: true)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .disabled(session.startProblem != nil)
                .accessibilityIdentifier("offline-start")
                if let problem = session.startProblem, session.chosen != nil {
                    Text(problem)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Every game, by shelf; the ones that cannot seat this many are dimmed.
    private var picker: some View {
        VStack(alignment: .leading, spacing: SR.sectionGap) {
            ForEach(OfflineGameCategory.allCases) { category in
                let items = OfflineCatalogue.games(in: category)
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: SR.cardGap) {
                        SRSectionLabel(text: category.title)
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                if index > 0 { Divider().overlay(SR.divider) }
                                pickerRow(item)
                            }
                        }
                        .padding(.horizontal, SR.cardPadding)
                        .padding(.vertical, 4)
                        .srGlassCard(.paper)
                    }
                }
            }
        }
    }

    private func pickerRow(_ item: OfflineCatalogueItem) -> some View {
        let fits = item.info.allows(lobby.players.filter(\.present).count)
        let chosen = lobby.gameId == item.id
        return Button {
            SRHaptic.select()
            session.choose(item.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.info.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SR.accent)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.info.title)
                        .font(SR.Text.title(16))
                        .foregroundStyle(SR.ink)
                        .lineLimit(1)
                    Text(item.info.playersLabel)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                }
                Spacer(minLength: 8)
                if chosen {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(SR.accent)
                        .accessibilityLabel("Chosen")
                }
            }
            .opacity(fits || chosen ? 1 : 0.5)
            .frame(minHeight: SR.tapTarget)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("offline-pick-\(item.id)")
    }

    private var waiting: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            if let chosen = session.chosen {
                SRSectionLabel(text: "Next up")
                SRCard(accented: true) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(chosen.info.title)
                            .font(SR.Text.display(20))
                            .foregroundStyle(SR.ink)
                        Text(chosen.info.blurb)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                OfflineHowToCard(info: chosen.info)
            }
            Text("Waiting for \(session.hostName) to \(session.chosen == nil ? "pick a game" : "start").")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("offline-waiting")
        }
    }
}

// MARK: - Playing

/// The running game's own view, built by its catalogue item from my view packet.
struct OfflinePlayingView: View {
    @ObservedObject var session: OfflineSession
    let lobby: OfflineLobby

    var body: some View {
        if let packet = session.packet, packet.match == lobby.match {
            if let item = OfflineCatalogue.item(packet.gameId), let screen = item.screen(input(packet)) {
                screen
                    .id("\(packet.gameId)-\(packet.match)")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SREmpty(title: "This game needs a newer app", icon: "arrow.down.app",
                        message: "\(session.hostName)'s phone is running a game this version does not know. Update the app, then join again.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .srPaper()
            }
        } else {
            OfflineConnectingView(name: nil, cancel: nil)
        }
    }

    private func input(_ packet: OfflineViewPacket) -> OfflineScreenInput {
        let session = self.session
        return OfflineScreenInput(
            data: packet.data,
            me: session.playerId,
            players: lobby.roster,
            isHost: session.isHost,
            clock: session.clock,
            refusal: session.refusal,
            send: { data in session.send(action: data) }
        )
    }
}

// MARK: - After a match

struct OfflineFinishedView: View {
    @ObservedObject var session: OfflineSession
    let lobby: OfflineLobby

    private var standings: [OfflineStanding] { lobby.standings ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "\(session.chosen?.info.title ?? "Game") · final", title: headline)
                if !standings.isEmpty {
                    OfflineStandingsCard(standings: standings, me: session.playerId)
                        .accessibilityIdentifier("offline-standings")
                }
                if session.isHost {
                    VStack(spacing: 10) {
                        Button {
                            SRHaptic.tap()
                            session.playAgain()
                        } label: {
                            SRButtonLabel(title: "Play again", icon: "arrow.counterclockwise", fill: true)
                        }
                        .srButton(.prominent)
                        .controlSize(.large)
                        .accessibilityIdentifier("offline-again")
                        Button {
                            SRHaptic.tap()
                            session.backToLobby()
                        } label: {
                            SRButtonLabel(title: "Pick another game", fill: true)
                        }
                        .srButton(.regular)
                        .controlSize(.large)
                        .accessibilityIdentifier("offline-pick-another")
                    }
                } else {
                    Text("Waiting for \(session.hostName) to play again or pick another game.")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .onAppear {
            if standings.first(where: { $0.playerId == session.playerId })?.rank == 1 { SRHaptic.ok() }
        }
    }

    private var headline: String {
        let winners = standings.filter { $0.rank == 1 }
        let names = winners.map { $0.playerId == session.playerId ? "You" : $0.name }
        switch names.count {
        case 0: return "Game over"
        case 1: return names[0] == "You" ? "You win" : "\(names[0]) wins"
        default: return names.dropLast().joined(separator: ", ") + " and \(names.last ?? "") tie"
        }
    }
}
