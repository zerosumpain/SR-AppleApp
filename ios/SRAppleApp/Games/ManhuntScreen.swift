import SwiftUI
import UIKit

/// One Manhunt room, from the lobby to the catch.
///
/// The lobby is every game's (`GameLobby`) with the play area as its panel:
/// how to play, the circle (centred on the host's phone) and who runs. The
/// 3-2-1 is every game's. Then the head start (the runner goes; nobody is on
/// anybody's map) and the hunt: a role banner on ink that says who I am and
/// what to do now, the clocks as draining bars, the map, and Catch or Confirm
/// pinned at the foot of the screen in thumb reach. The finish: how it ended,
/// in a picture and a sentence, my record on this phone, and the table. The
/// map shows only what the server sent this phone.
///
/// There is no pause: the hunt runs on the server's clock for everyone at
/// once, out of doors. How to play is a tap away (the bar's question mark)
/// in every phase instead.
struct ManhuntScreen: View {
    let roomId: String
    @StateObject private var store: ManhuntStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingHelp = false

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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !immersive && store.room != nil && !store.ended {
                        Button { showingHelp = true } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(minWidth: SR.tapTarget, minHeight: SR.tapTarget)
                        }
                        .accessibilityLabel("How to play")
                        .accessibilityIdentifier("manhunt-help")
                    }
                }
            }
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
            .sheet(isPresented: $showingHelp) {
                ManhuntHowToSheet(state: store.room?.manhunt)
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
            ManhuntOpening()
        }
    }
}

/// Before the first answer: what is happening, not a bare spinner.
struct ManhuntOpening: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(SR.accent)
            Text("Opening the game…")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .srPaper()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Lobby

/// How to play, the play area (centred on the host), the size and length,
/// and who runs.
struct ManhuntLobbyPanel: View {
    let room: GameRoom
    @ObservedObject var store: ManhuntStore

    private var state: ManhuntState? { room.manhunt }

    var body: some View {
        VStack(alignment: .leading, spacing: SR.sectionGap) {
            howTo
            areaCard
            runnerCard
            notes
        }
    }

