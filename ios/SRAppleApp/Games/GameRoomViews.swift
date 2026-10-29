import SwiftUI

// The parts of a room every game shares: the route that picks the game's
// screen, the lobby, the 3-2-1, and the "this game has ended" page.

// MARK: - The route

/// One room, whichever game it is. The Games tab's stack pushes this for every
/// `GameRoomRef`; it hands over to the game's own screen.
///
/// A ref from a list knows its game. A bare id — a notification raised by an
/// older build — reads the room's snapshot once to find out, retrying a flaky
/// connection and giving up only on a room that has gone.
struct GameRoomScreen: View {
    let ref: GameRoomRef
    @State private var game: String?
    @State private var gone = false
    /// Reads that failed so far: after a few, the wait says so.
    @State private var misses = 0
    @Environment(\.dismiss) private var dismiss

    init(ref: GameRoomRef) {
        self.ref = ref
        _game = State(initialValue: ref.game)
    }

    var body: some View {
        if gone {
            GameEndedView(id: "game-ended", done: { dismiss() })
                .toolbar(.hidden, for: .tabBar)
        } else if let game {
            switch GameKind(rawValue: game) {
            case .tapDuel?:
                TapDuelScreen(roomId: ref.id)
            case .wordleRace?:
                WordleRaceScreen(roomId: ref.id)
            case .quizNight?:
                QuizNightScreen(roomId: ref.id)
            case .anagramBlitz?:
                AnagramBlitzScreen(roomId: ref.id)
            case .mathsSprint?:
                MathsSprintScreen(roomId: ref.id)
            case .sequenceMemory?:
                SequenceMemoryScreen(roomId: ref.id)
            case .boggle?:
                BoggleScreen(roomId: ref.id)
            case .categories?:
                CategoriesScreen(roomId: ref.id)
            case .liarsDice?:
                LiarsDiceScreen(roomId: ref.id)
            case .drawGuess?:
                DrawGuessScreen(roomId: ref.id)
            case .marbleRace?:
                MarbleRaceScreen(roomId: ref.id)
            case .chess?:
                ChessScreen(roomId: ref.id)
            case .mission?:
                MissionScreen(roomId: ref.id)
            case .oneClue?:
                OneClueScreen(roomId: ref.id)
            case .fakeArtist?:
                FakeArtistScreen(roomId: ref.id)
            case .passThePlate?:
                PassThePlateScreen(roomId: ref.id)
            case .fireworks?:
                FireworksScreen(roomId: ref.id)
            case .manhunt?:
                ManhuntScreen(roomId: ref.id)
            case .homestead?:
                HomesteadScreen(roomId: ref.id)
            case .hometowns?:
                HometownsScreen(roomId: ref.id)
            case .lander?, .carRace?, .carRacerPlus?, .miniGolf?, .pinball?, .tiltMaze?, .orbit?,
                 .solitaire?, .merge2048?, .minesweeper?, .snake?:
                PhysicsGameScreen(kind: GameKind(rawValue: game) ?? .lander)
            case nil:
                SREmpty(
                    title: "\(GameNames.title(game)) needs a newer app",
                    icon: "arrow.down.app",
                    message: "This version of the app does not know that game yet.",
                    actionLabel: "Done",
                    action: { dismiss() }
                )
                .frame(maxHeight: .infinity)
                .srPaper()
                .toolbar(.hidden, for: .tabBar)
            }
        } else {
            GameRoomOpening(misses: misses, done: { dismiss() })
                .toolbar(.hidden, for: .tabBar)
                .task { await resolve() }
        }
    }

    private func resolve() async {
        var wait: UInt64 = 1
        while !Task.isCancelled {
            do {
                let envelope: GameRoomEnvelope = try await SiteClient.shared.send("api/native/games/\(ref.id)")
                game = envelope.room.game
                return
            } catch SiteError.status(let code, _) where code == 404 || code == 403 {
                gone = true
                return
            } catch {
                misses += 1
                try? await Task.sleep(nanoseconds: wait * 1_000_000_000)
                wait = min(wait * 2, 10)
            }
        }
    }
}

