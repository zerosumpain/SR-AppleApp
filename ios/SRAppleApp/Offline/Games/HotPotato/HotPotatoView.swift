import SwiftUI

/// Hot Potato on one phone: who has it, your puzzle when it is you, and the
/// moment it bursts.
///
/// The holder's screen shows four shapes; tapping the odd one out unlocks a
/// list of everyone still in, and tapping a name throws the potato to them.
/// Every other screen shows who is holding it and who threw it. Nobody's
/// screen shows the fuse — the host never sends it — so the tension is real
/// on every phone, the host's included.
struct HotPotatoView: View {
    let context: OfflineGameContext<HotPotatoRules>
    /// The puzzle I have just answered, so a second tap is not sent before
    /// the host's next view arrives.
    @State private var sentPuzzle: Int?
    /// The pass I have just thrown, for the same reason.
    @State private var sentPass: Int?

    private var view: HotPotatoRules.PlayerView { context.view }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                switch view.phase {
                case .passing: passing
                case .burst: burst
                case .over: over
                }
                HotPotatoTable(rows: view.rows, me: context.me, startingLives: view.startingLives,
                               burstOn: view.phase == .passing ? nil : view.burstOn)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .onChange(of: view.holder) { old, new in
            if new == context.me && old != context.me { SRHaptic.tap() }
        }
        .onChange(of: view.burstOn) { _, new in
            guard let new else { return }
            if new == context.me { SRHaptic.bad() } else { SRHaptic.ok() }
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
        SRPageHeader(kicker: "Potato \(view.round)", title: passingTitle, strap: passingStrap)
            .accessibilityIdentifier("offline-hot-potato-status")
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

    /// The four shapes, two by two, sized from the width.
    private func puzzle(_ task: HotPotatoRules.PuzzleView) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Odd one out")
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                let fumbled = context.clock.now() < task.lockedUntil
                let waiting = sentPuzzle == task.number
                HotPotatoPuzzleGrid(shapes: task.shapes, enabled: !fumbled && !waiting) { index in
                    choose(index, in: task)
                }
                .overlay {
                    if fumbled {
                        Text("Fumbled!")
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

    /// Everyone still in, one button each.
    private var throwList: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Throw it to")
            let targets = view.rows.filter { !$0.out && !$0.away && $0.id != context.me }
            ForEach(targets) { row in
                Button {
                    throwPotato(to: row.id)
                } label: {
                    SRButtonLabel(title: row.name, icon: "arrow.up.forward", fill: true)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .disabled(sentPass == view.pass)
                .accessibilityLabel("Throw to \(row.name)")
                .accessibilityIdentifier("offline-hot-potato-throw-\(row.id)")
            }
        }
    }

    /// What everyone but the holder sees: the potato, in someone else's hands.
    private var watching: some View {
        HStack(spacing: 14) {
            Image(systemName: "flame.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(SR.accent)
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
        SRPageHeader(kicker: "Potato \(view.round)", title: burstTitle, strap: burstStrap)
            .accessibilityIdentifier("offline-hot-potato-burst")
        HStack(spacing: 8) {
            Text("Next potato in")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
            OfflineCountdown(clock: context.clock, until: view.burstUntil, font: SR.Text.mono(), tone: SR.inkMuted)
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
        SRPageHeader(kicker: "Last one standing", title: overTitle)
            .accessibilityIdentifier("offline-hot-potato-over")
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
}

/// Four shapes in a two-by-two grid that takes its size from the width it is
/// given, so it fits the narrowest phone and never grows past a comfortable
/// thumb's reach on a big one.
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
            Button {
                onTap(index)
            } label: {
                Image(systemName: HotPotatoGlyphStyle.symbol(glyph))
                    .font(.system(size: side * 0.42, weight: .bold))
                    .foregroundStyle(enabled ? SR.ink : SR.inkGhost)
                    .frame(width: side, height: side)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .srGlassCard(.paper, radius: SR.Glass.innerRadius, interactive: true)
            .disabled(!enabled)
            .accessibilityLabel(HotPotatoGlyphStyle.name(glyph))
            .accessibilityHint("Tap if this is the odd one out")
            .accessibilityIdentifier("offline-hot-potato-shape-\(index)")
        } else {
            Color.clear.frame(width: side, height: side)
        }
    }
}

/// The SF Symbol and the spoken name for each shape.
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

/// Everyone, one row each: who holds the potato and how many lives are left.
/// Names truncate so five players fit a 375pt phone.
struct HotPotatoTable: View {
    let rows: [HotPotatoRules.Row]
    let me: String
    let startingLives: Int
    /// Who it just burst on, marked while the burst is on screen.
    let burstOn: String?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().overlay(SR.divider) }
                HStack(spacing: 10) {
                    OfflineInitial(name: row.name, size: 30, tone: OfflineSeatColour.of(index))
                        .opacity(row.out ? 0.4 : 1)
                    Text(row.id == me ? "You" : row.name)
                        .font(SR.Text.title())
                        .foregroundStyle(row.out ? SR.inkMuted : SR.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if row.holding {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(SR.accent)
                            .accessibilityHidden(true)
                    }
                    if row.id == burstOn {
                        Image(systemName: "burst.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(SR.error)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 8)
                    trailing(row)
                }
                .frame(minHeight: SR.tapTarget)
                .padding(.vertical, 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken(row))
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 6)
        .srGlassCard(.paper)
        .accessibilityIdentifier("offline-hot-potato-players")
    }

    @ViewBuilder
    private func trailing(_ row: HotPotatoRules.Row) -> some View {
        if row.away {
            Text("left")
                .font(SR.Text.mono(14))
                .foregroundStyle(SR.inkMuted)
                .fixedSize()
        } else if row.out {
            Text("out")
                .font(SR.Text.mono(14))
                .foregroundStyle(SR.inkMuted)
                .fixedSize()
        } else {
            HStack(spacing: 3) {
                ForEach(0..<max(startingLives, 0), id: \.self) { life in
                    Image(systemName: life < row.lives ? "heart.fill" : "heart")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(life < row.lives ? SR.error : SR.inkGhost)
                }
            }
            .fixedSize()
        }
    }

    private func spoken(_ row: HotPotatoRules.Row) -> String {
        var parts = [row.id == me ? "You" : row.name]
        if row.holding { parts.append("holding the potato") }
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