    private var howTo: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "How to play", trailing: "3 to 8 players")
            ManhuntHowToList(steps: ManhuntGuide.steps(state), compact: true)
                .padding(SR.cardPadding)
                .srGlassCard(.paper)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("manhunt-how-to")
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(ManhuntRules.keepOpenLine, systemImage: "iphone")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("manhunt-keep-open")
            if store.locationApproximate {
                ManhuntAlertRow(text: ManhuntRules.approximateLine, icon: "location.circle", tone: SR.error,
                                id: "manhunt-location-approximate", settings: true)
            }
            if let refusal = store.refusal {
                ManhuntAlertRow(text: refusal, icon: "exclamationmark.circle", tone: SR.error, id: "manhunt-refusal")
            }
        }
    }

    private var areaCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            areaHeader
            areaPicture
            if room.isHost { hostControls }
            if let rule = state?.rule {
                Text(rule)
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if room.playing.count < 3 {
                Label("Needs three or more: one runner, two hunters.", systemImage: "person.3")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("manhunt-needs-three")
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("manhunt-area")
    }

    private var areaHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("PLAY AREA")
                .font(SR.Text.label())
                .tracking(SR.kickerTracking)
                .foregroundStyle(SR.accent)
            Spacer(minLength: 8)
            Text("\(ManhuntRules.distance(state?.radius ?? 500)) · \(state?.minutes ?? 30) min")
                .font(SR.Text.mono(13))
                .foregroundStyle(SR.inkSecondary)
        }
    }

    @ViewBuilder
    private var areaPicture: some View {
        if let area = state?.area {
            ManhuntMap(area: area, marks: [], interactive: false)
                .frame(height: 200)
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
            HStack(alignment: .top, spacing: 14) {
                ManhuntAreaPlaceholder(searching: store.centring)
                Text(room.isHost ? "The circle goes round where you stand. Go to the middle of where you will play, then centre it." :
                        "Waiting for \(room.host?.name ?? "the host") to set the play area.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("manhunt-area-missing")
            }
        }
    }

    private var centreTitle: String {
        if store.centring { return "Finding where you are…" }
        return state?.area == nil ? "Centre on me" : "Re-centre on me"
    }

    @ViewBuilder
    private var hostControls: some View {
        Button { store.centreHere() } label: {
            SRButtonLabel(title: centreTitle, icon: "location.fill", fill: true)
                .frame(minHeight: 48)
        }
        .srButton(state?.area == nil ? .prominent : .regular)
        .controlSize(.large)
        .disabled(store.centring || store.sending)
        .accessibilityIdentifier("manhunt-centre")
        HStack(spacing: 10) {
            Menu {
                ForEach(ManhuntSettings.radii, id: \.self) { m in
                    Button(ManhuntSettings.radiusLabel(m)) { store.setSize(radius: m) }
                }
            } label: {
                SRButtonLabel(title: "Size · \(ManhuntRules.distance(state?.radius ?? 500))", icon: "circle.dashed", fill: true)
                    .frame(minHeight: 48)
            }
            .srButton(.regular)
            .disabled(state?.area == nil)
            .accessibilityLabel("Size, \(ManhuntRules.distance(state?.radius ?? 500))")
            .accessibilityIdentifier("manhunt-size")
            Menu {
                ForEach(ManhuntSettings.lengths, id: \.self) { m in
                    Button("\(m) minutes") { store.setSize(minutes: m) }
                }
            } label: {
                SRButtonLabel(title: "Length · \(state?.minutes ?? 30) min", icon: "timer", fill: true)
                    .frame(minHeight: 48)
            }
            .srButton(.regular)
            .disabled(state?.area == nil)
            .accessibilityLabel("Length, \(state?.minutes ?? 30) minutes")
            .accessibilityIdentifier("manhunt-length")
        }
    }

    private var runnerCard: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Runner", trailing: state?.runnerPick.map { room.name(of: $0) } ?? "Drawn at the start")
            if room.isHost {
                DaydreamWrap(spacing: 8) {
                    chip("Draw at random", icon: "shuffle", selected: state?.runnerPick == nil, id: "manhunt-runner-random") {
                        store.pickRunner(nil)
                    }
                    ForEach(room.players.filter { $0.status == "joined" || $0.status == "invited" }) { player in
                        chip(player.id == room.meId ? "Me" : player.name, icon: "figure.run",
                             selected: state?.runnerPick == player.id, id: "manhunt-runner-\(player.id)") {
                            store.pickRunner(player.id)
                        }
                    }
                }
            } else {
                Text(state?.runnerPick == room.meId ? "You're the runner. Get ready to go." :
                        "The host picks who runs, or the start draws someone.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func chip(_ title: String, icon: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: selected ? "checkmark.circle.fill" : icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selected ? SR.accent : SR.inkMuted)
                Text(title)
                    .font(SR.Text.bodyMedium(16))
                    .foregroundStyle(selected ? SR.ink : SR.inkSecondary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .srGlassCard(selected ? .paper : .clear, radius: SR.Glass.innerRadius + 4, interactive: true)
            .overlay {
                RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous)
                    .strokeBorder(selected ? SR.accent : SR.line, lineWidth: selected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(store.sending)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

/// The empty play area: a dashed circle with a pin, searching while the
/// host's phone finds itself.
struct ManhuntAreaPlaceholder: View {
    let searching: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(SR.good, style: StrokeStyle(lineWidth: 2.5, dash: [5, 4]))
                .rotationEffect(.degrees(spin ? 360 : 0))
            Circle()
                .fill(SR.good.opacity(0.10))
                .padding(6)
            Image(systemName: searching ? "location.magnifyingglass" : "mappin.and.ellipse")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(SR.good)
        }
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)
        .onAppear { animate(searching) }
        .onChange(of: searching) { _, now in animate(now) }
    }

    private func animate(_ on: Bool) {
        guard !reduceMotion else { return }
        if on {
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { spin = true }
        } else {
            withAnimation(.smooth(duration: 0.3)) { spin = false }
        }
    }
}

// MARK: - Head start and hunt

/// Where the one to chase (or the nearest chaser) is from me.
struct ManhuntLead: Equatable {
    let name: String
    /// "140 m north-east".
    let whereabouts: String
    let metres: Double
    let live: Bool
}

struct ManhuntPlaying: View {
    let room: GameRoom
    @ObservedObject var store: ManhuntStore
    let done: () -> Void
    @State private var confirmingLeave = false
    /// Bumped by the map's button to frame the circle again.
    @State private var recentre = 0

    private var state: ManhuntState? { room.manhunt }
    private var phase: ManhuntPhase { ManhuntScreenPhase.of(room) }
    private var role: ManhuntRole? { state?.myRole }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                banner
                if phase == .headstart { headStartDial }
                if phase == .hunt, let claim = state?.claim { claimCard(claim) }
                if phase == .hunt { hud }
                mapBlock
                status
                people
                leaveButton
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
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .srAnimation(.snappy, value: state?.claim)
        .srAnimation(.snappy, value: store.runnerLive)
        .onChange(of: store.refusal) { _, refusal in
            if let refusal { announce(refusal) }
        }
        .onChange(of: phase) { _, next in
            if next == .hunt { announce(role == .runner ? "The hunt is on. Stay hidden." : "The hunt is on. Go and find them.") }
        }
        .onChange(of: state?.pings.count ?? 0) { old, new in
            if new > old, phase == .hunt { announce(pingAnnouncement) }
        }
        .onChange(of: state?.claim) { _, claim in
            if let claim { announce(claimLine(claim)) }
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
            Text(role == .runner ? "If the runner leaves, the hunters win." : "Your phone stops sharing where you are.")
        }
    }

    private func announce(_ text: String) {
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    // MARK: Who I am, and what to do now

    private var seat: ManhuntPlayKit.Seat {
        switch role {
        case .runner?: return .runner
        case .hunter?: return .hunter
        case nil: return .watching
        }
    }

    private var runnerName: String {
        guard let id = state?.runnerId else { return "the runner" }
        return id == room.meId ? "you" : room.name(of: id)
    }

    /// I am in trouble, or the runner is showing: the banner goes red.
    private var alarm: Bool {
        store.claimOnMe || (role == .runner && store.runnerLive)
    }

    private var banner: some View {
        ManhuntRoleBanner(
            kicker: kicker,
            headline: headline,
            line: nowLine,
            symbol: bannerSymbol,
            tone: bannerTone,
            alarm: alarm,
            radar: role != .runner
        )
    }

    private var bannerSymbol: String {
        switch role {
        case .runner?: return "figure.run"
        case .hunter?: return "binoculars.fill"
        case nil: return "eye.fill"
        }
    }

    private var bannerTone: Color {
        if alarm { return SR.errorOnDark }
        return role == .runner ? SR.accentOnDark : SR.accentInkOnDark
    }

    private var kicker: String {
        let who = role == .runner ? "YOU RUN" : role == .hunter ? "YOU HUNT" : "WATCHING"
        let level = GameDifficulty.label(for: room.difficulty).uppercased()
        return "MANHUNT · \(who) · \(level)"
    }

    private var headline: String {
        if phase == .headstart {
            return role == .runner ? "Run! Get away" : "Wait — the runner is getting away"
        }
        return ManhuntRules.headline(role: role, live: store.runnerLive, claimByMe: store.claimByMe, claimOnMe: store.claimOnMe)
    }

    private var nowLine: String {
        let name = runnerName == "you" ? "the runner" : runnerName
        return ManhuntPlayKit.nowLine(headstart: phase == .headstart, seat: seat, live: store.runnerLive,
                                      claimByMe: store.claimByMe, claimOnMe: store.claimOnMe,
                                      runnerName: name, lead: role == .hunter ? lead?.whereabouts : nil,
                                      catchM: state?.catchM ?? 25)
    }

    /// For a hunter: the runner, live or at the last ping. For the runner:
    /// the nearest hunter at the last ping. Nil without my own fix.
    private var lead: ManhuntLead? {
        guard let state, let me = state.seat(room.meId)?.fix else { return nil }
        let marks = state.marks(meId: room.meId)
        func measure(_ mark: ManhuntMark, live: Bool) -> ManhuntLead {
            let m = ManhuntPlayKit.metres(fromLat: me.lat, fromLng: me.lng, toLat: mark.fix.lat, toLng: mark.fix.lng)
            let b = ManhuntPlayKit.bearing(fromLat: me.lat, fromLng: me.lng, toLat: mark.fix.lat, toLng: mark.fix.lng)
            return ManhuntLead(name: mark.name, whereabouts: ManhuntPlayKit.whereabouts(metres: m, bearing: b), metres: m, live: live)
        }
        if role == .hunter {
            if let live = marks.first(where: { $0.kind == .runnerLive }) { return measure(live, live: true) }
            if let ping = marks.first(where: { $0.kind == .runnerPing }) { return measure(ping, live: false) }
            return nil
        }
        if role == .runner {
            let leads = marks.filter { $0.kind == .hunterPing }.map { measure($0, live: false) }
            return leads.filter { $0.metres.isFinite }.min { $0.metres < $1.metres }
        }
        return nil
    }

    private var pingAnnouncement: String {
        if role == .runner { return "Ping. The hunters can see where you were." }
        if let lead { return "Ping. \(lead.name) was \(lead.whereabouts)." }
        return "Ping. The runner's position is on the map."
    }

    // MARK: Clocks

    private var headStartDial: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let left = ManhuntRules.left(until: state?.phaseEndsAt, now: store.serverNow())
            ManhuntHeadStartDial(runner: role == .runner, ms: left, total: state?.headStartMs ?? 120_000)
        }
        .accessibilityIdentifier("manhunt-clock")
    }

    private var hud: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let now = store.serverNow()
            let pingLeft = ManhuntRules.left(until: state?.nextPingAt, now: now)
            ManhuntHuntClocks(
                timeLeft: ManhuntRules.left(until: state?.endsAt, now: now),
                timeTotal: Double(state?.minutes ?? 30) * 60_000,
                pingLeft: pingLeft,
                pingTotal: state?.pingMs ?? 180_000,
                pingLine: state?.lastPing.map { pingLine($0, now: now) }
            )
        }
    }

    private func pingLine(_ ping: ManhuntPing, now: Double?) -> String {
        let ago = ManhuntRules.left(until: now, now: ping.at).map { ManhuntRules.clock($0) } ?? "–"
        return role == .runner ? "Hunters last shown \(ago) ago." : "Runner last shown \(ago) ago."
    }

    // MARK: The claim

    private func claimCard(_ claim: ManhuntClaim) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            ManhuntClaimCard(
                title: claimTitle(claim),
                line: claimLine(claim),
                left: ManhuntRules.left(until: claim.deadline, now: store.serverNow()),
                total: state?.claimMs ?? 20_000,
                onMe: role == .runner
            )
        }
    }

    private func claimTitle(_ claim: ManhuntClaim) -> String {
        if claim.hunterId == room.meId { return "You claimed the catch" }
        return role == .runner ? "Caught?" : "Catch claimed"
    }

    /// The room's own claim window, in whole seconds ("20 seconds").
    private var claimSeconds: String {
        let seconds = max(1, Int(((state?.claimMs ?? 20_000) / 1000).rounded()))
        return seconds == 1 ? "1 second" : "\(seconds) seconds"
    }

    private func claimLine(_ claim: ManhuntClaim) -> String {
        if claim.hunterId == room.meId { return "You claimed the catch. Waiting for the runner to confirm — it stands in \(claimSeconds)." }
        let who = room.name(of: claim.hunterId)
        if role == .runner { return "\(who) says they caught you. Confirm it, or it stands in \(claimSeconds)." }
        return "\(who) claimed the catch."
    }

    // MARK: The map

    private var trail: [ManhuntFix] {
        guard role == .hunter, let pings = state?.pings, pings.count > 1 else { return [] }
        return Array(pings.dropLast().compactMap { $0.runner }.suffix(6))
    }

    @ViewBuilder
    private var mapBlock: some View {
        if let state {
            ZStack(alignment: .topTrailing) {
                ManhuntMap(area: state.area, marks: state.marks(meId: room.meId), trail: trail,
                           reachM: role == .hunter && phase == .hunt ? state.catchM : nil, recentre: recentre)
                    .accessibilityElement()
                    .accessibilityLabel(mapSpoken(state))
                    .accessibilityIdentifier("manhunt-map")
                recentreButton
            }
            .overlay(alignment: .bottomLeading) { legend }
            .containerRelativeFrame(.vertical) { length, _ in
                min(520, max(280, length * 0.5))
            }
            .clipShape(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                    .strokeBorder(SR.line, lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
    }

    private var recentreButton: some View {
        Button {
            SRHaptic.tap()
            recentre += 1
        } label: {
            Image(systemName: "scope")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(SR.ink)
                .frame(width: 52, height: 52)
                .background(Circle().fill(SR.surface.opacity(0.94)))
                .overlay(Circle().strokeBorder(SR.line, lineWidth: 1))
        }
        .buttonStyle(SRPressStyle())
        .padding(10)
        .accessibilityLabel("Show the whole play area")
        .accessibilityIdentifier("manhunt-recentre")
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendDot(Color(hex: ManhuntPinArt.meHex), "You")
            if role == .hunter {
                legendDot(Color(hex: SR.Fixed.accentInk), "Hunters")
                legendDot(Color(hex: SR.Fixed.accent), "Runner at ping")
            } else if role == .runner {
                legendDot(Color(hex: SR.Fixed.warn), "Hunters at ping")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(SR.surface.opacity(0.94)))
        .padding(10)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func legendDot(_ colour: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(colour)
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                .frame(width: 12, height: 12)
            Text(text)
                .font(SR.Text.mono(12))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
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
        var spoken = "Map of the play area showing " + GameNames.list(bits)
        if let lead { spoken += ". \(lead.name) is \(lead.whereabouts)" }
        return spoken
    }

    // MARK: Status

    @ViewBuilder
    private var status: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.locationOff {
                ManhuntAlertRow(text: "Location is off for the SR app, so the game cannot see you. Turn it on in Settings.",
                                icon: "location.slash", tone: SR.error, id: "manhunt-location-off", settings: true)
            } else if store.locationApproximate {
                ManhuntAlertRow(text: ManhuntRules.approximateLine, icon: "location.circle", tone: SR.error,
                                id: "manhunt-location-approximate", settings: true)
            }
            if let refusal = store.refusal {
                ManhuntAlertRow(text: refusal, icon: "exclamationmark.circle", tone: SR.error, id: "manhunt-refusal")
            }
            if let me = state?.seat(room.meId), me.fix?.outside == true {
                ManhuntAlertRow(text: role == .runner ? "You are outside the circle: the hunters can see you live." :
                                    "You are outside the circle. Head back in.",
                                icon: "exclamationmark.triangle.fill", tone: SR.warn, id: "manhunt-outside")
            }
            if state?.runnerQuiet == true, role == .hunter {
                Label("The runner's phone has gone quiet: a catch is taken on your word.", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("manhunt-quiet")
            }
        }
    }

    // MARK: The foot: Catch, or Confirm

    @ViewBuilder
    private var actionBar: some View {
        if phase == .hunt, store.claimOnMe {
            ManhuntActionFoot(hint: "Only if they really got you.") {
                Button { store.confirm() } label: {
                    ManhuntBigLabel(title: "Yes, I'm caught", icon: "checkmark")
                }
                .buttonStyle(ManhuntBigButtonStyle(fill: SR.error))
                .disabled(store.sending)
                .accessibilityIdentifier("manhunt-confirm")
            }
        } else if phase == .hunt, role == .hunter {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                catchFoot(now: store.serverNow())
            }
        }
    }

    private func catchFoot(now: Double?) -> some View {
        let cooling = ManhuntRules.left(until: state?.catchCooldownUntil, now: now) ?? 0
        let reach = ManhuntRules.distance(state?.catchM ?? 25)
        let hint: String
        if cooling > 0 {
            hint = "That one missed. Get closer, then try again."
        } else if let lead {
            hint = "\(lead.name): \(lead.whereabouts) · catch within \(reach)"
        } else {
            hint = "Get within \(reach) of the runner, then tap."
        }
        let title = cooling > 0 ? "Catch again in \(ManhuntPlayKit.secondsUp(cooling)) s" : "Catch!"
        return ManhuntActionFoot(hint: hint) {
            Button { store.catchNow() } label: {
                ManhuntBigLabel(title: title, icon: "hand.raised.fill")
            }
            .buttonStyle(ManhuntBigButtonStyle(fill: store.runnerLive ? SR.error : SR.accentDeep, glow: store.runnerLive))
            .disabled(!store.canCatch(now: now))
            .accessibilityLabel(title)
            .accessibilityHint("Tap when you are within \(Int(state?.catchM ?? 25)) metres of the runner.")
            .accessibilityIdentifier("manhunt-catch")
        }
    }

    // MARK: Players

    private var people: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Players", trailing: "\(state?.inHunt.count ?? 0) in")
            VStack(spacing: 0) {
                ForEach(Array((state?.inHunt ?? []).enumerated()), id: \.element.id) { index, seat in
                    if index > 0 { Divider().overlay(SR.divider) }
                    personRow(seat)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
        }
    }

    private func personRow(_ seat: ManhuntSeat) -> some View {
        let runner = seat.role == .runner
        return HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                GameInitial(name: seat.name, tone: runner ? SR.accent : SR.accentInk, side: 36)
                Image(systemName: runner ? "figure.run" : "binoculars.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(SR.paper)
                    .frame(width: 17, height: 17)
                    .background(Circle().fill(runner ? SR.accentDeep : SR.ink))
                    .offset(x: 3, y: 3)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(seat.name + (seat.id == room.meId ? " (you)" : ""))
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                Text(runner ? "Runner" : "Hunter")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
            Spacer(minLength: 8)
            if seat.fix != nil, seat.id != room.meId {
                SRGlassChip(text: "Live", icon: "dot.radiowaves.left.and.right", tone: runner ? SR.error : SR.good)
            }
        }
        .frame(minHeight: 56)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("manhunt-player-\(seat.id)")
    }

    private var leaveButton: some View {
        Button { confirmingLeave = true } label: {
            SRButtonLabel(title: "Leave the game", icon: "xmark", fill: true)
                .frame(minHeight: 44)
        }
        .srButton(.regular)
        .controlSize(.large)
        .disabled(store.busy)
        .accessibilityIdentifier("manhunt-leave")
    }
}

// MARK: - Play pieces

/// Who I am and what to do now, on the ink band: the kicker, the headline,
/// one plain line, and a moving emblem — a radar sweeping for a hunter,
/// ripples round a running figure for the runner, faster when in trouble.
struct ManhuntRoleBanner: View {
    let kicker: String
    let headline: String
    let line: String
    let symbol: String
    let tone: Color
    let alarm: Bool
    let radar: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(kicker)
                    .font(SR.Text.label())
                    .tracking(SR.inkKickerTracking)
                    .foregroundStyle(SR.onInk(.label))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(headline)
                    .font(SR.Text.display(28))
                    .foregroundStyle(alarm ? SR.errorOnDark : SR.cream)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("manhunt-headline")
                Text(line)
                    .font(SR.Text.secondary(15))
                    .foregroundStyle(SR.onInk(.note))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("manhunt-now")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ManhuntEmblem(symbol: symbol, tone: tone, radar: radar, fast: alarm)
        }
        .padding(SR.cardPadding + 2)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                    .fill(SR.band)
                RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                    .fill(RadialGradient(colors: [tone.opacity(alarm ? 0.45 : 0.30), Color.clear],
                                         center: .topTrailing, startRadius: 4, endRadius: 260))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                .strokeBorder(alarm ? tone.opacity(0.8) : SR.lineOnDark, lineWidth: alarm ? 2 : 1)
        }
        .accessibilityElement(children: .contain)
    }
}

