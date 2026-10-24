import SwiftUI

/// Dots and Boxes on one phone: whose turn, the turn clock, the board and
/// the box count.
///
/// The board is sized from the width it is given, so a 6 × 5 board for five
/// players still fits a 375-point phone with boxes about 60 points across.
/// Lines are thin, so they are not buttons: a tap anywhere near a gap picks
/// the nearest undrawn line and highlights it, and Draw (or a second tap on
/// the same gap) sends it. A mis-tap costs nothing. VoiceOver reads the board
/// box by box, and each box offers its open sides as actions.
struct DotsAndBoxesView: View {
    let context: OfflineGameContext<DotsAndBoxesRules>
    /// The line picked but not yet drawn.
    @State private var selected: DotsAndBoxesRules.Line?
    /// A line has gone to the host and its answer has not come back yet, so
    /// a double tap sends once. Any new view clears it.
    @State private var waiting = false
    /// I have told the host my phone is back after being marked away.
    @State private var sentBack = false

    private var view: DotsAndBoxesRules.PlayerView { context.view }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SRPageHeader(kicker: kicker, title: title, strap: strap)
                if view.phase == .playing { turnBar }
                DotsAndBoxesBoard(
                    view: view,
                    selected: selected,
                    interactive: canDraw,
                    name: { who($0) },
                    onPick: { pick($0) },
                    onDraw: { draw($0) }
                )
                if canDraw { drawControls }
                if let line = lastMoveText {
                    Text(line)
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("offline-dots-and-boxes-last-move")
                }
                scores
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
            if let move = view.lastMove, move.playerId == context.me, move.claimed > 0 { SRHaptic.ok() }
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

    /// Whether I hold a seat in this match and am still here.
    private var playing: Bool {
        view.seats.contains { $0.id == context.me && !$0.away }
    }

    private var myTurn: Bool { view.phase == .playing && view.turnPlayer == context.me }

    /// I may pick and draw a line now.
    private var canDraw: Bool { myTurn && playing && !waiting }

    private func who(_ id: String) -> String {
        id == context.me ? "You" : context.name(of: id)
    }

    private var claimedCount: Int { view.boxes.filter { $0 >= 0 }.count }

    private var kicker: String {
        "Dots and Boxes · \(claimedCount) of \(view.boxes.count) boxes"
    }

    private var title: String {
        switch view.phase {
        case .playing:
            guard let turn = view.turnPlayer else { return "Dots and Boxes" }
            return turn == context.me ? "Your turn" : "\(context.name(of: turn))'s turn"
        case .done, .over:
            let names = view.champions.map { who($0) }
            if names.count == 1 { return names[0] == "You" ? "You win" : "\(names[0]) wins" }
            return names.isEmpty ? "Game over" : "A tie"
        }
    }

    /// What to do now, in one sentence.
    private var strap: String? {
        guard view.phase == .playing else { return "Every box is claimed." }
        if !playing { return "You are watching this game." }
        guard myTurn else {
            return "Wait for your turn. Don't leave a box with three sides drawn."
        }
        if selected != nil { return "Tap Draw to draw the highlighted line, or tap another gap." }
        return "Tap near a gap between two dots to pick a line. Close a box to go again."
    }

    private var lastMoveText: String? {
        guard let move = view.lastMove else { return nil }
        let name = who(move.playerId)
        let lead = move.timedOut
            ? (move.playerId == context.me ? "Time ran out, so a line was drawn for you" : "Time ran out, so a line was drawn for \(name)")
            : "\(name) drew a line"
        guard move.claimed > 0 else { return lead + "." }
        let boxes = move.claimed == 1 ? "a box" : "\(move.claimed) boxes"
        let again = view.phase == .playing ? (move.playerId == context.me ? " You go again." : " \(name) goes again.") : ""
        let claimedBy = move.timedOut ? " and it claimed \(boxes)." : " and claimed \(boxes)."
        return lead + claimedBy + again
    }

    // MARK: - The turn

