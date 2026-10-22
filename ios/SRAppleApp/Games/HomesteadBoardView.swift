import SwiftUI

// The island, drawn in one Canvas: hexes as paths in their tile colour with a
// small glyph (colour is never the only cue), number tokens (6 and 8 bolder),
// harbour piers, roads and buildings in each player's colour with their shape
// mark, the fox, and — when there is something to do — the lit spots from the
// server's legal lists. Pan with a drag, pinch to zoom (0.6× to 3×), double-tap
// to fit. A tap is matched to the nearest LIT spot only (`HomesteadTargets.hit`),
// so the board can never send a spot the server did not offer.

enum HomesteadPalette {
    static func colour(_ c: HomesteadColour?) -> Color {
        switch c {
        case .red?: return Color(hex: 0xD2453A)
        case .blue?: return Color(hex: 0x2F6FD0)
        case .amber?: return Color(hex: 0xE09A12)
        case .green?: return Color(hex: 0x2E8B47)
        case .purple?: return Color(hex: 0x8A4FC4)
        case nil: return Color(hex: 0x777777)
        }
    }

    static func tile(_ t: HomesteadTile) -> Color {
        switch t {
        case .woods: return Color(hex: 0x2F6B3A)
        case .claypit: return Color(hex: 0xB5643C)
        case .meadow: return Color(hex: 0x8DC26F)
        case .fields: return Color(hex: 0xE2C45A)
        case .quarry: return Color(hex: 0x8C8F96)
        case .dunes, .unknown: return Color(hex: 0xE9D9A8)
        }
    }

    /// The glyph on a tile: light on the dark tiles, dark on the light ones.
    static func glyph(_ t: HomesteadTile) -> Color {
        switch t {
        case .woods, .claypit, .quarry: return Color.white.opacity(0.85)
        default: return Color.black.opacity(0.55)
        }
    }

    static let sea = Color(hex: 0x4E97BD)
    static let seaDeep = Color(hex: 0x3A7FA6)
    static let outline = Color(hex: 0x2A2018)
    static let token = Color(hex: 0xFFF6E0)
    static let hot = Color(hex: 0xC0281D)
    static let lit = Color(hex: 0xFF8A00)
    static let fox = Color(hex: 0xE36A1E)
}

struct HomesteadBoardView: View {
    let state: HomesteadState
    var lit: [HomesteadTarget] = []
    var interactive: Bool = false
    var onTap: (HomesteadTarget) -> Void = { _ in }

    /// Board space: a hex's circumradius.
    static let unit: Double = 40

