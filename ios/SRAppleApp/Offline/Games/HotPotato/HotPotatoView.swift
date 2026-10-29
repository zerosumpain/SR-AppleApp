import SwiftUI

/// Hot Potato on one phone: who has it, your puzzle when it is you, and the
/// moment it bursts.
///
/// The holder's screen shows four shapes; tapping the odd one out unlocks
/// everyone still in, and tapping a name throws the potato to them. Every
/// other screen shows who is holding it and who threw it. Nobody's screen
/// shows the fuse — the host never sends it — so the tension is real on
/// every phone, the host's included.
///
/// The overhaul (2026-10-29) sat everyone round a fire with the potato
/// drawn in the holder's lap — it flies to whoever catches it, and shivers
/// on your own phone while it is yours — gave each shape its own colour on a
/// big tile, made the throws big buttons with faces, and turned the burst
/// into a BANG you can see across the room.
struct HotPotatoView: View {
    let context: OfflineGameContext<HotPotatoRules>
    /// The puzzle I have just answered, so a second tap is not sent before
    /// the host's next view arrives.
    @State private var sentPuzzle: Int?
    /// The pass I have just thrown, for the same reason.
    @State private var sentPass: Int?
    @State private var callout = ""
    @State private var calloutTone: Color = SR.accentDeep
    @State private var calloutToken = 0
    @State private var fumbles = 0

    private var view: HotPotatoRules.PlayerView { context.view }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch view.phase {
                case .passing: passing
                case .burst: burst
                case .over: over
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .overlay {
            NearbyPlayCallout(text: callout, icon: "flame.fill", tone: calloutTone, token: calloutToken, hold: 1.1)
        }
        .onChange(of: view.holder) { old, new in
            if new == context.me && old != context.me {
                SRHaptic.tap()
                pop("Catch!", tone: Color(hex: 0xE4572E))
            }
        }
        .onChange(of: view.burstOn) { _, new in
            guard let new else { return }
            if new == context.me { SRHaptic.bad() } else { SRHaptic.ok() }
        }
        .onChange(of: view.myTask?.lockedUntil) { old, new in
            // A wrong shape locks the puzzle for a moment: shake it.
            guard let new, new > (old ?? 0), new > context.clock.now() else { return }
            SRHaptic.bad()
            withAnimation(.linear(duration: 0.4)) { fumbles += 1 }
        }
        .onChange(of: context.refusal) { _, new in
            // A refused action frees the buttons again.
            if new != nil {
                sentPuzzle = nil
                sentPass = nil
            }
        }
    }

    // MARK: - The potato going round

    @ViewBuilder
    private var passing: some View {
        NearbyPlayBanner(kicker: "Potato \(view.round)", title: passingTitle, strap: passingStrap,
                         mine: view.holder == context.me, tone: holderTone, mark: .symbol("flame.fill"))
            .accessibilityIdentifier("offline-hot-potato-status")
        fire
        if let task = view.myTask {
            if task.solved {
                throwList
            } else {
                puzzle(task)
            }
        } else {
            watching
        }
    }

    private var holderTone: Color {
        guard let holder = view.holder, let index = view.rows.firstIndex(where: { $0.id == holder }) else {
            return SR.accent
        }
        return OfflineSeatColour.of(index)
    }

    private var passingTitle: String {
        guard let holder = view.holder else { return "Hot potato" }
        if holder == context.me { return "You've got it!" }
        return "\(context.name(of: holder)) has it"
    }

    private var passingStrap: String {
        if let task = view.myTask {
            return task.solved ? "Quick — throw it to someone." : "Tap the shape that doesn't match, then throw it."
        }
        if let thrower = view.thrower {
            let from = thrower == context.me ? "you" : context.name(of: thrower)
            return "Thrown by \(from). The fuse is hidden — it could go any second."
        }
        return "The fuse is hidden — it could go any second."
    }

