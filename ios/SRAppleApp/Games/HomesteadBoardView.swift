import SwiftUI

// The island, drawn in one Canvas: a sea with a few wave marks, a beach and a
// line of surf round the coast, then each hex lit from above (a light-to-dark
// fill and a bevel) with its own little scenery — trees in the woods, sheep
// in the meadow, wheat in the fields, bricks in the clay pit, rocks in the
// quarry, ripples in the dunes — and its SF Symbol glyph, so colour is never
// the only cue. Number tokens sit on a shadow (6 and 8 bolder and red),
// harbour piers point out to sea, roads are planks in each player's colour,
// cottages and towns stand on a shadow with a darker roof and the owner's
// shape mark, and the fox is a fox. When there is something to do the lit
// spots from the server's legal lists pulse.
//
// Two moments move on their own, briefly: a roll's paying hexes glow gold and
// ring outwards, and a piece that has just appeared pops and rings in its
// owner's colour. Both run on the TimelineView's display clock only while they
// last (and while spots are lit), pause in the background, and are still
// frames under Reduce Motion. The hexes that paid out on the dice showing keep
// a thin gold rim, which is not an animation.
//
// Pan with a drag, pinch to zoom (0.6× to 3×), double-tap to fit. A tap is
// matched to the nearest LIT spot only (`HomesteadTargets.hit`), so the board
// can never send a spot the server did not offer.

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

    /// The top of a hex, where the light falls.
    static func tileLight(_ t: HomesteadTile) -> Color {
        switch t {
        case .woods: return Color(hex: 0x3F8A4C)
        case .claypit: return Color(hex: 0xCB7C52)
        case .meadow: return Color(hex: 0xA7D88A)
        case .fields: return Color(hex: 0xF0D97E)
        case .quarry: return Color(hex: 0xA5A8AF)
        case .dunes, .unknown: return Color(hex: 0xF4E9C6)
        }
    }

    /// The foot of a hex, in its own shadow.
    static func tileDark(_ t: HomesteadTile) -> Color {
        switch t {
        case .woods: return Color(hex: 0x23522C)
        case .claypit: return Color(hex: 0x8E4A2A)
        case .meadow: return Color(hex: 0x6EA351)
        case .fields: return Color(hex: 0xC6A53C)
        case .quarry: return Color(hex: 0x6E7178)
        case .dunes, .unknown: return Color(hex: 0xD4C088)
        }
    }

    /// The scenery drawn on a hex: trees, bricks, wheat and so on.
    static func scenery(_ t: HomesteadTile) -> Color {
        switch t {
        case .woods: return Color(hex: 0x163C1E)
        case .claypit: return Color(hex: 0x7A3518)
        case .meadow: return Color(hex: 0xFFFFFF)
        case .fields: return Color(hex: 0x9C7A14)
        case .quarry: return Color(hex: 0x50535A)
        case .dunes, .unknown: return Color(hex: 0xB89C5C)
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
    static let seaDeep = Color(hex: 0x2F6E96)
    static let sand = Color(hex: 0xE9D6A4)
    static let outline = Color(hex: 0x2A2018)
    static let token = Color(hex: 0xFFF6E0)
    static let hot = Color(hex: 0xC0281D)
    static let lit = Color(hex: 0xFF8A00)
    static let fox = Color(hex: 0xE36A1E)
    static let gold = Color(hex: 0xFFC83D)
    static let trunk = Color(hex: 0x5A3A1E)
    static let pier = Color(hex: 0x8A6A3F)
}

/// One frame's moving parts: the lit spots' pulse (0…1), and how far through
/// the roll's glow and the new pieces' pop we are (0…1, nil when not running).
struct HomesteadBoardFrame {
    var pulse: Double
    var roll: Double?
    var fresh: Double?
    /// The dice are still tumbling: keep which hexes paid a secret until they land.
    var rollPending: Bool = false

    static let still = HomesteadBoardFrame(pulse: 0.5, roll: nil, fresh: nil)
}

struct HomesteadBoardView: View {
    let state: HomesteadState
    var lit: [HomesteadTarget] = []
    var interactive: Bool = false
    /// Light the hexes the dice paid out on; off for the island at the end.
    var showsRoll: Bool = true
    var onTap: (HomesteadTarget) -> Void = { _ in }

    /// Board space: a hex's circumradius.
    static let unit: Double = 40
    /// How long a roll's glow lasts, and a new piece's pop.
    static let rollGlow: Double = 2.2
    static let freshPop: Double = 0.9

    @State private var zoom: Double = 1
    @State private var pan: CGSize = .zero
    @GestureState private var pinch: Double = 1
    @GestureState private var drag: CGSize = .zero
    /// When the dice last landed (the glow's start), nil when it has faded.
    @State private var rollAt: Date?
    /// The pieces on the board last time, and the ones that have just appeared.
    @State private var seenPieces: Set<String> = []
    @State private var freshPieces: Set<String> = []
    @State private var freshAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geo in
            let viewport = makeViewport(geo.size)
            TimelineView(.animation(minimumInterval: frameInterval, paused: !animating)) { timeline in
                let moment = boardFrame(at: timeline.date)
                Canvas { context, _ in
                    draw(in: &context, viewport, frame: moment)
                }
            }
            .overlay { targetsForVoiceOver(viewport) }
            .contentShape(Rectangle())
            .gesture(taps(viewport))
            .simultaneousGesture(moves(viewport))
            .overlay(alignment: .bottomTrailing) { fitButton }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [HomesteadPalette.sea, HomesteadPalette.seaDeep], startPoint: .top, endPoint: .bottom))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.black.opacity(0.14), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(summary)
        .accessibilityIdentifier("homestead-board")
        .onAppear { seenPieces = pieceKeys }
        .onChange(of: state.dice?.at) { _, _ in rollLanded() }
        .onChange(of: pieceKeys) { _, keys in piecesChanged(keys) }
        .task(id: rollAt) {
            guard rollAt != nil else { return }
            let wait = HomesteadDiceView.tumbleTime + Self.rollGlow
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            if !Task.isCancelled { rollAt = nil }
        }
        .task(id: freshAt) {
            guard freshAt != nil else { return }
            try? await Task.sleep(nanoseconds: UInt64(Self.freshPop * 1_000_000_000))
            if !Task.isCancelled {
                freshAt = nil
                freshPieces = []
            }
        }
    }

    private func makeViewport(_ size: CGSize) -> HomesteadViewport {
        let s = Self.unit
        let bounds = state.board.bounds(size: s).insetBy(dx: -s * 0.7, dy: -s * 0.7)
        var v = HomesteadViewport(bounds: bounds, viewSize: size)
        v.zoom = HomesteadViewport.clampZoom(zoom * pinch)
        v.pan = v.clampedPan(CGSize(width: pan.width + drag.width, height: pan.height + drag.height))
        return v
    }

    // MARK: - The clock

    /// The display clock runs only while something moves: lit spots, a roll's
    /// glow or a new piece's pop — and never in the background.
    private var animating: Bool {
        guard !reduceMotion, scenePhase == .active else { return false }
        return !lit.isEmpty || rollAt != nil || freshAt != nil
    }

    /// 30 fps for a roll's glow or a pop; a gentler 20 for the lit spots'
    /// pulse, which can run for as long as a player thinks.
    private var frameInterval: Double {
        rollAt != nil || freshAt != nil ? 1.0 / 30 : 1.0 / 20
    }

    private func boardFrame(at date: Date) -> HomesteadBoardFrame {
        if reduceMotion { return .still }
        let t = date.timeIntervalSinceReferenceDate
        var moment = HomesteadBoardFrame(pulse: (sin(t * 4) + 1) / 2, roll: nil, fresh: nil)
        if let rollAt {
            // `rollAt` is when the dice land, a moment after the roll arrives.
            let p = date.timeIntervalSince(rollAt) / Self.rollGlow
            if p < 0 { moment.rollPending = true }
            if p >= 0, p < 1 { moment.roll = p }
        }
        if let freshAt {
            let p = date.timeIntervalSince(freshAt) / Self.freshPop
            if p >= 0, p < 1 { moment.fresh = p }
        }
        return moment
    }

    /// Every piece on the board, as one key each: a cottage that becomes a
    /// town is a new key, and pops.
    private var pieceKeys: Set<String> { HomesteadMoments.pieceKeys(state) }

    private func rollLanded() {
        guard showsRoll, !reduceMotion, state.dice != nil else { return }
        // The glow starts as the dice land, not while they tumble.
        rollAt = Date().addingTimeInterval(HomesteadDiceView.tumbleTime)
    }

    private func piecesChanged(_ keys: Set<String>) {
        let added = HomesteadMoments.fresh(previous: seenPieces, now: keys)
        seenPieces = keys
        // A handful is a move; dozens at once is the room being re-read.
        guard !reduceMotion, let added else { return }
        freshPieces = added
        freshAt = Date()
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
        // 24 points on screen, whatever the zoom.
        let reach = 24 / max(0.01, viewport.scale)
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
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(SR.ink)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(SR.surface.opacity(0.94)))
                    .overlay(Circle().strokeBorder(SR.line, lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(SRPressStyle())
            .padding(10)
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

    private func draw(in context: inout GraphicsContext, _ v: HomesteadViewport, frame: HomesteadBoardFrame) {
        let board = state.board
        drawWaves(in: &context, v)
        drawShore(in: &context, v)
        for hex in board.hexes {
            drawHex(hex, in: &context, v)
        }
        drawRollGlow(in: &context, v, frame: frame)
        drawLitFox(in: &context, v, pulse: frame.pulse)
        drawHarbours(in: &context, v)
        drawRoads(in: &context, v, frame: frame)
        drawLitRoads(in: &context, v, pulse: frame.pulse)
        drawBuildings(in: &context, v, frame: frame)
        drawLitCorners(in: &context, v, pulse: frame.pulse)
        drawFreshRings(in: &context, v, frame: frame)
        drawFox(in: &context, v)
    }

    /// A steady 0..<1 from two integers, for the waves' places.
    private static func scatter(_ i: Int, _ salt: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: (i &* 73_856_093) ^ (salt &* 19_349_663))
        x ^= x >> 13
        x = x &* 0x5BD1_E995
        x ^= x >> 15
        return Double(x % 10_000) / 10_000
    }

    /// A few pale wave marks out at sea, fixed to the board so they pan with it.
    private func drawWaves(in context: inout GraphicsContext, _ v: HomesteadViewport) {
        let s = Self.unit
        let k = v.scale
        let box = v.bounds.insetBy(dx: -s * 1.5, dy: -s * 1.5)
        let land = state.board.hexes.map { HomesteadPixels.centre($0.coord, size: s) }
        let w = max(4, s * 0.16 * k)
        var waves = Path()
        for i in 0..<34 {
            let bx = Double(box.minX) + Double(box.width) * Self.scatter(i, 1)
            let by = Double(box.minY) + Double(box.height) * Self.scatter(i, 2)
            let p = CGPoint(x: bx, y: by)
            if land.contains(where: { HomesteadPixels.distance($0, p) < s * 1.3 }) { continue }
            let at = v.toScreen(p)
            let x = Double(at.x), y = Double(at.y)
            waves.move(to: CGPoint(x: x - w, y: y))
            waves.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x - w / 2, y: y - w * 0.6))
            waves.addQuadCurve(to: CGPoint(x: x + w, y: y), control: CGPoint(x: x + w / 2, y: y - w * 0.6))
        }
        context.stroke(waves, with: .color(Color.white.opacity(0.28)),
                       style: StrokeStyle(lineWidth: max(1, 0.035 * s * k), lineCap: .round))
    }

    /// One hex's outline on screen, scaled about its centre (1 = the hex itself).
    private func outline(_ hex: HexCoord, _ v: HomesteadViewport, scale: Double) -> Path {
        let s = Self.unit
        let c = v.toScreen(HomesteadPixels.centre(hex, size: s))
        let cx = Double(c.x), cy = Double(c.y)
        let corners = HomesteadPixels.outline(hex, size: s).map { p -> CGPoint in
            let q = v.toScreen(p)
            return CGPoint(x: cx + (Double(q.x) - cx) * scale, y: cy + (Double(q.y) - cy) * scale)
        }
        var path = Path()
        path.addLines(corners)
        path.closeSubpath()
        return path
    }

    /// Surf, then a beach, round every hex: the inland ones are hidden under
    /// their neighbours, so only the coast shows.
    private func drawShore(in context: inout GraphicsContext, _ v: HomesteadViewport) {
        let k = v.scale
        var surf = Path()
        var beach = Path()
        for hex in state.board.hexes {
            surf.addPath(outline(hex.coord, v, scale: 1.24))
            beach.addPath(outline(hex.coord, v, scale: 1.13))
        }
        context.stroke(surf, with: .color(Color.white.opacity(0.4)), lineWidth: max(1, 2.2 * k))
        context.fill(beach, with: .color(HomesteadPalette.sand))
    }

    private func drawHex(_ hex: HomesteadHex, in context: inout GraphicsContext, _ v: HomesteadViewport) {
        let s = Self.unit
        let k = v.scale
        let radius = s * k
        let path = outline(hex.coord, v, scale: 1)
        let centre = v.toScreen(HomesteadPixels.centre(hex.coord, size: s))
        let cx = Double(centre.x), cy = Double(centre.y)
        let light = Gradient(colors: [HomesteadPalette.tileLight(hex.tile), HomesteadPalette.tileDark(hex.tile)])
        context.fill(path, with: .linearGradient(light, startPoint: CGPoint(x: cx, y: cy - radius),
                                                  endPoint: CGPoint(x: cx, y: cy + radius)))
        if radius >= 14 {
            drawScenery(hex.tile, cx: cx, cy: cy, radius: radius, hasToken: hex.token != nil, in: &context)
        }
        // A bevel: light on the inside edge, then the outline.
        context.stroke(outline(hex.coord, v, scale: 0.93), with: .color(Color.white.opacity(0.16)), lineWidth: max(1, 0.05 * radius))
        context.stroke(path, with: .color(HomesteadPalette.outline.opacity(0.55)), lineWidth: max(1, 1.4 * k / 1.2))
        // The glyph, above the token.
        let glyphSize = max(8, s * 0.32 * k)
        let glyph = Text(Image(systemName: hex.tile.symbol))
            .font(.system(size: glyphSize, weight: .semibold))
            .foregroundColor(HomesteadPalette.glyph(hex.tile))
        context.draw(glyph, at: CGPoint(x: cx, y: cy - s * 0.48 * k))
        if let token = hex.token {
            drawToken(token, hot: hex.hot, pips: hex.pips, at: centre, k: k, in: &context)
        }
        // The fox's hex is in shadow: it pays nobody.
        if let fox = state.fox, fox == hex.id {
            context.fill(path, with: .color(Color.black.opacity(0.24)))
        }
    }

    /// The little scenery on a hex, either side of its token.
    private func drawScenery(_ tile: HomesteadTile, cx: Double, cy: Double, radius r: Double, hasToken: Bool,
                             in context: inout GraphicsContext) {
        var spots: [(Double, Double)] = [(-0.56, 0.1), (0.56, 0.1), (-0.4, -0.44), (0.4, -0.44)]
        if !hasToken { spots.append((0, 0.2)) }
        let d = r * 0.12
        let colour = HomesteadPalette.scenery(tile)
        for (sx, sy) in spots {
            let x = cx + sx * r
            let y = cy + sy * r
            switch tile {
            case .woods: drawTree(x, y, d, colour, in: &context)
            case .meadow: drawSheep(x, y, d, in: &context)
            case .fields: drawWheat(x, y, d, colour, in: &context)
            case .claypit: drawBricks(x, y, d, colour, in: &context)
            case .quarry: drawRock(x, y, d, colour, in: &context)
            case .dunes, .unknown: drawRipple(x, y, d, colour, in: &context)
            }
        }
    }

    private func drawTree(_ x: Double, _ y: Double, _ d: Double, _ colour: Color, in context: inout GraphicsContext) {
        context.fill(Path(CGRect(x: x - d * 0.18, y: y + d * 0.5, width: d * 0.36, height: d * 0.55)),
                     with: .color(HomesteadPalette.trunk))
        var tree = Path()
        tree.move(to: CGPoint(x: x, y: y - d * 1.45))
        tree.addLine(to: CGPoint(x: x + d * 0.95, y: y + d * 0.6))
        tree.addLine(to: CGPoint(x: x - d * 0.95, y: y + d * 0.6))
        tree.closeSubpath()
        context.fill(tree, with: .color(colour))
    }

    private func drawSheep(_ x: Double, _ y: Double, _ d: Double, in context: inout GraphicsContext) {
        context.fill(Path(ellipseIn: CGRect(x: x - d * 1.0, y: y - d * 0.6, width: d * 1.9, height: d * 1.25)),
                     with: .color(Color.white.opacity(0.95)))
        context.fill(Path(ellipseIn: CGRect(x: x + d * 0.55, y: y - d * 0.75, width: d * 0.75, height: d * 0.75)),
                     with: .color(Color(hex: 0x3A3330)))
    }

    private func drawWheat(_ x: Double, _ y: Double, _ d: Double, _ colour: Color, in context: inout GraphicsContext) {
        var stalks = Path()
        var ears = Path()
        for i in -1...1 {
            let sx = x + Double(i) * d * 0.55
            stalks.move(to: CGPoint(x: sx, y: y + d * 0.9))
            stalks.addLine(to: CGPoint(x: sx, y: y - d * 0.3))
            ears.addEllipse(in: CGRect(x: sx - d * 0.2, y: y - d * 1.05, width: d * 0.4, height: d * 0.85))
        }
        context.stroke(stalks, with: .color(colour), lineWidth: max(0.8, d * 0.16))
        context.fill(ears, with: .color(colour))
    }

    private func drawBricks(_ x: Double, _ y: Double, _ d: Double, _ colour: Color, in context: inout GraphicsContext) {
        var bricks = Path()
        bricks.addRoundedRect(in: CGRect(x: x - d * 1.0, y: y - d * 0.1, width: d * 0.95, height: d * 0.55), cornerSize: CGSize(width: d * 0.1, height: d * 0.1))
        bricks.addRoundedRect(in: CGRect(x: x + d * 0.05, y: y - d * 0.1, width: d * 0.95, height: d * 0.55), cornerSize: CGSize(width: d * 0.1, height: d * 0.1))
        bricks.addRoundedRect(in: CGRect(x: x - d * 0.47, y: y - d * 0.72, width: d * 0.95, height: d * 0.55), cornerSize: CGSize(width: d * 0.1, height: d * 0.1))
        context.fill(bricks, with: .color(colour))
    }

    private func drawRock(_ x: Double, _ y: Double, _ d: Double, _ colour: Color, in context: inout GraphicsContext) {
        var rock = Path()
        rock.move(to: CGPoint(x: x - d * 1.0, y: y + d * 0.6))
        rock.addLine(to: CGPoint(x: x - d * 0.6, y: y - d * 0.4))
        rock.addLine(to: CGPoint(x: x + d * 0.1, y: y - d * 0.85))
        rock.addLine(to: CGPoint(x: x + d * 0.9, y: y - d * 0.2))
        rock.addLine(to: CGPoint(x: x + d * 1.0, y: y + d * 0.6))
        rock.closeSubpath()
        context.fill(rock, with: .color(colour))
        var shine = Path()
        shine.move(to: CGPoint(x: x - d * 0.55, y: y - d * 0.3))
        shine.addLine(to: CGPoint(x: x + d * 0.1, y: y - d * 0.72))
        context.stroke(shine, with: .color(Color.white.opacity(0.5)), lineWidth: max(0.8, d * 0.18))
    }

    private func drawRipple(_ x: Double, _ y: Double, _ d: Double, _ colour: Color, in context: inout GraphicsContext) {
        var ripple = Path()
        for row in 0..<2 {
            let ry = y + Double(row) * d * 0.7 - d * 0.35
            ripple.move(to: CGPoint(x: x - d, y: ry))
            ripple.addQuadCurve(to: CGPoint(x: x + d, y: ry), control: CGPoint(x: x, y: ry - d * 0.7))
        }
        context.stroke(ripple, with: .color(colour), style: StrokeStyle(lineWidth: max(0.8, d * 0.2), lineCap: .round))
    }

    /// The hexes the dice now showing paid out on: a gold rim always, and for
    /// a moment after the roll, a glow that rings outwards.
    private func drawRollGlow(in context: inout GraphicsContext, _ v: HomesteadViewport, frame: HomesteadBoardFrame) {
        guard showsRoll, !frame.rollPending else { return }
        let k = v.scale
        let radius = Self.unit * k
        for hex in HomesteadMoments.paying(state) {
            let path = outline(hex.coord, v, scale: 1)
            if let p = frame.roll {
                context.fill(path, with: .color(HomesteadPalette.gold.opacity(0.42 * (1 - p))))
                let ring = outline(hex.coord, v, scale: 1 + 0.3 * p)
                context.stroke(ring, with: .color(HomesteadPalette.gold.opacity(1 - p)), lineWidth: max(2, 0.1 * radius * (1 - p)))
            }
            context.stroke(outline(hex.coord, v, scale: 0.96), with: .color(HomesteadPalette.gold), lineWidth: max(2, 0.07 * radius))
        }
    }

    private func drawLitFox(in context: inout GraphicsContext, _ v: HomesteadViewport, pulse: Double) {
        let k = v.scale
        for target in lit where target.tool == .fox {
            guard let coord = HexCoord(id: target.id), state.board.hex(target.id) != nil else { continue }
            let path = outline(coord, v, scale: 0.9)
            context.fill(path, with: .color(HomesteadPalette.lit.opacity(0.12 + 0.14 * pulse)))
            let ring = path.strokedPath(StrokeStyle(lineWidth: max(2, 3 * k / 1.2), dash: [6, 4]))
            context.fill(ring, with: .color(HomesteadPalette.lit.opacity(0.55 + 0.45 * pulse)))
        }
    }

    private func drawHarbours(in context: inout GraphicsContext, _ v: HomesteadViewport) {
        let s = Self.unit
        let k = v.scale
        let board = state.board
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
            context.stroke(pier, with: .color(HomesteadPalette.outline.opacity(0.5)),
                           style: StrokeStyle(lineWidth: max(3, 0.13 * s * k), lineCap: .round))
            context.stroke(pier, with: .color(HomesteadPalette.pier), style: StrokeStyle(lineWidth: max(2, 0.09 * s * k), lineCap: .round))
            let label = CGPoint(x: Double(dock.x) + ux * s * 0.32, y: Double(dock.y) + uy * s * 0.32)
            let at = v.toScreen(label)
            let fontSize = max(8, s * 0.24 * k)
            let bubble = CGRect(x: Double(at.x) - fontSize * 1.6, y: Double(at.y) - fontSize * 0.8,
                                width: fontSize * 3.2, height: fontSize * 1.6)
            context.fill(Path(roundedRect: bubble.offsetBy(dx: 0, dy: fontSize * 0.12), cornerRadius: fontSize * 0.5),
                         with: .color(Color.black.opacity(0.22)))
            context.fill(Path(roundedRect: bubble, cornerRadius: fontSize * 0.5), with: .color(Color.white.opacity(0.94)))
            var text = Text("\(harbour.rate):1").font(.system(size: fontSize, weight: .bold, design: .rounded))
            if let r = harbour.resource {
                text = text + Text(" ") + Text(Image(systemName: r.symbol)).font(.system(size: fontSize * 0.9))
            }
            context.draw(text.foregroundColor(HomesteadPalette.outline), at: at)
        }
    }

    /// A road's two ends on screen, pulled in a little from the corners.
    private func roadEnds(_ edge: HomesteadEdge, _ v: HomesteadViewport, inset: Double) -> (CGPoint, CGPoint) {
        let s = Self.unit
        let (a, b) = edge.ends
        let pa = v.toScreen(HomesteadPixels.point(a, size: s))
        let pb = v.toScreen(HomesteadPixels.point(b, size: s))
        let ax = Double(pa.x), ay = Double(pa.y), bx = Double(pb.x), by = Double(pb.y)
        return (CGPoint(x: ax + (bx - ax) * inset, y: ay + (by - ay) * inset),
                CGPoint(x: bx + (ax - bx) * inset, y: by + (ay - by) * inset))
    }

    private func drawRoads(in context: inout GraphicsContext, _ v: HomesteadViewport, frame: HomesteadBoardFrame) {
        let s = Self.unit
        let k = v.scale
        for road in state.roads {
            guard let edge = HomesteadEdge(id: road.at) else { continue }
            // A new road grows from its middle out.
            var inset = 0.16
            if let p = frame.fresh, freshPieces.contains("r|\(road.at)") {
                inset = 0.5 - 0.34 * min(1, p * 2)
            }
            let (qa, qb) = roadEnds(edge, v, inset: inset)
            var line = Path()
            line.move(to: qa)
            line.addLine(to: qb)
            let width = max(3, 0.17 * s * k)
            context.stroke(line.offsetBy(dx: width * 0.25, dy: width * 0.35), with: .color(Color.black.opacity(0.28)),
                           style: StrokeStyle(lineWidth: width + 2, lineCap: .round))
            context.stroke(line, with: .color(HomesteadPalette.outline), style: StrokeStyle(lineWidth: width + 2.5, lineCap: .round))
            context.stroke(line, with: .color(HomesteadPalette.colour(state.colour(of: road.owner))),
                           style: StrokeStyle(lineWidth: width, lineCap: .round))
            context.stroke(line, with: .color(Color.white.opacity(0.28)),
                           style: StrokeStyle(lineWidth: max(1, width * 0.28), lineCap: .round))
        }
    }

    private func drawLitRoads(in context: inout GraphicsContext, _ v: HomesteadViewport, pulse: Double) {
        let s = Self.unit
        let k = v.scale
        for target in lit where target.tool == .road {
            guard let edge = HomesteadEdge(id: target.id) else { continue }
            let (qa, qb) = roadEnds(edge, v, inset: 0.1)
            var line = Path()
            line.move(to: qa)
            line.addLine(to: qb)
            let width = max(4, 0.2 * s * k)
            context.stroke(line, with: .color(Color.white.opacity(0.35 + 0.25 * pulse)),
                           style: StrokeStyle(lineWidth: width + 3, lineCap: .round))
            context.stroke(line, with: .color(HomesteadPalette.lit.opacity(0.55 + 0.45 * pulse)),
                           style: StrokeStyle(lineWidth: width, lineCap: .round,
                                              dash: [CGFloat(max(4, 0.18 * s * k)), CGFloat(max(3, 0.12 * s * k))]))
        }
    }

    private func drawBuildings(in context: inout GraphicsContext, _ v: HomesteadViewport, frame: HomesteadBoardFrame) {
        let s = Self.unit
        let k = v.scale
        for building in state.buildings {
            guard let vertex = HomesteadVertex(id: building.at) else { continue }
            let p = v.toScreen(HomesteadPixels.point(vertex, size: s))
            var size = max(8, s * 0.35 * k)
            if let f = frame.fresh, freshPieces.contains("b|\(building.at)|\(building.piece.rawValue)") {
                // Up from nothing, a little past full size, and settle.
                let grow = min(1, f * 2.2)
                size *= grow * (1 + 0.3 * sin(Double.pi * grow))
                if size < 1 { continue }
            }
            HomesteadArt.building(building.piece, colour: state.colour(of: building.owner), at: p, size: size, in: &context)
        }
    }

    /// Lit corner spots: a soft glow and a ring (a town spot rings its own cottage).
    private func drawLitCorners(in context: inout GraphicsContext, _ v: HomesteadViewport, pulse: Double) {
        let s = Self.unit
        let k = v.scale
        for target in lit where target.tool == .cottage || target.tool == .town {
            guard let vertex = HomesteadVertex(id: target.id) else { continue }
            let p = v.toScreen(HomesteadPixels.point(vertex, size: s))
            let px = Double(p.x), py = Double(p.y)
            let r = max(7, s * (target.tool == .town ? 0.5 : 0.26) * k) * (0.9 + 0.2 * pulse)
            let glow = r * 1.55
            context.fill(Path(ellipseIn: CGRect(x: px - glow, y: py - glow, width: 2 * glow, height: 2 * glow)),
                         with: .color(HomesteadPalette.lit.opacity(0.14 + 0.16 * pulse)))
            let ring = Path(ellipseIn: CGRect(x: px - r, y: py - r, width: 2 * r, height: 2 * r))
            if target.tool == .cottage {
                context.fill(ring, with: .color(Color.white.opacity(0.7)))
            }
            context.stroke(ring, with: .color(HomesteadPalette.lit.opacity(0.65 + 0.35 * pulse)), lineWidth: max(2.5, 0.09 * s * k))
        }
    }

    /// A ring in the owner's colour round each piece that has just appeared.
    private func drawFreshRings(in context: inout GraphicsContext, _ v: HomesteadViewport, frame: HomesteadBoardFrame) {
        guard let f = frame.fresh else { return }
        let s = Self.unit
        let k = v.scale
        for key in freshPieces {
            guard let piece = HomesteadMoments.spot(of: key) else { continue }
            var spot: CGPoint?
            var owner: String?
            if piece.road, let edge = HomesteadEdge(id: piece.id) {
                spot = HomesteadPixels.midpoint(edge, size: s)
                owner = state.roads.first(where: { $0.at == piece.id })?.owner
            } else if let vertex = HomesteadVertex(id: piece.id) {
                spot = HomesteadPixels.point(vertex, size: s)
                owner = state.building(at: piece.id)?.owner
            }
            guard let centre = spot else { continue }
            let p = v.toScreen(centre)
            let r = s * k * (0.25 + 0.75 * f)
            let ring = Path(ellipseIn: CGRect(x: Double(p.x) - r, y: Double(p.y) - r, width: 2 * r, height: 2 * r))
            let colour = HomesteadPalette.colour(owner.flatMap { state.colour(of: $0) })
            context.stroke(ring, with: .color(Color.white.opacity(0.8 * (1 - f))), lineWidth: max(3, 0.14 * s * k * (1 - f)) + 2)
            context.stroke(ring, with: .color(colour.opacity(1 - f)), lineWidth: max(2, 0.1 * s * k * (1 - f)))
        }
    }

    /// The fox: a fox's head on a shadow, beside the token of the hex it blocks.
    private func drawFox(in context: inout GraphicsContext, _ v: HomesteadViewport) {
        guard let fox = state.fox, let coord = HexCoord(id: fox), state.board.hex(fox) != nil else { return }
        let s = Self.unit
        let k = v.scale
        let c = v.toScreen(HomesteadPixels.centre(coord, size: s))
        let r = max(10, s * 0.34 * k)
        let at = CGPoint(x: Double(c.x) + s * 0.5 * k, y: Double(c.y) + s * 0.4 * k)
        HomesteadArt.fox(at: at, size: r, in: &context)
    }

    private func drawToken(_ token: Int, hot: Bool, pips: Int, at centre: CGPoint, k: Double, in context: inout GraphicsContext) {
        let s = Self.unit
        let r = max(8, s * 0.34 * k)
        let x = Double(centre.x)
        let y = Double(centre.y) + s * 0.12 * k
        context.fill(Path(ellipseIn: CGRect(x: x - r + r * 0.06, y: y - r + r * 0.14, width: 2 * r, height: 2 * r)),
                     with: .color(Color.black.opacity(0.28)))
        let disc = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        context.fill(disc, with: .color(HomesteadPalette.token))
        context.stroke(disc, with: .color(HomesteadPalette.outline.opacity(0.5)), lineWidth: max(0.8, r * 0.07))
        let number = Text("\(token)")
            .font(.system(size: r * (hot ? 1.05 : 0.95), weight: hot ? .heavy : .semibold, design: .rounded))
            .foregroundColor(hot ? HomesteadPalette.hot : HomesteadPalette.outline)
        context.draw(number, at: CGPoint(x: x, y: y - r * 0.12))
        // Pips under the number: chances in 36.
        guard pips > 0 else { return }
        let dot = max(1.2, r * 0.09)
        let gap = dot * 2.6
        let start = x - gap * Double(pips - 1) / 2
        var dots = Path()
        for i in 0..<pips {
            let dx = start + gap * Double(i)
            let dy = y + r * 0.58
            dots.addEllipse(in: CGRect(x: dx - dot, y: dy - dot, width: 2 * dot, height: 2 * dot))
        }
        context.fill(dots, with: .color(hot ? HomesteadPalette.hot : HomesteadPalette.outline))
    }
}

