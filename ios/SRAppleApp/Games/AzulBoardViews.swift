import SwiftUI

// Azul's pieces, drawn: the tiles, a factory, the centre, and a player's
// board (five pattern lines, the 5×5 wall, the floor). The screen arranges
// them (`AzulScreen.swift`); nothing here knows whose turn it is.
//
// Every tile is keyed by its id for the whole game, and every view that
// draws one can put it in the screen's shared namespace, so a tile taken
// from a factory flies to the line it landed on, the rest slide to the
// centre, and a full line's tile flies up onto the wall. Under Reduce Motion
// the screen's animation is off and they simply change.
//
// The board is laid out as equal flexible cells (five for the lines, five for
// the wall, a gap between), so its squares size to the phone's width with no
// GeometryReader — and stay square at any text size.

// MARK: - Paint

/// The tiles as paint. Fixed in both themes — they are tiles on a table —
/// and chosen to sit with the SR palette: a deep blue, a warm amber, a
/// terracotta, a near-black and a cream. Every tile also carries its own mark
/// (`AzulRules.glyph`), so nobody needs to tell them apart by colour.
enum AzulPaint {
    static func fill(_ colour: String) -> Color {
        switch colour {
        case "blue": return Color(hex: 0x1F4E8C)
        case "yellow": return Color(hex: 0xE2A62B)
        case "red": return Color(hex: 0xB8502E)
        case "black": return Color(hex: 0x24262C)
        case "white": return Color(hex: 0xF1E9DA)
        default: return Color(hex: 0xFBF7EF)
        }
    }

    /// The mark's colour on the fill.
    static func ink(_ colour: String) -> Color {
        switch colour {
        case "yellow", "white", AzulRules.marker: return Color(hex: 0x1E1B16)
        default: return Color(hex: 0xFBF7EF)
        }
    }

    /// The factories' and the centre's ground: a warm clay plate in both themes.
    static let plate = Color(hex: 0xE9DFCC)
    static let plateEdge = Color(hex: 0xC9B99C)
    static let plateInk = Color(hex: 0x4A3F30)
}

// MARK: - A tile

/// One tile's face: its colour, its mark and a little glaze. `faint` is an
/// empty wall square (the colour that belongs there, ghosted); `lifted` is a
/// picked tile, raised on a spring.
struct AzulTileFace: View {
    let colour: String
    var faint: Bool = false
    var lifted: Bool = false
    var dimmed: Bool = false
    /// Ringed: a tile that just moved, so the table can see what happened.
    var ringed: Bool = false

    var body: some View {
        ZStack {
            backing
            Image(systemName: AzulRules.glyph(colour))
                .resizable()
                .scaledToFit()
                .scaleEffect(0.5)
                .foregroundStyle(markColour)
                .accessibilityHidden(true)
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay {
            if ringed {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(SR.accent, lineWidth: 2)
                    .padding(-2)
            }
        }
        .shadow(color: shadowColour, radius: lifted ? 6 : 1, x: 0, y: lifted ? 4 : 1)
        .scaleEffect(lifted ? 1.12 : 1)
        .offset(y: lifted ? -5 : 0)
        .opacity(dimmed ? 0.45 : 1)
        .srAnimation(.spring(response: 0.32, dampingFraction: 0.58), value: lifted)
    }

    private var markColour: Color {
        faint ? AzulPaint.fill(colour).opacity(0.5) : AzulPaint.ink(colour).opacity(0.82)
    }

    private var shadowColour: Color {
        if faint { return Color.clear }
        return lifted ? SR.accent.opacity(0.45) : Color.black.opacity(0.18)
    }

    @ViewBuilder
    private var backing: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        if faint {
            ZStack {
                shape.fill(AzulPaint.fill(colour).opacity(0.14))
                shape.strokeBorder(AzulPaint.fill(colour).opacity(0.35), lineWidth: 1)
            }
        } else {
            ZStack {
                shape.fill(AzulPaint.fill(colour))
                shape.fill(LinearGradient(colors: [Color.white.opacity(0.26), Color.clear], startPoint: .top, endPoint: .center))
                shape.inset(by: 2).strokeBorder(AzulPaint.ink(colour).opacity(0.2), lineWidth: 1)
            }
        }
    }
}

/// A tile that can fly: in the screen's namespace when it has one.
struct AzulFly: ViewModifier {
    let id: Int
    let space: Namespace.ID?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let space {
            content.matchedGeometryEffect(id: id, in: space)
        } else {
            content
        }
    }
}

