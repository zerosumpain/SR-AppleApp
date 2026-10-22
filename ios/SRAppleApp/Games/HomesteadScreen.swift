import SwiftUI
import UIKit

/// One Homestead room, from lobby to the last point.
///
/// The lobby and the 3-2-1 are every game's (`GameLobby`, `GameCountdownView`);
/// Start waits for three. Play is a header (whose move, its deadline, the
/// dice), a strip of everyone's points and cards, the island — pan, pinch,
/// tap a lit spot — and a bar of what I can do now: roll, pick a piece to
/// build, buy an almanac card, trade, end the turn. Hand, bank, trade and log
/// are sheets; the discard after a 7 is a sheet that will not close until the
/// cards are put back. The finish is the table, the final island and the log.
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
                    ProgressView().tint(SR.accent).frame(maxWidth: .infinity, maxHeight: .infinity).srPaper()
                }
            case .finished:
                HomesteadFinished(room: room, store: store, done: { dismiss() })
            case .closed:
                GameEndedView(id: "homestead-ended", done: { dismiss() })
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

/// The rules the host picked, and that it needs three.
struct HomesteadTableCard: View {
    let room: GameRoom

    var body: some View {
        let state = room.homestead
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: GameKind.homestead.icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(SR.good)
                .accessibilityHidden(true)
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
                if room.playing.count < 3 {
                    Text(room.playing.count == 2 ? "Needs one more player." : "Needs three players.")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .accessibilityIdentifier("homestead-needs-three")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("homestead-table")
    }
}

// MARK: - Playing

struct HomesteadPlaying: View {
    let room: GameRoom
    let state: HomesteadState
    @ObservedObject var store: HomesteadStore
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            HomesteadStrip(state: state, now: { store.serverNow() })
            HomesteadBoardView(state: state, lit: store.lit, interactive: !store.sending, onTap: { store.tap($0) })
                .frame(minHeight: 220, maxHeight: .infinity)
                .overlay(alignment: .top) { refusal }
            status
            HomesteadActionBar(state: state, store: store)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .srGround(.warm)
        .accessibilityIdentifier("homestead-playing")
        .onChange(of: store.refusal) { _, refusal in
            if let refusal { UIAccessibility.post(notification: .announcement, argument: refusal) }
        }
        .sheet(item: $store.sheet) { sheet in
            switch sheet {
            case .hand: HomesteadHandSheet(state: state, store: store)
            case .bank: HomesteadBankSheet(state: state, store: store)
            case .trade: HomesteadTradeSheet(room: room, state: state, store: store)
            case .log: HomesteadLogSheet(state: state)
            }
        }
        .sheet(isPresented: Binding(get: { store.mustDiscard }, set: { _ in })) {
            HomesteadDiscardSheet(state: state, store: store)
                .interactiveDismissDisabled()
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

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("TURN \(max(1, state.turn)) · \(state.vpTarget) TO WIN" + (state.isAsync ? " · OVER DAYS" : ""))
                    .font(SR.Text.label())
                    .tracking(1.2)
                    .foregroundStyle(SR.accent)
                    .fixedSize(horizontal: false, vertical: true)
                Text(HomesteadText.headline(state, name: { $0 == state.meId ? "You" : room.name(of: $0) }))
                    .font(SR.Text.display(typeSize.isAccessibilitySize ? 20 : 22))
                    .foregroundStyle(state.isMyTurn || state.myDiscard > 0 ? SR.accentInk : SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("homestead-headline")
                HomesteadDeadline(state: state, now: { store.serverNow() })
            }
            Spacer(minLength: 6)
            HomesteadDiceView(dice: state.dice, serial: store.rollSerial)
        }
    }

