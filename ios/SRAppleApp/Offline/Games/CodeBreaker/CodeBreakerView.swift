import SwiftUI

/// Code Breaker on one phone: my guesses and their marks, the peg picker,
/// the race clock, and how far everyone else has got.
///
/// Every peg is sized from the width the page is given (measured once, below
/// the header), so four pegs and their marks — and the six-colour picker —
/// fit a 375-point phone with room to spare. The picker fills the
/// highlighted slot and moves on to the next empty one; tapping a slot
/// moves the highlight there, so a single peg can be changed without
/// starting again. The draft stays after a guess, because the next guess is
/// usually this one with a peg or two moved.
///
/// Other players appear only as counts — "4 of 10", cracked or not — which
/// is all the host ever sends about them. The code itself arrives only when
/// the race is over.
struct CodeBreakerView: View {
    let context: OfflineGameContext<CodeBreakerRules>
    /// The guess being built: one entry per slot, nil while empty.
    @State private var draft: [Int?] = Array(repeating: nil, count: CodeBreakerRules.codeLength)
    /// The slot the picker fills next.
    @State private var cursor = 0
    /// A guess has gone to the host and its mark has not come back yet, so a
    /// double tap sends once. A new mark or a refusal clears it.
    @State private var waiting = false
    /// The page's content width, for sizing pegs.
    @State private var width: CGFloat = 335

