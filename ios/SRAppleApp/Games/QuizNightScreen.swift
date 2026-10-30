import SwiftUI
import UIKit

/// One jkai Quiz Night room, from the lobby to the final scores.
///
/// The lobby and the 3-2-1 are every game's (`GameLobby`, `GameCountdownView`),
/// with the quiz's own panel in the lobby: the stage, drawn, what it is about,
/// how to play, and whether jkai has finished writing the questions. A
/// question is its prompt on a card, four big coloured answers — each with its
/// own shape as well as its colour, so a colour-blind player or a five-year-old
/// can say "the triangle" — and a bar running down to the question's end that
/// ticks in the last seconds. The reveal says, first and large, how MY answer
/// went and what it scored, then keeps the right answer lit (with a tick)
/// while the rest fade, and shows everyone's picks. The finish is my points,
/// how many I got right, my best on this phone, the table and the answers to
/// go over.
struct QuizNightScreen: View {
    let roomId: String
    @StateObject private var store: QuizNightStore
    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(roomId: String) {
        self.roomId = roomId
        _store = StateObject(wrappedValue: QuizNightStore(roomId: roomId))
    }

    var body: some View {
        content
            .navigationTitle("Quiz Night")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar(immersive ? .hidden : .visible, for: .navigationBar)
            .statusBarHidden(immersive)
            .onAppear { store.open() }
            .onDisappear { store.close() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.open() } else if phase == .background { store.close() }
            }
            .overlay(alignment: .bottom) {
                if let message = store.message, !immersive { SRBanner(text: message) }
            }
    }

    private var immersive: Bool {
        guard !store.ended, let phase = store.room?.phase else { return false }
        return phase == .countdown
    }

    @ViewBuilder
    private var content: some View {
        if let finished = store.lastFinished, store.ended || store.room?.phase == .closed {
            QuizFinished(room: finished, store: store, again: newQuiz, done: { dismiss() })
        } else if store.ended {
            GameEndedView(id: "quiz-ended", done: { dismiss() })
        } else if let room = store.room {
            switch room.phase {
            case .lobby, .unknown, .armed, .result, .playing, .show, .input, .review:
                GameLobby(
                    room: room, store: store, prefix: "quiz", done: { dismiss() },
                    panel: AnyView(QuizLobbyPanel(room: room, store: store, newQuiz: newQuiz)),
                    startBlocked: room.prep != .ready,
                    hidesStart: room.prep == .failed
                )
            case .countdown:
                GameCountdownView(room: room, store: store,
                                  note: "\(room.questionCount) questions. Right scores; right and fast scores more.",
                                  id: "quiz-countdown")
            case .question, .reveal:
                if let question = room.question {
                    QuizQuestionView(room: room, question: question, store: store)
                } else {
                    waiting
                }
            case .finished:
                QuizFinished(room: room, store: store, again: newQuiz, done: { dismiss() })
            case .closed:
                GameEndedView(id: "quiz-ended", done: { dismiss() })
            }
        } else {
            waiting
        }
    }

    private var waiting: some View {
        VStack(spacing: 18) {
            QuizNightStageArt()
                .frame(width: 150, height: 96)
            HStack(spacing: 10) {
                ProgressView().tint(SR.accent)
                Text("Opening the quiz…")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .srPaper()
        .accessibilityElement(children: .combine)
    }

    /// A new quiz with the same settings and people, then onto its room in
    /// place of this one.
    private func newQuiz() {
        Task {
            guard let next = await store.playAgain() else { return }
            router.pop(on: .games)
            router.push(GameRoomRef(id: next.id, game: next.game), on: .games)
        }
    }
}

// MARK: - The answers' colours and shapes

/// Each answer's colour and shape, by position. Fixed colours, the same in
/// both modes, every one holding white type at 5:1 or better; green is left
/// out on purpose, because green means "right" at the reveal.
enum QuizNightOptionInk {
    static let hexes: [UInt32] = [0xC8283E, 0x1E5FC8, 0x9A5800, 0x6D36C4, 0x0E7C86, 0xB4235A]

    static func fill(_ index: Int) -> Color {
        Color(hex: hexes[((index % hexes.count) + hexes.count) % hexes.count])
    }

    /// The type on a fill: white, in both modes.
    static let onFill = Color.white

    static func glyph(_ index: Int) -> QuizNightGlyphKind {
        switch index {
        case 0: return .triangle
        case 1: return .diamond
        case 2: return .circle
        case 3: return .square
        case 4: return .ring
        default: return .bar
        }
    }

    static func shapeName(_ index: Int) -> String {
        switch glyph(index) {
        case .triangle: return "triangle"
        case .diamond: return "diamond"
        case .circle: return "circle"
        case .square: return "square"
        case .ring: return "ring"
        case .bar: return "bar"
        }
    }
}

enum QuizNightGlyphKind {
    case triangle, diamond, circle, square, ring, bar
}

struct QuizNightTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct QuizNightDiamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

/// An answer's shape, drawn.
struct QuizNightGlyph: View {
    let kind: QuizNightGlyphKind
    var tint: Color = .white

    var body: some View {
        Group {
            switch kind {
            case .triangle: QuizNightTriangle().fill(tint).padding(.bottom, 1)
            case .diamond: QuizNightDiamond().fill(tint)
            case .circle: Circle().fill(tint).padding(1)
            case .square: RoundedRectangle(cornerRadius: 2, style: .continuous).fill(tint).padding(2)
            case .ring: Circle().strokeBorder(tint, lineWidth: 3.5).padding(1)
            case .bar: Capsule().fill(tint).frame(height: 7)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The quiz, drawn: a speech bubble with a question mark over the four
/// coloured shapes, as a little stage.
struct QuizNightStageArt: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let chip = min(w / 5.2, h * 0.36)
            ZStack(alignment: .top) {
                bubble(side: h * 0.62)
                HStack(spacing: chip * 0.22) {
                    ForEach(0..<4, id: \.self) { index in
                        QuizNightGlyph(kind: QuizNightOptionInk.glyph(index))
                            .frame(width: chip * 0.5, height: chip * 0.5)
                            .frame(width: chip, height: chip)
                            .background(RoundedRectangle(cornerRadius: chip * 0.28, style: .continuous)
                                .fill(QuizNightOptionInk.fill(index)))
                            .rotationEffect(.degrees(PartyRoomMaths.tilt(index, spread: 4)))
                    }
                }
                .frame(width: w, height: h, alignment: .bottom)
            }
        }
        .accessibilityHidden(true)
    }

    private func bubble(side: CGFloat) -> some View {
        Text("?")
            .font(SR.Text.hero(side * 0.62))
            .foregroundStyle(SR.paper)
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .frame(width: side * 1.25, height: side * 0.86)
            .background(RoundedRectangle(cornerRadius: side * 0.3, style: .continuous).fill(SR.accentDeep))
            .overlay(alignment: .bottomLeading) {
                QuizNightTriangle()
                    .fill(SR.accentDeep)
                    .frame(width: side * 0.22, height: side * 0.2)
                    .rotationEffect(.degrees(180))
                    .offset(x: side * 0.2, y: side * 0.16)
            }
            .shadow(color: SR.accentDeep.opacity(0.3), radius: 6, y: 3)
    }
}

// MARK: - Lobby

/// What the quiz is about, how to play, and where jkai is with the questions.
struct QuizLobbyPanel: View {
    let room: GameRoom
    @ObservedObject var store: QuizNightStore
    let newQuiz: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                QuizNightStageArt()
                    .frame(width: 112, height: 76)
                Spacer(minLength: 0)
                prepChip
            }
            switch room.prep {
            case .writing: writing
            case .ready: ready
            case .failed: failed
            }
            if room.prep != .failed { rules }
        }
        .padding(SR.cardPadding + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
    }

    @ViewBuilder
    private var prepChip: some View {
        switch room.prep {
        case .writing:
            SRGlassChip(text: "Writing", icon: "pencil", tone: SR.accent)
        case .ready:
            SRGlassChip(text: "Ready", icon: "checkmark", tone: SR.good)
        case .failed:
            SRGlassChip(text: "Not ready", icon: "exclamationmark.triangle", tone: SR.error)
        }
    }

    private var writing: some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressView().tint(SR.accent).padding(.top, 3)
            VStack(alignment: .leading, spacing: 4) {
                Text("jkai is writing the questions…")
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(settingsLine)
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("quiz-prep-writing")
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(room.title ?? room.topic ?? "A jkai quiz")
                .font(SR.Text.display(24))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("quiz-title")
            Text(settingsLine)
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("quiz-prep-ready")
    }

    @ViewBuilder
    private var failed: some View {
        Label(room.prepError ?? "jkai could not write this quiz.", systemImage: "exclamationmark.triangle")
            .font(SR.Text.bodyMedium(15))
            .foregroundStyle(SR.error)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("quiz-prep-failed")
        if room.isHost {
            Button {
                SRHaptic.tap()
                newQuiz()
            } label: {
                SRButtonLabel(title: store.creating ? "Starting…" : "Start a new quiz", icon: "arrow.counterclockwise", fill: true)
                    .frame(minHeight: 44)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .disabled(store.creating)
            .accessibilityIdentifier("quiz-new")
        } else {
            Text("Waiting for \(room.host?.name ?? "the host") to start a new quiz.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
        }
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 10) {
            QuizNightRuleLine(icon: "hand.tap.fill", text: "Tap one of the four answers. It locks in at once, so be sure.")
            QuizNightRuleLine(icon: "bolt.fill", text: "Right scores 500, and up to 500 more for being quick.")
            QuizNightRuleLine(icon: "person.3.fill", text: room.solo ? "After each question, see the answer and why." : "After each question, see the answer and everyone's picks.")
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("quiz-how-to")
    }

    /// "for kids · 10 questions · 20 s each", or "GCSE Biology · AQA ·
    /// Grades 4–5 · 10 questions · 30 s each".
    private var settingsLine: String {
        let seconds = Int(((room.timeMs ?? QuizTime.fallbackMs(room.difficulty)) / 1000).rounded())
        if let gcse = room.quizGcse {
            let tier = gcse.tier.map { " · \($0)" } ?? ""
            if room.prep == .writing {
                let topic = room.topic.map { " · “\($0)”" } ?? ""
                return "\(gcse.line)\(tier)\(topic) · \(seconds) s a question. Writing, then checking every answer."
            }
            return "\(gcse.line)\(tier) · \(room.questionCount) questions · \(seconds) s each"
        }
        let audience = QuizAudience.from(room.audience).phrase
        if room.prep == .writing {
            let topic = room.topic.map { "“\($0)”" } ?? "A topic of jkai’s choosing"
            return "\(topic) · \(audience) · \(seconds) s a question"
        }
        return "\(audience) · \(room.questionCount) questions · \(seconds) s each"
    }
}

/// One rule in the lobby: an icon in a soft disc and a sentence.
struct QuizNightRuleLine: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(SR.Text.title(14))
                .foregroundStyle(SR.accent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(SR.accent.opacity(0.12)))
                .accessibilityHidden(true)
            Text(text)
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
    }
}

