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
///
/// It looks like the board game: a wooden board with glossy pegs in sunk
/// holes and the little black and white key pegs beside each guess, which
/// pop in one at a time when a guess comes back marked. The picker is two
/// rows of three big pegs, a thumb wide each. Cracking the code stamps it;
/// the race clock drains a bar and turns red in the last half minute.
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
            VStack(alignment: .leading, spacing: 18) {
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
        let playingNow = view.phase == .playing
        let until = playingNow ? view.endsAt : view.revealUntil
        let total = playingNow ? CodeBreakerRules.raceSeconds : CodeBreakerRules.revealPause
        let clock = context.clock
        return HStack(spacing: 12) {
            Image(systemName: playingNow ? "timer" : "hourglass")
                .font(SR.Text.title(17))
                .foregroundStyle(SR.accent)
                .frame(width: 40, height: 40)
                .background(Circle().fill(SR.accent.opacity(0.14)))
                .accessibilityHidden(true)
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let left = clock.secondsLeft(until: until)
                let fraction = PlayTableMath.drainFraction(secondsLeft: until - clock.now(), total: total)
                let late = playingNow && left <= 30
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(playingNow ? "Race ends in" : "Table in")
                            .font(SR.Text.bodyMedium(15))
                            .foregroundStyle(SR.ink)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(CodeBreakerRules.clock(left))
                            .font(SR.Text.display(24))
                            .monospacedDigit()
                            .foregroundStyle(late ? SR.error : SR.ink)
                            .lineLimit(1)
                            .fixedSize()
                            .scaleEffect(late && left > 0 && left <= 10 ? 1.08 : 1)
                            .accessibilityLabel("\(left / 60) minutes \(left % 60) seconds")
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(SR.inkGhost.opacity(0.25))
                            Capsule()
                                .fill(late ? SR.error : SR.accent)
                                .frame(width: max(6, geo.size.width * CGFloat(fraction)))
                        }
                    }
                    .frame(height: 6)
                    .srAnimation(.linear(duration: 0.25), value: fraction)
                    .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("offline-code-breaker-clock")
    }

    // MARK: - Sizes

    /// Width inside a board.
    private var inner: CGFloat { max(200, width - 2 * SR.cardPadding) }

    /// The guess number column and the marks box beside each guess.
    private var numberWidth: CGFloat { 26 }
    private var marksSide: CGFloat { 42 }
    private var pegGap: CGFloat { 10 }

    /// A peg in a guess row: four of them, the number and the marks fit.
    private var rowPeg: CGFloat {
        let room = inner - numberWidth - marksSide - 24 - 3 * pegGap
        return max(26, min(46, room / CGFloat(view.codeLength)))
    }

    /// A peg in the composer's slots.
    private var slotPeg: CGFloat {
        max(40, min(64, (inner - 3 * 14) / CGFloat(view.codeLength)))
    }

    /// A colour in the picker: two rows of three, each a thumb wide.
    private var pickerPeg: CGFloat {
        max(52, min(68, (inner - 2 * 18) / 3))
    }

    // MARK: - The code, once the race is over

    private func secretCard(_ secret: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CodeBreakerBoardLabel(text: "The code")
                Spacer(minLength: 6)
                Image(systemName: view.leaders.isEmpty ? "lock.fill" : "lock.open.fill")
                    .font(SR.Text.title(18))
                    .foregroundStyle(CodeBreakerPaint.ink)
                    .accessibilityHidden(true)
            }
            HStack(spacing: 14) {
                ForEach(Array(secret.enumerated()), id: \.offset) { index, peg in
                    CodeBreakerPeg(peg: peg, size: slotPeg)
                        .modifier(CodeBreakerPopIn(delay: PlayTableMath.stagger(index: index, step: 0.12, cap: 0.6)))
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("The code was " + secret.map { CodeBreakerRules.pegName($0) }.joined(separator: ", "))
            if solved {
                PlayTableStamp(text: "Cracked", tone: Color(hex: 0x1D6B3A), size: 22)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
        }
        .padding(SR.cardPadding)
        .modifier(CodeBreakerBoardSurface())
        .accessibilityIdentifier("offline-code-breaker-secret")
    }

    // MARK: - My guesses

    private var guessesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                CodeBreakerBoardLabel(text: "Your guesses")
                Spacer(minLength: 6)
                Text("\(view.myGuesses.count) of \(view.maxGuesses)")
                    .font(SR.Text.mono())
                    .foregroundStyle(CodeBreakerPaint.ink)
            }
            .padding(.bottom, 8)
            if view.myGuesses.isEmpty {
                Text("No guesses yet. Your marks appear here — nobody else sees them.")
                    .font(SR.Text.secondary())
                    .foregroundStyle(CodeBreakerPaint.ink.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
            }
            ForEach(Array(view.myGuesses.enumerated()), id: \.offset) { index, guess in
                if index > 0 {
                    Rectangle().fill(CodeBreakerPaint.groove).frame(height: 1)
                }
                guessRow(number: index + 1, guess: guess)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if canGuess { guessesLeft }
        }
        .srAnimation(.spring(response: 0.4, dampingFraction: 0.8), value: view.myGuesses.count)
        .padding(SR.cardPadding)
        .modifier(CodeBreakerBoardSurface())
        .accessibilityIdentifier("offline-code-breaker-guesses")
    }

    /// The holes still empty, as a row of small pips: how many tries are left.
    private var guessesLeft: some View {
        let left = max(0, view.maxGuesses - view.myGuesses.count)
        return HStack(spacing: 6) {
            ForEach(0..<left, id: \.self) { _ in
                Circle()
                    .fill(CodeBreakerPaint.hole)
                    .frame(width: 10, height: 10)
            }
            Spacer(minLength: 6)
            Text(left == 1 ? "1 guess left" : "\(left) guesses left")
                .font(SR.Text.mono())
                .foregroundStyle(left <= 2 ? Color(hex: 0x9E1B1B) : CodeBreakerPaint.ink)
        }
        .padding(.top, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(left == 1 ? "1 guess left" : "\(left) guesses left")
    }

    private func guessRow(number: Int, guess: CodeBreakerRules.Guess) -> some View {
        let newest = number == view.myGuesses.count
        return HStack(spacing: 12) {
            Text("\(number)")
                .font(SR.Text.mono(13))
                .foregroundStyle(CodeBreakerPaint.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: numberWidth, alignment: .leading)
            HStack(spacing: pegGap) {
                ForEach(Array(guess.pegs.enumerated()), id: \.offset) { _, peg in
                    CodeBreakerPeg(peg: peg, size: rowPeg)
                }
            }
            Spacer(minLength: 0)
            CodeBreakerMarks(black: guess.black, white: guess.white, slots: view.codeLength, side: marksSide,
                             reveal: newest)
        }
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(guess.black == view.codeLength ? Color(hex: 0x2E9A54).opacity(0.25) : Color.clear)
        )
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
        VStack(alignment: .leading, spacing: 16) {
            CodeBreakerBoardLabel(text: "Next guess")
            slots
            picker
            HStack(spacing: 10) {
                PlayTableButton(title: "Guess", icon: "lock.open", haptic: .none) {
                    send()
                }
                .disabled(!draftComplete || waiting)
                .accessibilityIdentifier("offline-code-breaker-submit")
                .accessibilityLabel("Send this guess")

                PlayTableButton(title: "Clear", weight: .regular, haptic: .select) {
                    draft = Array(repeating: nil, count: view.codeLength)
                    cursor = 0
                }
                .disabled(draft.allSatisfy { $0 == nil } || waiting)
                .accessibilityIdentifier("offline-code-breaker-clear")
                .accessibilityLabel("Clear the guess")
            }
        }
        .padding(SR.cardPadding)
        .modifier(CodeBreakerBoardSurface())
        .accessibilityIdentifier("offline-code-breaker-composer")
    }

    private var slots: some View {
        HStack(spacing: 14) {
            ForEach(0..<view.codeLength, id: \.self) { slot in
                Button {
                    SRHaptic.select()
                    cursor = slot
                } label: {
                    CodeBreakerPeg(peg: slot < draft.count ? draft[slot] : nil, size: slotPeg,
                                   highlighted: slot == cursor)
                }
                .buttonStyle(SRPressStyle())
                .disabled(waiting)
                .accessibilityLabel(slotLabel(slot))
                .accessibilityHint("Selects this slot for the next colour.")
                .accessibilityAddTraits(slot == cursor ? AccessibilityTraits.isSelected : AccessibilityTraits())
                .accessibilityIdentifier("offline-code-breaker-slot-\(slot + 1)")
            }
        }
        .frame(maxWidth: .infinity)
        .srAnimation(.spring(response: 0.25, dampingFraction: 0.6), value: draft)
        .srAnimation(.snappy(duration: 0.18), value: cursor)
    }

    /// The six colours as two rows of three big pegs.
    private var picker: some View {
        let columns = 3
        let rows = (view.colours + columns - 1) / columns
        return VStack(spacing: 14) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 18) {
                    ForEach(0..<columns, id: \.self) { column in
                        pickerButton(row * columns + column)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func pickerButton(_ peg: Int) -> some View {
        if peg < view.colours {
            Button {
                fill(peg)
            } label: {
                CodeBreakerPeg(peg: peg, size: pickerPeg)
            }
            .buttonStyle(SRPressStyle())
            .disabled(waiting)
            .accessibilityLabel(CodeBreakerRules.pegName(peg))
            .accessibilityHint("Puts this colour in slot \(cursor + 1).")
            .accessibilityIdentifier("offline-code-breaker-colour-\(peg)")
        } else {
            Color.clear.frame(width: pickerPeg, height: pickerPeg)
        }
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
                raceRow(row, index: index)
            }
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .accessibilityIdentifier("offline-code-breaker-players")
    }

    private func raceRow(_ row: CodeBreakerRules.Row, index: Int) -> some View {
        let tone = OfflineSeatColour.of(index)
        let fraction = CGFloat(min(row.used, view.maxGuesses)) / CGFloat(max(view.maxGuesses, 1))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                OfflineInitial(name: row.name, size: 32, tone: tone)
                Text(row.id == context.me ? "You" : row.name)
                    .font(SR.Text.bodyMedium(16))
                    .foregroundStyle(row.away ? SR.inkMuted : SR.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if view.leaders.first == row.id {
                    Image(systemName: "crown.fill")
                        .font(SR.Text.label(13))
                        .foregroundStyle(Color(hex: 0xE0A21C))
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 6)
                Text(status(row))
                    .font(SR.Text.mono(13))
                    .foregroundStyle(row.solved ? SR.good : SR.inkSecondary)
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: icon(row))
                    .font(SR.Text.label(14))
                    .foregroundStyle(row.solved ? SR.good : SR.inkMuted)
                    .frame(width: 20)
                    .accessibilityHidden(true)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SR.inkGhost.opacity(0.22))
                    Capsule()
                        .fill(row.solved ? SR.good : tone)
                        .frame(width: max(6, geo.size.width * fraction))
                        .opacity(row.used == 0 ? 0 : 1)
                }
            }
            .frame(height: 6)
            .padding(.leading, 42)
            .srAnimation(.spring(response: 0.4, dampingFraction: 0.8), value: row.used)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
        .frame(minHeight: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowLabel(row))
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

