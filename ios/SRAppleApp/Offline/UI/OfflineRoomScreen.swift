import SwiftUI
import UIKit

/// The room, over the whole screen: finding one to join, the lobby, the game
/// itself, the standings, getting back in after a drop, and the page that
/// says the room has closed. A solo game is a room too, with nobody else in it.
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
                    Button(session.isSolo ? "Stop" : session.isHost ? "Close the room" : "Leave", role: .destructive) { session.leave() }
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
        case .reconnecting(let name):
            OfflineReconnectingView(name: name) { session.leave() }
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
        case .idle, .ended: return "Play offline"
        case .browsing: return "Join a game"
        case .connecting: return "Joining"
        case .reconnecting: return "Reconnecting"
        case .room:
            switch session.lobby?.phase {
            case .playing?: return session.chosen?.info.title ?? "Playing"
            case .finished?: return "Results"
            default: return session.isSolo ? (session.chosen?.info.title ?? "Solo") : "Lobby"
            }
        }
    }

    private var leaveLabel: String {
        switch session.stage {
        case .browsing, .connecting, .reconnecting: return "Cancel"
        case .ended, .idle: return "Done"
        case .room:
            if session.isSolo { return session.lobby?.phase == .playing ? "Stop" : "Done" }
            return session.isHost ? "Close" : "Leave"
        }
    }

    /// Ask before ending something other people are in, or a game half played.
    private var needsConfirming: Bool {
        guard session.stage == .room, let lobby = session.lobby else { return false }
        if session.isSolo { return lobby.phase == .playing }
        if session.isHost { return lobby.players.contains { $0.id != lobby.hostId && !$0.isBot } }
        return lobby.phase == .playing
    }

    private var confirmTitle: String {
        if session.isSolo { return "Stop this game?" }
        return session.isHost ? "Close the room for everyone?" : "Leave this game?"
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
                             strap: "Looking over Bluetooth and Wi-Fi at once. The host's room appears here as soon as their phone is in reach.")

                VStack(alignment: .leading, spacing: SR.cardGap) {
                    SRSectionLabel(text: "Rooms nearby", trailing: session.found.isEmpty ? nil : "\(session.found.count)")
                    if session.found.isEmpty {
                        searching
                    } else {
                        ForEach(session.found) { host in
                            Button {
                                SRHaptic.tap()
                                typing = false
                                session.join(host)
                            } label: {
                                OfflineFoundRow(host: host)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("offline-room-\(host.name)")
                        }
                    }
                }

                addressCard
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .srGround(.warm)
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
                        Text("Nothing yet. Check the host has tapped Host a room and is keeping the app open, that Bluetooth and Wi-Fi are on for both of you, and that Local Network is allowed for SR Companion (Settings › Privacy & Security › Local Network). The search starts again by itself every few seconds.")
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// The last resort, folded away: a host on a hotspot or Wi-Fi shows its
    /// address in its lobby.
    private var addressCard: some View {
        SRCard {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    Text("If the room never appears, the host's lobby shows an address — on a hotspot, usually 172.20.10.1. Join their Wi-Fi or hotspot, then type it here.")
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
                .padding(.top, 10)
            } label: {
                Text("Type the host's address")
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.ink)
            }
            .tint(SR.accent)
        }
    }

    private func joinAddress() {
        guard OfflineAddress.parse(address) != nil else { return }
        typing = false
        SRHaptic.tap()
        session.join(address: address)
    }
}

/// One room in the list: its name, how it was found, and Join.
struct OfflineFoundRow: View {
    let host: OfflineFoundHost

    var body: some View {
        SRCard(interactive: true) {
            HStack(spacing: 12) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SR.paper)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(SR.accent))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(host.name)
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                        .lineLimit(2)
                    if !host.via.isEmpty {
                        Text(host.via.map(\.short).joined(separator: " · "))
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                            .accessibilityLabel("Found over \(host.via.map(\.short).joined(separator: " and "))")
                    }
                }
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

