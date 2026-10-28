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
                if let line = statusLine {
                    Text(line)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("offline-chess-status")
                }
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
            if view.toMove == context.me { SRHaptic.tap() }
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
        .confirmationDialog(
            "The pawn becomes…",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible
        ) {
            ForEach(OfflineChessRules.Promotion.allCases, id: \.self) { choice in
                Button("\(Self.kind(choice).glyph) \(Self.kind(choice).name)") { promote(choice) }
            }
            Button("Cancel", role: .cancel) { pending = nil }
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

    // MARK: - A side of the table

    /// One side: who plays it, whose move it is, and what it has taken.
    private func side(_ colour: ChessColour) -> some View {
        let id = player(colour)
        let taken = (colour == .white ? view.takenByWhite : view.takenByBlack).compactMap(Self.piece)
        let tally = ChessRules.tallyOrder.compactMap { kind -> ChessTally? in
            let count = taken.filter { $0 == kind }.count
            return count > 0 ? ChessTally(kind: kind, count: count) : nil
        }
        let moving = view.toMove == id
        return HStack(spacing: 10) {
            OfflineInitial(name: context.name(of: id), size: 28, tone: colour.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(who(id))
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(moving ? "\(colour.tintName) · to move" : colour.tintName)
                    .font(SR.Text.label())
                    .foregroundStyle(moving ? colour.tint : SR.inkMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if !tally.isEmpty {
                HStack(spacing: 6) {
                    ForEach(tally, id: \.kind) { item in
                        Text(ChessRules.tallyText(item.kind, item.count))
                            .font(.system(size: 17))
                            .foregroundStyle(colour.other.tint)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
            if view.winner == id {
                Image(systemName: "crown.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SR.accent)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .frame(minHeight: SR.tapTarget)
        .padding(.vertical, 2)
        .srGlassCard(.paper)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(who(id)), \(colour.tintName)\(moving ? ", to move" : ""), took \(ChessRules.tallySpoken(tally))")
        .accessibilityIdentifier("offline-chess-side-\(colour.rawValue)")
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
            .accessibilityIdentifier("offline-chess-level")
        }
    }

    @ViewBuilder
    private var actions: some View {
        if let offer = view.drawOfferBy, offer != context.me {
            HStack(spacing: 10) {
                Button {
                    SRHaptic.tap()
                    context.send(.offerDraw)
                } label: {
                    SRButtonLabel(title: "Accept", icon: "hand.raised.fill", fill: true)
                }
                .srButton(.prominent)
                .controlSize(.large)
                .accessibilityLabel("Accept the draw")
                .accessibilityIdentifier("offline-chess-accept-draw")
                Button {
                    SRHaptic.select()
                    context.send(.declineDraw)
                } label: {
                    SRButtonLabel(title: "Decline", fill: true)
                }
                .srButton(.regular)
                .controlSize(.large)
                .accessibilityLabel("Decline the draw")
                .accessibilityIdentifier("offline-chess-decline-draw")
            }
        } else {
            HStack(spacing: 10) {
                Button {
                    SRHaptic.tap()
                    context.send(.offerDraw)
                } label: {
                    SRButtonLabel(title: "Offer draw", icon: "hand.raised.fill", fill: true)
                }
                .srButton(.regular)
                .controlSize(.large)
                .disabled(view.drawOfferBy == context.me)
                .accessibilityIdentifier("offline-chess-offer-draw")
                Button {
                    SRHaptic.select()
                    confirmingResign = true
                } label: {
                    SRButtonLabel(title: "Resign", icon: "flag.fill", fill: true)
                }
                .srButton(.regular)
                .controlSize(.large)
                .accessibilityIdentifier("offline-chess-resign")
            }
        }
    }

    private var moveList: some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Moves", trailing: view.moves.count == 1 ? "1 move" : "\(view.moves.count) moves")
            Text(ChessRules.moveList(view.moves))
                .font(SR.Text.mono(13))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SR.cardPadding)
                .srGlassCard(.paper)
                .accessibilityIdentifier("offline-chess-moves")
        }
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
