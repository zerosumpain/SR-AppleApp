import SwiftUI
import UIKit

/// One Fireworks room, from lobby to the last bang.
///
/// The lobby and the 3-2-1 are every game's (`GameLobby`, `GameCountdownView`),
/// with the rule the host picked and how to play as the lobby's panel; Start
/// waits for a second player.
///
/// Play is a night sky across the top — each colour a rocket that climbs a
/// segment per card and bursts bigger the higher it gets, with a real burst
/// when a card lands and a shake of the misfire fuses when one does not —
/// then the table's tokens, the deck and the score. Below, everyone else's
/// hand face up: on my turn each has a big Hint button, and the hint is put
/// together right there, the cards it would point at lifting before it is
/// sent. My own hand is face down (night-blue backs), each card saying only
/// what hints have told me; tap one to play or drop it with the big buttons
/// under it. A banner at the top says whose turn it is, with the clock.
///
/// The finish is the team's score under a finale of fireworks in the show's
/// own colours, the show in a sentence, and this phone's best show.
///
/// There is no pause — the turn clock is everyone's — so the "?" in the bar
/// opens how to play over a table that carries on.
struct FireworksScreen: View {
    let roomId: String
    @StateObject private var store: FireworksStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingHowTo = false

    init(roomId: String) {
        self.roomId = roomId
        _store = StateObject(wrappedValue: FireworksStore(roomId: roomId))
    }

    var body: some View {
        content
            .navigationTitle("Fireworks")
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
                        TableHelpButton(id: "fireworks-help") { showingHowTo = true }
                    }
                }
            }
            .sheet(isPresented: $showingHowTo) {
                TableHowToSheet(game: "Fireworks", steps: FireworksHowTo.steps,
                                note: TableHowToNote.live, id: "fireworks-how-to")
            }
    }

    private var immersive: Bool {
        guard !store.ended, let room = store.room else { return false }
        return FireworksScreenPhase.of(room) == .countdown
    }

    private var showsHelp: Bool {
        guard !store.ended, let room = store.room else { return false }
        return FireworksScreenPhase.of(room) == .playing
    }

    @ViewBuilder
    private var content: some View {
        if store.ended {
            GameEndedView(id: "fireworks-ended", done: { dismiss() })
        } else if let room = store.room {
            switch FireworksScreenPhase.of(room) {
            case .lobby, .unknown:
                GameLobby(room: room, store: store, prefix: "fireworks", done: { dismiss() },
                          panel: AnyView(FireworksTableCard(room: room)),
                          startBlocked: room.playing.count < 2)
            case .countdown:
                GameCountdownView(room: room, store: store,
                                  note: "You can see everyone's cards but your own. Hints are how you learn yours.",
                                  id: "fireworks-countdown")
            case .playing:
                FireworksPlaying(room: room, store: store, done: { dismiss() })
            case .finished:
                FireworksFinished(room: room, store: store, done: { dismiss() })
            case .closed:
                GameEndedView(id: "fireworks-ended", done: { dismiss() })
            }
        } else {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    ForEach(FireworksRules.baseColours, id: \.self) { colour in
                        FireworksBurstGlyph(colour: colour, strength: 0.6)
                            .frame(width: 40, height: 40)
                    }
                }
                ProgressView()
                    .tint(FireworksPaint.starlight)
                Text("Setting up the show…")
                    .font(SR.Text.secondary())
                    .foregroundStyle(FireworksPaint.starlight)
            }
            .padding(24)
            .background(FireworksNight())
            .padding(SR.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .srPaper()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Setting up the show")
        }
    }
}

// MARK: - How to play

enum FireworksHowTo {
    static let steps = [
        TableHowToStep(icon: "person.3.fill", title: "One team, one show",
                       text: "Everyone plays together. Build each colour's firework from 1 up to 5, in order."),
        TableHowToStep(icon: "eye.slash.fill", title: "Your cards face away",
                       text: "You can see everybody's cards except your own, so you need the others to tell you about yours."),
        TableHowToStep(icon: "lightbulb.fill", title: "Give a hint",
                       text: "On your turn, point at every card of one colour, or of one number, in somebody's hand. Each hint costs a token."),
        TableHowToStep(icon: "sparkles", title: "Play or drop",
                       text: "Play a card you think goes next. A wrong one is a misfire. Dropping a card wins a hint token back."),
        TableHowToStep(icon: "flag.checkered", title: "The show ends",
                       text: "Too many misfires stops it. Otherwise, when the deck runs out everyone has one last turn. Every card in the fireworks scores a point."),
    ]
}

// MARK: - Colours

/// The suits as paint. Fixed in both themes — they are cards on a table —
/// and every card also SAYS its colour, so nobody needs to tell red from green.
enum FireworksPaint {
    static func fill(_ colour: String) -> Color {
        switch colour {
        case "red": return Color(hex: 0xC4473C)
        case "yellow": return Color(hex: 0xE3B22B)
        case "green": return Color(hex: 0x3A8658)
        case "blue": return Color(hex: 0x2F5FA8)
        case "white": return Color(hex: 0xF4EFE4)
        default: return Color(hex: 0x6B4A9B)
        }
    }