enum QuizTime {
    /// The spec's seconds a question, for a room that did not say.
    static func fallbackMs(_ difficulty: String) -> Double {
        switch GameDifficulty(rawValue: difficulty) {
        case .medium?: return 15_000
        case .hard?: return 10_000
        default: return 20_000
        }
    }
}

// MARK: - A question

struct QuizQuestionView: View {
    let room: GameRoom
    let question: QuizQuestion
    @ObservedObject var store: QuizNightStore
    @Environment(\.dynamicTypeSize) private var typeSize

    private var revealed: Bool { room.phase == .reveal }
    private var mine: Int? { store.myChoice }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if revealed {
                    QuizRevealBanner(room: room, question: question)
                    QuizNextLine(room: room, store: store)
                } else {
                    QuizTimeBar(room: room, store: store)
                }
                prompt
                options
                if revealed {
                    revealExtras
                } else {
                    QuizAnsweredStrip(room: room, question: question)
                    statusLine
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier(revealed ? "quiz-reveal" : "quiz-question")
        .srAnimation(.snappy, value: revealed)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            QuizNightQuestionDial(number: question.index + 1, of: room.questionCount)
            VStack(alignment: .leading, spacing: 4) {
                Text("QUESTION \(question.index + 1) OF \(room.questionCount)")
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let line = room.quizGcse?.line ?? room.title {
                    Text(line)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let me = room.me, me.joined {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(me.score.formatted())
                        .font(SR.Text.figure(26))
                        .foregroundStyle(SR.ink)
                        .monospacedDigit()
                        .srNumeric(Double(me.score))
                    Text("POINTS")
                        .font(SR.Text.label())
                        .foregroundStyle(SR.inkMuted)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Your score, \(me.score) points")
                .accessibilityIdentifier("quiz-my-score")
            }
        }
    }

    private var prompt: some View {
        Text(question.prompt)
            .font(SR.Text.display(24))
            .foregroundStyle(SR.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SR.cardPadding + 2)
            .srGlassCard(.paper)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("quiz-prompt")
    }

    /// Four short answers sit two by two, like the buttons on a quiz-show
    /// desk; long ones, more than four, or large text get a row each.
    private var grid: Bool {
        question.options.count == 4
            && question.options.allSatisfy { $0.count <= 18 }
            && !typeSize.isAccessibilitySize
    }

    @ViewBuilder
    private var options: some View {
        if grid {
            // A Grid, not a LazyVGrid: its rows hand every cell the row's
            // height, so the two tiles side by side stay the same size when
            // one answer (or its list of pickers) runs to another line.
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    optionButton(0, tile: true)
                    optionButton(1, tile: true)
                }
                GridRow {
                    optionButton(2, tile: true)
                    optionButton(3, tile: true)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("quiz-options")
        } else {
            VStack(spacing: 10) {
                ForEach(Array(question.options.indices), id: \.self) { index in
                    optionButton(index, tile: false)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("quiz-options")
        }
    }

    /// One answer. `grid` holds only for exactly four, so 0...3 are there.
    private func optionButton(_ index: Int, tile: Bool) -> some View {
        let text = question.options.indices.contains(index) ? question.options[index] : ""
        return QuizOptionButton(
            index: index,
            text: text,
            state: state(of: index),
            pickers: revealed ? question.pickers(of: index).map { name(of: $0) } : [],
            enabled: !revealed && store.canAnswer,
            tile: tile
        ) {
            store.answer(index)
        }
    }

    @ViewBuilder
    private var revealExtras: some View {
        if let topic = question.topic {
            Label(topic, systemImage: "book.closed")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .accessibilityLabel("Spec topic: \(topic)")
                .accessibilityIdentifier("quiz-topic")
        }
        if let explain = question.explain {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lightbulb.fill")
                    .font(SR.Text.title(16))
                    .foregroundStyle(Color(hex: 0xE9A800))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color(hex: 0xFFD54A).opacity(0.22)))
                    .accessibilityHidden(true)
                Text(explain)
                    .font(SR.Text.body(15))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(SR.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("quiz-explain")
        }
        QuizPicksList(room: room, question: question)
    }

    private func state(of index: Int) -> QuizOptionState {
        if revealed {
            let right = question.answerIndex == index
            return .revealed(right: right, mine: mine == index)
        }
        if let mine { return mine == index ? .locked : .dimmed }
        return .open
    }

    private func name(of id: String) -> String {
        id == room.meId ? "You" : room.name(of: id)
    }

    @ViewBuilder
    private var statusLine: some View {
        if room.me?.joined != true {
            Label("You are watching this one.", systemImage: "eye")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
        } else if let mine {
            HStack(spacing: 12) {
                QuizNightGlyph(kind: QuizNightOptionInk.glyph(mine))
                    .frame(width: 16, height: 16)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(QuizNightOptionInk.fill(mine)))
                VStack(alignment: .leading, spacing: 2) {
                    Label("Locked in: \(QuizNight.letter(mine))", systemImage: "lock.fill")
                        .font(SR.Text.title(16))
                        .foregroundStyle(SR.ink)
                    Text(room.solo ? "The answer comes when the clock runs out." : "Waiting for the others.")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(room.solo ? "Locked in." : "Locked in. Waiting for the others.")
            .accessibilityIdentifier("quiz-locked")
        }
    }
}

/// Which question this is, as a ring filling question by question.
struct QuizNightQuestionDial: View {
    let number: Int
    let of: Int
    @ScaledMetric(relativeTo: .headline) private var side: CGFloat = 48

    var body: some View {
        let share = PartyRoomMaths.share(number, of: of)
        ZStack {
            Circle().stroke(SR.line, lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(share))
                .stroke(SR.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(number)")
                .font(SR.Text.figure(18))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(width: side, height: side)
        .srAnimation(.smooth(duration: 0.5), value: share)
        .accessibilityHidden(true)
    }
}

/// How one answer looks.
enum QuizOptionState: Equatable {
    /// Can be tapped.
    case open
    /// I picked it; waiting for the reveal.
    case locked
    /// I picked another.
    case dimmed
    case revealed(right: Bool, mine: Bool)
}

/// One of the answers: a big coloured button with its shape and letter.
struct QuizOptionButton: View {
    let index: Int
    let text: String
    let state: QuizOptionState
    /// Revealed: who chose this one.
    let pickers: [String]
    let enabled: Bool
    /// Two by two: a taller tile, shape over words.
    var tile: Bool = false
    let action: () -> Void

    private var radius: CGFloat { SR.Glass.innerRadius + 6 }

    var body: some View {
        Button {
            action()
        } label: {
            Group {
                if tile { tileLabel } else { rowLabel }
            }
            .padding(.horizontal, tile ? 14 : SR.cardPadding)
            .padding(.vertical, tile ? 14 : 12)
            .frame(maxWidth: .infinity, minHeight: tile ? 112 : 68, maxHeight: tile ? CGFloat.infinity : nil,
                   alignment: tile ? .topLeading : .leading)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: strokeWidth)
            )
            .opacity(dim ? 0.55 : 1)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .buttonStyle(SRPressStyle())
        .disabled(!enabled)
        .srAnimation(.spring(response: 0.35, dampingFraction: 0.75), value: state)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(isMine ? [.isSelected] : [])
        .accessibilityIdentifier("quiz-option-\(index)")
    }

    private var rowLabel: some View {
        HStack(alignment: .center, spacing: 12) {
            badge
            VStack(alignment: .leading, spacing: 3) {
                kicker
                Text(text)
                    .font(SR.Text.bodyMedium(18))
                    .foregroundStyle(textColour)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                pickerLine
            }
            Spacer(minLength: 6)
            statusIcon
        }
    }

    private var tileLabel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                badge
                Spacer(minLength: 4)
                statusIcon
            }
            Spacer(minLength: 0)
            kicker
            Text(text)
                .font(SR.Text.bodyMedium(17))
                .foregroundStyle(textColour)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
            pickerLine
        }
    }

    private var badge: some View {
        QuizNightGlyph(kind: QuizNightOptionInk.glyph(index), tint: coloured ? QuizNightOptionInk.onFill : QuizNightOptionInk.fill(index))
            .frame(width: 18, height: 18)
            .frame(width: 40, height: 40)
            .background(Circle().fill(coloured ? Color.white.opacity(0.22) : QuizNightOptionInk.fill(index).opacity(0.14)))
    }

    private var kicker: some View {
        Text(caption.map { "\(QuizNight.letter(index)) · \($0)" } ?? QuizNight.letter(index))
            .font(SR.Text.label())
            .tracking(1)
            .foregroundStyle(textColour.opacity(0.88))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    @ViewBuilder
    private var pickerLine: some View {
        if !pickers.isEmpty {
            Label(GameNames.list(pickers), systemImage: "person.fill")
                .font(SR.Text.mono())
                .foregroundStyle(textColour.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if let icon {
            Image(systemName: icon)
                .font(SR.Text.title(22))
                .foregroundStyle(iconColour)
                .transition(.scale.combined(with: .opacity))
                .accessibilityHidden(true)
        }
    }

    /// Wearing its own colour: open, my locked pick, and the right answer at
    /// the reveal. Everything else goes plain.
    private var coloured: Bool {
        switch state {
        case .open, .locked, .dimmed: return true
        case .revealed(let right, _): return right
        }
    }

    private var isMine: Bool {
        switch state {
        case .locked: return true
        case .revealed(_, let mine): return mine
        default: return false
        }
    }

    private var isRight: Bool {
        if case .revealed(let right, _) = state { return right }
        return false
    }

    private var revealedWrongPick: Bool {
        if case .revealed(let right, let mine) = state { return mine && !right }
        return false
    }

    private var dim: Bool {
        switch state {
        case .dimmed: return true
        case .revealed(let right, let mine): return !right && !mine
        default: return false
        }
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if coloured {
            shape
                .fill(LinearGradient(colors: [QuizNightOptionInk.fill(index).opacity(0.86), QuizNightOptionInk.fill(index)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: QuizNightOptionInk.fill(index).opacity(state == .dimmed ? 0 : 0.28), radius: 6, y: 3)
        } else {
            shape.fill(SR.surface)
        }
    }

    private var stroke: Color {
        if revealedWrongPick { return SR.error }
        if isRight { return SR.good }
        if state == .locked { return Color.white.opacity(0.9) }
        if coloured { return Color.white.opacity(0.18) }
        return SR.line
    }

    private var strokeWidth: CGFloat {
        if revealedWrongPick || isRight { return 4 }
        if state == .locked { return 3 }
        return 1
    }

    private var textColour: Color { coloured ? QuizNightOptionInk.onFill : SR.ink }

    /// The shape cue that does not depend on colour: a tick on the right
    /// answer, a cross on my wrong pick, a lock on a pick waiting.
    private var icon: String? {
        if isRight { return "checkmark.circle.fill" }
        if revealedWrongPick { return "xmark.circle.fill" }
        if state == .locked { return "lock.fill" }
        return nil
    }

    private var iconColour: Color {
        if revealedWrongPick { return SR.error }
        return QuizNightOptionInk.onFill
    }

    private var caption: String? {
        switch state {
        case .locked: return "YOUR ANSWER"
        case .revealed(let right, let mine):
            if right && mine { return "RIGHT · YOURS" }
            if right { return "RIGHT ANSWER" }
            if mine { return "YOUR ANSWER" }
            return nil
        default: return nil
        }
    }

    private var spoken: String {
        var parts = ["\(QuizNight.letter(index)), \(QuizNightOptionInk.shapeName(index)): \(text)"]
        switch state {
        case .locked: parts.append("your answer, locked in")
        case .revealed(let right, let mine):
            if right { parts.append("the right answer") }
            if mine { parts.append(right ? "you got it" : "your answer, wrong") }
            if !pickers.isEmpty { parts.append("chosen by \(GameNames.list(pickers))") }
        default: break
        }
        return parts.joined(separator: ", ")
    }
}

/// The reveal's headline, for me: right and what it scored, wrong and what
/// it was, or no answer at all.
struct QuizRevealBanner: View {
    let room: GameRoom
    let question: QuizQuestion

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(SR.Text.hero(30))
                .foregroundStyle(tone)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(SR.Text.display(22))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let sub {
                    Text(sub)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            if let pick, pick.right {
                Text(QuizNight.points(pick.points))
                    .font(SR.Text.figure(24))
                    .foregroundStyle(SR.good)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(SR.good.opacity(0.14)))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous).fill(tone.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous).strokeBorder(tone.opacity(0.45), lineWidth: 1.5))
        .scaleEffect(shown || reduceMotion ? 1 : 0.9)
        .opacity(shown || reduceMotion ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.65)) { shown = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("quiz-verdict")
    }

    private var joined: Bool { room.me?.joined == true }
    private var pick: QuizPick? { question.pick(of: room.meId) }

    private var answerLine: String? {
        guard let answer = question.answerIndex, question.options.indices.contains(answer) else { return nil }
        return "It was \(QuizNight.letter(answer)): \(question.options[answer])"
    }

    /// The quickest right answer in the room was mine.
    private var fastest: Bool {
        guard let pick, pick.right, room.playing.count > 1 else { return false }
        let others = question.picks.filter { $0.playerId != room.meId && $0.right }
        return !others.isEmpty && others.allSatisfy { $0.points < pick.points }
    }

    private var headline: String {
        guard joined else { return answerLine ?? "The answer" }
        guard let pick else { return "No answer this time" }
        return pick.right ? "Right!" : "Not this time"
    }

    private var sub: String? {
        guard joined else { return nil }
        if let pick, pick.right { return fastest ? "The quickest right answer." : "Nicely done." }
        return answerLine
    }

    private var icon: String {
        guard joined else { return "checkmark.seal.fill" }
        guard let pick else { return "hourglass" }
        return pick.right ? "checkmark.seal.fill" : "xmark.octagon.fill"
    }

    private var tone: Color {
        guard joined else { return SR.accent }
        guard let pick else { return SR.warn }
        return pick.right ? SR.good : SR.error
    }
}

/// The question's clock: a bar running down to `phaseEndsAt`, the seconds
/// left in a pill, and a tick for each of the last three.
struct QuizTimeBar: View {
    let room: GameRoom
    @ObservedObject var store: QuizNightStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let left = fraction
            let urgent = left.map { $0 <= 0.25 } ?? false
            HStack(spacing: 12) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(SR.ink.opacity(0.1))
                        Capsule()
                            .fill(left == nil ? SR.inkGhost : (urgent ? SR.error : SR.accent))
                            .frame(width: max(0, geo.size.width * CGFloat(left ?? 1)))
                    }
                }
                .frame(height: 14)
                Text(secondsText)
                    .font(SR.Text.figure(20))
                    .monospacedDigit()
                    .foregroundStyle(urgent ? SR.paper : SR.ink)
                    .frame(minWidth: 56, minHeight: 36)
                    .background(Capsule().fill(urgent ? SR.error : SR.ink.opacity(0.08)))
            }
            .background { QuizNightClockHaptics(seconds: secondsLeft) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(secondsLeft.map { "\($0) seconds left" } ?? "Time left unknown")
            .accessibilityIdentifier("quiz-timer")
        }
    }