// MARK: - Pieces, drawn

/// The pieces and the fox, drawn into a GraphicsContext: shared by the board,
/// the build bar's buttons and the finish.
enum HomesteadArt {
    /// A cottage or a town on a shadow, a darker roof, the owner's mark.
    static func building(_ piece: HomesteadPiece, colour: HomesteadColour?, at p: CGPoint, size h: Double,
                         in context: inout GraphicsContext) {
        let path = HomesteadShapes.building(piece, at: p, size: h)
        context.fill(path.offsetBy(dx: h * 0.12, dy: h * 0.16), with: .color(Color.black.opacity(0.3)))
        context.fill(path, with: .color(HomesteadPalette.colour(colour)))
        context.fill(HomesteadShapes.roof(piece, at: p, size: h), with: .color(Color.black.opacity(0.24)))
        context.stroke(path, with: .color(HomesteadPalette.outline), lineWidth: max(1.2, h * 0.12))
        if let mark = colour?.mark {
            let markPath = HomesteadShapes.mark(mark, at: CGPoint(x: Double(p.x), y: Double(p.y) + h * 0.2), size: h * 0.42)
            context.fill(markPath, with: .color(Color.white.opacity(0.95)))
        }
    }

    /// A road as a short plank, corner to corner of `rect`.
    static func road(colour: HomesteadColour?, in rect: CGRect, context: inout GraphicsContext) {
        let w = Double(rect.width), h = Double(rect.height)
        var line = Path()
        line.move(to: CGPoint(x: Double(rect.minX) + w * 0.18, y: Double(rect.minY) + h * 0.78))
        line.addLine(to: CGPoint(x: Double(rect.minX) + w * 0.82, y: Double(rect.minY) + h * 0.22))
        let width = h * 0.24
        context.stroke(line, with: .color(HomesteadPalette.outline), style: StrokeStyle(lineWidth: width + 2.5, lineCap: .round))
        context.stroke(line, with: .color(HomesteadPalette.colour(colour)), style: StrokeStyle(lineWidth: width, lineCap: .round))
        context.stroke(line, with: .color(Color.white.opacity(0.3)), style: StrokeStyle(lineWidth: max(1, width * 0.28), lineCap: .round))
    }