    /// Ink that reads on the fill.
    static func ink(_ colour: String) -> Color {
        colour == "yellow" || colour == "white" ? Color(hex: 0x1E1B16) : Color(hex: 0xFBF7EF)
    }

    /// The prism's sheen: every colour at once.
    static var prism: AngularGradient {
        AngularGradient(colors: ["red", "yellow", "green", "blue", "white", "red"].map(fill), center: .center)
    }

    /// A short tag printed on every card.
    static func tag(_ colour: String) -> String {
        colour == FireworksRules.prism ? "PRISM" : colour.uppercased()
    }

    /// A suit as a fill for any shape: the prism's sheen, or the flat colour.
    static func shading(_ colour: String) -> AnyShapeStyle {
        colour == FireworksRules.prism ? AnyShapeStyle(prism) : AnyShapeStyle(fill(colour))
    }

    /// A burst's colour: the prism cycles through the other five.
    static func spark(_ colour: String, _ i: Int) -> Color {
        guard colour == FireworksRules.prism else { return fill(colour) }
        let all = FireworksRules.baseColours
        return fill(all[i % all.count])
    }

    // The night the show is set against: deep blue in both themes, with
    // starlight type on it (well over 7:1).
    static let nightTop = Color(hex: 0x0B1030)
    static let nightBottom = Color(hex: 0x232A63)
    static let starlight = Color(hex: 0xEEF0FF)
    static let starlightSoft = Color(hex: 0xEEF0FF, alpha: 0.74)

    static var night: LinearGradient {
        LinearGradient(colors: [nightTop, nightBottom], startPoint: .top, endPoint: .bottom)
    }
}

/// The night sky: a deep blue slab with a scatter of fixed stars.
struct FireworksNight: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
        ZStack {
            shape.fill(FireworksPaint.night)
            Canvas { context, size in
                for i in 0..<38 {
                    let x = TableSparks.unit(91, i) * Double(size.width)
                    let y = TableSparks.unit(17, i) * Double(size.height) * 0.8
                    let r = 0.6 + 1.1 * TableSparks.unit(5, i)
                    let glow = 0.25 + 0.5 * TableSparks.unit(3, i)
                    let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(glow)))
                }
            }
            .clipShape(shape)
        }
        .shadow(color: Color.black.opacity(0.22), radius: 12, x: 0, y: 6)
        .accessibilityHidden(true)
    }
}

/// A firework, drawn once: rays and sparks round a bright core, reaching
/// further (and with more rays) the higher `strength` is, 0…1. At 0 it is an
/// unlit rocket on its stick.
struct FireworksBurstGlyph: View {
    let colour: String
    let strength: Double