    private var timeMs: Double { room.timeMs ?? QuizTime.fallbackMs(room.difficulty) }

    private var fraction: Double? {
        guard let end = room.phaseEndsAt, let now = store.serverNow() else { return nil }
        return QuizNight.fractionLeft(endsAt: end, timeMs: timeMs, atServer: now)
    }

    private var secondsLeft: Int? {
        guard let end = room.phaseEndsAt, let now = store.serverNow() else { return nil }
        return GameCountdown.secondsLeft(until: end, atServer: now)
    }

    private var secondsText: String { secondsLeft.map { "\($0)s" } ?? "–" }
}

/// Nothing to see: the question clock's ticks, fired as the seconds change.
struct QuizNightClockHaptics: View {
    let seconds: Int?

    var body: some View {
        Color.clear
            .onChange(of: seconds) { old, new in
                if PartyRoomMaths.tick(from: old, to: new, warnAt: 3) { SRHaptic.select() }
            }
    }
}

/// Who has answered — never what — as a row of initials.
struct QuizAnsweredStrip: View {
    let room: GameRoom
    let question: QuizQuestion

    var body: some View {
        if room.playing.count > 1 {
            let tones = SR.PersonHue.assign(room.players.map(\.id))
            VStack(alignment: .leading, spacing: 10) {
                SRSectionLabel(text: "Answered", trailing: "\(answered.count) of \(room.playing.count)")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(room.playing) { player in
                            QuizAvatar(name: player.name, done: answered.contains(player.id), you: player.id == room.meId,
                                       tone: tones[player.id] ?? SR.accentInk)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            .accessibilityIdentifier("quiz-answered")
        }
    }

    private var answered: Set<String> { Set(question.answeredIds) }

    private var spoken: String {
        let names = room.playing.filter { answered.contains($0.id) }.map { $0.id == room.meId ? "You" : $0.name }
        return names.isEmpty ? "Nobody has answered yet" : "Answered: \(GameNames.list(names))"
    }
}

/// A player's initial in a circle: filled in their colour, with a tick that
/// pops in, once they have answered.
struct QuizAvatar: View {
    let name: String
    let done: Bool
    let you: Bool
    var tone: Color = SR.accentInk

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                Text(String(name.prefix(1)).uppercased())
                    .font(SR.Text.title(18))
                    .foregroundStyle(done ? SR.paper : SR.inkSecondary)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(done ? tone : Color.clear))
                    .overlay(Circle().strokeBorder(done ? Color.clear : SR.line, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(SR.Text.title(16))
                        .foregroundStyle(SR.good)
                        .background(Circle().fill(SR.paper))
                        .offset(x: 3, y: 3)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            Text(you ? "You" : name)
                .font(SR.Text.mono())
                .foregroundStyle(done ? SR.ink : SR.inkMuted)
                .lineLimit(1)
        }
        .frame(minWidth: 56)
        .srAnimation(.spring(response: 0.35, dampingFraction: 0.6), value: done)
    }
}

/// The reveal's countdown to what comes next.
struct QuizNextLine: View {
    let room: GameRoom
    @ObservedObject var store: QuizNightStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            Label(line, systemImage: last ? "flag.checkered" : "arrow.right.circle.fill")
                .font(SR.Text.title(15))
                .foregroundStyle(SR.inkSecondary)
                .monospacedDigit()
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .srGlass(.paper, in: Capsule())
                .accessibilityIdentifier("quiz-next")
        }
    }

    private var last: Bool { (room.question?.index ?? 0) + 1 >= room.questionCount }

    private var line: String {
        let what = last ? "Final scores" : "Next question"
        guard let end = room.phaseEndsAt, let now = store.serverNow() else { return "\(what) in a moment" }
        let left = GameCountdown.secondsLeft(until: end, atServer: now)
        return left > 0 ? "\(what) in \(left)" : "\(what)…"
    }
}

