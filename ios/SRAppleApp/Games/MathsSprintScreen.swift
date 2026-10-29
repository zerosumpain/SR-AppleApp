import SwiftUI
import UIKit

/// One Quick Maths Sprint room, from lobby to the recaps.
///
/// The lobby and the 3-2-1 are every game's (`GameLobby`, `GameCountdownView`);
/// the lobby carries a how-to card with this phone's best. Playing is my
/// current problem, big, exactly as the server wrote it; a keypad pinned under
/// it; my score (with a "+1" that pops on every right answer), a draining
/// clock, the streak as pips towards the next bonus; and everyone else as a
/// place and a score. Finished is my sprint in figures, the personal best, a
/// podium, the standings and each player's last few problems.
struct MathsSprintScreen: View {
    let roomId: String
    @StateObject private var store: MathsSprintStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(roomId: String) {
        self.roomId = roomId
        _store = StateObject(wrappedValue: MathsSprintStore(roomId: roomId))
    }

    var body: some View {
        content
            .navigationTitle("Quick Maths Sprint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .toolbar(immersive ? .hidden : .visible, for: .navigationBar)
            .statusBarHidden(immersive)
            .onAppear { store.open() }
            .onDisappear { store.close() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.open() } else if phase == .background { store.close() }
            }
            // At the top: the keypad owns the bottom edge while playing.
            .overlay(alignment: .top) {
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
            GameEndedView(id: "sprint-ended", done: { dismiss() })
        } else if let room = store.room {
            switch room.phase {
            case .lobby, .unknown, .armed, .result, .question, .reveal, .show, .input, .review:
                GameLobby(room: room, store: store, prefix: "sprint", done: { dismiss() },
                          panel: AnyView(SprintHowTo(room: room)))
            case .countdown:
                GameCountdownView(room: room, store: store,
                                  note: "Sixty seconds. Same problems for everyone. A wrong answer keeps you on the same one.",
                                  id: "sprint-countdown")
            case .playing:
                SprintPlaying(room: room, store: store)
            case .finished:
                SprintFinished(room: room, store: store, done: { dismiss() })
            case .closed:
                GameEndedView(id: "sprint-ended", done: { dismiss() })
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

/// How to play, in the lobby, with this phone's best sprint at this level.
struct SprintHowTo: View {
    let room: GameRoom
    @State private var best: Int?
    @State private var played = 0

    var body: some View {
        QuickRoomHowTo(
            pitch: "Sixty seconds of sums",
            rules: [
                QuickRoomRule(icon: "keyboard.fill", text: "Type the answer on the keypad and press GO. The minus key makes it negative."),
                QuickRoomRule(icon: "arrow.right.circle.fill", text: "Right moves you on to the next problem. Wrong keeps you on the same one."),
                QuickRoomRule(icon: "flame.fill", text: "Every \(max(1, room.streakBonus)) right in a row earns a bonus point."),
                QuickRoomRule(icon: "person.3.fill", text: "Everyone gets the same problems. Most points when the clock runs out wins.")
            ],
            best: best.map { "Best \($0) pts" },
            played: played,
            id: "sprint-howto"
        )
        .onAppear {
            let book = QuickRoomBestStore.sprint
            best = book.best(difficulty: room.difficulty)
            played = book.gamesPlayed()
        }
    }
}

// MARK: - Playing

struct SprintPlaying: View {
    let room: GameRoom
    @ObservedObject var store: MathsSprintStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Points just won, shown as "+1" / "+2" beside the score for a moment.
    @State private var gain: Int?
    @State private var gainTick = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                SprintTimeBar(room: room, store: store)
                if !room.others.isEmpty {
                    SprintOthersStrip(room: room)
                }
                problemCard
                SprintStreak(room: room, bonuses: store.bonuses)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .srGround(.warm)
        .safeAreaInset(edge: .bottom) { keypad }
        .accessibilityIdentifier("sprint-playing")
        .onChange(of: store.shakes) { _, _ in
            if let wrong = store.wrongValue {
                UIAccessibility.post(notification: .announcement, argument: "Not \(wrong). Try again.")
            }
        }
        .onChange(of: me?.score ?? 0) { old, new in
            guard new > old else { return }
            gain = new - old
            gainTick += 1
        }
        .task(id: gainTick) {
            guard gainTick > 0 else { return }
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            gain = nil
        }
    }

    private var me: SprintMe? { room.sprint }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("QUICK MATHS · \(GameDifficulty.label(for: room.difficulty).uppercased())")
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                scoreLine
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                WordleTimer(room: room, store: store, id: "sprint-timer")
                if let place {
                    Text(place)
                        .font(SR.Text.label())
                        .tracking(1)
                        .foregroundStyle(SR.inkSecondary)
                        .accessibilityLabel("You are \(place)")
                }
            }
        }
    }