/// The board's colours: wood and its grooves, the same in both appearances.
enum CodeBreakerPaint {
    static let woodLight = Color(hex: 0xE2B97F)
    static let woodDeep = Color(hex: 0xBE8C4E)
    static let groove = Color(hex: 0x8A5F2E).opacity(0.45)
    static let hole = Color(hex: 0x6E4A22)
    static let ink = Color(hex: 0x3B2410)
}

/// A wooden board under a stretch of the game.
struct CodeBreakerBoardSurface: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
        return content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                shape.fill(LinearGradient(colors: [CodeBreakerPaint.woodLight, CodeBreakerPaint.woodDeep],
                                          startPoint: .top, endPoint: .bottom))
                    .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            )
            .overlay(shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
    }
}

/// A small-caps heading burnt into the board.
struct CodeBreakerBoardLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(SR.Text.label())
            .tracking(1.3)
            .foregroundStyle(CodeBreakerPaint.ink)
            .lineLimit(1)
    }
}

/// One peg: its colour, lit like a glossy plastic peg, with its own shape on
/// top so it reads without colour. An empty peg is a hole sunk in the board;
/// the highlighted one (the slot the picker fills next) gets an accent ring.
struct CodeBreakerPeg: View {
    let peg: Int?
    let size: CGFloat
    var highlighted: Bool = false