/// The banner's moving picture, drawn in one Canvas on a 24 fps timeline that
/// stops under Reduce Motion and whenever the app is not in front.
struct ManhuntEmblem: View {
    let symbol: String
    let tone: Color
    /// A radar sweep (hunting) rather than ripples (running).
    let radar: Bool
    var fast: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || scenePhase != .active)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                draw(&context, size: size, t: t)
            }
        }
        .overlay {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(SR.cream)
        }
        .frame(width: 84, height: 84)
        .accessibilityHidden(true)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, t: Double) {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let r = min(size.width, size.height) / 2 - 1
        let speed: Double = fast ? 2.2 : 1
        // The rings: the radar's scale, or the ground the ripples cross.
        for i in 1...3 {
            let ring = r * CGFloat(i) / 3
            let rect = CGRect(x: centre.x - ring, y: centre.y - ring, width: ring * 2, height: ring * 2)
            context.stroke(Path(ellipseIn: rect), with: .color(SR.onInk(.hairline)), lineWidth: 1)
        }
        context.fill(Path(ellipseIn: CGRect(x: centre.x - r * 0.42, y: centre.y - r * 0.42, width: r * 0.84, height: r * 0.84)),
                     with: .color(tone.opacity(0.9)))
        if radar {
            let angle = (t * speed * 1.6).truncatingRemainder(dividingBy: 2 * .pi)
            var wedge = Path()
            wedge.move(to: centre)
            wedge.addArc(center: centre, radius: r, startAngle: .radians(angle - 0.9), endAngle: .radians(angle), clockwise: false)
            wedge.closeSubpath()
            context.fill(wedge, with: .color(tone.opacity(0.32)))
            var beam = Path()
            beam.move(to: centre)
            beam.addLine(to: CGPoint(x: centre.x + r * CGFloat(cos(angle)), y: centre.y + r * CGFloat(sin(angle))))
            context.stroke(beam, with: .color(tone), lineWidth: 2)
            // A blip that flares as the beam passes it.
            let blipAngle = 5.2
            var gap = (angle - blipAngle).truncatingRemainder(dividingBy: 2 * .pi)
            if gap < 0 { gap += 2 * .pi }
            let glow = max(0.15, 1 - gap / 2.5)
            let blip = CGPoint(x: centre.x + r * 0.7 * CGFloat(cos(blipAngle)), y: centre.y + r * 0.7 * CGFloat(sin(blipAngle)))
            context.fill(Path(ellipseIn: CGRect(x: blip.x - 4, y: blip.y - 4, width: 8, height: 8)),
                         with: .color(SR.cream.opacity(glow)))
        } else {
            for i in 0..<3 {
                var phase = (t * speed * 0.6 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                if phase < 0 { phase += 1 }
                let ring = r * (0.42 + 0.58 * CGFloat(phase))
                let rect = CGRect(x: centre.x - ring, y: centre.y - ring, width: ring * 2, height: ring * 2)
                context.stroke(Path(ellipseIn: rect), with: .color(tone.opacity(0.85 * (1 - phase))), lineWidth: 2.5)
            }
        }
    }
}