extension View {
    func azulFly(_ id: Int, in space: Namespace.ID?) -> some View { modifier(AzulFly(id: id, space: space)) }
}

/// A square cell of a board's grid: as wide as its share of the row.
private struct AzulCell<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
    }
}

/// An empty slot on a pattern line or the floor.
private struct AzulSlot: View {
    var lit: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(lit ? SR.accent.opacity(0.14) : SR.ink.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(lit ? SR.accent : SR.line, style: StrokeStyle(lineWidth: lit ? 2 : 1, dash: lit ? [] : [3, 2]))
            )
            .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Factories and the centre

/// One factory: a clay plate with up to four tiles. A tap on a tile picks
/// every tile of its colour here.
struct AzulFactoryView: View {
    let index: Int
    let tiles: [AzulTile]
    let picked: Set<Int>
    /// Something is picked here: the rest dim.
    let active: Bool
    let space: Namespace.ID?
    let enabled: Bool
    let pick: (String) -> Void

    var body: some View {
        ZStack {
            Circle().fill(AzulPaint.plate)
            Circle().strokeBorder(active ? SR.accent : AzulPaint.plateEdge, lineWidth: active ? 3 : 1.5)
            if tiles.isEmpty {
                Text("\(index + 1)")
                    .font(SR.Text.label())
                    .foregroundStyle(AzulPaint.plateInk.opacity(0.45))
            } else {
                grid.padding(18)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Factory \(index + 1)")
        .accessibilityIdentifier("azul-factory-\(index)")
    }

    private var grid: some View {
        VStack(spacing: 5) {
            HStack(spacing: 5) {
                slot(0)
                slot(1)
            }
            HStack(spacing: 5) {
                slot(2)
                slot(3)
            }
        }
    }

    @ViewBuilder
    private func slot(_ i: Int) -> some View {
        if i < tiles.count {
            AzulTableTile(tile: tiles[i], count: AzulRules.tiles(tiles[i].c, in: tiles).count, from: "factory \(index + 1)",
                          lifted: picked.contains(tiles[i].id), dimmed: active && !picked.contains(tiles[i].id),
                          space: space, enabled: enabled) { pick(tiles[i].c) }
        } else {
            Color.clear.frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
        }
    }
}

/// A tile on the table, as a button: tapping it picks its colour at its source.
struct AzulTableTile: View {
    let tile: AzulTile
    /// How many of its colour share its source.
    let count: Int
    let from: String
    let lifted: Bool
    let dimmed: Bool
    let space: Namespace.ID?
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        // Not `.disabled` off my turn: that would grey the table out. The
        // store ignores a pick when it is not my turn.
        Button {
            if enabled { action() }
        } label: {
            AzulTileFace(colour: tile.c, lifted: lifted, dimmed: dimmed)
                .azulFly(tile.id, in: space)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(lifted ? .isSelected : [])
        .accessibilityIdentifier("azul-tile-\(tile.id)")
    }

    private var spoken: String {
        let name = AzulRules.colourName(tile.c).lowercased()
        let what = count == 1 ? "1 \(name)" : "\(count) \(name)"
        return lifted ? "\(what) from \(from), picked" : "\(what) in \(from)"
    }
}

/// The centre: what the factories left, grouped by colour, and the
/// first-player marker while nobody has taken from here yet.
struct AzulCentreView: View {
    let tiles: [AzulTile]
    let marker: Bool
    let picked: Set<Int>
    let active: Bool
    let space: Namespace.ID?
    let enabled: Bool
    let pick: (String) -> Void

    private var sorted: [AzulTile] {
        tiles.sorted { a, b in
            let x = AzulRules.colours.firstIndex(of: a.c) ?? 9, y = AzulRules.colours.firstIndex(of: b.c) ?? 9
            return x != y ? x < y : a.id < b.id
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("CENTRE")
                    .font(SR.Text.label())
                    .tracking(SR.kickerTracking)
                    .foregroundStyle(AzulPaint.plateInk)
                Spacer(minLength: 8)
                if marker {
                    Text("First to take here starts next round")
                        .font(SR.Text.mono())
                        .foregroundStyle(AzulPaint.plateInk.opacity(0.75))
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                        .minimumScaleFactor(0.7)
                }
            }
            if tiles.isEmpty && !marker {
                Text("Empty")
                    .font(SR.Text.secondary())
                    .foregroundStyle(AzulPaint.plateInk.opacity(0.6))
                    .frame(maxWidth: .infinity, minHeight: 34)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 30, maximum: 40), spacing: 6)], spacing: 6) {
                    if marker {
                        AzulMarkerFace()
                            .azulFly(AzulRules.markerId, in: space)
                            .accessibilityIdentifier("azul-centre-marker")
                    }
                    ForEach(sorted) { tile in
                        AzulTableTile(tile: tile, count: AzulRules.tiles(tile.c, in: tiles).count, from: "the centre",
                                      lifted: picked.contains(tile.id), dimmed: active && !picked.contains(tile.id),
                                      space: space, enabled: enabled) { pick(tile.c) }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous).fill(AzulPaint.plate)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SR.Glass.innerRadius + 4, style: .continuous)
                .strokeBorder(active ? SR.accent : AzulPaint.plateEdge, lineWidth: active ? 3 : 1.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(marker ? "The centre, with the first-player marker" : "The centre")
        .accessibilityIdentifier("azul-centre")
    }
}

/// The first-player marker: a cream tile with a 1.
struct AzulMarkerFace: View {
    var body: some View {
        AzulTileFace(colour: AzulRules.marker)
            .accessibilityLabel("First-player marker")
    }
}

// MARK: - A board

/// A player's board: five pattern lines (right-aligned, filling towards the
/// wall), the wall with each square's colour ghosted until a tile is on it,
/// and the floor with what each space costs. On my turn the lines lit for the
/// picked colour glow and take a tap.
struct AzulBoardView: View {
    let board: AzulBoard
    var compact: Bool = false
    /// Lines that may take the picked colour.
    var lit: Set<Int> = []
    /// Something is picked: the floor is always open.
    var floorLit: Bool = false
    /// The round's wall tiles and what each scored (the scoring pause).
    var scored: [Int: Int] = [:]
    /// Tiles that just landed here, ringed.
    var recent: Set<Int> = []
    var space: Namespace.ID? = nil
    /// Tapping a lit line or the floor.
    var place: ((AzulLine) -> Void)? = nil