    private var turnBar: some View {
        HStack(spacing: 10) {
            if let turn = view.turnPlayer, let seat = view.seats.first(where: { $0.id == turn }) {
                OfflineInitial(name: seat.name, size: 28, tone: OfflineSeatColour.of(seat.seat))
                Text(turn == context.me ? "Your line" : "\(seat.name) is drawing")
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
        .accessibilityIdentifier("offline-dots-and-boxes-turn")
    }

    private var drawControls: some View {
        HStack(spacing: 10) {
            Button {
                if let line = selected { draw(line) }
            } label: {
                SRButtonLabel(title: "Draw", icon: "pencil", fill: true)
            }
            .srButton(.prominent)
            .controlSize(.large)
            .disabled(selected == nil)
            .accessibilityIdentifier("offline-dots-and-boxes-draw")
            .accessibilityLabel("Draw the picked line")

            Button {
                SRHaptic.select()
                selected = nil
            } label: {
                SRButtonLabel(title: "Clear", fill: true)
            }
            .srButton(.regular)
            .controlSize(.large)
            .disabled(selected == nil)
            .accessibilityIdentifier("offline-dots-and-boxes-clear")
            .accessibilityLabel("Clear the picked line")
        }
    }

    // MARK: - The scores

    private var scores: some View {
        VStack(spacing: 0) {
            ForEach(Array(view.seats.enumerated()), id: \.element.id) { index, seat in
                if index > 0 { Divider().overlay(SR.divider) }
                HStack(spacing: 10) {
                    OfflineInitial(name: seat.name, size: 28, tone: OfflineSeatColour.of(seat.seat))
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
                    if view.champions.contains(seat.id) {
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
                    Text("\(seat.boxes)")
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
        .accessibilityIdentifier("offline-dots-and-boxes-scores")
    }

    private func seatLabel(_ seat: DotsAndBoxesRules.Seat) -> String {
        var parts = [seat.id == context.me ? "You" : seat.name]
        parts.append(seat.boxes == 1 ? "1 box" : "\(seat.boxes) boxes")
        if seat.away { parts.append("left the game") }
        if view.turnPlayer == seat.id { parts.append("drawing now") }
        if view.champions.contains(seat.id) { parts.append("winner") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Acting

    /// A tap on the board picked `line`: the same line twice draws it.
    private func pick(_ line: DotsAndBoxesRules.Line) {
        guard canDraw else { return }
        if selected == line {
            draw(line)
        } else {
            SRHaptic.select()
            selected = line
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

    private func draw(_ line: DotsAndBoxesRules.Line) {
        guard canDraw else { return }
        SRHaptic.tap()
        waiting = true
        context.send(.draw(turn: view.turnNumber, line: line))
    }
}

/// The board itself: dots, drawn lines, claimed boxes in their owner's seat
/// colour, the last line in the accent colour, and the picked line dashed.
///
/// Drawn in one `Canvas` sized from the available width (the aspect ratio
/// fixes the height), with one spatial tap that is turned into the nearest
/// undrawn line. Over it sits an invisible grid of one accessibility element
/// per box — hit testing off, so it never steals a tap — for VoiceOver.
struct DotsAndBoxesBoard: View {
    let view: DotsAndBoxesRules.PlayerView
    let selected: DotsAndBoxesRules.Line?
    let interactive: Bool
    /// A player's display name by id ("You" for me).
    let name: (String) -> String
    let onPick: (DotsAndBoxesRules.Line) -> Void
    let onDraw: (DotsAndBoxesRules.Line) -> Void

    /// Space around the outer dots, in box widths, so the edge lines can be
    /// tapped and the outer dots are not clipped.
    private static let margin: CGFloat = 0.3

    var body: some View {
        GeometryReader { geo in
            let metrics = Metrics(size: geo.size, rows: view.rows, cols: view.cols)
            ZStack(alignment: .topLeading) {
                Canvas { canvas, _ in
                    paint(canvas, metrics)
                }
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture().onEnded { value in
                        guard interactive, let line = metrics.line(near: value.location, isOpen: isOpen) else { return }
                        onPick(line)
                    }
                )
                .accessibilityHidden(true)

                ForEach(0..<(view.rows * view.cols), id: \.self) { index in
                    let row = index / view.cols
                    let col = index % view.cols
                    Rectangle()
                        .fill(Color.white.opacity(0.001))
                        .frame(width: metrics.unit, height: metrics.unit)
                        .position(metrics.centre(row: row, col: col))
                        .allowsHitTesting(false)
                        .accessibilityElement()
                        .accessibilityLabel(boxLabel(row: row, col: col))
                        .accessibilityHint(interactive ? "Swipe up or down to pick an open side to draw." : "")
                        .accessibilityActions {
                            if interactive {
                                ForEach(Array(openSides(row: row, col: col).enumerated()), id: \.offset) { _, side in
                                    Button("Draw the \(side.name) side") { onDraw(side.line) }
                                }
                            }
                        }
                        .accessibilityIdentifier("offline-dots-and-boxes-box-\(row)-\(col)")
                }
            }
        }
        .aspectRatio((CGFloat(view.cols) + 2 * Self.margin) / (CGFloat(view.rows) + 2 * Self.margin), contentMode: .fit)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Board, \(view.rows) rows of \(view.cols) boxes")
        .accessibilityIdentifier("offline-dots-and-boxes-board")
    }

    // MARK: - Reading the board

    private func isOpen(_ line: DotsAndBoxesRules.Line) -> Bool {
        DotsAndBoxesRules.isDrawn(line, rows: view.rows, cols: view.cols, hLines: view.hLines, vLines: view.vLines) == false
    }

    private func isDrawn(_ line: DotsAndBoxesRules.Line) -> Bool {
        DotsAndBoxesRules.isDrawn(line, rows: view.rows, cols: view.cols, hLines: view.hLines, vLines: view.vLines) == true
    }

    private func owner(row: Int, col: Int) -> DotsAndBoxesRules.Seat? {
        let index = row * view.cols + col
        guard view.boxes.indices.contains(index), view.boxes[index] >= 0 else { return nil }
        let seat = view.boxes[index]
        return view.seats.first { $0.seat == seat }
    }

    /// A box's sides with their spoken names, top, bottom, left, right.
    private func sides(row: Int, col: Int) -> [(name: String, line: DotsAndBoxesRules.Line)] {
        let lines = DotsAndBoxesRules.sides(row: row, col: col)
        return zip(["top", "bottom", "left", "right"], lines).map { (name: $0.0, line: $0.1) }
    }

    private func openSides(row: Int, col: Int) -> [(name: String, line: DotsAndBoxesRules.Line)] {
        sides(row: row, col: col).filter { isOpen($0.line) }
    }

    private func boxLabel(row: Int, col: Int) -> String {
        var text = "Row \(row + 1), column \(col + 1)"
        if let seat = owner(row: row, col: col) {
            return text + ", claimed by \(name(seat.id))"
        }
        let open = openSides(row: row, col: col).map(\.name)
        if open.isEmpty { return text }
        text += open.count == 4 ? ", no sides drawn" : ", open: " + open.joined(separator: ", ")
        if open.count == 1 { text += ". One line closes it" }
        return text
    }

    // MARK: - Painting

    private func paint(_ canvas: GraphicsContext, _ m: Metrics) {
        // Claimed boxes, in the owner's colour, with their initial.
        for row in 0..<view.rows {
            for col in 0..<view.cols {
                guard let seat = owner(row: row, col: col) else { continue }
                let tone = OfflineSeatColour.of(seat.seat)
                let origin = m.dot(row: row, col: col)
                let rect = CGRect(x: origin.x, y: origin.y, width: m.unit, height: m.unit)
                canvas.fill(Path(rect), with: .color(tone.opacity(0.28)))
                let initial = Text(String(seat.name.prefix(1)).uppercased())
                    .font(.system(size: m.unit * 0.38, weight: .bold, design: .rounded))
                    .foregroundColor(tone)
                canvas.draw(initial, at: m.centre(row: row, col: col))
            }
        }

        let thin = max(1, m.unit * 0.02)
        let thick = max(3, m.unit * 0.07)
        let last = view.lastMove?.line

        for line in allLines {
            let path = m.path(of: line)
            if isDrawn(line) {
                let tone = line == last ? SR.accent : SR.ink
                canvas.stroke(path, with: .color(tone), style: StrokeStyle(lineWidth: thick, lineCap: .round))
            } else if line == selected {
                canvas.stroke(path, with: .color(SR.accent.opacity(0.8)),
                              style: StrokeStyle(lineWidth: thick, lineCap: .round, dash: [thick * 1.6, thick * 1.4]))
            } else if view.phase == .playing {
                canvas.stroke(path, with: .color(SR.inkGhost), style: StrokeStyle(lineWidth: thin, lineCap: .round))
            }
        }

        // Dots last, on top of the line ends.
        let radius = max(3.5, m.unit * 0.08)
        for row in 0...view.rows {
            for col in 0...view.cols {
                let point = m.dot(row: row, col: col)
                let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                canvas.fill(Path(ellipseIn: rect), with: .color(SR.ink))
            }
        }
    }

    /// Every line on the board, horizontals then verticals.
    private var allLines: [DotsAndBoxesRules.Line] {
        var out: [DotsAndBoxesRules.Line] = []
        for row in 0...view.rows {
            for col in 0..<view.cols { out.append(DotsAndBoxesRules.Line(horizontal: true, row: row, col: col)) }
        }
        for row in 0..<view.rows {
            for col in 0...view.cols { out.append(DotsAndBoxesRules.Line(horizontal: false, row: row, col: col)) }
        }
        return out
    }

    // MARK: - Geometry

    /// Where the dots sit for one size: a square unit per box, centred, with
    /// `margin` units of space round the outside.
    private struct Metrics {
        let rows: Int
        let cols: Int
        let unit: CGFloat
        let originX: CGFloat
        let originY: CGFloat

        init(size: CGSize, rows: Int, cols: Int) {
            self.rows = max(rows, 1)
            self.cols = max(cols, 1)
            let across = CGFloat(self.cols) + 2 * DotsAndBoxesBoard.margin
            let down = CGFloat(self.rows) + 2 * DotsAndBoxesBoard.margin
            unit = max(1, min(size.width / across, size.height / down))
            originX = (size.width - unit * CGFloat(self.cols)) / 2
            originY = (size.height - unit * CGFloat(self.rows)) / 2
        }

        func dot(row: Int, col: Int) -> CGPoint {
            CGPoint(x: originX + CGFloat(col) * unit, y: originY + CGFloat(row) * unit)
        }

        func centre(row: Int, col: Int) -> CGPoint {
            CGPoint(x: originX + (CGFloat(col) + 0.5) * unit, y: originY + (CGFloat(row) + 0.5) * unit)
        }

        func ends(of line: DotsAndBoxesRules.Line) -> (CGPoint, CGPoint) {
            let start = dot(row: line.row, col: line.col)
            let end = line.horizontal ? dot(row: line.row, col: line.col + 1) : dot(row: line.row + 1, col: line.col)
            return (start, end)
        }

        func path(of line: DotsAndBoxesRules.Line) -> Path {
            let (start, end) = ends(of: line)
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            return path
        }

        /// The undrawn line nearest `point`, if one is within half a box of it.
        /// Looks at the sides of the box under the finger and its neighbours,
        /// so a tap on a drawn edge still finds the open one beside it.
        func line(near point: CGPoint, isOpen: (DotsAndBoxesRules.Line) -> Bool) -> DotsAndBoxesRules.Line? {
            let fx = (point.x - originX) / unit
            let fy = (point.y - originY) / unit
            let boxCol = min(max(Int(fx.rounded(.down)), 0), cols - 1)
            let boxRow = min(max(Int(fy.rounded(.down)), 0), rows - 1)
            var best: (line: DotsAndBoxesRules.Line, distance: CGFloat)?
            for row in max(boxRow - 1, 0)...min(boxRow + 1, rows - 1) {
                for col in max(boxCol - 1, 0)...min(boxCol + 1, cols - 1) {
                    for line in DotsAndBoxesRules.sides(row: row, col: col) where isOpen(line) {
                        let distance = self.distance(from: point, to: line)
                        if best == nil || distance < best!.distance { best = (line, distance) }
                    }
                }
            }
            guard let best, best.distance <= unit * 0.5 else { return nil }
            return best.line
        }

        private func distance(from point: CGPoint, to line: DotsAndBoxesRules.Line) -> CGFloat {
            let (a, b) = ends(of: line)
            let dx = b.x - a.x
            let dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            guard lengthSquared > 0 else { return hypot(point.x - a.x, point.y - a.y) }
            let t = min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared, 0), 1)
            return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
        }
    }
}
