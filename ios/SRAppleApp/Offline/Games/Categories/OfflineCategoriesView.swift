import SwiftUI

/// Categories on one phone: the letter, the clock and a card of answers to
/// write; then the review — every answer judged, with a veto beside each of
/// the others' — and Done.
///
/// What I type is kept here (`drafts`) and sent as I type, so the host always
/// has my latest answer when the clock runs out; the fields never take the
/// host's copy back while I am typing, so an echo arriving late cannot undo
/// a keystroke. A phone that rejoins mid-game starts from the host's copy.
struct OfflineCategoriesView: View {
    let context: OfflineGameContext<OfflineCategoriesRules>
    @State private var drafts: [String] = []
    @FocusState private var focused: Int?

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
                switch view.phase {
                case .countdown:
                    Text("A letter and a card of \(Rules.cardSize) categories are coming. Get ready.")
                        .font(SR.Text.body())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .playing:
                    if playing {
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
        HStack(alignment: .center, spacing: 14) {
            CategoriesLetter(letter: view.letter, side: 68)
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

    private var card: some View {
        VStack(spacing: 10) {
            ForEach(Array(view.categories.enumerated()), id: \.offset) { index, category in
                row(index, category)
            }
            Text(view.together ? "Answers save as you type. The same answer as someone else scores nothing."
                               : "Answers save as you type.")
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    private func row(_ index: Int, _ category: String) -> some View {
        let text = index < drafts.count ? drafts[index] : ""
        let warning = CategoriesRules.warning(text, letter: view.letter)
        let count = view.categories.count
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(index + 1)")
                    .font(SR.Text.label())
                    .foregroundStyle(SR.inkGhost)
                    .monospacedDigit()
                    .frame(minWidth: 18, alignment: .leading)
                Text(category)
                    .font(SR.Text.title(15))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextField(view.letter.map { "\($0.uppercased())…" } ?? "…", text: Binding(
                get: { index < drafts.count ? drafts[index] : "" },
                set: { edit(index, $0) }
            ))
            .font(SR.Text.body(17))
            .foregroundStyle(SR.ink)
            .textInputAutocapitalization(.words)
            .submitLabel(index + 1 < count ? .next : .done)
            .focused($focused, equals: index)
            .onSubmit { focused = index + 1 < count ? index + 1 : nil }
            .padding(.horizontal, 12)
            .frame(minHeight: SR.tapTarget)
            .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
            .accessibilityLabel("\(category), answer")
            .accessibilityIdentifier("offline-categories-field-\(index)")
            if let warning {
                Label(warning, systemImage: "exclamationmark.circle")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.warn)
            }
        }
        .accessibilityElement(children: .contain)
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
            OfflineInitial(name: context.name(of: answer.owner), size: 26,
                           tone: OfflineSeatColour.of(context.players.firstIndex { $0.id == answer.owner } ?? 0))
            VStack(alignment: .leading, spacing: 2) {
                Text(answer.text.isEmpty ? "—" : answer.text)
                    .font(SR.Text.title(16))
                    .foregroundStyle(answer.text.isEmpty || crossed ? SR.inkGhost : SR.ink)
                    .strikethrough(crossed, color: SR.inkMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(line(answer, mine: mine))
                    .font(SR.Text.mono())
                    .foregroundStyle(answer.status == .ok ? SR.good : SR.inkMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if canVeto {
                Button {
                    SRHaptic.select()
                    context.send(.veto(owner: answer.owner, index: answer.index, on: !answer.vetoedByMe))
                } label: {
                    Image(systemName: answer.vetoedByMe ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(answer.vetoedByMe ? SR.error : SR.inkSecondary)
                        .frame(width: SR.tapTarget, height: SR.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(answer.vetoedByMe ? "Take back your veto" : "Veto \(answer.text)")
                .accessibilityIdentifier("offline-categories-veto-\(answer.owner)-\(answer.index)")
            }
            Text(answer.points > 0 ? "+1" : "0")
                .font(SR.Text.figure(18))
                .foregroundStyle(answer.points > 0 ? SR.ink : SR.inkGhost)
                .frame(minWidth: 26, alignment: .trailing)
        }
        .frame(minHeight: SR.tapTarget)
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
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