    private var gap: CGFloat { compact ? 2 : 3 }
    private var divide: CGFloat { compact ? 8 : 12 }

    var body: some View {
        VStack(spacing: compact ? 3 : 5) {
            ForEach(0..<5, id: \.self) { row in
                HStack(spacing: gap) {
                    lineCells(row)
                    Color.clear.frame(width: divide - gap * 2, height: 1)
                    wallCells(row)
                }
            }
            floorRow
                .padding(.top, compact ? 4 : 8)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Lines

    @ViewBuilder
    private func lineCells(_ row: Int) -> some View {
        let open = place != nil && lit.contains(row)
        let cells = HStack(spacing: gap) {
            ForEach(0..<5, id: \.self) { slot in
                lineCell(row, slot: slot, lit: open)
            }
        }
        if open, let place {
            Button { place(.line(row)) } label: { cells.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(lineSpoken(row) + ", lit")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("azul-line-\(row)")
        } else {
            cells
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(lineSpoken(row))
                .accessibilityIdentifier("azul-line-\(board.id)-\(row)")
        }
    }

    @ViewBuilder
    private func lineCell(_ row: Int, slot: Int, lit: Bool) -> some View {
        // Line `row` holds row + 1, in the slots nearest the wall.
        let first = 4 - row
        let tiles = board.lines[row]
        let index = 4 - slot
        AzulCell {
            if slot < first {
                Color.clear
            } else if index < tiles.count {
                AzulTileFace(colour: tiles[index].c, ringed: recent.contains(tiles[index].id))
                    .azulFly(tiles[index].id, in: space)
            } else {
                AzulSlot(lit: lit)
            }
        }
    }

    private func lineSpoken(_ row: Int) -> String {
        let tiles = board.lines[row]
        let base = "Line \(row + 1), holds \(row + 1)"
        guard let colour = tiles.first?.c else { return base + ", empty" }
        return base + ", \(tiles.count) \(AzulRules.colourName(colour).lowercased())"
    }

    // MARK: The wall

    private func wallCells(_ row: Int) -> some View {
        HStack(spacing: gap) {
            ForEach(0..<5, id: \.self) { col in
                wallCell(row, col)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(wallSpoken(row))
        .accessibilityIdentifier("azul-wall-\(board.id)-\(row)")
    }

    @ViewBuilder
    private func wallCell(_ row: Int, _ col: Int) -> some View {
        let colour = AzulRules.wallColour(row: row, col: col)
        AzulCell {
            if let id = board.wallTile(row, col) {
                AzulTileFace(colour: colour, ringed: scored[id] != nil)
                    .azulFly(id, in: space)
                    .overlay(alignment: .top) {
                        if let points = scored[id] { AzulPointsBadge(points: points, delay: 0.35 + 0.12 * Double(row)) }
                    }
            } else {
                AzulTileFace(colour: colour, faint: true)
            }
        }
    }

    private func wallSpoken(_ row: Int) -> String {
        let filled = (0..<5).compactMap { col -> String? in
            board.wallTile(row, col) == nil ? nil : AzulRules.colourName(AzulRules.wallColour(row: row, col: col)).lowercased()
        }
        return filled.isEmpty ? "Wall row \(row + 1), empty" : "Wall row \(row + 1): " + filled.joined(separator: ", ")
    }

    // MARK: The floor

    private var floorRow: some View {
        VStack(spacing: 2) {
            floorTiles
            if !compact { floorLabels }
        }
    }

    @ViewBuilder
    private var floorTiles: some View {
        let open = place != nil && floorLit
        // Laid out as the rows above are — two halves of five either side of
        // the gap — so its squares line up with theirs: five spaces, then two
        // more and three empty cells, where the floor's cost is written.
        let cells = HStack(spacing: gap) {
            HStack(spacing: gap) {
                ForEach(0..<5, id: \.self) { i in floorCell(i, lit: open) }
            }
            Color.clear.frame(width: divide - gap * 2, height: 1)
            HStack(spacing: gap) {
                ForEach(5..<7, id: \.self) { i in floorCell(i, lit: open) }
                ForEach(0..<3, id: \.self) { _ in AzulCell { Color.clear } }
            }
            .overlay(alignment: .trailing) { floorTotal }
        }
        if open, let place {
            Button { place(.floor) } label: { cells.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(floorSpoken + ", open")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("azul-floor")
        } else {
            cells
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(floorSpoken)
                .accessibilityIdentifier("azul-floor-\(board.id)")
        }
    }

    @ViewBuilder
    private func floorCell(_ i: Int, lit: Bool) -> some View {
        AzulCell {
            if i < board.floor.count {
                AzulTileFace(colour: board.floor[i].c, ringed: recent.contains(board.floor[i].id))
                    .azulFly(board.floor[i].id, in: space)
            } else {
                AzulSlot(lit: lit)
                    .overlay {
                        if compact {
                            Text(AzulRules.floorLabel(i))
                                .font(SR.Text.label())
                                .foregroundStyle(SR.inkGhost)
                                .lineLimit(1)
                                .minimumScaleFactor(0.4)
                                .padding(1)
                        }
                    }
            }
        }
    }

    /// What the floor costs now, in the cells past it.
    private var floorTotal: some View {
        Text(board.floorPenalty > 0 ? "−\(board.floorPenalty)" : "0")
            .font(SR.Text.figure(compact ? 15 : 18))
            .foregroundStyle(board.floorPenalty > 0 ? SR.error : SR.inkGhost)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .srNumeric(Double(board.floorPenalty))
            .accessibilityHidden(true)
    }

    private var floorLabels: some View {
        HStack(spacing: gap) {
            HStack(spacing: gap) {
                ForEach(0..<5, id: \.self) { i in floorLabel(i) }
            }
            Color.clear.frame(width: divide - gap * 2, height: 1)
            HStack(spacing: gap) {
                ForEach(5..<7, id: \.self) { i in floorLabel(i) }
                ForEach(0..<3, id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
            }
            .overlay(alignment: .trailing) {
                Text("FLOOR")
                    .font(SR.Text.label())
                    .tracking(1)
                    .foregroundStyle(SR.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .accessibilityHidden(true)
    }

    private func floorLabel(_ i: Int) -> some View {
        Text(AzulRules.floorLabel(i))
            .font(SR.Text.label())
            .foregroundStyle(i < board.floor.count ? SR.error : SR.inkMuted)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity)
    }

    private var floorSpoken: String {
        let n = board.floor.count
        let what = n == 0 ? "Floor, empty" : "Floor, \(n) \(n == 1 ? "tile" : "tiles")"
        return board.floorPenalty > 0 ? "\(what), costs \(board.floorPenalty)" : what
    }
}

/// "+3" over a wall tile placed this round, popping in.
struct AzulPointsBadge: View {
    let points: Int
    var delay: Double = 0

    var body: some View {
        Text("+\(points)")
            .font(SR.Text.label(12))
            .foregroundStyle(SR.paper)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(SR.accent))
            .offset(y: -10)
            .tablePopIn(delay: delay)
            .accessibilityHidden(true)
    }
}
