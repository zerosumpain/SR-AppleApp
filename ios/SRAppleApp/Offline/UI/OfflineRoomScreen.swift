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
///
/// Every waiting state says what it is waiting for and shows it moving
/// (a radar while looking, the link while joining), using the system's
/// symbol animations, which cost nothing once the state is over.
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
        // A refused move is felt as well as read.
        .onChange(of: session.refusal) { _, refusal in
            if refusal != nil { SRHaptic.bad() }
        }
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

// MARK: - Waiting art

/// Rings round a beacon: looking for rooms. The beacon's waves run only
/// while `active` (and never under Reduce Motion).
struct OfflineRadar: View {
    let active: Bool
    var size: CGFloat = 150
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { ring in
                Circle()
                    .stroke(SR.accent.opacity(0.28 - Double(ring) * 0.07), lineWidth: 2)
                    .frame(width: size * (0.45 + 0.27 * CGFloat(ring)), height: size * (0.45 + 0.27 * CGFloat(ring)))
            }
            Circle()
                .fill(LinearGradient(colors: [SR.accent, SR.accentDeep], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.38, height: size * 0.38)
                .shadow(color: SR.accent.opacity(0.35), radius: 10, x: 0, y: 4)
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: size * 0.15, weight: .semibold))
                .foregroundStyle(Color.white)
                .symbolEffect(.variableColor.iterative.reversing, options: .repeating, isActive: active && !reduceMotion)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Two phones and the air between them: joining, or getting back in.
