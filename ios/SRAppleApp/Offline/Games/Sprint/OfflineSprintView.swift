import SwiftUI

/// Maths Sprint on one phone: the clock, my sum and my score, a keypad, and
/// everyone's running total.
///
/// The keypad is built from the page's width (three keys a row, each at
/// least a thumb tall), so it fits a 375-point phone at any text size; the
/// sum itself scales down rather than wrap. What I have typed stays on this
/// phone until Enter — only the answer travels.
///
/// The overhaul (2026-10-29) counts in 3-2-1 with big bumping digits, runs
/// the minute as a ring, ticks a right answer green and shakes a wrong one,
/// calls out a streak bonus, makes every key a thumb-sized tile, races the
/// scores as bars, and keeps this phone's best score.
struct OfflineSprintView: View {
    let context: OfflineGameContext<OfflineSprintRules>
    @State private var typed = ""
    /// The sum an answer was sent for, so a double tap sends once; the next
    /// view (a new index) or a refusal clears it.
    @State private var sentFor: Int?
    /// How the last answer went, for the tick or the cross on the sum.
    @State private var verdict: Bool?
    @State private var verdictToken = 0
    @State private var shakes = 0
    @State private var callout = ""
    @State private var calloutToken = 0
    @State private var best: NearbyPlayBestOutcome?
    @State private var burstToken = 0

