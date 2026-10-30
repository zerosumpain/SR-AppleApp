import SwiftUI

/// A golfer's name as typed on the setup screen, with an id so a row can be removed safely.
struct MiniGolfName: Identifiable, Equatable {
    let id = UUID()
    var text = ""
}

/// Mini Golf: pick the holes and who is playing, then play.
struct MiniGolfScreen: View {
    @State private var loop: MiniGolfLoop = .front
    @State private var names = [MiniGolfName()]
    @State private var game: MiniGolfGame? = nil
    @State private var book = MiniGolfStore().load()

    var body: some View {
        Group {
            if let game {
                MiniGolfPlayView(game: game, again: { playAgain(game) }, leave: { leave(game) })
                    .id(ObjectIdentifier(game))
            } else {
                setup
            }
        }
        .navigationTitle(GameKind.miniGolf.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private func playAgain(_ old: MiniGolfGame) {
        old.stop()
        game = MiniGolfGame(loop: old.round.loop, players: old.round.players)
    }

    private func leave(_ old: MiniGolfGame) {
        old.stop()
        book = MiniGolfStore().load()
        game = nil
    }

    private var players: [MiniGolfPlayer] {
        names.enumerated().map { index, name in
            let trimmed = name.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = names.count == 1 ? "You" : "Player \(index + 1)"
            return MiniGolfPlayer(id: index, name: trimmed.isEmpty ? fallback : String(trimmed.prefix(16)), seat: index)
        }
    }

    // MARK: - Setup

    private var setup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Physics", title: GameKind.miniGolf.title, strap: GameKind.miniGolf.line)
                loops
                MiniGolfCourseStrip(loop: loop, book: book)
                golfers
                howTo
                bests
                Button {
                    SRHaptic.tap()
                    game = MiniGolfGame(loop: loop, players: players)
                } label: {
                    SRButtonLabel(title: "Tee off", icon: "figure.golf", fill: true)
                        .frame(minHeight: 44)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .accessibilityIdentifier("mini-golf-start")
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .srGround(.warm)
        .accessibilityIdentifier("mini-golf-setup")
    }

    private var loops: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Holes")
            ForEach(MiniGolfLoop.allCases) { option in
                MiniGolfChoiceRow(title: option.title, line: loopLine(option), icon: loopIcon(option),
                                  selected: loop == option) { loop = option }
                    .accessibilityIdentifier("mini-golf-loop-\(option.rawValue)")
            }
        }
    }

    private func loopIcon(_ option: MiniGolfLoop) -> String {
        switch option {
        case .front: return "1.circle.fill"
        case .back: return "10.circle.fill"
        case .full: return "flag.2.crossed.fill"
        }
    }

    private func loopLine(_ option: MiniGolfLoop) -> String {
        let par = "Par \(option.par)."
        guard let best = book.best(loop: option) else { return "\(option.line) \(par)" }
        let diff = MiniGolfScoreWord.toPar(best - option.par)
        return "\(option.line) \(par) Best round: \(best) (\(diff))."
    }

    private var golfers: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Who's playing", trailing: "\(names.count) of 4")
            ForEach($names) { $name in
                let index = names.firstIndex { $0.id == name.id } ?? 0
                MiniGolfNameRow(index: index, text: $name.text, removable: names.count > 1) {
                    let gone = name.id
                    names.removeAll { $0.id == gone }
                }
            }
            if names.count < 4 {
                Button {
                    SRHaptic.select()
                    names.append(MiniGolfName())
                } label: {
                    SRButtonLabel(title: "Add a player", icon: "plus")
                        .frame(minHeight: 44)
                }
                .srButton(.regular)
                .accessibilityIdentifier("mini-golf-add-player")
            }
            Text(names.count == 1
                 ? "Playing on your own. Add players to pass the phone round: everyone plays each hole in turn."
                 : "Pass the phone: everyone plays each hole in turn, and the fewest strokes wins.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var howTo: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "How to play")
            VStack(alignment: .leading, spacing: 8) {
                MiniGolfRuleLine(text: "Put a finger anywhere and drag back, away from where you want the ball to go. The further you pull, the harder the putt.")
                MiniGolfRuleLine(text: "Let go to putt. Slide back to the start to cancel.")
                MiniGolfRuleLine(text: "A fast ball lips out of the cup, so the last putt wants to be gentle.")
                MiniGolfRuleLine(text: "Water costs a stroke and puts you back where you played from. Sand stops a ball dead.")
                MiniGolfRuleLine(text: "Par + 4 is the most a hole takes: after that the ball is picked up.")
            }
            .padding(SR.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .srGlassCard(.paper)
        }
    }