    /// Everyone round the fire, the potato in the holder's lap.
    private var fire: some View {
        NearbyPlayFelt(tone: .tavern, padding: 10) {
            HotPotatoCircle(rows: view.rows, me: context.me, holder: view.phase == .passing ? view.holder : nil,
                            burstOn: view.phase == .passing ? nil : view.burstOn,
                            startingLives: view.startingLives, phase: view.phase)
                .frame(height: 250)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("offline-hot-potato-players")
    }

    /// The four shapes, two by two, sized from the width.
    private func puzzle(_ task: HotPotatoRules.PuzzleView) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Odd one out")
            // Redraws only until the fumble lock lifts, then stops. The small
            // margin makes sure the last frame lands after the lock, so the
            // shapes can never stay greyed out on a frame drawn a hair early.
            let lockedLeft = max(0, task.lockedUntil - context.clock.now()) + 0.05
            TimelineView(NearbyPlayFiniteSchedule(end: Date().addingTimeInterval(lockedLeft), step: 0.1)) { _ in
                let fumbled = context.clock.now() < task.lockedUntil
                let waiting = sentPuzzle == task.number
                HotPotatoPuzzleGrid(shapes: task.shapes, enabled: !fumbled && !waiting) { index in
                    choose(index, in: task)
                }
                .modifier(NearbyPlayShake(travel: 10, animatableData: CGFloat(fumbles)))
                .overlay {
                    if fumbled {
                        Label("Fumbled!", systemImage: "hand.raised.slash.fill")
                            .font(SR.Text.display(26))
                            .foregroundStyle(SR.paper)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(SR.error))
                            .accessibilityLabel("Fumbled. Wait a moment.")
                    }
                }
            }
        }
        .accessibilityIdentifier("offline-hot-potato-puzzle")
    }

    /// Everyone still in, one big button each, two to a row.
    private var throwList: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Throw it to")
            let targets = view.rows.filter { !$0.out && !$0.away && $0.id != context.me }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(targets) { row in
                    throwButton(row)
                }
            }
        }
    }

    private func throwButton(_ row: HotPotatoRules.Row) -> some View {
        let seat = view.rows.firstIndex { $0.id == row.id } ?? 0
        let shape = RoundedRectangle(cornerRadius: NearbyPlayMetrics.radius, style: .continuous)
        let locked = sentPass == view.pass
        return Button {
            throwPotato(to: row.id)
        } label: {
            VStack(spacing: 6) {
                OfflineInitial(name: row.name, size: 44, tone: OfflineSeatColour.of(seat))
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 2) }
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.forward")
                        .font(SR.Text.label(13))
                        .accessibilityHidden(true)
                    Text(row.name)
                        .font(SR.Text.title(16))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            // White on a fixed orange, the same in both modes.
            .foregroundStyle(Color.white)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 96)
            .background {
                ZStack {
                    shape.fill(Color(hex: 0xD9480F))
                    shape.fill(LinearGradient(colors: [Color.white.opacity(0.2), Color.white.opacity(0)],
                                              startPoint: .top, endPoint: .center))
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(SRPressStyle())
        .disabled(locked)
        .opacity(locked ? 0.5 : 1)
        .accessibilityLabel("Throw to \(row.name)")
        .accessibilityIdentifier("offline-hot-potato-throw-\(row.id)")
    }

    /// What everyone but the holder sees: the potato, in someone else's hands.
    private var watching: some View {
        HStack(spacing: 14) {
            Image(systemName: "eye.fill")
                .font(SR.Text.display(26))
                .foregroundStyle(Color(hex: 0xD9480F))
                .accessibilityHidden(true)
            Text(watchingLine)
                .font(SR.Text.body())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("offline-hot-potato-watching")
    }

    private var watchingLine: String {
        let mine = view.rows.first { $0.id == context.me }
        if mine == nil { return "You are watching this game." }
        if mine?.out == true { return "You're out. Watch who it bursts on next." }
        return "Get ready — it could be thrown to you."
    }

    // MARK: - It burst

    @ViewBuilder
    private var burst: some View {
        NearbyPlayBanner(kicker: "Potato \(view.round)", title: burstTitle, strap: burstStrap,
                         mine: view.burstOn == context.me, tone: SR.error, mark: .symbol("burst.fill")) {
            NearbyPlayBannerClock(clock: context.clock, until: view.burstUntil,
                                  total: HotPotatoRules.burstPause, mine: view.burstOn == context.me)
                .accessibilityLabel("Next potato soon")
        }
        .accessibilityIdentifier("offline-hot-potato-burst")
        ZStack {
            fire
            HotPotatoBang()
                .frame(width: 170, height: 170)
                .allowsHitTesting(false)
        }
    }

    private var burstTitle: String {
        guard let id = view.burstOn else { return "Bang!" }
        return id == context.me ? "It burst on you!" : "It burst on \(context.name(of: id))!"
    }

    private var burstStrap: String? {
        guard let id = view.burstOn, let row = view.rows.first(where: { $0.id == id }) else { return nil }
        let who = id == context.me ? "You" : row.name
        if row.out { return id == context.me ? "You're out." : "\(who) is out." }
        let lives = row.lives == 1 ? "1 life" : "\(row.lives) lives"
        return id == context.me ? "You have \(lives) left." : "\(who) has \(lives) left."
    }

    // MARK: - Over

    @ViewBuilder
    private var over: some View {
        NearbyPlayBanner(kicker: "Last one standing", title: overTitle,
                         mine: view.winner == context.me, mark: .symbol("trophy.fill"))
            .accessibilityIdentifier("offline-hot-potato-over")
        fire
    }

    private var overTitle: String {
        guard let winner = view.winner else { return "Nobody survived" }
        return winner == context.me ? "You win" : "\(context.name(of: winner)) wins"
    }

    // MARK: - Acting

    private func choose(_ index: Int, in task: HotPotatoRules.PuzzleView) {
        guard view.phase == .passing, view.holder == context.me, sentPuzzle != task.number else { return }
        sentPuzzle = task.number
        SRHaptic.select()
        context.send(.tap(task: task.number, choice: index))
    }

    private func throwPotato(to id: String) {
        guard view.phase == .passing, view.holder == context.me, sentPass != view.pass else { return }
        sentPass = view.pass
        SRHaptic.ok()
        context.send(.throwTo(pass: view.pass, target: id))
    }

    private func pop(_ text: String, tone: Color) {
        callout = text
        calloutTone = tone
        calloutToken += 1
    }
}

/// Everyone sat round the fire on an oval, the potato in the holder's lap.
/// When it is thrown it flies across to the catcher.
struct HotPotatoCircle: View {
    let rows: [HotPotatoRules.Row]
    let me: String
    let holder: String?
    let burstOn: String?
    let startingLives: Int
    let phase: HotPotatoRules.Phase

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            ZStack {
                // The fire in the middle.
                Image(systemName: "flame.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Color(hex: 0xFFD166), Color(hex: 0xE4572E)],
                                                    startPoint: .top, endPoint: .bottom))
                    .opacity(phase == .passing ? 0.55 : 0.3)
                    .position(centre)
                    .accessibilityHidden(true)
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    seat(row, index: index)
                        .position(spot(index, in: size))
                }
                if let holderIndex = holderIndex {
                    HotPotatoArt(hot: holder == me, size: 56)
                        .position(potatoSpot(holderIndex, in: size))
                        .srAnimation(.spring(response: 0.5, dampingFraction: 0.7), value: holderIndex)
                }
            }
        }
    }

    private var holderIndex: Int? {
        guard let holder else { return nil }
        return rows.firstIndex { $0.id == holder }
    }

    /// Seat `index` of `rows.count` on the oval, the first at the top.
    private func spot(_ index: Int, in size: CGSize) -> CGPoint {
        let count = max(1, rows.count)
        let angle = -Double.pi / 2 + Double(index) * 2 * Double.pi / Double(count)
        let rx = Double(size.width) * 0.36
        let ry = Double(size.height) * 0.32
        return CGPoint(x: Double(size.width) / 2 + cos(angle) * rx, y: Double(size.height) / 2 + sin(angle) * ry)
    }

    /// The potato sits between the holder and the fire.
    private func potatoSpot(_ index: Int, in size: CGSize) -> CGPoint {
        let seat = spot(index, in: size)
        let cx = size.width / 2, cy = size.height / 2
        return CGPoint(x: cx + (seat.x - cx) * 0.48, y: cy + (seat.y - cy) * 0.48)
    }

    private func seat(_ row: HotPotatoRules.Row, index: Int) -> some View {
        let holding = row.id == holder
        let burst = row.id == burstOn
        return VStack(spacing: 3) {
            ZStack {
                OfflineInitial(name: row.name, size: 46, tone: row.out ? Color.gray : OfflineSeatColour.of(index))
                    .overlay {
                        Circle().strokeBorder(holding ? NearbyPlayFeltInk.gold : Color.white.opacity(0.25),
                                              lineWidth: holding ? 3 : 1)
                    }
                if burst {
                    Image(systemName: "burst.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Color(hex: 0xFFD166))
                        .offset(x: 18, y: -18)
                        .accessibilityHidden(true)
                }
            }
            Text(row.id == me ? "You" : row.name)
                .font(SR.Text.label(12))
                .foregroundStyle(holding ? NearbyPlayFeltInk.gold : NearbyPlayFeltInk.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 76)
            lives(row)
        }
        .opacity(row.out || row.away ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(row))
    }

    @ViewBuilder
    private func lives(_ row: HotPotatoRules.Row) -> some View {
        if row.away {
            Text("left")
                .font(SR.Text.mono(12))
                .foregroundStyle(NearbyPlayFeltInk.secondary)
        } else if row.out {
            Text("out")
                .font(SR.Text.mono(12))
                .foregroundStyle(NearbyPlayFeltInk.secondary)
        } else {
            HStack(spacing: 2) {
                ForEach(0..<max(startingLives, 0), id: \.self) { life in
                    Image(systemName: life < row.lives ? "heart.fill" : "heart")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(life < row.lives ? Color(hex: 0xFF6B6B) : NearbyPlayFeltInk.faint)
                }
            }
        }
    }

    private func spoken(_ row: HotPotatoRules.Row) -> String {
        var parts = [row.id == me ? "You" : row.name]
        if row.id == holder { parts.append("holding the potato") }
        if row.id == burstOn { parts.append("it burst on them") }
        if row.away {
            parts.append("left the game")
        } else if row.out {
            parts.append("out")
        } else {
            parts.append(row.lives == 1 ? "1 life left" : "\(row.lives) lives left")
        }
        return parts.joined(separator: ", ")
    }
}

