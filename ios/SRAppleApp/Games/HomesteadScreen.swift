import SwiftUI
import UIKit

/// One Homestead room, from lobby to the last point.
///
/// The lobby and the 3-2-1 are every game's (`GameLobby`, `GameCountdownView`);
/// the lobby's panel is a picture of the island and how to play, and Start
/// waits for three. Play is a turn card (whose move in their colour, its
/// deadline, the dice and their total), a strip of everyone's points racing to
/// the target, the island — pan, pinch, tap a lit spot — a one-line hint, and
/// the bar: big build buttons with each piece drawn in my colour, then the one
/// move the room is waiting on as a wide button (or whose move it is, when it
/// is not mine) beside square Hand, Trade, Bank and Log buttons. A roll, my
/// turn coming round and a point scored each get a moment over the island.
/// Hand, bank, trade and log are sheets; the discard after a 7 is a sheet that
/// will not close until the cards are put back; how to play is a card over the
/// table, from the bar's question mark. The finish is my result, the table,
/// this phone's record, the final island and the log.
struct HomesteadScreen: View {
    let roomId: String
    @StateObject private var store: HomesteadStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(roomId: String) {
        self.roomId = roomId
        _store = StateObject(wrappedValue: HomesteadStore(roomId: roomId))
    }

    var body: some View {
        content
            .navigationTitle("Homestead")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar(immersive ? .hidden : .visible, for: .navigationBar)
            .statusBarHidden(immersive)
            .onAppear { store.open() }
            .onDisappear { store.close() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.open() } else if phase == .background { store.close() }
            }
            .overlay(alignment: .top) {
                if let message = store.message, !immersive { SRBanner(text: message) }
            }
    }

    private var immersive: Bool {
        guard !store.ended, let room = store.room else { return false }
        return HomesteadScreenPhase.of(room) == .countdown
    }

    @ViewBuilder
    private var content: some View {
        if store.ended {
            GameEndedView(id: "homestead-ended", done: { dismiss() })
        } else if let room = store.room {
            switch HomesteadScreenPhase.of(room) {
            case .lobby, .unknown:
                GameLobby(room: room, store: store, prefix: "homestead", done: { dismiss() },
                          panel: AnyView(HomesteadTableCard(room: room)),
                          startBlocked: room.playing.count < 3 || room.playing.count > 5)
            case .countdown:
                GameCountdownView(room: room, store: store,
                                  note: "Everyone places two cottages and two roads first: there, then back again.",
                                  id: "homestead-countdown")
            case .playing:
                if let state = room.homestead {
                    HomesteadPlaying(room: room, state: state, store: store)
                } else {
                    HomesteadLoading()
                }
            case .finished:
                HomesteadFinished(room: room, store: store, done: { dismiss() })
            case .closed:
                GameEndedView(id: "homestead-ended", done: { dismiss() })
            }
        } else {
            HomesteadLoading()
        }
    }
}

/// While the room is on its way: the island picture and a spinner.
struct HomesteadLoading: View {
    var body: some View {
        VStack(spacing: 16) {
            HomesteadIslandArt(side: 96)
            ProgressView().tint(SR.accent)
            Text("Rowing out to the island…")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .srPaper()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading Homestead")
    }
}

// MARK: - Lobby

/// The rules the host picked, a picture of the island, how to play, and that
/// it needs three.
struct HomesteadTableCard: View {
    let room: GameRoom

    var body: some View {
        let state = room.homestead
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                HomesteadIslandArt(side: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text((state.map(HomesteadText.rules) ?? GameDifficulty.label(for: room.difficulty)).uppercased())
                        .font(SR.Text.label())
                        .tracking(SR.kickerTracking)
                        .foregroundStyle(SR.accent)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(state?.island?.label ?? "The island")
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                    Text(state?.rule ?? "Roll for resources, build roads, cottages and towns, trade with each other. First to the points on their own turn wins.")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if room.playing.count < 3 {
                needsMore
            }
            HomesteadHowToPlay(target: state?.vpTarget)
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("homestead-table")
    }

    /// Three seats, filled as people join: Start waits for all three.
    private var needsMore: some View {
        let count = room.playing.count
        return HStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: i < count ? "person.fill" : "person")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(i < count ? SR.accentInk : SR.inkGhost)
                }
            }
            .accessibilityHidden(true)
            Text(count == 2 ? "Needs one more player." : "Needs three players.")
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("homestead-needs-three")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                .fill(SR.accent.opacity(0.1))
        )
    }
}

/// How to play, in five lines a child can follow. In the lobby and behind the
/// bar's question mark.
struct HomesteadHowToPlay: View {
    /// The room's target; nil before the room says.
    let target: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HOW TO PLAY")
                .font(SR.Text.label())
                .tracking(SR.kickerTracking)
                .foregroundStyle(SR.inkSecondary)
            row("dice.fill", tint: HomesteadPalette.outline,
                "Roll the dice. Every hex showing that number pays its resource to the cottages and towns on its corners.")
            row("house.fill", tint: HomesteadPalette.colour(.red),
                "Spend resources to build roads, cottages (1 point) and towns (2 points). New cottages need a road to them.")
            row("arrow.left.arrow.right", tint: HomesteadPalette.colour(.blue),
                "Trade with the family on your turn, or with the bank: 4 for 1, or better at a harbour.")
            row("pawprint.fill", tint: HomesteadPalette.fox,
                "A 7 moves the fox. It blocks a hex and steals a card. Holding more than 7 cards? Put half back.")
            row("trophy.fill", tint: Color(hex: 0xC79A00), "First to \(goal) on their own turn wins.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("homestead-how-to-play")
    }

    private var goal: String {
        guard let target else { return "the target" }
        return "\(target) points"
    }

    private func row(_ icon: String, tint: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(tint))
                .accessibilityHidden(true)
            Text(text)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Playing

/// A short moment over the island: a roll, my turn, a point.
struct HomesteadToast: Identifiable, Equatable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String?
    let tint: Color

    static func == (a: HomesteadToast, b: HomesteadToast) -> Bool { a.id == b.id }

    /// The roll's toast: the fox's colour on a 7.
    static func roll(_ state: HomesteadState, name: (String) -> String) -> HomesteadToast? {
        guard let line = HomesteadMoments.roll(state, name: name) else { return nil }
        let seven = state.dice?.total == 7
        return HomesteadToast(icon: seven ? "pawprint.fill" : "dice.fill", title: line.title, detail: line.detail,
                              tint: seven ? HomesteadPalette.fox : HomesteadPalette.outline)
    }
}