    /// The fox's head: ears, a white muzzle, eyes and a nose, on a shadow.
    static func fox(at p: CGPoint, size r: Double, in context: inout GraphicsContext) {
        let x = Double(p.x), y = Double(p.y)
        context.fill(Path(ellipseIn: CGRect(x: x - r * 1.05, y: y + r * 0.55, width: r * 2.1, height: r * 0.6)),
                     with: .color(Color.black.opacity(0.3)))
        var head = Path()
        head.move(to: CGPoint(x: x, y: y + r * 0.85))
        head.addLine(to: CGPoint(x: x - r, y: y - r * 0.12))
        head.addLine(to: CGPoint(x: x - r * 0.78, y: y - r * 1.0))
        head.addLine(to: CGPoint(x: x - r * 0.3, y: y - r * 0.5))
        head.addLine(to: CGPoint(x: x + r * 0.3, y: y - r * 0.5))
        head.addLine(to: CGPoint(x: x + r * 0.78, y: y - r * 1.0))
        head.addLine(to: CGPoint(x: x + r, y: y - r * 0.12))
        head.closeSubpath()
        context.fill(head, with: .color(HomesteadPalette.fox))
        var ears = Path()
        ears.move(to: CGPoint(x: x - r * 0.72, y: y - r * 0.8))
        ears.addLine(to: CGPoint(x: x - r * 0.42, y: y - r * 0.5))
        ears.addLine(to: CGPoint(x: x - r * 0.78, y: y - r * 0.35))
        ears.closeSubpath()
        ears.move(to: CGPoint(x: x + r * 0.72, y: y - r * 0.8))
        ears.addLine(to: CGPoint(x: x + r * 0.42, y: y - r * 0.5))
        ears.addLine(to: CGPoint(x: x + r * 0.78, y: y - r * 0.35))
        ears.closeSubpath()
        context.fill(ears, with: .color(HomesteadPalette.outline.opacity(0.75)))
        var muzzle = Path()
        muzzle.move(to: CGPoint(x: x - r * 0.82, y: y - r * 0.02))
        muzzle.addLine(to: CGPoint(x: x, y: y + r * 0.85))
        muzzle.addLine(to: CGPoint(x: x + r * 0.82, y: y - r * 0.02))
        muzzle.addQuadCurve(to: CGPoint(x: x - r * 0.82, y: y - r * 0.02), control: CGPoint(x: x, y: y + r * 0.35))
        context.fill(muzzle, with: .color(Color(hex: 0xFFF4E6)))
        context.stroke(head, with: .color(HomesteadPalette.outline), lineWidth: max(1.2, r * 0.1))
        var eyes = Path()
        eyes.addEllipse(in: CGRect(x: x - r * 0.48, y: y - r * 0.3, width: r * 0.2, height: r * 0.24))
        eyes.addEllipse(in: CGRect(x: x + r * 0.28, y: y - r * 0.3, width: r * 0.2, height: r * 0.24))
        eyes.addEllipse(in: CGRect(x: x - r * 0.14, y: y + r * 0.52, width: r * 0.28, height: r * 0.22))
        context.fill(eyes, with: .color(HomesteadPalette.outline))
    }
}