    private var view: OfflineSprintRules.PlayerView { context.view }
    private var mine: OfflineSprintRules.Mine? { view.me }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                NearbyPlayBanner(kicker: kicker, title: title, mine: view.phase == .playing && mine != nil,
                                 mark: .symbol("plus.forwardslash.minus")) {
                    clock
                }
                .accessibilityIdentifier("offline-sprint-header")
                if let mine, view.phase == .playing || view.phase == .countdown {
                    problemCard(mine)
                    keypad
                }
                if let best, let mine, view.phase == .done || view.phase == .over {
                    NearbyPlayBestLine(outcome: best, value: mine.score, format: { "\($0) pts" })
                }
                board
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .overlay {
            ZStack {
                NearbyPlayBurst(token: burstToken)
                NearbyPlayCallout(text: callout, icon: "flame.fill", tone: SR.good, token: calloutToken, hold: 1.0)
            }
        }
        .onChange(of: mine?.index) { _, _ in
            sentFor = nil
            typed = ""
            if let right = mine?.lastRight { answered(right) }
        }
        .onChange(of: view.phase) { old, new in
            if new == .playing { SRHaptic.select() }
            // Once, on the first view past the whistle — even if a missed
            // view means this phone goes straight from playing to over.
            let ended = new == .done || new == .over
            let wasEnded = old == .done || old == .over
            if ended && !wasEnded {
                SRHaptic.ok()
                finished()
            }
        }
        .onChange(of: context.refusal) { _, new in
            if new != nil { sentFor = nil }
        }
    }

    // MARK: - Words

    private var kicker: String {
        guard let mine else { return "Maths Sprint · watching" }
        return "Maths Sprint · \(mine.right) right"
    }

    private var title: String {
        switch view.phase {
        case .countdown: return "Ready…"
        case .playing: return mine.map { "\($0.score) points" } ?? "Racing"
        case .done, .over:
            guard let top = view.board.first else { return "Time's up" }
            if view.board.count == 1 { return "\(top.score) points" }
            return top.id == context.me ? "You win" : "\(top.name) wins"
        }
    }

    // MARK: - The clock

    @ViewBuilder
    private var clock: some View {
        switch view.phase {
        case .countdown:
            EmptyView()
        case .playing:
            NearbyPlayBannerClock(clock: context.clock, until: view.endsAt,
                                  total: OfflineSprintRules.seconds, mine: mine != nil)
        case .done, .over:
            Image(systemName: "flag.checkered")
                .font(SR.Text.display(26))
                .foregroundStyle(SR.inkMuted)
                .accessibilityLabel("Time's up")
        }
    }

    // MARK: - My sum

    private func problemCard(_ mine: OfflineSprintRules.Mine) -> some View {
        VStack(spacing: 12) {
            if view.phase == .countdown {
                NearbyPlayCountdownHero(clock: context.clock, until: view.startsAt, size: 96, tone: SR.accent)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                HStack(spacing: 8) {
                    if mine.streak >= 2 {
                        NearbyPlayStat(icon: "flame.fill", text: "\(mine.streak) in a row")
                            .nearbyPlayBump(mine.streak)
                    }
                    Spacer(minLength: 0)
                    if let verdict {
                        Image(systemName: verdict ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(SR.Text.display(26))
                            .foregroundStyle(verdict ? SR.good : SR.error)
                            .nearbyPlayBump(verdictToken, scale: 1.3)
                            .accessibilityLabel(verdict ? "Right" : "Wrong")
                    }
                }
                .frame(minHeight: 30)
                Text(mine.problem.map { "\($0) =" } ?? "Get ready")
                    .font(SR.Text.hero(44))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .modifier(NearbyPlayShake(travel: 10, animatableData: CGFloat(shakes)))
                    .accessibilityLabel(mine.problem.map { "What is \(spoken($0))?" } ?? "Get ready")
            }
            answerSlot
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity)
        .srGlassCard(.paper)
    }

    private var answerSlot: some View {
        let shape = RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous)
        return HStack(spacing: 2) {
            Text(typed.isEmpty ? " " : typed)
                .font(SR.Text.figure(38))
                .foregroundStyle(SR.accent)
                .lineLimit(1)
            if canAnswer {
                Capsule()
                    .fill(SR.accent.opacity(0.6))
                    .frame(width: 3, height: 32)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(shape.fill(SR.surface))
        .overlay(shape.strokeBorder(verdictRim, lineWidth: verdict == nil ? 1 : 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(typed.isEmpty ? "No answer typed" : "Your answer, \(typed)")
        .accessibilityIdentifier("offline-sprint-typed")
    }

    private var verdictRim: Color {
        guard let verdict else { return SR.line }
        return verdict ? SR.good : SR.error
    }

    /// "12 × 7" read as words: VoiceOver says "minus" for "−", not "dash".
    private func spoken(_ text: String) -> String {
        text.replacingOccurrences(of: "−", with: "minus")
            .replacingOccurrences(of: "×", with: "times")
            .replacingOccurrences(of: "÷", with: "divided by")
    }

    // MARK: - The keypad

    private var canAnswer: Bool {
        view.phase == .playing && mine?.problem != nil && sentFor == nil
    }

    private var keypad: some View {
        let rows: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["⌫", "0", "Enter"]]
        return VStack(spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in keyButton(key) }
                }
            }
        }
        .disabled(!canAnswer)
        .opacity(canAnswer ? 1 : 0.5)
    }

    private func keyButton(_ key: String) -> some View {
        let enter = key == "Enter"
        let shape = RoundedRectangle(cornerRadius: NearbyPlayMetrics.radius, style: .continuous)
        return Button {
            press(key)
        } label: {
            Group {
                if key == "⌫" {
                    Image(systemName: "delete.left.fill")
                        .font(SR.Text.display(24))
                } else if enter {
                    Image(systemName: "return")
                        .font(SR.Text.display(24))
                } else {
                    Text(key)
                        .font(SR.Text.figure(30))
                }
            }
            .foregroundStyle(enter ? SR.paper : SR.ink)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(shape.fill(enter ? SR.accentDeep : SR.surface))
            .overlay(shape.strokeBorder(enter ? Color.clear : SR.line, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
            .contentShape(shape)
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel(key == "⌫" ? "Delete" : key)
        .accessibilityIdentifier("offline-sprint-key-\(key == "⌫" ? "delete" : key.lowercased())")
    }

    private func press(_ key: String) {
        switch key {
        case "⌫":
            if !typed.isEmpty { typed.removeLast() }
            SRHaptic.select()
        case "Enter":
            guard let mine, let value = Int(typed), canAnswer else { return }
            sentFor = mine.index
            context.send(.answer(index: mine.index, value: value))
        default:
            guard typed.count < 5 else { return }
            typed += key
            SRHaptic.select()
        }
    }

    // MARK: - Moments

    private func answered(_ right: Bool) {
        verdict = right
        verdictToken += 1
        if right {
            SRHaptic.tap()
            if let streak = mine?.streak, streak > 0, streak % OfflineSprintRules.streakEvery == 0 {
                callout = "Streak bonus +\(OfflineSprintRules.streakBonus)"
                calloutToken += 1
            }
        } else {
            SRHaptic.bad()
            withAnimation(.linear(duration: 0.35)) { shakes += 1 }
        }
    }

    private func finished() {
        if view.board.count > 1, view.board.first?.id == context.me { burstToken += 1 }
        if best == nil, let mine {
            best = NearbyPlayBestBook.record(OfflineSprintRules.info.id, value: mine.score, rule: .higher)
            if best?.beatAnOldBest == true { burstToken += 1 }
        }
    }

    // MARK: - Everyone

    private var leader: Int { max(1, view.board.map(\.score).max() ?? 1) }

    private var board: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: view.board.count == 1 ? "Score" : "Scores")
            VStack(spacing: 0) {
                ForEach(Array(view.board.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().overlay(SR.divider) }
                    boardRow(row, place: index + 1)
                }
            }
            .padding(.horizontal, SR.cardPadding)
            .padding(.vertical, 4)
            .srGlassCard(.paper)
            .accessibilityIdentifier("offline-sprint-board")
        }
    }

    private func boardRow(_ row: OfflineSprintRules.Row, place: Int) -> some View {
        let tone = OfflineSeatColour.of(seat(of: row.id))
        let share = CGFloat(max(0, row.score)) / CGFloat(leader)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                if view.board.count > 1 {
                    NearbyPlayPlaceDisc(place: place)
                }
                OfflineInitial(name: row.name, size: 30, tone: tone)
                Text(row.id == context.me ? "\(row.name) (you)" : row.name)
                    .font(SR.Text.title(16))
                    .foregroundStyle(row.away ? SR.inkMuted : SR.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(row.right) right")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                Text("\(row.score)")
                    .font(SR.Text.figure(22))
                    .foregroundStyle(SR.ink)
                    .contentTransition(.numericText(value: Double(row.score)))
            }
            GeometryReader { geo in
                Capsule()
                    .fill(tone)
                    .frame(width: max(6, geo.size.width * share))
            }
            .frame(height: 5)
            .srAnimation(.snappy(duration: 0.3), value: row.score)
            .accessibilityHidden(true)
        }
        .frame(minHeight: 56)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func seat(of id: String) -> Int {
        context.players.firstIndex { $0.id == id } ?? 0
    }
}