struct OfflineLinkArt: View {
    /// The link has dropped: the waves turn to the warning colour.
    var trouble = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tone = trouble ? SR.warn : SR.accent
        HStack(spacing: 16) {
            phone(tone: SR.inkSecondary)
            Image(systemName: trouble ? "wifi.exclamationmark" : "antenna.radiowaves.left.and.right")
                .font(SR.Text.display(28))
                .foregroundStyle(tone)
                .symbolEffect(.variableColor.iterative.reversing, options: .repeating, isActive: !trouble && !reduceMotion)
                .symbolEffect(.pulse, options: .repeating, isActive: trouble && !reduceMotion)
            phone(tone: tone)
        }
        .padding(.vertical, 8)
        .accessibilityHidden(true)
    }

    private func phone(tone: Color) -> some View {
        Image(systemName: "iphone")
            .font(SR.Text.hero(52))
            .foregroundStyle(tone)
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
                            .buttonStyle(SRPressStyle())
                            .accessibilityIdentifier("offline-room-\(host.name)")
                        }
                        stillLooking
                    }
                }
                .srAnimation(.smooth(duration: 0.35), value: session.found.map(\.id))

                addressCard
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .srGround(.warm)
        .onChange(of: session.found.count) { old, new in
            // A room turning up is worth a tap on the hand.
            if new > old { SRHaptic.select() }
        }
    }

    /// Looking, and — after a few quiet seconds — what usually explains a
    /// list that stays empty.
    private var searching: some View {
        VStack(spacing: 14) {
            OfflineRadar(active: true)
            Text("Looking for rooms…")
                .font(SR.Text.title())
                .foregroundStyle(SR.ink)
            Text("Ask the host to tap Host a room. Their room shows up here by itself.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let since = session.browsingSince, context.date.timeIntervalSince(since) > 8 {
                    Label {
                        Text("Nothing yet. Check the host has tapped Host a room and is keeping the app open, that Bluetooth and Wi-Fi are on for both of you, and that Local Network is allowed for SR Companion (Settings › Privacy & Security › Local Network). The search starts again by itself every few seconds.")
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(SR.warn)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                            .fill(SR.warn.opacity(0.1))
                    )
                    .transition(.opacity)
                }
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
    }

    /// Under a list of rooms: the search goes on, for a host who opens late.
    private var stillLooking: some View {
        HStack(spacing: 10) {
            ProgressView().tint(SR.accent)
            Text("Still looking for more…")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
        }
        .padding(.leading, 4)
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
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .frame(minHeight: OfflineKitMetrics.bigButton)
                        .srGlassCard(.paper, radius: SR.Glass.innerRadius)
                        .accessibilityLabel("Host's address")
                        .accessibilityIdentifier("offline-address")
                    OfflineKitButton(title: "Join", icon: "arrow.right", prominent: false, haptic: .none, id: "offline-address-join") {
                        joinAddress()
                    }
                    .disabled(OfflineAddress.parse(address) == nil)
                }
                .padding(.top, 10)
            } label: {
                Label("Type the host's address", systemImage: "keyboard")
                    .font(SR.Text.title(16))
                    .foregroundStyle(SR.ink)
                    .frame(minHeight: SR.tapTarget, alignment: .leading)
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

/// One room in the list: the host's initial, the room's name, how it was
/// found, and a Join pill — the whole row is the button.
struct OfflineFoundRow: View {
    let host: OfflineFoundHost

    var body: some View {
        HStack(spacing: 12) {
            OfflineInitial(name: host.name, size: 44, tone: OfflineSeatColour.of(OfflineFoundRow.seat(for: host.id)))
            VStack(alignment: .leading, spacing: 4) {
                Text(host.name)
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .lineLimit(2)
                if !host.via.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(host.via) { link in
                            Label(link.short, systemImage: link.symbol)
                                .font(SR.Text.mono())
                                .foregroundStyle(SR.inkMuted)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Found over \(host.via.map(\.short).joined(separator: " and "))")
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Text("JOIN")
                    .font(SR.Text.label(13))
                    .tracking(1.2)
                Image(systemName: "arrow.right")
                    .font(SR.Text.label(13))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(Capsule().fill(SR.accent))
        }
        .padding(SR.cardPadding)
        .frame(minHeight: 72)
        .srGlassCard(.paper, interactive: true)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// A colour for a room that stays the same every time it is seen.
    static func seat(for id: String) -> Int {
        Int(id.unicodeScalars.reduce(UInt32(0)) { $0 &+ $1.value } % 8)
    }
}

/// "Joining Sam's game…", with a way back.
struct OfflineConnectingView: View {
    let name: String?
    let cancel: (() -> Void)?

    var body: some View {
        VStack(spacing: 18) {
            OfflineLinkArt()
            Text(name.map { "Joining \($0)…" } ?? "Waiting for the host…")
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Keep both phones close and the app open.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .multilineTextAlignment(.center)
            if let cancel {
                OfflineKitButton(title: "Back to the list", icon: "chevron.left", prominent: false, action: cancel)
                    .frame(maxWidth: 320)
            }
        }
        .padding(SR.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .srGround(.warm)
        .accessibilityElement(children: .contain)
    }
}

/// "Getting back into Sam's game…": the host dropped out of reach and this
/// phone is looking for the same room to take its seat again.
struct OfflineReconnectingView: View {
    let name: String
    let giveUp: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            OfflineLinkArt(trouble: true)
            Text("Getting back into \(name)'s game…")
                .font(SR.Text.display(22))
                .foregroundStyle(SR.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("The connection dropped — usually a locked phone or a few steps too far. Your seat is kept; this joins again by itself as soon as \(name)'s phone is back in reach.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ProgressView().tint(SR.warn)
                Text("Trying again…")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
            OfflineKitButton(title: "Give up and leave", icon: "xmark", prominent: false, id: "offline-reconnect-give-up", action: giveUp)
                .frame(maxWidth: 320)
        }
        .padding(SR.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .srGround(.warm)
        .onAppear { SRHaptic.bad() }
        .accessibilityIdentifier("offline-reconnecting")
    }
}

// MARK: - The lobby

struct OfflineLobbyView: View {
    @ObservedObject var session: OfflineSession
    let lobby: OfflineLobby

    private var present: Int { lobby.players.filter(\.present).count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: session.isHost ? "You are hosting" : "Hosted by \(session.hostName)",
                             title: lobby.roomName)
                if session.isHost {
                    startCard
                    players
                    OfflineConnectionCard(session: session, lobby: lobby)
                    picker
                } else {
                    waiting
                    players
                    OfflineConnectionCard(session: session, lobby: lobby)
                    if let chosen = session.chosen {
                        OfflineHowToCard(info: chosen.info)
                    }
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .onChange(of: lobby.players.count) { old, new in
            // Somebody sat down.
            if new > old { SRHaptic.select() }
        }
        .accessibilityIdentifier("offline-lobby")
    }

    // MARK: Seats

    private var emptySeats: Int {
        OfflineShell.emptySeats(seated: lobby.players.count, capacity: OfflineRoom.capacity,
                                maxPlayers: session.chosen?.info.maxPlayers)
    }

    private var players: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Who's here", trailing: "\(lobby.players.count) of \(OfflineRoom.capacity)")
            VStack(spacing: 0) {
                ForEach(Array(lobby.players.enumerated()), id: \.element.id) { index, player in
                    if index > 0 { Divider().overlay(SR.divider) }
                    playerRow(player, seat: index)
                }
                ForEach(0..<emptySeats, id: \.self) { _ in
                    Divider().overlay(SR.divider)
                    openSeat
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
            .srAnimation(.smooth(duration: 0.3), value: lobby.players.map(\.id))
            .accessibilityIdentifier("offline-players")
        }
    }

    private func playerRow(_ player: OfflineLobbyPlayer, seat: Int) -> some View {
        HStack(spacing: 12) {
            OfflineInitial(name: player.name, size: 40, tone: OfflineSeatColour.of(seat))
                .opacity(player.present ? 1 : 0.45)
                .overlay(alignment: .bottomTrailing) {
                    if player.isBot {
                        Image(systemName: "cpu")
                            .font(SR.Text.label())
                            .foregroundStyle(SR.ink)
                            .padding(3)
                            .background(Circle().fill(SR.surface))
                            .offset(x: 4, y: 4)
                            .accessibilityHidden(true)
                    }
                }
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
                        .font(SR.Text.display(24))
                        .foregroundStyle(SR.inkGhost)
                        .frame(width: SR.tapTarget + 4, height: SR.tapTarget + 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SRPressStyle())
                .accessibilityLabel("Remove \(player.name)")
                .accessibilityIdentifier("offline-remove-\(player.id)")
            }
        }
        .frame(minHeight: 56)
        .padding(.vertical, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityElement(children: .contain)
    }

    /// A seat nobody has taken yet: the room still has space.
    private var openSeat: some View {
        HStack(spacing: 12) {
            Circle()
                .strokeBorder(SR.inkGhost, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: "plus")
                        .font(SR.Text.label(13))
                        .foregroundStyle(SR.inkGhost)
                }
                .accessibilityHidden(true)
            Text(session.isHost ? "Open seat — waiting for a phone" : "Open seat")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 52)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// Host, computer player, or — on the host's phone — how each guest's
    /// connection looks.
    @ViewBuilder
    private func chip(for player: OfflineLobbyPlayer) -> some View {
        if player.id == lobby.hostId {
            SRGlassChip(text: "Host", icon: "crown.fill", tone: SR.accent)
        } else if player.isBot {
            SRGlassChip(text: "Computer", icon: "cpu", tone: SR.inkSecondary)
        } else if !player.present {
            SRGlassChip(text: "Away", icon: "wifi.slash", tone: SR.error)
        } else if session.isHost, let health = session.health[player.id], let label = health.label {
            SRGlassChip(text: label, icon: health.isTrouble ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                        tone: health.isTrouble ? SR.error : SR.good)
        }
    }

    // MARK: Start

    /// The chosen game and Start — first on the host's page, so Start is
    /// never a scroll away.
    private var startCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let chosen = session.chosen {
                HStack(spacing: 14) {
                    OfflineGameBadge(info: chosen.info, size: 60)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("UP NEXT")
                            .font(SR.Text.label())
                            .tracking(1.4)
                            .foregroundStyle(OfflineGameArt.hue(chosen.info.category).base)
                        Text(chosen.info.title)
                            .font(SR.Text.display(22))
                            .foregroundStyle(SR.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(chosen.info.playersLabel)
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "hand.point.down.fill")
                        .font(SR.Text.display(22))
                        .foregroundStyle(SR.accent)
                        .accessibilityHidden(true)
                    Text("Pick a game below.")
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                }
            }
            OfflineKitButton(title: "Start", icon: "play.fill", prominent: true, haptic: .ok, id: "offline-start") {
                session.start()
            }
            .disabled(session.startProblem != nil)
            if session.chosen?.entry.hasBot == true, session.addBotProblem == nil {
                OfflineKitButton(title: "Add a computer player", icon: "cpu", prominent: false, id: "offline-add-bot") {
                    session.addBot()
                }
            }
            if let problem = session.startProblem, session.chosen != nil {
                Label {
                    Text(problem)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(SR.accent)
                }
            }
        }
        .padding(SR.cardPadding + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                .fill(LinearGradient(colors: [startTint.opacity(0.16), Color.clear], startPoint: .top, endPoint: .bottom))
        )
        .srGlassCard(.paper)
        .srAnimation(.smooth(duration: 0.3), value: lobby.gameId)
    }

    private var startTint: Color {
        guard let chosen = session.chosen else { return SR.accent }
        return OfflineGameArt.hue(chosen.info.category).base
    }

    // MARK: Picker

    /// Every game, by shelf; the ones that cannot seat this many are dimmed,
    /// and say why.
    private var picker: some View {
        VStack(alignment: .leading, spacing: SR.sectionGap) {
            ForEach(OfflineGameCategory.allCases) { category in
                pickerShelf(category)
            }
        }
    }

    @ViewBuilder
    private func pickerShelf(_ category: OfflineGameCategory) -> some View {
        let items = OfflineCatalogue.games(in: category)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                OfflineShelfHeading(category: category, count: items.count)
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().overlay(SR.divider) }
                        pickerRow(item)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .srGlassCard(.paper)
            }
        }
    }

    private func pickerRow(_ item: OfflineCatalogueItem) -> some View {
        let note = OfflineShell.fitNote(minPlayers: item.info.minPlayers, maxPlayers: item.info.maxPlayers, count: present)
        let chosen = lobby.gameId == item.id
        return Button {
            SRHaptic.select()
            session.choose(item.id)
        } label: {
            HStack(spacing: 12) {
                OfflineGameBadge(info: item.info, size: 40)
                    .saturation(note == nil || chosen ? 1 : 0.2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.info.title)
                        .font(SR.Text.title(16))
                        .foregroundStyle(SR.ink)
                        .lineLimit(1)
                    Text(item.entry.hasBot ? "\(item.info.playersLabel) · bots can join" : item.info.playersLabel)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .lineLimit(1)
                    if let note, !chosen {
                        Text(note)
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.warn)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                    .font(SR.Text.display(22))
                    .foregroundStyle(chosen ? SR.accent : SR.inkGhost)
                    .accessibilityHidden(true)
            }
            .opacity(note == nil || chosen ? 1 : 0.6)
            .padding(.horizontal, 6)
            .frame(minHeight: 60)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                    .fill(chosen ? SR.accent.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(SRPressStyle())
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityValue(chosen ? "Chosen" : (note ?? ""))
        .accessibilityIdentifier("offline-pick-\(item.id)")
    }

    // MARK: A guest's wait

    /// A guest's whole job in the lobby: know what is next and wait for the
    /// host. Said first, large, with the game's badge.
    private var waiting: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let chosen = session.chosen {
                HStack(spacing: 14) {
                    OfflineGameBadge(info: chosen.info, size: 60)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("NEXT UP")
                            .font(SR.Text.label())
                            .tracking(1.4)
                            .foregroundStyle(OfflineGameArt.hue(chosen.info.category).base)
                        Text(chosen.info.title)
                            .font(SR.Text.display(22))
                            .foregroundStyle(SR.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                Text(chosen.info.blurb)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            OfflineWaitLine(text: "Waiting for \(session.hostName) to \(session.chosen == nil ? "pick a game" : "start").")
                .accessibilityIdentifier("offline-waiting")
        }
        .padding(SR.cardPadding + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .srAnimation(.smooth(duration: 0.3), value: lobby.gameId)
    }
}

/// A gently pulsing hourglass and what it is waiting for.
struct OfflineWaitLine: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "hourglass")
                .font(SR.Text.title(17))
                .foregroundStyle(SR.accent)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                .accessibilityHidden(true)
            Text(text)
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                .fill(SR.accent.opacity(0.1))
        )
        .accessibilityElement(children: .combine)
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
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .font(SR.Text.title(16))
                        .foregroundStyle(Color.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(statusTone))
                        .accessibilityHidden(true)
                    Text(headline)
                        .font(SR.Text.title(16))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(detail)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if session.isHost, !session.addresses.isEmpty {
                    ForEach(session.addresses, id: \.self) { address in
                        Text(address)
                            .font(SR.Text.figure(24))
                            .foregroundStyle(SR.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .textSelection(.enabled)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                                    .fill(SR.accent.opacity(0.1))
                            )
                            .accessibilityLabel("Address \(address)")
                            .accessibilityIdentifier("offline-address-\(address)")
                    }
                }
                HStack(spacing: 10) {
                    OfflineKitButton(title: session.testing ? "Testing…" : "Test connection", icon: "waveform.path.ecg",
                                     prominent: false, id: "offline-test-connection") {
                        session.testConnection()
                    }
                    .disabled(session.testing)
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

    /// Green when every guest is heard; amber when one is not; the accent
    /// while a host waits for its first.
    private var statusTone: Color {
        if session.isHost {
            if guests.isEmpty { return SR.accent }
            let trouble = guests.contains { guest in session.health[guest.id]?.isTrouble ?? false }
            return trouble ? SR.warn : SR.good
        }
        return SR.good
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
            OfflineDealingView(title: session.chosen?.info.title)
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

/// The beat between Start and the first view: the game's name and a
/// shuffle, rather than a bare spinner.
struct OfflineDealingView: View {
    let title: String?

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(SR.accent)
            Text(title.map { "Setting up \($0)…" } ?? "Waiting for the host…")
                .font(SR.Text.title())
                .foregroundStyle(SR.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SR.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .srGround(.warm)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - After a match

struct OfflineFinishedView: View {
    @ObservedObject var session: OfflineSession
    let lobby: OfflineLobby
    @ObservedObject private var results = OfflineResultStore.shared

    private var standings: [OfflineStanding] { lobby.standings ?? [] }

    private var outcome: OfflineShell.Outcome {
        OfflineShell.outcome(standings, me: session.playerId, isSolo: session.isSolo)
    }

    private var myScore: Int? { standings.first { $0.playerId == session.playerId }?.score }

    private var best: Int? {
        guard let id = session.chosen?.id else { return nil }
        return results.queue.tallies[id]?.best
    }

    /// Confetti for a win, a share of one, or a solo score that is this
    /// phone's best.
    private var celebrate: Bool {
        switch outcome {
        case .won, .tied: return true
        case .solo:
            guard let score = myScore, score > 0 else { return false }
            return best.map { score >= $0 } ?? true
        case .placed, .watched: return false
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                OfflineResultHero(kicker: "\(session.chosen?.info.title ?? "Game") · final",
                                  headline: OfflineShell.headline(standings, me: session.playerId, isSolo: session.isSolo),
                                  strap: OfflineShell.strap(outcome, best: best, score: myScore),
                                  outcome: outcome)
                if standings.count >= 2 {
                    OfflinePodiumView(standings: standings, me: session.playerId, players: lobby.roster)
                }
                if !standings.isEmpty {
                    OfflineStandingsCard(standings: standings, me: session.playerId)
                        .accessibilityIdentifier("offline-standings")
                }
                actions
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
        .overlay(alignment: .top) {
            if celebrate {
                OfflineConfettiView(seed: UInt64(max(0, lobby.match)) &+ 1)
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            if standings.first(where: { $0.playerId == session.playerId })?.rank == 1 { SRHaptic.ok() }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if session.isHost {
            VStack(spacing: 10) {
                OfflineKitButton(title: "Play again", icon: "arrow.counterclockwise", prominent: true, id: "offline-again") {
                    session.playAgain()
                }
                OfflineKitButton(title: session.isSolo ? "Done" : "Pick another game",
                                 icon: session.isSolo ? "checkmark" : "square.grid.2x2",
                                 prominent: false, id: "offline-pick-another") {
                    // Alone there is no lobby to go back to: the shelf is the lobby.
                    if session.isSolo { session.leave() } else { session.backToLobby() }
                }
            }
        } else {
            OfflineWaitLine(text: "Waiting for \(session.hostName) to play again or pick another game.")
        }
    }

    /// Where this result is going.
    private let syncLine = "Saved on this phone. It joins the family leaderboard next time you are online and paired."
}

/// The top of the results: a trophy (or a medal, or a star alone), the
/// kicker, the headline, and one line of what it means for you.
struct OfflineResultHero: View {
    let kicker: String
    let headline: String
    let strap: String
    let outcome: OfflineShell.Outcome
    @State private var landed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The emblem beside the headline; above it at the accessibility sizes.
    private var mast: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
    }

    var body: some View {
        mast {
            emblem
            VStack(alignment: .leading, spacing: 4) {
                Text(kicker.uppercased())
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                    .fixedSize(horizontal: false, vertical: true)
                Text(headline)
                    .font(SR.Text.hero(34))
                    .tracking(-0.8)
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(strap)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { landed = true }
    }

    private var emblem: some View {
        let colours = OfflineMedal.colours(emblemRank)
        return ZStack {
            Circle()
                .fill(LinearGradient(colors: [colours.glow, colours.base], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle()
                .strokeBorder(Color.white.opacity(0.5), lineWidth: 3)
            Image(systemName: emblemSymbol)
                .font(SR.Text.hero(34))
                .foregroundStyle(colours.ink)
                .symbolEffect(.bounce, value: landed)
        }
        .frame(width: 84, height: 84)
        .shadow(color: colours.base.opacity(0.4), radius: 12, x: 0, y: 6)
        .scaleEffect(landed || reduceMotion ? 1 : 0.6)
        .opacity(landed || reduceMotion ? 1 : 0)
        .animation(reduceMotion ? nil : Animation.smooth(duration: 0.5), value: landed)
        .accessibilityHidden(true)
    }

    private var emblemRank: Int {
        switch outcome {
        case .won, .tied, .solo: return 1
        case .placed(let rank): return rank
        case .watched: return 4
        }
    }

    private var emblemSymbol: String {
        switch outcome {
        case .won, .tied: return "trophy.fill"
        case .solo: return "star.fill"
        case .placed(let rank): return rank <= 3 ? "medal.fill" : "flag.checkered"
        case .watched: return "eye.fill"
        }
    }
}

/// The top three on a podium — second, first, third — rising into place,
/// each in their seat colour, this phone's name marked.
struct OfflinePodiumView: View {
    let standings: [OfflineStanding]
    let me: String
    /// Seat order, for each player's colour.
    let players: [OfflinePlayer]
    @State private var risen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let tallest: CGFloat = 112

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(OfflineShell.podium(standings)) { row in
                column(row)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
        .onAppear { risen = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func column(_ row: OfflineStanding) -> some View {
        let seat = players.firstIndex { $0.id == row.playerId } ?? 0
        let tone = OfflineSeatColour.of(seat)
        let share = CGFloat(OfflineShell.podiumHeight(rank: row.rank))
        let height = tallest * share
        let delay = Double(3 - min(3, row.rank)) * 0.12
        let up = risen || reduceMotion
        return VStack(spacing: 6) {
            OfflineInitial(name: row.name, size: row.rank == 1 ? 52 : 42, tone: tone)
                .overlay(alignment: .top) {
                    if row.rank == 1 {
                        Image(systemName: "crown.fill")
                            .font(SR.Text.title(18))
                            .foregroundStyle(OfflineMedal.colours(1).base)
                            .offset(y: -20)
                    }
                }
            Text(row.playerId == me ? "You" : row.name)
                .font(SR.Text.title(15))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [OfflineMedal.colours(row.rank).glow, OfflineMedal.colours(row.rank).base],
                                         startPoint: .top, endPoint: .bottom))
                VStack(spacing: 2) {
                    Text("\(row.rank)")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(OfflineMedal.colours(row.rank).ink)
                    Text("\(row.score)")
                        .font(SR.Text.mono())
                        .foregroundStyle(OfflineMedal.colours(row.rank).ink.opacity(0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(.top, 8)
                .opacity(up ? 1 : 0)
            }
            .frame(height: up ? height : 12)
            .animation(reduceMotion ? nil : Animation.smooth(duration: 0.6).delay(delay), value: risen)
        }
        .frame(maxWidth: .infinity)
    }

    private var spoken: String {
        let rows = OfflineShell.podium(standings).sorted { $0.rank < $1.rank }
        let parts: [String] = rows.map { (row: OfflineStanding) -> String in
            let who: String = row.playerId == me ? "you" : row.name
            return OfflineShell.ordinal(row.rank) + " " + who
        }
        return "Podium: " + parts.joined(separator: ", ")
    }
}