/// The pieces' and marks' outlines, shared by the board and the strip.
enum HomesteadShapes {
    /// A cottage is a little house; a town is a wider one with a tower.
    static func building(_ piece: HomesteadPiece, at p: CGPoint, size h: Double) -> Path {
        var path = Path()
        let x = Double(p.x), y = Double(p.y)
        switch piece {
        case .town:
            let w = h * 1.5
            path.move(to: CGPoint(x: x - w / 2, y: y + h * 0.7))
            path.addLine(to: CGPoint(x: x - w / 2, y: y - h * 0.1))
            path.addLine(to: CGPoint(x: x - w * 0.1, y: y - h * 0.1))
            path.addLine(to: CGPoint(x: x - w * 0.1, y: y - h * 0.55))
            path.addLine(to: CGPoint(x: x + w * 0.2, y: y - h * 0.95))
            path.addLine(to: CGPoint(x: x + w / 2, y: y - h * 0.55))
            path.addLine(to: CGPoint(x: x + w / 2, y: y + h * 0.7))
            path.closeSubpath()
        case .cottage, .road:
            let w = h * 1.05
            path.move(to: CGPoint(x: x - w / 2, y: y + h * 0.6))
            path.addLine(to: CGPoint(x: x - w / 2, y: y - h * 0.1))
            path.addLine(to: CGPoint(x: x, y: y - h * 0.7))
            path.addLine(to: CGPoint(x: x + w / 2, y: y - h * 0.1))
            path.addLine(to: CGPoint(x: x + w / 2, y: y + h * 0.6))
            path.closeSubpath()
        }
        return path
    }

