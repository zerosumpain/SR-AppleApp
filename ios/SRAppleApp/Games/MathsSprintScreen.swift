import SwiftUI
import UIKit

/// One Quick Maths Sprint room, from lobby to the recaps.
///
/// The lobby and the 3-2-1 are every game's (`GameLobby`, `GameCountdownView`).
/// Playing is my current problem, big, exactly as the server wrote it; a keypad
/// pinned under it; my score and streak; and everyone else as a name and a
/// score. Finished is the standings and each player's last few problems.
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
                GameLobby(room: room, store: store, prefix: "sprint", done: { dismiss() })
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

// MARK: - Playing

struct SprintPlaying: View {
    let room: GameRoom
    @ObservedObject var store: MathsSprintStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
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
        .safeAreaInset(edge: .bottom) {
            SprintKeypad(
                enabled: store.canAnswer,
                canGo: store.canAnswer && !store.submitting && store.input.value != nil,
                press: { store.press($0) },
                minus: { store.toggleSign() },
                delete: { store.delete() },
                go: { store.submit() }
            )
            .padding(.horizontal, SR.gutter)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .background(SR.paper.opacity(0.94), ignoresSafeAreaEdges: .bottom)
        }
        .accessibilityIdentifier("sprint-playing")
        .onChange(of: store.shakes) { _, _ in
            if let wrong = store.wrongValue {
                UIAccessibility.post(notification: .announcement, argument: "Not \(wrong). Try again.")
            }
        }
    }

    private var me: SprintMe? { room.sprint }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("QUICK MATHS · \(GameDifficulty.label(for: room.difficulty).uppercased())")
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(me?.score ?? 0)")
                        .font(SR.Text.display(26))
                        .foregroundStyle(SR.ink)
                        .monospacedDigit()
                    Text("POINTS")
                        .font(SR.Text.label())
                        .foregroundStyle(SR.inkMuted)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Your score, \(me?.score ?? 0) points")
                .accessibilityIdentifier("sprint-my-score")
            }
            Spacer(minLength: 8)
            WordleTimer(room: room, store: store, id: "sprint-timer")
        }
    }

    private var problemCard: some View {
        VStack(spacing: 10) {
            if let problem = me?.problem {
                Text("PROBLEM \(problem.index + 1)")
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.inkMuted)
                Text(problem.text)
                    .font(SR.Text.hero(52))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .accessibilityLabel(SprintSpeech.problem(problem.text))
                    .accessibilityIdentifier("sprint-problem")
                    .modifier(WordleShake(animatableData: CGFloat(reduceMotion ? 0 : store.shakes)))
                    .animation(.linear(duration: 0.4), value: store.shakes)
                Text(store.input.isEmpty ? "?" : store.input.display)
                    .font(SR.Text.figure(40))
                    .foregroundStyle(store.input.isEmpty ? SR.inkGhost : SR.accent)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(minHeight: 48)
                    .accessibilityLabel(store.input.isEmpty ? "Your answer, empty" : "Your answer, \(store.input.display)")
                    .accessibilityIdentifier("sprint-answer")
                Group {
                    if let wrong = store.wrongValue {
                        Label("Not \(wrong). Try again.", systemImage: "xmark.circle")
                            .foregroundStyle(SR.error)
                            .accessibilityIdentifier("sprint-wrong")
                    } else {
                        Text(" ")
                    }
                }
                .font(SR.Text.bodyMedium(15))
            } else if room.me?.joined != true {
                Text("You are not playing in this one.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
            } else {
                Text(me.map { $0.correct >= room.problemCount ? "You answered them all." : "Time’s up." } ?? "Time’s up.")
                    .font(SR.Text.display(24))
                    .foregroundStyle(SR.ink)
            }
        }
        .padding(SR.cardPadding + 4)
        .frame(maxWidth: .infinity)
        .srGlassCard(.paper)
    }
}

/// The streak, with a cue every time it reaches a bonus.
struct SprintStreak: View {
    let room: GameRoom
    let bonuses: Int