/// The reveal's table: each player's pick, the points it scored, and their
/// running total, highest first.
struct QuizPicksList: View {
    let room: GameRoom
    let question: QuizQuestion

    var body: some View {
        let tones = SR.PersonHue.assign(room.players.map(\.id))
        let rows = ranked
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: room.solo ? "Your score" : "Scores")
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, player in
                    if index > 0 { Divider().overlay(SR.divider) }
                    row(player, place: place(of: player, in: rows), tone: tones[player.id] ?? SR.accentInk)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quiz-picks")
    }

    private var ranked: [GamePlayer] {
        room.playing.sorted { $0.score > $1.score }
    }

    private func place(of player: GamePlayer, in rows: [GamePlayer]) -> Int {
        PartyRoomMaths.place(of: player.id, ids: rows.map(\.id), scores: rows.map(\.score)) ?? 1
    }

    private func row(_ player: GamePlayer, place: Int, tone: Color) -> some View {
        let pick = question.pick(of: player.id)
        let mine = player.id == room.meId
        return HStack(spacing: 12) {
            Text("\(place)")
                .font(SR.Text.figure(18))
                .foregroundStyle(place == 1 ? SR.accent : SR.inkMuted)
                .frame(minWidth: 22)
            GameInitial(name: player.name, tone: tone, side: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(player.name + (mine ? " (you)" : ""))
                        .font(SR.Text.title())
                        .foregroundStyle(mine ? SR.accentInk : SR.ink)
                        .lineLimit(1)
                    if place == 1, !room.solo, player.score > 0 {
                        Image(systemName: "crown.fill")
                            .font(SR.Text.label(13))
                            .foregroundStyle(Color(hex: 0xE9A800))
                            .accessibilityHidden(true)
                    }
                }
                pickLine(pick)
            }
            Spacer(minLength: 8)
            Text(player.score.formatted())
                .font(SR.Text.figure(20))
                .foregroundStyle(SR.ink)
                .monospacedDigit()
        }
        .frame(minHeight: 56)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(player, pick))
        .accessibilityIdentifier("quiz-pick-\(player.id)")
    }

    private func pickLine(_ pick: QuizPick?) -> some View {
        HStack(spacing: 6) {
            if let pick {
                QuizNightGlyph(kind: QuizNightOptionInk.glyph(pick.choice), tint: QuizNightOptionInk.fill(pick.choice))
                    .frame(width: 11, height: 11)
                Text("\(QuizNight.letter(pick.choice)) · \(QuizNight.points(pick.points))")
                    .font(SR.Text.mono())
                    .foregroundStyle(pick.right ? SR.good : SR.inkMuted)
                Image(systemName: pick.right ? "checkmark" : "xmark")
                    .font(SR.Text.label())
                    .foregroundStyle(pick.right ? SR.good : SR.inkMuted)
                    .accessibilityHidden(true)
            } else {
                Text("No answer · 0")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
        }
    }

    private func spoken(_ player: GamePlayer, _ pick: QuizPick?) -> String {
        let answer: String
        if let pick {
            answer = pick.right ? "right, \(pick.points) points" : "answered \(QuizNight.letter(pick.choice)), wrong"
        } else {
            answer = "no answer"
        }
        return "\(player.name), \(answer), \(player.score) in total"
    }
}