/// The potato: a lumpy brown spud with eyes in its skin and a glow of heat.
/// While it is in YOUR hands it shivers — on a timeline that runs only then.
struct HotPotatoArt: View {
    let hot: Bool
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shiver = hot && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !shiver)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let angle = shiver ? sin(t * 22) * 7 : 0
            spud
                .rotationEffect(.degrees(angle - 12))
        }
        .frame(width: size * 1.3, height: size * 1.3)
        .accessibilityHidden(true)
    }

    private var spud: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xFF8C42).opacity(hot ? 0.7 : 0.4), Color.clear],
                                     center: .center, startRadius: size * 0.2, endRadius: size * 0.65))
                .frame(width: size * 1.3, height: size * 1.3)
            Ellipse()
                .fill(LinearGradient(colors: [Color(hex: 0xD9A066), Color(hex: 0x8A5426)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size * 0.74)
                .overlay {
                    Ellipse().strokeBorder(Color(hex: 0x5E3714), lineWidth: max(1, size * 0.03))
                }
            Canvas { context, canvasSize in
                let w = canvasSize.width, h = canvasSize.height
                let eyes: [CGRect] = [
                    CGRect(x: w * 0.28, y: h * 0.34, width: w * 0.08, height: h * 0.06),
                    CGRect(x: w * 0.58, y: h * 0.28, width: w * 0.07, height: h * 0.05),
                    CGRect(x: w * 0.46, y: h * 0.58, width: w * 0.09, height: h * 0.06),
                    CGRect(x: w * 0.7, y: h * 0.56, width: w * 0.06, height: h * 0.05),
                ]
                for eye in eyes {
                    context.fill(Path(ellipseIn: eye), with: .color(Color(hex: 0x5E3714).opacity(0.7)))
                }
                let shine = CGRect(x: w * 0.22, y: h * 0.2, width: w * 0.22, height: h * 0.1)
                context.fill(Path(ellipseIn: shine), with: .color(Color.white.opacity(0.35)))
            }
            .frame(width: size, height: size * 0.74)
        }
    }
}

