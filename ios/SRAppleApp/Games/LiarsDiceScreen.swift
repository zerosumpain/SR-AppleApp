import SwiftUI
import UIKit

/// One Liar's Dice room, from lobby to the last die.
///
/// The lobby and the 3-2-1 are every game's (`GameLobby`, `GameCountdownView`),
/// with the table the host picked — dice each, whether ones are wild — and how
/// to play as the lobby's panel; Start waits for a second player (there is no
/// solo table).
///
/// Bidding is a felt table. Along the top, everybody else's cup with how many
/// dice it hides and their latest bid; in the middle, the standing bid, big;
/// at the bottom, my own dice (tap to drop the cup over them). Above the table
/// a banner says whose move it is, with the turn clock. On my turn a picker
/// offers only legal raises — big − and +, a die per face — and the two moves,
/// Liar! and Bid, sit pinned to the bottom of the screen so they are never a
/// scroll away. On easy and medium the picker says how likely a bid is, from
/// my own dice and the odds on everybody else's.
///
/// A call lifts every cup: a stamp says whether the bid stood, the dice that
/// count light up, and the loser's row is marked. The finish is the order
/// people went out in, a celebration for the winner, and the record this
/// phone keeps (`TableGameRecords`).
///
/// There is no pause: the turn clock is the server's and everyone's, so the
/// "?" in the bar opens how to play over a table that carries on.
struct LiarsDiceScreen: View {
    let roomId: String
    @StateObject private var store: LiarsDiceStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingHowTo = false

    init(roomId: String) {
        self.roomId = roomId
        _store = StateObject(wrappedValue: LiarsDiceStore(roomId: roomId))
    }

    var body: some View {
        content
            .navigationTitle("Liar's Dice")
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
            .toolbar {
                if showsHelp {
                    ToolbarItem(placement: .topBarTrailing) {
                        TableHelpButton(id: "liars-help") { showingHowTo = true }
                    }
                }
            }
            .sheet(isPresented: $showingHowTo) {
                TableHowToSheet(game: "Liar's Dice",
                                steps: LiarsDiceHowTo.steps(wild: store.room?.liarsDice?.wildOnes ?? true),
                                note: TableHowToNote.live,
                                id: "liars-how-to")
            }
    }

    private var immersive: Bool {
        guard !store.ended, let room = store.room else { return false }
        return LiarsDiceScreenPhase.of(room) == .countdown
    }

    private var showsHelp: Bool {
        guard !store.ended, let room = store.room else { return false }
        switch LiarsDiceScreenPhase.of(room) {
        case .bidding, .reveal: return true
        default: return false
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.ended {
            GameEndedView(id: "liars-ended", done: { dismiss() })
        } else if let room = store.room {
            switch LiarsDiceScreenPhase.of(room) {
            case .lobby, .unknown:
                GameLobby(room: room, store: store, prefix: "liars", done: { dismiss() },
                          panel: AnyView(LiarsDiceTableCard(room: room)),
                          startBlocked: room.playing.count < 2)
            case .countdown:
                GameCountdownView(room: room, store: store,
                                  note: "Only you can see your dice. Bid on what the whole table holds.",
                                  id: "liars-countdown")
            case .bidding, .reveal:
                LiarsDicePlaying(room: room, store: store)
            case .finished:
                LiarsDiceFinished(room: room, store: store, done: { dismiss() })
            case .closed:
                GameEndedView(id: "liars-ended", done: { dismiss() })
            }
        } else {
            LiarsDiceLoading()
        }
    }
}

/// Before the room's first answer: the cups on the felt, and a spinner.
struct LiarsDiceLoading: View {
    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                LiarsDiceCupArt(width: 54)
                LiarsDiceCupArt(width: 54)
                LiarsDiceCupArt(width: 54)
            }
            ProgressView()
                .tint(LiarsDicePaint.cream)
            Text("Finding the table…")
                .font(SR.Text.secondary())
                .foregroundStyle(LiarsDicePaint.creamSoft)
        }
        .padding(28)
        .background(LiarsDiceFelt())
        .padding(SR.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .srPaper()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Finding the table")
    }
}

// MARK: - How to play

enum LiarsDiceHowTo {
    static func steps(wild: Bool) -> [TableHowToStep] {
        var steps = [
            TableHowToStep(icon: "eye.slash.fill", title: "Peek at your dice",
                           text: "Everyone rolls under a cup. Only you can see your own dice."),
            TableHowToStep(icon: "arrow.up.circle.fill", title: "Bid on the whole table",
                           text: "Guess how many of one face are under all the cups together, like “three 5s”. Each bid must go higher: more dice, or as many of a higher face."),
            TableHowToStep(icon: "hand.raised.fill", title: "Or call “Liar!”",
                           text: "Think the last bid is too high? Call it. Every cup lifts and the dice are counted."),
            TableHowToStep(icon: "minus.circle.fill", title: "Somebody loses a die",
                           text: "If the dice were there, the caller loses one. If not, the bidder does. Lose them all and you are out."),
            TableHowToStep(icon: "crown.fill", title: "Last cup standing wins",
                           text: "Keep hold of at least one die when everybody else has lost theirs."),
        ]
        if wild {
            steps.insert(TableHowToStep(icon: "1.circle.fill", title: "Ones are wild",
                                        text: "A one counts as any face, so nobody bids on ones."), at: 3)
        }
        return steps
    }
}