    var body: some View {
        Canvas { context, size in
            let w = Double(size.width)
            let h = Double(size.height)
            let cx = w / 2
            let cy = h / 2
            if strength <= 0 {
                var stick = Path()
                stick.move(to: CGPoint(x: cx, y: h - 2))
                stick.addLine(to: CGPoint(x: cx, y: h * 0.55))
                context.stroke(stick, with: .color(Color.white.opacity(0.28)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                let head = CGRect(x: cx - 3, y: h * 0.55 - 7, width: 6, height: 8)
                context.fill(Path(roundedRect: head, cornerRadius: 2), with: .color(FireworksPaint.spark(colour, 0).opacity(0.55)))
                return
            }
            let maxR = min(w, h) / 2 - 2
            let reach = maxR * (0.42 + 0.58 * min(1, strength))
            let rays = 8 + Int((min(1, strength) * 8).rounded())
            for i in 0..<rays {
                let a = Double(i) / Double(rays) * 2 * Double.pi
                let inner = reach * 0.28
                var ray = Path()
                ray.move(to: CGPoint(x: cx + cos(a) * inner, y: cy + sin(a) * inner))
                ray.addLine(to: CGPoint(x: cx + cos(a) * reach * 0.86, y: cy + sin(a) * reach * 0.86))
                let tint = FireworksPaint.spark(colour, i)
                context.stroke(ray, with: .color(tint.opacity(0.9)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                let dot = CGRect(x: cx + cos(a) * reach - 2, y: cy + sin(a) * reach - 2, width: 4, height: 4)
                context.fill(Path(ellipseIn: dot), with: .color(tint))
            }
            let core = CGRect(x: cx - 3.5, y: cy - 3.5, width: 7, height: 7)
            context.fill(Path(ellipseIn: core), with: .color(Color.white.opacity(0.95)))
        }
        .accessibilityHidden(true)
    }
}

/// The face of a card, front or back.
struct FireworksCardFace: View {
    /// Nil for a face-down card.
    let colour: String?
    let rank: Int?
    var lit: Bool = false
    var picked: Bool = false
    /// Under a face-down card: what it is known to be.
    var known: String? = nil
    var knownColour: String? = nil
    /// How wide a card may grow.
    var maxWidth: CGFloat = 72
    /// A face-down card's number, once hints have pinned it down.
    var knownRank: Int? = nil

    var body: some View {
        ZStack {
            background
            if let colour, let rank {
                front(colour, rank)
            } else {
                back
            }
        }
        .aspectRatio(0.7, contentMode: .fit)
        .frame(maxWidth: maxWidth)
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(edgeColour, lineWidth: edgeWidth)
        )
        .shadow(color: shadowColour, radius: shadowRadius, x: 0, y: shadowDrop)
        .offset(y: raised ? -8 : 0)
        .srAnimation(.snappy(duration: 0.18), value: raised)
    }

    // The lifted look, worked out once (and kept out of the modifier chain, so
    // the type checker has plain values to work with).
    private var raised: Bool { picked || lit }
    private var edgeColour: Color {
        if picked { return SR.accent }
        if lit { return SR.accent.opacity(0.95) }
        return Color.black.opacity(0.22)
    }
    private var edgeWidth: CGFloat { raised ? 3 : 1 }
    private var shadowColour: Color { raised ? SR.accent.opacity(0.45) : Color.black.opacity(0.14) }
    private var shadowRadius: CGFloat { raised ? 8 : 2 }
    private var shadowDrop: CGFloat { raised ? 4 : 1 }

    private func front(_ colour: String, _ rank: Int) -> some View {
        let ink = FireworksPaint.ink(colour)
        return VStack(spacing: 1) {
            Image(systemName: "sparkle")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(ink.opacity(0.8))
                .accessibilityHidden(true)
            Text("\(rank)")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(FireworksPaint.tag(colour))
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(4)
    }

    private var back: some View {
        VStack(spacing: 2) {
            if let knownRank {
                Text("\(knownRank)")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(FireworksPaint.starlight)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            } else {
                Image(systemName: "sparkle")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(knownColour.map(FireworksPaint.fill) ?? FireworksPaint.starlightSoft)
                    .accessibilityHidden(true)
            }
            Text(known ?? "?")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(FireworksPaint.starlight)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 2)
        }
        .padding(4)
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        if let colour, rank != nil {
            ZStack {
                shape.fill(FireworksPaint.shading(colour))
                shape.fill(LinearGradient(colors: [Color.white.opacity(0.28), Color.clear],
                                          startPoint: .top, endPoint: .center))
                shape.inset(by: 3).strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
            }
        } else {
            ZStack {
                shape.fill(FireworksPaint.night)
                if let knownColour {
                    shape.inset(by: 3).strokeBorder(FireworksPaint.shading(knownColour), lineWidth: 3)
                } else {
                    shape.inset(by: 3).strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                }
            }
        }
    }
}

/// A small card for the discards: the number in its suit's colour.
struct FireworksMiniCard: View {
    let colour: String
    let rank: Int

    var body: some View {
        Text("\(rank)")
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .foregroundStyle(FireworksPaint.ink(colour))
            .frame(width: 26, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(FireworksPaint.shading(colour))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.2), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Lobby

/// The rule the host picked, in the lobby, under a little night sky with a
/// firework per colour — and how to play, and, until two are in, that it
/// needs two.
struct FireworksTableCard: View {
    let room: GameRoom

    private var colours: [String] {
        room.fireworks?.colours ?? (room.difficulty == "hard" ? FireworksRules.baseColours + [FireworksRules.prism] : FireworksRules.baseColours)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sky
                .accessibilityHidden(true)
            Text((room.fireworks?.rule ?? GameDifficulty.label(for: room.difficulty)).uppercased())
                .font(SR.Text.label())
                .tracking(SR.kickerTracking)
                .foregroundStyle(SR.accent)
                .fixedSize(horizontal: false, vertical: true)
            Text("One team, one show")
                .font(SR.Text.title())
                .foregroundStyle(SR.ink)
            Text("Play each colour from 1 to 5 in order. You see everyone's cards but your own, so the team gives hints — a colour or a number — and each hint costs a token. Dropping a card wins one back.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            TableHowToList(steps: Array(FireworksHowTo.steps.dropFirst().prefix(3)))
            if room.playing.count < 2 {
                Label("Needs one more player.", systemImage: "person.2.fill")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .accessibilityIdentifier("fireworks-needs-two")
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fireworks-table")
    }

    private var sky: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(colours.enumerated()), id: \.element) { index, colour in
                VStack(spacing: 6) {
                    FireworksBurstGlyph(colour: colour, strength: 0.4 + 0.12 * Double(index))
                        .frame(height: 44)
                    FireworksCardFace(colour: colour, rank: 5)
                        .frame(width: 34)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .background(FireworksNight())
    }
}

// MARK: - The table

/// A wobble, for the misfire fuses when one burns: it shakes as the value
/// rolls on by one, and is still at every whole number.
struct FireworksShake: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 7 * sin(animatableData * .pi * 4), y: 0))
    }
}

/// Hint tokens as counters, misfires as fuses, the deck and the score.
struct FireworksCounters: View {
    let state: FireworksState
    /// Counts misfires seen on this screen, so a new one shakes the fuses.
    var shake: Int = 0

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                hints
                misfires
            }
            HStack(spacing: 10) {
                deck
                score
            }
        }
    }