    var body: some View {
        let streak = room.sprint?.streak ?? 0
        let every = room.streakBonus
        let hot = MathsSprint.onBonus(streak: streak, every: every)
        HStack(spacing: 10) {
            Image(systemName: hot ? "flame.fill" : "flame")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(streak > 0 ? SR.accent : SR.inkGhost)
                .symbolEffect(.bounce, value: bonuses)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(streak == 1 ? "1 in a row" : "\(streak) in a row")
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                Text(hot ? "BONUS +1" : "\(MathsSprint.toBonus(streak: streak, every: every)) to the next bonus")
                    .font(SR.Text.label())
                    .tracking(hot ? 1.2 : 0)
                    .foregroundStyle(hot ? SR.accent : SR.inkMuted)
            }
            Spacer(minLength: 8)
            if let misses = room.sprint?.misses, misses > 0 {
                Text(GameResults.count(misses, "miss", "misses"))
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous)
                .fill(hot ? SR.accent.opacity(0.14) : Color.clear)
        )
        .animation(.easeOut(duration: 0.25), value: hot)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hot ? "\(streak) in a row, bonus point" : "\(streak) in a row")
        .accessibilityIdentifier("sprint-streak")
    }
}

/// Everyone else: a name and a live score.
struct SprintOthersStrip: View {
    let room: GameRoom

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(room.others) { player in
                    HStack(spacing: 10) {
                        GameInitial(name: player.name, side: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.name)
                                .font(SR.Text.title(14))
                                .foregroundStyle(SR.ink)
                                .lineLimit(1)
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
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
        .accessibilityIdentifier("sprint-others")
    }
}

/// 1–9, minus, 0, delete, and Go. Every key at least 44 points each way.
struct SprintKeypad: View {
    let enabled: Bool
    let canGo: Bool
    let press: (Int) -> Void
    let minus: () -> Void
    let delete: () -> Void
    let go: () -> Void

    static let keyHeight: CGFloat = 54
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
            Button {
                go()
            } label: {
                Text("GO")
                    .font(SR.Text.display(22))
                    .foregroundStyle(SR.paper)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(canGo ? SR.accent : SR.accent.opacity(0.45))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canGo)
            .frame(width: 84, height: Self.keyHeight * 4 + Self.gap * 3)
            .accessibilityLabel("Go")
            .accessibilityHint("Sends your answer")
            .accessibilityIdentifier("sprint-go")
        }
        .opacity(enabled ? 1 : 0.55)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sprint-keypad")
    }

    private func key(label: String? = nil, icon: String? = nil, spoken: String, id: String,
                     action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SR.surface)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(SR.line, lineWidth: 1)
                if let label {
                    Text(label)
                        .font(SR.Text.display(24))
                        .foregroundStyle(SR.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(SR.ink)
                }
            }
            .frame(maxWidth: .infinity, minHeight: Self.keyHeight, maxHeight: Self.keyHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                SRPageHeader(kicker: "Quick Maths Sprint · final",
                             title: GameResults.title(room, solo: "You scored \(room.sprint?.score ?? room.me?.score ?? 0)", none: "Nobody scored"),
                             strap: GameResults.strap(room))

                GameStandingsCard(
                    room: room,
                    label: room.solo ? "Your sprint" : "Standings",
                    id: "sprint-standings",
                    detail: { row in
                        "\(row.correct) right · \(GameResults.count(row.misses, "miss", "misses")) · best streak \(row.bestStreak)"
                    },
                    figure: { (text: "\($0.score)", spoken: "\($0.score) points") }
                )

                if let recaps = room.recaps, !recaps.isEmpty {
                    VStack(alignment: .leading, spacing: SR.cardGap) {
                        SRSectionLabel(text: room.solo ? "Your last problems" : "Last problems")
                        ForEach(recaps) { recap in
                            SprintRecapCard(name: recap.playerId == room.meId ? "You" : room.name(of: recap.playerId),
                                            recap: recap)
                        }
                    }
                }

                GameFinishedButtons(room: room, store: store, prefix: "sprint", done: done)
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("sprint-finished")
        .onAppear { if room.winnerIds.contains(room.meId) { SRHaptic.ok() } }
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
                HStack(spacing: 10) {
                    Image(systemName: row.solved ? "checkmark.circle.fill" : "xmark.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(row.solved ? SR.good : SR.inkGhost)
                        .accessibilityHidden(true)
                    Text("\(row.text) = \(row.answer)")
                        .font(SR.Text.bodyMedium(16))
                        .foregroundStyle(SR.ink)
                        .monospacedDigit()
                    Spacer(minLength: 8)
                    if row.wrongTries > 0 {
                        Text(GameResults.count(row.wrongTries, "wrong try", "wrong tries"))
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken(row))
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sprint-recap-\(recap.playerId)")
    }

    private func spoken(_ row: SprintRecapRow) -> String {
        let state = row.solved ? "solved" : "not solved"
        let tries = row.wrongTries > 0 ? ", \(GameResults.count(row.wrongTries, "wrong try", "wrong tries"))" : ""
        return "\(SprintSpeech.problem(row.text)) equals \(row.answer), \(state)\(tries)"
    }
}