    private var scoreLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(me?.score ?? 0)")
                .font(SR.Text.hero(40))
                .foregroundStyle(SR.ink)
                .monospacedDigit()
                .srNumeric(Double(me?.score ?? 0))
            Text("POINTS")
                .font(SR.Text.label())
                .foregroundStyle(SR.inkMuted)
            if let gain {
                Text("+\(gain)")
                    .font(SR.Text.title(17))
                    .foregroundStyle(SR.paper)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(gain > 1 ? SR.accent : SR.good))
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .srAnimation(.spring(response: 0.3, dampingFraction: 0.6), value: gain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your score, \(me?.score ?? 0) points")
        .accessibilityIdentifier("sprint-my-score")
    }

    /// "2nd of 3", when anyone else is playing.
    private var place: String? {
        guard !room.others.isEmpty, room.me?.joined == true else { return nil }
        var scores: [(id: String, score: Int)] = room.others.map { (id: $0.id, score: $0.score) }
        scores.append((id: room.meId, score: me?.score ?? room.me?.score ?? 0))
        guard let place = QuickRoomPlace.place(of: room.meId, scores: scores) else { return nil }
        return "\(QuickRoomPlace.ordinal(place).uppercased()) OF \(scores.count)"
    }

    // MARK: The problem

    private var problemCard: some View {
        VStack(spacing: 10) {
            if let problem = me?.problem {
                Text("PROBLEM \(problem.index + 1)")
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.inkMuted)
                Text(problem.text)
                    .font(SR.Text.hero(56))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .accessibilityLabel(SprintSpeech.problem(problem.text))
                    .accessibilityIdentifier("sprint-problem")
                    .modifier(WordleShake(animatableData: CGFloat(reduceMotion ? 0 : store.shakes)))
                    .animation(.linear(duration: 0.4), value: store.shakes)
                    .id(problem.index)
                    .transition(problemTransition)
                answerSlot
                feedbackLine
            } else if room.me?.joined != true {
                Text("You are not playing in this one.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            } else {
                Image(systemName: allAnswered ? "checkmark.seal.fill" : "timer")
                    .font(SR.Text.hero(40))
                    .foregroundStyle(allAnswered ? SR.good : SR.accent)
                    .accessibilityHidden(true)
                Text(allAnswered ? "You answered them all." : "Time’s up.")
                    .font(SR.Text.display(24))
                    .foregroundStyle(SR.ink)
            }
        }
        .srAnimation(.snappy(duration: 0.28), value: me?.problem?.index)
        .padding(SR.cardPadding + 4)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
        .srGlassCard(.paper)
        .overlay(
            RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                .strokeBorder(flashTone, lineWidth: 3)
        )
        .srAnimation(.easeOut(duration: 0.2), value: flashKey)
    }

    private var allAnswered: Bool {
        guard let me else { return false }
        return me.correct >= room.problemCount
    }