/// The head start's one big clock: a ring draining to the hunt.
struct ManhuntHeadStartDial: View {
    let runner: Bool
    let ms: Double?
    let total: Double

    @ScaledMetric(relativeTo: .largeTitle) private var dial: CGFloat = 196

    private var fraction: Double { ManhuntPlayKit.fraction(left: ms, total: total) }
    private var tone: Color { runner ? SR.accentOnDark : SR.accentInkOnDark }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(SR.onInk(.track), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: CGFloat(fraction))
                    .stroke(tone, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .srAnimation(.linear(duration: 1), value: fraction)
                VStack(spacing: 2) {
                    Text("HUNT STARTS IN")
                        .font(SR.Text.label())
                        .tracking(1.4)
                        .foregroundStyle(SR.onInk(.label))
                    Text(ms.map(ManhuntRules.clock) ?? "–")
                        .font(SR.Text.hero(54))
                        .foregroundStyle(SR.cream)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .padding(24)
            }
            .frame(width: min(dial, 250), height: min(dial, 250))
            Text(runner ? "Put the phone in your pocket and go. It keeps sending while the game runs." :
                    "Your map stays empty until the hunt begins.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.onInk(.note))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, SR.cardPadding)
        .background(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous).fill(SR.band))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hunt starts in \(ms.map(ManhuntRules.clock) ?? "a moment")")
    }
}