    @State private var zoom: Double = 1
    @State private var pan: CGSize = .zero
    @GestureState private var pinch: Double = 1
    @GestureState private var drag: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let viewport = makeViewport(geo.size)
            TimelineView(.animation(minimumInterval: 1.0 / 20, paused: lit.isEmpty || reduceMotion)) { timeline in
                let phase = reduceMotion ? 0.5 : (sin(timeline.date.timeIntervalSinceReferenceDate * 4) + 1) / 2
                Canvas { context, _ in
                    draw(in: &context, viewport, pulse: phase)
                }
            }
            .overlay { targetsForVoiceOver(viewport) }
            .contentShape(Rectangle())
            .gesture(taps(viewport))
            .simultaneousGesture(moves(viewport))
            .overlay(alignment: .bottomTrailing) { fitButton }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [HomesteadPalette.sea, HomesteadPalette.seaDeep], startPoint: .top, endPoint: .bottom))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(summary)
        .accessibilityIdentifier("homestead-board")
    }

    private func makeViewport(_ size: CGSize) -> HomesteadViewport {
        let s = Self.unit
        let bounds = state.board.bounds(size: s).insetBy(dx: -s * 0.7, dy: -s * 0.7)
        var v = HomesteadViewport(bounds: bounds, viewSize: size)
        v.zoom = HomesteadViewport.clampZoom(zoom * pinch)
        v.pan = v.clampedPan(CGSize(width: pan.width + drag.width, height: pan.height + drag.height))
        return v
    }

    // MARK: - Gestures

    private func taps(_ viewport: HomesteadViewport) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { _ in fit() }
            .exclusively(before: SpatialTapGesture(count: 1).onEnded { value in
                tap(at: value.location, viewport)
            })
    }

    private func moves(_ viewport: HomesteadViewport) -> some Gesture {
        let magnify = MagnifyGesture()
            .updating($pinch) { value, state, _ in state = Double(value.magnification) }
            .onEnded { value in zoom = HomesteadViewport.clampZoom(zoom * Double(value.magnification)) }
        let dragging = DragGesture(minimumDistance: 10)
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                pan = viewport.clampedPan(CGSize(width: pan.width + value.translation.width,
                                                 height: pan.height + value.translation.height))
            }
        return SimultaneousGesture(magnify, dragging)
    }

    private func tap(at location: CGPoint, _ viewport: HomesteadViewport) {
        guard interactive, !lit.isEmpty else { return }
        let point = viewport.toBoard(location)
        // 22 points on screen, whatever the zoom.
        let reach = 22 / max(0.01, viewport.scale)
        if let target = HomesteadTargets.hit(point, among: lit, size: Self.unit, reach: reach) {
            onTap(target)
        } else {
            SRHaptic.select()
        }
    }

    private func fit() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
            zoom = 1
            pan = .zero
        }
    }

    @ViewBuilder
    private var fitButton: some View {
        if zoom != 1 || pan != .zero {
            Button { fit() } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(SR.ink)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(SR.paper.opacity(0.92)))
            }
            .buttonStyle(.plain)
            .padding(8)
            .accessibilityLabel("Fit the island")
            .accessibilityIdentifier("homestead-fit")
        }
    }

    // MARK: - VoiceOver

    /// Each lit spot as its own element, where it is drawn: "Cottage spot,
    /// fields 8 and quarry 5". Not hit-testable: a finger's tap goes through
    /// the gesture above; VoiceOver's activate goes through the action.
    private func targetsForVoiceOver(_ viewport: HomesteadViewport) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(interactive ? lit : [], id: \.self) { target in
                if let p = HomesteadTargets.point(target, size: Self.unit) {
                    let at = viewport.toScreen(p)
                    Color.clear
                        .frame(width: 30, height: 30)
                        .position(x: at.x, y: at.y)
                        .accessibilityElement()
                        .accessibilityLabel(HomesteadTargets.spoken(target, in: state))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { onTap(target) }
                        .accessibilityIdentifier("homestead-spot-\(target.tool.rawValue)-\(target.id)")
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var summary: String {
        var bits = ["The island, \(state.board.hexes.count) hexes"]
        if let fox = state.fox, let hex = state.board.hex(fox) { bits.append("the fox is on \(hex.spoken)") }
        let mine = state.buildings.filter { $0.owner == state.meId }
        if !mine.isEmpty {
            let cottages = mine.filter { $0.piece == .cottage }.count
            let towns = mine.filter { $0.piece == .town }.count
            bits.append("you have \(cottages) \(cottages == 1 ? "cottage" : "cottages") and \(towns) \(towns == 1 ? "town" : "towns")")
        }
        if interactive, !lit.isEmpty { bits.append("\(lit.count) spots lit") }
        return bits.joined(separator: ", ")
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, _ v: HomesteadViewport, pulse: Double) {
        let s = Self.unit
        let k = v.scale
        let board = state.board
        let litFox = Set(lit.filter { $0.tool == .fox }.map(\.id))

        // Hexes.
        for hex in board.hexes {
            let corners = HomesteadPixels.outline(hex.coord, size: s).map { v.toScreen($0) }
            var path = Path()
            path.addLines(corners)
            path.closeSubpath()
            context.fill(path, with: .color(HomesteadPalette.tile(hex.tile)))
            context.stroke(path, with: .color(HomesteadPalette.outline.opacity(0.55)), lineWidth: max(1, 1.4 * k / 1.2))
            let centre = v.toScreen(HomesteadPixels.centre(hex.coord, size: s))
            // The glyph, above the token.
            let glyphSize = max(8, s * 0.32 * k)
            let glyph = Text(Image(systemName: hex.tile.symbol))
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundColor(HomesteadPalette.glyph(hex.tile))
            context.draw(glyph, at: CGPoint(x: centre.x, y: centre.y - s * 0.48 * k))
            if let token = hex.token {
                drawToken(token, hot: hex.hot, pips: hex.pips, at: centre, k: k, in: &context)
            }
            if litFox.contains(hex.id) {
                var ring = path
                ring = ring.strokedPath(StrokeStyle(lineWidth: max(2, 3 * k / 1.2), dash: [6, 4]))
                context.fill(ring, with: .color(HomesteadPalette.lit.opacity(0.55 + 0.45 * pulse)))
            }
        }

        // Harbours.
        for harbour in board.harbours {
            guard let edge = HomesteadEdge(id: harbour.edge), let shore = board.shoreHex(of: edge) else { continue }
            let (a, b) = edge.ends
            let pa = HomesteadPixels.point(a, size: s)
            let pb = HomesteadPixels.point(b, size: s)
            let mid = HomesteadPixels.midpoint(edge, size: s)
            let c = HomesteadPixels.centre(shore.coord, size: s)
            let dx = Double(mid.x - c.x), dy = Double(mid.y - c.y)
            let len = max(0.001, (dx * dx + dy * dy).squareRoot())
            let ux = dx / len, uy = dy / len
            let dock = CGPoint(x: Double(mid.x) + ux * s * 0.55, y: Double(mid.y) + uy * s * 0.55)
            var pier = Path()
            pier.move(to: v.toScreen(pa)); pier.addLine(to: v.toScreen(dock))
            pier.move(to: v.toScreen(pb)); pier.addLine(to: v.toScreen(dock))
            context.stroke(pier, with: .color(Color(hex: 0x8A6A3F)), style: StrokeStyle(lineWidth: max(2, 0.09 * s * k), lineCap: .round))
            let label = CGPoint(x: Double(dock.x) + ux * s * 0.32, y: Double(dock.y) + uy * s * 0.32)
            let at = v.toScreen(label)
            let fontSize = max(8, s * 0.24 * k)
            let bubble = CGRect(x: at.x - fontSize * 1.6, y: at.y - fontSize * 0.8, width: fontSize * 3.2, height: fontSize * 1.6)
            context.fill(Path(roundedRect: bubble, cornerRadius: fontSize * 0.5), with: .color(Color.white.opacity(0.9)))
            var text = Text("\(harbour.rate):1").font(.system(size: fontSize, weight: .bold, design: .rounded))
            if let r = harbour.resource {
                text = text + Text(" ") + Text(Image(systemName: r.symbol)).font(.system(size: fontSize * 0.9))
            }
            context.draw(text.foregroundColor(Color(hex: 0x2A2018)), at: at)
        }

        // Roads.
        for road in state.roads {
            guard let edge = HomesteadEdge(id: road.at) else { continue }
            let (a, b) = edge.ends
            let pa = v.toScreen(HomesteadPixels.point(a, size: s))
            let pb = v.toScreen(HomesteadPixels.point(b, size: s))
            let inset = 0.16
            let qa = CGPoint(x: pa.x + (pb.x - pa.x) * inset, y: pa.y + (pb.y - pa.y) * inset)
            let qb = CGPoint(x: pb.x + (pa.x - pb.x) * inset, y: pb.y + (pa.y - pb.y) * inset)
            var line = Path()
            line.move(to: qa)
            line.addLine(to: qb)
            let width = max(3, 0.17 * s * k)
            context.stroke(line, with: .color(HomesteadPalette.outline), style: StrokeStyle(lineWidth: width + 2.5, lineCap: .round))
            context.stroke(line, with: .color(HomesteadPalette.colour(state.colour(of: road.owner))),
                           style: StrokeStyle(lineWidth: width, lineCap: .round))
        }

        // Lit road spots.
        for target in lit where target.tool == .road {
            guard let edge = HomesteadEdge(id: target.id) else { continue }
            let (a, b) = edge.ends
            var line = Path()
            line.move(to: v.toScreen(HomesteadPixels.point(a, size: s)))
            line.addLine(to: v.toScreen(HomesteadPixels.point(b, size: s)))
            context.stroke(line, with: .color(HomesteadPalette.lit.opacity(0.5 + 0.5 * pulse)),
                           style: StrokeStyle(lineWidth: max(4, 0.2 * s * k), lineCap: .round, dash: [CGFloat(max(4, 0.18 * s * k)), CGFloat(max(3, 0.12 * s * k))]))
        }

        // Buildings.
        for building in state.buildings {
            guard let vertex = HomesteadVertex(id: building.at) else { continue }
            let p = v.toScreen(HomesteadPixels.point(vertex, size: s))
            let colour = state.colour(of: building.owner)
            drawBuilding(building.piece, colour: colour, at: p, size: max(7, s * 0.3 * k), in: &context)
        }

        // Lit corner spots: rings (a town spot rings its own cottage).
        for target in lit where target.tool == .cottage || target.tool == .town {
            guard let vertex = HomesteadVertex(id: target.id) else { continue }
            let p = v.toScreen(HomesteadPixels.point(vertex, size: s))
            let r = max(7, s * (target.tool == .town ? 0.46 : 0.26) * k) * (0.9 + 0.2 * pulse)
            let ring = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            if target.tool == .cottage {
                context.fill(ring, with: .color(Color.white.opacity(0.55)))
            }
            context.stroke(ring, with: .color(HomesteadPalette.lit.opacity(0.6 + 0.4 * pulse)), lineWidth: max(2, 0.08 * s * k))
        }

        // The fox.
        if let fox = state.fox, let coord = HexCoord(id: fox), board.hex(fox) != nil {
            let c = v.toScreen(HomesteadPixels.centre(coord, size: s))
            let r = max(9, s * 0.36 * k)
            let at = CGPoint(x: c.x + s * 0.5 * k, y: c.y + s * 0.42 * k)
            let disc = Path(ellipseIn: CGRect(x: at.x - r, y: at.y - r, width: 2 * r, height: 2 * r))
            context.fill(disc, with: .color(HomesteadPalette.outline.opacity(0.88)))
            context.stroke(disc, with: .color(HomesteadPalette.fox), lineWidth: max(1.5, r * 0.14))
            let paw = Text(Image(systemName: "pawprint.fill")).font(.system(size: r * 1.05, weight: .bold)).foregroundColor(HomesteadPalette.fox)
            context.draw(paw, at: at)
        }
    }

    private func drawToken(_ token: Int, hot: Bool, pips: Int, at centre: CGPoint, k: Double, in context: inout GraphicsContext) {
        let s = Self.unit
        let r = max(8, s * 0.34 * k)
        let at = CGPoint(x: centre.x, y: centre.y + s * 0.12 * k)
        let disc = Path(ellipseIn: CGRect(x: at.x - r, y: at.y - r, width: 2 * r, height: 2 * r))
        context.fill(disc, with: .color(HomesteadPalette.token))
        context.stroke(disc, with: .color(HomesteadPalette.outline.opacity(0.5)), lineWidth: max(0.8, r * 0.07))
        let number = Text("\(token)")
            .font(.system(size: r * (hot ? 1.05 : 0.95), weight: hot ? .heavy : .semibold, design: .rounded))
            .foregroundColor(hot ? HomesteadPalette.hot : HomesteadPalette.outline)
        context.draw(number, at: CGPoint(x: at.x, y: at.y - r * 0.12))
        // Pips under the number: chances in 36.
        guard pips > 0 else { return }
        let dot = max(1.2, r * 0.09)
        let gap = dot * 2.6
        let start = at.x - gap * Double(pips - 1) / 2
        for i in 0..<pips {
            let x = start + gap * Double(i)
            let y = at.y + r * 0.58
            context.fill(Path(ellipseIn: CGRect(x: x - dot, y: y - dot, width: 2 * dot, height: 2 * dot)),
                         with: .color(hot ? HomesteadPalette.hot : HomesteadPalette.outline))
        }
    }

    private func drawBuilding(_ piece: HomesteadPiece, colour: HomesteadColour?, at p: CGPoint, size h: Double,
                              in context: inout GraphicsContext) {
        let path = HomesteadShapes.building(piece, at: p, size: h)
        context.fill(path, with: .color(HomesteadPalette.colour(colour)))
        context.stroke(path, with: .color(HomesteadPalette.outline), lineWidth: max(1.2, h * 0.12))
        if let mark = colour?.mark {
            let markPath = HomesteadShapes.mark(mark, at: CGPoint(x: p.x, y: p.y + h * 0.18), size: h * 0.42)
            context.fill(markPath, with: .color(Color.white.opacity(0.95)))
        }
    }
}

/// The pieces' and marks' outlines, shared by the board and the strip.
enum HomesteadShapes {
    /// A cottage is a little house; a town is a wider one with a tower.
    static func building(_ piece: HomesteadPiece, at p: CGPoint, size h: Double) -> Path {
        var path = Path()
        switch piece {
        case .town:
            let w = h * 1.5
            path.move(to: CGPoint(x: p.x - w / 2, y: p.y + h * 0.7))
            path.addLine(to: CGPoint(x: p.x - w / 2, y: p.y - h * 0.1))
            path.addLine(to: CGPoint(x: p.x - w * 0.1, y: p.y - h * 0.1))
            path.addLine(to: CGPoint(x: p.x - w * 0.1, y: p.y - h * 0.55))
            path.addLine(to: CGPoint(x: p.x + w * 0.2, y: p.y - h * 0.95))
            path.addLine(to: CGPoint(x: p.x + w / 2, y: p.y - h * 0.55))
            path.addLine(to: CGPoint(x: p.x + w / 2, y: p.y + h * 0.7))
            path.closeSubpath()
        case .cottage, .road:
            let w = h * 1.05
            path.move(to: CGPoint(x: p.x - w / 2, y: p.y + h * 0.6))
            path.addLine(to: CGPoint(x: p.x - w / 2, y: p.y - h * 0.1))
            path.addLine(to: CGPoint(x: p.x, y: p.y - h * 0.7))
            path.addLine(to: CGPoint(x: p.x + w / 2, y: p.y - h * 0.1))
            path.addLine(to: CGPoint(x: p.x + w / 2, y: p.y + h * 0.6))
            path.closeSubpath()
        }
        return path
    }

    static func mark(_ mark: HomesteadMark, at p: CGPoint, size d: Double) -> Path {
        let r = d / 2
        switch mark {
        case .circle:
            return Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: d, height: d))
        case .square:
            return Path(CGRect(x: p.x - r * 0.85, y: p.y - r * 0.85, width: d * 0.85, height: d * 0.85))
        case .triangle:
            var path = Path()
            path.move(to: CGPoint(x: p.x, y: p.y - r))
            path.addLine(to: CGPoint(x: p.x + r, y: p.y + r * 0.8))
            path.addLine(to: CGPoint(x: p.x - r, y: p.y + r * 0.8))
            path.closeSubpath()
            return path
        case .diamond:
            var path = Path()
            path.move(to: CGPoint(x: p.x, y: p.y - r))
            path.addLine(to: CGPoint(x: p.x + r, y: p.y))
            path.addLine(to: CGPoint(x: p.x, y: p.y + r))
            path.addLine(to: CGPoint(x: p.x - r, y: p.y))
            path.closeSubpath()
            return path
        case .cross:
            let t = r * 0.38
            var path = Path()
            path.addRect(CGRect(x: p.x - r, y: p.y - t, width: d, height: 2 * t))
            path.addRect(CGRect(x: p.x - t, y: p.y - r, width: 2 * t, height: d))
            return path
        }
    }
}

