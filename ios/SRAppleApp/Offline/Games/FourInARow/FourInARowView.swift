import SwiftUI

/// Four in a Row on one phone: whose turn, the turn clock, the board and
/// who is playing which disc.
///
/// The board is sized from the width it is given, so the 9 × 7 board for
/// three or four players still fits a 375-point phone with spaces about 36
/// points across. A tap on a column picks it and shows a faint disc where
/// yours would land; Drop (or a second tap on the same column) sends it, so
/// a mis-tap costs nothing.
///
/// Each player's discs have their own colour AND their own marker (a dot, a
/// cross, a triangle, a square), so the board still reads for someone who
/// cannot tell the colours apart. VoiceOver reads the board column by
/// column, bottom up, and each column offers "Drop a disc here" as an action.
struct FourInARowView: View {
    let context: OfflineGameContext<FourInARowRules>
    /// The column picked but not yet dropped into.
    @State private var selected: Int?
    /// A drop has gone to the host and its answer has not come back yet, so
    /// a double tap sends once. Any new view clears it.
    @State private var waiting = false
    /// I have told the host my phone is back after being marked away.
    @State private var sentBack = false

    private var view: FourInARowRules.PlayerView { context.view }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SRPageHeader(kicker: kicker, title: title, strap: strap)
                if view.phase == .playing { turnBar }
                FourInARowBoard(
                    view: view,
                    mySeat: mySeat,
                    selected: canDrop ? selected : nil,
                    interactive: canDrop,
                    name: { who($0) },
                    onPick: { pick($0) },
                    onDrop: { drop($0) }
                )
                if canDrop { dropControls }
                if let line = lastMoveText {
                    Text(line)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("offline-four-in-a-row-last-move")
                }
                seatsCard
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .srGround(.warm)
        .onAppear { comeBackIfAway() }
        .onChange(of: view) { _, _ in
            waiting = false
            comeBackIfAway()
        }
        .onChange(of: view.turnNumber) { _, _ in
            selected = nil
            if view.turnPlayer == context.me, view.lastMove?.playerId != context.me { SRHaptic.tap() }
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
            // A lost answer must not leave the board locked: give up waiting
            // after a while.
            guard waiting else { return }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { waiting = false }
        }
    }

    // MARK: - Words

    /// My seat in this match, if I hold one.
    private var mySeat: Int? {
        view.seats.first { $0.id == context.me }?.seat
    }

    /// Whether I hold a seat in this match and am still here.
    private var playing: Bool {
        view.seats.contains { $0.id == context.me && !$0.away }
    }

    private var myTurn: Bool { view.phase == .playing && view.turnPlayer == context.me }

    /// I may pick and drop now.
    private var canDrop: Bool { myTurn && playing && !waiting }

    private func who(_ id: String) -> String {
        id == context.me ? "You" : context.name(of: id)
    }

    private var discsDropped: Int { view.grid.filter { $0 >= 0 }.count }

    private var kicker: String {
        "Four in a Row · \(view.cols) × \(view.rows) · \(discsDropped) of \(view.grid.count) spaces"
    }

    private var title: String {
        switch view.phase {
        case .playing:
            guard let turn = view.turnPlayer else { return "Four in a Row" }
            return turn == context.me ? "Your turn" : "\(context.name(of: turn))'s turn"
        case .done, .over:
            if view.ending == .draw { return "A draw" }
            guard let winner = view.winner else { return "Game over" }
            return winner == context.me ? "You win" : "\(context.name(of: winner)) wins"
        }
    }

    /// What to do now, in one sentence.
    private var strap: String? {
        guard view.phase == .playing else {
            switch view.ending {
            case .line?: return "Four in a row — the winning line is ringed."
            case .draw?: return "The board is full with no line of four."
            case .forfeit?: return "Everyone else left the game."
            case nil: return nil
            }
        }
        if !playing { return "You are watching this game." }
        guard myTurn else {
            return "Wait for your turn. Watch for anyone with three in a row."
        }
        if selected != nil { return "Tap Drop, or the same column again, to drop your disc." }
        return "Tap a column to pick it. Line up four of your discs to win."
    }

    private var lastMoveText: String? {
        guard let move = view.lastMove else { return nil }
        let name = who(move.playerId)
        let place = "column \(move.column + 1)"
        if move.timedOut {
            return move.playerId == context.me
                ? "Time ran out, so your disc was dropped in \(place)."
                : "Time ran out, so \(name)'s disc was dropped in \(place)."
        }
        return "\(name) dropped a disc in \(place)."
    }

    // MARK: - The turn

    private var turnBar: some View {
        HStack(spacing: 10) {
            if let turn = view.turnPlayer, let seat = view.seats.first(where: { $0.id == turn }) {
                FourInARowDisc(seat: seat.seat, size: 28)
                    .accessibilityHidden(true)
                Text(turn == context.me ? "Your disc" : "\(seat.name) is choosing")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 6)
            Image(systemName: "timer")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SR.inkSecondary)
                .accessibilityHidden(true)
            OfflineCountdown(clock: context.clock, until: view.turnEndsAt, font: SR.Text.display(22),
                             tone: myTurn ? SR.accent : SR.ink)
                .fixedSize()
        }
        .padding(.horizontal, SR.cardPadding)
        .frame(minHeight: SR.tapTarget)
        .padding(.vertical, 4)
        .srGlassCard(.paper)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("offline-four-in-a-row-turn")
    }

    private var dropControls: some View {
        HStack(spacing: 10) {
            Button {
                if let column = selected { drop(column) }
            } label: {
                SRButtonLabel(title: "Drop", icon: "arrow.down", fill: true)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .disabled(selected == nil)
            .accessibilityIdentifier("offline-four-in-a-row-drop")
            .accessibilityLabel(selected.map { "Drop a disc in column \($0 + 1)" } ?? "Drop")

            Button {
                SRHaptic.select()
                selected = nil
            } label: {
                SRButtonLabel(title: "Clear", fill: true)
            }
            .srButton(.regular)
            .controlSize(.large)
            .disabled(selected == nil)
            .accessibilityIdentifier("offline-four-in-a-row-clear")
            .accessibilityLabel("Clear the picked column")
        }
    }

    // MARK: - Who is playing which disc

    private var seatsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(view.seats.enumerated()), id: \.element.id) { index, seat in
                if index > 0 { Divider().overlay(SR.divider) }
                HStack(spacing: 10) {
                    FourInARowDisc(seat: seat.seat, size: 26)
                        .opacity(seat.away ? 0.45 : 1)
                    Text(seat.id == context.me ? "You" : seat.name)
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(seat.away ? SR.inkMuted : SR.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if view.turnPlayer == seat.id {
                        Image(systemName: "arrowtriangle.left.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(SR.accent)
                            .accessibilityHidden(true)
                    }
                    if view.winner == seat.id {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SR.accent)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 6)
                    if seat.away {
                        Text("left")
                            .font(SR.Text.mono(13))
                            .foregroundStyle(SR.inkSecondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    Text("\(discCount(seat.seat))")
                        .font(SR.Text.mono(15))
                        .foregroundStyle(SR.ink)
                        .frame(minWidth: 30, alignment: .trailing)
                        .fixedSize()
                }
                .frame(minHeight: 40)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(seatLabel(seat))
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 6)
        .srGlassCard(.paper)
        .accessibilityIdentifier("offline-four-in-a-row-players")
    }

    private func discCount(_ seat: Int) -> Int {
        view.grid.filter { $0 == seat }.count
    }

    private func seatLabel(_ seat: FourInARowRules.Seat) -> String {
        var parts = [seat.id == context.me ? "You" : seat.name]
        parts.append("plays the \(FourInARowDisc.markerName(seat.seat)) discs")
        let count = discCount(seat.seat)
        parts.append(count == 1 ? "1 dropped" : "\(count) dropped")
        if seat.away { parts.append("left the game") }
        if view.turnPlayer == seat.id { parts.append("choosing now") }
        if view.winner == seat.id { parts.append("winner") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Acting

    /// A tap on the board picked `column`: the same column twice drops.
    private func pick(_ column: Int) {
        guard canDrop else { return }
        guard FourInARowRules.landingRow(column: column, cols: view.cols, rows: view.rows, grid: view.grid) != nil else {
            SRHaptic.bad()
            return
        }
        if selected == column {
            drop(column)
        } else {
            SRHaptic.select()
            selected = column
        }
    }

    /// The host marked me away while my phone was gone; seeing views again
    /// means I am back, so say so once.
    private func comeBackIfAway() {
        guard let seat = view.seats.first(where: { $0.id == context.me }) else { return }
        if seat.away {
            guard !sentBack, view.phase == .playing else { return }
            sentBack = true
            context.send(.back)
        } else {
            sentBack = false
        }
    }

    private func drop(_ column: Int) {
        guard canDrop else { return }
        SRHaptic.tap()
        waiting = true
        context.send(.drop(turn: view.turnNumber, column: column))
    }
}

/// The board: a plate of round spaces, one tappable column per button, with
/// a pointer over the picked column, a faint disc where it would land, the
/// last disc ringed in the accent colour and the winning line ringed in ink.
///
/// Sized from the width it is given — the space side is the smaller of the
/// width over the columns and the height over the rows — and the aspect
/// ratio fixes the height, so it never runs off a narrow phone.
struct FourInARowBoard: View {
    let view: FourInARowRules.PlayerView
    /// My seat, for the colour of the faint disc; nil for a spectator.
    let mySeat: Int?
    let selected: Int?
    let interactive: Bool
    /// A player's display name by id ("You" for me).
    let name: (String) -> String
    let onPick: (Int) -> Void
    let onDrop: (Int) -> Void

    /// The plate's border, in spaces.
    private static let inset: CGFloat = 0.2
    /// The pointer row above the columns, in spaces.
    private static let pointer: CGFloat = 0.6

    private var cols: Int { max(view.cols, 1) }
    private var rows: Int { max(view.rows, 1) }

    private var aspect: CGFloat {
        (CGFloat(cols) + 2 * Self.inset) / (CGFloat(rows) + Self.pointer + 2 * Self.inset)
    }

    var body: some View {
        GeometryReader { geo in
            let unit = max(1, min(geo.size.width / (CGFloat(cols) + 2 * Self.inset),
                                  geo.size.height / (CGFloat(rows) + Self.pointer + 2 * Self.inset)))
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(0..<cols, id: \.self) { col in
                        column(col, unit: unit)
                    }
                }
                .padding(.horizontal, unit * Self.inset)
                .padding(.bottom, unit * Self.inset)
                .background(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: unit * 0.3, style: .continuous)
                        .fill(SR.ink.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: unit * 0.3, style: .continuous)
                                .strokeBorder(SR.line, lineWidth: 1)
                        )
                        .frame(height: unit * (CGFloat(rows) + 2 * Self.inset))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(aspect, contentMode: .fit)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Board, \(cols) columns by \(rows) rows")
        .accessibilityIdentifier("offline-four-in-a-row-board")
    }

    // MARK: - A column

    private func column(_ col: Int, unit: CGFloat) -> some View {
        let landing = FourInARowRules.landingRow(column: col, cols: view.cols, rows: view.rows, grid: view.grid)
        return Button {
            onPick(col)
        } label: {
            VStack(spacing: 0) {
                ZStack {
                    if selected == col {
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: unit * 0.4, weight: .bold))
                            .foregroundStyle(mySeat.map { OfflineSeatColour.of($0) } ?? SR.accent)
                    }
                }
                .frame(width: unit, height: unit * (Self.pointer + Self.inset))
                ForEach(0..<rows, id: \.self) { row in
                    space(row: row, col: col, ghost: selected == col && landing == row, unit: unit)
                }
            }
            .frame(width: unit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(columnLabel(col, landing: landing))
        .accessibilityHint(interactive && landing != nil ? "Double-tap to pick this column, then double-tap again to drop." : "")
        .accessibilityAddTraits(selected == col ? .isSelected : [])
        .accessibilityActions {
            if interactive && landing != nil {
                Button("Drop a disc here") { onDrop(col) }
            }
        }
        .accessibilityIdentifier("offline-four-in-a-row-column-\(col)")
    }

    @ViewBuilder
    private func space(row: Int, col: Int, ghost: Bool, unit: CGFloat) -> some View {
        let index = row * view.cols + col
        let owner = view.grid.indices.contains(index) ? view.grid[index] : -1
        let isLast = view.lastMove.map { $0.row == row && $0.column == col } ?? false
        ZStack {
            Circle()
                .fill(SR.paper)
            Circle()
                .strokeBorder(SR.line, lineWidth: 1)
            if owner >= 0 {
                FourInARowDisc(seat: owner, size: unit * 0.78)
            } else if ghost, let seat = mySeat {
                FourInARowDisc(seat: seat, size: unit * 0.78)
                    .opacity(0.35)
            }
            if view.winningCells.contains(index) {
                Circle()
                    .strokeBorder(SR.ink, lineWidth: max(2, unit * 0.09))
            } else if isLast {
                Circle()
                    .strokeBorder(SR.accent, lineWidth: max(1.5, unit * 0.06))
            }
        }
        .padding(unit * 0.05)
        .frame(width: unit, height: unit)
    }

    // MARK: - Words

    private func columnLabel(_ col: Int, landing: Int?) -> String {
        var text = "Column \(col + 1)"
        var discs: [String] = []
        for row in stride(from: view.rows - 1, through: 0, by: -1) {
            let index = row * view.cols + col
            guard view.grid.indices.contains(index) else { continue }
            let owner = view.grid[index]
            guard owner >= 0 else { break }
            discs.append(ownerName(owner))
        }
        if discs.isEmpty {
            text += ", empty"
        } else {
            text += ", from the bottom: " + discs.joined(separator: ", ")
        }
        if let landing {
            let free = landing + 1
            text += free == 1 ? ". 1 space free" : ". \(free) spaces free"
        } else {
            text += ". Full"
        }
        if selected == col { text += ". Picked" }
        return text
    }

    private func ownerName(_ seat: Int) -> String {
        guard let player = view.seats.first(where: { $0.seat == seat }) else { return "a disc" }
        let who = name(player.id)
        return who == "You" ? "yours" : "\(who)'s"
    }
}

/// One player's disc: their seat colour with their seat's marker on it, so
/// discs differ in shape as well as colour.
struct FourInARowDisc: View {
    let seat: Int
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(OfflineSeatColour.of(seat))
            .overlay(
                Image(systemName: Self.symbol(seat))
                    .font(.system(size: size * 0.4, weight: .heavy))
                    .foregroundStyle(SR.paper)
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    /// The marker for a seat: dot, cross, triangle, square (then star).
    static func symbol(_ seat: Int) -> String {
        switch seat {
        case 0: return "circle.fill"
        case 1: return "xmark"
        case 2: return "triangle.fill"
        case 3: return "square.fill"
        default: return "star.fill"
        }
    }

    /// The marker's spoken name.
    static func markerName(_ seat: Int) -> String {
        switch seat {
        case 0: return "dot"
        case 1: return "cross"
        case 2: return "triangle"
        case 3: return "square"
        default: return "star"
        }
    }
}