// MARK: - Finished

struct QuizFinished: View {
    let room: GameRoom
    @ObservedObject var store: QuizNightStore
    let again: () -> Void
    let done: () -> Void

    /// What this quiz did to my best on this phone; set once on appearing.
    @State private var best: PartyRoomBestNote?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Quiz Night · final", title: title, strap: strap)

                if let row = mine {
                    QuizNightResultHero(room: room, row: row, place: place, best: best)
                }

                GameStandingsCard(
                    room: room,
                    label: room.solo ? "Your quiz" : "Standings",
                    id: "quiz-standings",
                    detail: detail,
                    figure: { (text: $0.score.formatted(), spoken: "\($0.score) points") }
                )

                buttons

                if let review = room.quizReview, !review.isEmpty {
                    QuizReviewSection(items: review, gcse: room.quizGcse != nil)
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("quiz-finished")
        .onAppear { recordBest() }
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            if room.isHost {
                Button {
                    SRHaptic.tap()
                    again()
                } label: {
                    Group {
                        if store.creating {
                            HStack(spacing: 8) {
                                ProgressView().tint(SR.cream)
                                SRButtonLabel(title: "Starting…")
                            }
                        } else {
                            SRButtonLabel(title: "Play again", icon: "arrow.counterclockwise", fill: true)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .disabled(store.creating)
                .accessibilityLabel("Play again")
                .accessibilityIdentifier("quiz-again")
                Text("A new quiz, same settings. Everyone who played gets an invite.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                SRHaptic.tap()
                done()
            } label: {
                SRButtonLabel(title: "Done", fill: true)
                    .frame(minHeight: 44)
            }
            .srButton(.regular)
            .controlSize(.large)
            .accessibilityIdentifier("quiz-done")
        }
    }

    private var standings: [GameStanding] { room.standings ?? [] }

    private var mine: GameStanding? {
        guard room.me?.joined == true else { return nil }
        return standings.first { $0.id == room.meId }
    }

    private var place: Int? {
        guard !room.solo, !standings.isEmpty else { return nil }
        return PartyRoomMaths.place(of: room.meId, ids: standings.map(\.id), scores: standings.map(\.score))
    }

    private var title: String {
        if room.solo {
            let mine = standings.first { $0.id == room.meId }
            return "You scored \((mine?.score ?? room.me?.score ?? 0).formatted())"
        }
        let names = room.winnerIds.map { $0 == room.meId ? "You" : room.name(of: $0) }
        switch names.count {
        case 0: return "Nobody scored"
        case 1: return names[0] == "You" ? "You win" : "\(names[0]) wins"
        default: return "\(GameNames.list(names)) tie"
        }
    }

    private var strap: String? {
        room.isHost ? nil : "Only \(room.host?.name ?? "the host") can start another quiz from here."
    }

    private func recordBest() {
        guard best == nil, let row = mine else { return }
        let kind = "\(room.difficulty)|\(room.questionCount)"
        let note = PartyRoomBestStore.quizNight.record(row.score, kind: kind, token: room.id)
        best = note
        let won = room.solo ? room.records[room.meId] != nil : room.winnerIds.contains(room.meId)
        if note.isNew, !won { SRHaptic.ok() }
    }

    private func detail(_ row: GameStanding) -> String {
        let right = "\(row.correct) of \(room.questionCount) right"
        guard let ms = row.avgMs else { return right }
        let seconds = Double(ms) / 1000
        return "\(right) · \(seconds.formatted(.number.precision(.fractionLength(1)))) s average"
    }
}

/// My quiz in one card: points, how many right as a ring, my place, and my
/// best on this phone for a quiz like this one.
struct QuizNightResultHero: View {
    let room: GameRoom
    let row: GameStanding
    let place: Int?
    let best: PartyRoomBestNote?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ring
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.score.formatted())
                        .font(SR.Text.hero(40))
                        .foregroundStyle(SR.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("points")
                        .font(SR.Text.title())
                        .foregroundStyle(SR.inkSecondary)
                }
                if let place {
                    Text("\(PartyRoomMaths.ordinal(place)) of \(room.standings?.count ?? room.playing.count)")
                        .font(SR.Text.title(15))
                        .foregroundStyle(place == 1 ? SR.accent : SR.inkSecondary)
                }
                bestLine
            }
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .scaleEffect(shown || reduceMotion ? 1 : 0.94)
        .opacity(shown || reduceMotion ? 1 : 0)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.7)) { shown = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("quiz-result")
    }

    private var ring: some View {
        let share = PartyRoomMaths.share(row.correct, of: room.questionCount)
        return ZStack {
            Circle().stroke(SR.line, lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(shown || reduceMotion ? share : 0))
                .stroke(SR.good, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .smooth(duration: 0.9).delay(0.15), value: shown)
            VStack(spacing: 0) {
                Text("\(row.correct)/\(room.questionCount)")
                    .font(SR.Text.figure(18))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("RIGHT")
                    .font(SR.Text.label())
                    .foregroundStyle(SR.inkMuted)
            }
            .padding(8)
        }
        .frame(width: 84, height: 84)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.correct) of \(room.questionCount) right")
    }

    @ViewBuilder
    private var bestLine: some View {
        if let best {
            if best.isNew {
                Label("New personal best!", systemImage: "star.fill")
                    .font(SR.Text.title(15))
                    .foregroundStyle(SR.good)
                    .accessibilityIdentifier("quiz-new-best")
            } else if let value = best.best {
                Text("Your best on a quiz like this: \(value.formatted())")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - The review

/// Every question again with its answer — what I missed first, and for a GCSE
/// quiz the spec topics to revise next.
struct QuizReviewSection: View {
    let items: [QuizReviewItem]
    let gcse: Bool

    @State private var open: Set<Int> = []

    private var missed: Int { items.filter { !$0.gotIt }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Go over the answers",
                           trailing: missed == 0 ? "All right" : "\(missed) to look at")

            let topics = QuizReview.reviseNext(items)
            if gcse, !topics.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("REVISE NEXT")
                        .font(SR.Text.label())
                        .tracking(SR.kickerTracking)
                        .foregroundStyle(SR.accent)
                    ForEach(topics.prefix(3), id: \.self) { topic in
                        Label(topic, systemImage: "book.closed")
                            .font(SR.Text.bodyMedium(15))
                            .foregroundStyle(SR.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(SR.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .srGlassCard(.paper)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("quiz-revise-next")
            }

            VStack(spacing: 0) {
                ForEach(Array(QuizReview.ordered(items).enumerated()), id: \.element.id) { position, item in
                    if position > 0 { Divider().overlay(SR.divider) }
                    row(item)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 6)
            .srGlassCard(.paper)
            .accessibilityIdentifier("quiz-review")
        }
    }

    private func row(_ item: QuizReviewItem) -> some View {
        let expanded = open.contains(item.index)
        return Button {
            SRHaptic.select()
            withAnimation(.snappy) {
                if expanded { open.remove(item.index) } else { open.insert(item.index) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.gotIt ? "checkmark" : "xmark")
                        .font(SR.Text.label(13))
                        .foregroundStyle(SR.paper)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(item.gotIt ? SR.good : SR.error))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Q\(item.index + 1). \(item.prompt)")
                            .font(SR.Text.bodyMedium(15))
                            .foregroundStyle(SR.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(summary(item))
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(SR.Text.label(13))
                        .foregroundStyle(SR.inkMuted)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .padding(.top, 4)
                        .accessibilityHidden(true)
                }
                if expanded { detail(item) }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(expanded ? "Hides the answer." : "Shows the answer and why.")
        .accessibilityIdentifier("quiz-review-\(item.index)")
    }

    private func detail(_ item: QuizReviewItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                QuizNightGlyph(kind: QuizNightOptionInk.glyph(item.answerIndex))
                    .frame(width: 11, height: 11)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(QuizNightOptionInk.fill(item.answerIndex)))
                Text("Answer: \(QuizNight.letter(item.answerIndex)). \(item.answer)")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.ink)
            }
            if let mine = item.myChoice, mine != item.answerIndex, item.options.indices.contains(mine) {
                Text("You said \(QuizNight.letter(mine)). \(item.options[mine])")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
            }
            if let explain = item.explain {
                Label(explain, systemImage: "lightbulb")
                    .font(SR.Text.body(15))
                    .foregroundStyle(SR.inkSecondary)
            }
            if let topic = item.topic {
                Label(topic, systemImage: "book.closed")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.leading, 38)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// "You: right · 2 of 3 got it", or "You: no answer · nobody got it".
    private func summary(_ item: QuizReviewItem) -> String {
        let me: String
        if item.myChoice == nil { me = "No answer" } else { me = item.gotIt ? "Right" : "Wrong" }
        guard item.playerCount > 1 else { return me }
        let table = item.rightCount == 0 ? "nobody got it" : "\(item.rightCount) of \(item.playerCount) got it"
        return "\(me) · \(table)"
    }
}