    /// The roof of a building, to shade darker than its walls.
    static func roof(_ piece: HomesteadPiece, at p: CGPoint, size h: Double) -> Path {
        var path = Path()
        let x = Double(p.x), y = Double(p.y)
        switch piece {
        case .town:
            let w = h * 1.5
            path.move(to: CGPoint(x: x - w * 0.1, y: y - h * 0.55))
            path.addLine(to: CGPoint(x: x + w * 0.2, y: y - h * 0.95))
            path.addLine(to: CGPoint(x: x + w / 2, y: y - h * 0.55))
            path.closeSubpath()
            path.addRect(CGRect(x: x - w / 2, y: y - h * 0.1, width: w * 0.4, height: h * 0.16))
        case .cottage, .road:
            let w = h * 1.05
            path.move(to: CGPoint(x: x - w / 2, y: y - h * 0.1))
            path.addLine(to: CGPoint(x: x, y: y - h * 0.7))
            path.addLine(to: CGPoint(x: x + w / 2, y: y - h * 0.1))
            path.closeSubpath()
        }
        return path
    }

    static func mark(_ mark: HomesteadMark, at p: CGPoint, size d: Double) -> Path {
        let r = d / 2
        let x = Double(p.x), y = Double(p.y)
        switch mark {
        case .circle:
            return Path(ellipseIn: CGRect(x: x - r, y: y - r, width: d, height: d))
        case .square:
            return Path(CGRect(x: x - r * 0.85, y: y - r * 0.85, width: d * 0.85, height: d * 0.85))
        case .triangle:
            var path = Path()
            path.move(to: CGPoint(x: x, y: y - r))
            path.addLine(to: CGPoint(x: x + r, y: y + r * 0.8))
            path.addLine(to: CGPoint(x: x - r, y: y + r * 0.8))
            path.closeSubpath()
            return path
        case .diamond:
            var path = Path()
            path.move(to: CGPoint(x: x, y: y - r))
            path.addLine(to: CGPoint(x: x + r, y: y))
            path.addLine(to: CGPoint(x: x, y: y + r))
            path.addLine(to: CGPoint(x: x - r, y: y))
            path.closeSubpath()
            return path
        case .cross:
            let t = r * 0.38
            var path = Path()
            path.addRect(CGRect(x: x - r, y: y - t, width: d, height: 2 * t))
            path.addRect(CGRect(x: x - t, y: y - r, width: 2 * t, height: d))
            return path
        }
    }
}