/// The hunt's two clocks, side by side, each a figure over a draining bar;
/// the ping clock turns amber (and the phone taps) in its last ten seconds.
struct ManhuntHuntClocks: View {
    let timeLeft: Double?
    let timeTotal: Double
    let pingLeft: Double?
    let pingTotal: Double
    let pingLine: String?

    private var soon: Bool { ManhuntPlayKit.pingSoon(pingLeft) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ManhuntClockTile(title: "Time left", ms: timeLeft, total: timeTotal, icon: "timer", id: "manhunt-clock")
                ManhuntClockTile(title: soon ? "Ping soon" : "Next ping", ms: pingLeft, total: pingTotal,
                                 icon: "dot.radiowaves.left.and.right", warn: soon, id: "manhunt-next-ping")
            }
            if let pingLine {
                Text(pingLine)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .accessibilityIdentifier("manhunt-last-ping")
            }
        }
        .onChange(of: soon) { _, now in
            if now { SRHaptic.tap() }
        }
    }
}

struct ManhuntClockTile: View {
    let title: String
    let ms: Double?
    let total: Double
    let icon: String
    var warn: Bool = false
    let id: String

    private var fraction: Double { ManhuntPlayKit.fraction(left: ms, total: total) }
    private var tint: Color { warn ? SR.warn : SR.accentInk }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .accessibilityHidden(true)
                Text(title.uppercased())
                    .font(SR.Text.label())
                    .tracking(1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(warn ? SR.warn : SR.inkMuted)
            Text(ms.map(ManhuntRules.clock) ?? "–")
                .font(SR.Text.figure(30))
                .foregroundStyle(warn ? SR.warn : SR.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Capsule()
                .fill(SR.line)
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(tint)
                        .scaleEffect(x: CGFloat(fraction), y: 1, anchor: .leading)
                }
                .srAnimation(.linear(duration: 1), value: fraction)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 12)
        .srGlassCard(.paper)
        .overlay {
            if warn {
                RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                    .strokeBorder(SR.warn, lineWidth: 2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
}

/// A catch is claimed: who, what happens next, and the twenty seconds
/// draining before it stands.
struct ManhuntClaimCard: View {
    let title: String
    let line: String
    let left: Double?
    let total: Double
    let onMe: Bool

    private var tone: Color { onMe ? SR.error : SR.accentInk }
    private var fraction: Double { ManhuntPlayKit.fraction(left: left, total: total) }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle().stroke(tone.opacity(0.2), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat(fraction))
                    .stroke(tone, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .srAnimation(.linear(duration: 1), value: fraction)
                Text("\(ManhuntPlayKit.secondsUp(left))")
                    .font(SR.Text.figure(20))
                    .foregroundStyle(tone)
                    .monospacedDigit()
            }
            .frame(width: 58, height: 58)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Label(title.uppercased(), systemImage: "hand.raised.fill")
                    .font(SR.Text.label())
                    .tracking(1.2)
                    .foregroundStyle(tone)
                Text(line)
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("manhunt-claim")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(SR.cardPadding)
        .background(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous).fill(tone.opacity(0.10)))
        .overlay {
            RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                .strokeBorder(tone, lineWidth: 2)
        }
        .transition(.scale(scale: 0.96).combined(with: .opacity))
        .accessibilityElement(children: .contain)
    }
}

/// A problem line with its icon, and — when the fix is in Settings — the
/// button that goes there.
struct ManhuntAlertRow: View {
    let text: String
    let icon: String
    let tone: Color
    let id: String
    var settings: Bool = false

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(text, systemImage: icon)
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(tone)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(id)
            if settings, let url = URL(string: UIApplication.openSettingsURLString) {
                Button {
                    SRHaptic.tap()
                    openURL(url)
                } label: {
                    SRButtonLabel(title: "Open Settings", icon: "gearshape", fill: false)
                        .frame(minHeight: 40)
                }
                .srButton(.regular)
                .accessibilityIdentifier("\(id)-settings")
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous).fill(tone.opacity(0.08)))
        .overlay {
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous)
                .strokeBorder(tone.opacity(0.5), lineWidth: 1)
        }
    }
}