struct HomesteadPlaying: View {
    let room: GameRoom
    let state: HomesteadState
    @ObservedObject var store: HomesteadStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var toast: HomesteadToast?
    @State private var helping = false

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // At accessibility sizes the controls cannot all fit under a
                // board that fills the screen: the board takes a fixed height
                // and the whole play area scrolls, so Roll and End turn are
                // always reachable.
                ScrollView { playArea(board: AnyView(board.frame(height: 300))) }
                    .scrollBounceBehavior(.basedOnSize)
            } else {
                playArea(board: AnyView(board.frame(minHeight: 200, maxHeight: .infinity)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .srGround(.warm)
        .overlay { helpCard }
        .accessibilityIdentifier("homestead-playing")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    SRHaptic.select()
                    setHelping(true)
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("How to play")
                .accessibilityIdentifier("homestead-help")
            }
        }
        .onChange(of: store.refusal) { _, refusal in
            if let refusal { UIAccessibility.post(notification: .announcement, argument: refusal) }
        }
        .onChange(of: store.rollSerial) { _, _ in rolled() }
        .onChange(of: state.activeId) { _, active in turnChanged(to: active) }
        .onChange(of: state.me?.vp) { old, new in pointsChanged(from: old, to: new) }
        .onChange(of: store.mustDiscard) { _, owing in if owing { setHelping(false) } }
        .task(id: toast?.id) {
            guard toast != nil else { return }
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { toast = nil }
        }
        .sheet(item: $store.sheet) { sheet in
            switch sheet {
            case .hand: HomesteadHandSheet(state: state, store: store)
            case .bank: HomesteadBankSheet(state: state, store: store)
            case .trade: HomesteadTradeSheet(room: room, state: state, store: store)
            case .log: HomesteadLogSheet(state: state)
            case .discard:
                HomesteadDiscardSheet(state: state, store: store)
                    .interactiveDismissDisabled()
            }
        }
        .confirmationDialog(
            "Take a card from…",
            isPresented: Binding(get: { store.foxAsk != nil }, set: { if !$0 { store.foxAsk = nil } }),
            titleVisibility: .visible
        ) {
            ForEach(store.foxAsk?.victims ?? [], id: \.self) { id in
                Button(state.player(id)?.name ?? "Someone") { store.robFrom(id) }
            }
            Button("Cancel", role: .cancel) { store.foxAsk = nil }
        }
    }

    private var board: some View {
        HomesteadBoardView(state: state, lit: store.lit, interactive: !store.sending, onTap: { store.tap($0) })
    }

    private func playArea(board: AnyView) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HomesteadTurnCard(room: room, state: state, store: store)
            HomesteadStrip(state: state, now: { store.serverNow() })
            board
                .overlay(alignment: .top) { refusal }
                .overlay(alignment: .bottom) { toastView }
            status
            HomesteadActionBar(state: state, store: store)
        }
    }

    private func name(_ id: String) -> String { id == state.meId ? "You" : room.name(of: id) }

    // MARK: Moments

    private func show(_ next: HomesteadToast, announce: Bool) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.78)) { toast = next }
        if announce {
            let line = next.title + (next.detail.map { ". \($0)" } ?? "")
            UIAccessibility.post(notification: .announcement, argument: line)
        }
    }

    private func rolled() {
        guard let next = HomesteadToast.roll(state, name: name) else { return }
        let seven = state.dice?.total == 7
        // Wait for the dice to land, so the toast does not give the roll away
        // while they tumble (HomesteadDiceView); at once under Reduce Motion.
        let delay: Double = reduceMotion ? 0 : HomesteadDiceView.tumbleTime
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if seven { SRHaptic.bad() }
            show(next, announce: true)
        }
    }

    private func turnChanged(to active: String?) {
        guard state.phase == .playing, store.seated, let active, active == state.meId else { return }
        show(HomesteadToast(icon: "sparkles", title: "Your turn!", detail: HomesteadMoments.turnDetail(state.step),
                            tint: SR.accent), announce: false)
    }

    private func pointsChanged(from old: Int?, to new: Int?) {
        guard let line = HomesteadMoments.points(from: old, to: new, target: state.vpTarget) else { return }
        show(HomesteadToast(icon: "star.fill", title: line.title, detail: line.detail, tint: SR.good), announce: true)
    }

    private func setHelping(_ on: Bool) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { helping = on }
    }

    // MARK: Overlays

    @ViewBuilder
    private var refusal: some View {
        if let refusal = store.refusal {
            Label(refusal, systemImage: "exclamationmark.circle")
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Capsule().fill(SR.error.opacity(0.94)))
                .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
                .padding(8)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
                .accessibilityIdentifier("homestead-refusal")
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            HStack(spacing: 12) {
                Image(systemName: toast.icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(toast.tint))
                VStack(alignment: .leading, spacing: 1) {
                    Text(toast.title)
                        .font(SR.Text.title(17))
                        .foregroundStyle(SR.ink)
                    if let detail = toast.detail {
                        Text(detail)
                            .font(SR.Text.secondary(13))
                            .foregroundStyle(SR.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(SR.surface.opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(toast.tint.opacity(0.5), lineWidth: 1.5)
            )
            .shadow(color: Color.black.opacity(0.22), radius: 10, x: 0, y: 4)
            .padding(10)
            .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .bottom).combined(with: .opacity))
            .id(toast.id)
            .allowsHitTesting(false)
            // Said aloud as an announcement when it matters; not a stop on the way round.
            .accessibilityHidden(true)
            .accessibilityIdentifier("homestead-toast")
        }
    }

    @ViewBuilder
    private var helpCard: some View {
        if helping {
            ZStack {
                Color.black.opacity(0.38)
                    .ignoresSafeArea()
                    .onTapGesture { setHelping(false) }
                    .accessibilityHidden(true)
                ViewThatFits(in: .vertical) {
                    helpBody
                    ScrollView { helpBody }
                }
                .background(
                    RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                        .fill(SR.surface)
                )
                .shadow(color: Color.black.opacity(0.25), radius: 18, x: 0, y: 8)
                .frame(maxWidth: 520)
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
            }
            .transition(.opacity)
            // One modal container, so VoiceOver stays in the card until it closes.
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityIdentifier("homestead-help-card")
        }
    }

    private var helpBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                HomesteadIslandArt(side: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Homestead")
                        .font(SR.Text.display(22))
                        .foregroundStyle(SR.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(HomesteadText.rules(state))
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            HomesteadHowToPlay(target: state.vpTarget)
            Button {
                SRHaptic.tap()
                setHelping(false)
            } label: {
                Text("GOT IT")
                    .font(SR.Text.title(16))
                    .tracking(1)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .accessibilityIdentifier("homestead-help-done")
        }
        .padding(20)
    }

    // MARK: The hint under the island

    /// One line under the board: what a tap does now, or the best hint.
    @ViewBuilder
    private var status: some View {
        if let line = statusLine {
            let quiet = store.lit.isEmpty
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: quiet ? "lightbulb.fill" : "hand.tap.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(quiet ? SR.inkMuted : HomesteadPalette.lit)
                    .accessibilityHidden(true)
                Text(line)
                    .font(quiet ? SR.Text.secondary() : SR.Text.bodyMedium(15))
                    .foregroundStyle(quiet ? SR.inkMuted : SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("homestead-status")
        }
    }

    private var statusLine: String? {
        guard store.seated else { return "You are watching this one." }
        switch state.step {
        case .setup?:
            guard state.isMyTurn else { return nil }
            return state.setup?.need == .road ? "Tap a lit side next to your new cottage." : "Tap a lit corner. Cottages need a gap of two sides."
        case .fox?:
            return state.isMyTurn ? "Tap a lit hex to move the fox there." : nil
        case .roads?:
            return state.isMyTurn ? "Tap a lit side for a free road (\(state.freeRoads) left)." : nil
        case .main?:
            if let picked = store.picked {
                return state.legal.spots(for: picked).isEmpty ? "Nowhere to put a \(picked.rawValue) right now." : "Tap a lit spot for your \(picked.rawValue)."
            }
            if let hints = state.hints, !hints.affordable.isEmpty {
                return "You can afford: " + hints.affordable.map(HomesteadPlaying.costName).joined(separator: ", ") + "."
            }
            if state.hard, state.isMyTurn { return "Pick a piece to see where it can go." }
            return nil
        default:
            return nil
        }
    }

    static func costName(_ key: String) -> String {
        key == "card" ? "an almanac card" : "a \(key)"
    }
}

// MARK: - The turn card

/// Whose move it is, big and in their colour: their mark, the headline, the
/// deadline, and the dice on the right.
struct HomesteadTurnCard: View {
    let room: GameRoom
    let state: HomesteadState
    @ObservedObject var store: HomesteadStore
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Me to act: my turn, or a discard I owe.
    private var mine: Bool { state.isMyTurn || state.myDiscard > 0 }

    private var tint: Color {
        if mine { return SR.accent }
        return HomesteadPalette.colour(state.activeId.flatMap { state.colour(of: $0) })
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    whoseMark
                    Text("TURN \(max(1, state.turn)) · \(state.vpTarget) TO WIN" + (state.isAsync ? " · OVER DAYS" : ""))
                        .font(SR.Text.label())
                        .tracking(1.2)
                        .foregroundStyle(mine ? SR.accentInk : SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(HomesteadText.headline(state, name: { $0 == state.meId ? "You" : room.name(of: $0) }))
                    .font(SR.Text.display(typeSize.isAccessibilitySize ? 20 : 21))
                    .foregroundStyle(mine ? SR.accentInk : SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("homestead-headline")
                HomesteadDeadline(state: state, now: { store.serverNow() })
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            HomesteadDiceView(dice: state.dice, serial: store.rollSerial, side: typeSize.isAccessibilitySize ? 30 : 34)
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(tint.opacity(mine ? 0.16 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(tint.opacity(mine ? 0.8 : 0.35), lineWidth: mine ? 2 : 1)
        )
        // A bar of the colour of whoever the room waits on, down the leading edge.
        .overlay(alignment: .leading) {
            Capsule()
                .fill(tint)
                .frame(width: 5)
                .padding(.vertical, 14)
                .padding(.leading, 7)
        }
        .srAnimation(.smooth(duration: 0.35), value: state.activeId)
    }

    /// The mark of whoever the room waits on; a star when it is me.
    @ViewBuilder
    private var whoseMark: some View {
        if mine {
            Image(systemName: state.myDiscard > 0 ? "tray.and.arrow.up.fill" : "star.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(SR.accent)
                .accessibilityHidden(true)
        } else if let colour = state.activeId.flatMap({ state.colour(of: $0) }) {
            HomesteadSeatMark(colour: colour, side: 16)
                .accessibilityHidden(true)
        }
    }
}

/// "Your move · 0:42 left" for whoever the room waits on, ticking.
struct HomesteadDeadline: View {
    let state: HomesteadState
    let now: () -> Double?

    var body: some View {
        if let end = state.phaseEndsAt, state.phase == .playing {
            TimelineView(.periodic(from: .now, by: state.isAsync ? 30 : 1)) { _ in
                if let now = now() {
                    let left = max(0, end - now)
                    let urgent = left < 15_000
                    Label(text(left), systemImage: urgent ? "timer.circle.fill" : "timer")
                        .font(urgent ? SR.monoBold() : SR.Text.mono())
                        .foregroundStyle(urgent ? SR.error : SR.inkMuted)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("homestead-deadline")
                }
            }
        }
    }

    private func text(_ left: Double) -> String {
        let waiting = state.waitingOn
        let who: String
        if waiting.contains(state.meId) {
            who = "Your move"
        } else if waiting.count == 1, let p = state.player(waiting[0]) {
            who = p.name
        } else {
            who = "Everyone"
        }
        return "\(who) · \(HomesteadText.timeLeft(left)) left"
    }
}

// MARK: - The strip of players

/// Everyone at the table: colour and mark, points racing to the target, cards,
/// almanac cards, and the two awards. The player whose move it is is lit in
/// their colour, and the strip scrolls to them.
struct HomesteadStrip: View {
    let state: HomesteadState
    let now: () -> Double?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(state.seated) { player in
                        chip(player)
                            .id(player.id)
                    }
                }
                .padding(.vertical, 2)
            }
            .onChange(of: state.activeId) { _, active in
                guard let active else { return }
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(active, anchor: .center) }
            }
            .onAppear {
                if let active = state.activeId { proxy.scrollTo(active, anchor: .center) }
            }
        }
        .accessibilityIdentifier("homestead-strip")
    }

    private func chip(_ p: HomesteadPlayer) -> some View {
        let active = p.id == state.activeId
        let me = p.id == state.meId
        let points = me ? (state.me?.vp ?? p.publicVp) : p.publicVp
        let colour = HomesteadPalette.colour(p.colour)
        return HStack(spacing: 8) {
            HomesteadSeatMark(colour: p.colour, side: 28)
            VStack(alignment: .leading, spacing: 3) {
                chipTitle(p, me: me, active: active)
                chipFigures(p, points: points)
                progress(points: points, colour: colour)
                if let owed = state.discardOwed[p.id], owed > 0 {
                    Text("Puts back \(owed)")
                        .font(SR.monoBold())
                        .foregroundStyle(SR.error)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(active ? colour.opacity(0.16) : SR.surface.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(active ? colour : SR.line, lineWidth: active ? 2.5 : 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(p, points: points, me: me, active: active))
        .accessibilityIdentifier("homestead-player-\(p.id)")
    }

    private func chipTitle(_ p: HomesteadPlayer, me: Bool, active: Bool) -> some View {
        HStack(spacing: 4) {
            if active {
                Image(systemName: "hourglass")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(HomesteadPalette.colour(p.colour))
            }
            Text(me ? "You" : p.name)
                .font(SR.Text.title(15))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
            if p.longestTrail {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(SR.accent)
                    .accessibilityLabel("Longest Trail")
            }
            if p.chiefRanger {
                Image(systemName: "figure.hiking")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(SR.accent)
                    .accessibilityLabel("Chief Ranger")
            }
            if p.away {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(SR.inkMuted)
                    .accessibilityLabel("Away")
            }
        }
    }

    private func chipFigures(_ p: HomesteadPlayer, points: Int) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                Image(systemName: "star.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(hex: 0xC79A00))
                Text("\(points)").font(SR.monoBold()).foregroundStyle(SR.ink)
            }
            HStack(spacing: 2) {
                Image(systemName: "rectangle.portrait.on.rectangle.portrait.fill").font(.system(size: 10, weight: .bold))
                Text("\(p.handCount)").font(SR.Text.mono())
            }
            .foregroundStyle(SR.inkMuted)
            if p.cardCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "book.closed.fill").font(.system(size: 10, weight: .bold))
                    Text("\(p.cardCount)").font(SR.Text.mono())
                }
                .foregroundStyle(SR.inkMuted)
            }
        }
        .lineLimit(1)
    }

    /// Points against the target, as a bar in the player's colour.
    private func progress(points: Int, colour: Color) -> some View {
        let width: CGFloat = 92
        let share = HomesteadMoments.share(points, of: state.vpTarget)
        return Capsule()
            .fill(SR.line)
            .frame(width: width, height: 5)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(colour)
                    .frame(width: max(5, width * CGFloat(share)), height: 5)
            }
            .srAnimation(.smooth(duration: 0.5), value: points)
    }

    private func spoken(_ p: HomesteadPlayer, points: Int, me: Bool, active: Bool) -> String {
        var bits = [me ? "You" : p.name, p.colour?.label ?? "", "\(points) of \(state.vpTarget) points", "\(p.handCount) cards"]
        if p.cardCount > 0 { bits.append("\(p.cardCount) almanac cards") }
        if p.longestTrail { bits.append("Longest Trail") }
        if p.chiefRanger { bits.append("Chief Ranger") }
        if p.away { bits.append("away") }
        if let owed = state.discardOwed[p.id], owed > 0 { bits.append("puts back \(owed)") }
        if active { bits.append("their move") }
        return bits.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

// MARK: - The action bar

struct HomesteadActionBar: View {
    let state: HomesteadState
    @ObservedObject var store: HomesteadStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var myColour: HomesteadColour? { state.myself?.colour }

    /// How the move and the tools share a row: roomy (labels beside icons),
    /// snug (labels under them, narrower squares — a small phone with four
    /// tools), or stacked (the move on its own row, at large text).
    private enum Fit { case roomy, snug, stacked }

    var body: some View {
        VStack(spacing: 8) {
            if store.canBuild { buildRow }
            if typeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    primary(.stacked)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        tools(.stacked)
                    }
                }
            } else {
                // One row whenever it fits, so the island keeps its height.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        primary(.roomy)
                        tools(.roomy)
                    }
                    HStack(spacing: 6) {
                        primary(.snug)
                        tools(.snug)
                    }
                    VStack(spacing: 8) {
                        primary(.stacked)
                        HStack(spacing: 8) { tools(.stacked) }
                    }
                }
            }
        }
    }

    // MARK: The move the room is waiting on

    /// Roll, End turn, Skip, Put back — the one move the step is waiting on;
    /// or, when there is none for me, whose move it is.
    @ViewBuilder
    private func primary(_ fit: Fit) -> some View {
        if store.mustDiscard {
            big("Put back cards", icon: "tray.and.arrow.up.fill", id: "homestead-discard", fit: fit) { store.show(.discard) }
        } else if state.legal.canRoll {
            big("Roll", icon: "dice.fill", id: "homestead-roll", fit: fit, beckons: true) { store.roll() }
        } else if state.step == .roads, state.isMyTurn {
            big("Skip", icon: "forward.fill", id: "homestead-skip", fit: fit) { store.skip() }
        } else if state.legal.canEnd {
            big("End turn", icon: "checkmark", id: "homestead-end", fit: fit) { store.end() }
        } else {
            waiting
        }
    }

    /// The move, as the one lit button on the bar: accent, 56 points tall.
    private func big(_ title: String, icon: String, id: String, fit: Fit, beckons: Bool = false,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            bigLabel(title, icon: icon, fit: fit, beckons: beckons)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: [SR.accent, SR.accentDeep], startPoint: .top, endPoint: .bottom))
                )
                .shadow(color: SR.accentDeep.opacity(0.35), radius: 6, x: 0, y: 3)
                .opacity(store.sending ? 0.7 : 1)
        }
        .buttonStyle(SRPressStyle())
        .disabled(store.sending)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder
    private func bigLabel(_ title: String, icon: String, fit: Fit, beckons: Bool) -> some View {
        let glyph = Group {
            if store.sending {
                ProgressView().tint(Color.white)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .symbolEffect(.pulse, isActive: beckons && !reduceMotion)
            }
        }
        if fit == .snug {
            VStack(spacing: 2) {
                glyph
                Text(title.uppercased())
                    .font(SR.Text.label(13))
                    .tracking(0.6)
                    .lineLimit(1)
                    .fixedSize()
            }
        } else {
            HStack(spacing: 10) {
                glyph
                Text(title.uppercased())
                    .font(SR.Text.title(16))
                    .tracking(0.8)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    /// Not a button: whose move it is, in their colour.
    private var waiting: some View {
        let active = state.player(state.activeId)
        let line: String
        if state.isMyTurn {
            line = "Your move: tap the island"
        } else if state.step == .discard {
            line = "Waiting for discards"
        } else if let active {
            line = "\(active.name)'s move"
        } else {
            line = "Waiting…"
        }
        return HStack(spacing: 10) {
            if state.isMyTurn {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(HomesteadPalette.lit)
            } else if let active, state.step != .discard {
                HomesteadSeatMark(colour: active.colour, side: 26)
            } else {
                Image(systemName: "hourglass")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(SR.inkMuted)
            }
            Text(line)
                .font(SR.Text.title(16))
                .foregroundStyle(SR.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(SR.surface.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(SR.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("homestead-waiting")
    }

    // MARK: Hand, Trade, Bank, Log

    @ViewBuilder
    private func tools(_ fit: Fit) -> some View {
        tool("Hand", icon: "rectangle.stack.fill", badge: state.me.map { "\($0.hand.total)" }, id: "homestead-hand", fit: fit) {
            store.show(.hand)
        }
        if state.legal.canTrade || !state.openOffers.isEmpty {
            tool("Trade", icon: "arrow.left.arrow.right", badge: state.openOffers.isEmpty ? nil : "\(state.openOffers.count)",
                 id: "homestead-trade", fit: fit) { store.show(.trade) }
        }
        if state.legal.canTrade {
            tool("Bank", icon: "building.columns.fill", badge: nil, id: "homestead-bank", fit: fit) { store.show(.bank) }
        }
        tool("Log", icon: "list.bullet", badge: nil, id: "homestead-log", fit: fit) { store.show(.log) }
    }

    private func toolWidth(_ fit: Fit) -> CGFloat {
        switch fit {
        case .roomy: return 58
        case .snug: return 52
        case .stacked: return .infinity
        }
    }

    private func tool(_ title: String, icon: String, badge: String?, id: String, fit: Fit,
                      action: @escaping () -> Void) -> some View {
        Button {
            SRHaptic.select()
            action()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                Text(title.uppercased())
                    .font(SR.Text.label(11))
                    .tracking(0.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(SR.ink)
            .padding(.horizontal, 2)
            .frame(minWidth: 52, idealWidth: fit == .roomy ? 58 : 52, maxWidth: toolWidth(fit), minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(SR.surface.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(SR.line, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Text(badge)
                        .font(SR.monoBold())
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(SR.accent))
                        .offset(x: 4, y: -5)
                }
            }
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel(badge.map { "\(title), \($0)" } ?? title)
        .accessibilityIdentifier(id)
    }

    // MARK: Building

    /// Four across, or two rows of two at accessibility sizes, where four
    /// labels cannot fit a phone's width.
    @ViewBuilder
    private var buildRow: some View {
        if typeSize.isAccessibilitySize {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                buildButtons
            }
        } else {
            HStack(spacing: 6) { buildButtons }
        }
    }

    @ViewBuilder
    private var buildButtons: some View {
        ForEach(HomesteadPiece.allCases) { piece in
            pieceButton(piece)
        }
        buyButton
    }

    /// One line in the four-across row; room to wrap when the row is two by two.
    private var labelLines: Int { typeSize.isAccessibilitySize ? 2 : 1 }

    private func buildTile<Art: View>(_ title: String, art: Art, cost: HomesteadCounts, picked: Bool) -> some View {
        VStack(spacing: 3) {
            art
            Text(title)
                .font(SR.Text.label(13))
                .lineLimit(labelLines)
                .minimumScaleFactor(0.8)
            if state.showCosts { HomesteadCostRow(cost: cost, hand: state.me?.hand) }
        }
        .frame(maxWidth: .infinity, minHeight: 60)
        .padding(.vertical, 4)
        .foregroundStyle(picked ? Color.white : SR.ink)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(picked ? SR.accent : SR.surface.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(picked ? SR.accentDeep : SR.line, lineWidth: picked ? 2 : 1)
        )
        .scaleEffect(picked ? 1.04 : 1)
        .srAnimation(.snappy(duration: 0.2), value: picked)
    }

    private func pieceButton(_ piece: HomesteadPiece) -> some View {
        let spots = state.legal.spots(for: piece)
        let picked = store.picked == piece
        return Button { store.pick(piece) } label: {
            buildTile(piece.label, art: HomesteadPieceIcon(piece: piece, colour: myColour, side: 25),
                      cost: state.cost(piece.costKey), picked: picked)
        }
        .buttonStyle(SRPressStyle())
        .disabled(spots.isEmpty || store.sending)
        .opacity(spots.isEmpty ? 0.45 : 1)
        .accessibilityLabel("\(piece.label), \(spots.count) \(spots.count == 1 ? "spot" : "spots")"
            + (state.showCosts ? ", costs \(state.cost(piece.costKey).text())" : ""))
        .accessibilityAddTraits(picked ? .isSelected : [])
        .accessibilityIdentifier("homestead-pick-\(piece.rawValue)")
    }

    private var buyButton: some View {
        let art = Image(systemName: "book.closed.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(HomesteadPalette.colour(.purple))
            .frame(width: 25, height: 25)
        return Button { store.buy() } label: {
            buildTile("Card", art: art, cost: state.cost("card"), picked: false)
        }
        .buttonStyle(SRPressStyle())
        .disabled(!state.legal.canBuy || store.sending)
        .opacity(state.legal.canBuy ? 1 : 0.45)
        .accessibilityLabel("Buy an almanac card, \(state.deckCount) left" + (state.showCosts ? ", costs \(state.cost("card").text())" : ""))
        .accessibilityIdentifier("homestead-buy")
    }
}

/// A price as glyphs and counts, each dimmed when my hand falls short.
struct HomesteadCostRow: View {
    let cost: HomesteadCounts
    var hand: HomesteadCounts? = nil
    /// Bigger glyphs, for an offer's give and want.
    var large: Bool = false

    var body: some View {
        HStack(spacing: large ? 8 : 2) {
            ForEach(HomesteadResource.allCases.filter { cost[$0] > 0 }) { r in
                HStack(spacing: 1) {
                    Text("\(cost[r])").font(large ? SR.monoBold(15) : SR.Text.mono())
                    Image(systemName: r.symbol).font(.system(size: large ? 15 : 10, weight: .semibold))
                }
                .foregroundStyle(HomesteadResourceColour.of(r))
                .opacity(hand.map { $0[r] >= cost[r] } ?? true ? 1 : 0.4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cost.text())
    }
}

enum HomesteadResourceColour {
    /// The tile's colour, darkened where it would vanish on paper and lifted
    /// where it would vanish on a dark phone.
    static func of(_ r: HomesteadResource) -> Color {
        switch r {
        case .timber: return Color(light: 0x2F6B3A, dark: 0x6FC27F)
        case .clay: return Color(light: 0xB5643C, dark: 0xE38A5E)
        case .wool: return Color(light: 0x4F8A35, dark: 0x9BD67E)
        case .grain: return Color(light: 0xA8841C, dark: 0xF0CF5A)
        case .stone: return Color(light: 0x5D6068, dark: 0xB7BAC2)
        }
    }
}

/// A resource's badge: its glyph on its tile's colour.
struct HomesteadResourceBadge: View {
    let resource: HomesteadResource
    var side: CGFloat = 36

    var body: some View {
        Image(systemName: resource.symbol)
            .font(.system(size: side * 0.48, weight: .semibold))
            .foregroundStyle(HomesteadPalette.glyph(resource.tile))
            .frame(width: side, height: side)
            .background(
                Circle().fill(LinearGradient(colors: [HomesteadPalette.tileLight(resource.tile), HomesteadPalette.tileDark(resource.tile)],
                                             startPoint: .top, endPoint: .bottom))
            )
            .overlay(Circle().strokeBorder(Color.black.opacity(0.15), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// One resource and how many: the hand's tiles.
struct HomesteadResourceTile: View {
    let resource: HomesteadResource
    let count: Int
    var note: String? = nil

    var body: some View {
        VStack(spacing: 5) {
            HomesteadResourceBadge(resource: resource, side: 38)
            Text("\(count)")
                .font(SR.Text.figure(24))
                .foregroundStyle(count > 0 ? SR.ink : SR.inkGhost)
                .srNumeric(Double(count))
            Text(resource.label)
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let note {
                Text(note)
                    .font(SR.monoBold())
                    .foregroundStyle(SR.accentInk)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) \(resource.rawValue)" + (note.map { ", \($0)" } ?? ""))
        .accessibilityIdentifier("homestead-res-\(resource.rawValue)")
    }
}

/// Minus, the count, plus — for picking how many of a resource. The buttons
/// are a full 44 points.
struct HomesteadStepper: View {
    let resource: HomesteadResource
    let count: Int
    let canAdd: Bool
    let add: () -> Void
    let remove: () -> Void
    var id: String

    var body: some View {
        HStack(spacing: 8) {
            HomesteadResourceBadge(resource: resource, side: 30)
            Text(resource.label)
                .font(SR.Text.body())
                .foregroundStyle(SR.ink)
            Spacer(minLength: 8)
            Button { remove(); SRHaptic.select() } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 30))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(count > 0 ? SR.accent : SR.inkGhost)
            .disabled(count == 0)
            .accessibilityLabel("One less \(resource.rawValue)")
            Text("\(count)")
                .font(SR.Text.figure(22))
                .monospacedDigit()
                .foregroundStyle(count > 0 ? SR.ink : SR.inkMuted)
                .frame(minWidth: 30)
                .srNumeric(Double(count))
                .accessibilityLabel("\(count) \(resource.rawValue)")
            Button { add(); SRHaptic.select() } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 30))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(canAdd ? SR.accent : SR.inkGhost)
            .disabled(!canAdd)
            .accessibilityLabel("One more \(resource.rawValue)")
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }
}

// MARK: - Sheets

/// A sheet's frame: title, scrolling body, Done.
struct HomesteadSheetFrame<Content: View>: View {
    let title: String
    var id: String
    var done: (() -> Void)? = nil
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SR.sectionGap) {
                    content
                }
                .padding(.horizontal, SR.gutter)
                .padding(.vertical, 12)
            }
            .srGround(.warm)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let done { done() } else { dismiss() }
                    }
                    .accessibilityIdentifier("\(id)-done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier(id)
    }
}

/// My cards: resources, almanac cards to play, the price list, the pieces
/// left and the hints.
struct HomesteadHandSheet: View {
    let state: HomesteadState
    @ObservedObject var store: HomesteadStore
    @State private var harvest: [HomesteadResource] = [.timber, .clay]
    @State private var market: HomesteadResource = .grain
    @State private var asking: HomesteadCard?

    private var me: HomesteadMe? { state.me }

    var body: some View {
        HomesteadSheetFrame(title: "Your hand", id: "homestead-hand-sheet") {
            if let me {
                VStack(alignment: .leading, spacing: SR.cardGap) {
                    SRSectionLabel(text: "Resources", trailing: "\(me.hand.total)")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                        ForEach(HomesteadResource.allCases) { r in
                            HomesteadResourceTile(resource: r, count: me.hand[r], note: me.rate(r) < 4 ? "\(me.rate(r)):1" : nil)
                        }
                    }
                }
                almanac(me)
            } else {
                Text("You are watching: no hand of your own.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            }
            if state.showCosts { prices }
            if let mine = state.myself, !mine.pieces.isEmpty { piecesLeft(mine) }
            if let hints = state.hints { hintsCard(hints) }
        }
    }

    @ViewBuilder
    private func almanac(_ me: HomesteadMe) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Almanac cards", trailing: "\(me.cards.count) · \(state.deckCount) in the deck")
            if me.cards.isEmpty {
                Text("None yet. Buy one for 1 wool, 1 grain and 1 stone.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(me.cards.enumerated()), id: \.offset) { _, card in
                cardRow(card, me: me)
            }
        }
    }

    /// An almanac card as a little card: its picture on a coloured face.
    private func cardArt(_ card: HomesteadCard) -> some View {
        Image(systemName: card.symbol)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: 46, height: 62)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: [Self.cardTint(card).opacity(0.85), Self.cardTint(card)],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5)
                    .padding(3)
            )
            .accessibilityHidden(true)
    }

    static func cardTint(_ card: HomesteadCard) -> Color {
        switch card {
        case .ranger: return HomesteadPalette.colour(.green)
        case .heirloom: return Color(hex: 0xB8860B)
        case .pathfinders: return HomesteadPalette.colour(.blue)
        case .harvest: return HomesteadPalette.colour(.amber)
        case .market: return HomesteadPalette.colour(.purple)
        case .other: return Color(hex: 0x777777)
        }
    }

    private func cardRow(_ held: HomesteadHeldCard, me: HomesteadMe) -> some View {
        let playable = state.legal.playable.contains(held.kind) && !held.new && !me.playedCardThisTurn
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                cardArt(held.kind)
                VStack(alignment: .leading, spacing: 2) {
                    Text(held.kind.title + (held.new ? " · new" : ""))
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                    Text(held.kind.line + (held.new && held.kind != .heirloom ? " Playable from your next turn." : ""))
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if asking == held.kind, held.kind == .harvest {
                HStack {
                    resourcePicker("First", selection: $harvest[0])
                    resourcePicker("Second", selection: $harvest[1])
                }
                Button { store.play(.harvest, take: harvest) } label: {
                    SRButtonLabel(title: "Take \(harvest[0].rawValue) and \(harvest[1].rawValue)", icon: "basket.fill", fill: true)
                        .frame(minHeight: 44)
                }
                .srButton(.prominent)
                .accessibilityIdentifier("homestead-harvest-go")
            } else if asking == held.kind, held.kind == .market {
                resourcePicker("Resource", selection: $market)
                Button { store.play(.market, resource: market) } label: {
                    SRButtonLabel(title: "Ask everyone for their \(market.rawValue)", icon: "storefront.fill", fill: true)
                        .frame(minHeight: 44)
                }
                .srButton(.prominent)
                .accessibilityIdentifier("homestead-market-go")
            } else if playable {
                Button {
                    switch held.kind {
                    case .harvest, .market: asking = held.kind
                    default: store.play(held.kind)
                    }
                } label: {
                    SRButtonLabel(title: "Play \(held.kind.title)", icon: "play.fill", fill: true)
                        .frame(minHeight: 44)
                }
                .srButton(.regular)
                .disabled(store.sending)
                .accessibilityIdentifier("homestead-play-\(held.kind.raw)")
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
    }

    private func resourcePicker(_ title: String, selection: Binding<HomesteadResource>) -> some View {
        Picker(title, selection: selection) {
            ForEach(HomesteadResource.allCases) { r in
                Label(r.label, systemImage: r.symbol).tag(r)
            }
        }
        .pickerStyle(.menu)
        .tint(SR.accentInk)
    }

    private var prices: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Prices")
            VStack(spacing: 0) {
                ForEach(["road", "cottage", "town", "card"], id: \.self) { key in
                    priceRow(key)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .srGlassCard(.paper)
            Text("Cottage 1 point, town 2. Longest Trail (5 roads or more in a row) and Chief Ranger (3 rangers or more) are 2 points each.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func priceRow(_ key: String) -> some View {
        HStack(spacing: 10) {
            if let piece = HomesteadPiece(rawValue: key) {
                HomesteadPieceIcon(piece: piece, colour: state.myself?.colour, side: 26)
            } else {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(HomesteadPalette.colour(.purple))
                    .frame(width: 26, height: 26)
                    .accessibilityHidden(true)
            }
            Text(key == "card" ? "Almanac card" : key.capitalized)
                .font(SR.Text.body())
                .foregroundStyle(SR.ink)
            Spacer(minLength: 8)
            HomesteadCostRow(cost: state.cost(key), hand: state.me?.hand, large: true)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    /// The pieces still in my box.
    private func piecesLeft(_ mine: HomesteadPlayer) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Pieces left")
            HStack(spacing: 10) {
                ForEach(HomesteadPiece.allCases) { piece in
                    VStack(spacing: 4) {
                        HomesteadPieceIcon(piece: piece, colour: mine.colour, side: 30)
                        Text("\(mine.pieces[piece] ?? 0)")
                            .font(SR.Text.figure(20))
                            .foregroundStyle(SR.ink)
                        Text(Self.plural(piece))
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(mine.pieces[piece] ?? 0) \(piece.rawValue)s left")
                }
            }
            .padding(.vertical, 12)
            .srGlassCard(.paper)
        }
        .accessibilityIdentifier("homestead-pieces-left")
    }

    static func plural(_ piece: HomesteadPiece) -> String {
        switch piece {
        case .road: return "roads"
        case .cottage: return "cottages"
        case .town: return "towns"
        }
    }

    private func hintsCard(_ hints: HomesteadHints) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Hints")
            VStack(alignment: .leading, spacing: 6) {
                if !hints.affordable.isEmpty {
                    Text("You can afford " + GameNames.list(hints.affordable.map(HomesteadPlaying.costName)) + ".")
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(hints.trades, id: \.self) { trade in
                    Text("Trade \(trade.count) \(trade.give.rawValue) for 1 \(trade.get.rawValue)" + (trade.forWhat.map { " to build \(HomesteadPlaying.costName($0))" } ?? "") + ".")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let tip = hints.tip {
                    Label(tip, systemImage: "lightbulb.fill")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(SR.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .srGlassCard(.paper)
            .accessibilityIdentifier("homestead-hints")
        }
    }
}

/// Trade with the bank at my rates: 4:1, 3:1 at any harbour, 2:1 at a
/// resource's own.
struct HomesteadBankSheet: View {
    let state: HomesteadState
    @ObservedObject var store: HomesteadStore
    @State private var give: HomesteadResource?
    @State private var get: HomesteadResource?

    var body: some View {
        HomesteadSheetFrame(title: "Bank", id: "homestead-bank-sheet") {
            if let me = state.me {
                exchange(me)
                VStack(alignment: .leading, spacing: SR.cardGap) {
                    SRSectionLabel(text: "Give")
                    ForEach(HomesteadResource.allCases) { r in
                        let rate = me.rate(r)
                        choice(r, line: "\(rate) for 1 · you have \(me.hand[r])", selected: give == r,
                               enabled: me.hand[r] >= rate, id: "homestead-bank-give-\(r.rawValue)") { give = r }
                    }
                }
                VStack(alignment: .leading, spacing: SR.cardGap) {
                    SRSectionLabel(text: "Get one")
                    ForEach(HomesteadResource.allCases) { r in
                        choice(r, line: "\(state.bank[r]) in the bank", selected: get == r,
                               enabled: state.bank[r] > 0 && r != give, id: "homestead-bank-get-\(r.rawValue)") { get = r }
                    }
                }
                Button {
                    guard let give, let get else { return }
                    store.bank(give: give, get: get)
                    self.give = nil
                    self.get = nil
                } label: {
                    SRButtonLabel(title: summary(me), icon: "building.columns.fill", fill: true)
                        .frame(minHeight: 44)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .disabled(give == nil || get == nil || give == get || store.sending)
                .accessibilityIdentifier("homestead-bank-go")
            }
        }
    }

    /// The swap as a picture: what goes, an arrow, what comes.
    private func exchange(_ me: HomesteadMe) -> some View {
        HStack(spacing: 14) {
            side(give, count: give.map { me.rate($0) }, label: "Give")
            Image(systemName: "arrow.right")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(SR.inkMuted)
            side(get, count: get == nil ? nil : 1, label: "Get")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .srGlassCard(.paper)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary(me))
    }

    private func side(_ r: HomesteadResource?, count: Int?, label: String) -> some View {
        VStack(spacing: 4) {
            if let r {
                HomesteadResourceBadge(resource: r, side: 44)
            } else {
                Circle()
                    .strokeBorder(SR.inkGhost, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .frame(width: 44, height: 44)
            }
            Text(count.map { "\($0)" } ?? "?")
                .font(SR.Text.figure(20))
                .foregroundStyle(SR.ink)
            Text(label.uppercased())
                .font(SR.Text.label())
                .foregroundStyle(SR.inkMuted)
        }
        .frame(minWidth: 80)
    }

    private func summary(_ me: HomesteadMe) -> String {
        guard let give, let get else { return "Pick what to give and get" }
        return "Give \(me.rate(give)) \(give.rawValue), get 1 \(get.rawValue)"
    }

    private func choice(_ r: HomesteadResource, line: String, selected: Bool, enabled: Bool, id: String,
                        action: @escaping () -> Void) -> some View {
        Button { action(); SRHaptic.select() } label: {
            HStack(spacing: 12) {
                HomesteadResourceBadge(resource: r, side: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.label).font(SR.Text.title()).foregroundStyle(SR.ink)
                    Text(line).font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(selected ? SR.accent : SR.inkGhost)
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 10)
            .frame(minHeight: 56)
            .srGlassCard(.paper)
            .overlay(
                RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                    .strokeBorder(selected ? SR.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(SRPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

/// Every offer on the table, with what I may do about each; and, on my turn
/// (or answering one), the composer.
struct HomesteadTradeSheet: View {
    let room: GameRoom
    let state: HomesteadState
    @ObservedObject var store: HomesteadStore
    @State private var draft = HomesteadTradeDraft()
    /// Answering this offer with a counter, rather than proposing.
    @State private var counterTo: HomesteadOffer?
    /// Nil = everyone.
    @State private var to: Set<String> = []

    private func name(_ id: String) -> String { id == state.meId ? "You" : (state.player(id)?.name ?? room.name(of: id)) }

    var body: some View {
        HomesteadSheetFrame(title: "Trade", id: "homestead-trade-sheet") {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                SRSectionLabel(text: "Offers", trailing: "\(state.openOffers.count) open")
                if state.offers.isEmpty {
                    Text(state.isMyTurn ? "No offers yet. Make one below." : "No offers yet. Only the player whose turn it is can start a trade.")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(state.offers.sorted { ($0.isOpen ? 0 : 1, -$0.at) < ($1.isOpen ? 0 : 1, -$1.at) }) { offer in
                    offerRow(offer)
                }
            }
            if composing { composer }
        }
    }

    private var composing: Bool {
        if counterTo != nil { return true }
        return state.isMyTurn && state.legal.canTrade
    }

    private func offerRow(_ offer: HomesteadOffer) -> some View {
        let role = state.role(in: offer)
        let audience: String = {
            guard let to = offer.to else { return "to everyone" }
            return "to " + GameNames.list(to.map(name))
        }()
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HomesteadSeatMark(colour: state.colour(of: offer.from), side: 22)
                Text("\(name(offer.from)) \(offer.isCounter ? "counters" : "offers") \(audience)")
                    .font(SR.Text.title(15))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if !offer.isOpen {
                    SRGlassChip(text: statusLabel(offer), tone: SR.inkMuted)
                }
            }
            offerSwap(offer)
            if !offer.refusedBy.isEmpty {
                Text("No thanks from " + GameNames.list(offer.refusedBy.map(name)) + ".")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
            if role.short, offer.isOpen, !role.mine {
                Text("You don't have the \(offer.want.text()) it asks for.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
            offerButtons(offer, role: role)
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .opacity(offer.isOpen ? 1 : 0.6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homestead-offer-\(offer.id)")
    }

    /// Gives on the left, wants on the right, in big glyphs.
    private func offerSwap(_ offer: HomesteadOffer) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("GIVES").font(SR.Text.label()).foregroundStyle(SR.inkMuted)
                HomesteadCostRow(cost: offer.give, large: true)
            }
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(SR.inkMuted)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("WANTS").font(SR.Text.label()).foregroundStyle(SR.inkMuted)
                HomesteadCostRow(cost: offer.want, large: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                .fill(SR.surface.opacity(0.6))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gives \(offer.give.text()), wants \(offer.want.text())")
    }

    private func offerButtons(_ offer: HomesteadOffer, role: HomesteadOfferRole) -> some View {
        HStack(spacing: 8) {
            if role.canAccept {
                Button { store.accept(offer.id) } label: {
                    SRButtonLabel(title: "Accept", icon: "checkmark", fill: true).frame(minHeight: 44)
                }
                .srButton(.prominent)
                .accessibilityIdentifier("homestead-accept-\(offer.id)")
            }
            if role.canCounter {
                Button {
                    counterTo = offer
                    draft = HomesteadTradeDraft(give: offer.want, want: offer.give)
                } label: {
                    SRButtonLabel(title: "Counter", icon: "arrow.uturn.left", fill: true).frame(minHeight: 44)
                }
                .srButton(.regular)
                .accessibilityIdentifier("homestead-counter-\(offer.id)")
            }
            if role.canRefuse {
                Button { store.refuse(offer.id) } label: {
                    SRButtonLabel(title: "No thanks", fill: true).frame(minHeight: 44)
                }
                .srButton(.regular)
                .accessibilityIdentifier("homestead-refuse-\(offer.id)")
            }
            if role.canCancel {
                Button { store.cancel(offer.id) } label: {
                    SRButtonLabel(title: "Withdraw", icon: "xmark", fill: true).frame(minHeight: 44)
                }
                .srButton(.regular)
                .accessibilityIdentifier("homestead-cancel-\(offer.id)")
            }
        }
        .disabled(store.sending)
    }

    private func statusLabel(_ offer: HomesteadOffer) -> String {
        switch offer.status {
        case .done: return offer.acceptedBy.map { "Done with \(name($0))" } ?? "Done"
        case .cancelled: return "Withdrawn"
        case .void: return "No longer possible"
        default: return offer.status.rawValue
        }
    }

    private var composer: some View {
        let hand = state.me?.hand ?? .none
        let problem = draft.problem(hand: hand)
        return VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: counterTo == nil ? "Make an offer" : "Your counter to \(name(counterTo?.from ?? ""))")
            VStack(alignment: .leading, spacing: 4) {
                Text("YOU GIVE").font(SR.Text.label()).foregroundStyle(SR.inkSecondary)
                ForEach(HomesteadResource.allCases) { r in
                    HomesteadStepper(resource: r, count: draft.give[r], canAdd: draft.give[r] < hand[r],
                                     add: { draft.give[r] += 1; draft.want[r] = 0 }, remove: { draft.give[r] -= 1 },
                                     id: "homestead-give-\(r.rawValue)")
                }
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
            VStack(alignment: .leading, spacing: 4) {
                Text("YOU WANT").font(SR.Text.label()).foregroundStyle(SR.inkSecondary)
                ForEach(HomesteadResource.allCases) { r in
                    HomesteadStepper(resource: r, count: draft.want[r], canAdd: draft.want[r] < 9,
                                     add: { draft.want[r] += 1; draft.give[r] = 0 }, remove: { draft.want[r] -= 1 },
                                     id: "homestead-want-\(r.rawValue)")
                }
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
            if counterTo == nil { recipients }
            if let problem {
                Text(problem)
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
            HStack(spacing: 8) {
                Button {
                    if let offer = counterTo {
                        store.counter(offer.id, draft)
                        counterTo = nil
                    } else {
                        store.offer(draft, to: to.isEmpty ? nil : state.seats.filter { to.contains($0) })
                    }
                    draft = HomesteadTradeDraft()
                } label: {
                    SRButtonLabel(title: counterTo == nil ? "Offer it" : "Send counter", icon: "paperplane.fill", fill: true)
                        .frame(minHeight: 44)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .disabled(problem != nil || store.sending)
                .accessibilityIdentifier("homestead-offer-go")
                if counterTo != nil {
                    Button {
                        counterTo = nil
                        draft = HomesteadTradeDraft()
                    } label: {
                        SRButtonLabel(title: "Never mind", fill: true).frame(minHeight: 44)
                    }
                    .srButton(.regular)
                    .controlSize(.large)
                }
            }
        }
    }

    private var recipients: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(to.isEmpty ? "TO EVERYONE" : "TO").font(SR.Text.label()).foregroundStyle(SR.inkSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(state.seated.filter { $0.id != state.meId && $0.joined }) { p in
                        recipient(p)
                    }
                }
            }
            Text("Pick nobody to offer it to everyone.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
        }
    }

    private func recipient(_ p: HomesteadPlayer) -> some View {
        let on = to.contains(p.id)
        return Button {
            to.formSymmetricDifference([p.id])
            SRHaptic.select()
        } label: {
            HStack(spacing: 6) {
                HomesteadSeatMark(colour: p.colour, side: 22)
                Text(p.name).font(SR.Text.bodyMedium(15))
                if on {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Capsule().fill(on ? SR.accent.opacity(0.2) : SR.surface.opacity(0.7)))
            .overlay(Capsule().strokeBorder(on ? SR.accent : SR.line, lineWidth: on ? 2 : 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(SR.ink)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("homestead-to-\(p.id)")
    }
}

/// After a 7: put back exactly half (rounded down) of what I hold. A row of
/// card backs fills as I pick, so how many are still to go is plain.
struct HomesteadDiscardSheet: View {
    let state: HomesteadState
    @ObservedObject var store: HomesteadStore
    @State private var draft = HomesteadDiscardDraft()

    var body: some View {
        let owed = state.myDiscard
        let hand = state.me?.hand ?? .none
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SR.sectionGap) {
                    SRPageHeader(kicker: "A 7 was rolled", title: "Put back \(owed) cards",
                                 strap: "You hold more than seven, so half go back to the bank. Pick which.")
                    HomesteadDeadline(state: state, now: { store.serverNow() })
                    meter(picked: draft.cards.total, owed: owed)
                    VStack(spacing: 4) {
                        ForEach(HomesteadResource.allCases) { r in
                            VStack(spacing: 0) {
                                HomesteadStepper(resource: r, count: draft.cards[r],
                                                 canAdd: draft.cards[r] < hand[r] && draft.cards.total < owed,
                                                 add: { draft.add(r, owed: owed, hand: hand) }, remove: { draft.remove(r) },
                                                 id: "homestead-discard-\(r.rawValue)")
                                Text("You have \(hand[r])")
                                    .font(SR.Text.mono())
                                    .foregroundStyle(SR.inkMuted)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
                    }
                    .padding(SR.cardPadding)
                    .srGlassCard(.paper)
                    Button { store.discard(draft) } label: {
                        SRButtonLabel(title: "Put back \(draft.cards.total) of \(owed)", icon: "tray.and.arrow.up.fill", fill: true)
                            .frame(minHeight: 44)
                    }
                    .srButton(.prominent)
                    .controlSize(.large)
                    .disabled(!draft.ready(owed: owed, hand: hand) || store.sending)
                    .accessibilityIdentifier("homestead-discard-go")
                    if let refusal = store.refusal {
                        Text(refusal).font(SR.Text.bodyMedium(15)).foregroundStyle(SR.error)
                    }
                }
                .padding(.horizontal, SR.gutter)
                .padding(.vertical, 12)
            }
            .srGround(.warm)
            .navigationTitle("Discard")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("homestead-discard-sheet")
    }

    /// One card back per card owed, filled as they are picked.
    private func meter(picked: Int, owed: Int) -> some View {
        let shown = min(owed, 12)
        return HStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<max(shown, 0), id: \.self) { i in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(i < picked ? SR.accent : SR.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(i < picked ? SR.accentDeep : SR.line, lineWidth: 1.5)
                        )
                        .frame(width: 18, height: 26)
                }
            }
            .srAnimation(.snappy(duration: 0.2), value: picked)
            Spacer(minLength: 8)
            Text(picked >= owed ? "Ready" : "\(owed - picked) to go")
                .font(SR.monoBold())
                .foregroundStyle(picked >= owed ? SR.good : SR.inkSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(picked >= owed ? "All \(owed) picked" : "\(picked) of \(owed) picked")
        .accessibilityIdentifier("homestead-discard-meter")
    }
}

/// What has happened, newest first.
struct HomesteadLogSheet: View {
    let state: HomesteadState

    var body: some View {
        HomesteadSheetFrame(title: "What happened", id: "homestead-log-sheet") {
            HomesteadLogList(entries: state.log.reversed(), state: state)
        }
    }
}

struct HomesteadLogList: View {
    let entries: [HomesteadLogEntry]
    let state: HomesteadState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if entries.isEmpty {
                Text("Nothing yet.").font(SR.Text.secondary()).foregroundStyle(SR.inkMuted).padding(.vertical, 8)
            }
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { Divider().overlay(SR.divider) }
                row(entry)
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("homestead-log")
    }

    private func row(_ entry: HomesteadLogEntry) -> some View {
        let tint = entry.by.map { HomesteadPalette.colour(state.colour(of: $0)) } ?? SR.inkMuted
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(tint))
                .accessibilityHidden(true)
            Text(entry.text + (entry.auto ? " (timed out)" : ""))
                .font(SR.Text.secondary())
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Finished

struct HomesteadFinished: View {
    let room: GameRoom
    @ObservedObject var store: HomesteadStore
    let done: () -> Void
    @State private var record: TableGameRecord?

    private var state: HomesteadState? { room.homestead }
    private var iWon: Bool { room.winnerIds.contains(room.meId) }
    private var gameKey: String { TableGameKey.finished(roomId: room.id, startedAt: room.startedAt) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Homestead · \(state.map(HomesteadText.rules) ?? GameDifficulty.label(for: room.difficulty)) · final",
                             title: GameResults.title(room, solo: "Game over", none: "Nobody won"),
                             strap: GameResults.strap(room))

                if let state, let mine = standing(room.meId) {
                    hero(state, mine: mine)
                }

                if let state, let line = HomesteadText.outcome(state, name: { $0 == room.meId ? "You" : room.name(of: $0) }) {
                    Text(line)
                        .font(SR.Text.bodyMedium(16))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("homestead-outcome")
                }

                GameStandingsCard(
                    room: room,
                    label: "Points",
                    id: "homestead-standings",
                    detail: detail,
                    figure: { row in
                        guard let s = standing(row.id) else { return nil }
                        return (text: "\(s.vp)", spoken: "\(s.vp) points")
                    }
                )

                if let record {
                    TableRecordCard(record: record, gameKey: gameKey, bestLabel: "Best points", id: "homestead-record")
                }

                if let state, !state.board.hexes.isEmpty {
                    VStack(alignment: .leading, spacing: SR.cardGap) {
                        SRSectionLabel(text: "The island at the end")
                        HomesteadBoardView(state: state, showsRoll: false)
                            .frame(height: 320)
                    }
                    VStack(alignment: .leading, spacing: SR.cardGap) {
                        SRSectionLabel(text: "The last moves")
                        HomesteadLogList(entries: Array(state.log.suffix(8).reversed()), state: state)
                    }
                }

                GameFinishedButtons(room: room, store: store, prefix: "homestead", done: done)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("homestead-finished")
        .onAppear { noteRecord() }
    }

    /// My result: a crown when I won, else my town, with how far I got.
    private func hero(_ state: HomesteadState, mine: HomesteadStanding) -> some View {
        let colour = state.myself?.colour
        let share = HomesteadMoments.share(mine.vp, of: state.vpTarget)
        return HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .fill(iWon ? SR.accent : HomesteadPalette.colour(colour).opacity(0.16))
                    .frame(width: 80, height: 80)
                if iWon {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(Color.white)
                } else {
                    HomesteadPieceIcon(piece: .town, colour: colour, side: 50)
                }
            }
            .tablePopIn()
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(heroTitle(mine))
                    .font(SR.Text.display(24))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(heroDetail(mine, target: state.vpTarget))
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                GeometryReader { geo in
                    Capsule()
                        .fill(SR.line)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(iWon ? SR.accent : HomesteadPalette.colour(colour))
                                .frame(width: max(8, geo.size.width * CGFloat(share)))
                        }
                }
                .frame(height: 8)
            }
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("homestead-hero")
    }

    private func heroTitle(_ mine: HomesteadStanding) -> String {
        if iWon { return "Your homestead won!" }
        if mine.left { return "You left the island" }
        return "You came \(HomesteadMoments.ordinal(mine.place))"
    }

    private func heroDetail(_ mine: HomesteadStanding, target: Int) -> String {
        var bits = ["\(mine.vp) of \(target) points"]
        bits.append(GameResults.count(mine.cottages, "cottage", "cottages"))
        bits.append(GameResults.count(mine.towns, "town", "towns"))
        return bits.joined(separator: " · ") + (iWon ? ". Well played!" : ". Ask for a rematch!")
    }

    /// This phone's keepsake: games, wins in a row and the best points, once
    /// per finished game. Not kept for the demo.
    private func noteRecord() {
        guard record == nil, let mine = standing(room.meId) else { return }
        let book = TableGameBestStore(gameId: GameKind.homestead.rawValue, persists: !SRDemo.isOn)
        record = book.note(variant: GameKind.homestead.rawValue, key: gameKey, won: iWon, score: mine.vp)
    }

    private func standing(_ id: String) -> HomesteadStanding? {
        state?.standings?.first { $0.id == id }
    }

    private func detail(_ row: GameStanding) -> String {
        guard let s = standing(row.id) else { return "" }
        var bits = ["\(s.cottages) \(s.cottages == 1 ? "cottage" : "cottages")", "\(s.towns) \(s.towns == 1 ? "town" : "towns")"]
        if s.heirlooms > 0 { bits.append("\(s.heirlooms) \(s.heirlooms == 1 ? "heirloom" : "heirlooms")") }
        if s.longestTrail { bits.append("Longest Trail") }
        if s.chiefRanger { bits.append("Chief Ranger") }
        if s.left { bits.append("left") }
        return bits.joined(separator: " · ")
    }
}