/// A player's colour with their shape mark — beside a name, in the strip.
struct HomesteadSeatMark: View {
    let colour: HomesteadColour?
    var side: CGFloat = 22

    var body: some View {
        Canvas { context, size in
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let disc = Path(ellipseIn: CGRect(origin: .zero, size: size))
            context.fill(disc, with: .color(HomesteadPalette.colour(colour)))
            if let mark = colour?.mark {
                context.fill(HomesteadShapes.mark(mark, at: centre, size: Double(size.width) * 0.48), with: .color(.white))
            }
        }
        .frame(width: side, height: side)
        .accessibilityLabel(colour.map { "\($0.label), \($0.mark.spoken)" } ?? "No seat")
    }
}

// MARK: - Dice

/// Two dice. When a new roll lands they tumble for ~0.8 s, then settle on the
/// server's faces. Reduce Motion: no tumble.
struct HomesteadDiceView: View {
    let dice: HomesteadDice?
    /// Bumped by the store each time `dice.at` changes.
    let serial: Int
    var side: CGFloat = 38

    @State private var shown: (Int, Int)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            HomesteadDieFace(value: shown?.0 ?? dice?.a ?? 1, side: side, faded: dice == nil)
            HomesteadDieFace(value: shown?.1 ?? dice?.b ?? 1, side: side, faded: dice == nil)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dice.map { "Dice: \($0.a) and \($0.b), \($0.total)" } ?? "Not rolled yet")
        .accessibilityIdentifier("homestead-dice")
        .task(id: serial) {
            guard serial > 0, !reduceMotion else { return }
            for _ in 0..<8 {
                shown = (Int.random(in: 1...6), Int.random(in: 1...6))
                try? await Task.sleep(nanoseconds: 100_000_000)
                if Task.isCancelled { break }
            }
            shown = nil
        }
    }
}