    @ViewBuilder
    private var bests: some View {
        if book.rounds > 0 || !book.bestHole.isEmpty {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                SRSectionLabel(text: "On this phone")
                HStack(spacing: 12) {
                    MiniGolfStat(label: "ROUNDS", value: "\(book.rounds)")
                    MiniGolfStat(label: "HOLES IN ONE", value: "\(book.holesInOne)")
                    MiniGolfStat(label: "HOLES PLAYED", value: "\(book.bestHole.count) of 18")
                }
            }
        }
    }
}

/// One choice on the setup screen, ticked when chosen.
struct MiniGolfChoiceRow: View {
    let title: String
    let line: String
    let icon: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            SRHaptic.select()
            action()
        } label: {
            SRCard(accented: selected, interactive: true) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(selected ? SR.accent : SR.inkMuted)
                        .frame(width: 30)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(SR.Text.title())
                            .foregroundStyle(SR.ink)
                        Text(line)
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected ? SR.accent : SR.inkGhost)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? AccessibilityTraits([.isButton, .isSelected]) : .isButton)
    }
}

/// A player's name field, in their colour.
struct MiniGolfNameRow: View {
    let index: Int
    @Binding var text: String
    let removable: Bool
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            MiniGolfBallBadge(seat: index)
                .accessibilityHidden(true)
            TextField(index == 0 ? "Your name" : "Player \(index + 1)", text: $text)
                .font(SR.Text.body())
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .accessibilityIdentifier("mini-golf-player-\(index)")
            if removable {
                Button {
                    SRHaptic.select()
                    remove()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(SR.inkMuted)
                        .frame(width: 56, height: 56)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(text.isEmpty ? "player \(index + 1)" : text)")
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .frame(minHeight: 56)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius)
    }
}

/// A golf ball with the player's colour band: who is who on every card.
struct MiniGolfBallBadge: View {
    let seat: Int
    var size: CGFloat = 18

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.white, Color(red: 0.84, green: 0.85, blue: 0.88)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.8))
            Circle()
                .stroke(OfflineSeatColour.of(seat), lineWidth: size * 0.14)
                .padding(size * 0.2)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.25), radius: 1.5, x: 0.5, y: 1)
    }
}

/// A dot and a line of the rules.
struct MiniGolfRuleLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(SR.accent)
                .frame(width: 5, height: 5)
                .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 1 }
                .accessibilityHidden(true)
            Text(text)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A small figure with its label, for the bests.
struct MiniGolfStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(SR.Text.label(11))
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(SR.Text.figure(22))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius)
        .accessibilityElement(children: .combine)
    }
}

/// The holes of the chosen loop as little pictures, each with its par and the best on it.
struct MiniGolfCourseStrip: View {
    let loop: MiniGolfLoop
    let book: MiniGolfBook

    var body: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "The course", trailing: "Par \(loop.par)")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(loop.holeIndices, id: \.self) { index in
                        MiniGolfHoleThumb(hole: MiniGolfCourse.holes[index], best: book.best(hole: index + 1))
                            .equatable()
                    }
                }
                .padding(.vertical, 2)
            }
            .accessibilityIdentifier("mini-golf-course-strip")
        }
    }
}

/// One hole, small: drawn the way it plays, with its number, par and best.
/// Equal when the hole and the best are, so typing a name does not redraw the course.
struct MiniGolfHoleThumb: View, Equatable {
    let hole: MiniGolfHole
    let best: Int?

    static func == (a: MiniGolfHoleThumb, b: MiniGolfHoleThumb) -> Bool {
        a.hole.number == b.hole.number && a.best == b.best
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            picture
                .frame(width: 96, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous))
            Text("\(hole.number). \(hole.name)")
                .font(SR.Text.label(12))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(bestLine)
                .font(SR.Text.mono(12))
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 96)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hole \(hole.number), \(hole.name), par \(hole.par). \(best.map { "Best \($0)." } ?? "Not played yet.")")
    }

    private var bestLine: String {
        guard let best else { return "Par \(hole.par)" }
        return "Par \(hole.par) · best \(best)"
    }

    private var picture: some View {
        let rect = CGRect(x: 0, y: 0, width: 96, height: 132)
        let camera = MiniGolfCamera.framing(hole.bounds, width: 96, height: 132, focus: hole.tee, overview: true)
        let snap = MiniGolfSnapshot(hole: hole, ball: hole.tee, camera: camera, playRect: rect)
        let paths = MiniGolfHolePaths(hole)
        let colour = OfflineSeatColour.of(0)
        return Canvas { context, size in
            MiniGolfPainter(snap: snap, paths: paths, dark: false, ballColour: colour).draw(in: context, size: size)
        }
    }
}