/// The wait while a room from a bare id is found: what is happening, and —
/// once a few reads have failed — that the signal is the likely reason, with
/// a way back out.
struct GameRoomOpening: View {
    let misses: Int
    let done: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(SR.accent)
            Text(misses >= 3 ? "Still trying to reach the game" : "Opening the game…")
                .font(SR.Text.display(19))
                .foregroundStyle(SR.ink)
                .multilineTextAlignment(.center)
            if misses >= 3 {
                Text("Check this phone has a signal. It keeps trying on its own.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button { done() } label: {
                    SRButtonLabel(title: "Back to Games")
                        .frame(minHeight: 44)
                }
                .srButton(.regular)
                .controlSize(.large)
                .accessibilityIdentifier("game-opening-back")
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .srPaper()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("game-opening")
    }
}

/// The room has gone: rooms last minutes, and a restart ends them.
struct GameEndedView: View {
    let id: String
    let done: () -> Void

    var body: some View {
        SREmpty(
            title: "This game has ended",
            icon: "flag.checkered",
            message: "Rooms last a few minutes. Start another from Games.",
            actionLabel: "Done",
            action: done
        )
        .frame(maxHeight: .infinity)
        .srPaper()
        .accessibilityIdentifier(id)
    }
}

// MARK: - Lobby

/// Who is in, who is invited, Start (the host) and Leave. The same for every
/// game; `prefix` keeps each game's accessibility ids its own.
///
/// The lobby is the wait. Its header is the game's own picture with whose
/// game it is and how long it stays open; under it, the seats filling up —
/// a face for everyone in, an empty seat for each still needed — so whether
/// it can start is seen before it is read. The host's Start rides at the foot
/// of the screen, always in reach; everyone else's foot says who it waits on.
/// Each invite says whether it has reached its phone yet — there is no push,
/// so an invite waits for the app to be opened — and the host can ask more
/// people in from here rather than starting over.
struct GameLobby<Store: GameRoomStoring>: View {
    let room: GameRoom
    @ObservedObject var store: Store
    /// "tapduel", "wordle", "quiz".
    let prefix: String
    let done: () -> Void
    /// A game's own panel between the header and the players — Quiz Night's
    /// topic and "jkai is writing the questions…".
    var panel: AnyView? = nil
    /// Start is shown to the host but cannot be pressed yet.
    var startBlocked: Bool = false
    /// The host's Start is replaced by something in `panel`.
    var hidesStart: Bool = false

    /// The family roster, for "ask more people".
    @EnvironmentObject private var games: GamesStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The player id an invite is being sent to.
    @State private var inviting: String?
    @State private var inviteRefusal: String?
    /// A parent asked to close this lobby; the dialog is up.
    @State private var confirmingClose = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                GameLobbyHeader(room: room, title: headerTitle, closes: AnyView(closes))

                Text(strap)
                    .font(SR.Text.bodyMedium(16))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let panel { panel }

                players

                if room.phase == .lobby && room.isHost && room.me?.joined == true { askMore }

