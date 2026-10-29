import SwiftUI

/// Chess on one phone: whose move, the board, the two sides with what each
/// has taken, the computer's level, draw and resign, and the moves so far.
///
/// The board is the online game's own `ChessBoardView` — the same blue and
/// red pieces, the same lit squares and check square — fed from the host's
/// FEN, so a game played offline looks like one played on the site. A tap
/// on one of my pieces lifts it and lights where it may go (the host sends
/// the side to move its legal moves); a tap on a lit square sends the move,
/// asking first what a pawn reaching the last rank becomes. A tap on the
/// lifted piece puts it down.
///
/// Against the phone, a segmented control sets how hard it plays; the
/// computer answers a draw offer by itself, accepting only when it is
/// behind.
///
/// Around the board: a turn strip in the colour of the side to move (with a
/// "thinking" pulse while the computer plays), a plate for each side with
/// what it has taken and who is ahead on material ("+3"), a red CHECK badge
/// that pulses with a warning tap when my king is attacked, a promotion card
/// of four big pieces, the moves as numbered pairs with the newest lit, and a
/// stamped result when the game ends.
struct OfflineChessView: View {
    let context: OfflineGameContext<OfflineChessRules>
    /// The square of the piece I have lifted.
    @State private var selected: Int?
    /// A pawn move waiting for its promotion choice.
    @State private var pending: Pending?
    /// A move has gone to the host and its answer has not come back yet.
    @State private var waiting = false
    @State private var confirmingResign = false

    private struct Pending: Equatable {
        let from: Int
        let to: Int
    }