    private func tile<Content: View>(_ label: String, spoken: String, id: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(SR.Text.label())
                .tracking(1)
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier(id)
    }

    private var hints: some View {
        tile("HINT TOKENS", spoken: "\(state.hints) of \(state.maxHints) hint tokens", id: "fireworks-hints") {
            HStack(spacing: 8) {
                tokenDots
                Text("\(state.hints)/\(state.maxHints)")
                    .font(SR.Text.figure(17))
                    .foregroundStyle(state.hints == 0 ? SR.error : SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    private var tokenDots: some View {
        let columns = max(1, (state.maxHints + 1) / 2)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                ForEach(0..<columns, id: \.self) { i in token(i) }
            }
            HStack(spacing: 3) {
                ForEach(columns..<max(columns, state.maxHints), id: \.self) { i in token(i) }
            }
        }
    }

    private func token(_ i: Int) -> some View {
        let on = i < state.hints
        return Circle()
            .fill(on ? SR.accent : Color.clear)
            .overlay(Circle().strokeBorder(on ? SR.accent : SR.inkGhost, lineWidth: 1.5))
            .frame(width: 10, height: 10)
    }

    private var misfires: some View {
        let danger = state.misfires + 1 >= state.maxMisfires
        return tile("MISFIRES", spoken: "\(state.misfires) of \(state.maxMisfires) misfires", id: "fireworks-misfires") {
            HStack(spacing: 4) {
                ForEach(0..<max(0, state.maxMisfires), id: \.self) { i in
                    Image(systemName: i < state.misfires ? "flame.fill" : "flame")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(i < state.misfires ? SR.error : SR.inkGhost)
                }
                Spacer(minLength: 4)
                Text("\(state.misfires)/\(state.maxMisfires)")
                    .font(SR.Text.figure(17))
                    .foregroundStyle(danger ? SR.error : SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .modifier(FireworksShake(animatableData: CGFloat(shake)))
            .srAnimation(.linear(duration: 0.45), value: shake)
        }
    }

    private var deck: some View {
        tile("DECK", spoken: state.finalTurns.map { "Deck empty, \($0) turns left" } ?? "\(state.deck) cards to draw",
             id: "fireworks-deck") {
            HStack(spacing: 6) {
                Image(systemName: state.finalTurns == nil ? "rectangle.stack.fill" : "hourglass")
                    .font(SR.Text.title())
                    .foregroundStyle(state.finalTurns == nil ? SR.inkSecondary : SR.error)
                Text(state.finalTurns.map { "\($0) left" } ?? "\(state.deck)")
                    .font(SR.Text.figure(20))
                    .foregroundStyle(state.finalTurns == nil ? SR.ink : SR.error)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
    }

    private var score: some View {
        tile("SCORE", spoken: "Score \(state.score) of \(state.maxScore)", id: "fireworks-score") {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(state.score)")
                    .font(SR.Text.figure(24))
                    .foregroundStyle(SR.accent)
                    .srNumeric(Double(state.score))
                Text("of \(state.maxScore)")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
        }
    }
}

/// The show: one rocket per colour on a night sky, climbing a segment per
/// card and bursting bigger the higher it has got. When a card lands,
/// `flash` names its colour and a short burst goes off over the sky.
struct FireworksSky: View {
    let state: FireworksState
    var flash: String? = nil
    var flashKey: Int = 0
    /// How many cards have landed on each colour while on this screen: a
    /// change re-pops that colour's burst.
    var pulses: [String: Int] = [:]

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(state.colours, id: \.self) { colour in
                column(colour)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(FireworksNight())
        .overlay {
            if let flash {
                TableCelebration(colours: [FireworksPaint.spark(flash, flashKey), FireworksPaint.spark(flash, flashKey + 2), Color.white],
                                 bursts: 2, duration: 1.9, seed: flashKey)
                    .id(flashKey)
                    .clipShape(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fireworks-stacks")
    }

    private func column(_ colour: String) -> some View {
        let top = state.top(colour)
        return VStack(spacing: 6) {
            FireworksBurstGlyph(colour: colour, strength: Double(top) / 5)
                .frame(height: 52)
                .tablePopIn()
                .id("\(colour)-\(pulses[colour] ?? 0)")
            VStack(spacing: 3) {
                ForEach([5, 4, 3, 2, 1], id: \.self) { r in
                    segment(colour, lit: r <= top)
                }
            }
            Text(top == 0 ? "–" : "\(top)")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(FireworksPaint.starlight)
            Text(FireworksPaint.tag(colour))
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(FireworksPaint.starlightSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(FireworksRules.colourName(colour)): \(top == 0 ? "not started" : "up to \(top)")")
        .accessibilityIdentifier("fireworks-stack-\(colour)")
    }

    @ViewBuilder
    private func segment(_ colour: String, lit: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        if lit {
            shape.fill(FireworksPaint.shading(colour))
                .frame(height: 7)
        } else {
            shape.fill(Color.white.opacity(0.12))
                .frame(height: 7)
        }
    }
}

// MARK: - Playing

struct FireworksPlaying: View {
    let room: GameRoom
    @ObservedObject var store: FireworksStore
    /// Back to the games list, after leaving the show.
    let done: () -> Void
    @State private var confirmingLeave = false
    /// The colour that just went up, for the sky's burst.
    @State private var flashColour: String?
    @State private var flashKey = 0
    /// Misfires seen here, so a new one shakes the fuses.
    @State private var misfireShake = 0
    /// Cards landed on each colour while on this screen.
    @State private var pulses: [String: Int] = [:]

    private var state: FireworksState? { room.fireworks }
    private func name(_ id: String) -> String { id == room.meId ? "You" : room.name(of: id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                banner
                if let state {
                    FireworksSky(state: state, flash: flashColour, flashKey: flashKey, pulses: pulses)
                    FireworksCounters(state: state, shake: misfireShake)
                    ForEach(store.others) { seat in
                        otherHand(seat, state: state)
                    }
                    if store.seated { myHand(state) }
                    statusLine.frame(maxWidth: .infinity)
                    if !state.log.isEmpty { logCard(state) }
                    if !state.discards.isEmpty { discardsCard(state) }
                    if let rule = state.rule {
                        Label(rule, systemImage: "info.circle")
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("fireworks-rule")
                    }
                    if store.seated { leaveButton }
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("fireworks-playing")
        .onChange(of: store.refusal) { _, refusal in
            if let refusal { UIAccessibility.post(notification: .announcement, argument: refusal) }
        }
        .onChange(of: state?.log.count ?? 0) { old, new in
            noteMoves(from: old, to: new)
        }
        .confirmationDialog("Leave the show?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) {
                Task {
                    if await store.act("leave") { done() }
                }
            }
            Button("Keep playing", role: .cancel) {}
        } message: {
            Text(FireworksRules.leaveWarning(staying: store.others.count))
        }
    }

    /// A play just landed (the sky bursts in its colour) or misfired (the
    /// fuses shake). The store has already buzzed for it.
    private func noteMoves(from old: Int, to new: Int) {
        guard new > old, let entry = state?.log.last, entry.kind == .play else { return }
        if entry.ok == true, let colour = entry.card?.colour {
            flashColour = colour
            flashKey += 1
            pulses[colour, default: 0] += 1
        } else if entry.ok == false {
            misfireShake += 1
        }
    }

    private var leaveButton: some View {
        Button {
            SRHaptic.select()
            confirmingLeave = true
        } label: {
            TableButtonLabel(title: "Leave the show", icon: "rectangle.portrait.and.arrow.right")
        }
        .buttonStyle(TableSolidButtonStyle(outline: true))
        .disabled(store.busy)
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .accessibilityIdentifier("fireworks-leave")
    }

    // MARK: The banner

    private var banner: some View {
        VStack(alignment: .leading, spacing: 8) {
            TableTurnBanner(mine: store.myTurn) {
                TableTurnWords(mine: store.myTurn,
                               kicker: "Fireworks · turn \((state?.turn ?? 0) + 1) · \(GameDifficulty.label(for: room.difficulty))",
                               title: headline, detail: bannerDetail, titleId: "fireworks-headline")
            } clock: {
                if state?.turnId != nil {
                    TableTurnClock(store: store, endsAt: room.phaseEndsAt, turnMs: state?.turnMs ?? 75_000,
                                   mine: store.myTurn)
                        .accessibilityIdentifier("fireworks-turn-bar")
                }
            }
            if let left = state?.finalTurns {
                Label(left == 1 ? "The deck is empty: this is the last turn." : "The deck is empty: \(left) turns left.",
                      systemImage: "hourglass")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("fireworks-final")
            }
        }
    }

    private var headline: String {
        guard let state else { return "Setting up…" }
        if store.myTurn { return "Your turn" }
        guard let turn = state.turnId else { return "Waiting…" }
        return "\(room.name(of: turn))’s turn"
    }

    private var bannerDetail: String {
        guard let state else { return "" }
        if store.myTurn {
            return state.hints > 0 ? "Give somebody a hint, or play or drop one of your cards."
                : "No hint tokens left: play a card, or drop one to win a token back."
        }
        if !store.seated { return "You are watching this one." }
        return "Watch what they do — a hint might be about your cards."
    }

    // MARK: Everyone else's hands

    private func otherHand(_ seat: FireworksSeat, state: FireworksState) -> some View {
        let targeted = store.hintTarget == seat.id
        let preview = targeted ? store.previewIds : []
        let isTurn = state.turnId == seat.id
        return VStack(alignment: .leading, spacing: 12) {
            otherHeader(seat, isTurn: isTurn)
            otherCards(seat, state: state, preview: preview)
            if store.myTurn { hintButton(seat, targeted: targeted) }
            if targeted { hintComposer }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .overlay {
            if targeted {
                RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                    .strokeBorder(SR.accent, lineWidth: 2)
            }
        }
        .srAnimation(.snappy(duration: 0.25), value: targeted)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fireworks-hand-\(seat.id)")
    }

    private func otherHeader(_ seat: FireworksSeat, isTurn: Bool) -> some View {
        HStack(spacing: 8) {
            GameInitial(name: room.name(of: seat.id), tone: isTurn ? SR.accent : SR.accentInk, side: 30)
            Text(room.name(of: seat.id))
                .font(SR.Text.title())
                .foregroundStyle(SR.ink)
                .lineLimit(1)
            if isTurn {
                Text("PLAYING")
                    .font(SR.Text.label())
                    .tracking(1)
                    .foregroundStyle(SR.paper)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(SR.accent))
            }
            Spacer(minLength: 4)
            Text(GameResults.count(seat.hand.count, "card", "cards"))
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
        }
    }

    private func otherCards(_ seat: FireworksSeat, state: FireworksState, preview: Set<Int>) -> some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(seat.hand) { card in
                VStack(spacing: 6) {
                    FireworksCardFace(colour: card.colour, rank: card.rank, lit: preview.contains(card.id), maxWidth: 80)
                    Text(FireworksRules.knownText(card.knows, allColours: state.colours))
                        .font(SR.Text.label(12))
                        .foregroundStyle(card.knows?.hinted == true ? SR.accentInk : SR.inkGhost)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenOther(card, state: state, lit: preview.contains(card.id)))
                .accessibilityIdentifier("fireworks-card-\(card.id)")
            }
        }
        .padding(.top, 8)
    }

    private func hintButton(_ seat: FireworksSeat, targeted: Bool) -> some View {
        let who = room.name(of: seat.id)
        return Button {
            store.target(seat.id)
        } label: {
            TableButtonLabel(title: targeted ? "Cancel the hint" : "Hint \(who)",
                             icon: targeted ? "xmark" : "lightbulb.fill")
        }
        .buttonStyle(TableSolidButtonStyle(outline: targeted))
        .disabled(!store.canHint)
        .accessibilityLabel(targeted ? "Cancel the hint for \(who)" : "Give \(who) a hint")
        .accessibilityIdentifier("fireworks-hint-\(seat.id)")
    }

    private func spokenOther(_ card: FireworksCard, state: FireworksState, lit: Bool) -> String {
        var bits = [FireworksRules.cardText(card)]
        let known = FireworksRules.knownText(card.knows, allColours: state.colours)
        bits.append(known == "Nothing yet" ? "they know nothing about it yet" : "they know: \(known)")
        if lit { bits.append("this hint points at it") }
        return bits.joined(separator: ", ")
    }

    private var hintComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            let target = store.hintTarget.map { room.name(of: $0) } ?? "them"
            Divider().overlay(SR.divider)
            SRSectionLabel(text: "What to tell \(target)")
            if store.hintChoices.isEmpty {
                Text("No hint would point at anything in that hand.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
                    ForEach(store.hintChoices, id: \.self) { choice in
                        hintChip(choice)
                    }
                }
            }
            Button { store.sendHint() } label: {
                TableButtonLabel(title: sendTitle, icon: "lightbulb.fill")
            }
            .buttonStyle(TableSolidButtonStyle())
            .disabled(store.hint == nil || !store.canHint)
            .accessibilityIdentifier("fireworks-send-hint")
        }
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fireworks-hint-composer")
    }

    private var sendTitle: String {
        guard let hint = store.hint else { return "Pick a colour or a number" }
        let n = store.previewIds.count
        return "Point at \(n == 1 ? "1 card" : "\(n) cards"): \(hint.spoken)"
    }

    private func hintChip(_ choice: FireworksHint) -> some View {
        let on = store.hint == choice
        return Button { store.choose(choice) } label: {
            chipFace(choice, on: on)
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel("Hint \(choice.spoken)")
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("fireworks-choice-\(choiceId(choice))")
    }

    @ViewBuilder
    private func chipFace(_ choice: FireworksHint, on: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        switch choice {
        case .colour(let c):
            Text(FireworksRules.colourName(c))
                .font(SR.Text.label(13))
                .foregroundStyle(FireworksPaint.ink(c))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(shape.fill(FireworksPaint.fill(c)))
                .overlay(shape.strokeBorder(on ? SR.accent : Color.black.opacity(0.2), lineWidth: on ? 3.5 : 1))
                .overlay(alignment: .topTrailing) { if on { chipTick } }
        case .rank(let r):
            Text("\(r)")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(on ? SR.paper : SR.ink)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(shape.fill(on ? SR.accent : SR.surface))
                .overlay(shape.strokeBorder(on ? SR.accent : SR.line, lineWidth: on ? 3.5 : 1))
                .overlay(alignment: .topTrailing) { if on { chipTick } }
        }
    }

    private var chipTick: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(SR.paper, SR.accent)
            .offset(x: 5, y: -5)
            .accessibilityHidden(true)
    }

    private func choiceId(_ choice: FireworksHint) -> String {
        switch choice {
        case .colour(let c): return c
        case .rank(let r): return "\(r)"
        }
    }

    // MARK: My hand

    private func myHand(_ state: FireworksState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SRSectionLabel(text: "Your cards", trailing: "facing away")
            HStack(alignment: .top, spacing: 6) {
                ForEach(Array(store.myHand.enumerated()), id: \.element.id) { index, card in
                    myCard(card, index: index, state: state)
                }
            }
            .padding(.top, 8)
            if store.myTurn { myMoves }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("fireworks-my-hand")
    }

    private func myCard(_ card: FireworksCard, index: Int, state: FireworksState) -> some View {
        let known = FireworksRules.knownText(card.knows, allColours: state.colours)
        return VStack(spacing: 6) {
            FireworksCardFace(colour: nil, rank: nil, picked: store.pickedCard == card.id,
                              known: known, knownColour: card.knows?.colour, maxWidth: 80,
                              knownRank: card.knows?.rank)
            if let could = FireworksRules.couldText(card.could) {
                Text(could)
                    .font(SR.Text.label(12))
                    .foregroundStyle(SR.inkMuted)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .accessibilityIdentifier("fireworks-could-\(index)")
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { store.pick(card: card.id) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenMine(card, index: index, known: known))
        .accessibilityAddTraits(store.myTurn ? .isButton : [])
        .accessibilityAddTraits(store.pickedCard == card.id ? .isSelected : [])
        .accessibilityIdentifier("fireworks-mine-\(index)")
    }

    private var myMoves: some View {
        HStack(spacing: 10) {
            Button { store.play() } label: {
                TableButtonLabel(title: "Play it", icon: "sparkles")
            }
            .buttonStyle(TableSolidButtonStyle())
            .disabled(!store.canPlay)
            .accessibilityIdentifier("fireworks-play")
            Button { store.discard() } label: {
                TableButtonLabel(title: "Drop it", icon: "arrow.down.to.line")
            }
            .buttonStyle(TableSolidButtonStyle(outline: true))
            .disabled(store.pickedCard == nil || store.sending)
            .accessibilityIdentifier("fireworks-discard")
        }
        .padding(.top, 4)
    }

    private func spokenMine(_ card: FireworksCard, index: Int, known: String) -> String {
        var bits = ["Your card \(index + 1)", known == "Nothing yet" ? "nothing known yet" : known]
        if let could = FireworksRules.couldText(card.could) { bits.append(could.lowercased()) }
        if store.pickedCard == card.id { bits.append("picked") }
        return bits.joined(separator: ", ")
    }

    @ViewBuilder
    private var statusLine: some View {
        if let refusal = store.refusal {
            Label(refusal, systemImage: "exclamationmark.circle")
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.error)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("fireworks-refusal")
        } else if store.myTurn {
            Text(store.pickedCard != nil
                 ? "Play it onto its firework, or drop it for a hint token."
                 : store.hintTarget != nil ? "Pick what to tell them; the cards it points at light up."
                 : "Tap one of your cards, or Hint somebody.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("fireworks-guide")
        } else if !store.seated {
            Text("You are watching this one.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
        }
    }

    private func logCard(_ state: FireworksState) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "What happened", trailing: GameResults.count(state.log.count, "move", "moves"))
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(state.log.suffix(6).reversed().enumerated()), id: \.offset) { _, entry in
                    logRow(entry)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
            .accessibilityIdentifier("fireworks-log")
        }
    }

    private func logRow(_ entry: FireworksLogEntry) -> some View {
        let look = logLook(entry)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: look.icon)
                .font(SR.Text.title(15))
                .foregroundStyle(look.tone)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(FireworksRules.logLine(entry, name: name))
                .font(SR.Text.secondary())
                .foregroundStyle(entry.kind == .play && entry.ok == false ? SR.error : SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func logLook(_ entry: FireworksLogEntry) -> (icon: String, tone: Color) {
        switch entry.kind {
        case .hint: return ("lightbulb.fill", SR.accent)
        case .play: return entry.ok == true ? ("sparkles", SR.good) : ("burst.fill", SR.error)
        case .discard: return ("arrow.down.to.line", SR.inkMuted)
        case .unknown: return ("circle", SR.inkMuted)
        }
    }

    private func discardsCard(_ state: FireworksState) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Dropped and misfired", trailing: GameResults.count(state.discards.count, "card", "cards"))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(state.colours, id: \.self) { colour in
                    let ranks = state.discards.filter { $0.colour == colour }.compactMap(\.rank).sorted()
                    if !ranks.isEmpty {
                        HStack(spacing: 6) {
                            Text(FireworksRules.colourName(colour))
                                .font(SR.Text.bodyMedium(14))
                                .foregroundStyle(SR.ink)
                                .frame(width: 64, alignment: .leading)
                            ForEach(Array(ranks.enumerated()), id: \.offset) { _, rank in
                                FireworksMiniCard(colour: colour, rank: rank)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(FireworksDiscards.summary(state.discards, colours: state.colours))
            .accessibilityIdentifier("fireworks-discards")
        }
    }
}

/// The discard pile as a line per colour: "Red 1 1 4".
enum FireworksDiscards {
    static func summary(_ cards: [FireworksCard], colours: [String]) -> String {
        colours.compactMap { colour in
            let ranks = cards.filter { $0.colour == colour }.compactMap(\.rank).sorted()
            guard !ranks.isEmpty else { return nil }
            return "\(FireworksRules.colourName(colour)) " + ranks.map(String.init).joined(separator: " ")
        }
        .joined(separator: "\n")
    }
}

// MARK: - Finished

struct FireworksFinished: View {
    let room: GameRoom
    @ObservedObject var store: FireworksStore
    let done: () -> Void
    @State private var record: TableGameRecord?

    private var state: FireworksState? { room.fireworks }
    private var gameKey: String { TableGameKey.finished(roomId: room.id, startedAt: room.startedAt) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Fireworks · \(GameDifficulty.label(for: room.difficulty)) · final",
                             title: FireworksRules.verdict(score: state?.score ?? 0, max: state?.maxScore ?? 25),
                             strap: GameResults.strap(room))

                if let state {
                    finale(state)
                    scoreLine(state)
                    Text(FireworksRules.endingLine(state))
                        .font(SR.Text.bodyMedium(16))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("fireworks-outcome")
                }

                if let record {
                    TableRecordCard(record: record, gameKey: gameKey, bestLabel: "Best show",
                                    bestSuffix: "/\(state?.maxScore ?? 25)", showsWins: false, id: "fireworks-record")
                }

                teamCard

                GameFinishedButtons(room: room, store: store, prefix: "fireworks", done: done)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("fireworks-finished")
        .onAppear(perform: noteRecord)
    }

    /// The show, with a finale over it: more bursts the better it went.
    private func finale(_ state: FireworksState) -> some View {
        let bursts = min(10, max(3, state.score / 3))
        let colours = state.colours.map(FireworksPaint.fill) + [Color.white]
        return FireworksSky(state: state)
            .overlay {
                if state.score > 0 {
                    TableCelebration(colours: colours, bursts: bursts, duration: 4.2, seed: state.score)
                        .clipShape(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
                }
            }
    }

    private func scoreLine(_ state: FireworksState) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(state.score)")
                .font(SR.Text.figure(56))
                .foregroundStyle(SR.accent)
            Text("of \(state.maxScore)")
                .font(SR.Text.title())
                .foregroundStyle(SR.inkMuted)
            Spacer(minLength: 8)
            stars(state)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The team scored \(state.score) of \(state.maxScore)")
        .accessibilityIdentifier("fireworks-final-score")
    }

    /// Up to five stars for the share of the show that went up.
    private func stars(_ state: FireworksState) -> some View {
        let share = state.maxScore > 0 ? Double(state.score) / Double(state.maxScore) : 0
        let lit = Int((share * 5).rounded())
        return HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: i < lit ? "star.fill" : "star")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(i < lit ? Color(hex: 0xE3B22B) : SR.inkGhost)
                    .tablePopIn(delay: 0.4 + Double(i) * 0.12)
            }
        }
        .accessibilityHidden(true)
    }

    private func noteRecord() {
        guard let state, standing(room.meId) != nil else { return }
        let book = TableGameBestStore(gameId: GameKind.fireworks.rawValue, persists: !SRDemo.isOn)
        record = book.note(variant: "\(GameKind.fireworks.rawValue)-\(state.maxScore)", key: gameKey,
                           won: state.ending == "perfect", score: state.score)
    }

    private func standing(_ id: String) -> FireworksStanding? {
        state?.standings?.first { $0.id == id }
    }

    /// The team, without places: a shared result is not a ranking (the shared
    /// `GameStandingsCard` numbers its rows 1, 2, 3).
    private var teamCard: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            GameRecordLine(room: room)
            SRSectionLabel(text: "The team", trailing: state.map { "\($0.score) together" })
            VStack(spacing: 0) {
                ForEach(Array((room.standings ?? []).enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().overlay(SR.divider) }
                    teamRow(row)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
            .accessibilityIdentifier("fireworks-standings")
        }
    }

    private func teamRow(_ row: GameStanding) -> some View {
        let left = standing(row.id)?.left == true
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: left ? "figure.walk" : "sparkles")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(left ? SR.inkGhost : SR.accent)
                .frame(width: 28, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.name + (row.id == room.meId ? " (you)" : ""))
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                Text(FireworksRules.teamDetail(left: left))
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("fireworks-standings-\(row.id)")
    }
}