    @ViewBuilder
    private var refusal: some View {
        if let refusal = store.refusal {
            Label(refusal, systemImage: "exclamationmark.circle")
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.paper)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(SR.error.opacity(0.92)))
                .padding(8)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("homestead-refusal")
        }
    }

    /// One line under the board: what a tap does now, or the best hint.
    @ViewBuilder
    private var status: some View {
        if let line = statusLine {
            Text(line)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
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

/// "Your move · 0:42 left" for whoever the room waits on, ticking.
struct HomesteadDeadline: View {
    let state: HomesteadState
    let now: () -> Double?

    var body: some View {
        if let end = state.phaseEndsAt, state.phase == .playing {
            TimelineView(.periodic(from: .now, by: state.isAsync ? 30 : 1)) { _ in
                if let now = now() {
                    let left = max(0, end - now)
                    Label(text(left), systemImage: "timer")
                        .font(SR.Text.mono())
                        .foregroundStyle(left < 15_000 ? SR.error : SR.inkMuted)
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

/// Everyone at the table: colour and mark, points, cards, almanac cards, and
/// the two awards. The player whose move it is is lit.
struct HomesteadStrip: View {
    let state: HomesteadState
    let now: () -> Double?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(state.seated) { player in
                    chip(player)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityIdentifier("homestead-strip")
    }

    private func chip(_ p: HomesteadPlayer) -> some View {
        let active = p.id == state.activeId
        let me = p.id == state.meId
        let points = me ? (state.me?.vp ?? p.publicVp) : p.publicVp
        return HStack(spacing: 8) {
            HomesteadSeatMark(colour: p.colour)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
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
                Text("\(points) pts · \(p.handCount) cards" + (p.cardCount > 0 ? " · \(p.cardCount) alm." : ""))
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .lineLimit(1)
                if let owed = state.discardOwed[p.id], owed > 0 {
                    Text("Puts back \(owed)")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.error)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(active ? SR.accent.opacity(0.16) : SR.paper.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(active ? SR.accent : SR.line, lineWidth: active ? 2 : 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(p, points: points, me: me, active: active))
        .accessibilityIdentifier("homestead-player-\(p.id)")
    }

    private func spoken(_ p: HomesteadPlayer, points: Int, me: Bool, active: Bool) -> String {
        var bits = [me ? "You" : p.name, p.colour?.label ?? "", "\(points) points", "\(p.handCount) cards"]
        if p.cardCount > 0 { bits.append("\(p.cardCount) almanac cards") }
        if p.longestTrail { bits.append("Longest Trail") }
        if p.chiefRanger { bits.append("Chief Ranger") }
        if p.away { bits.append("away") }
        if active { bits.append("their move") }
        return bits.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

// MARK: - The action bar

struct HomesteadActionBar: View {
    let state: HomesteadState
    @ObservedObject var store: HomesteadStore
    @Environment(\.dynamicTypeSize) private var typeSize

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 150 : 84), spacing: 8)]
    }

    var body: some View {
        VStack(spacing: 8) {
            if store.canBuild { buildRow }
            LazyVGrid(columns: columns, spacing: 8) {
                primary
                tool("Hand", icon: "rectangle.stack.fill", badge: state.me.map { "\($0.hand.total)" }, id: "homestead-hand") {
                    store.sheet = .hand
                }
                if state.legal.canTrade || !state.openOffers.isEmpty {
                    tool("Trade", icon: "arrow.left.arrow.right", badge: state.openOffers.isEmpty ? nil : "\(state.openOffers.count)",
                         id: "homestead-trade") { store.sheet = .trade }
                }
                if state.legal.canTrade {
                    tool("Bank", icon: "building.columns.fill", badge: nil, id: "homestead-bank") { store.sheet = .bank }
                }
                tool("Log", icon: "list.bullet", badge: nil, id: "homestead-log") { store.sheet = .log }
            }
        }
    }

    /// Roll, End turn, Skip — the one move the step is waiting on.
    @ViewBuilder
    private var primary: some View {
        if state.legal.canRoll {
            big("Roll", icon: "dice.fill", id: "homestead-roll") { store.roll() }
        } else if state.step == .roads, state.isMyTurn {
            big("Skip", icon: "forward.fill", id: "homestead-skip") { store.skip() }
        } else if state.legal.canEnd {
            big("End turn", icon: "checkmark", id: "homestead-end") { store.end() }
        }
    }

    private var buildRow: some View {
        HStack(spacing: 6) {
            ForEach(HomesteadPiece.allCases) { piece in
                pieceButton(piece)
            }
            buyButton
        }
    }

    private func pieceButton(_ piece: HomesteadPiece) -> some View {
        let spots = state.legal.spots(for: piece)
        let picked = store.picked == piece
        return Button { store.pick(piece) } label: {
            VStack(spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: icon(piece)).font(.system(size: 13, weight: .bold))
                    Text(piece.label).font(SR.Text.label(13)).lineLimit(1)
                }
                if state.showCosts { HomesteadCostRow(cost: state.cost(piece.costKey), hand: state.me?.hand) }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .foregroundStyle(picked ? SR.paper : SR.ink)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(picked ? SR.accent : SR.paper.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(SR.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(spots.isEmpty || store.sending)
        .opacity(spots.isEmpty ? 0.45 : 1)
        .accessibilityLabel("\(piece.label), \(spots.count) \(spots.count == 1 ? "spot" : "spots")"
            + (state.showCosts ? ", costs \(state.cost(piece.costKey).text())" : ""))
        .accessibilityAddTraits(picked ? .isSelected : [])
        .accessibilityIdentifier("homestead-pick-\(piece.rawValue)")
    }

    private var buyButton: some View {
        Button { store.buy() } label: {
            VStack(spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "book.closed.fill").font(.system(size: 13, weight: .bold))
                    Text("Card").font(SR.Text.label(13)).lineLimit(1)
                }
                if state.showCosts { HomesteadCostRow(cost: state.cost("card"), hand: state.me?.hand) }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .foregroundStyle(SR.ink)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(SR.paper.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(SR.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!state.legal.canBuy || store.sending)
        .opacity(state.legal.canBuy ? 1 : 0.45)
        .accessibilityLabel("Buy an almanac card, \(state.deckCount) left" + (state.showCosts ? ", costs \(state.cost("card").text())" : ""))
        .accessibilityIdentifier("homestead-buy")
    }

    private func icon(_ piece: HomesteadPiece) -> String {
        switch piece {
        case .road: return "road.lanes"
        case .cottage: return "house.fill"
        case .town: return "building.2.fill"
        }
    }

    private func big(_ title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SRButtonLabel(title: title, icon: icon, fill: true)
        }
        .srButton(.prominent)
        .disabled(store.sending)
        .accessibilityIdentifier(id)
    }

    private func tool(_ title: String, icon: String, badge: String?, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                SRButtonLabel(title: title, icon: icon, fill: true)
                if let badge {
                    Text(badge)
                        .font(SR.Text.label())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(SR.accent.opacity(0.2)))
                }
            }
        }
        .srButton(.regular)
        .accessibilityIdentifier(id)
    }
}

/// A price as glyphs and counts, each dimmed when my hand falls short.
struct HomesteadCostRow: View {
    let cost: HomesteadCounts
    var hand: HomesteadCounts? = nil

    var body: some View {
        HStack(spacing: 3) {
            ForEach(HomesteadResource.allCases.filter { cost[$0] > 0 }) { r in
                HStack(spacing: 1) {
                    Text("\(cost[r])").font(SR.Text.mono())
                    Image(systemName: r.symbol).font(.system(size: 10, weight: .semibold))
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
    /// The tile's colour, darkened where it would vanish on paper.
    static func of(_ r: HomesteadResource) -> Color {
        switch r {
        case .timber: return HomesteadPalette.tile(.woods)
        case .clay: return HomesteadPalette.tile(.claypit)
        case .wool: return Color(hex: 0x4F8A35)
        case .grain: return Color(hex: 0xA8841C)
        case .stone: return Color(hex: 0x5D6068)
        }
    }
}

/// One resource and how many: the hand's tiles.
struct HomesteadResourceTile: View {
    let resource: HomesteadResource
    let count: Int
    var note: String? = nil

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: resource.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(HomesteadResourceColour.of(resource))
            Text("\(count)")
                .font(SR.Text.figure(22))
                .foregroundStyle(SR.ink)
            Text(resource.label)
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let note {
                Text(note)
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.accentInk)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .srGlassCard(.paper)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) \(resource.rawValue)" + (note.map { ", \($0)" } ?? ""))
        .accessibilityIdentifier("homestead-res-\(resource.rawValue)")
    }
}

/// Minus, the count, plus — for picking how many of a resource.
struct HomesteadStepper: View {
    let resource: HomesteadResource
    let count: Int
    let canAdd: Bool
    let add: () -> Void
    let remove: () -> Void
    var id: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: resource.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(HomesteadResourceColour.of(resource))
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(resource.label)
                .font(SR.Text.body())
                .foregroundStyle(SR.ink)
            Spacer(minLength: 8)
            Button { remove(); SRHaptic.select() } label: {
                Image(systemName: "minus.circle.fill").font(.system(size: 26))
            }
            .buttonStyle(.plain)
            .foregroundStyle(count > 0 ? SR.accent : SR.inkGhost)
            .disabled(count == 0)
            .accessibilityLabel("One less \(resource.rawValue)")
            Text("\(count)")
                .font(SR.Text.figure(20))
                .monospacedDigit()
                .frame(minWidth: 28)
                .accessibilityLabel("\(count) \(resource.rawValue)")
            Button { add(); SRHaptic.select() } label: {
                Image(systemName: "plus.circle.fill").font(.system(size: 26))
            }
            .buttonStyle(.plain)
            .foregroundStyle(canAdd ? SR.accent : SR.inkGhost)
            .disabled(!canAdd)
            .accessibilityLabel("One more \(resource.rawValue)")
        }
        .padding(.vertical, 4)
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
        .accessibilityIdentifier(id)
    }
}

/// My cards: resources, almanac cards to play, the price list and the hints.
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

    private func cardRow(_ held: HomesteadHeldCard, me: HomesteadMe) -> some View {
        let playable = state.legal.playable.contains(held.kind) && !held.new && !me.playedCardThisTurn
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: held.kind.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(SR.accentInk)
                    .frame(width: 28)
                    .accessibilityHidden(true)
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
                }
                .srButton(.prominent)
                .accessibilityIdentifier("homestead-harvest-go")
            } else if asking == held.kind, held.kind == .market {
                resourcePicker("Resource", selection: $market)
                Button { store.play(.market, resource: market) } label: {
                    SRButtonLabel(title: "Ask everyone for their \(market.rawValue)", icon: "storefront.fill", fill: true)
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
                    HStack {
                        Text(key == "card" ? "Almanac card" : key.capitalized)
                            .font(SR.Text.body())
                            .foregroundStyle(SR.ink)
                        Spacer(minLength: 8)
                        HomesteadCostRow(cost: state.cost(key), hand: state.me?.hand)
                    }
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
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
                }
                .srButton(.prominent)
                .controlSize(.large)
                .disabled(give == nil || get == nil || give == get || store.sending)
                .accessibilityIdentifier("homestead-bank-go")
            }
        }
    }

    private func summary(_ me: HomesteadMe) -> String {
        guard let give, let get else { return "Pick what to give and get" }
        return "Give \(me.rate(give)) \(give.rawValue), get 1 \(get.rawValue)"
    }

    private func choice(_ r: HomesteadResource, line: String, selected: Bool, enabled: Bool, id: String,
                        action: @escaping () -> Void) -> some View {
        Button { action(); SRHaptic.select() } label: {
            HStack(spacing: 12) {
                Image(systemName: r.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(HomesteadResourceColour.of(r))
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.label).font(SR.Text.title()).foregroundStyle(SR.ink)
                    Text(line).font(SR.Text.mono()).foregroundStyle(SR.inkMuted)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? SR.accent : SR.inkGhost)
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 10)
            .srGlassCard(.paper)
        }
        .buttonStyle(.plain)
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
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HomesteadSeatMark(colour: state.colour(of: offer.from), side: 18)
                Text("\(name(offer.from)) \(offer.isCounter ? "counters" : "offers") \(audience)")
                    .font(SR.Text.title(15))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if !offer.isOpen {
                    SRGlassChip(text: statusLabel(offer), tone: SR.inkMuted)
                }
            }
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("GIVES").font(SR.Text.label()).foregroundStyle(SR.inkMuted)
                    HomesteadCostRow(cost: offer.give)
                }
                Image(systemName: "arrow.left.arrow.right").foregroundStyle(SR.inkMuted).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("WANTS").font(SR.Text.label()).foregroundStyle(SR.inkMuted)
                    HomesteadCostRow(cost: offer.want)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Gives \(offer.give.text()), wants \(offer.want.text())")
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
            HStack(spacing: 8) {
                if role.canAccept {
                    Button { store.accept(offer.id) } label: { SRButtonLabel(title: "Accept", icon: "checkmark", fill: true) }
                        .srButton(.prominent)
                        .accessibilityIdentifier("homestead-accept-\(offer.id)")
                }
                if role.canCounter {
                    Button {
                        counterTo = offer
                        draft = HomesteadTradeDraft(give: offer.want, want: offer.give)
                    } label: { SRButtonLabel(title: "Counter", icon: "arrow.uturn.left", fill: true) }
                        .srButton(.regular)
                        .accessibilityIdentifier("homestead-counter-\(offer.id)")
                }
                if role.canRefuse {
                    Button { store.refuse(offer.id) } label: { SRButtonLabel(title: "No thanks", fill: true) }
                        .srButton(.regular)
                        .accessibilityIdentifier("homestead-refuse-\(offer.id)")
                }
                if role.canCancel {
                    Button { store.cancel(offer.id) } label: { SRButtonLabel(title: "Withdraw", icon: "xmark", fill: true) }
                        .srButton(.regular)
                        .accessibilityIdentifier("homestead-cancel-\(offer.id)")
                }
            }
            .disabled(store.sending)
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .opacity(offer.isOpen ? 1 : 0.6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homestead-offer-\(offer.id)")
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
            SRSectionLabel(text: counterTo == nil ? "Make an offer" : "Your counter to \(name(counterTo!.from))")
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
                }
                .srButton(.prominent)
                .disabled(problem != nil || store.sending)
                .accessibilityIdentifier("homestead-offer-go")
                if counterTo != nil {
                    Button {
                        counterTo = nil
                        draft = HomesteadTradeDraft()
                    } label: { SRButtonLabel(title: "Never mind", fill: true) }
                        .srButton(.regular)
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
                        let on = to.contains(p.id)
                        Button {
                            to.formSymmetricDifference([p.id])
                            SRHaptic.select()
                        } label: {
                            HStack(spacing: 6) {
                                HomesteadSeatMark(colour: p.colour, side: 18)
                                Text(p.name).font(SR.Text.bodyMedium(15))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(on ? SR.accent.opacity(0.2) : SR.paper.opacity(0.6)))
                            .overlay(Capsule().strokeBorder(on ? SR.accent : SR.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(SR.ink)
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .accessibilityIdentifier("homestead-to-\(p.id)")
                    }
                }
            }
            Text("Pick nobody to offer it to everyone.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
        }
    }
}