struct HomesteadDieFace: View {
    let value: Int
    let side: CGFloat
    var faded = false

    /// Pip positions on a 3×3 grid, by face.
    private var pips: [(Int, Int)] {
        switch value {
        case 1: return [(1, 1)]
        case 2: return [(0, 0), (2, 2)]
        case 3: return [(0, 0), (1, 1), (2, 2)]
        case 4: return [(0, 0), (2, 0), (0, 2), (2, 2)]
        case 5: return [(0, 0), (2, 0), (1, 1), (0, 2), (2, 2)]
        default: return [(0, 0), (2, 0), (0, 1), (2, 1), (0, 2), (2, 2)]
        }
    }

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            let face = Path(roundedRect: rect, cornerRadius: size.width * 0.2)
            context.fill(face, with: .color(Color(hex: 0xFFF6E0)))
            context.stroke(face, with: .color(HomesteadPalette.outline.opacity(0.6)), lineWidth: 1.2)
            let step = size.width / 4
            let r = size.width * 0.085
            for (col, row) in pips {
                let x = step * CGFloat(col + 1)
                let y = step * CGFloat(row + 1)
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)),
                             with: .color(HomesteadPalette.outline))
            }
        }
        .frame(width: side, height: side)
        .opacity(faded ? 0.4 : 1)
    }
}