// MARK: - Paint

/// The table's colours. Fixed in both themes: it is a felt table with
/// leather cups and ivory dice, not a page — and everything on it says what it
/// is in words too.
enum LiarsDicePaint {
    static let feltTop = Color(hex: 0x2E7A5A)
    static let feltBottom = Color(hex: 0x17483A)
    static let feltEdge = Color(hex: 0x0F3327)
    /// Type on the felt: 5:1 and up across the gradient.
    static let cream = Color(hex: 0xF6F1E4)
    static let creamSoft = Color(hex: 0xF6F1E4, alpha: 0.82)
    static let gold = Color(hex: 0xF2C14E)
    static let cupLight = Color(hex: 0xA6643A)
    static let cupDark = Color(hex: 0x5E3119)
    static let cupRim = Color(hex: 0xCB8C57)
    static let dieLight = Color(hex: 0xFFFDF7)
    static let dieDark = Color(hex: 0xE4DBC6)
    static let pip = Color(hex: 0x1E1B16)

    static var felt: LinearGradient {
        LinearGradient(colors: [feltTop, feltBottom], startPoint: .top, endPoint: .bottom)
    }

    static var cup: LinearGradient {
        LinearGradient(colors: [cupLight, cupDark], startPoint: .leading, endPoint: .trailing)
    }
}

