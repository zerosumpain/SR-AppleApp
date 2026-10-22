import SwiftUI
import UIKit

/// One Manhunt room, from the lobby to the catch.
///
/// The lobby is every game's (`GameLobby`) with the play area as its panel:
/// the circle centres on the host's phone, and the host may pick the runner.
/// The 3-2-1 is every game's. Then the head start (the runner goes; nobody is
/// on anybody's map), the hunt (the map, the clocks, Catch or Confirm), and
/// the finish: who won, in a sentence, and the table. The map shows only what
/// the server sent this phone.
struct ManhuntScreen: View {
    let roomId: String
    @StateObject private var store: ManhuntStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(roomId: String) {
        self.roomId = roomId
        _store = StateObject(wrappedValue: ManhuntStore(roomId: roomId))
    }

    var body: some View {
        content
            .navigationTitle("Manhunt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar(immersive ? .hidden : .visible, for: .navigationBar)
            .statusBarHidden(immersive)
            .onAppear { store.open() }
            .onDisappear { store.close() }
            .onChange(of: scenePhase) { _, phase in
                // The stream sleeps in the background; a live hunt keeps sending
                // positions (the phone is in a pocket), and the finish stops it.
                if phase == .active { store.open() } else if phase == .background { store.pauseStream() }
            }
            .overlay(alignment: .top) {
                if let message = store.message, !immersive { SRBanner(text: message) }
            }
    }

    private var immersive: Bool {
        guard !store.ended, let room = store.room else { return false }
        return ManhuntScreenPhase.of(room) == .countdown
    }

    @ViewBuilder
    private var content: some View {
        if store.ended {
            GameEndedView(id: "manhunt-ended", done: { dismiss() })
        } else if let room = store.room {
            switch ManhuntScreenPhase.of(room) {
            case .lobby, .unknown:
                GameLobby(room: room, store: store, prefix: "manhunt", done: { dismiss() },
                          panel: AnyView(ManhuntLobbyPanel(room: room, store: store)),
                          startBlocked: room.manhunt?.area == nil || room.playing.count < 3)
            case .countdown:
                GameCountdownView(room: room, store: store,
                                  note: "The runner gets a two-minute head start. Nobody is on the map until the hunt begins.",
                                  id: "manhunt-countdown")
            case .headstart, .hunt:
                ManhuntPlaying(room: room, store: store, done: { dismiss() })
            case .finished:
                ManhuntFinished(room: room, store: store, done: { dismiss() })
            case .closed:
                GameEndedView(id: "manhunt-ended", done: { dismiss() })
            }
        } else {
            ProgressView()
                .tint(SR.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .srPaper()
        }
    }
}

// MARK: - Lobby

/// The play area (centred on the host), the size and length, and who runs.
struct ManhuntLobbyPanel: View {
    let room: GameRoom
    @ObservedObject var store: ManhuntStore

    private var state: ManhuntState? { room.manhunt }

    var body: some View {
        VStack(alignment: .leading, spacing: SR.sectionGap) {
            areaCard
            runnerCard
            if let refusal = store.refusal {
                Label(refusal, systemImage: "exclamationmark.circle")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("manhunt-refusal")
            }
        }
    }

    private var areaCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("PLAY AREA")
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                Spacer(minLength: 8)
                Text("\(ManhuntRules.distance(state?.radius ?? 500)) · \(state?.minutes ?? 30) min")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkSecondary)
            }
            if let area = state?.area {
                ManhuntMap(area: area, marks: [], interactive: false)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous))
                    .accessibilityElement()
                    .accessibilityLabel("Map of the play area, \(ManhuntRules.distance(area.radiusM)) round the centre")
                    .accessibilityIdentifier("manhunt-area-map")
                Text(room.isHost ? "Centred on where you were standing. Everyone plays inside the circle." :
                        "Centred on where \(room.host?.name ?? "the host") was standing. Everyone plays inside the circle.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(room.isHost ? "The circle goes round where you stand. Go to the middle of where you will play, then centre it." :
                        "Waiting for \(room.host?.name ?? "the host") to set the play area.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("manhunt-area-missing")
            }
            if room.isHost {
                Button { store.centreHere() } label: {
                    SRButtonLabel(title: store.centring ? "Finding where you are…" : (state?.area == nil ? "Centre on me" : "Re-centre on me"),
                                  icon: "location.fill", fill: true)
                }
                .srButton(state?.area == nil ? .prominent : .regular)
                .controlSize(.large)
                .disabled(store.centring || store.sending)
                .accessibilityIdentifier("manhunt-centre")
                HStack(spacing: 8) {
                    Menu {
                        ForEach(ManhuntSettings.radii, id: \.self) { m in
                            Button(ManhuntSettings.radiusLabel(m)) { store.setSize(radius: m) }
                        }
                    } label: {
                        SRButtonLabel(title: "Size", icon: "circle.dashed", fill: true)
                    }
                    .srButton(.regular)
                    .disabled(state?.area == nil)
                    .accessibilityIdentifier("manhunt-size")
                    Menu {
                        ForEach(ManhuntSettings.lengths, id: \.self) { m in
                            Button("\(m) minutes") { store.setSize(minutes: m) }
                        }
                    } label: {
                        SRButtonLabel(title: "Length", icon: "timer", fill: true)
                    }
                    .srButton(.regular)
                    .disabled(state?.area == nil)
                    .accessibilityIdentifier("manhunt-length")
                }
            }
            if let rule = state?.rule {
                Text(rule)
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if room.playing.count < 3 {
                Text("Needs three or more: one runner, two hunters.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .accessibilityIdentifier("manhunt-needs-three")
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("manhunt-area")
    }

    private var runnerCard: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Runner", trailing: state?.runnerPick.map { room.name(of: $0) } ?? "Drawn at the start")
            if room.isHost {
                DaydreamWrap(spacing: 8) {
                    chip("Draw at random", selected: state?.runnerPick == nil, id: "manhunt-runner-random") {
                        store.pickRunner(nil)
                    }
                    ForEach(room.players.filter { $0.status == "joined" || $0.status == "invited" }) { player in
                        chip(player.id == room.meId ? "Me" : player.name, selected: state?.runnerPick == player.id,
                             id: "manhunt-runner-\(player.id)") {
                            store.pickRunner(player.id)
                        }
                    }
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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
        .disabled(store.sending)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

// MARK: - Head start and hunt

struct ManhuntPlaying: View {
    let room: GameRoom
    @ObservedObject var store: ManhuntStore
    let done: () -> Void
    @State private var confirmingLeave = false

    private var state: ManhuntState? { room.manhunt }
    private var phase: ManhuntPhase { ManhuntScreenPhase.of(room) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let now = store.serverNow()
                    VStack(alignment: .leading, spacing: 14) {
                        header(now: now)
                        clocks(now: now)
                    }
                }
                if let state {
                    ManhuntMap(area: state.area, marks: state.marks(meId: room.meId))
                        .frame(height: 340)
                        .clipShape(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous))
                        .overlay(alignment: .bottomLeading) { legend }
                        .accessibilityElement()
                        .accessibilityLabel(mapSpoken(state))
                        .accessibilityIdentifier("manhunt-map")
                }
                status
                actions
                people
                Button { confirmingLeave = true } label: {
                    SRButtonLabel(title: "Leave the game", icon: "xmark", fill: true)
                }
                .srButton(.regular)
                .controlSize(.large)
                .disabled(store.busy)
                .accessibilityIdentifier("manhunt-leave")
                Text("Your position goes only to this game, only while it runs, and is never kept.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier(phase == .headstart ? "manhunt-headstart" : "manhunt-hunt")
        .onChange(of: store.refusal) { _, refusal in
            if let refusal { UIAccessibility.post(notification: .announcement, argument: refusal) }
        }
        .confirmationDialog("Leave this game?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) {
                Task {
                    _ = await store.act("leave")
                    done()
                }
            }
            Button("Keep playing", role: .cancel) {}
        } message: {
            Text(state?.myRole == .runner ? "If the runner leaves, the hunters win." : "Your phone stops sharing where you are.")
        }
    }

    private func header(now: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kicker)
                .font(SR.Text.label())
                .tracking(SR.kickerTracking)
                .foregroundStyle(SR.accent)
            Text(headline)
                .font(SR.Text.display(26))
                .foregroundStyle(store.claimOnMe || (state?.myRole == .runner && store.runnerLive) ? SR.error : SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("manhunt-headline")
        }
    }

    private var kicker: String {
        let role = state?.myRole == .runner ? "YOU RUN" : state?.myRole == .hunter ? "YOU HUNT" : "WATCHING"
        let level = GameDifficulty.label(for: room.difficulty).uppercased()
        return "MANHUNT · \(role) · \(level)"
    }

    private var headline: String {
        if phase == .headstart {
            return state?.myRole == .runner ? "Run! Get away" : "Wait — the runner is getting away"
        }
        return ManhuntRules.headline(role: state?.myRole, live: store.runnerLive, claimByMe: store.claimByMe, claimOnMe: store.claimOnMe)
    }

    private func clocks(now: Double?) -> some View {
        HStack(spacing: 10) {
            if phase == .headstart {
                clock(title: "Hunt starts in", ms: ManhuntRules.left(until: state?.phaseEndsAt, now: now), id: "manhunt-clock")
            } else {
                clock(title: "Time left", ms: ManhuntRules.left(until: state?.endsAt, now: now), id: "manhunt-clock")
                clock(title: "Next ping", ms: ManhuntRules.left(until: state?.nextPingAt, now: now), id: "manhunt-next-ping")
            }
        }
    }

    private func clock(title: String, ms: Double?, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(SR.Text.label())
                .tracking(1)
                .foregroundStyle(SR.inkMuted)
            Text(ms.map(ManhuntRules.clock) ?? "–")
                .font(SR.Text.figure(26))
                .foregroundStyle(SR.ink)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 10)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    private var legend: some View {
        HStack(spacing: 10) {
            legendDot(Color(uiColor: .systemBlue), "You")
            if state?.myRole == .hunter {
                legendDot(SR.accentInk, "Hunter")
                legendDot(SR.accent, "Runner at ping")
            } else if state?.myRole == .runner {
                legendDot(SR.warn, "Hunter at ping")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(SR.paper.opacity(0.9)))
        .padding(8)
        .accessibilityHidden(true)
    }

    private func legendDot(_ colour: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(colour).frame(width: 9, height: 9)
            Text(text).font(SR.Text.mono(11)).foregroundStyle(SR.ink)
        }
    }

    private func mapSpoken(_ state: ManhuntState) -> String {
        let marks = state.marks(meId: room.meId)
        if marks.isEmpty { return "Map of the play area. Nobody to show yet." }
        let bits = marks.map { mark -> String in
            switch mark.kind {
            case .me: return "you"
            case .hunter: return "\(mark.name), live"
            case .runnerLive: return "\(mark.name), the runner, live"
            case .runnerPing: return "\(mark.name), the runner, at the last ping"
            case .hunterPing: return "\(mark.name) at the last ping"
            }
        }
        return "Map of the play area showing " + GameNames.list(bits)
    }

    @ViewBuilder
    private var status: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.locationOff {
                Label("Location is off for the SR app, so the game cannot see you. Turn it on in Settings.", systemImage: "location.slash")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("manhunt-location-off")
            }
            if let refusal = store.refusal {
                Label(refusal, systemImage: "exclamationmark.circle")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("manhunt-refusal")
            }
            if let claim = state?.claim {
                Label(claimLine(claim), systemImage: "hand.raised.fill")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.accentInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("manhunt-claim")
            }
            if let me = state?.seat(room.meId), me.fix?.outside == true {
                Label(state?.myRole == .runner ? "You are outside the circle: the hunters can see you live." : "You are outside the circle. Head back in.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.warn)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("manhunt-outside")
            }
            if state?.runnerQuiet == true, state?.myRole == .hunter {
                Text("The runner's phone has gone quiet: a catch is taken on your word.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("manhunt-quiet")
            }
            if phase == .hunt, let ping = state?.lastPing {
                TimelineView(.periodic(from: .now, by: 5)) { _ in
                    Text(pingLine(ping, now: store.serverNow()))
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .accessibilityIdentifier("manhunt-last-ping")
                }
            }
        }
    }

    private func claimLine(_ claim: ManhuntClaim) -> String {
        if claim.hunterId == room.meId { return "You claimed the catch. Waiting for the runner to confirm — it stands in 20 seconds." }
        let who = room.name(of: claim.hunterId)
        if state?.myRole == .runner { return "\(who) says they caught you. Confirm it, or it stands in 20 seconds." }
        return "\(who) claimed the catch."
    }

    private func pingLine(_ ping: ManhuntPing, now: Double?) -> String {
        let ago = ManhuntRules.left(until: now, now: ping.at).map { ManhuntRules.clock($0) } ?? "–"
        return state?.myRole == .runner ? "Hunters last shown \(ago) ago." : "Runner last shown \(ago) ago."
    }

    @ViewBuilder
    private var actions: some View {
        if phase == .hunt {
            if store.claimOnMe {
                Button { store.confirm() } label: {
                    SRButtonLabel(title: "Yes, I'm caught", icon: "checkmark", fill: true)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .disabled(store.sending)
                .accessibilityIdentifier("manhunt-confirm")
            } else if state?.myRole == .hunter {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let now = store.serverNow()
                    let cooling = ManhuntRules.left(until: state?.catchCooldownUntil, now: now) ?? 0
                    Button { store.catchNow() } label: {
                        SRButtonLabel(title: cooling > 0 ? "Catch again in \(Int((cooling / 1000).rounded(.up))) s" : "Catch!",
                                      icon: "hand.raised.fill", fill: true)
                    }
                    .srButton(.prominent)
                    .controlSize(.large)
                    .disabled(!store.canCatch(now: now))
                    .accessibilityHint("Tap when you are within \(Int(state?.catchM ?? 25)) metres of the runner.")
                    .accessibilityIdentifier("manhunt-catch")
                }
            }
        }
    }

    private var people: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Players", trailing: "\(state?.inHunt.count ?? 0) in")
            VStack(spacing: 0) {
                ForEach(Array((state?.inHunt ?? []).enumerated()), id: \.element.id) { index, seat in
                    if index > 0 { Divider().overlay(SR.divider) }
                    HStack(spacing: 12) {
                        GameInitial(name: seat.name, tone: seat.role == .runner ? SR.accent : SR.accentInk)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(seat.name + (seat.id == room.meId ? " (you)" : ""))
                                .font(SR.Text.title())
                                .foregroundStyle(SR.ink)
                            Text(seat.role == .runner ? "Runner" : "Hunter")
                                .font(SR.Text.mono())
                                .foregroundStyle(SR.inkMuted)
                        }
                        Spacer(minLength: 8)
                        if seat.fix != nil, seat.id != room.meId {
                            SRGlassChip(text: "Live", tone: seat.role == .runner ? SR.error : SR.good)
                        }
                    }
                    .frame(minHeight: SR.tapTarget)
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("manhunt-player-\(seat.id)")
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
        }
    }
}