    private var problemTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                           removal: .move(edge: .leading).combined(with: .opacity))
    }

    /// The answer being typed, in a slot that lights when there is something in it.
    private var answerSlot: some View {
        HStack(spacing: 10) {
            Text("=")
                .font(SR.Text.figure(32))
                .foregroundStyle(SR.inkGhost)
                .accessibilityHidden(true)
            Text(store.input.isEmpty ? "?" : store.input.display)
                .font(SR.Text.figure(40))
                .foregroundStyle(store.input.isEmpty ? SR.inkGhost : SR.accent)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(minWidth: 80, minHeight: 52)
                .accessibilityLabel(store.input.isEmpty ? "Your answer, empty" : "Your answer, \(store.input.display)")
                .accessibilityIdentifier("sprint-answer")
        }
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                .fill(store.input.isEmpty ? SR.line.opacity(0.25) : SR.accent.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
                .strokeBorder(store.input.isEmpty ? SR.line : SR.accent.opacity(0.6), lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private var feedbackLine: some View {
        Group {
            if let wrong = store.wrongValue {
                Label("Not \(wrong). Try again.", systemImage: "xmark.circle.fill")
                    .foregroundStyle(SR.error)
                    .accessibilityIdentifier("sprint-wrong")
            } else if let gain {
                Label(gain > 1 ? "Right — bonus point!" : "Right!", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(SR.good)
            } else {
                Text(" ")
            }
        }
        .font(SR.Text.bodyMedium(15))
    }

    /// 0 resting, 1 a right answer, 2 a wrong one: the card's rim flashes.
    private var flashKey: Int {
        if store.wrongValue != nil { return 2 }
        return gain != nil ? 1 : 0
    }

    private var flashTone: Color {
        switch flashKey {
        case 1: return SR.good
        case 2: return SR.error
        default: return Color.clear
        }
    }

    // MARK: The keypad

    private var keypad: some View {
        SprintKeypad(
            enabled: store.canAnswer,
            canGo: store.canAnswer && !store.submitting && store.input.value != nil,
            press: { store.press($0) },
            minus: { store.toggleSign() },
            delete: { store.delete() },
            go: { store.submit() }
        )
        .padding(.horizontal, SR.gutter)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(SR.paper.opacity(0.94), ignoresSafeAreaEdges: .bottom)
    }
}

/// The sprint's clock as a bar that drains, olive to violet to red.
struct SprintTimeBar: View {
    let room: GameRoom
    @ObservedObject var store: MathsSprintStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            bar(share)
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    private func bar(_ share: Double) -> some View {
        Capsule()
            .fill(SR.line.opacity(0.5))
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(tone(share))
                        .frame(width: max(10, geo.size.width * CGFloat(share)))
                }
            }
            .srAnimation(.linear(duration: 0.25), value: share)
    }

    private var share: Double {
        guard let end = room.phaseEndsAt, let now = store.serverNow() else { return 1 }
        let total: Double = room.timeLimitMs ?? room.startedAt.map { end - $0 } ?? 60_000
        return SprintGauge.timeShare(msLeft: end - now, totalMs: total)
    }

    private func tone(_ share: Double) -> Color {
        if share < 0.17 { return SR.error }
        if share < 0.34 { return SR.accent }
        return SR.good
    }
}

/// The streak, as pips filling towards the next bonus, with a flare every
/// time it reaches one.
struct SprintStreak: View {
    let room: GameRoom
    let bonuses: Int

    var body: some View {
        let streak = room.sprint?.streak ?? 0
        let every = room.streakBonus
        let hot = MathsSprint.onBonus(streak: streak, every: every)
        HStack(spacing: 12) {
            Image(systemName: hot ? "flame.fill" : "flame")
                .font(SR.Text.title(24))
                .foregroundStyle(streak > 0 ? SR.accent : SR.inkGhost)
                .symbolEffect(.bounce, value: bonuses)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(streak == 1 ? "1 in a row" : "\(streak) in a row")
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                    Spacer(minLength: 4)
                    Text(hot ? "BONUS +1" : "\(MathsSprint.toBonus(streak: streak, every: every)) to the next bonus")
                        .font(SR.Text.label())
                        .tracking(hot ? 1.2 : 0)
                        .foregroundStyle(hot ? SR.accent : SR.inkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                pips(streak: streak, every: every, hot: hot)
            }
            if let misses = room.sprint?.misses, misses > 0 {
                Text(GameResults.count(misses, "miss", "misses"))
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous)
                .fill(hot ? SR.accent.opacity(0.14) : Color.clear)
        )
        .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
        .animation(.easeOut(duration: 0.25), value: hot)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hot ? "\(streak) in a row, bonus point" : "\(streak) in a row")
        .accessibilityIdentifier("sprint-streak")
    }

    private func pips(streak: Int, every: Int, hot: Bool) -> some View {
        let count = max(1, min(every, 10))
        let lit = SprintGauge.lit(streak: streak, every: every)
        let shown = every > 0 ? Int((Double(lit) / Double(every) * Double(count)).rounded()) : 0
        return HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index < shown ? (hot ? SR.accent : SR.good) : SR.line.opacity(0.7))
                    .frame(height: 7)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: shown)
    }
}