    private var view: OfflineChessRules.PlayerView { context.view }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SRPageHeader(kicker: kicker, title: title, strap: strap)
                if view.phase == .playing { turnStrip }
                side(bottom.other)
                ChessBoardView(
                    board: board,
                    bottom: bottom,
                    selected: selected.map(Self.square),
                    targets: targetNames,
                    lastMove: view.lastMove.map {
                        ChessLastMove(from: OfflineChessRules.squareName($0.from), to: OfflineChessRules.squareName($0.to))
                    },
                    checked: view.check ? board.king(view.whiteToMove ? .white : .black) : nil,
                    turn: view.phase == .playing ? (view.whiteToMove ? .white : .black) : nil,
                    interactive: canMove,
                    onTap: { tap($0) }
                )
                .padding(.horizontal, 2)
                side(bottom)
                if pending != nil { promotionCard }
                if let line = statusLine {
                    Text(line)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("offline-chess-status")
                }
                if view.phase != .playing, view.ending != nil { resultCard }
                if seated && view.phase == .playing {
                    if againstComputer { levelPicker }
                    actions
                }
                if !view.moves.isEmpty { moveList }
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .accessibilityIdentifier("offline-chess")
        .onChange(of: view) { _, _ in waiting = false }
        .onChange(of: view.ply) { _, _ in
            selected = nil
            pending = nil
            if view.toMove == context.me {
                if view.check { SRHaptic.bad() } else { SRHaptic.tap() }
            }
        }
        .onChange(of: view.phase) { _, new in
            guard new == .done else { return }
            if view.winner == context.me { SRHaptic.ok() } else if view.winner != nil { SRHaptic.bad() }
        }
        .onChange(of: context.refusal) { _, new in
            if new != nil {
                SRHaptic.bad()
                waiting = false
            }
        }
        .task(id: waiting) {
            // A lost answer must not leave the board locked.
            guard waiting else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { waiting = false }
        }
        .confirmationDialog("Resign this game?", isPresented: $confirmingResign, titleVisibility: .visible) {
            Button("Resign", role: .destructive) { context.send(.resign) }
            Button("Keep playing", role: .cancel) {}
        } message: {
            Text("\(opponentName) wins it.")
        }
    }

    // MARK: - Who is who

    private var board: ChessBoard { ChessBoard(fen: view.fen) }

    private var myColour: ChessColour? {
        if context.me == view.white { return .white }
        if context.me == view.black { return .black }
        return nil
    }

    private var seated: Bool { myColour != nil }

    /// The colour nearest me: mine, or Blue when watching.
    private var bottom: ChessColour { myColour ?? .white }

    private func player(_ colour: ChessColour) -> String { colour == .white ? view.white : view.black }

    private func who(_ id: String) -> String { id == context.me ? "You" : context.name(of: id) }

    private var opponent: String { myColour.map { player($0.other) } ?? view.black }

    private var opponentName: String { context.name(of: opponent) }

    /// Computer players sit as `bot-1`, `bot-2` (`OfflineRoom.addBot`).
    private var againstComputer: Bool { opponent.hasPrefix("bot-") }

    private var myTurn: Bool { view.phase == .playing && view.toMove == context.me }

    private var canMove: Bool { myTurn && !waiting && pending == nil }

    private var movingColour: ChessColour { view.whiteToMove ? .white : .black }

    // MARK: - Words

    private var kicker: String {
        var parts = ["Chess", "Move \(view.ply / 2 + 1)"]
        if againstComputer { parts.append("vs computer · \(view.level.title)") }
        return parts.joined(separator: " · ")
    }

    private var title: String {
        switch view.phase {
        case .playing:
            if myTurn { return view.check ? "Your move — check!" : "Your move" }
            guard let turn = view.toMove else { return "Chess" }
            if turn.hasPrefix("bot-") { return "\(context.name(of: turn)) is thinking…" }
            return "\(context.name(of: turn)) to move"
        case .done, .over:
            guard let ending = view.ending else { return "Game over" }
            if ending.isDraw { return "A draw" }
            guard let winner = view.winner else { return "Game over" }
            return winner == context.me ? "You win" : "\(context.name(of: winner)) wins"
        }
    }

    private var strap: String? {
        if let ending = view.ending {
            let loser = view.winner.map { $0 == view.white ? view.black : view.white }
            return ChessRules.outcomeLine(ending.rawValue, winner: view.winner.map(who), loser: loser.map(who))
        }
        guard let colour = myColour else { return "You are watching this game." }
        return "You play \(colour.tintName) (\(colour.name))."
    }

    private var statusLine: String? {
        guard view.phase == .playing else { return nil }
        if let offer = view.drawOfferBy {
            return offer == context.me ? "Draw offered — it stands until \(opponentName) moves." : "\(who(offer)) offers a draw."
        }
        guard myTurn else { return nil }
        return selected == nil ? "Tap a piece to pick it up." : "Tap a lit square, or the piece to put it down."
    }

    // MARK: - Pieces

    private static func square(_ index: Int) -> ChessSquare { ChessSquare(file: index % 8, rank: index / 8) }

    private static func kind(_ choice: OfflineChessRules.Promotion) -> ChessPieceKind {
        switch choice {
        case .queen: return .queen
        case .rook: return .rook
        case .bishop: return .bishop
        case .knight: return .knight
        }
    }

    private static func piece(_ raw: Int) -> ChessPieceKind? {
        switch raw {
        case OfflineChessRules.pawn: return .pawn
        case OfflineChessRules.knight: return .knight
        case OfflineChessRules.bishop: return .bishop
        case OfflineChessRules.rook: return .rook
        case OfflineChessRules.queen: return .queen
        default: return nil
        }
    }

    /// Lit squares for the lifted piece, by name.
    private var targetNames: Set<String> {
        guard let selected else { return [] }
        return Set(view.targets.filter { $0.from == selected }.map { OfflineChessRules.squareName($0.to) })
    }

    private func taken(by colour: ChessColour) -> [ChessPieceKind] {
        (colour == .white ? view.takenByWhite : view.takenByBlack).compactMap(Self.piece)
    }

    /// How far `colour` is ahead on material, from what each side has taken.
    private func lead(_ colour: ChessColour) -> Int {
        PlayTableMath.materialLead(taken: taken(by: colour).map(\.value), lost: taken(by: colour.other).map(\.value))
    }

    // MARK: - The turn

    private var turnStrip: some View {
        let colour = movingColour
        let id = player(colour)
        let bot = id.hasPrefix("bot-")
        let text: String
        if myTurn {
            text = view.check ? "Your move — you're in check" : "Your move"
        } else {
            text = bot ? "\(context.name(of: id)) is thinking" : "\(context.name(of: id)) to move"
        }
        return PlayTableTurnStrip(text: text, mine: myTurn, clock: context.clock, until: nil, total: 0, tone: colour.tint) {
            ZStack {
                Circle().fill(colour.tint.opacity(0.16))
                Image(systemName: bot && !myTurn ? "cpu" : "crown.fill")
                    .font(SR.Text.title(18))
                    .foregroundStyle(colour.tint)
                    .symbolEffect(.pulse, options: .repeating, isActive: bot && !myTurn)
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)
        }
        .accessibilityIdentifier("offline-chess-turn")
    }

    // MARK: - A side of the table

    /// One side: who plays it, whose move it is, what it has taken, and how
    /// far ahead it is.
    private func side(_ colour: ChessColour) -> some View {
        let id = player(colour)
        let pieces = taken(by: colour)
        let tally = ChessRules.tallyOrder.compactMap { kind -> ChessTally? in
            let count = pieces.filter { $0 == kind }.count
            return count > 0 ? ChessTally(kind: kind, count: count) : nil
        }
        let moving = view.phase == .playing && view.toMove == id
        let inCheck = moving && view.check
        let ahead = lead(colour)
        return HStack(spacing: 12) {
            OfflineInitial(name: context.name(of: id), size: 36, tone: colour.tint)
                .overlay(Circle().strokeBorder(moving ? colour.tint : Color.clear, lineWidth: 2.5).padding(-4))
            VStack(alignment: .leading, spacing: 2) {
                Text(who(id))
                    .font(SR.Text.bodyMedium(16))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(moving ? "\(colour.tintName) · to move" : colour.tintName)
                    .font(SR.Text.label())
                    .foregroundStyle(moving ? colour.tint : SR.inkMuted)
                    .lineLimit(1)
            }
            if inCheck { OfflineChessCheckBadge() }
            Spacer(minLength: 6)
            if !tally.isEmpty {
                HStack(spacing: 4) {
                    ForEach(tally, id: \.kind) { item in
                        Text(ChessRules.tallyText(item.kind, item.count))
                            .font(SR.Text.title(17))
                            .foregroundStyle(colour.other.tint)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
            if ahead > 0 {
                Text("+\(ahead)")
                    .font(SR.Text.label(13))
                    .monospacedDigit()
                    .foregroundStyle(SR.good)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(SR.good.opacity(0.14)))
                    .fixedSize()
            }
            if view.winner == id {
                Image(systemName: "crown.fill")
                    .font(SR.Text.title(16))
                    .foregroundStyle(Color(hex: 0xE0A21C))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .frame(minHeight: 60)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous)
                .fill(moving ? colour.tint.opacity(0.1) : Color.clear)
        )
        .srGlassCard(.paper)
        .srAnimation(.snappy(duration: 0.25), value: moving)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sideLabel(id: id, colour: colour, moving: moving, inCheck: inCheck, tally: tally, ahead: ahead))
        .accessibilityIdentifier("offline-chess-side-\(colour.rawValue)")
    }

    private func sideLabel(id: String, colour: ChessColour, moving: Bool, inCheck: Bool,
                           tally: [ChessTally], ahead: Int) -> String {
        var text = "\(who(id)), \(colour.tintName)\(moving ? ", to move" : ""), took \(ChessRules.tallySpoken(tally))"
        if inCheck { text += ", in check" }
        if ahead > 0 { text += ", \(ahead) ahead on material" }
        return text
    }

    // MARK: - Promotion

    /// The pawn's choice, as four big pieces to tap.
    private var promotionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SRSectionLabel(text: "The pawn becomes…")
            HStack(spacing: 10) {
                ForEach(OfflineChessRules.Promotion.allCases, id: \.self) { choice in
                    promotionButton(choice)
                }
            }
            PlayTableButton(title: "Cancel", weight: .regular, haptic: .select) {
                pending = nil
            }
            .accessibilityIdentifier("offline-chess-promotion-cancel")
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
        .transition(.scale(scale: 0.92).combined(with: .opacity))
        .accessibilityIdentifier("offline-chess-promotion")
    }

    private func promotionButton(_ choice: OfflineChessRules.Promotion) -> some View {
        let kind = Self.kind(choice)
        let tint = bottom.tint
        return Button {
            SRHaptic.ok()
            promote(choice)
        } label: {
            VStack(spacing: 2) {
                Text(kind.glyph)
                    .font(.system(size: 36))
                    .foregroundStyle(tint)
                Text(kind.name)
                    .font(SR.Text.label(12))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(tint.opacity(0.45), lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel(kind.name)
        .accessibilityIdentifier("offline-chess-promote-\(kind.rawValue)")
    }

    // MARK: - The end

    private var resultCard: some View {
        let draw = view.ending?.isDraw ?? false
        let won = view.winner == context.me
        let stampText: String
        let tone: Color
        if draw {
            stampText = "Draw"
            tone = SR.inkSecondary
        } else if view.ending == .checkmate {
            stampText = "Checkmate"
            tone = won ? SR.good : SR.error
        } else {
            stampText = won ? "You win" : "Game over"
            tone = won ? SR.good : SR.inkSecondary
        }
        return VStack(spacing: 10) {
            PlayTableStamp(text: stampText, tone: tone, size: 26)
            if let strap {
                Text(strap)
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("offline-chess-result")
    }

    // MARK: - Controls

    private var levelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SRSectionLabel(text: "\(opponentName) plays")
            Picker("Computer level", selection: Binding(
                get: { view.level },
                set: { level in
                    SRHaptic.select()
                    context.send(.level(level))
                }
            )) {
                ForEach(OfflineChessRules.Level.allCases, id: \.self) { level in
                    Text(level.title).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .accessibilityIdentifier("offline-chess-level")
        }
        .padding(SR.cardPadding)
        .srGlassCard(.paper)
    }

    @ViewBuilder
    private var actions: some View {
        if let offer = view.drawOfferBy, offer != context.me {
            HStack(spacing: 10) {
                PlayTableButton(title: "Accept", icon: "hand.raised.fill") {
                    context.send(.offerDraw)
                }
                .accessibilityLabel("Accept the draw")
                .accessibilityIdentifier("offline-chess-accept-draw")
                PlayTableButton(title: "Decline", weight: .regular, haptic: .select) {
                    context.send(.declineDraw)
                }
                .accessibilityLabel("Decline the draw")
                .accessibilityIdentifier("offline-chess-decline-draw")
            }
        } else {
            HStack(spacing: 10) {
                PlayTableButton(title: "Offer draw", icon: "hand.raised.fill", weight: .regular) {
                    context.send(.offerDraw)
                }
                .disabled(view.drawOfferBy == context.me)
                .accessibilityIdentifier("offline-chess-offer-draw")
                PlayTableButton(title: "Resign", icon: "flag.fill", weight: .regular, haptic: .select) {
                    confirmingResign = true
                }
                .accessibilityIdentifier("offline-chess-resign")
            }
        }
    }

    /// The moves as numbered pairs, the newest lit.
    private var moveList: some View {
        let pairs = stride(from: 0, to: view.moves.count, by: 2).map { start -> OfflineChessMovePair in
            OfflineChessMovePair(number: start / 2 + 1, white: view.moves[start],
                                 black: start + 1 < view.moves.count ? view.moves[start + 1] : nil)
        }
        let last = view.moves.count - 1
        return VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Moves", trailing: view.moves.count == 1 ? "1 move" : "\(view.moves.count) moves")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 6) {
                ForEach(pairs, id: \.number) { pair in
                    movePair(pair, last: last)
                }
            }
            .padding(SR.cardPadding)
            .srGlassCard(.paper)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ChessRules.moveList(view.moves))
            .accessibilityIdentifier("offline-chess-moves")
        }
    }

    private func movePair(_ pair: OfflineChessMovePair, last: Int) -> some View {
        let whiteIndex = (pair.number - 1) * 2
        return HStack(spacing: 6) {
            Text("\(pair.number).")
                .font(SR.Text.mono(12))
                .foregroundStyle(SR.inkMuted)
                .frame(minWidth: 26, alignment: .trailing)
            moveText(pair.white, lit: whiteIndex == last, tone: ChessColour.white.tint)
            if let black = pair.black {
                moveText(black, lit: whiteIndex + 1 == last, tone: ChessColour.black.tint)
            }
            Spacer(minLength: 0)
        }
    }

    private func moveText(_ san: String, lit: Bool, tone: Color) -> some View {
        // The newest move is lit in its side's colour as a tinted wash with
        // the colour as ink: white on the dark-mode tints would not read.
        Text(san)
            .font(SR.Text.mono(13))
            .foregroundStyle(lit ? tone : SR.ink)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(lit ? tone.opacity(0.16) : Color.clear))
            .overlay(Capsule().strokeBorder(lit ? tone : Color.clear, lineWidth: 1.5))
    }

    // MARK: - Acting

    private func tap(_ square: ChessSquare) {
        guard canMove else { return }
        let index = square.index
        if selected == index {
            SRHaptic.select()
            selected = nil
            return
        }
        if let from = selected, let target = view.targets.first(where: { $0.from == from && $0.to == index }) {
            if target.promotes {
                SRHaptic.select()
                pending = Pending(from: from, to: index)
            } else {
                send(from: from, to: index, promotion: nil)
            }
            return
        }
        if view.targets.contains(where: { $0.from == index }) {
            SRHaptic.select()
            selected = index
        } else {
            selected = nil
        }
    }

    private func promote(_ choice: OfflineChessRules.Promotion) {
        guard let move = pending else { return }
        pending = nil
        send(from: move.from, to: move.to, promotion: choice)
    }

    private func send(from: Int, to: Int, promotion: OfflineChessRules.Promotion?) {
        guard myTurn else { return }
        SRHaptic.tap()
        waiting = true
        selected = nil
        context.send(.move(ply: view.ply, from: from, to: to, promotion: promotion))
    }
}

/// One numbered pair of moves for the move list.
struct OfflineChessMovePair {
    let number: Int
    let white: String
    let black: String?
}

/// "CHECK", in red, with a short pulse when it appears.
struct OfflineChessCheckBadge: View {
    @State private var big = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("CHECK")
            .font(SR.Text.label(11))
            .tracking(1)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(SR.error))
            .scaleEffect(big ? 1.15 : 1)
            .fixedSize()
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) { big = true }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { big = false }
                }
            }
    }
}