/// A player's colour with their shape mark — beside a name, in the strip. A
/// white rim keeps it clear of any ground, dark or light.
struct HomesteadSeatMark: View {
    let colour: HomesteadColour?
    var side: CGFloat = 22

    var body: some View {
        Canvas { context, size in
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let disc = Path(ellipseIn: CGRect(origin: .zero, size: size).insetBy(dx: 0.75, dy: 0.75))
            context.fill(disc, with: .color(HomesteadPalette.colour(colour)))
            context.stroke(disc, with: .color(Color.white.opacity(0.9)), lineWidth: 1.5)
            if let mark = colour?.mark {
                context.fill(HomesteadShapes.mark(mark, at: centre, size: Double(size.width) * 0.48), with: .color(.white))
            }
        }
        .frame(width: side, height: side)
        .accessibilityLabel(colour.map { "\($0.label), \($0.mark.spoken)" } ?? "No seat")
    }
}

/// A piece as it stands on the island, in a player's colour: for the build
/// bar, the hand and the finish.
struct HomesteadPieceIcon: View {
    let piece: HomesteadPiece
    let colour: HomesteadColour?
    var side: CGFloat = 28

    var body: some View {
        Canvas { context, size in
            let w = Double(size.width), h = Double(size.height)
            switch piece {
            case .road:
                HomesteadArt.road(colour: colour, in: CGRect(origin: .zero, size: size), context: &context)
            case .cottage:
                let unit = min(w, h) * 0.6
                HomesteadArt.building(.cottage, colour: colour, at: CGPoint(x: w * 0.47, y: h * 0.55), size: unit, in: &context)
            case .town:
                let unit = min(w, h) * 0.52
                HomesteadArt.building(.town, colour: colour, at: CGPoint(x: w * 0.47, y: h * 0.56), size: unit, in: &context)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// A little island of seven hexes, a cottage and a road: the lobby's picture.
struct HomesteadIslandArt: View {
    var side: CGFloat = 76

    private static let tiles: [HomesteadTile] = [.fields, .woods, .meadow, .claypit, .quarry, .fields, .woods]

    var body: some View {
        Canvas { context, size in
            let s = Double(min(size.width, size.height)) / 5.8
            let ox = Double(size.width) / 2, oy = Double(size.height) / 2
            let disc = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            context.fill(Path(ellipseIn: disc), with: .linearGradient(
                Gradient(colors: [HomesteadPalette.sea, HomesteadPalette.seaDeep]),
                startPoint: CGPoint(x: ox, y: 0), endPoint: CGPoint(x: ox, y: Double(size.height))))
            let centre = HexCoord(0, 0)
            let coords = [centre] + centre.neighbours
            for (i, coord) in coords.enumerated() {
                let corners = HomesteadPixels.outline(coord, size: s).map { CGPoint(x: Double($0.x) + ox, y: Double($0.y) + oy) }
                var path = Path()
                path.addLines(corners)
                path.closeSubpath()
                let tile = Self.tiles[i % Self.tiles.count]
                context.fill(path, with: .color(HomesteadPalette.tile(tile)))
                context.stroke(path, with: .color(HomesteadPalette.outline.opacity(0.45)), lineWidth: 1)
            }
            let corner = HomesteadPixels.point(HomesteadVertex(0, 0, .n), size: s)
            let at = CGPoint(x: Double(corner.x) + ox, y: Double(corner.y) + oy)
            HomesteadArt.building(.cottage, colour: .red, at: at, size: s * 0.55, in: &context)
            let fox = HomesteadPixels.centre(HexCoord(1, 0), size: s)
            HomesteadArt.fox(at: CGPoint(x: Double(fox.x) + ox, y: Double(fox.y) + oy), size: s * 0.36, in: &context)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

// MARK: - Dice

/// Two dice and their total. When a new roll lands they tumble and wobble
/// for ~0.8 s, then drop onto the server's faces with a little bounce and a
/// tap; a 7 shows the fox beside them. Reduce Motion: no tumble.
struct HomesteadDiceView: View {
    let dice: HomesteadDice?
    /// Bumped by the store each time `dice.at` changes.
    let serial: Int
    var side: CGFloat = 40

    /// How long the tumble lasts (8 faces × 95 ms, rounded up): the roll's
    /// toast and the board's glow wait this long so they do not give it away.
    static let tumbleTime: Double = 0.8

    @State private var shown: (Int, Int)?
    @State private var tilt: Double = 0
    @State private var landed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                HomesteadDieFace(value: shown?.0 ?? dice?.a ?? 1, side: side, faded: dice == nil)
                    .rotationEffect(.degrees(tilt))
                HomesteadDieFace(value: shown?.1 ?? dice?.b ?? 1, side: side, faded: dice == nil)
                    .rotationEffect(.degrees(-tilt * 0.8))
            }
            .scaleEffect(landed ? 1.12 : 1)
            total
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dice.map { "Dice: \($0.a) and \($0.b), \($0.total)" } ?? "Not rolled yet")
        .accessibilityIdentifier("homestead-dice")
        .task(id: serial) { await tumble() }
    }

    /// The total under the finger's eye: a 7 is the fox's number.
    @ViewBuilder
    private var total: some View {
        if let dice, shown == nil {
            let seven = dice.total == 7
            ZStack {
                Circle()
                    .fill(seven ? HomesteadPalette.fox : SR.ink)
                if seven {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: side * 0.42, weight: .bold))
                        .foregroundStyle(Color.white)
                } else {
                    Text("\(dice.total)")
                        .font(.system(size: side * 0.48, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(SR.paper)
                }
            }
            .frame(width: side * 0.9, height: side * 0.9)
            .scaleEffect(landed ? 1.18 : 1)
            .transition(.scale.combined(with: .opacity))
        }
    }

    @MainActor
    private func tumble() async {
        guard serial > 0, !reduceMotion else { return }
        for _ in 0..<8 {
            shown = (Int.random(in: 1...6), Int.random(in: 1...6))
            withAnimation(.easeOut(duration: 0.09)) { tilt = Double.random(in: -24...24) }
            try? await Task.sleep(nanoseconds: 95_000_000)
            if Task.isCancelled { break }
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
            shown = nil
            tilt = 0
            landed = true
        }
        if Task.isCancelled {
            landed = false
            return
        }
        SRHaptic.tap()
        try? await Task.sleep(nanoseconds: 240_000_000)
        withAnimation(.easeOut(duration: 0.2)) { landed = false }
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
            let corner = size.width * 0.22
            // The die's side, under its face: a little depth.
            context.fill(Path(roundedRect: rect.offsetBy(dx: 0, dy: 1.5), cornerRadius: corner),
                         with: .color(Color(hex: 0xC9B98F)))
            let face = Path(roundedRect: rect.insetBy(dx: 0, dy: 0.75).offsetBy(dx: 0, dy: -0.75), cornerRadius: corner)
            context.fill(face, with: .linearGradient(Gradient(colors: [Color(hex: 0xFFFCF2), Color(hex: 0xF4E8C8)]),
                                                     startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(face, with: .color(HomesteadPalette.outline.opacity(0.55)), lineWidth: 1.2)
            let step = size.width / 4
            let r = size.width * 0.09
            var dots = Path()
            for (col, row) in pips {
                let x = step * CGFloat(col + 1)
                let y = step * CGFloat(row + 1)
                dots.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            }
            context.fill(dots, with: .color(value == 1 ? HomesteadPalette.hot : HomesteadPalette.outline))
        }
        .frame(width: side, height: side)
        .opacity(faded ? 0.4 : 1)
    }
}