/// "Getting back into Sam's game…": the host dropped out of reach and this
/// phone is looking for the same room to take its seat again.
struct OfflineReconnectingView: View {
    let name: String
    let giveUp: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ProgressView().tint(SR.accent).controlSize(.large)
            Text("Getting back into \(name)'s game…")
                .font(SR.Text.title())
                .foregroundStyle(SR.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("The connection dropped — usually a locked phone or a few steps too far. Your seat is kept; this joins again by itself as soon as \(name)'s phone is back in reach.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Give up and leave", action: giveUp)
                .font(SR.Text.bodyMedium(15))
                .tint(SR.accent)
                .accessibilityIdentifier("offline-reconnect-give-up")
        }
        .padding(SR.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .srGround(.warm)
        .accessibilityIdentifier("offline-reconnecting")
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
                OfflineConnectionCard(session: session, lobby: lobby)
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

    private var players: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Who's here", trailing: "\(lobby.players.count) of \(OfflineRoom.capacity)")
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
                        chip(for: player)
                        if player.isBot, session.isHost {
                            Button {
                                SRHaptic.select()
                                session.removeBot(player.id)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(SR.inkGhost)
                                    .frame(width: SR.tapTarget, height: SR.tapTarget)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(player.name)")
                            .accessibilityIdentifier("offline-remove-\(player.id)")
                        }
                    }
                    .frame(minHeight: SR.tapTarget)
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .contain)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
            .accessibilityIdentifier("offline-players")
        }
    }

    /// Host, computer player, or — on the host's phone — how each guest's
    /// connection looks.
    @ViewBuilder
    private func chip(for player: OfflineLobbyPlayer) -> some View {
        if player.id == lobby.hostId {
            SRGlassChip(text: "Host", tone: SR.accent)
        } else if player.isBot {
            SRGlassChip(text: "Computer", icon: "cpu", tone: SR.inkSecondary)
        } else if !player.present {
            SRGlassChip(text: "Away", tone: SR.error)
        } else if session.isHost, let health = session.health[player.id], let label = health.label {
            SRGlassChip(text: label, icon: health.isTrouble ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                        tone: health.isTrouble ? SR.error : SR.good)
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
                if session.chosen?.entry.hasBot == true, session.addBotProblem == nil {
                    Button {
                        SRHaptic.tap()
                        session.addBot()
                    } label: {
                        SRButtonLabel(title: "Add a computer player", icon: "cpu", fill: true)
                    }
                    .srButton(.regular)
                    .controlSize(.large)
                    .accessibilityIdentifier("offline-add-bot")
                }
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
                    Text(item.entry.hasBot ? "\(item.info.playersLabel) · bots can join" : item.info.playersLabel)
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

/// How this room is connected, in plain words, and a way to test it: the
/// host sees how guests join and who it has heard from; a guest sees which
/// link carries it and can time a round trip.
struct OfflineConnectionCard: View {
    @ObservedObject var session: OfflineSession
    let lobby: OfflineLobby

    var body: some View {
        SRCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(headline, systemImage: symbol)
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.ink)
                Text(detail)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if session.isHost, !session.addresses.isEmpty {
                    ForEach(session.addresses, id: \.self) { address in
                        Text(address)
                            .font(SR.Text.figure(22))
                            .foregroundStyle(SR.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .textSelection(.enabled)
                            .accessibilityLabel("Address \(address)")
                            .accessibilityIdentifier("offline-address-\(address)")
                    }
                }
                HStack(spacing: 10) {
                    Button {
                        SRHaptic.tap()
                        session.testConnection()
                    } label: {
                        SRButtonLabel(title: session.testing ? "Testing…" : "Test connection", icon: "waveform.path.ecg")
                    }
                    .srButton(.regular)
                    .disabled(session.testing)
                    .accessibilityIdentifier("offline-test-connection")
                    if session.testing { ProgressView().tint(SR.accent) }
                }
                if let result = session.testResult {
                    Text(result)
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("offline-test-result")
                }
            }
        }
        .accessibilityIdentifier("offline-connection")
    }

    private var guests: [OfflineLobbyPlayer] {
        lobby.players.filter { $0.id != lobby.hostId && !$0.isBot }
    }

    private var headline: String {
        if session.isHost {
            switch guests.count {
            case 0: return "Open on \(session.transport.title)"
            case 1: return "1 phone connected"
            default: return "\(guests.count) phones connected"
            }
        }
        if let route = session.route { return "Connected over \(route.short)" }
        return "Connected to \(session.hostName)"
    }

    private var symbol: String {
        if session.isHost { return session.transport.symbol }
        return (session.route ?? .auto).symbol
    }

    private var detail: String {
        if session.isHost {
            let how = "Others open Play offline, tap Find a room and pick \(lobby.roomName). Keep this app open while you play."
            return session.addresses.isEmpty ? how : how + " If the room does not appear for them, they can join your Wi-Fi or hotspot and type:"
        }
        return "If the game feels slow or stalls, test the link. A dropped connection rejoins by itself."
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
                            // Alone there is no lobby to go back to: the shelf is the lobby.
                            if session.isSolo { session.leave() } else { session.backToLobby() }
                        } label: {
                            SRButtonLabel(title: session.isSolo ? "Done" : "Pick another game", fill: true)
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
                if standings.contains(where: { $0.playerId == session.playerId }) {
                    Label(syncLine, systemImage: "icloud.and.arrow.up")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("offline-result-saved")
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

    /// Where this result is going.
    private let syncLine = "Saved on this phone. It joins the family leaderboard next time you are online and paired."

    private var headline: String {
        if session.isSolo, standings.count == 1, let mine = standings.first {
            return "\(mine.score) points"
        }
        let winners = standings.filter { $0.rank == 1 }
        let names = winners.map { $0.playerId == session.playerId ? "You" : $0.name }
        switch names.count {
        case 0: return "Game over"
        case 1: return names[0] == "You" ? "You win" : "\(names[0]) wins"
        default: return names.dropLast().joined(separator: ", ") + " and \(names.last ?? "") tie"
        }
    }
}