    var body: some View {
        ZStack {
            if let peg, peg >= 0, peg < CodeBreakerRules.colours {
                Circle()
                    .fill(CodeBreakerPeg.colour(peg))
                Circle()
                    .fill(RadialGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0)],
                                         center: UnitPoint(x: 0.32, y: 0.26), startRadius: 0, endRadius: size * 0.6))
                Circle()
                    .strokeBorder(Color.black.opacity(0.22), lineWidth: max(1, size * 0.04))
                Image(systemName: CodeBreakerRules.symbols[peg])
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(CodeBreakerPeg.symbolTone(peg))
                    .transition(.scale.combined(with: .opacity))
            } else {
                Circle()
                    .fill(CodeBreakerPaint.hole)
                Circle()
                    .fill(LinearGradient(colors: [Color.black.opacity(0.35), Color.black.opacity(0)],
                                         startPoint: .top, endPoint: .center))
                    .padding(size * 0.06)
                Circle()
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
            }
            if highlighted {
                Circle()
                    .strokeBorder(SR.accent, lineWidth: 3.5)
                    .padding(-5)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(peg == nil ? 0 : 0.28), radius: size * 0.06, x: 0, y: size * 0.05)
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

/// A guess's marks as a small square of key pegs: black for right place,
/// white for wrong place, an empty hole for nothing. The newest guess's
/// pegs pop in one at a time.
struct CodeBreakerMarks: View {
    let black: Int
    let white: Int
    let slots: Int
    let side: CGFloat
    /// Pop the pegs in, staggered (the guess just came back).
    var reveal: Bool = false