/// The pinned foot under the scroll: one line of help over one big button.
struct ManhuntActionFoot<Content: View>: View {
    let hint: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 8) {
            Text(hint)
                .font(SR.Text.mono(13))
                .foregroundStyle(SR.inkSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            content
        }
        .padding(.horizontal, SR.gutter)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, ignoresSafeAreaEdges: .bottom)
        .overlay(alignment: .top) {
            Rectangle().fill(SR.divider).frame(height: 0.5)
        }
    }
}

/// The big button's words: a heavy symbol and a rounded headline.
struct ManhuntBigLabel: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .heavy))
            Text(title)
                .font(SR.Text.display(22))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

/// Catch and Confirm: a solid slab at least 64 points tall, full width,
/// that gives under the finger. Paper type on the fill holds its contrast
/// in both modes (the fill tokens are measured against paper). `glow`
/// breathes a ring round it — the runner is showing, go now.
struct ManhuntBigButtonStyle: ButtonStyle {
    var fill: Color
    var glow: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        ManhuntBigButtonBody(configuration: configuration, fill: fill, glow: glow)
    }
}

private struct ManhuntBigButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let fill: Color
    let glow: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 22, style: .continuous) }

    var body: some View {
        configuration.label
            .foregroundStyle(isEnabled ? SR.paper : SR.inkSecondary)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(shape.fill(isEnabled ? fill : SR.line))
            .overlay {
                if glow && isEnabled {
                    shape
                        .inset(by: -4)
                        .stroke(fill.opacity(breathe ? 0.15 : 0.6), lineWidth: 3)
                }
            }
            .contentShape(shape)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.85 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
            .onAppear { startBreathing() }
            .onChange(of: glow) { _, _ in startBreathing() }
    }

    private func startBreathing() {
        guard glow, !reduceMotion else { breathe = false; return }
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { breathe = true }
    }
}