                secondaryButtons
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("\(prefix)-lobby")
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        // Someone sat down: the host feels it, and everyone sees the seat fill.
        .onChange(of: room.playing.count) { old, new in
            if new > old { SRHaptic.ok() }
        }
        .srAnimation(.snappy, value: room.players.map(\.status))
        .confirmationDialog("Close this lobby?", isPresented: $confirmingClose, titleVisibility: .visible) {
            Button("Close it for everyone", role: .destructive) {
                Task { if await games.closeLobby(room.id) { done() } }
            }
            Button("Keep it open", role: .cancel) {}
        } message: {
            Text("Everyone waiting in it is told it was closed.")
        }
    }

    private var headerTitle: String {
        room.isHost ? "Your game" : (room.host.map { "\($0.name)’s game" } ?? "A game")
    }

    // MARK: Players

    private var players: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Players", trailing: "\(room.playing.count) in")
            GameLobbySeats(room: room)
            VStack(spacing: 0) {
                ForEach(Array(room.players.enumerated()), id: \.element.id) { index, player in
                    if index > 0 { Divider().overlay(SR.divider) }
                    playerRow(player)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
        }
    }

    private func playerRow(_ player: GamePlayer) -> some View {
        HStack(spacing: 12) {
            GameInitial(name: player.name, filled: player.joined, tone: personTone(player.id), side: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(player.name + (player.id == room.meId ? " (you)" : ""))
                        .font(SR.Text.title())
                        .foregroundStyle(player.joined ? SR.ink : SR.inkMuted)
                    if player.isHost {
                        Label("HOST", systemImage: "crown.fill")
                            .font(SR.Text.label())
                            .tracking(1.2)
                            .foregroundStyle(SR.accent)
                            .labelStyle(.titleAndIcon)
                    }
                }
                if player.status == "invited" {
                    Text(player.sawInvite
                         ? "Has the invite — waiting for them to join"
                         : "Gets the invite when they open the SR app")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            SRGlassChip(text: statusLabel(player), icon: statusIcon(player.status), tone: statusTone(player.status))
        }
        .frame(minHeight: SR.tapTarget + 4)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("\(prefix)-player-\(player.id)")
    }

    private func personTone(_ id: String) -> Color {
        SR.PersonHue.assign(room.players.map(\.id))[id] ?? SR.accentInk
    }

    /// The host asks more of the family in, one tap each, while the lobby is open.
    @ViewBuilder
    private var askMore: some View {
        let asked = Set(room.players.filter { $0.status == "joined" || $0.status == "invited" }.map(\.id))
        let others = games.players.filter { !asked.contains($0.id) }
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Ask more people")
            if games.players.isEmpty {
                Text("Nobody else in the family can play yet. They need the SR app on their phone, with games turned on for them.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else if others.isEmpty {
                Text("Everyone who can play has been asked.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(others.enumerated()), id: \.element.id) { index, person in
                        if index > 0 { Divider().overlay(SR.divider) }
                        inviteRow(person)
                    }
                }
                .padding(.horizontal, SR.cardPadding)
                .padding(.vertical, 6)
                .srGlassCard(.paper)
            }
            if let inviteRefusal {
                Label(inviteRefusal, systemImage: "exclamationmark.circle")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Their phone rings when the SR app is open — tell them to open it.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func inviteRow(_ person: GamePerson) -> some View {
        HStack(spacing: 12) {
            GameInitial(name: person.name, filled: false, side: 36)
                .accessibilityHidden(true)
            Text(person.name)
                .font(SR.Text.title())
                .foregroundStyle(SR.ink)
            Spacer(minLength: 8)
            Button {
                SRHaptic.tap()
                invite(person)
            } label: {
                if inviting == person.id {
                    ProgressView().tint(SR.accent)
                } else {
                    SRButtonLabel(title: "Invite", icon: "paperplane.fill")
                }
            }
            .srButton(.regular)
            .controlSize(.large)
            .disabled(inviting != nil)
            .accessibilityLabel("Invite \(person.name)")
            .accessibilityIdentifier("\(prefix)-invite-\(person.id)")
        }
        .frame(minHeight: SR.tapTarget + 4)
        .padding(.vertical, 4)
    }

    private func invite(_ person: GamePerson) {
        inviting = person.id
        inviteRefusal = nil
        Task {
            switch await GameRoomLink.invite([person.id], to: room.id) {
            case .ok, .gone:
                SRHaptic.ok()
            case .wrongPhase:
                inviteRefusal = "The game has already started."
                SRHaptic.bad()
            case .refused(let text), .failed(let text):
                inviteRefusal = text
                SRHaptic.bad()
            }
            inviting = nil
        }
    }

    // MARK: The clock

    /// "Open 2:41", ticking, from the server's deadline on this phone's clock.
    @ViewBuilder
    private var closes: some View {
        let hue = GamesArt.hue(room.game)
        if room.phase == .lobby, let end = room.phaseEndsAt {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                if let now = store.serverNow() {
                    let left = max(0, Int(((end - now) / 1000).rounded(.down)))
                    Label("Lobby open for \(GameDeadline.clock(seconds: left))", systemImage: "timer")
                        .font(SR.monoMedium(13))
                        .monospacedDigit()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        // On the header's colour: its own type colour, and
                        // solid, in the hue's ink, in the last half-minute.
                        .background(Capsule().fill(hue.onFill.opacity(left < 30 ? 0.95 : 0.22)))
                        .foregroundStyle(left < 30 ? hue.base : hue.onFill)
                        .accessibilityIdentifier("\(prefix)-lobby-closes")
                }
            }
        }
    }

    // MARK: The buttons

    /// The one thing to do now, pinned to the foot: Start for the host, the
    /// wait for everyone else.
    @ViewBuilder
    private var footer: some View {
        if room.isHost && !hidesStart {
            footerBar {
                if let need = blockedLine {
                    Text(need)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                Button {
                    SRHaptic.tap()
                    Task {
                        if await store.act("start") { SRHaptic.ok() }
                    }
                } label: {
                    SRButtonLabel(title: startTitle, icon: "play.fill", fill: true)
                        .frame(minHeight: 44)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .disabled(store.busy || startBlocked)
                .accessibilityIdentifier("\(prefix)-start")
            }
        } else if room.me?.joined == true && !room.isHost {
            footerBar {
                GameLobbyWaiting(text: "Waiting for \(room.host?.name ?? "the host") to start", animated: !reduceMotion)
            }
        } else if room.me?.status == "invited" {
            footerBar {
                HStack(spacing: 10) {
                    ProgressView().tint(SR.accent)
                    Text("Joining…").font(SR.Text.bodyMedium(15)).foregroundStyle(SR.inkSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
        } else if room.me?.joined != true {
            footerBar {
                Button { done() } label: {
                    SRButtonLabel(title: "Done", fill: true)
                        .frame(minHeight: 44)
                }
                .srButton(.regular)
                .controlSize(.large)
            }
        }
    }

    private func footerBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 8) { content() }
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

    /// Leave (or the host's Cancel game), and a parent's Close for everyone:
    /// the lobby's way out, below everything, never beside Start.
    @ViewBuilder
    private var secondaryButtons: some View {
        VStack(spacing: 10) {
            if room.me?.joined == true {
                Button {
                    SRHaptic.tap()
                    Task {
                        _ = await store.act("leave")
                        done()
                    }
                } label: {
                    SRButtonLabel(title: room.isHost ? "Cancel game" : "Leave", fill: true)
                        .frame(minHeight: 44)
                }
                .srButton(.regular)
                .controlSize(.large)
                .disabled(store.busy)
                .accessibilityIdentifier("\(prefix)-leave")
            }
            // A parent may close somebody else's lobby for everyone in it
            // (the host already has Cancel game, which does that).
            if room.phase == .lobby && games.isParent && !room.isHost {
                Button { confirmingClose = true } label: {
                    SRButtonLabel(title: "Close lobby for everyone", icon: "xmark.octagon", fill: true)
                        .frame(minHeight: 44)
                }
                .srButton(.regular)
                .controlSize(.large)
                .disabled(store.busy || games.busy == room.id)
                .accessibilityIdentifier("\(prefix)-close-lobby")
            }
        }
    }

    // MARK: Words

    /// Still waiting on somebody: say who is left out if the host starts now.
    private var waitingOn: [GamePlayer] { room.players.filter { $0.status == "invited" } }

    private var startTitle: String {
        waitingOn.isEmpty ? "Start" : "Start without \(GameNames.list(waitingOn.map(\.name)))"
    }

    /// "Needs 1 more player" over a Start that cannot be pressed yet.
    private var blockedLine: String? {
        startBlocked ? GamesPagePlan.seatsLine(room.game, joined: room.playing.count) : nil
    }

    private var strap: String {
        if room.me?.status == "declined" || room.me?.status == "left" { return "You are not playing in this one." }
        if room.isHost {
            if !waitingOn.isEmpty {
                return "Waiting for \(GameNames.list(waitingOn.map(\.name))). Start when everyone you want is in."
            }
            return room.playing.count <= 1
                ? "Just you so far. Ask someone in below, or start on your own."
                : "Everyone is in. Start when you are ready."
        }
        return "Waiting for \(room.host?.name ?? "the host") to start."
    }

    private func statusLabel(_ player: GamePlayer) -> String {
        switch player.status {
        case "joined": return "In"
        case "invited": return player.sawInvite ? "Seen" : "Invited"
        case "declined": return "Declined"
        case "left": return "Left"
        default: return player.status
        }
    }

    private func statusIcon(_ status: String) -> String? {
        switch status {
        case "joined": return "checkmark"
        case "invited": return "envelope.fill"
        case "declined", "left": return "xmark"
        default: return nil
        }
    }

    private func statusTone(_ status: String) -> Color {
        switch status {
        case "joined": return SR.good
        case "invited": return SR.accentInk
        default: return SR.inkMuted
        }
    }
}

/// A lobby's header: the game's picture with what it is, whose, and the
/// lobby's clock.
struct GameLobbyHeader: View {
    let room: GameRoom
    let title: String
    /// The ticking "Lobby open for 2:41", or nothing.
    let closes: AnyView

    var body: some View {
        let hue = GamesArt.hue(room.game)
        let shape = RoundedRectangle(cornerRadius: SR.Glass.radius + 2, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: GamesArt.icon(room.game))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(hue.base)
                    .frame(width: 50, height: 50)
                    .background(Circle().fill(hue.onFill.opacity(0.94)))
                    .shadow(color: Color.black.opacity(0.14), radius: 4, y: 2)
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                closes
            }
            Text(kicker.uppercased())
                .font(SR.Text.label())
                .tracking(SR.kickerTracking)
                .opacity(0.92)
                .fixedSize(horizontal: false, vertical: true)
            Text(title)
                .font(SR.Text.hero(34))
                .tracking(-0.6)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(hue.onFill)
        .background { GamesTileBackdrop(game: room.game, hue: hue, symbolSide: 130) }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
        .shadow(color: hue.base.opacity(0.28), radius: 14, y: 6)
    }

    private var kicker: String {
        "\(GameNames.title(room.game)) · \(GameDifficulty.label(for: room.difficulty))"
            + (room.pace == .async ? " · \(GamePace.async.label)" : "")
    }
}

/// The seats: a face for everyone in, in their own colour, and an empty seat
/// for each player the game still needs before it can start.
struct GameLobbySeats: View {
    let room: GameRoom

    var body: some View {
        let joined = room.playing
        let empty = GamesPagePlan.emptySeats(room.game, joined: joined.count)
        let tones = SR.PersonHue.assign(room.players.map(\.id))
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(joined) { player in
                        GameInitial(name: player.name, filled: true, tone: tones[player.id] ?? SR.accentInk, side: 46)
                            .transition(.scale.combined(with: .opacity))
                    }
                    ForEach(0..<empty, id: \.self) { _ in
                        Circle()
                            .strokeBorder(SR.inkMuted, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            .frame(width: 46, height: 46)
                            .overlay(Image(systemName: "plus").font(.system(size: 14, weight: .semibold)).foregroundStyle(SR.inkMuted))
                    }
                }
                .padding(.vertical, 2)
            }
            if let line = GamesPagePlan.seatsLine(room.game, joined: joined.count) {
                Text(line)
                    .font(SR.Text.mono())
                    .foregroundStyle(empty > 0 ? SR.accentInk : SR.inkMuted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        let names = GameNames.list(room.playing.map(\.name))
        let base = room.playing.isEmpty ? "Nobody in yet" : "\(names) in"
        guard let line = GamesPagePlan.seatsLine(room.game, joined: room.playing.count) else { return base }
        return "\(base). \(line)."
    }
}

/// "Waiting for Sam to start", with three dots taking turns — or still, under
/// Reduce Motion. Ticks twice a second, and only while the lobby is on screen.
struct GameLobbyWaiting: View {
    let text: String
    var animated: Bool = true

    var body: some View {
        HStack(spacing: 10) {
            if animated {
                TimelineView(.periodic(from: .now, by: 0.4)) { timeline in
                    dots(lit: Int(timeline.date.timeIntervalSinceReferenceDate / 0.4) % 3)
                }
            } else {
                dots(lit: -1)
            }
            Text(text)
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private func dots(lit: Int) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(SR.accent)
                    .frame(width: 8, height: 8)
                    .opacity(lit < 0 || lit == index ? 1 : 0.3)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: lit)
    }
}

// MARK: - Countdown

/// The 3-2-1, full screen on ink, before any game's play begins: the game's
/// mark and colour, the figure in a ring that drains each second, a tap you
/// can feel on every number.
struct GameCountdownView<Store: GameRoomStoring>: View {
    let room: GameRoom
    @ObservedObject var store: Store
    /// One line under the figure: the rule that matters in the first second.
    let note: String
    let id: String

    var body: some View {
        let hue = GamesArt.hue(room.game)
        ZStack {
            SR.band.ignoresSafeArea()
            RadialGradient(colors: [hue.glow.opacity(0.45), Color.clear], center: .center, startRadius: 10, endRadius: 360)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            VStack(spacing: 18) {
                HStack(spacing: 10) {
                    GameArtBadge(game: room.game, side: 34)
                    Text(GameNames.title(room.game).uppercased())
                        .font(SR.Text.label(13))
                        .tracking(SR.inkKickerTracking)
                        .foregroundStyle(SR.cream)
                }
                Text("GET READY")
                    .font(SR.Text.label(13))
                    .tracking(SR.inkKickerTracking)
                    .foregroundStyle(SR.onInk(.label))
                // A tenth of a second is close enough to the server's second,
                // and a tenth of the work a twentieth was.
                TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                    GameCountdownFigure(figure: figure, tint: hue.glow)
                }
                Text(note)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.onInk(.note))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SR.gutter)
            }
        }
        .accessibilityIdentifier(id)
    }

    private var figure: String {
        guard let end = room.phaseEndsAt, let now = store.serverNow() else { return "…" }
        let left = GameCountdown.secondsLeft(until: end, atServer: now)
        return left > 0 ? "\(min(left, 3))" : "…"
    }
}

/// The countdown's figure and its ring. A new figure pops in, the ring fills
/// and drains over the second, and the phone taps once.
struct GameCountdownFigure: View {
    let figure: String
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var ring: CGFloat = 220
    @State private var drain: CGFloat = 1
    @State private var pop: CGFloat = 1

    var body: some View {
        ZStack {
            Circle()
                .stroke(SR.onInk(.track), lineWidth: 10)
            Circle()
                .trim(from: 0, to: drain)
                .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(figure)
                .font(SR.Text.hero(130))
                .foregroundStyle(SR.cream)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .contentTransition(.numericText(countsDown: true))
                .animation(reduceMotion ? nil : .snappy, value: figure)
                .scaleEffect(pop)
                .padding(28)
        }
        // Grows with the text, but never past a small phone's width.
        .frame(width: min(ring, 300), height: min(ring, 300))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(figure == "…" ? "Get ready" : "Starting in \(figure)")
        .onChange(of: figure, initial: true) { _, value in
            guard value != "…" else { return }
            SRHaptic.tap()
            // The ring refills at once, unanimated; the drain and the pop
            // start on the next turn of the run loop, from that full ring.
            var refill = Transaction()
            refill.disablesAnimations = true
            withTransaction(refill) { drain = 1 }
            guard !reduceMotion else { return }
            DispatchQueue.main.async {
                withAnimation(.linear(duration: 0.92)) { drain = 0 }
                withAnimation(.spring(response: 0.18, dampingFraction: 0.7)) { pop = 1.16 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { pop = 1 }
            }
        }
    }
}
