import SwiftUI

/// Categories on one phone: the letter, the clock and a card of answers to
/// write; then the review — every answer judged, with a veto beside each of
/// the others' — and Done.
///
/// What I type is kept here (`drafts`) and sent as I type, so the host always
/// has my latest answer when the clock runs out; the fields never take the
/// host's copy back while I am typing, so an echo arriving late cannot undo
/// a keystroke. A phone that rejoins mid-game starts from the host's copy.
///
/// The letter is a die that rolls when it arrives (`PlayTableLetterDie`); the
/// card is an answer sheet with a numbered line per category that ticks green
/// when its answer starts with the letter and turns amber when it does not,
/// under a bar that fills as the card does. In the review each answer wears
/// a stamp — a point, shared, wrong letter, vetoed — and the veto is a real
/// button, not a small glyph.
struct OfflineCategoriesView: View {
    let context: OfflineGameContext<OfflineCategoriesRules>
    @State private var drafts: [String] = []
    @FocusState private var focused: Int?
    @ObservedObject private var results = OfflineResultStore.shared

    private typealias Rules = OfflineCategoriesRules

    private var view: Rules.PlayerView { context.view }
    private var reviewing: Bool { view.phase == .review || view.phase == .over }
    private var playing: Bool { view.phase == .playing && view.mine != nil }
    private var filled: Int { drafts.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count }
    private var myRow: Rules.Row? { view.board.first { $0.id == context.me } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                clockBar
                phaseContent
                if view.phase == .over, let mine = myRow {
                    PlayTableBestStrip(score: mine.score, best: results.queue.tallies[Rules.info.id]?.best)
                }
                OfflineWordScores(title: view.board.count == 1 ? "Score" : "Scores", rows: rows, me: context.me,
                                  players: context.players, id: "offline-categories-scores")
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .srGround(.warm)
        .onAppear { startDrafts() }
        .onChange(of: view.categories) { _, _ in startDrafts() }
        .onChange(of: view.phase) { _, new in
            if new != .playing { focused = nil }
            if new == .playing { SRHaptic.select() }
            if new == .review { SRHaptic.ok() }
        }
        .onChange(of: context.refusal) { _, new in
            if new != nil { SRHaptic.bad() }
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch view.phase {
        case .countdown:
            Text("A letter and a card of \(Rules.cardSize) categories are coming. Get ready.")
                .font(SR.Text.body())
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .playing:
            if playing {
                progress
                card
            } else {
                Text("You are watching this one. The answers show when time is up.")
                    .font(SR.Text.body())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .review, .over:
            review
        }
    }

    /// One empty answer a category — or, rejoining, the host's copy of mine.
    private func startDrafts() {
        guard drafts.count != view.categories.count else { return }
        if let mine = view.mine, mine.count == view.categories.count {
            drafts = mine
        } else {
            drafts = Array(repeating: "", count: view.categories.count)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            PlayTableLetterDie(letter: view.letter, side: 76)
            VStack(alignment: .leading, spacing: 4) {
                Text(view.mine == nil ? "CATEGORIES · WATCHING" : "CATEGORIES")
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(SR.accent)
                Text(title)
                    .font(SR.Text.display(22))
                    .foregroundStyle(SR.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                if let letter = view.letter {
                    Text("Every answer starts with \(letter.uppercased())")
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkMuted)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("offline-categories-header")
    }

    private var title: String {
        switch view.phase {
        case .countdown: return "Ready…"
        case .playing: return playing ? "\(filled) of \(view.categories.count) answered" : "Writing"
        case .review, .over:
            guard let top = view.board.first else { return "Time's up" }
            if view.board.count == 1 { return top.score == 1 ? "1 point" : "\(top.score) points" }
            if view.phase == .review, myRow?.done != true { return "Check the answers" }
            if view.board.filter({ $0.score == top.score }).count > 1 { return "A tie" }
            return top.id == context.me ? "You win" : "\(top.name) wins"
        }
    }

    private var clockBar: some View {
        switch view.phase {
        case .countdown:
            return OfflineWordClock(clock: context.clock, label: "Starting in", until: view.startsAt, tone: SR.accent)
        case .playing:
            return OfflineWordClock(clock: context.clock, label: "Time left", until: view.endsAt,
                                    chip: view.together ? "same answer scores 0" : nil)
        case .review:
            return OfflineWordClock(clock: context.clock, label: view.together ? "Review" : "Your card",
                                    until: view.reviewUntil, chip: view.together ? "veto what doesn't fit" : nil)
        case .over:
            return OfflineWordClock(clock: context.clock, label: "Done", until: nil)
        }
    }

    // MARK: - Writing

    /// How full the card is, as a bar that fills.
    private var progress: some View {
        let total = max(view.categories.count, 1)
        let fraction = CGFloat(filled) / CGFloat(total)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(SR.inkGhost.opacity(0.25))
                Capsule()
                    .fill(LinearGradient(colors: [SR.accent, SR.good], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(10, geo.size.width * fraction))
                    .opacity(filled == 0 ? 0 : 1)
            }
        }
        .frame(height: 10)
        .srAnimation(.spring(response: 0.4, dampingFraction: 0.75), value: filled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(filled) of \(view.categories.count) answered")
    }

    private var card: some View {
        VStack(spacing: 0) {
            ForEach(Array(view.categories.enumerated()), id: \.offset) { index, category in
                if index > 0 {
                    Rectangle()
                        .fill(SR.accent.opacity(0.18))
                        .frame(height: 1)
                }
                row(index, category)
            }
            Text(view.together ? "Answers save as you type. The same answer as someone else scores nothing."
                               : "Answers save as you type.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
        }
        .padding(SR.cardPadding)
        .overlay(alignment: .leading) {
            // The red margin rule of a sheet of exercise paper.
            Rectangle()
                .fill(SR.error.opacity(0.35))
                .frame(width: 1.5)
                .padding(.leading, SR.cardPadding + 40)
                .padding(.vertical, 14)
                .accessibilityHidden(true)
        }
        .srGlassCard(.paper)
    }

    private func row(_ index: Int, _ category: String) -> some View {
        let text = index < drafts.count ? drafts[index] : ""
        let warning = CategoriesRules.warning(text, letter: view.letter)
        let count = view.categories.count
        let answered = !text.trimmingCharacters(in: .whitespaces).isEmpty
        let tone: Color = !answered ? SR.inkGhost : (warning == nil ? SR.good : SR.warn)
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(answered ? tone : Color.clear)
                Circle()
                    .strokeBorder(tone, lineWidth: 2)
                if answered {
                    Image(systemName: warning == nil ? "checkmark" : "exclamationmark")
                        .font(SR.Text.label(13))
                        .foregroundStyle(Color.white)
                } else {
                    Text("\(index + 1)")
                        .font(SR.Text.label())
                        .foregroundStyle(SR.inkMuted)
                        .monospacedDigit()
                }
            }
            .frame(width: 30, height: 30)
            .padding(.top, 2)
            .srAnimation(.spring(response: 0.3, dampingFraction: 0.6), value: answered)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(category)
                    .font(SR.Text.title(15))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                field(index, category, count: count)
                if let warning {
                    Label(warning, systemImage: "exclamationmark.circle")
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.warn)
                }
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private func field(_ index: Int, _ category: String, count: Int) -> some View {
        TextField(view.letter.map { "\($0.uppercased())…" } ?? "…", text: Binding(
            get: { index < drafts.count ? drafts[index] : "" },
            set: { edit(index, $0) }
        ))
        .font(SR.Text.body(18))
        .foregroundStyle(SR.ink)
        .textInputAutocapitalization(.words)
        .submitLabel(index + 1 < count ? .next : .done)
        .focused($focused, equals: index)
        .onSubmit { focused = index + 1 < count ? index + 1 : nil }
        .padding(.horizontal, 4)
        .frame(minHeight: 48)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(focused == index ? SR.accent : SR.line)
                .frame(height: focused == index ? 2 : 1)
        }
        .accessibilityLabel("\(category), answer")
        .accessibilityIdentifier("offline-categories-field-\(index)")
    }

    /// Keeps the draft and sends it: the host stores the latest, so nothing
    /// is lost when the clock runs out mid-word.
    private func edit(_ index: Int, _ text: String) {
        guard playing, index < drafts.count else { return }
        let capped = text.count > Rules.maxAnswer ? String(text.prefix(Rules.maxAnswer)) : text
        guard capped != drafts[index] else { return }
        drafts[index] = capped
        context.send(.answer(index: index, text: capped))
    }

    // MARK: - The review

    @ViewBuilder
    private var review: some View {
        if let cards = view.review {
            ForEach(Array(cards.enumerated()), id: \.offset) { index, answers in
                VStack(alignment: .leading, spacing: SR.cardGap) {
                    SRSectionLabel(text: index < view.categories.count ? view.categories[index] : "Category \(index + 1)")
                    VStack(spacing: 0) {
                        ForEach(Array(answers.enumerated()), id: \.element.id) { position, answer in
                            if position > 0 { Divider().overlay(SR.divider) }
                            answerRow(answer)
                        }
                    }
                    .padding(.horizontal, SR.cardPadding)
                    .padding(.vertical, 4)
                    .srGlassCard(.paper)
                }
                .accessibilityIdentifier("offline-categories-review-\(index)")
            }
        }
        if view.mine != nil, view.phase == .review {
            OfflineWordContinue(ready: myRow?.done ?? false,
                                waitingOn: view.board.filter { !$0.done && !$0.away && $0.id != context.me }.map(\.name),
                                id: "offline-categories-done") {
                context.send(.done)
            }
        }
    }

    private func answerRow(_ answer: Rules.Answer) -> some View {
        let mine = answer.owner == context.me
        let crossed = answer.status == .shared || answer.status == .wrongLetter || answer.status == .struck
        let canVeto = view.together && view.phase == .review && view.mine != nil && !mine && answer.status != .empty
        return HStack(alignment: .center, spacing: 10) {
            OfflineInitial(name: context.name(of: answer.owner), size: 30,
                           tone: OfflineSeatColour.of(context.players.firstIndex { $0.id == answer.owner } ?? 0))
            VStack(alignment: .leading, spacing: 4) {
                Text(answer.text.isEmpty ? "—" : answer.text)
                    .font(SR.Text.title(17))
                    .foregroundStyle(answer.text.isEmpty || crossed ? SR.inkGhost : SR.ink)
                    .strikethrough(crossed, color: SR.inkMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    statusPill(answer)
                    Text(shortLine(answer, mine: mine))
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityLabel(line(answer, mine: mine))
                }
            }
            Spacer(minLength: 8)
            if canVeto { vetoButton(answer) }
            Text(answer.points > 0 ? "+1" : "0")
                .font(SR.Text.figure(20))
                .foregroundStyle(answer.points > 0 ? SR.good : SR.inkGhost)
                .frame(minWidth: 28, alignment: .trailing)
                .srNumeric(Double(answer.points))
        }
        .frame(minHeight: 60)
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private func vetoButton(_ answer: Rules.Answer) -> some View {
        Button {
            if answer.vetoedByMe { SRHaptic.select() } else { SRHaptic.tap() }
            context.send(.veto(owner: answer.owner, index: answer.index, on: !answer.vetoedByMe))
        } label: {
            VStack(spacing: 2) {
                Image(systemName: answer.vetoedByMe ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .font(SR.Text.title(18))
                Text(answer.vetoedByMe ? "VETOED" : "VETO")
                    .font(SR.Text.label(10))
                    .tracking(0.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(answer.vetoedByMe ? Color.white : SR.error)
            .frame(width: PlayTableMetrics.bigButton, height: PlayTableMetrics.bigButton)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(answer.vetoedByMe ? SR.error : SR.error.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(SR.error.opacity(answer.vetoedByMe ? 0 : 0.45), lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(SRPressStyle())
        .srAnimation(.snappy(duration: 0.2), value: answer.vetoedByMe)
        .accessibilityLabel(answer.vetoedByMe ? "Take back your veto" : "Veto \(answer.text)")
        .accessibilityIdentifier("offline-categories-veto-\(answer.owner)-\(answer.index)")
    }

    /// The answer's verdict as a small coloured stamp.
    private func statusPill(_ answer: Rules.Answer) -> some View {
        let words: String
        let tone: Color
        switch answer.status {
        case .ok: words = "POINT"; tone = SR.good
        case .shared: words = "SHARED"; tone = SR.warn
        case .wrongLetter: words = "WRONG LETTER"; tone = SR.warn
        case .struck: words = "VETOED"; tone = SR.error
        case .empty: words = "BLANK"; tone = SR.inkMuted
        }
        return Text(words)
            .font(SR.Text.label(11))
            .tracking(0.6)
            .foregroundStyle(tone)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(tone.opacity(0.14)))
            .overlay(Capsule().strokeBorder(tone.opacity(0.5), lineWidth: 1))
            .accessibilityHidden(true)
    }

    /// Beside the stamp: who, and the vetoes so far — the stamp says the rest.
    private func shortLine(_ answer: Rules.Answer, mine: Bool) -> String {
        var parts = [mine ? "You" : context.name(of: answer.owner)]
        if answer.vetoes > 0, answer.status != .struck, answer.strikeAt > 0 {
            parts.append("\(answer.vetoes) of \(answer.strikeAt) \(answer.strikeAt == 1 ? "veto" : "vetoes")")
        }
        return parts.joined(separator: " · ")
    }

    /// "Ann · SHARED", "You · 1 of 2 vetoes".
    private func line(_ answer: Rules.Answer, mine: Bool) -> String {
        var parts = [mine ? "You" : context.name(of: answer.owner)]
        switch answer.status {
        case .ok: parts.append("a point")
        case .shared: parts.append("SHARED")
        case .wrongLetter: parts.append("WRONG LETTER")
        case .struck: parts.append("VETOED")
        case .empty: parts.append("blank")
        }
        if answer.vetoes > 0, answer.status != .struck, answer.strikeAt > 0 {
            parts.append("\(answer.vetoes) of \(answer.strikeAt) \(answer.strikeAt == 1 ? "veto" : "vetoes")")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Scores

    private var rows: [OfflineWordScoreRow] {
        view.board.map { row in
            OfflineWordScoreRow(id: row.id, name: row.name,
                                detail: "\(row.filled) of \(max(view.categories.count, Rules.cardSize)) answered",
                                score: reviewing ? row.score : nil, away: row.away,
                                ready: view.phase == .review && row.done)
        }
    }
}