/// BANG: a jagged burst with the word on it, springing out once.
struct HotPotatoBang: View {
    @State private var out = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            HotPotatoStarShape(points: 12, inner: 0.62)
                .fill(LinearGradient(colors: [Color(hex: 0xFFD166), Color(hex: 0xE4572E)],
                                     startPoint: .top, endPoint: .bottom))
            HotPotatoStarShape(points: 12, inner: 0.62)
                .stroke(Color(hex: 0x7A1E0E), lineWidth: 3)
            Text("BANG!")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(Color(hex: 0x4A0F05))
                .rotationEffect(.degrees(-8))
        }
        .scaleEffect(out || reduceMotion ? 1 : 0.2)
        .opacity(out || reduceMotion ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.5)) { out = true }
        }
        .accessibilityHidden(true)
    }
}

/// A star with `points` spikes, its valleys at `inner` of the radius.
struct HotPotatoStarShape: Shape {
    var points: Int
    var inner: CGFloat

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let count = max(3, points) * 2
        var path = Path()
        for i in 0..<count {
            let radius = i % 2 == 0 ? outer : outer * inner
            let angle = -Double.pi / 2 + Double(i) * Double.pi / Double(count / 2)
            let point = CGPoint(x: centre.x + CGFloat(cos(angle)) * radius, y: centre.y + CGFloat(sin(angle)) * radius)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// Four shapes in a two-by-two grid that takes its size from the width it is
/// given, so it fits the narrowest phone and never grows past a comfortable
/// thumb's reach on a big one. Each shape wears its own colour.
struct HotPotatoPuzzleGrid: View {
    let shapes: [HotPotatoRules.Glyph]
    let enabled: Bool
    let onTap: (Int) -> Void

    private let gap: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let side = max(0, (min(geo.size.width, 360) - gap) / 2)
            VStack(spacing: gap) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<2, id: \.self) { column in
                            cell(row * 2 + column, side: side)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func cell(_ index: Int, side: CGFloat) -> some View {
        if index < shapes.count {
            let glyph = shapes[index]
            let shape = RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous)
            Button {
                onTap(index)
            } label: {
                Image(systemName: HotPotatoGlyphStyle.symbol(glyph))
                    .font(.system(size: side * 0.46, weight: .bold))
                    .foregroundStyle(enabled ? HotPotatoGlyphStyle.colour(glyph) : SR.inkGhost)
                    .shadow(color: Color.black.opacity(enabled ? 0.18 : 0), radius: 3, x: 0, y: 2)
                    .frame(width: side, height: side)
                    .background(shape.fill(SR.surface))
                    .overlay(shape.strokeBorder(SR.line, lineWidth: 1))
                    .contentShape(shape)
            }
            .buttonStyle(SRPressStyle())
            .disabled(!enabled)
            .accessibilityLabel(HotPotatoGlyphStyle.name(glyph))
            .accessibilityHint("Tap if this is the odd one out")
            .accessibilityIdentifier("offline-hot-potato-shape-\(index)")
        } else {
            Color.clear.frame(width: side, height: side)
        }
    }
}

/// The SF Symbol, the colour and the spoken name for each shape.
enum HotPotatoGlyphStyle {
    static func symbol(_ glyph: HotPotatoRules.Glyph) -> String {
        switch glyph {
        case .circle: return "circle.fill"
        case .square: return "square.fill"
        case .triangle: return "triangle.fill"
        case .diamond: return "diamond.fill"
        case .star: return "star.fill"
        case .heart: return "heart.fill"
        case .hexagon: return "hexagon.fill"
        case .shield: return "shield.fill"
        }
    }

    /// One colour per shape, strong on both grounds.
    static func colour(_ glyph: HotPotatoRules.Glyph) -> Color {
        switch glyph {
        case .circle: return Color(hex: 0x2F80ED)
        case .square: return Color(hex: 0x12A150)
        case .triangle: return Color(hex: 0xF08C00)
        case .diamond: return Color(hex: 0x9B51E0)
        case .star: return Color(hex: 0xE0A800)
        case .heart: return Color(hex: 0xE5383B)
        case .hexagon: return Color(hex: 0x06AED4)
        case .shield: return Color(hex: 0xD6336C)
        }
    }

    static func name(_ glyph: HotPotatoRules.Glyph) -> String {
        switch glyph {
        case .circle: return "Circle"
        case .square: return "Square"
        case .triangle: return "Triangle"
        case .diamond: return "Diamond"
        case .star: return "Star"
        case .heart: return "Heart"
        case .hexagon: return "Hexagon"
        case .shield: return "Shield"
        }
    }
}
