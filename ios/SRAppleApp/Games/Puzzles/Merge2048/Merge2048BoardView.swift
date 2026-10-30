import SwiftUI

/// How long things take on the board.
enum Merge2048Motion {
    /// One slide, from swipe to landing.
    static let slide: Double = 0.12
}

/// Where things sit on a board drawn `width` points square.
struct Merge2048Metrics {
    let side: Int
    let width: CGFloat

    var gap: CGFloat { max(6, width * (side >= 5 ? 0.022 : 0.028)) }
    var cell: CGFloat { max(1, (width - gap * CGFloat(side + 1)) / CGFloat(side)) }
    var corner: CGFloat { cell * 0.17 }

    /// The top-left corner of a cell.
    func origin(row: Int, col: Int) -> CGPoint {
        CGPoint(x: gap + CGFloat(col) * (cell + gap), y: gap + CGFloat(row) * (cell + gap))
    }
}

/// The board: the tray, the empty cells, every tile at its place, and the
/// sparks over them. Tiles are keyed by their ids, so a move slides each one
/// from where it was to where it went; a tile merged away slides under the
/// one that took it and is gone a moment later.
struct Merge2048BoardView: View {
    let side: Int
    let sprites: [Merge2048Sprite]
    let sparks: [Merge2048Spark]
    let sparksLive: Bool
    let bumps: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width, geo.size.height)
            let metrics = Merge2048Metrics(side: side, width: width)
            ZStack(alignment: .topLeading) {
                tray(metrics)
                tiles(metrics)
                Merge2048SparksLayer(sparks: sparks, live: sparksLive, inset: metrics.gap / 2)
                    .frame(width: width, height: width)
            }
            .frame(width: width, height: width)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .modifier(Merge2048Shake(shakes: CGFloat(bumps)))
        .animation(reduceMotion ? nil : .linear(duration: 0.28), value: bumps)
    }

    private func tray(_ metrics: Merge2048Metrics) -> some View {
        let outer = RoundedRectangle(cornerRadius: metrics.corner + metrics.gap, style: .continuous)
        return ZStack(alignment: .topLeading) {
            outer
                .fill(LinearGradient(colors: [Merge2048Palette.tray, Merge2048Palette.trayDeep],
                                     startPoint: .top, endPoint: .bottom))
                .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 8)
            ForEach(0..<(side * side), id: \.self) { index in
                slot(index, metrics)
            }
        }
        .frame(width: metrics.width, height: metrics.width, alignment: .topLeading)
    }

    private func slot(_ index: Int, _ metrics: Merge2048Metrics) -> some View {
        let point = metrics.origin(row: index / side, col: index % side)
        return RoundedRectangle(cornerRadius: metrics.corner, style: .continuous)
            .fill(Merge2048Palette.slot)
            .frame(width: metrics.cell, height: metrics.cell)
            .offset(x: point.x, y: point.y)
    }

    private func tiles(_ metrics: Merge2048Metrics) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(sprites) { item in
                tileView(item, metrics)
            }
        }
        .frame(width: metrics.width, height: metrics.width, alignment: .topLeading)
    }

    private func tileView(_ sprite: Merge2048Sprite, _ metrics: Merge2048Metrics) -> some View {
        let point = metrics.origin(row: sprite.tile.row, col: sprite.tile.col)
        return Merge2048TileView(value: sprite.tile.value, cell: metrics.cell, corner: metrics.corner)
            .frame(width: metrics.cell, height: metrics.cell)
            .offset(x: point.x, y: point.y)
            .zIndex(sprite.leaving ? 0 : Double(1 + Merge2048Ladder.step(sprite.tile.value)))
            .transition(.opacity)
    }
}

/// One tile: it grows in when it first appears, and when its value doubles it
/// waits for the slide to land, shows the new number and pops.
struct Merge2048TileView: View {
    let value: Int
    let cell: CGFloat
    let corner: CGFloat

    @State private var shown: Int
    @State private var grown: CGFloat = 0.15
    @State private var pop: CGFloat = 1
    /// Bumped on every change, so a landing overtaken by a newer one (an
    /// undo straight after a merge) never puts back a stale number.
    @State private var epoch = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(value: Int, cell: CGFloat, corner: CGFloat) {
        self.value = value
        self.cell = cell
        self.corner = corner
        _shown = State(initialValue: value)
    }

    var body: some View {
        Merge2048TileFace(value: shown, cell: cell, corner: corner)
            .scaleEffect(grown * pop)
            .onAppear(perform: appear)
            .onChange(of: value) { _, newValue in
                land(newValue)
            }
    }

    private func appear() {
        if reduceMotion {
            grown = 1
            return
        }
        withAnimation(.spring(response: 0.26, dampingFraction: 0.62).delay(Merge2048Motion.slide * 0.8)) {
            grown = 1
        }
    }

    private func land(_ newValue: Int) {
        let mine = epoch + 1
        epoch = mine
        // Smaller means an undo: no celebration, just the old number back.
        if reduceMotion || newValue <= shown {
            shown = newValue
            return
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Merge2048Motion.slide * 0.85 * 1_000_000_000))
            guard epoch == mine else { return }
            shown = newValue
            withAnimation(.easeOut(duration: 0.07)) { pop = 1.17 }
            try? await Task.sleep(nanoseconds: 70_000_000)
            withAnimation(.spring(response: 0.24, dampingFraction: 0.5)) { pop = 1 }
        }
    }
}

/// A tile's face, still: the fill, a soft top light, the number. Also drawn
/// on its own on the win card and in the milestone ladder.
struct Merge2048TileFace: View {
    let value: Int
    let cell: CGFloat
    var corner: CGFloat? = nil

    var body: some View {
        let swatch = Merge2048Palette.swatch(value)
        let radius = corner ?? cell * 0.17
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack {
            shape.fill(swatch.fill)
            shape
                .fill(LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0)],
                                     startPoint: .top, endPoint: .center))
                .padding(cell * 0.04)
            if swatch.crowned {
                shape.strokeBorder(Color.white.opacity(0.75), lineWidth: max(1.5, cell * 0.035))
            }
            Text(verbatim: String(value))
                .font(.system(size: Merge2048Palette.fontSize(for: value, cell: cell), weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(swatch.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, cell * 0.06)
        }
        .compositingGroup()
        .shadow(color: swatch.base.opacity(Merge2048Ladder.step(value) >= 3 ? 0.45 : 0.18),
                radius: cell * 0.07, x: 0, y: cell * 0.04)
        .accessibilityHidden(true)
    }
}

/// The board's shudder when a swipe moves nothing.
struct Merge2048Shake: GeometryEffect {
    var amount: CGFloat = 7
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let dx = amount * sin(shakes * CGFloat.pi * 3)
        return ProjectionTransform(CGAffineTransform(translationX: dx, y: 0))
    }
}