// MARK: - How to play

/// The rules, as the room has them set: ping gap, head start, catch reach.
enum ManhuntGuide {
    static func steps(_ state: ManhuntState?) -> [ManhuntHowToStep] {
        let headStart = Int(((state?.headStartMs ?? 120_000) / 60_000).rounded())
        let ping = Int(((state?.pingMs ?? 180_000) / 60_000).rounded())
        let reach = ManhuntRules.distance(state?.catchM ?? 25)
        let claim = Int(((state?.claimMs ?? 20_000) / 1000).rounded())
        let headStartText = headStart == 1 ? "a one-minute" : "a \(headStart)-minute"
        let pingText = ping == 1 ? "Every minute" : "Every \(ping) minutes"
        return [
            ManhuntHowToStep(icon: "figure.run", title: "One runs, the rest hunt",
                             text: "The runner gets \(headStartText) head start. Hunters stay put and give them a fair go."),
            ManhuntHowToStep(icon: "dot.radiowaves.left.and.right", title: "Pings give you away",
                             text: "\(pingText) the hunters see where the runner was, and the runner sees where the hunters were."),
            ManhuntHowToStep(icon: "circle.dashed", title: "Stay in the circle",
                             text: "Step outside and the hunters see you live until you come back in."),
            ManhuntHowToStep(icon: "hand.raised.fill", title: "Catch them",
                             text: "Get within \(reach) and tap Catch. The runner owns up, or the catch stands after \(claim) seconds."),
            ManhuntHowToStep(icon: "timer", title: "Beat the clock",
                             text: "If time runs out before a catch, the runner wins."),
        ]
    }
}

struct ManhuntHowToStep: Identifiable {
    let icon: String
    let title: String
    let text: String
    var id: String { title }
}

struct ManhuntHowToList: View {
    let steps: [ManhuntHowToStep]
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 18) {
            ForEach(steps) { step in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: step.icon)
                        .font(.system(size: compact ? 15 : 18, weight: .bold))
                        .foregroundStyle(SR.paper)
                        .frame(width: compact ? 34 : 42, height: compact ? 34 : 42)
                        .background(Circle().fill(SR.accentDeep))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(SR.Text.title(compact ? 16 : 17))
                            .foregroundStyle(SR.ink)
                        Text(step.text)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct ManhuntHowToSheet: View {
    let state: ManhuntState?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Manhunt · how to play", title: "Hide and seek, with a map",
                             strap: "Played outdoors, three to eight of you. Every phone in the game shows only what its player is allowed to see.")
                ManhuntHowToList(steps: ManhuntGuide.steps(state))
                Label("Your position goes only to this game, only while it runs, and is never kept.", systemImage: "lock.fill")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    SRHaptic.tap()
                    dismiss()
                } label: {
                    SRButtonLabel(title: "Got it", icon: "checkmark", fill: true)
                        .frame(minHeight: 48)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .accessibilityIdentifier("manhunt-help-done")
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 24)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("manhunt-help-sheet")
    }
}

// MARK: - Finished

struct ManhuntFinished: View {
    let room: GameRoom
    @ObservedObject var store: ManhuntStore
    let done: () -> Void
    @State private var note: ManhuntRecordNote?
    /// This game is in the record: set once my standing has been counted.
    @State private var counted = false

