import SwiftUI
import UIKit

/// One jkai Quiz Night room, from the lobby to the final scores.
///
/// The lobby and the 3-2-1 are every game's (`GameLobby`, `GameCountdownView`),
/// with the quiz's own panel in the lobby: what it is about, and whether jkai
/// has finished writing the questions. A question is its prompt, four large
/// answers and a bar running down to the question's end; the reveal marks the
/// right answer with a tick as well as colour, and shows everyone's picks.
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
        if store.ended {
            GameEndedView(id: "quiz-ended", done: { dismiss() })
        } else if let room = store.room {
            switch room.phase {
            case .lobby, .unknown, .armed, .result, .playing, .show, .input:
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
        ProgressView()
            .tint(SR.accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .srPaper()
    }

    /// A new quiz with the same settings and people, then onto its room in
    /// place of this one.
    private func newQuiz() {
        Task {
            guard let next = await store.playAgain() else { return }
            if !router.games.isEmpty { router.games.removeLast() }
            router.games.append(GameRoomRef(id: next.id, game: next.game))
        }
    }
}

// MARK: - Lobby

/// What the quiz is about, and where jkai is with the questions.
struct QuizLobbyPanel: View {
    let room: GameRoom
    @ObservedObject var store: QuizNightStore
    let newQuiz: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch room.prep {
            case .writing:
                HStack(spacing: 12) {
                    ProgressView().tint(SR.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("jkai is writing the questions…")
                            .font(SR.Text.title())
                            .foregroundStyle(SR.ink)
                        Text(settingsLine)
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("quiz-prep-writing")
            case .ready:
                VStack(alignment: .leading, spacing: 4) {
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
            case .failed:
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
        }
        .padding(SR.cardPadding + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
    }

    /// "for kids · 10 questions · 20 s each".
    private var settingsLine: String {
        let seconds = Int(((room.timeMs ?? QuizTime.fallbackMs(room.difficulty)) / 1000).rounded())
        let audience = QuizAudience.from(room.audience).phrase
        if room.prep == .writing {
            let topic = room.topic.map { "“\($0)”" } ?? "A topic of jkai’s choosing"
            return "\(topic) · \(audience) · \(seconds) s a question"
        }
        return "\(audience) · \(room.questionCount) questions · \(seconds) s each"
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

    private var revealed: Bool { room.phase == .reveal }
    private var mine: Int? { store.myChoice }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if revealed {
                    QuizNextLine(room: room, store: store)
                } else {
                    QuizTimeBar(room: room, store: store)
                }
                Text(question.prompt)
                    .font(SR.Text.display(24))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("quiz-prompt")

                VStack(spacing: 10) {
                    ForEach(Array(question.options.enumerated()), id: \.offset) { index, text in
                        QuizOptionButton(
                            index: index,
                            text: text,
                            state: state(of: index),
                            pickers: revealed ? question.pickers(of: index).map { name(of: $0) } : [],
                            enabled: !revealed && store.canAnswer
                        ) {
                            store.answer(index)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("quiz-options")

                if revealed {
                    if let explain = question.explain {
                        Label(explain, systemImage: "lightbulb")
                            .font(SR.Text.body(15))
                            .foregroundStyle(SR.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(SR.cardPadding)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
                            .accessibilityIdentifier("quiz-explain")
                    }
                    QuizPicksList(room: room, question: question)
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
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("QUESTION \(question.index + 1) OF \(room.questionCount)")
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                if let title = room.title {
                    Text(title)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let me = room.me, me.joined {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(me.score.formatted())
                        .font(SR.Text.figure(24))
                        .foregroundStyle(SR.ink)
                        .monospacedDigit()
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
            Text("You are watching this one.")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkMuted)
        } else if mine != nil {
            Label(room.solo ? "Locked in." : "Locked in. Waiting for the others.", systemImage: "lock.fill")
                .font(SR.Text.secondary())
                .foregroundStyle(SR.inkSecondary)
                .accessibilityIdentifier("quiz-locked")
        }
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

/// One of the four answers: a large button with its letter.
struct QuizOptionButton: View {
    let index: Int
    let text: String
    let state: QuizOptionState
    /// Revealed: who chose this one.
    let pickers: [String]
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Text(QuizNight.letter(index))
                    .font(SR.Text.display(18))
                    .foregroundStyle(badgeText)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(badgeFill))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(text)
                        .font(SR.Text.bodyMedium(17))
                        .foregroundStyle(textColour)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let caption {
                        Text(caption)
                            .font(SR.Text.label())
                            .tracking(1)
                            .foregroundStyle(textColour.opacity(0.85))
                    }
                    if !pickers.isEmpty {
                        Text(GameNames.list(pickers))
                            .font(SR.Text.mono())
                            .foregroundStyle(textColour.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(iconColour)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 6, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 6, style: .continuous)
                    .strokeBorder(stroke, lineWidth: strokeWidth)
            )
            .opacity(dim ? 0.5 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(isMine ? [.isSelected] : [])
        .accessibilityIdentifier("quiz-option-\(index)")
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

    private var fill: Color {
        if isRight { return SR.good }
        if state == .locked { return SR.accent }
        return SR.surface
    }

    private var stroke: Color {
        if revealedWrongPick { return SR.error }
        if isRight || state == .locked { return .clear }
        return SR.line
    }

    private var strokeWidth: CGFloat { revealedWrongPick ? 3 : 1 }

    private var textColour: Color { isRight || state == .locked ? SR.paper : SR.ink }

    private var badgeFill: Color { isRight || state == .locked ? SR.paper : SR.ink }

    private var badgeText: Color {
        if isRight { return SR.good }
        if state == .locked { return SR.accent }
        return SR.paper
    }

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
        return SR.paper
    }

    private var caption: String? {
        switch state {
        case .locked: return "YOUR ANSWER"
        case .revealed(let right, let mine):
            if right && mine { return "RIGHT · YOUR ANSWER" }
            if right { return "RIGHT ANSWER" }
            if mine { return "YOUR ANSWER" }
            return nil
        default: return nil
        }
    }

    private var spoken: String {
        var parts = ["\(QuizNight.letter(index)): \(text)"]
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

/// The question's clock: a bar running down to `phaseEndsAt`, and the
/// seconds left.
struct QuizTimeBar: View {
    let room: GameRoom
    @ObservedObject var store: QuizNightStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
            let left = fraction
            HStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(SR.ink.opacity(0.12))
                        Capsule()
                            .fill(left.map { $0 <= 0.25 ? SR.error : SR.accent } ?? SR.inkGhost)
                            .frame(width: geo.size.width * CGFloat(left ?? 1))
                    }
                }
                .frame(height: 10)
                Text(secondsText)
                    .font(SR.Text.figure(20))
                    .monospacedDigit()
                    .foregroundStyle(left.map { $0 <= 0.25 ? SR.error : SR.ink } ?? SR.inkMuted)
                    .frame(minWidth: 44, alignment: .trailing)
            }
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

/// Who has answered — never what — as a row of initials.
struct QuizAnsweredStrip: View {
    let room: GameRoom
    let question: QuizQuestion

    var body: some View {
        if room.playing.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                SRSectionLabel(text: "Answered", trailing: "\(answered.count) of \(room.playing.count)")
                HStack(spacing: 10) {
                    ForEach(room.playing) { player in
                        QuizAvatar(name: player.name, done: answered.contains(player.id), you: player.id == room.meId)
                    }
                    Spacer(minLength: 0)
                }
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

/// A player's initial in a circle: filled with a tick once they have answered.
struct QuizAvatar: View {
    let name: String
    let done: Bool
    let you: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                Text(String(name.prefix(1)).uppercased())
                    .font(SR.Text.title(17))
                    .foregroundStyle(done ? SR.paper : SR.inkSecondary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(done ? SR.accentInk : Color.clear))
                    .overlay(Circle().strokeBorder(done ? Color.clear : SR.line, lineWidth: 1.5))
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(SR.good)
                        .background(Circle().fill(SR.paper))
                        .offset(x: 3, y: 3)
                }
            }
            Text(you ? "You" : name)
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
        }
        .frame(minWidth: 52)
    }
}

/// The reveal's countdown to what comes next.
struct QuizNextLine: View {
    let room: GameRoom
    @ObservedObject var store: QuizNightStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            Text(line)
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .monospacedDigit()
                .accessibilityIdentifier("quiz-next")
        }
    }

    private var line: String {
        let last = (room.question?.index ?? 0) + 1 >= room.questionCount
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
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: room.solo ? "Your score" : "Scores")
            VStack(spacing: 0) {
                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, player in
                    if index > 0 { Divider().overlay(SR.divider) }
                    row(player)
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

    private func row(_ player: GamePlayer) -> some View {
        let pick = question.pick(of: player.id)
        return HStack(spacing: 12) {
            Image(systemName: pick == nil ? "minus.circle" : (pick?.right == true ? "checkmark.circle.fill" : "xmark.circle"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(pick?.right == true ? SR.good : SR.inkGhost)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.name + (player.id == room.meId ? " (you)" : ""))
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                Text(detail(pick))
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
            Spacer(minLength: 8)
            Text(player.score.formatted())
                .font(SR.Text.figure(20))
                .foregroundStyle(SR.ink)
                .monospacedDigit()
        }
        .frame(minHeight: SR.tapTarget)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(player, pick))
        .accessibilityIdentifier("quiz-pick-\(player.id)")
    }

    private func detail(_ pick: QuizPick?) -> String {
        guard let pick else { return "No answer · 0" }
        return "\(QuizNight.letter(pick.choice)) · \(QuizNight.points(pick.points))"
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Quiz Night · final", title: title, strap: strap)

                VStack(alignment: .leading, spacing: SR.cardGap) {
                    SRSectionLabel(text: room.solo ? "Your quiz" : "Standings", trailing: room.title)
                    VStack(spacing: 0) {
                        ForEach(Array(standings.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { Divider().overlay(SR.divider) }
                            HStack(alignment: .center, spacing: 12) {
                                Text("\(index + 1)")
                                    .font(SR.Text.display(26))
                                    .foregroundStyle(room.winnerIds.contains(row.id) ? SR.accent : SR.inkGhost)
                                    .frame(width: 32, alignment: .leading)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(row.name + (row.id == room.meId ? " (you)" : ""))
                                            .font(SR.Text.title())
                                            .foregroundStyle(SR.ink)
                                        if room.winnerIds.contains(row.id), !room.solo {
                                            Image(systemName: "crown.fill")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(SR.accent)
                                                .accessibilityLabel("Winner")
                                        }
                                    }
                                    Text(detail(row))
                                        .font(SR.Text.mono())
                                        .foregroundStyle(SR.inkMuted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 8)
                                Text(row.score.formatted())
                                    .font(SR.Text.figure(24))
                                    .foregroundStyle(SR.ink)
                                    .monospacedDigit()
                            }
                            .padding(.vertical, 10)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.horizontal, SR.cardPadding)
                    .padding(.vertical, 6)
                    .srGlassCard(.paper)
                    .accessibilityIdentifier("quiz-standings")
                }

                VStack(spacing: 10) {
                    if room.isHost {
                        Button {
                            SRHaptic.tap()
                            again()
                        } label: {
                            SRButtonLabel(title: store.creating ? "Starting…" : "Play again", icon: "arrow.counterclockwise", fill: true)
                        }
                        .srButton(.prominent)
                        .controlSize(.large)
                        .disabled(store.creating)
                        .accessibilityIdentifier("quiz-again")
                        Text("A new quiz, same settings. Everyone who played gets an invite.")
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button { done() } label: { SRButtonLabel(title: "Done", fill: true) }
                        .srButton(.regular)
                        .controlSize(.large)
                        .accessibilityIdentifier("quiz-done")
                }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("quiz-finished")
        .onAppear { if room.winnerIds.contains(room.meId) { SRHaptic.ok() } }
    }

    private var standings: [GameStanding] { room.standings ?? [] }

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

    private func detail(_ row: GameStanding) -> String {
        let right = "\(row.correct) of \(room.questionCount) right"
        guard let ms = row.avgMs else { return right }
        let seconds = Double(ms) / 1000
        return "\(right) · \(seconds.formatted(.number.precision(.fractionLength(1)))) s average"
    }
}
