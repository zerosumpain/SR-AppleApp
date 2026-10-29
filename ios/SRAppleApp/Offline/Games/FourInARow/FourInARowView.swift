import SwiftUI

/// Four in a Row on one phone: whose turn, the turn clock, the board and
/// who is playing which disc.
///
/// The board is sized from the width it is given, so the 9 × 7 board for
/// three or four players still fits a 375-point phone with spaces about 36
/// points across. A tap on a column picks it and holds your disc over it,
/// with a faint one where it would land; Drop (or a second tap on the same
/// column) sends it, so a mis-tap costs nothing.
///
/// Each player's discs have their own colour AND their own marker (a dot, a
/// cross, a triangle, a square), so the board still reads for someone who
/// cannot tell the colours apart. VoiceOver reads the board column by
/// column, bottom up, and each column offers "Drop a disc here" as an action.
///
/// The board is the classic upright frame: a blue plate with round holes,
/// drawn over the discs, so a dropped disc falls behind it — glimpsed through
/// each hole on the way down — and lands with a bounce and a tap. The winning
/// four are ringed in gold.
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
            VStack(alignment: .leading, spacing: 18) {
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
            if view.turnPlayer == context.me, view.lastMove?.playerId != context.me { SRHaptic.select() }
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

    @ViewBuilder
    private var turnBar: some View {
        if let turn = view.turnPlayer, let seat = view.seats.first(where: { $0.id == turn }) {
            PlayTableTurnStrip(text: turn == context.me ? "Your disc" : "\(seat.name) is choosing",
                               mine: turn == context.me, clock: context.clock, until: view.turnEndsAt,
                               total: FourInARowRules.turnSeconds, tone: OfflineSeatColour.of(seat.seat)) {
                FourInARowDisc(seat: seat.seat, size: 40)
            }
            .accessibilityIdentifier("offline-four-in-a-row-turn")
        }
    }

    private var dropControls: some View {
        HStack(spacing: 10) {
            PlayTableButton(title: "Drop", icon: "arrow.down", haptic: .none) {
                if let column = selected { drop(column) }
            }
            .disabled(selected == nil)
            .accessibilityIdentifier("offline-four-in-a-row-drop")
            .accessibilityLabel(selected.map { "Drop a disc in column \($0 + 1)" } ?? "Drop")

            PlayTableButton(title: "Clear", weight: .regular, haptic: .select) {
                selected = nil
            }
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
                seatRow(seat)
            }
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 6)
        .srGlassCard(.paper)
        .accessibilityIdentifier("offline-four-in-a-row-players")
    }

    private func seatRow(_ seat: FourInARowRules.Seat) -> some View {
        let turn = view.turnPlayer == seat.id && view.phase == .playing
        let tone = OfflineSeatColour.of(seat.seat)
        return HStack(spacing: 12) {
            FourInARowDisc(seat: seat.seat, size: 34)
                .opacity(seat.away ? 0.45 : 1)
                .overlay(Circle().strokeBorder(turn ? tone : Color.clear, lineWidth: 2.5).padding(-4))
            Text(seat.id == context.me ? "You" : seat.name)
                .font(SR.Text.bodyMedium(16))
                .foregroundStyle(seat.away ? SR.inkMuted : SR.ink)
                .lineLimit(1)
                .truncationMode(.tail)
            if turn {
                Text("CHOOSING")
                    .font(SR.Text.label(10))
                    .tracking(0.8)
                    .foregroundStyle(tone)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(tone.opacity(0.14)))
                    .accessibilityHidden(true)
            }
            if view.winner == seat.id {
                Image(systemName: "crown.fill")
                    .font(SR.Text.label(14))
                    .foregroundStyle(Color(hex: 0xE0A21C))
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
                .font(SR.Text.figure(17))
                .foregroundStyle(SR.ink)
                .frame(minWidth: 30, alignment: .trailing)
                .fixedSize()
                .srNumeric(Double(discCount(seat.seat)))
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(seatLabel(seat))
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

/// The frame's colours: the same in both appearances, as the toy is.
enum FourInARowPaint {
    static let plateLight = Color(hex: 0x2F62D9)
    static let plateDeep = Color(hex: 0x173C9E)
    static let holeRim = Color(hex: 0x0E2A75)
    static let backing = Color(hex: 0x0B1A47)
    static let win = Color(hex: 0xF5C451)
}

/// The board: one tappable column per button holding the discs, with the
/// blue plate drawn over them (holes cut out, so it never takes a tap), my
/// disc held over the picked column, a faint disc where it would land, the
/// last disc ringed and the winning line ringed in gold.
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
    private static let inset: CGFloat = 0.22
    /// The row above the plate where a picked disc is held, in spaces.
    private static let pointer: CGFloat = 0.95

    private var cols: Int { max(view.cols, 1) }
    private var rows: Int { max(view.rows, 1) }

    private var aspect: CGFloat {
        (CGFloat(cols) + 2 * Self.inset) / (CGFloat(rows) + Self.pointer + 2 * Self.inset)
    }

    var body: some View {
        GeometryReader { geo in
            let across: CGFloat = CGFloat(cols) + 2 * Self.inset
            let down: CGFloat = CGFloat(rows) + Self.pointer + 2 * Self.inset
            let unit: CGFloat = max(1, min(geo.size.width / across, geo.size.height / down))
            let plateHeight = unit * (CGFloat(rows) + 2 * Self.inset)
            let plateWidth = unit * (CGFloat(cols) + 2 * Self.inset)
            ZStack(alignment: .bottom) {
                // The dark behind the holes.
                RoundedRectangle(cornerRadius: unit * 0.3, style: .continuous)
                    .fill(FourInARowPaint.backing)
                    .frame(width: plateWidth, height: plateHeight)
                HStack(spacing: 0) {
                    ForEach(0..<cols, id: \.self) { col in
                        column(col, unit: unit)
                    }
                }
                .padding(.horizontal, unit * Self.inset)
                .padding(.bottom, unit * Self.inset)
                FourInARowPlate(view: view, selected: selected, unit: unit,
                                inset: Self.inset, pointer: Self.pointer)
                    .frame(width: plateWidth, height: plateHeight)
                    .shadow(color: Color.black.opacity(0.22), radius: 8, x: 0, y: 5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
        }
        .aspectRatio(aspect, contentMode: .fit)
        .frame(maxWidth: 460)
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
                    if selected == col, let seat = mySeat {
                        FourInARowDisc(seat: seat, size: unit * 0.78)
                            .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 3)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
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
        .srAnimation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
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
            if owner >= 0 {
                if isLast {
                    FourInARowFallingDisc(seat: owner, size: unit * 0.82,
                                          fall: unit * (CGFloat(row) + 1.1), rows: row + 1)
                } else {
                    FourInARowDisc(seat: owner, size: unit * 0.82)
                }
            } else if ghost, let seat = mySeat {
                FourInARowDisc(seat: seat, size: unit * 0.82)
                    .opacity(0.35)
            }
        }
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

/// The blue plate with its holes, drawn over the discs: one `Canvas`, the
/// holes cut with an even-odd fill, then the rims, a light down the picked
/// column, the last disc's ring and the winning four in gold.
struct FourInARowPlate: View {
    let view: FourInARowRules.PlayerView
    let selected: Int?
    let unit: CGFloat
    let inset: CGFloat
    let pointer: CGFloat

    var body: some View {
        let cols = max(view.cols, 1)
        let rows = max(view.rows, 1)
        let unit = self.unit
        let inset = self.inset
        let winning = Set(view.winningCells)
        let last = view.lastMove
        let selected = self.selected
        return Canvas { context, size in
            let radius = unit * 0.43
            func centre(_ row: Int, _ col: Int) -> CGPoint {
                CGPoint(x: unit * inset + (CGFloat(col) + 0.5) * unit,
                        y: unit * inset + (CGFloat(row) + 0.5) * unit)
            }
            func hole(_ row: Int, _ col: Int, grow: CGFloat) -> CGRect {
                let c = centre(row, col)
                let r = radius + grow
                return CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            }
            var plate = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: unit * 0.3, style: .continuous)
            for row in 0..<rows {
                for col in 0..<cols {
                    plate.addEllipse(in: hole(row, col, grow: 0))
                }
            }
            context.fill(plate,
                         with: .linearGradient(Gradient(colors: [FourInARowPaint.plateLight, FourInARowPaint.plateDeep]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)),
                         style: FillStyle(eoFill: true))
            var rims = Path()
            for row in 0..<rows {
                for col in 0..<cols {
                    rims.addEllipse(in: hole(row, col, grow: 0))
                }
            }
            context.stroke(rims, with: .color(FourInARowPaint.holeRim), lineWidth: max(1, unit * 0.05))
            if let selected, selected < cols {
                let x = unit * inset + CGFloat(selected) * unit
                let band = CGRect(x: x + unit * 0.04, y: unit * 0.05, width: unit * 0.92, height: size.height - unit * 0.1)
                context.fill(Path(roundedRect: band, cornerRadius: unit * 0.4), with: .color(Color.white.opacity(0.12)))
            }
            if let last, winning.isEmpty {
                context.stroke(Path(ellipseIn: hole(last.row, last.column, grow: unit * 0.02)),
                               with: .color(Color.white.opacity(0.85)), lineWidth: max(1.5, unit * 0.06))
            }
            for index in winning {
                let row = index / cols
                let col = index % cols
                context.stroke(Path(ellipseIn: hole(row, col, grow: unit * 0.03)),
                               with: .color(FourInARowPaint.win), lineWidth: max(2.5, unit * 0.1))
            }
        }
    }
}

/// One player's disc: their seat colour, lit like a plastic counter, with
/// their seat's marker on it, so discs differ in shape as well as colour.
struct FourInARowDisc: View {
    let seat: Int
    let size: CGFloat

    var body: some View {
        let tone = OfflineSeatColour.of(seat)
        return ZStack {
            Circle()
                .fill(tone)
            Circle()
                .fill(RadialGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0)],
                                     center: UnitPoint(x: 0.32, y: 0.28), startRadius: 0, endRadius: size * 0.55))
            Circle()
                .strokeBorder(Color.black.opacity(0.18), lineWidth: max(1, size * 0.07))
                .padding(size * 0.12)
            Image(systemName: Self.symbol(seat))
                .font(.system(size: size * 0.36, weight: .heavy))
                .foregroundStyle(Color.white.opacity(0.92))
        }
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

/// The newest disc: it falls from above the plate into its space, bounces
/// once and lands with a tap. Once, when it first appears; simply there
/// under Reduce Motion.
struct FourInARowFallingDisc: View {
    let seat: Int
    let size: CGFloat
    /// How far above its space it starts, in points.
    let fall: CGFloat
    /// How many rows it falls, for the timing.
    let rows: Int
    @State private var landed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let down = landed || reduceMotion
        return FourInARowDisc(seat: seat, size: size)
            .offset(y: down ? 0 : -fall)
            .onAppear {
                guard !reduceMotion, !landed else { return }
                let seconds = PlayTableMath.dropSeconds(rows: rows)
                withAnimation(.spring(response: seconds * 1.5, dampingFraction: 0.58)) { landed = true }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    SRHaptic.tap()
                }
            }
    }
}