    private var state: ManhuntState? { room.manhunt }
    private var mine: ManhuntStanding? { state?.standings?.first { $0.id == room.meId } }
    private var iWon: Bool { mine?.result == "won" || mine?.result == "team" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Manhunt · \(GameDifficulty.label(for: room.difficulty)) · final",
                             title: GameResults.title(room, solo: "Game over", none: "Game over"),
                             strap: GameResults.strap(room))
                ManhuntResultHero(outcome: state?.result?.outcome ?? "", line: outcomeLine, mine: myLine, won: iWon)
                if let note { ManhuntRecordCard(note: note) }
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
        .onAppear { countOnce() }
        // The table can land after the page does: count it when it comes.
        .onChange(of: mine?.result) { _, _ in countOnce() }
    }

    private var outcomeLine: String? {
        state?.outcomeLine(name: { $0 == room.meId ? "You" : room.name(of: $0) })
    }

    /// My part in it, in a few words.
    private var myLine: String? {
        guard let mine, let role = mine.role else { return nil }
        if role == .runner { return iWon ? "You ran, and you got away." : "You ran, and they got you." }
        if state?.result?.outcome == "caught", state?.result?.catcherId == room.meId { return "You hunted, and you made the catch." }
        return iWon ? "You hunted, and your side won." : "You hunted, and the runner got away."
    }

    /// Counts this game into the record on this phone, once. A watcher's
    /// page shows the record without counting; the demo counts into a
    /// throwaway record, so the reviewer's phone keeps none.
    private func countOnce() {
        guard !counted, let state else { return }
        let records = ManhuntRecordStore()
        guard let mine, let role = mine.role else {
            // Not (yet) in the table: show the record without counting.
            if note == nil, !SRDemo.isOn {
                let record = records.load()
                if record.games > 0 { note = ManhuntRecordNote(record: record, headline: nil) }
            }
            return
        }
        counted = true
        let token = "\(room.id)-\(String(format: "%.0f", state.startedAt ?? 0))"
        let madeCatch = state.result?.outcome == "caught" && state.result?.catcherId == room.meId
        if SRDemo.isOn {
            var record = ManhuntRecord()
            note = record.record(token: token, runner: role == .runner, won: iWon, madeCatch: madeCatch)
        } else {
            note = records.record(token: token, runner: role == .runner, won: iWon, madeCatch: madeCatch)
        }
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

/// How it ended, as a picture: a hand for a catch, a running figure for an
/// escape, a flag when someone left — on the ink band, with the sentence.
struct ManhuntResultHero: View {
    let outcome: String
    let line: String?
    let mine: String?
    let won: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private var symbol: String {
        switch outcome {
        case "caught": return "hand.raised.fill"
        case "time": return "figure.run"
        default: return "flag.checkered"
        }
    }

    private var word: String {
        switch outcome {
        case "caught": return "CAUGHT!"
        case "time": return "GOT AWAY!"
        default: return "GAME OVER"
        }
    }

    private var tone: Color { outcome == "caught" ? SR.accentInkOnDark : SR.accentOnDark }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            emblem
            VStack(alignment: .leading, spacing: 6) {
                Text(word)
                    .font(SR.Text.hero(30))
                    .foregroundStyle(tone)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityHidden(true)
                if let line {
                    Text(line)
                        .font(SR.Text.bodyMedium(16))
                        .foregroundStyle(SR.cream)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("manhunt-outcome")
                }
                if let mine {
                    Label(mine, systemImage: won ? "star.fill" : "heart.fill")
                        .font(SR.Text.secondary())
                        .foregroundStyle(won ? SR.goodOnDark : SR.onInk(.note))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("manhunt-my-result")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(SR.cardPadding + 2)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous).fill(SR.band)
                RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                    .fill(RadialGradient(colors: [tone.opacity(0.35), Color.clear], center: .leading, startRadius: 4, endRadius: 240))
            }
        }
        .accessibilityElement(children: .contain)
        .onAppear {
            if reduceMotion { shown = true } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1)) { shown = true }
            }
        }
    }

    private var emblem: some View {
        ZStack {
            Circle().fill(tone.opacity(0.22))
            Circle().strokeBorder(tone, lineWidth: 3)
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(SR.cream)
        }
        .frame(width: 80, height: 80)
        .scaleEffect(shown ? 1 : 0.4)
        .rotationEffect(.degrees(shown ? 0 : -25))
        .opacity(shown ? 1 : 0)
        .accessibilityHidden(true)
    }
}

/// My record at Manhunt on this phone, with what this game changed.
struct ManhuntRecordCard: View {
    let note: ManhuntRecordNote

    private var record: ManhuntRecord { note.record }

    var body: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Your record", trailing: record.games == 1 ? "1 game" : "\(record.games) games")
            VStack(alignment: .leading, spacing: 12) {
                if let headline = note.headline {
                    Label(headline, systemImage: "sparkles")
                        .font(SR.Text.title())
                        .foregroundStyle(SR.accent)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("manhunt-record-new")
                }
                HStack(spacing: 10) {
                    tile("Escapes", "\(record.escapes)", detail: record.runs == 1 ? "of 1 run" : "of \(record.runs) runs", icon: "figure.run")
                    tile("Catches", "\(record.catches)", detail: record.hunts == 1 ? "in 1 hunt" : "in \(record.hunts) hunts", icon: "hand.raised.fill")
                }
                HStack(spacing: 10) {
                    tile("Wins", "\(record.wins)", detail: "as either side", icon: "star.fill")
                    tile("Best streak", "\(record.bestStreak)", detail: "wins in a row", icon: "flame.fill")
                }
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("manhunt-record")
    }

    private func tile(_ title: String, _ value: String, detail: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title.uppercased(), systemImage: icon)
                .font(SR.Text.label())
                .tracking(1)
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(SR.Text.figure(28))
                .foregroundStyle(SR.ink)
                .monospacedDigit()
            Text(detail)
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous).fill(SR.accentInk.opacity(0.07)))
        .accessibilityElement(children: .combine)
    }
}