// MARK: - Finished

struct ManhuntFinished: View {
    let room: GameRoom
    @ObservedObject var store: ManhuntStore
    let done: () -> Void

    private var state: ManhuntState? { room.manhunt }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Manhunt · \(GameDifficulty.label(for: room.difficulty)) · final",
                             title: GameResults.title(room, solo: "Game over", none: "Game over"),
                             strap: GameResults.strap(room))
                if let line = state?.outcomeLine(name: { $0 == room.meId ? "You" : room.name(of: $0) }) {
                    Text(line)
                        .font(SR.Text.bodyMedium(16))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("manhunt-outcome")
                }
                GameStandingsCard(room: room, label: "Result", id: "manhunt-standings", detail: detail, figure: { _ in nil })
                Text("The game's positions were dropped when it ended.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                GameFinishedButtons(room: room, store: store, prefix: "manhunt", done: done)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("manhunt-finished")
    }

    private func detail(_ row: GameStanding) -> String {
        guard let s = state?.standings?.first(where: { $0.id == row.id }) else { return "" }
        let role = s.role == .runner ? "Runner" : "Hunter"
        let result: String
        switch s.result {
        case "won":
            if s.role == .runner { result = "got away" } else { result = state?.result?.outcome == "caught" ? "made the catch" : "won" }
        case "team": result = "on the winning side"
        default: result = "lost"
        }
        return "\(role) · \(result)" + (s.left ? " · left" : "")
    }
}