    private var view: CodeBreakerRules.PlayerView { context.view }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SRPageHeader(kicker: kicker, title: title, strap: strap)
                    .accessibilityIdentifier("offline-code-breaker-header")
                clockBar
                if view.phase != .playing, let secret = view.secret { secretCard(secret) }
                if seated { guessesCard }
                if canGuess { composer }
                playersCard
            }
            // Measured INSIDE the page gutter: the width the cards actually
            // get (335 on a 375pt phone), not the screen's.
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { width = geo.size.width }
                        .onChange(of: geo.size.width) { _, new in width = new }
                }
            )
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .onChange(of: view.myGuesses.count) { _, _ in
            waiting = false
            cursor = 0
            if let last = view.myGuesses.last {
                if last.black == view.codeLength { SRHaptic.ok() } else { SRHaptic.tap() }
            }
        }
        .onChange(of: view.phase) { _, new in
            waiting = false
            if new != .playing { SRHaptic.select() }
        }
        .onChange(of: context.refusal) { _, new in
            if new != nil {
                SRHaptic.bad()
                waiting = false
            }
        }
        .task(id: waiting) {
            // A lost answer must not leave the picker locked: give up
            // waiting after a while.
            guard waiting else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { waiting = false }
        }
    }

    // MARK: - Who I am in this race

    private var myRow: CodeBreakerRules.Row? {
        view.rows.first { $0.id == context.me }
    }

    /// I hold a seat in this match (left or not).
    private var seated: Bool { myRow != nil }

    private var solved: Bool { myRow?.solved ?? false }

    private var outOfGuesses: Bool { myRow?.outOfGuesses ?? false }

    /// I may build and send a guess now.
    private var canGuess: Bool {
        view.phase == .playing && seated && !solved && !outOfGuesses
    }

    private var draftComplete: Bool { draft.allSatisfy { $0 != nil } }

    private func who(_ id: String) -> String {
        id == context.me ? "You" : context.name(of: id)
    }

    // MARK: - Words

    private var kicker: String {
        guard view.phase == .playing, seated, !solved, !outOfGuesses else { return "Code Breaker" }
        let next = min(view.myGuesses.count + 1, view.maxGuesses)
        return "Code Breaker · guess \(next) of \(view.maxGuesses)"
    }

    private var title: String {
        if view.phase != .playing {
            guard let winner = view.leaders.first else { return "Nobody cracked it" }
            return winner == context.me ? "You win" : "\(context.name(of: winner)) wins"
        }
        if !seated { return "Code Breaker" }
        if solved { return "Cracked it" }
        if outOfGuesses { return "Out of guesses" }
        return "Crack the code"
    }

    /// What to do now, in one sentence.
    private var strap: String {
        if view.phase != .playing {
            return "Fewest guesses wins; on a tie, the quicker crack. The table is next."
        }
        if !seated { return "You are watching. The code is shown when the race ends." }
        if solved {
            let used = view.myGuesses.count
            return (used == 1 ? "In 1 guess." : "In \(used) guesses.") + " Waiting for the others to finish."
        }
        if outOfGuesses { return "The code is shown when everyone has finished." }
        if waiting { return "Marking your guess…" }
        if draftComplete { return "Tap Guess to send it. Black: right colour, right place. White: right colour, wrong place." }
        return "Pick \(view.codeLength) pegs, then tap Guess. Colours can repeat."
    }

    // MARK: - The clock

    private var clockBar: some View {
        HStack(spacing: 10) {
            Image(systemName: view.phase == .playing ? "timer" : "hourglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SR.inkSecondary)
                .accessibilityHidden(true)
            Text(view.phase == .playing ? "Race ends in" : "Table in")
                .font(SR.Text.bodyMedium(15))
                .foregroundStyle(SR.ink)
                .lineLimit(1)
            Spacer(minLength: 6)
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let until = view.phase == .playing ? view.endsAt : view.revealUntil
                let left = context.clock.secondsLeft(until: until)
                Text(CodeBreakerRules.clock(left))
                    .font(SR.Text.display(22))
                    .foregroundStyle(view.phase == .playing && left <= 30 ? SR.error : SR.ink)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityLabel("\(left / 60) minutes \(left % 60) seconds")
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .frame(minHeight: SR.tapTarget)
        .padding(.vertical, 4)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("offline-code-breaker-clock")
    }

    // MARK: - Sizes

    /// Width inside a glass card.
    private var inner: CGFloat { max(200, width - 2 * SR.cardPadding) }

    /// The guess number column and the marks box beside each guess.
    private var numberWidth: CGFloat { 26 }
    private var marksSide: CGFloat { 40 }
    private var pegGap: CGFloat { 8 }

    /// A peg in a guess row: four of them, the number and the marks fit.
    private var rowPeg: CGFloat {
        let room = inner - numberWidth - marksSide - 20 - 3 * pegGap
        return max(24, min(44, room / CGFloat(view.codeLength)))
    }

    /// A peg in the composer's slots.
    private var slotPeg: CGFloat {
        max(32, min(56, (inner - 3 * pegGap) / CGFloat(view.codeLength)))
    }

    /// A colour in the picker: six to a row.
    private var pickerPeg: CGFloat {
        max(28, min(48, (inner - CGFloat(view.colours - 1) * pegGap) / CGFloat(view.colours)))
    }

    // MARK: - The code, once the race is over

    private func secretCard(_ secret: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "The code")
            HStack(spacing: pegGap) {
                ForEach(Array(secret.enumerated()), id: \.offset) { _, peg in
                    CodeBreakerPeg(peg: peg, size: slotPeg)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("The code was " + secret.map { CodeBreakerRules.pegName($0) }.joined(separator: ", "))
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("offline-code-breaker-secret")
    }

    // MARK: - My guesses

    private var guessesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SRSectionLabel(text: "Your guesses", trailing: "\(view.myGuesses.count) of \(view.maxGuesses)")
                .padding(.bottom, 8)
            if view.myGuesses.isEmpty {
                Text("No guesses yet. Your marks appear here — nobody else sees them.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
            }
            ForEach(Array(view.myGuesses.enumerated()), id: \.offset) { index, guess in
                if index > 0 { Divider().overlay(SR.divider) }
                guessRow(number: index + 1, guess: guess)
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("offline-code-breaker-guesses")
    }

    private func guessRow(number: Int, guess: CodeBreakerRules.Guess) -> some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(SR.Text.mono(13))
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: numberWidth, alignment: .leading)
            HStack(spacing: pegGap) {
                ForEach(Array(guess.pegs.enumerated()), id: \.offset) { _, peg in
                    CodeBreakerPeg(peg: peg, size: rowPeg)
                }
            }
            Spacer(minLength: 0)
            CodeBreakerMarks(black: guess.black, white: guess.white, slots: view.codeLength, side: marksSide)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(guessLabel(number: number, guess: guess))
        .accessibilityIdentifier("offline-code-breaker-guess-\(number)")
    }

    private func guessLabel(number: Int, guess: CodeBreakerRules.Guess) -> String {
        let pegs = guess.pegs.map { CodeBreakerRules.pegName($0) }.joined(separator: ", ")
        if guess.black == view.codeLength { return "Guess \(number): \(pegs). Cracked it." }
        return "Guess \(number): \(pegs). \(guess.black) black, \(guess.white) white."
    }

    // MARK: - Building a guess

    private var composer: some View {
        VStack(alignment: .leading, spacing: 14) {
            SRSectionLabel(text: "Next guess")
            HStack(spacing: pegGap) {
                ForEach(0..<view.codeLength, id: \.self) { slot in
                    Button {
                        SRHaptic.select()
                        cursor = slot
                    } label: {
                        CodeBreakerPeg(peg: slot < draft.count ? draft[slot] : nil, size: slotPeg,
                                       highlighted: slot == cursor)
                    }
                    .buttonStyle(.plain)
                    .disabled(waiting)
                    .accessibilityLabel(slotLabel(slot))
                    .accessibilityHint("Selects this slot for the next colour.")
                    .accessibilityAddTraits(slot == cursor ? AccessibilityTraits.isSelected : AccessibilityTraits())
                    .accessibilityIdentifier("offline-code-breaker-slot-\(slot + 1)")
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: pegGap) {
                ForEach(0..<view.colours, id: \.self) { peg in
                    Button {
                        fill(peg)
                    } label: {
                        CodeBreakerPeg(peg: peg, size: pickerPeg)
                    }
                    .buttonStyle(.plain)
                    .disabled(waiting)
                    .accessibilityLabel(CodeBreakerRules.pegName(peg))
                    .accessibilityHint("Puts this colour in slot \(cursor + 1).")
                    .accessibilityIdentifier("offline-code-breaker-colour-\(peg)")
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                Button {
                    send()
                } label: {
                    SRButtonLabel(title: "Guess", icon: "lock.open", fill: true)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .disabled(!draftComplete || waiting)
                .accessibilityIdentifier("offline-code-breaker-submit")
                .accessibilityLabel("Send this guess")

                Button {
                    SRHaptic.select()
                    draft = Array(repeating: nil, count: view.codeLength)
                    cursor = 0
                } label: {
                    SRButtonLabel(title: "Clear", fill: true)
                }
                .srButton(.regular)
                .controlSize(.large)
                .disabled(draft.allSatisfy { $0 == nil } || waiting)
                .accessibilityIdentifier("offline-code-breaker-clear")
                .accessibilityLabel("Clear the guess")
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("offline-code-breaker-composer")
    }

    private func slotLabel(_ slot: Int) -> String {
        let peg = slot < draft.count ? draft[slot] : nil
        return "Slot \(slot + 1), " + (peg.map { CodeBreakerRules.pegName($0) } ?? "empty")
    }

    // MARK: - Everyone

    private var playersCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SRSectionLabel(text: "The race")
                .padding(.bottom, 6)
            ForEach(Array(view.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { Divider().overlay(SR.divider) }
                HStack(spacing: 10) {
                    OfflineInitial(name: row.name, size: 28, tone: OfflineSeatColour.of(index))
                    Text(row.id == context.me ? "You" : row.name)
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(row.away ? SR.inkMuted : SR.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if view.leaders.first == row.id {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SR.accent)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 6)
                    Text(status(row))
                        .font(SR.Text.mono(13))
                        .foregroundStyle(row.solved ? SR.accent : SR.inkSecondary)
                        .lineLimit(1)
                        .fixedSize()
                    Image(systemName: icon(row))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(row.solved ? SR.accent : SR.inkMuted)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 40)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(rowLabel(row))
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("offline-code-breaker-players")
    }

    /// "4/10", "1:23", "left".
    private func status(_ row: CodeBreakerRules.Row) -> String {
        if row.away && !row.solved { return "left · \(row.used)/\(view.maxGuesses)" }
        if let seconds = row.seconds { return "\(row.used)/\(view.maxGuesses) · \(CodeBreakerRules.clock(seconds))" }
        return "\(row.used)/\(view.maxGuesses)"
    }

    private func icon(_ row: CodeBreakerRules.Row) -> String {
        if row.solved { return "lock.open.fill" }
        if row.away { return "wifi.slash" }
        if row.outOfGuesses { return "xmark" }
        return "lock.fill"
    }

    private func rowLabel(_ row: CodeBreakerRules.Row) -> String {
        var parts = [row.id == context.me ? "You" : row.name]
        parts.append(row.used == 1 ? "1 guess used" : "\(row.used) guesses used")
        if row.solved { parts.append("cracked it") }
        if let seconds = row.seconds { parts.append("in \(seconds / 60) minutes \(seconds % 60) seconds") }
        if row.outOfGuesses { parts.append("out of guesses") }
        if row.away { parts.append("left the game") }
        if view.leaders.first == row.id { parts.append("winner") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Acting

    /// Put `peg` in the highlighted slot and move to the next empty slot
    /// (or the next slot along, once all are full).
    private func fill(_ peg: Int) {
        guard canGuess, !waiting else { return }
        if draft.count != view.codeLength { draft = Array(repeating: nil, count: view.codeLength) }
        let slot = min(max(cursor, 0), view.codeLength - 1)
        SRHaptic.select()
        draft[slot] = peg
        let order = Array(slot + 1..<view.codeLength) + Array(0..<slot)
        if let empty = order.first(where: { draft[$0] == nil }) {
            cursor = empty
        } else {
            cursor = (slot + 1) % view.codeLength
        }
    }

    private func send() {
        guard canGuess, !waiting, draftComplete else { return }
        let pegs = draft.compactMap { $0 }
        guard pegs.count == view.codeLength else { return }
        SRHaptic.tap()
        waiting = true
        context.send(.guess(number: view.myGuesses.count + 1, pegs: pegs))
    }
}

/// One peg: its colour, with its own shape on top so it reads without
/// colour. An empty peg is a dashed ring; the highlighted one (the slot the
/// picker fills next) gets an accent ring.
struct CodeBreakerPeg: View {
    let peg: Int?
    let size: CGFloat
    var highlighted: Bool = false

    var body: some View {
        ZStack {
            if let peg, peg >= 0, peg < CodeBreakerRules.colours {
                Circle()
                    .fill(CodeBreakerPeg.colour(peg))
                Image(systemName: CodeBreakerRules.symbols[peg])
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(CodeBreakerPeg.symbolTone(peg))
            } else {
                Circle()
                    .strokeBorder(SR.inkGhost, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
            }
            if highlighted {
                Circle()
                    .strokeBorder(SR.accent, lineWidth: 3)
                    .padding(-4)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
    }

    /// The six peg colours, chosen to differ in lightness as well as hue.
    static func colour(_ peg: Int) -> Color {
        switch peg {
        case 0: return Color(red: 0.84, green: 0.13, blue: 0.13)
        case 1: return Color(red: 0.95, green: 0.52, blue: 0.05)
        case 2: return Color(red: 0.98, green: 0.82, blue: 0.16)
        case 3: return Color(red: 0.11, green: 0.56, blue: 0.24)
        case 4: return Color(red: 0.10, green: 0.36, blue: 0.85)
        default: return Color(red: 0.48, green: 0.24, blue: 0.77)
        }
    }

    /// Dark shapes on the light pegs, white on the rest.
    static func symbolTone(_ peg: Int) -> Color {
        peg == 1 || peg == 2 ? Color.black.opacity(0.7) : Color.white
    }
}

/// A guess's marks as a small square of dots: filled for black (right
/// place), ringed for white (wrong place), faint for nothing.
struct CodeBreakerMarks: View {
    let black: Int
    let white: Int
    let slots: Int
    let side: CGFloat

    var body: some View {
        let columns = 2
        let rows = (slots + columns - 1) / columns
        let dot = side / CGFloat(max(columns, rows)) * 0.62
        VStack(spacing: dot * 0.45) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: dot * 0.45) {
                    ForEach(0..<columns, id: \.self) { column in
                        mark(row * columns + column, dot: dot)
                    }
                }
            }
        }
        .frame(width: side, height: side)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(black) black, \(white) white")
    }

    @ViewBuilder
    private func mark(_ index: Int, dot: CGFloat) -> some View {
        if index >= slots {
            Color.clear.frame(width: dot, height: dot)
        } else if index < black {
            Circle().fill(SR.ink).frame(width: dot, height: dot)
        } else if index < black + white {
            Circle().strokeBorder(SR.ink, lineWidth: 1.5).frame(width: dot, height: dot)
        } else {
            Circle().fill(SR.inkGhost.opacity(0.5)).frame(width: dot, height: dot)
        }
    }
}