/// Everyone else: a place, a name and a live score, leader first.
struct SprintOthersStrip: View {
    let room: GameRoom

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ranked) { player in
                    chip(player)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
        .accessibilityIdentifier("sprint-others")
    }

    private var ranked: [GamePlayer] {
        room.others.sorted { a, b in a.score == b.score ? a.name < b.name : a.score > b.score }
    }

    private var scores: [(id: String, score: Int)] {
        var list: [(id: String, score: Int)] = room.others.map { (id: $0.id, score: $0.score) }
        if room.me?.joined == true {
            list.append((id: room.meId, score: room.sprint?.score ?? room.me?.score ?? 0))
        }
        return list
    }

    private func chip(_ player: GamePlayer) -> some View {
        let place = QuickRoomPlace.place(of: player.id, scores: scores) ?? 0
        return HStack(spacing: 10) {
            GameInitial(name: player.name, tone: place == 1 ? SR.accent : SR.accentInk, side: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(player.name)
                        .font(SR.Text.title(14))
                        .foregroundStyle(SR.ink)
                        .lineLimit(1)
                    if place == 1 {
                        Image(systemName: "crown.fill")
                            .font(SR.Text.label())
                            .foregroundStyle(SR.accent)
                    }
                }
                Text("\(player.score) pts")
                    .font(SR.Text.label())
                    .foregroundStyle(SR.inkSecondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(player.name), \(player.score) points")
        .accessibilityIdentifier("sprint-other-\(player.id)")
    }
}

/// 1–9, minus, 0, delete, and Go. Every key 60 points tall and a third of the
/// width, and each one gives under the thumb.
struct SprintKeypad: View {
    let enabled: Bool
    let canGo: Bool
    let press: (Int) -> Void
    let minus: () -> Void
    let delete: () -> Void
    let go: () -> Void

    static let keyHeight: CGFloat = 60
    static let gap: CGFloat = 8

    var body: some View {
        HStack(alignment: .top, spacing: Self.gap) {
            VStack(spacing: Self.gap) {
                ForEach([[1, 2, 3], [4, 5, 6], [7, 8, 9]], id: \.self) { row in
                    HStack(spacing: Self.gap) {
                        ForEach(row, id: \.self) { digit in
                            key(label: "\(digit)", spoken: "\(digit)", id: "sprint-key-\(digit)") { press(digit) }
                        }
                    }
                }
                HStack(spacing: Self.gap) {
                    key(label: "−", spoken: "Minus", id: "sprint-key-minus", action: minus)
                    key(label: "0", spoken: "0", id: "sprint-key-0") { press(0) }
                    key(icon: "delete.left", spoken: "Delete", id: "sprint-key-delete", action: delete)
                }
            }
            goKey
        }
        .opacity(enabled ? 1 : 0.55)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sprint-keypad")
    }

    private var goKey: some View {
        Button {
            go()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 26, weight: .heavy))
                Text("GO")
                    .font(SR.Text.display(24))
            }
            .foregroundStyle(SR.paper)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(canGo ? SR.accent : SR.accent.opacity(0.4))
            )
            .shadow(color: canGo ? SR.accent.opacity(0.35) : Color.clear, radius: 8, y: 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(QuickRoomKeyStyle())
        .disabled(!canGo)
        .frame(width: 88, height: Self.keyHeight * 4 + Self.gap * 3)
        .accessibilityLabel("Go")
        .accessibilityHint("Sends your answer")
        .accessibilityIdentifier("sprint-go")
    }

    private func key(label: String? = nil, icon: String? = nil, spoken: String, id: String,
                     action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(SR.surface)
                    .shadow(color: Color.black.opacity(0.08), radius: 2, y: 1)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(SR.line, lineWidth: 1)
                if let label {
                    Text(label)
                        .font(SR.Text.display(28))
                        .foregroundStyle(SR.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(SR.ink)
                }
            }
            .frame(maxWidth: .infinity, minHeight: Self.keyHeight, maxHeight: Self.keyHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(QuickRoomKeyStyle())
        .disabled(!enabled)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier(id)
    }
}

// MARK: - Finished