/// After a 7: put back exactly half (rounded down) of what I hold.
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
                    VStack(spacing: 0) {
                        ForEach(HomesteadResource.allCases) { r in
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
                    .padding(SR.cardPadding)
                    .srGlassCard(.paper)
                    Button { store.discard(draft) } label: {
                        SRButtonLabel(title: "Put back \(draft.cards.total) of \(owed)", icon: "tray.and.arrow.up.fill", fill: true)
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
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: entry.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(entry.by.map { HomesteadPalette.colour(state.colour(of: $0)) } ?? SR.inkMuted)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    Text(entry.text + (entry.auto ? " (timed out)" : ""))
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("homestead-log")
    }
}

// MARK: - Finished

struct HomesteadFinished: View {
    let room: GameRoom
    @ObservedObject var store: HomesteadStore
    let done: () -> Void

    private var state: HomesteadState? { room.homestead }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Homestead · \(state.map(HomesteadText.rules) ?? GameDifficulty.label(for: room.difficulty)) · final",
                             title: GameResults.title(room, solo: "Game over", none: "Nobody won"),
                             strap: GameResults.strap(room))

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

                if let state, !state.board.hexes.isEmpty {
                    VStack(alignment: .leading, spacing: SR.cardGap) {
                        SRSectionLabel(text: "The island at the end")
                        HomesteadBoardView(state: state)
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