/// The felt itself: a deep green slab with a dark edge and a faint gold rule.
struct LiarsDiceFelt: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
        ZStack {
            shape.fill(LiarsDicePaint.felt)
            shape.fill(RadialGradient(colors: [Color.white.opacity(0.12), Color.clear],
                                      center: .top, startRadius: 0, endRadius: 280))
            shape.strokeBorder(LiarsDicePaint.feltEdge, lineWidth: 4)
            shape.inset(by: 7).strokeBorder(LiarsDicePaint.gold.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Lobby

/// The table the host picked, in the lobby: three cups on the felt with a die
/// in front, dice each and the rule about ones, how to play in four lines —
/// and, until somebody else is in, that this game needs two.
struct LiarsDiceTableCard: View {
    let room: GameRoom

    var body: some View {
        let state = room.liarsDice
        VStack(alignment: .leading, spacing: 16) {
            scene
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(LiarsDiceSettings.about(state).uppercased())
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                Text((state?.wildOnes ?? true) ? "Ones are wild" : "No wilds")
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                Text(state?.rule ?? "Bid on what the whole table holds, or call the last bid a lie.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TableHowToList(steps: Array(LiarsDiceHowTo.steps(wild: state?.wildOnes ?? true).prefix(4)))
            if room.playing.count < 2 {
                Label("Needs at least two players.", systemImage: "person.2.fill")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .accessibilityIdentifier("liars-needs-two")
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("liars-table")
    }

    private var scene: some View {
        HStack(alignment: .bottom, spacing: 18) {
            LiarsDiceCupArt(width: 48)
            VStack(spacing: 6) {
                LiarsDiceCupArt(width: 56, glowing: true)
                HStack(spacing: 4) {
                    LiarsDie(face: 6, side: 22)
                    LiarsDie(face: 1, side: 22, lit: true)
                    LiarsDie(face: 3, side: 22)
                }
            }
            LiarsDiceCupArt(width: 48)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(LiarsDiceFelt())
    }
}

// MARK: - A die and a cup

/// One die: ivory with dark pips. `face` nil is a die under a cup — leather,
/// with a question mark. `lit` marks a die that counts (the accent, with a
/// gold rim); `dim` one that does not.
struct LiarsDie: View {
    let face: Int?
    var side: CGFloat = 52
    var lit: Bool = false
    var dim: Bool = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
        ZStack {
            shape
                .fill(faceFill)
                .shadow(color: Color.black.opacity(face == nil || dim ? 0 : 0.3),
                        radius: max(1, side * 0.05), x: 0, y: max(1, side * 0.05))
            shape
                .strokeBorder(lit ? LiarsDicePaint.gold : Color.black.opacity(0.14),
                              lineWidth: lit ? max(1.5, side * 0.06) : 1)
            if let face {
                pips(face)
            } else {
                Text("?")
                    .font(.system(size: side * 0.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(LiarsDicePaint.cream.opacity(0.9))
            }
        }
        .frame(width: side, height: side)
        .opacity(dim ? 0.38 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        guard let face else { return "Hidden" }
        return String(face)
    }

    private var faceFill: AnyShapeStyle {
        if face == nil { return AnyShapeStyle(LiarsDicePaint.cup) }
        if lit {
            return AnyShapeStyle(LinearGradient(colors: [SR.accent, SR.accentDeep],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        return AnyShapeStyle(LinearGradient(colors: [LiarsDicePaint.dieLight, LiarsDicePaint.dieDark],
                                            startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    /// Where the pips sit for each face, on a 3×3 grid (0…8, row-major).
    static func spots(_ face: Int) -> [Int] {
        switch face {
        case 1: return [4]
        case 2: return [2, 6]
        case 3: return [2, 4, 6]
        case 4: return [0, 2, 6, 8]
        case 5: return [0, 2, 4, 6, 8]
        default: return [0, 2, 3, 5, 6, 8]
        }
    }

    private func pips(_ face: Int) -> some View {
        let inset = side * 0.22
        let step = (side - inset * 2) / 2
        let pip = side * 0.19
        let on = Self.spots(face)
        return ZStack(alignment: .topLeading) {
            ForEach(on, id: \.self) { spot in
                Circle()
                    .fill(lit ? SR.paper : LiarsDicePaint.pip)
                    .frame(width: pip, height: pip)
                    .offset(x: inset + CGFloat(spot % 3) * step - pip / 2,
                            y: inset + CGFloat(spot / 3) * step - pip / 2)
            }
        }
        .frame(width: side, height: side, alignment: .topLeading)
    }
}

/// A dice cup, upside down on the felt: narrow at the top, a rim at the foot.
struct LiarsDiceCupShape: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.width * 0.17
        let round = rect.width * 0.08
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + inset + round, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - inset - round, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - inset + round * 0.4, y: rect.minY + round),
                       control: CGPoint(x: rect.maxX - inset, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + inset - round * 0.4, y: rect.minY + round))
        p.addQuadCurve(to: CGPoint(x: rect.minX + inset + round, y: rect.minY),
                       control: CGPoint(x: rect.minX + inset, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// A cup to draw: leather, a lighter rim, a gold glow when its owner is bidding.
struct LiarsDiceCupArt: View {
    var width: CGFloat = 56
    var glowing: Bool = false
    var faded: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            LiarsDiceCupShape()
                .fill(LiarsDicePaint.cup)
            LiarsDiceCupShape()
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
            Capsule()
                .fill(LiarsDicePaint.cupRim)
                .frame(height: max(4, width * 0.13))
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: width * 0.12, height: width * 0.42)
                .offset(x: -width * 0.16, y: -width * 0.22)
        }
        .frame(width: width, height: width * 0.86)
        .shadow(color: glowing ? LiarsDicePaint.gold.opacity(0.9) : Color.black.opacity(0.3),
                radius: glowing ? 10 : 3, x: 0, y: glowing ? 0 : 3)
        .saturation(faded ? 0 : 1)
        .opacity(faded ? 0.45 : 1)
        .accessibilityHidden(true)
    }
}

/// Another player at the felt: their cup, their latest bid in a bubble, their
/// name and a dot per die left.
struct LiarsDiceSeatView: View {
    let name: String
    let count: Int
    let out: Bool
    let left: Bool
    let turn: Bool
    let lastBid: LiarsDiceBid?

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .top) {
                LiarsDiceCupArt(width: 54, glowing: turn, faded: out)
                    .padding(.top, 16)
                if let lastBid, !out {
                    bubble(lastBid)
                        .tablePopIn()
                        .id("\(lastBid.quantity)x\(lastBid.face)")
                }
            }
            Text(name)
                .font(SR.Text.title(15))
                .foregroundStyle(LiarsDicePaint.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if out {
                Text(left ? "LEFT" : "OUT")
                    .font(SR.Text.label())
                    .tracking(1)
                    .foregroundStyle(LiarsDicePaint.creamSoft)
            } else {
                dots
            }
            if turn {
                Text("BIDDING")
                    .font(SR.Text.label())
                    .tracking(1)
                    .foregroundStyle(LiarsDicePaint.gold)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func bubble(_ bid: LiarsDiceBid) -> some View {
        HStack(spacing: 3) {
            Text("\(bid.quantity)×")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(LiarsDicePaint.pip)
            LiarsDie(face: bid.face, side: 17)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(LiarsDicePaint.cream))
        .overlay(Capsule().strokeBorder(bid.auto ? SR.error : Color.clear, lineWidth: 1.5))
    }

    private var dots: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(0, count), id: \.self) { _ in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(LiarsDicePaint.cream)
                    .frame(width: 9, height: 9)
            }
        }
        .frame(minHeight: 12)
    }
}

// MARK: - Bidding and the reveal

struct LiarsDicePlaying: View {
    let room: GameRoom
    @ObservedObject var store: LiarsDiceStore
    /// The cup is down over my dice: a peek-proof moment when somebody looks over.
    @State private var cupDown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var state: LiarsDiceState? { room.liarsDice }
    private var revealing: Bool { LiarsDiceScreenPhase.of(room) == .reveal }
    private var wild: Bool { state?.wildOnes ?? true }
    /// The odds are a guide on easy and medium; hard is played by feel.
    private var showsOdds: Bool { room.difficulty != "hard" }
    private var seatedHere: Bool { room.me?.joined == true && !store.myDice.isEmpty }
    private var showsActions: Bool { !revealing && room.me?.joined == true && store.myTurn }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                banner
                if revealing, let reveal = state?.reveal {
                    LiarsDiceRevealCard(room: room, reveal: reveal)
                } else {
                    felt
                    if showsActions { picker }
                    statusLine
                        .frame(maxWidth: .infinity)
                }
                if let bids = state?.bids, !bids.isEmpty, !revealing { talk(bids) }
                if let rule = state?.rule {
                    Label(rule, systemImage: "info.circle")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("liars-rule")
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsActions { actionBar }
        }
        .srAnimation(.snappy(duration: 0.3), value: showsActions)
        .accessibilityIdentifier(revealing ? "liars-reveal" : "liars-playing")
        .onChange(of: store.refusal) { _, refusal in
            if let refusal { UIAccessibility.post(notification: .announcement, argument: refusal) }
        }
        .onChange(of: revealing) { _, now in
            if now { revealFeedback() }
        }
        .onChange(of: state?.round) { _, _ in
            // A new round is a fresh roll: lift the cup so the new dice show.
            if cupDown { cupDown = false }
        }
    }

    // MARK: The banner

    private var banner: some View {
        TableTurnBanner(mine: showsActions) {
            VStack(alignment: .leading, spacing: 10) {
                TableTurnWords(mine: showsActions, kicker: kicker, title: bannerTitle, detail: bannerDetail)
                diceInPlay
            }
        } clock: {
            if !revealing, state?.turnId != nil {
                TableTurnClock(store: store, endsAt: room.phaseEndsAt, turnMs: state?.turnMs ?? 45_000,
                               mine: showsActions)
                    .accessibilityIdentifier("liars-turn-bar")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("liars-banner")
    }

    private var kicker: String {
        "Round \(state?.round ?? 1) · \(GameDifficulty.label(for: room.difficulty))"
    }

    private var bannerTitle: String {
        if revealing { return "Cups up!" }
        if showsActions { return "Your turn" }
        if room.me?.joined == true, store.myDice.isEmpty { return "You are out" }
        guard let turn = state?.turnId else { return "Rolling…" }
        return "\(room.name(of: turn)) is bidding"
    }

    private var bannerDetail: String {
        if revealing { return "Somebody called Liar! Every cup is lifted." }
        if showsActions {
            if !store.canBid { return "No bid can go higher. Call it!" }
            return state?.bid == nil ? "Open the bidding." : "Raise the bid, or call Liar!"
        }
        if room.me?.joined == true, store.myDice.isEmpty { return "Watch the rest play it out." }
        if room.me?.joined != true { return "You are watching this one." }
        return "Peek at your dice and plan your next bid."
    }

    private var diceInPlay: some View {
        HStack(spacing: 6) {
            Image(systemName: "die.face.5.fill")
                .font(SR.Text.label(13))
                .accessibilityHidden(true)
            Text("\(state?.totalDice ?? 0) DICE IN PLAY")
                .font(SR.Text.label())
                .tracking(1)
                .monospacedDigit()
        }
        .foregroundStyle(TableTurnInk.ink(showsActions))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(TableTurnInk.ink(showsActions).opacity(0.12)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(state?.totalDice ?? 0) dice in play")
        .accessibilityIdentifier("liars-total")
    }

    // MARK: The felt

    private var felt: some View {
        VStack(spacing: 18) {
            opponents
            standingBid
            mine
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(LiarsDiceFelt())
    }

    private var seated: [GamePlayer] {
        room.players.filter { state?.seat($0.id)?.seated ?? $0.joined }
    }

    private var others: [GamePlayer] { seated.filter { $0.id != room.meId } }

    @ViewBuilder
    private var opponents: some View {
        let list = others
        Group {
            if list.count <= 4 {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(list, id: \.id) { player in seat(player) }
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 14) {
                    ForEach(list, id: \.id) { player in seat(player) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("liars-seats")
    }

    private func seat(_ player: GamePlayer) -> some View {
        let seat = state?.seat(player.id)
        let count = seat?.diceCount ?? 0
        let out = seat?.out == true || !player.joined
        let turn = !revealing && state?.turnId == player.id
        let latest = state?.bids.last { $0.playerId == player.id }
        return LiarsDiceSeatView(name: player.name, count: count, out: out, left: !player.joined,
                                 turn: turn, lastBid: latest)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(seatSpoken(player, count: count, out: out, turn: turn, latest: latest))
            .accessibilityIdentifier("liars-seat-\(player.id)")
    }

    private func seatSpoken(_ player: GamePlayer, count: Int, out: Bool, turn: Bool, latest: LiarsDiceBid?) -> String {
        if out { return "\(player.name), \(player.joined ? "out" : "left")" }
        var bits = ["\(player.name), \(GameResults.count(count, "die", "dice"))"]
        if turn { bits.append("bidding now") }
        if let latest { bits.append("last bid \(LiarsDiceRules.bidText(quantity: latest.quantity, face: latest.face))") }
        return bits.joined(separator: ", ")
    }

    // MARK: The standing bid

    private var standingBid: some View {
        VStack(spacing: 6) {
            Text("STANDING BID")
                .font(SR.Text.label())
                .tracking(1.4)
                .foregroundStyle(LiarsDicePaint.creamSoft)
            if let bid = state?.bid {
                HStack(spacing: 12) {
                    Text("\(bid.quantity)")
                        .font(.system(size: 54, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(LiarsDicePaint.cream)
                    Text("×")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(LiarsDicePaint.creamSoft)
                    LiarsDie(face: bid.face, side: 52)
                }
                .tablePopIn()
                .id("\(state?.round ?? 0)|\(bid.playerId)|\(bid.quantity)x\(bid.face)")
                HStack(spacing: 6) {
                    Text(bid.playerId == room.meId ? "Your bid" : "\(room.name(of: bid.playerId))’s bid")
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(LiarsDicePaint.cream)
                    if bid.auto {
                        Text("TIMED OUT")
                            .font(SR.Text.label())
                            .tracking(1)
                            .foregroundStyle(LiarsDicePaint.pip)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(LiarsDicePaint.gold))
                    }
                }
                if showsOdds, room.me?.joined == true, let line = standingOdds(bid) {
                    oddsChip("Is it true? \(line)")
                }
            } else {
                Text("No bid yet")
                    .font(SR.Text.display(26))
                    .foregroundStyle(LiarsDicePaint.cream)
                Text(opener)
                    .font(SR.Text.secondary())
                    .foregroundStyle(LiarsDicePaint.creamSoft)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.2)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bidSpoken)
        .accessibilityIdentifier("liars-bid")
    }

    private func oddsChip(_ text: String) -> some View {
        Text(text)
            .font(SR.Text.mono())
            .foregroundStyle(LiarsDicePaint.cream)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.12)))
    }

    private var unseen: Int { max(0, (state?.totalDice ?? 0) - store.myDice.count) }

    private func standingOdds(_ bid: LiarsDiceBid) -> String? {
        guard !store.myDice.isEmpty || unseen > 0 else { return nil }
        let chance = LiarsDiceOdds.chance(quantity: bid.quantity, face: bid.face, mine: store.myDice,
                                          unseen: unseen, wild: wild)
        return LiarsDiceOdds.line(chance)
    }

    private var opener: String {
        guard let turn = state?.turnId else { return "" }
        return turn == room.meId ? "You open." : "\(room.name(of: turn)) opens."
    }

    private var bidSpoken: String {
        guard let bid = state?.bid else { return "No bid yet. \(opener)" }
        let who = bid.playerId == room.meId ? "You" : room.name(of: bid.playerId)
        let timed = bid.auto ? ", timed out" : ""
        var line = "Standing bid: \(LiarsDiceRules.bidText(quantity: bid.quantity, face: bid.face)), by \(who)\(timed)"
        if showsOdds, room.me?.joined == true, let odds = standingOdds(bid) { line += ". \(odds)" }
        return line
    }

    // MARK: My dice

    @ViewBuilder
    private var mine: some View {
        if seatedHere {
            myCup
        } else {
            Text(room.me?.joined == true ? "You are out of dice. Watch the rest play it out." : "You are not playing in this one.")
                .font(SR.Text.secondary())
                .foregroundStyle(LiarsDicePaint.creamSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private var dieSide: CGFloat { store.myDice.count > 5 ? 42 : 50 }

    private var myCup: some View {
        VStack(spacing: 8) {
            HStack {
                Text("YOUR DICE")
                    .font(SR.Text.label())
                    .tracking(1.4)
                    .foregroundStyle(LiarsDicePaint.creamSoft)
                Spacer(minLength: 8)
                Label("Only you can see these", systemImage: "eye")
                    .font(SR.Text.mono())
                    .foregroundStyle(LiarsDicePaint.creamSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityHidden(true)
            ZStack {
                HStack(spacing: 8) {
                    ForEach(Array(store.myDice.enumerated()), id: \.offset) { index, die in
                        LiarsDie(face: die, side: dieSide, lit: countsTowardsBid(die))
                            .tablePopIn(delay: Double(index) * 0.06)
                    }
                }
                .id(state?.round ?? 0)
                .opacity(cupDown ? 0 : 1)
                if cupDown {
                    LiarsDiceCupArt(width: 104)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, minHeight: dieSide + 28)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.black.opacity(0.22)))
            .contentShape(Rectangle())
            .onTapGesture { toggleCup() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(cupDown ? "Your dice, under the cup" : "Your dice: \(store.myDice.map(String.init).joined(separator: ", "))")
            .accessibilityHint(cupDown ? "Lifts the cup" : "Puts the cup down")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { toggleCup() }
            .accessibilityIdentifier("liars-my-dice")
            Text(cupDown ? "Tap the cup to peek." : "Tap to hide them under the cup.")
                .font(SR.Text.mono())
                .foregroundStyle(LiarsDicePaint.creamSoft)
                .accessibilityHidden(true)
        }
    }

    private func toggleCup() {
        SRHaptic.select()
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { cupDown.toggle() }
    }

    /// Whether one of my dice counts: towards the face I am picking on my
    /// turn, else towards the standing bid's.
    private func countsTowardsBid(_ die: Int) -> Bool {
        guard let state else { return false }
        if showsActions, store.canBid { return LiarsDiceRules.counts(die, towards: store.face, wild: state.wildOnes) }
        guard let bid = state.bid else { return false }
        return LiarsDiceRules.counts(die, towards: bid.face, wild: state.wildOnes)
    }

    // MARK: The picker

    private var picker: some View {
        VStack(alignment: .leading, spacing: 14) {
            SRSectionLabel(text: "Your bid", trailing: store.canBid ? "Only legal raises" : nil)
            if store.canBid {
                quantityRow
                facesRow
                pickedLine
            } else {
                Text("No bid can go higher than every die on the table. Call it.")
                    .font(SR.Text.bodyMedium(16))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("liars-picker")
    }

    private var quantityRow: some View {
        HStack(spacing: 12) {
            TableRoundButton(icon: "minus", label: "Fewer dice", enabled: store.canLowerQuantity,
                             id: "liars-quantity-down") { store.lowerQuantity() }
            VStack(spacing: 0) {
                Text("\(store.quantity)")
                    .font(SR.Text.hero(52))
                    .foregroundStyle(SR.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .srNumeric(Double(store.quantity))
                Text(store.quantity == 1 ? "DIE" : "DICE")
                    .font(SR.Text.label())
                    .tracking(1.2)
                    .foregroundStyle(SR.inkMuted)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(store.quantity) dice")
            .accessibilityValue("\(store.quantity)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: store.raiseQuantity()
                case .decrement: store.lowerQuantity()
                @unknown default: break
                }
            }
            .accessibilityIdentifier("liars-quantity")
            TableRoundButton(icon: "plus", label: "More dice", enabled: store.canRaiseQuantity,
                             id: "liars-quantity-up") { store.raiseQuantity() }
        }
    }

    private var facesRow: some View {
        HStack(spacing: 6) {
            ForEach(LiarsDiceRules.biddableFaces(wild: wild), id: \.self) { f in
                faceButton(f)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func faceButton(_ f: Int) -> some View {
        let legal = store.faceIsLegal(f)
        let picked = store.face == f
        return Button { store.pick(face: f) } label: {
            LiarsDie(face: f, side: 40, lit: picked, dim: !legal)
                .scaleEffect(picked ? 1.12 : 1)
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(picked ? SR.accent.opacity(0.16) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!legal)
        .srAnimation(.snappy(duration: 0.2), value: picked)
        .accessibilityLabel("\(f)s")
        .accessibilityAddTraits(picked ? .isSelected : [])
        .accessibilityIdentifier("liars-face-\(f)")
    }

    private var pickedLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Bid \(LiarsDiceRules.bidText(quantity: store.quantity, face: store.face))")
                .font(SR.Text.title())
                .foregroundStyle(SR.ink)
            Spacer(minLength: 8)
            if showsOdds {
                let chance = LiarsDiceOdds.chance(quantity: store.quantity, face: store.face, mine: store.myDice,
                                                  unseen: unseen, wild: wild)
                Text(LiarsDiceOdds.line(chance))
                    .font(SR.Text.mono())
                    .foregroundStyle(oddsTone(chance))
                    .multilineTextAlignment(.trailing)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("liars-picked")
    }

    private func oddsTone(_ chance: Double) -> Color {
        switch LiarsDiceOdds.feel(chance) {
        case .sure, .likely: return SR.good
        case .coinToss: return SR.inkSecondary
        case .unlikely, .longShot, .impossible: return SR.error
        }
    }

    // MARK: The moves, pinned to the bottom

    private var actionBar: some View {
        VStack(spacing: 8) {
            if let refusal = store.refusal {
                Label(refusal, systemImage: "exclamationmark.circle")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.error)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                    .accessibilityIdentifier("liars-refusal")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    liarButton
                    bidButton
                }
                VStack(spacing: 10) {
                    bidButton
                    liarButton
                }
            }
            if state?.bid == nil {
                Text("Nobody has bid yet, so there is nothing to call.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
        }
        .padding(.horizontal, SR.gutter)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider().overlay(SR.divider) }
        .srAnimation(.snappy(duration: 0.2), value: store.refusal)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var liarButton: some View {
        Button { store.callLiar() } label: {
            TableButtonLabel(title: "Liar!", icon: "hand.raised.fill")
        }
        .buttonStyle(TableSolidButtonStyle(fill: SR.error, ink: SR.paper))
        .disabled(!store.canCall)
        .accessibilityHint("Calls the standing bid a lie. Every cup is lifted.")
        .accessibilityIdentifier("liars-call")
    }

    private var bidButton: some View {
        Button { store.bid() } label: {
            TableButtonLabel(title: "Bid \(LiarsDiceRules.bidText(quantity: store.quantity, face: store.face))",
                             icon: "arrow.up")
        }
        .buttonStyle(TableSolidButtonStyle())
        .disabled(!store.canBid || !store.pickedIsLegal || store.sending)
        .accessibilityIdentifier("liars-bid-send")
    }

    @ViewBuilder
    private var statusLine: some View {
        if !store.myTurn, let turn = state?.turnId, room.me?.joined == true {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(SR.inkMuted)
                Text("Waiting for \(room.name(of: turn))…")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("liars-waiting")
        }
    }

    // MARK: Table talk

    private func talk(_ bids: [LiarsDiceBid]) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "This round", trailing: GameResults.count(bids.count, "bid", "bids"))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(bids.enumerated().reversed()), id: \.offset) { index, bid in
                    talkRow(bid, latest: index == bids.count - 1)
                }
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("liars-talk")
    }

    private func talkRow(_ bid: LiarsDiceBid, latest: Bool) -> some View {
        let who = bid.playerId == room.meId ? "You" : room.name(of: bid.playerId)
        return HStack(spacing: 10) {
            GameInitial(name: who, tone: latest ? SR.accent : SR.accentInk, side: 28)
            Text(who)
                .font(latest ? SR.Text.title(16) : SR.Text.bodyMedium(15))
                .foregroundStyle(latest ? SR.ink : SR.inkMuted)
                .lineLimit(1)
            Spacer(minLength: 8)
            if bid.auto {
                Text("TIMED OUT")
                    .font(SR.Text.label())
                    .tracking(1)
                    .foregroundStyle(SR.error)
            }
            Text("\(bid.quantity) ×")
                .font(SR.Text.figure(18))
                .foregroundStyle(SR.ink)
                .monospacedDigit()
            LiarsDie(face: bid.face, side: latest ? 28 : 22)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(who) bid \(LiarsDiceRules.bidText(quantity: bid.quantity, face: bid.face))\(bid.auto ? ", timed out" : "")")
    }

    // MARK: The reveal's moment

    /// A buzz for how the call went for me: I lost a die, or my call or my
    /// bid won the argument. (The store already ticks for the cups lifting.)
    private func revealFeedback() {
        guard let reveal = state?.reveal else { return }
        let me = room.meId
        if reveal.loserId == me {
            SRHaptic.bad()
        } else if reveal.challengerId == me || reveal.bid.playerId == me {
            SRHaptic.ok()
        }
    }
}

/// Every cup lifted after a call: a stamp with the verdict, the count against
/// the bid, the sentence, and each player's dice with the ones that count lit.
struct LiarsDiceRevealCard: View {
    let room: GameRoom
    let reveal: LiarsDiceReveal

    private var wild: Bool { room.liarsDice?.wildOnes ?? true }
    private func name(_ id: String) -> String { id == room.meId ? "You" : room.name(of: id) }

    var body: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Cups up")
            verdict
            cups
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("liars-reveal-card")
    }

    private var verdictTitle: String {
        reveal.bidStood ? "The bid stood!" : "Caught out!"
    }

    private var verdictTone: Color { reveal.bidStood ? SR.good : SR.error }

    private var verdict: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Label("\(name(reveal.challengerId)) called Liar!", systemImage: "hand.raised.fill")
                    .font(SR.Text.label(13))
                    .tracking(0.8)
                    .foregroundStyle(SR.paper)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(SR.error))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            Text(verdictTitle)
                .font(SR.Text.hero(36))
                .foregroundStyle(verdictTone)
                .fixedSize(horizontal: false, vertical: true)
                .tablePopIn()
            HStack(alignment: .center, spacing: 10) {
                Text("\(reveal.count)")
                    .font(SR.Text.hero(48))
                    .foregroundStyle(SR.ink)
                    .monospacedDigit()
                VStack(alignment: .leading, spacing: 0) {
                    Text("ON THE TABLE")
                        .font(SR.Text.label())
                        .tracking(1)
                        .foregroundStyle(SR.inkMuted)
                    Text("\(reveal.bid.quantity) were bid")
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(SR.inkSecondary)
                }
                Spacer(minLength: 0)
                LiarsDie(face: reveal.bid.face, side: 44, lit: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(reveal.count) on the table; \(reveal.bid.quantity) were bid")
            Text(LiarsDiceRules.revealLine(reveal) { name($0) })
                .font(SR.Text.bodyMedium(16))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("liars-reveal-line")
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .overlay(
            RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                .strokeBorder(verdictTone.opacity(0.55), lineWidth: 2)
        )
    }

    private var cups: some View {
        VStack(spacing: 10) {
            ForEach(Array(reveal.dice.enumerated()), id: \.element.id) { index, cup in
                cupRow(cup, index: index)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(LiarsDiceFelt())
    }

    private func cupRow(_ cup: LiarsDiceCup, index: Int) -> some View {
        let lost = cup.playerId == reveal.loserId
        let counting = LiarsDiceRules.tally([cup.dice], face: reveal.bid.face, wild: wild)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(name(cup.playerId))
                    .font(SR.Text.title())
                    .foregroundStyle(LiarsDicePaint.cream)
                    .lineLimit(1)
                if lost {
                    Text(reveal.eliminated ? "OUT" : "−1 DIE")
                        .font(SR.Text.label())
                        .tracking(1)
                        .foregroundStyle(SR.paper)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(SR.error))
                }
                Spacer(minLength: 8)
                Text(counting == 1 ? "1 COUNTS" : "\(counting) COUNT")
                    .font(SR.Text.label())
                    .tracking(1)
                    .monospacedDigit()
                    .foregroundStyle(LiarsDicePaint.gold)
            }
            HStack(spacing: 6) {
                ForEach(Array(cup.dice.enumerated()), id: \.offset) { dieIndex, die in
                    let hit = LiarsDiceRules.counts(die, towards: reveal.bid.face, wild: wild)
                    LiarsDie(face: die, side: 36, lit: hit, dim: !hit)
                        .tablePopIn(delay: Double(index) * 0.18 + Double(dieIndex) * 0.05)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(lost ? SR.error.opacity(0.28) : Color.black.opacity(0.2))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cupSpoken(cup))
        .accessibilityIdentifier("liars-cup-\(cup.playerId)")
    }

    private func cupSpoken(_ cup: LiarsDiceCup) -> String {
        let n = LiarsDiceRules.tally([cup.dice], face: reveal.bid.face, wild: wild)
        var line = "\(name(cup.playerId)): \(cup.dice.map(String.init).joined(separator: ", ")). \(n) counting."
        if cup.playerId == reveal.loserId { line += reveal.eliminated ? " Out." : " Loses a die." }
        return line
    }
}

// MARK: - Finished

struct LiarsDiceFinished: View {
    let room: GameRoom
    @ObservedObject var store: LiarsDiceStore
    let done: () -> Void
    @State private var record: TableGameRecord?

    private var iWon: Bool { room.winnerIds.contains(room.meId) }
    private var gameKey: String { TableGameKey.finished(roomId: room.id, startedAt: room.startedAt) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Liar's Dice · \(LiarsDiceSettings.about(room.liarsDice)) · final",
                             title: GameResults.title(room, solo: "Game over", none: "Nobody won"),
                             strap: GameResults.strap(room))

                hero

                GameStandingsCard(
                    room: room,
                    label: "Standings",
                    id: "liars-standings",
                    detail: detail,
                    figure: { row in
                        let dice = standing(row.id)?.dice ?? 0
                        return dice > 0 ? (text: "\(dice)", spoken: GameResults.count(dice, "die", "dice") + " left") : nil
                    }
                )

                if let record {
                    TableRecordCard(record: record, gameKey: gameKey, bestLabel: nil, id: "liars-record")
                }

                if let reveal = room.liarsDice?.reveal {
                    LiarsDiceRevealCard(room: room, reveal: reveal)
                }

                GameFinishedButtons(room: room, store: store, prefix: "liars", done: done)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .overlay {
            if iWon { TableCelebration(colours: TableCheer.colours, bursts: 7, duration: 3.4, seed: 11) }
        }
        .accessibilityIdentifier("liars-finished")
        .onAppear {
            if iWon { SRHaptic.ok() }
            noteRecord()
        }
    }

    /// The winner's moment: a crown over a cup, or where I finished.
    private var hero: some View {
        let mine = standing(room.meId)
        return HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(iWon ? SR.accent : SR.surface)
                    .frame(width: 76, height: 76)
                Image(systemName: iWon ? "crown.fill" : "die.face.3.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(iWon ? SR.paper : SR.inkMuted)
            }
            .tablePopIn()
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(heroTitle(mine))
                    .font(SR.Text.display(24))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(heroDetail(mine))
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("liars-hero")
    }

    private func heroTitle(_ mine: LiarsDiceStanding?) -> String {
        if iWon { return "Last cup standing" }
        guard let mine else { return "That's the game" }
        return "You came \(LiarsDiceFinished.ordinal(mine.place))"
    }

    private func heroDetail(_ mine: LiarsDiceStanding?) -> String {
        if iWon {
            let dice = mine?.dice ?? 0
            return dice > 0 ? "You finished with \(GameResults.count(dice, "die", "dice")) left under your cup." : "Nobody could out-bluff you."
        }
        guard let mine else { return "Thanks for watching." }
        if mine.left { return "You left the table." }
        return mine.outRound.map { "Out in round \($0). Ask for a rematch!" } ?? "Ask for a rematch!"
    }

    static func ordinal(_ n: Int) -> String {
        switch n {
        case 1: return "first"
        case 2: return "second"
        case 3: return "third"
        case 4: return "fourth"
        case 5: return "fifth"
        case 6: return "sixth"
        default: return "\(n)th"
        }
    }

    private func noteRecord() {
        guard standing(room.meId) != nil else { return }
        let store = TableGameBestStore(gameId: GameKind.liarsDice.rawValue, persists: !SRDemo.isOn)
        record = store.note(variant: GameKind.liarsDice.rawValue, key: gameKey, won: iWon, score: nil)
    }

    private func standing(_ id: String) -> LiarsDiceStanding? {
        room.liarsDice?.standings?.first { $0.id == id }
    }

    private func detail(_ row: GameStanding) -> String {
        guard let s = standing(row.id) else { return "" }
        if room.winnerIds.contains(row.id) { return "Last one with dice" }
        if s.left { return s.outRound.map { "Left in round \($0)" } ?? "Left" }
        return s.outRound.map { "Out in round \($0)" } ?? "Out"
    }
}