struct SprintFinished: View {
    let room: GameRoom
    @ObservedObject var store: MathsSprintStore
    let done: () -> Void
    @State private var note: QuickRoomBestNote?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Quick Maths Sprint · final",
                             title: GameResults.title(room, solo: "You scored \(myScore)", none: "Nobody scored"),
                             strap: GameResults.strap(room))

                if room.me?.joined == true || mine != nil {
                    QuickRoomStatRow(stats: stats)
                }

                if let note, mine != nil {
                    QuickRoomBestCard(title: "Your best sprint at \(GameDifficulty.label(for: room.difficulty).lowercased())",
                                      value: note.best.map { "\($0) pts" },
                                      isNew: note.isNew,
                                      previous: note.previous.map { "was \($0) pts" },
                                      id: "sprint-best")
                }

                if !room.solo && (room.standings?.count ?? 0) >= 2 {
                    QuickRoomPodium(room: room, figure: { "\($0.score) pts" })
                }

                GameStandingsCard(
                    room: room,
                    label: room.solo ? "Your sprint" : "Standings",
                    id: "sprint-standings",
                    detail: { row in
                        "\(row.correct) right · \(GameResults.count(row.misses, "miss", "misses")) · best streak \(row.bestStreak)"
                    },
                    figure: { (text: "\($0.score)", spoken: "\($0.score) points") }
                )

                recapsSection

                GameFinishedButtons(room: room, store: store, prefix: "sprint", done: done)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .overlay {
            if celebrate { QuickRoomConfetti() }
        }
        .accessibilityIdentifier("sprint-finished")
        // A win's tap and confetti come from `GameStandingsCard`; this page
        // adds them only for a new best the card does not celebrate.
        .onAppear { recordBest() }
    }

    @ViewBuilder
    private var recapsSection: some View {
        if let recaps = room.recaps, !recaps.isEmpty {
            VStack(alignment: .leading, spacing: SR.cardGap) {
                SRSectionLabel(text: room.solo ? "Your last problems" : "Last problems")
                ForEach(recaps) { recap in
                    SprintRecapCard(name: recap.playerId == room.meId ? "You" : room.name(of: recap.playerId),
                                    recap: recap)
                }
            }
        }
    }

    private var mine: GameStanding? { room.standings?.first { $0.id == room.meId } }

    private var myScore: Int { mine?.score ?? room.sprint?.score ?? room.me?.score ?? 0 }

    private var stats: [QuickRoomStat] {
        let correct = mine?.correct ?? room.sprint?.correct ?? 0
        let misses = mine?.misses ?? room.sprint?.misses ?? 0
        let streak = mine?.bestStreak ?? room.sprint?.bestStreak ?? 0
        let accuracy = SprintGauge.accuracy(correct: correct, misses: misses).map { "\($0)%" } ?? "—"
        return [
            QuickRoomStat(label: "Points", value: "\(myScore)"),
            QuickRoomStat(label: "Right", value: "\(correct)"),
            QuickRoomStat(label: "Best streak", value: "\(streak)"),
            QuickRoomStat(label: "Accuracy", value: accuracy)
        ]
    }

    /// Confetti for a new best — unless the standings card is already
    /// throwing its own for a win (or a family record).
    private var celebrate: Bool {
        note?.isNew == true && !GameResults.celebrates(room)
    }

    private func recordBest() {
        guard note == nil, let mine else { return }
        let signature = (room.standings ?? [])
            .map { "\($0.id):\($0.score):\($0.correct):\($0.misses)" }
            .joined(separator: ",")
        let started = Int(room.startedAt ?? 0)
        let fresh = QuickRoomBestStore.sprint.record(mine.score, difficulty: room.difficulty,
                                                     token: "\(room.id)|\(started)|\(signature)")
        note = fresh
        if fresh.isNew && !GameResults.celebrates(room) { SRHaptic.ok() }
    }
}

/// One player's last few problems, with the answers.
struct SprintRecapCard: View {
    let name: String
    let recap: SprintRecap

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name)
                .font(SR.Text.title(15))
                .foregroundStyle(SR.ink)
            if recap.problems.isEmpty {
                Text("No problems answered.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            }
            ForEach(recap.problems) { row in
                recapRow(row)
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sprint-recap-\(recap.playerId)")
    }

    private func recapRow(_ row: SprintRecapRow) -> some View {
        HStack(spacing: 10) {
            Image(systemName: row.solved ? "checkmark.circle.fill" : "xmark.circle")
                .font(SR.Text.title(17))
                .foregroundStyle(row.solved ? SR.good : SR.inkGhost)
                .accessibilityHidden(true)
            Text("\(row.text) = \(row.answer)")
                .font(SR.Text.bodyMedium(17))
                .foregroundStyle(SR.ink)
                .monospacedDigit()
            Spacer(minLength: 8)
            if row.wrongTries > 0 {
                Text(GameResults.count(row.wrongTries, "wrong try", "wrong tries"))
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(row))
    }

    private func spoken(_ row: SprintRecapRow) -> String {
        let state = row.solved ? "solved" : "not solved"
        let tries = row.wrongTries > 0 ? ", \(GameResults.count(row.wrongTries, "wrong try", "wrong tries"))" : ""
        return "\(SprintSpeech.problem(row.text)) equals \(row.answer), \(state)\(tries)"
    }
}