    var body: some View {
        let columns = 2
        let rows = (slots + columns - 1) / columns
        let dot = side / CGFloat(max(columns, rows)) * 0.62
        return VStack(spacing: dot * 0.45) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: dot * 0.45) {
                    ForEach(0..<columns, id: \.self) { column in
                        mark(row * columns + column, dot: dot)
                    }
                }
            }
        }
        .frame(width: side, height: side)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.12))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(black) black, \(white) white")
    }

    @ViewBuilder
    private func mark(_ index: Int, dot: CGFloat) -> some View {
        let delay = reveal ? PlayTableMath.stagger(index: index, step: 0.12, cap: 0.6) : 0
        if index >= slots {
            Color.clear.frame(width: dot, height: dot)
        } else if index < black {
            Circle()
                .fill(Color(hex: 0x15131C))
                .overlay(Circle().fill(Color.white.opacity(0.25)).padding(dot * 0.25).offset(x: -dot * 0.12, y: -dot * 0.12))
                .frame(width: dot, height: dot)
                .modifier(CodeBreakerPopIn(delay: delay, active: reveal))
        } else if index < black + white {
            Circle()
                .fill(Color.white)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1))
                .frame(width: dot, height: dot)
                .modifier(CodeBreakerPopIn(delay: delay, active: reveal))
        } else {
            Circle()
                .fill(CodeBreakerPaint.hole.opacity(0.7))
                .frame(width: dot * 0.7, height: dot * 0.7)
                .frame(width: dot, height: dot)
        }
    }
}

/// Pops a piece in after `delay`, once, when it first appears. Off under
/// Reduce Motion, or when `active` is false.
struct CodeBreakerPopIn: ViewModifier {
    let delay: Double
    var active: Bool = true
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let up = shown || reduceMotion || !active
        return content
            .scaleEffect(up ? 1 : 0.2)
            .opacity(up ? 1 : 0)
            .onAppear {
                guard active, !reduceMotion, !shown else { return }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.55).delay(delay)) { shown = true }
            }
    }
}
